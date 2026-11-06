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
	t.check(library.open_face() != null, "the open eye face")

	var regions_problem := library.verify_regions_match()
	t.check(regions_problem.is_empty(),
		"the region band table is identical on all six bodies", regions_problem)

	# BodyLayout is the Godot copy of build_bodies.py's row table; every row
	# number in core/ comes from it, so it must match what the files say.
	t.group("assets: the shared row layout matches the files")
	for id in library.body_ids():
		var map := library.body(id).regions
		var differ: Array[String] = []
		for name in BodyLayout.BANDS.keys():
			var band := map.band(String(name))
			if band == null or Vector2i(band.z0, band.z1) != BodyLayout.BANDS[name]:
				differ.append(String(name))
		if map.band_names().size() != BodyLayout.BANDS.size():
			differ.append("(band count %d)" % map.band_names().size())
		t.check(differ.is_empty(), "%s bands match BodyLayout" % id, ", ".join(differ))
	for shape in library.head_shapes():
		var head := library.head(shape)
		t.check(head.pivot.is_equal_approx(BodyLayout.HEAD_PIVOT), "%s head pivot matches" % shape)
		t.check_equal(int(head.neck_socket["z"]), BodyLayout.NECK_ROW, "%s neck socket row matches" % shape)
		t.check_equal(head.eye_rows(), Vector2i(BodyLayout.EYE_Z0, BodyLayout.EYE_Z1),
			"%s eye rows match" % shape)
		t.check_equal(head.screen_left_eye_x(),
			Vector2i(BodyLayout.EYE_X0, BodyLayout.EYE_X0 + BodyLayout.EYE_W - 1),
			"%s eye columns match" % shape)
		t.check_equal(head.face_plane_y(), BodyLayout.FACE_PLANE_Y, "%s face plane matches" % shape)
		var depth_lo := 99
		var depth_hi := -99
		for cell in head.cells.keys():
			if (cell as Vector3i).z > BodyLayout.NECK_ROW:
				depth_lo = mini(depth_lo, (cell as Vector3i).y)
				depth_hi = maxi(depth_hi, (cell as Vector3i).y)
		t.check_equal(depth_hi - depth_lo + 1, BodyLayout.HEAD_DEPTH, "%s head depth matches" % shape)

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
		t.check_equal(top, BodyLayout.NECK_ROW - 1,
			"%s chest tops out on the row under the neck" % id)
