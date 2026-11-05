@tool
class_name TestFaces
extends RefCounted

## SPEC.md section 12: "Every expression fits every head (no eye cell falls off
## the face plane)." Plus the section 5 rules that make that possible: bulk 0,
## the shared eye box, and the face drawing under hair and hats.


static func run(t: TestReport, library: AssetLibrary) -> void:
	t.group("faces: every expression fits every head")
	for name in library.expression_names():
		var face := library.face(name)
		for shape in library.head_shapes():
			var head := library.head(shape)
			var missing := face.missing_on_head(head)
			t.check(missing.is_empty(), "%s fits the %s head" % [name, shape],
				"%d cells off the face plane, e.g. %s" % [
					missing.size(), missing[0] if not missing.is_empty() else ""])

	t.group("faces: overlay rules")
	for name2 in library.expression_names():
		var face2 := library.face(name2)
		t.check_equal(face2.bulk, 0, "%s is skin-tight (bulk 0)" % name2)
		t.check_equal(face2.plane_y, VoxelAxes.FACE_PLANE_Y,
			"%s sits on the face plane" % name2)
		var absolute := face2.to_absolute()
		var off_plane := 0
		for cell in absolute.keys():
			if (cell as Vector3i).y != VoxelAxes.FACE_PLANE_Y:
				off_plane += 1
		t.check_equal(off_plane, 0, "%s has every cell on y = 6" % name2)

		# The eye box is 4 wide x 5 tall per eye, so no expression may exceed it.
		var xs_low := 99
		var xs_high := -99
		var zs_low := 99
		var zs_high := -99
		for cell2 in absolute.keys():
			var c: Vector3i = cell2
			xs_low = mini(xs_low, c.x)
			xs_high = maxi(xs_high, c.x)
			zs_low = mini(zs_low, c.z)
			zs_high = maxi(zs_high, c.z)
		t.check(xs_low >= 7 and xs_high <= 16,
			"%s stays inside the eye box in x" % name2, "x %d..%d" % [xs_low, xs_high])
		t.check(zs_low >= 30 and zs_high <= 34,
			"%s stays inside the eye box in z" % name2, "z %d..%d" % [zs_low, zs_high])

	t.group("faces: symmetry")
	var symmetric := ["neutral", "blink", "happy", "angry", "sad", "surprised", "bored"]
	for name3 in symmetric:
		var face3 := library.face(name3)
		if face3 == null:
			continue
		t.check(face3.is_symmetric(), "%s is stored the same for both eyes" % name3)
	for name4 in ["wink", "look_left", "look_right"]:
		var face4 := library.face(name4)
		if face4 == null:
			continue
		t.check(not face4.is_symmetric(),
			"%s stores both eyes because it is asymmetric" % name4)

	# look_left and look_right must be each other's mirror.
	var left := library.face("look_left")
	var right := library.face("look_right")
	if left != null and right != null:
		var mirrored := {}
		for cell in left.to_absolute().keys():
			mirrored[VoxelAxes.mirror_voxel(cell)] = left.to_absolute()[cell]
		t.check(mirrored == right.to_absolute(),
			"look_left mirrors onto look_right")

	t.group("faces: the overlay recolours and never adds volume")
	var request := CharacterAssembler.Request.make(
		library, "female_average", "oval", "neutral")
	request.wardrobe = Wardrobe.create_default()
	request.worn = CharacterAssembler.worn_from_outfit(request.wardrobe, "everyday")
	var dressed := CharacterAssembler.assemble(request)

	var bare := CharacterAssembler.Request.make(
		library, "female_average", "oval", "neutral")
	bare.wardrobe = request.wardrobe
	bare.worn = []
	var head_part := CharacterAssembler.assemble(bare).part(BodyDef.HEAD_PART)
	t.check_equal(head_part.count(), library.head("oval").count(),
		"the face adds no voxels to the head")

	var eye_cells := 0
	for cell in head_part.cells.keys():
		if int(head_part.sources.get(cell, 0)) == CharacterAssembler.Source.FACE:
			eye_cells += 1
	t.check(eye_cells > 0, "the neutral face actually paints eye cells",
		"%d cells" % eye_cells)
	t.check(dressed.warnings.is_empty(), "assembling a dressed figure warns about nothing",
		", ".join(dressed.warnings))

	# A hat must win over the face where they overlap: the face draws under it.
	var hat := GarmentItem.create("test_hat", "Test hat", "hat")
	hat.roles = ["cloth"]
	hat.colourways = {"default": {"cloth": "ink"}}
	# Bulk 0 on the lower head front recolours the very cells the eyes use.
	hat.set_region("lower_head.L.F", "cloth", 0)
	hat.set_region("mid_head.L.F", "cloth", 0)
	request.wardrobe.add_item(hat)
	request.worn = [{"item": "test_hat", "colourway": "default"}]
	var with_hat := CharacterAssembler.assemble(request)
	var head2 := with_hat.part(BodyDef.HEAD_PART)
	var face_left := 0
	for cell2 in head2.cells.keys():
		var c2: Vector3i = cell2
		if int(head2.sources.get(c2, 0)) != CharacterAssembler.Source.FACE:
			continue
		if VoxelAxes.is_left(c2):
			face_left += 1
	t.check_equal(face_left, 0,
		"a bulk-0 hat over the left side of the face covers those eye cells")
