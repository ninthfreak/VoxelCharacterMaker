@tool
class_name TestFaces
extends RefCounted

## SPEC.md section 12: the eyes fit every head (no eye cell falls off the face
## plane). Plus the section 5 rules that make that possible: bulk 0, the shared
## eye box, and the face drawing under hair and hats. The one shipped face is the
## open eye; every other look is lids and brow (EyeLids, tested in features).


static func run(t: TestReport, library: AssetLibrary) -> void:
	var face := library.open_face()
	t.group("faces: the open eye fits every head")
	t.check(face != null, "the open eye loads")
	if face == null:
		return
	for shape in library.head_shapes():
		var missing := face.missing_on_head(library.head(shape))
		t.check(missing.is_empty(), "the open eye fits the %s head" % shape,
			"%d cells off the face plane, e.g. %s" % [
				missing.size(), missing[0] if not missing.is_empty() else ""])

	t.group("faces: overlay rules")
	t.check_equal(face.bulk, 0, "the eye is skin-tight (bulk 0)")
	t.check_equal(face.plane_y, VoxelAxes.FACE_PLANE_Y, "it sits on the face plane")
	var absolute := face.to_absolute()
	var off_plane := 0
	var xs := Vector2i(99, -99)
	var zs := Vector2i(99, -99)
	for cell in absolute.keys():
		var c: Vector3i = cell
		if c.y != VoxelAxes.FACE_PLANE_Y:
			off_plane += 1
		xs = Vector2i(mini(xs.x, c.x), maxi(xs.y, c.x))
		zs = Vector2i(mini(zs.x, c.z), maxi(zs.y, c.z))
	t.check_equal(off_plane, 0, "every cell is on the face plane")
	t.check(xs.x >= BodyLayout.EYE_X0 and xs.y <= VoxelAxes.MIRROR_X_MAX - BodyLayout.EYE_X0,
		"it stays inside the eye box in x", "x %d..%d" % [xs.x, xs.y])
	t.check(zs.x >= BodyLayout.EYE_Z0 and zs.y <= BodyLayout.EYE_Z1,
		"it stays inside the eye box in z", "z %d..%d" % [zs.x, zs.y])
	t.check(face.is_symmetric(), "it is stored the same for both eyes")

	t.group("faces: the overlay recolours and never adds volume")
	var request := CharacterAssembler.Request.make(
		library, "female_average", "oval")
	request.wardrobe = Wardrobe.create_default()
	request.worn = CharacterAssembler.worn_from_outfit(request.wardrobe, "everyday")
	var dressed := CharacterAssembler.assemble(request)

	var bare := CharacterAssembler.Request.make(
		library, "female_average", "oval")
	bare.wardrobe = request.wardrobe
	bare.worn = []
	var head_part := CharacterAssembler.assemble(bare).part(BodyDef.HEAD_PART)
	t.check_equal(head_part.count(), library.head("oval").count(),
		"the face adds no voxels to the head")

	var eye_cells := 0
	for cell in head_part.cells.keys():
		if int(head_part.sources.get(cell, 0)) == CharacterAssembler.Source.FACE:
			eye_cells += 1
	t.check(eye_cells > 0, "the eyes actually paint cells",
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
