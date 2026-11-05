@tool
class_name TestAssets
extends RefCounted

## SPEC.md section 12, the body and head checks:
##
##   - loading each body reproduces its voxel counts
##   - every body: mirror-symmetric, one connected piece, every part one piece,
##     no edge-only contacts, parts touch only their parents
##   - the region band table is identical on all six bodies (section 3.4)
##
## The expected counts come from tests/expected.json, measured from the shipped
## files by tools/verify_assets.py.


static func run(t: TestReport, library: AssetLibrary) -> void:
	var expected := TestReport.expected()
	var bodies: Dictionary = expected.get("bodies", {})
	var heads: Dictionary = expected.get("heads", {})

	t.group("assets: library loads")
	t.check(library.errors.is_empty(), "every asset loaded", ", ".join(library.errors))
	t.check_equal(library.bodies.size(), 6, "six bodies")
	t.check_equal(library.heads.size(), 5, "five heads")
	t.check(library.faces.size() >= 11, "at least the eleven starter expressions",
		"got %d" % library.faces.size())

	var regions_problem := library.verify_regions_match()
	t.check(regions_problem.is_empty(),
		"the region band table is identical on all six bodies", regions_problem)

	t.group("assets: heads")
	for shape in library.head_shapes():
		var head := library.head(shape)
		var want: Dictionary = heads.get(shape, {})
		if not want.is_empty():
			t.check_equal(head.count(), int(want["voxels"]), "head %s voxel count" % shape)
		t.check_equal(TestReport.components(head.cells), 1,
			"head %s is one connected piece" % shape)
		t.check(TestReport.same_cells(head.cells, TestReport.mirror_of(head.cells)),
			"head %s is mirror-symmetric" % shape)
		t.check(head.pivot.is_equal_approx(HeadDef.EXPECTED_PIVOT),
			"head %s shares the pivot" % shape)
		t.check_equal(head.face_plane_y(), VoxelAxes.FACE_PLANE_Y,
			"head %s shares the face plane" % shape)

	t.group("assets: bodies")
	for id in library.body_ids():
		var body := library.body(id)
		var want: Dictionary = bodies.get(id, {})

		# Counts are stated with the round head attached; body files exclude it.
		var full := body.all_cells().duplicate()
		for cell in library.head("round").cells.keys():
			full[cell] = true

		if not want.is_empty():
			t.check_equal(full.size(), int(want["voxels_with_round_head"]),
				"%s voxel count with the round head" % id)
			t.check_equal(body.total_voxels(), int(want["voxels_body_only"]),
				"%s voxel count without a head" % id)

		var full_set := TestReport.as_set(full.keys())
		t.check(TestReport.same_cells(full_set, TestReport.mirror_of(full_set)),
			"%s is mirror-symmetric" % id)
		t.check_equal(TestReport.components(full_set), 1,
			"%s is one connected piece" % id)

		var bad := TestReport.edge_only_contacts(full_set)
		t.check(bad.is_empty(), "%s has no edge-only contacts" % id,
			"%d found, e.g. %s" % [bad.size(), bad[0] if not bad.is_empty() else ""])

		# Every part is one connected piece.
		for name in body.part_names():
			var part := body.part(name)
			if part.cells.is_empty():
				continue
			t.check_equal(TestReport.components(part.cells), 1,
				"%s part %s is one piece" % [id, name])

		# Every part touches only its parent.
		var cells_by_part := {}
		for name2 in body.part_names():
			var p := body.part(name2)
			cells_by_part[name2] = library.head("round").cells \
				if name2 == BodyDef.HEAD_PART else p.cells
		var names := cells_by_part.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a := String(names[i])
				var b := String(names[j])
				var related := body.part(a).parent == b or body.part(b).parent == a
				if related:
					continue
				t.check(not TestReport.face_adjacent(cells_by_part[a], cells_by_part[b]),
					"%s: %s does not touch %s" % [id, a, b])

		# Thighs never touch each other (SPEC section 3.1, called out by name).
		t.check(not TestReport.face_adjacent(
				body.part("thigh_L").cells, body.part("thigh_R").cells),
			"%s thighs do not touch each other" % id)

		# The head socket matches so any head fits any body.
		var chest := body.part("chest")
		var top := 0
		for cell in chest.cells.keys():
			top = maxi(top, (cell as Vector3i).z)
		t.check_equal(top, 26, "%s chest tops out at z26, under the neck row" % id)
