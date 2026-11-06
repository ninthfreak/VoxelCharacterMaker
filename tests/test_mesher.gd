@tool
class_name TestMesher
extends RefCounted

## Mesher and rig checks (SPEC.md section 9).
##
## The winding test matters more than it looks. Godot treats CLOCKWISE triangles
## as front-facing, which is the opposite of the usual OpenGL convention, and a
## headless test cannot see that the figure has rendered inside-out. So the
## convention is asserted directly: for every triangle, the right-hand-rule
## normal of its vertex order must point AGAINST the outward normal, because the
## vertices are clockwise seen from outside. If the figure ever appears
## inside-out, this is the one place to flip.


static func run(t: TestReport, library: AssetLibrary) -> void:
	t.group("mesher: one isolated voxel")
	var part := CharacterAssembler.Part.new()
	part.name = "test"
	var cell := Vector3i(12, 12, 12)
	part.cells[cell] = true
	part.colours[cell] = Color.WHITE
	part.tones[cell] = Shading.Tone.MID

	t.check_equal(Mesher.count_faces(part), 6, "an isolated voxel has six open faces")

	var mesh := Mesher.build_part(part, Vector3(12, 12, 12), false)
	t.check(mesh != null, "it produces a mesh")
	if mesh == null:
		return
	t.check_equal(mesh.get_surface_count(), 1, "one surface")

	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	t.check_equal(vertices.size(), 36, "six quads as twelve triangles is 36 vertices")
	t.check_equal(normals.size(), 36, "a normal per vertex")
	t.check_equal(colours.size(), 36, "a colour per vertex")

	# Every face of the cube is one voxel wide.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in vertices:
		lo = lo.min(v)
		hi = hi.max(v)
	var side := VoxelAxes.VOXEL_SIZE
	t.check((hi - lo).is_equal_approx(Vector3(side, side, side)),
		"the cube is one voxel on a side", str(hi - lo))

	# The six distinct normals are the six axis directions.
	var seen := {}
	for n in normals:
		seen[n.snappedf(0.001)] = true
	t.check_equal(seen.size(), 6, "six distinct face normals")

	t.group("mesher: winding matches Godot's clockwise front faces")
	var wrong := 0
	var degenerate := 0
	for i in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		var geometric := (b - a).cross(c - a)
		if geometric.length() < 0.000001:
			degenerate += 1
			continue
		if geometric.normalized().dot(normals[i]) > 0.0:
			wrong += 1
	t.check_equal(degenerate, 0, "no degenerate triangles")
	t.check_equal(wrong, 0,
		"every triangle is clockwise seen from outside, which Godot draws front-facing")

	t.group("mesher: culling is per part, not across the figure")
	# Two voxels of the SAME part that touch hide the shared faces...
	var pair := CharacterAssembler.Part.new()
	pair.name = "pair"
	for c2 in [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]:
		pair.cells[c2] = true
		pair.colours[c2] = Color.WHITE
		pair.tones[c2] = Shading.Tone.MID
	t.check_equal(Mesher.count_faces(pair), 10,
		"two touching voxels in one part show ten faces, not twelve")

	# ...but a neighbouring PART does not cull anything, or a limb would open a
	# hole the moment it rotated away.
	var request := CharacterAssembler.Request.make(library, "male_average", "round", "neutral")
	request.wardrobe = Wardrobe.create_default()
	request.worn = []
	var assembled := CharacterAssembler.assemble(request)
	var chest := assembled.part("chest")
	var pelvis := assembled.part("pelvis")
	var chest_bottom := 0
	for cell3 in chest.cells.keys():
		var c3: Vector3i = cell3
		if not chest.cells.has(c3 + VoxelAxes.DOWN):
			chest_bottom += 1
	t.check(chest_bottom > 0,
		"the chest still meshes its underside even though the pelvis is there",
		"%d faces" % chest_bottom)
	t.check(TestReport.face_adjacent(chest.cells, pelvis.cells),
		"the chest and pelvis do in fact touch")

	t.group("mesher: shading is computed across the whole figure")
	# A cell on the chest's underside is enclosed by the pelvis below it, so the
	# tone rule must have seen the pelvis: it cannot be "bottom exposed" = dark.
	var solid := assembled.all_cells()
	var mismatches := 0
	for name in assembled.order:
		var p := assembled.part(String(name))
		for cell4 in p.cells.keys():
			var want := Shading.tone_for(cell4, solid)
			if int(p.tones.get(cell4, -1)) != want:
				mismatches += 1
	t.check_equal(mismatches, 0,
		"every part's tones match the rule applied to the whole figure")

	t.group("rig: hierarchy and poses")
	var rig := CharacterRig.new()
	rig.build(assembled)
	t.check_equal(rig.joints.size(), assembled.order.size(), "a joint per part")
	for name2 in assembled.order:
		var p2 := assembled.part(String(name2))
		var joint: Node3D = rig.joints.get(name2)
		t.check(joint != null, "joint %s exists" % name2)
		if joint == null or p2.parent.is_empty():
			continue
		var parent_joint: Node3D = rig.joints.get(p2.parent)
		t.check(joint.get_parent() == parent_joint,
			"%s hangs under %s" % [name2, p2.parent])

	# The real invariant: walking the joint chain from the root must land on
	# each part's pivot. Checking only the root once let every child joint sit
	# 24 times too far out, because the offsets were in voxels, not metres.
	for name4 in assembled.order:
		var part4 := assembled.part(String(name4))
		var accumulated := Vector3.ZERO
		var walk := String(name4)
		while not walk.is_empty():
			accumulated += (rig.joints[walk] as Node3D).position
			walk = assembled.part(walk).parent
		t.check(accumulated.is_equal_approx(VoxelAxes.point_to_godot(part4.pivot)),
			"joint %s chains to its pivot" % name4,
			"got %s, pivot maps to %s" % [
				accumulated, VoxelAxes.point_to_godot(part4.pivot)])

	# The pelvis is the root, at the hips' bottom row, and the figure stands on y = 0.
	var pelvis_joint: Node3D = rig.joints["pelvis"]
	var hip_height := float(BodyLayout.PELVIS_PIVOT_Z) / VoxelAxes.VOXELS_PER_METRE
	t.check(pelvis_joint.position.is_equal_approx(Vector3(0, hip_height, 0)),
		"the pelvis joint is at the bottom of the hips above the rig origin",
		str(pelvis_joint.position))
	var bounds := rig.figure_aabb()
	t.check_near(bounds.position.y, 0.0, "the figure's feet are at y = 0", 0.001)
	t.check_near(bounds.size.y, 1.75, "the figure is 1.75 m tall", 0.01)

	for pose in Poses.names():
		rig.apply_pose(pose)
		var moved := false
		for name3 in rig.joints.keys():
			if (rig.joints[name3] as Node3D).rotation_degrees.length() > 0.001:
				moved = true
				break
		if pose == Poses.REST:
			t.check(not moved, "the rest pose rotates nothing")
		else:
			t.check(moved, "pose %s rotates something" % pose)
	rig.free()

	t.group("rig: cloth panels follow their driver")
	var wardrobe := Wardrobe.create_default()
	var skirt := GarmentItem.create("panel_skirt", "Skirt", "bottom")
	skirt.add_special("skirt")
	skirt.roles = ["cloth", "hem"]
	skirt.colourways = {"default": {"cloth": "moss", "hem": "ochre"}}
	wardrobe.add_item(skirt)

	var skirt_request := CharacterAssembler.Request.make(
		library, "female_average", "round", "neutral")
	skirt_request.wardrobe = wardrobe
	skirt_request.worn = [{"item": "panel_skirt", "colourway": "default"}]
	var with_skirt := CharacterAssembler.assemble(skirt_request)

	var skirt_rig := CharacterRig.new()
	skirt_rig.build(with_skirt)
	skirt_rig.apply_pose(Poses.MID_STRIDE)
	var stride := Poses.get_pose(Poses.MID_STRIDE)
	var front: Node3D = skirt_rig.joints.get(CharacterAssembler.panel_name("panel_skirt", 0, SkirtGenerator.PANEL_FRONT))
	var back: Node3D = skirt_rig.joints.get(CharacterAssembler.panel_name("panel_skirt", 0, SkirtGenerator.PANEL_BACK))
	t.check(front != null and back != null, "the front and back panels are in the rig")
	if front != null and back != null:
		var forward_thigh := maxf(
			(stride.get("thigh_L", Vector3.ZERO) as Vector3).x,
			(stride.get("thigh_R", Vector3.ZERO) as Vector3).x)
		t.check_near(front.rotation_degrees.x, forward_thigh * Poses.PANEL_FOLLOW,
			"the front panel follows the more forward thigh", 0.01)
		t.check(back.rotation_degrees.x < front.rotation_degrees.x,
			"the back panel trails the front one",
			"%f vs %f" % [back.rotation_degrees.x, front.rotation_degrees.x])
	skirt_rig.free()
