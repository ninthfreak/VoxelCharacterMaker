@tool
class_name TestAxes
extends RefCounted

## The coordinate lock SPEC.md section 2 asks for, by name:
##
##   "Decide in phase 1 and lock it with a test (a camera on the -Z side must
##    see the face; the character's left hand must be on the camera's right)."
##
## Both halves are checked below against Godot's own camera convention -- a
## Camera3D looks along its local -Z and its local +X is the viewer's right --
## using Transform3D.looking_at, so the test fails if that convention ever
## changes rather than if this file's arithmetic does.
##
## If the project ever adopts the glTF/MODEL_FRONT convention (models face +Z),
## these expectations flip, and FigureAxes is the only other place to change.

const CAMERA_HEIGHT := 0.875  ## mid-figure: 1.75 m / 2


static func run(t: TestReport, library: LowpolyLibrary) -> void:
	t.group("axes: the SPEC section 2 coordinate lock")

	# -- the mapping itself --------------------------------------------------
	t.check(FigureAxes.point_to_godot(Vector3(12, 12, 0)).is_equal_approx(Vector3.ZERO),
		"the mirror plane at the depth centre on the floor is the origin")
	t.check_near(FigureAxes.point_to_godot(Vector3(12, 12, 42)).y, 1.75, "42 units tall is 1.75 m")
	t.check_near(FigureAxes.UNITS_PER_METRE, 24.0, "24 units to the metre")

	# A proper rotation, not a mirroring: the determinant must be positive, or every piece of geometry would come
	# out inside-out.
	var ex := FigureAxes.direction_to_godot(Vector3(1, 0, 0))
	var ey := FigureAxes.direction_to_godot(Vector3(0, 1, 0))
	var ez := FigureAxes.direction_to_godot(Vector3(0, 0, 1))
	t.check(ex.cross(ey).dot(ez) > 0.0, "the asset-to-Godot mapping is a proper rotation (handedness preserved)",
		"triple product %f" % ex.cross(ey).dot(ez))

	# -- axis directions ----------------------------------------------------
	t.check(FigureAxes.direction_to_godot(Vector3(0, 0, 1)).normalized().is_equal_approx(Vector3.UP),
		"asset +z (up) becomes Godot +Y")
	t.check(FigureAxes.direction_to_godot(Vector3(1, 0, 0)).normalized().is_equal_approx(Vector3.LEFT),
		"asset +x (the character's left) becomes Godot -X")
	t.check(FigureAxes.direction_to_godot(Vector3(0, -1, 0)).normalized().is_equal_approx(Vector3.FORWARD),
		"asset -y (the way the figure faces) becomes Godot -Z")

	# A displacement must carry the scale, not just the axis swap: direction_to_godot is the linear part of
	# point_to_godot and has to agree with it. Testing only unit axes hid a missing 1/24 here once.
	t.check(FigureAxes.direction_to_godot(Vector3(0, 0, 24)).is_equal_approx(Vector3.UP), "24 units up is one metre up",
		str(FigureAxes.direction_to_godot(Vector3(0, 0, 24))))
	for pair in [[Vector3(5, -3, 11), Vector3(12, 12, 12)], [Vector3(21, 12, 26), Vector3(12, 12, 16)]]:
		var from: Vector3 = pair[0]
		var to: Vector3 = pair[1]
		t.check(FigureAxes.direction_to_godot(from - to).is_equal_approx(
				FigureAxes.point_to_godot(from) - FigureAxes.point_to_godot(to)),
			"a displacement agrees with the difference of the two points")

	# godot_to_point undoes point_to_godot exactly. Picking depends on it, and it lives beside the forward mapping so
	# a convention change moves both.
	for sample in [Vector3(0, 0, 0), Vector3(12, 12, 12), Vector3(21.5, 6, 33), Vector3(3, 17.25, 41)]:
		var p: Vector3 = sample
		t.check(FigureAxes.godot_to_point(FigureAxes.point_to_godot(p)).is_equal_approx(p),
			"godot_to_point inverts point_to_godot at %s" % p)

	# -- the two halves of the lock, with a real camera and a real figure --
	var body := library.body("male_average")
	var head := library.head("round")
	if not t.check(body != null and head != null, "the figure for the camera test is in the library"):
		return
	var target := Vector3(0, CAMERA_HEIGHT, 0)
	var camera := Transform3D(Basis(), Vector3(0, CAMERA_HEIGHT, -3.0)).looking_at(target, Vector3.UP)
	var to_camera := camera.affine_inverse()

	# 1. a camera on the -Z side must see the face: the front of the head (its smallest y) is nearer than its back.
	var front := Vector3(0, INF, 0)
	var back := Vector3(0, -INF, 0)
	for p in head.points:
		if p.y < front.y:
			front = p
		if p.y > back.y:
			back = p
	var face_local := to_camera * FigureAxes.point_to_godot(front + Vector3(0, 0, body.head_raise))
	var back_local := to_camera * FigureAxes.point_to_godot(back + Vector3(0, 0, body.head_raise))
	# Looking along -Z, "nearer the camera" means a local z closer to zero.
	t.check(face_local.z > back_local.z, "a camera on -Z sees the face, not the back of the head",
		"face local z %f, back of head %f" % [face_local.z, back_local.z])
	t.check(face_local.z < 0.0, "the figure is in front of the camera", "face local z %f" % face_local.z)

	# 2. the character's left hand must be on the camera's right.
	var left_centre := _centre(body, "forearm_L")
	var right_centre := _centre(body, "forearm_R")
	t.check(left_centre.x > FigureAxes.MIRROR_X, "the character's left forearm is on asset +x",
		"centre x %f" % left_centre.x)
	var left_local := to_camera * FigureAxes.point_to_godot(left_centre)
	var right_local := to_camera * FigureAxes.point_to_godot(right_centre)
	t.check(left_local.x > 0.0, "the character's left hand is on the camera's right (local +X)",
		"left hand local x %f" % left_local.x)
	t.check(right_local.x < 0.0, "the character's right hand is on the camera's left",
		"right hand local x %f" % right_local.x)

	# -- pivots and the floor ----------------------------------------------
	t.group("axes: pivots mirror, and the feet stand on the floor")
	for id in library.body_ids():
		var b := library.body(id)
		var pelvis: Vector3 = b.parts["pelvis"]["pivot"]
		t.check(is_equal_approx(pelvis.x, 12.0) and is_equal_approx(pelvis.y, 12.0),
			"%s: the pelvis pivot is on the mirror plane at the depth centre" % id, str(pelvis))
		for part_name in ["upper_arm", "forearm", "thigh", "shin"]:
			var left: Vector3 = b.parts[part_name + "_L"]["pivot"]
			var right: Vector3 = b.parts[part_name + "_R"]["pivot"]
			t.check_near(right.x, 2.0 * FigureAxes.MIRROR_X - left.x, "%s: the %s pivots mirror" % [id, part_name], 0.001)
		var lowest := INF
		for p in b.points:
			lowest = minf(lowest, p.z)
		t.check_near(lowest, 0.0, "%s stands on z = 0" % id, 0.001)


## The middle of the corners that follow a part alone.
static func _centre(body: LowpolyLibrary.Body, part: String) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for k in body.points.size():
		var w: Dictionary = body.shares[k]
		if float(w.get(part, 0.0)) > 0.999:
			sum += body.points[k]
			n += 1
	return sum / float(maxi(n, 1))
