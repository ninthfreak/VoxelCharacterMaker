@tool
class_name TestBodyEdit
extends RefCounted

## The body editor's model (SPEC.md section 8, "Body editing").
##
## The three rules the spec states -- parts as layers, one owner per cell,
## mandatory mirror pairs -- are invariants rather than UI, so they are tested
## here on the model rather than left to the panel to honour.
##
## The strongest check in this file is the pivot one: every pivot measured from
## a shipped body's own geometry must come out exactly equal to the pivot
## recorded in that body's file. That is what proves the editor measures joints
## the way tools/build_bodies.py does, so an edited body gets the pivots it
## would have had if it had been generated.


static func run(t: TestReport, library: AssetLibrary) -> void:
	_topology(t)
	_pivots(t, library)
	_one_owner(t, library)
	_mirror(t, library)
	_validation(t, library)
	_round_trip(t, library)
	_heads(t, library)
	_overrides(t, library)


# ------------------------------------------------------------- topology ----

static func _topology(t: TestReport) -> void:
	t.group("topology: the shared checks")

	var single := {Vector3i(0, 0, 0): true}
	t.check_equal(VoxelTopology.components(single), 1, "one cell is one piece")

	var apart := {Vector3i(0, 0, 0): true, Vector3i(5, 0, 0): true}
	t.check_equal(VoxelTopology.components(apart), 2, "two separated cells are two pieces")

	var joined := {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true}
	t.check_equal(VoxelTopology.components(joined), 1, "two touching cells are one piece")
	t.check(VoxelTopology.touches(single, joined), "sets that share a cell touch")

	# A diagonal pair with both bridging cells empty is an edge-only contact.
	var diagonal := {Vector3i(0, 0, 0): true, Vector3i(1, 1, 0): true}
	t.check_equal(VoxelTopology.edge_only_contacts(diagonal).size(), 1,
		"a bare diagonal pair is an edge-only contact")
	var bridged := diagonal.duplicate()
	bridged[Vector3i(1, 0, 0)] = true
	t.check_equal(VoxelTopology.edge_only_contacts(bridged).size(), 0,
		"bridging the diagonal removes the edge-only contact")
	t.check_equal(VoxelTopology.components(bridged), 1, "and makes it one piece")

	# Mirror symmetry is about the plane between x11 and x12.
	var pair := {Vector3i(10, 5, 5): true, Vector3i(13, 5, 5): true}
	t.check(VoxelTopology.is_mirror_symmetric(pair), "x10 and x13 are mirror partners")
	var lone := {Vector3i(10, 5, 5): true}
	t.check(not VoxelTopology.is_mirror_symmetric(lone), "a lone cell is not symmetric")
	t.check_equal(VoxelTopology.asymmetric_cells(lone).size(), 1,
		"and it is reported as the cell without a partner")

	# mid_x is measured in corner space, so an even run lands on a boundary.
	var run_even := {}
	for x in range(13, 17):
		run_even[Vector3i(x, 12, 10)] = true
	t.check_near(VoxelTopology.mid_x(run_even, 10, 10), 15.0,
		"a 4-wide run from x13 has mid-x 15, on a voxel boundary")
	var run_odd := {}
	for x in range(13, 16):
		run_odd[Vector3i(x, 12, 10)] = true
	t.check_near(VoxelTopology.mid_x(run_odd, 10, 10), 14.5,
		"a 3-wide run has mid-x on a voxel centre")


# --------------------------------------------------------------- pivots ----

static func _pivots(t: TestReport, library: AssetLibrary) -> void:
	t.group("body edit: pivots are measured, not stored")
	for id in library.body_ids():
		var body := library.body(id)
		var edit := BodyEdit.from_body(body)
		var measured := edit.pivots()
		for name in body.part_names():
			var want: Vector3 = body.part(name).pivot
			var got: Vector3 = measured.get(name, Vector3.ZERO)
			t.check(got.is_equal_approx(want),
				"%s %s pivot measured from geometry" % [id, name],
				"measured %s, file says %s" % [got, want])

		# The parity rule: an even-width part pivots on a voxel boundary.
		# SPEC 3.2 accepts exceptions for 3-wide arms and 5-wide legs.
		var off_boundary: Array[String] = []
		for name2 in BodyEdit.PAINTABLE:
			if not edit.pivot_on_boundary(name2):
				off_boundary.append(name2)
		t.note("%s: pivots on a voxel centre: %s" % [
			id, ", ".join(off_boundary) if not off_boundary.is_empty() else "none"])

	# Moving geometry moves the pivot with it.
	var edit2 := BodyEdit.from_body(library.body("male_average"))
	var before := edit2.pivot_of("upper_arm_L").x
	var moved: Array = []
	for cell in edit2.part_cells("upper_arm_L").keys():
		var c: Vector3i = cell
		if c.z >= 19 and c.z <= 21:
			moved.append(Vector3i(c.x + 1, c.y, c.z))
	edit2.paint_many(moved, "upper_arm_L")
	t.check(edit2.pivot_of("upper_arm_L").x > before,
		"widening the arm moves its measured pivot outward",
		"%f -> %f" % [before, edit2.pivot_of("upper_arm_L").x])
	t.check_near(edit2.pivot_of("upper_arm_R").x,
		VoxelAxes.MIRROR_SUM - edit2.pivot_of("upper_arm_L").x,
		"and the right arm's pivot stays its mirror")


# ------------------------------------------------------- one owner / layers --

static func _one_owner(t: TestReport, library: AssetLibrary) -> void:
	t.group("body edit: one owner per cell")
	var edit := BodyEdit.from_body(library.body("male_average"))

	# Every cell is owned by exactly one part, as loaded.
	var seen := {}
	var doubled := 0
	for name in BodyEdit.PAINTABLE:
		for cell in edit.part_cells(name).keys():
			if seen.has(cell):
				doubled += 1
			seen[cell] = name
	t.check_equal(doubled, 0, "no cell starts out in two parts")
	t.check_equal(seen.size(), edit.total_voxels(), "the owner index matches the parts")

	# Painting a cell into another part takes it away from the first.
	var target := Vector3i(13, 12, 20)
	edit.paint(target, "chest")
	t.check_equal(edit.owner_at(target), "chest", "the cell is the chest's")
	edit.paint(target, "upper_arm_L")
	t.check_equal(edit.owner_at(target), "upper_arm_L", "painting moves ownership")
	t.check(not edit.part_cells("chest").has(target),
		"and the previous owner no longer holds it")

	# Erasing removes it from whoever holds it.
	edit.erase(target)
	t.check_equal(edit.owner_at(target), "", "erasing clears the owner")
	t.check(not edit.part_cells("upper_arm_L").has(target), "and the part too")

	# The head cannot be painted: its geometry comes from the head library.
	t.check(not edit.can_paint(BodyDef.HEAD_PART), "the head is not paintable")
	t.check(not edit.paint(Vector3i(12, 12, 30), BodyDef.HEAD_PART),
		"and painting it is refused")

	# Cells outside the grid are refused rather than silently stored.
	t.check(not edit.paint(Vector3i(-1, 5, 5), "chest"), "a cell off the grid is refused")
	t.check(not edit.paint(Vector3i(5, 5, 999), "chest"), "so is one above the grid")


# --------------------------------------------------------------- mirror ----

static func _mirror(t: TestReport, library: AssetLibrary) -> void:
	t.group("body edit: mirror pairs are mandatory")

	t.check_equal(BodyEdit.mirror_part("upper_arm_L"), "upper_arm_R",
		"a paired part mirrors into its opposite number")
	t.check_equal(BodyEdit.mirror_part("upper_arm_R"), "upper_arm_L", "and back")
	t.check_equal(BodyEdit.mirror_part("chest"), "chest",
		"a centred part mirrors into itself")

	var edit := BodyEdit.from_body(library.body("female_slim"))

	# Painting the left arm fills the right arm's mirrored cell.
	var cell := Vector3i(19, 11, 20)
	edit.paint(cell, "upper_arm_L")
	var mirrored := VoxelAxes.mirror_voxel(cell)
	t.check_equal(edit.owner_at(cell), "upper_arm_L", "the painted cell is the left arm's")
	t.check_equal(edit.owner_at(mirrored), "upper_arm_R",
		"its mirror belongs to the right arm")

	# The slice grid looks down on the figure, so screen-left is the
	# character's RIGHT. Choosing upper_arm_L and painting there must paint the
	# right arm (and mirror the left arm into place), not put the left arm on
	# the right-hand side of the body.
	var wrong_side := Vector3i(3, 11, 21)
	t.check(not VoxelAxes.is_left(wrong_side), "x3 is on the character's right")
	edit.paint(wrong_side, "upper_arm_L")
	t.check_equal(edit.owner_at(wrong_side), "upper_arm_R",
		"painting upper_arm_L on the character's right paints the right arm")
	t.check_equal(edit.owner_at(VoxelAxes.mirror_voxel(wrong_side)), "upper_arm_L",
		"and the left arm gets the mirrored cell on the left")
	var crossed := 0
	for name in ["upper_arm", "forearm", "thigh", "shin"]:
		for cell3 in edit.part_cells(name + "_L").keys():
			if not VoxelAxes.is_left(cell3):
				crossed += 1
		for cell4 in edit.part_cells(name + "_R").keys():
			if VoxelAxes.is_left(cell4):
				crossed += 1
	t.check_equal(crossed, 0, "no paired part ever ends up on the wrong side")
	t.check(edit.pivot_of("upper_arm_L").x > VoxelAxes.MIRROR_X,
		"so the left arm's pivot stays on the left",
		str(edit.pivot_of("upper_arm_L")))
	t.check_equal(BodyEdit.part_for_side("chest", wrong_side), "chest",
		"a centred part is not affected by which side it is painted on")

	# Painting a centred part mirrors within that same part.
	var chest_cell := Vector3i(16, 10, 23)
	edit.paint(chest_cell, "chest")
	t.check_equal(edit.owner_at(VoxelAxes.mirror_voxel(chest_cell)), "chest",
		"a centred part's mirror stays in the same part")

	# Erasing mirrors too.
	edit.erase(cell)
	t.check_equal(edit.owner_at(mirrored), "",
		"erasing one side erases the other")

	# No cell is its own mirror, so there is no column to special-case.
	for x in range(0, VoxelAxes.GRID.x):
		var c := Vector3i(x, 12, 20)
		if VoxelAxes.mirror_voxel(c) == c:
			t.check(false, "no cell should be its own mirror", str(c))
			break

	# The whole point: a body cannot be made asymmetric through this class.
	var scratch := BodyEdit.from_body(library.body("male_slim"))
	for i in 40:
		scratch.paint(Vector3i(6 + i % 12, 4 + i % 14, 8 + i % 18), "chest")
	for j in 15:
		scratch.erase(Vector3i(7 + j % 9, 6 + j % 11, 10 + j % 12))
	t.check(VoxelTopology.is_mirror_symmetric(scratch.owner_of),
		"after arbitrary painting and erasing the body is still symmetric",
		"%d cells without a partner"
			% VoxelTopology.asymmetric_cells(scratch.owner_of).size())
	# and the parts correspond, not just the occupancy
	var mismatched := 0
	for cell2 in scratch.owner_of.keys():
		var here := scratch.owner_at(cell2)
		var there := scratch.owner_at(VoxelAxes.mirror_voxel(cell2))
		if there != BodyEdit.mirror_part(here):
			mismatched += 1
	t.check_equal(mismatched, 0, "and every cell's mirror is in the mirrored part")


# ----------------------------------------------------------- validation ----

static func _validation(t: TestReport, library: AssetLibrary) -> void:
	t.group("body edit: validation agrees with the shipped bodies")
	var head := library.head("round")
	for id in library.body_ids():
		var edit := BodyEdit.from_body(library.body(id))
		var findings := edit.validate(head)
		var failed := BodyEdit.failures(findings)
		var names: Array[String] = []
		for entry in failed:
			names.append((entry as BodyEdit.Finding).label)
		t.check(failed.is_empty(), "%s passes every body check as shipped" % id,
			", ".join(names))

	t.group("body edit: validation catches what it claims to")

	# A floating island breaks connectivity.
	var island := BodyEdit.from_body(library.body("male_average"))
	island.paint(Vector3i(2, 2, 44), "chest")
	t.check(_fails(island.validate(head), "one connected piece"),
		"a detached cell breaks the connected-piece check")

	# A cell in the neck socket stops any head fitting.
	var blocked := BodyEdit.from_body(library.body("male_average"))
	blocked.paint(Vector3i(11, 11, HeadDef.NECK_ROW), "chest")
	t.check(_fails(blocked.validate(head), "neck socket is clear"),
		"a cell in the neck socket is caught")

	# Lifting the whole body off the floor is caught.
	var floating := BodyEdit.from_body(library.body("male_average"))
	var feet: Array = []
	for cell in floating.part_cells("shin_L").keys():
		if (cell as Vector3i).z == 0:
			feet.append(cell)
	for cell2 in floating.part_cells("shin_R").keys():
		if (cell2 as Vector3i).z == 0:
			feet.append(cell2)
	floating.erase_many(feet)
	t.check(_fails(floating.validate(head), "feet stand on z0"),
		"a body that no longer reaches the floor is caught")

	# Emptying a part is caught rather than quietly accepted.
	var gutted := BodyEdit.from_body(library.body("male_average"))
	gutted.erase_many(gutted.part_cells("forearm_L").keys().duplicate())
	var gutted_failures := BodyEdit.failures(gutted.validate(head))
	t.check(not gutted_failures.is_empty(), "emptying a part fails validation",
		"%d findings" % gutted_failures.size())

	# A clean body reports no problem cells to mark.
	var clean := BodyEdit.from_body(library.body("female_average"))
	var marks := 0
	for entry2 in clean.validate(head):
		var finding: BodyEdit.Finding = entry2
		if not finding.ok:
			marks += finding.cells.size()
	t.check_equal(marks, 0, "a shipped body has no cells to mark as problems")


static func _fails(findings: Array, label: String) -> bool:
	for entry in findings:
		var finding: BodyEdit.Finding = entry
		if finding.label == label:
			return not finding.ok
	return false


# ---------------------------------------------------------- round trips ----

static func _round_trip(t: TestReport, library: AssetLibrary) -> void:
	t.group("body edit: round trips")

	for id in library.body_ids():
		var body := library.body(id)
		var edit := BodyEdit.from_body(body)

		# Through the body file schema and back.
		var json := edit.to_json()
		var reloaded := BodyEdit.new()
		reloaded.sex = String(json["sex"])
		reloaded.build = String(json["build"])
		for name in BodyDef.EXPECTED_PARENTS.keys():
			reloaded.parts[name] = {}
		var raw_parts: Dictionary = json["parts"]
		for name2 in raw_parts.keys():
			for v in ((raw_parts[name2] as Dictionary)["voxels"] as Array):
				var cell := JsonIO.to_vec3i(v)
				reloaded.parts[name2][cell] = true
				reloaded.owner_of[cell] = String(name2)
		t.check_equal(reloaded.total_voxels(), edit.total_voxels(),
			"%s serialises every voxel" % id)
		t.check(VoxelTopology.same_cells(reloaded.owner_of, edit.owner_of),
			"%s serialises the same cells" % id)
		var same_owner := true
		for cell2 in edit.owner_of.keys():
			if reloaded.owner_at(cell2) != edit.owner_at(cell2):
				same_owner = false
				break
		t.check(same_owner, "%s keeps every cell with its part" % id)

		# The head's voxels stay out of a body file.
		t.check_equal(((json["parts"] as Dictionary)[BodyDef.HEAD_PART]
			as Dictionary)["voxels"].size(), 0,
			"%s writes no head voxels" % id)

		# And a BodyDef built straight from the edit matches the original.
		var rebuilt := edit.to_body_def()
		t.check_equal(rebuilt.total_voxels(), body.total_voxels(),
			"%s rebuilds to the same voxel count" % id)
		for name3 in body.part_names():
			t.check(rebuilt.part(name3).pivot.is_equal_approx(body.part(name3).pivot),
				"%s %s pivot survives the rebuild" % [id, name3])

	# The undo snapshot restores exactly.
	var edit2 := BodyEdit.from_body(library.body("male_heavy"))
	var before := edit2.snapshot()
	var count_before := edit2.total_voxels()
	edit2.paint_many([Vector3i(4, 4, 30), Vector3i(5, 4, 30)], "chest")
	edit2.erase_many(edit2.part_cells("shin_L").keys().duplicate())
	t.check(edit2.total_voxels() != count_before, "the edits changed the body")
	edit2.restore(before)
	t.check_equal(edit2.total_voxels(), count_before, "restore brings the count back")
	t.check(VoxelTopology.same_cells(edit2.owner_of, before["cells"]),
		"restore brings every cell back")
	t.check(BodyEdit.all_ok(edit2.validate(library.head("round"))),
		"and the restored body is valid again")


# ------------------------------------------------------------------ heads ---

## Every cell some shipped expression paints.
static func _eye_cells(library: AssetLibrary) -> Dictionary:
	var out := {}
	for name in library.expression_names():
		for cell in library.face(name).ink_cells().keys():
			out[cell] = true
	return out


static func _heads(t: TestReport, library: AssetLibrary) -> void:
	t.group("head edit: the shipped heads pass every head check")
	var eyes := _eye_cells(library)
	for shape in library.head_shapes():
		var edit := HeadEdit.from_head(library.head(shape))
		var failed := BodyEdit.failures(edit.validate(eyes))
		var names: Array[String] = []
		for f in failed:
			names.append((f as BodyEdit.Finding).label)
		t.check(failed.is_empty(), "%s passes as shipped" % shape, ", ".join(names))

	t.group("head edit: what is locked and what is checked")
	var head := HeadEdit.from_head(library.head("round"))
	var before := head.total_voxels()
	t.check(not head.paint(Vector3i(14, 12, HeadDef.NECK_ROW), HeadEdit.PART),
		"the neck row cannot be painted: it is the shared socket")
	t.check(not head.erase(Vector3i(11, 11, HeadDef.NECK_ROW)),
		"nor erased")
	t.check_equal(head.total_voxels(), before, "so the socket is untouched")

	t.check(head.paint(Vector3i(20, 12, 36), HeadEdit.PART), "the head can be painted")
	t.check_equal(head.owner_at(Vector3i(3, 12, 36)), HeadEdit.PART,
		"and the edit mirrors across the face")

	# Take away an eye cell: some expression no longer fits.
	var eye_cell: Vector3i = eyes.keys()[0]
	head.erase(eye_cell)
	t.check(_fails(head.validate(eyes), "every eye fits"),
		"removing a voxel an eye is drawn on is caught")
	head.paint(eye_cell, HeadEdit.PART)

	# Build out in front of an eye: it would be buried.
	head.paint(Vector3i(eye_cell.x, eye_cell.y - 1, eye_cell.z), HeadEdit.PART)
	t.check(_fails(head.validate(eyes), "nothing in front of the eyes"),
		"covering an eye from the front is caught")

	# Grow the crown above row 41: hair and hats would no longer sit right.
	var tall := HeadEdit.from_head(library.head("boxy"))
	tall.paint(Vector3i(12, 12, 42), HeadEdit.PART)
	t.check(_fails(tall.validate(eyes), "top of the head is row 41"),
		"a head taller than the shared height is caught")

	t.group("head edit: round trip through the head file schema")
	var path := "user://test_head_round_trip.json"
	var original := HeadEdit.from_head(library.head("heart"))
	t.check(original.save_to(path).is_empty(), "an edited head saves")
	var reloaded := HeadDef.load_from(path)
	t.check(reloaded != null, "and loads back through HeadDef, which validates it")
	if reloaded != null:
		t.check(VoxelTopology.same_cells(reloaded.cells, library.head("heart").cells),
			"with the same voxels")
		t.check_equal(reloaded.shape, "heart", "and the same name")
	DirAccess.remove_absolute(path)
	var def := original.to_head_def()
	t.check(VoxelTopology.same_cells(def.cells, library.head("heart").cells),
		"to_head_def gives the preview the same head")


# ------------------------------------------------------- edited overrides --

static func _overrides(t: TestReport, library: AssetLibrary) -> void:
	t.group("assets: an edited file wins over the generated one")
	var dir := "user://test_edited_assets"
	DirAccess.make_dir_recursive_absolute(dir)

	var edited_lib := AssetLibrary.new()
	edited_lib.edited_dir = dir
	edited_lib.load_all()
	t.check(not edited_lib.is_head_edited("oval"), "nothing is edited to begin with")

	var head := HeadEdit.from_head(edited_lib.head("oval"))
	head.paint(Vector3i(13, 16, 40), HeadEdit.PART)
	var count := head.total_voxels()
	t.check(head.save_to(edited_lib.edited_head_path("oval")).is_empty(),
		"an edited head saves into the edited folder")

	var reread := AssetLibrary.new()
	reread.edited_dir = dir
	reread.load_all()
	t.check(reread.is_head_edited("oval"), "a fresh library sees the edit")
	t.check_equal(reread.head("oval").count(), count, "and loads it instead of the generated head")

	var generated_only := AssetLibrary.new()
	generated_only.edited_dir = dir
	generated_only.use_edited = false
	generated_only.load_all()
	t.check_equal(generated_only.head("oval").count(), library.head("oval").count(),
		"with edits switched off, the generated head loads")

	t.check(reread.revert_head("oval").is_empty(), "reverting succeeds")
	t.check(not reread.is_head_edited("oval"), "and removes the edit")
	t.check_equal(reread.head("oval").count(), library.head("oval").count(),
		"putting the generated head back")
	DirAccess.remove_absolute(dir)
