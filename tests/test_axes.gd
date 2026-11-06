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
## these expectations flip, and VoxelAxes is the only other place to change.

const CAMERA_HEIGHT := 0.875  ## mid-figure: 1.75 m / 2


static func run(t: TestReport, library: AssetLibrary) -> void:
	t.group("axes: the SPEC section 2 coordinate lock")

	# -- the mapping itself --------------------------------------------------
	t.check(VoxelAxes.point_to_godot(Vector3(12, 12, 0)).is_equal_approx(Vector3.ZERO),
		"the mirror line at the depth centre on the floor is the origin")
	t.check_near(VoxelAxes.point_to_godot(Vector3(12, 12, 42)).y, 1.75,
		"42 voxels tall is 1.75 m")
	t.check_near(VoxelAxes.VOXELS_PER_METRE, 24.0, "24 voxels per metre")

	# A proper rotation, not a mirroring: the determinant must be positive, or
	# every piece of geometry would come out inside-out.
	var ex := VoxelAxes.direction_to_godot(Vector3(1, 0, 0))
	var ey := VoxelAxes.direction_to_godot(Vector3(0, 1, 0))
	var ez := VoxelAxes.direction_to_godot(Vector3(0, 0, 1))
	t.check(ex.cross(ey).dot(ez) > 0.0,
		"the asset-to-Godot mapping is a proper rotation (handedness preserved)",
		"triple product %f" % ex.cross(ey).dot(ez))

	# -- axis directions ----------------------------------------------------
	t.check(VoxelAxes.direction_to_godot(Vector3(0, 0, 1)).normalized()
			.is_equal_approx(Vector3.UP),
		"asset +z (up) becomes Godot +Y")
	t.check(VoxelAxes.direction_to_godot(Vector3(1, 0, 0)).normalized()
			.is_equal_approx(Vector3.LEFT),
		"asset +x (the character's left) becomes Godot -X")
	t.check(VoxelAxes.direction_to_godot(Vector3(0, -1, 0)).normalized()
			.is_equal_approx(Vector3.FORWARD),
		"asset -y (the way the figure faces) becomes Godot -Z")

	# A displacement must carry the voxel scale, not just the axis swap:
	# direction_to_godot is the linear part of point_to_godot and has to agree
	# with it. Testing only unit axes hid a missing 1/24 here once.
	t.check(VoxelAxes.direction_to_godot(Vector3(0, 0, 24)).is_equal_approx(Vector3.UP),
		"24 voxels up is one metre up",
		str(VoxelAxes.direction_to_godot(Vector3(0, 0, 24))))
	for pair in [[Vector3(5, -3, 11), Vector3(12, 12, 12)],
			[Vector3(21, 12, 26), Vector3(12, 12, 16)]]:
		var from: Vector3 = pair[0]
		var to: Vector3 = pair[1]
		t.check(VoxelAxes.direction_to_godot(from - to).is_equal_approx(
				VoxelAxes.point_to_godot(from) - VoxelAxes.point_to_godot(to)),
			"a displacement agrees with the difference of the two points")

	# godot_to_point undoes point_to_godot exactly. Picking depends on it, and
	# it lives beside the forward mapping so a convention change moves both.
	for sample in [Vector3(0, 0, 0), Vector3(12, 12, 12), Vector3(21.5, 6, 33),
			Vector3(3, 17.25, 41)]:
		var p: Vector3 = sample
		t.check(VoxelAxes.godot_to_point(VoxelAxes.point_to_godot(p)).is_equal_approx(p),
			"godot_to_point inverts point_to_godot at %s" % p)

	# -- the two halves of the lock, with a real camera ---------------------
	var body := library.body("male_average")
	var head := library.head("round")
	if body == null or head == null:
		t.check(false, "assets needed for the camera test are present")
		return

	var target := Vector3(0, CAMERA_HEIGHT, 0)
	var camera_position := Vector3(0, CAMERA_HEIGHT, -3.0)
	var camera := Transform3D(Basis(), camera_position).looking_at(target, Vector3.UP)
	var to_camera := camera.affine_inverse()

	# 1. a camera on the -Z side must see the face.
	# The face plane is y = 6, the back of the head is the largest y on the head.
	var back_y := 0
	for cell in head.cells.keys():
		back_y = maxi(back_y, (cell as Vector3i).y)
	var face_point := VoxelAxes.voxel_centre_to_godot(Vector3i(12, VoxelAxes.FACE_PLANE_Y, 32))
	var back_point := VoxelAxes.voxel_centre_to_godot(Vector3i(12, back_y, 32))
	var face_local := to_camera * face_point
	var back_local := to_camera * back_point

	# Looking along -Z, "nearer the camera" means a local z closer to zero.
	t.check(face_local.z > back_local.z,
		"a camera on -Z sees the face, not the back of the head",
		"face local z %f, back of head %f" % [face_local.z, back_local.z])
	t.check(face_local.z < 0.0, "the figure is in front of the camera",
		"face local z %f" % face_local.z)

	# 2. the character's left hand must be on the camera's right.
	var left_hand := body.part("forearm_L")
	var right_hand := body.part("forearm_R")
	t.check(left_hand != null and right_hand != null, "both forearms exist")
	if left_hand == null or right_hand == null:
		return

	var left_centre := _centre_of(left_hand.cells)
	var right_centre := _centre_of(right_hand.cells)
	t.check(left_centre.x > VoxelAxes.MIRROR_X,
		"the character's left forearm is on asset +x",
		"centre x %f" % left_centre.x)

	var left_local := to_camera * VoxelAxes.point_to_godot(left_centre)
	var right_local := to_camera * VoxelAxes.point_to_godot(right_centre)
	t.check(left_local.x > 0.0,
		"the character's left hand is on the camera's right (local +X)",
		"left hand local x %f" % left_local.x)
	t.check(right_local.x < 0.0,
		"the character's right hand is on the camera's left",
		"right hand local x %f" % right_local.x)

	# -- pivots sit where the parity rule says ------------------------------
	t.group("axes: pivot parity")
	t.check(VoxelAxes.point_to_godot(Vector3(12, 12, 12)).is_equal_approx(Vector3(0, 0.5, 0)),
		"pivot (12, 12, 12) lands on a voxel boundary half a metre up")
	for id in library.body_ids():
		var b := library.body(id)
		var pelvis := b.part("pelvis")
		t.check(pelvis.pivot.is_equal_approx(Vector3(12, 12, 12)),
			"%s pelvis pivot is (12, 12, 12)" % id, str(pelvis.pivot))
		for part_name in ["upper_arm", "forearm", "thigh", "shin"]:
			var left := b.part(part_name + "_L")
			var right := b.part(part_name + "_R")
			t.check_near(right.pivot.x, VoxelAxes.MIRROR_SUM - left.pivot.x,
				"%s %s pivots mirror" % [id, part_name])

	# The feet stand on z = 0 on every body.
	for id2 in library.body_ids():
		var b2 := library.body(id2)
		var lowest := 999
		for name in b2.part_names():
			for cell in b2.part(name).cells.keys():
				lowest = mini(lowest, (cell as Vector3i).z)
		t.check_equal(lowest, 0, "%s stands on z = 0" % id2)


static func _centre_of(cells: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	for cell in cells.keys():
		var c: Vector3i = cell
		sum += Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5)
	if cells.is_empty():
		return sum
	return sum / float(cells.size())
