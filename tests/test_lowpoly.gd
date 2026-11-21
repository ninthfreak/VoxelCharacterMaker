@tool
class_name TestLowpoly
extends RefCounted

## The low-poly characters in Godot (SPEC.md section 0): the editor's move to low-poly, phase 1.
##
## The bodies and heads are made in Python (lowpoly/) and read here from assets/lowpoly/. These checks hold that the
## game reads them whole, puts a head on a body as lowpoly/ does, and bends the figure in every test pose exactly as
## lowpoly/expected.py works out: tests/lowpoly_expected.json lists where every corner must be, and Godot's posed
## corners must be within its tolerance of each (Godot's vectors are single precision, the Python's double).

const EXPECTED_PATH := "res://tests/lowpoly_expected.json"


static func run(t: TestReport, voxel_library: AssetLibrary) -> void:
	t.group("low-poly: the bodies and heads, read from assets/lowpoly/")
	var library := LowpolyLibrary.new()
	t.check(library.load_all(), "every low-poly body and head file reads", ", ".join(library.errors))
	t.check_equal(library.body_ids().size(), 8, "eight bodies: slim, average, heavy and short, each sex")
	t.check_equal(library.head_shapes().size(), 5, "five heads")
	if library.body_ids().is_empty() or library.head_shapes().is_empty():
		return
	_layout(t, library)
	_heads_on_necks(t, library)

	t.group("low-poly: the figure bends as lowpoly/ bends it")
	_rig(t, library)
	_against_python(t, library)

	t.group("low-poly: clothing, as lowpoly/ dresses a figure")
	var wardrobe := Wardrobe.create_default(voxel_library)
	_dressed_against_python(t, library, wardrobe)
	_dressing_rules(t, library, wardrobe)


static func _layout(t: TestReport, library: LowpolyLibrary) -> void:
	var first := library.body(library.body_ids()[0])
	var same := true
	var weights_ok := true
	for id in library.body_ids():
		var b := library.body(id)
		same = same and b.points.size() == first.points.size() and b.polygons.size() == first.polygons.size()
		for i in mini(b.polygons.size(), first.polygons.size()):
			var p: Dictionary = b.polygons[i]
			var q: Dictionary = first.polygons[i]
			same = same and p["corners"] == q["corners"] and p["region"] == q["region"] and p["part"] == q["part"]
		for w in b.shares:
			var sum := 0.0
			for part in (w as Dictionary).keys():
				sum += float(w[part])
				weights_ok = weights_ok and LowpolyLibrary.PARTS.has(String(part))
			weights_ok = weights_ok and (w as Dictionary).size() <= 4 and absf(sum - 1.0) < 1e-6
	t.check(same, "all eight bodies have the same corners and polygons (%d and %d), in the same order, on the same regions"
		% [first.points.size(), first.polygons.size()])
	t.check(weights_ok, "every corner follows at most four parts, in shares that add up to one")
	var visible := 0
	for p in first.polygons:
		visible += 0 if bool(p["hidden"]) else 1
	t.check_equal(visible, 320, "a body draws 320 polygons; the rest are ends hidden inside a neighbouring piece")


static func _heads_on_necks(t: TestReport, library: LowpolyLibrary) -> void:
	var sits := true
	var detail := ""
	for id in library.body_ids():
		var f := LowpolyFigure.make(library, id, "round", Palette.SKIN_MID)
		var lowest := INF                                   # the head piece; the neck belongs to the head part too
		for p in f.polygons:
			if String(p["piece"]) == "head":
				for k in p["corners"]:
					lowest = minf(lowest, f.points[k].z)
		var neck: Vector2 = library.body(id).heights.get("neck", Vector2.ZERO)
		if absf(lowest - neck.y) > 1e-4:
			sits = false
			detail = "%s: head from %.3f, neck top %.3f" % [id, lowest, neck.y]
	t.check(sits, "on every body the head's lowest point is the top of the neck (on a short body, 6 units lower)", detail)


static func _rig(t: TestReport, library: LowpolyLibrary) -> void:
	var f := LowpolyFigure.make(library, "male_short", "strong", Palette.SKIN_MID)
	var rig := LowpolyRig.new()
	rig.build(f)
	t.check_equal(rig.skeleton.get_bone_count(), 11, "a bone for each of the eleven parts")
	var parents_ok := true
	for part in LowpolyLibrary.PARTS:
		var i := rig.skeleton.find_bone(part)
		var parent := String(f.parts[part]["parent"])
		var p := rig.skeleton.get_bone_parent(i)
		parents_ok = parents_ok and (p == -1 if parent.is_empty() else rig.skeleton.get_bone_name(p) == parent)
	t.check(parents_ok, "each bone hangs from its part's parent (SPEC 3.1)")
	var mesh := rig.mesh_instance.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	t.check_equal(indices.size() / 3, f.triangles(), "the mesh draws every visible polygon, as %d triangles" % f.triangles())
	t.check(rig.mesh_instance.skin != null and rig.mesh_instance.skin.get_bind_count() == 11,
		"the mesh is skinned to all eleven bones")
	var still := rig.posed_points({})
	var moved := 0.0
	for k in still.size():
		moved = maxf(moved, still[k].distance_to(f.points[k]))
	t.check(moved < 1e-4, "standing still, every corner is where the files put it", "moved %f" % moved)

	# The skeleton must turn the bones as the rig works them out, or what is drawn and what is picked would differ.
	rig.apply_pose(Poses.SITTING)
	var m := rig.skinning()
	var agree := true
	for part in LowpolyLibrary.PARTS:
		var i := rig.skeleton.find_bone(part)
		var drawn := rig.skeleton.get_bone_global_pose(i) * (rig.skeleton.get_bone_global_rest(i).affine_inverse())
		agree = agree and drawn.is_equal_approx(m[part])
	t.check(agree, "the skeleton turns every bone as the rig works it out (sitting)")
	# Flat: the corners of a polygon share its normal. Smooth: a corner shared by polygons facing different ways
	# has a normal between theirs, so the corners of one polygon differ.
	var spread := func() -> float:
		var normals: PackedVector3Array = (rig.mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var most := 0.0
		var at := 0
		for p in f.polygons:
			if bool(p["hidden"]):
				continue
			var n := (p["corners"] as PackedInt32Array).size()
			for i in range(1, n):
				most = maxf(most, normals[at].distance_to(normals[at + i]))
			at += n
		return most
	var flat_spread: float = spread.call()
	rig.flat_shading = false
	var smooth_spread: float = spread.call()
	t.check(flat_spread < 0.01 and smooth_spread > 0.3, "shading switches between flat (one normal a polygon) and smooth",
		"spread across a polygon: flat %f, smooth %f" % [flat_spread, smooth_spread])
	rig.free()


static func _against_python(t: TestReport, library: LowpolyLibrary) -> void:
	var expected := JsonIO.read_dict(EXPECTED_PATH)
	if not t.check(String(expected.get("format", "")) == "lowpoly_expected", "tests/lowpoly_expected.json reads",
			"run: python3 lowpoly/expected.py"):
		return
	var tolerance := float(expected.get("tolerance", 0.001))
	var rig := LowpolyRig.new()
	var worst := 0.0
	var where := ""
	var cases := 0
	var built := ""
	for c in expected["cases"]:
		var case_: Dictionary = c
		var key := "%s/%s" % [case_["body"], case_["head"]]
		if key != built:
			rig.build(LowpolyFigure.make(library, String(case_["body"]), String(case_["head"]), Palette.SKIN_MID))
			built = key
		var got := rig.posed_points(Poses.get_pose(String(case_["pose"])))
		var want: Array = case_["points"]
		if got.size() != want.size():
			worst = INF
			where = "%s %s: %d corners, expected %d" % [case_["body"], case_["pose"], got.size(), want.size()]
			continue
		for k in want.size():
			var d := got[k].distance_to(LowpolyLibrary._vec(want[k]))
			if d > worst:
				worst = d
				where = "%s %s, corner %d" % [case_["body"], case_["pose"], k]
		cases += 1
	rig.free()
	t.check(worst <= tolerance, "in all %d cases (every body standing; every test pose on the feminine average and the masculine short) every corner is where lowpoly/ puts it, within %s units"
		% [cases, tolerance], "off by %f at %s" % [worst, where])


## Every dressed figure in tests/lowpoly_expected.json, polygon by polygon: the same polygons in the same order, each
## with its corners where lowpoly/dress.py puts them, in its colour, made by the same worn item.
static func _dressed_against_python(t: TestReport, library: LowpolyLibrary, wardrobe: Wardrobe) -> void:
	var expected := JsonIO.read_dict(EXPECTED_PATH)
	var cases: Array = expected.get("dressed", [])
	if not t.check(not cases.is_empty(), "tests/lowpoly_expected.json has dressed figures", "run: python3 lowpoly/expected.py"):
		return
	var tolerance := float(expected.get("tolerance", 0.001))
	for c in cases:
		var case_: Dictionary = c
		var req := CharacterAssembler.Request.new()
		req.body_id = String(case_["body"])
		req.head_shape = String(case_["head"])
		req.wardrobe = wardrobe
		req.worn = wardrobe.outfit(String(case_["outfit"]))
		if not String(case_["hair"]).is_empty():
			req.features = [{"item": String(case_["hair"]), "colourway": String(case_["hair_colourway"])}]
		var f := LowpolyAssembler.assemble(library, req)
		var want: Array = case_["polygons"]
		var label := "%s, %s, %s: %d polygons as lowpoly/ makes them" % [case_["body"], case_["outfit"],
			"with %s" % case_["hair"] if not String(case_["hair"]).is_empty() else "bald", want.size()]
		if f == null or f.polygons.size() != want.size():
			t.check(false, label, "%d polygons" % (f.polygons.size() if f != null else -1))
			continue
		var worst := 0.0
		var wrong := ""
		for i in want.size():
			var w: Dictionary = want[i]
			var got: Dictionary = f.polygons[i]
			var corners: PackedInt32Array = got["corners"]
			var pts: Array = w["points"]
			var colour := "#" + (got["colour"] as Color).to_html(false)
			if corners.size() != pts.size() or colour != String(w["colour"]) or String(got["by"]) != String(w["by"]):
				wrong = "polygon %d: %d corners, %s by '%s'; expected %d, %s by '%s'" % [i, corners.size(), colour,
					got["by"], pts.size(), w["colour"], w["by"]]
				break
			for k in pts.size():
				worst = maxf(worst, f.points[corners[k]].distance_to(LowpolyLibrary._vec(pts[k])))
		t.check(wrong.is_empty() and worst <= tolerance, label + " (colours, items, corners within %s)" % tolerance,
			wrong if not wrong.is_empty() else "off by %f" % worst)


## The rules themselves, on one figure: what the cross-check above cannot say by itself.
static func _dressing_rules(t: TestReport, library: LowpolyLibrary, wardrobe: Wardrobe) -> void:
	var req := CharacterAssembler.Request.new()
	req.body_id = "female_average"
	req.head_shape = "round"
	req.wardrobe = wardrobe
	req.worn = wardrobe.outfit("travelling")
	var f := LowpolyAssembler.assemble(library, req)
	var ears_bare := true
	var floor_ok := true
	for p in f.polygons:
		if String(p["at"]) == "ear" and not String(p["by"]).is_empty():
			ears_bare = false
		for k in p["corners"]:
			floor_ok = floor_ok and f.points[k].z >= -1e-6
	t.check(floor_ok, "nothing worn goes below the floor (rule 3)")
	var hems := 0
	var inward := 0
	var parent: Dictionary = {}
	for p in f.polygons:
		if not p.get("hem", false):
			parent = p
			continue
		var c: PackedInt32Array = p["corners"]
		var n := Vector3.ZERO
		var mid := Vector3.ZERO
		for i in c.size():
			n += f.points[c[i]].cross(f.points[c[(i + 1) % c.size()]])
			mid += f.points[c[i]] / c.size()
		var pc: PackedInt32Array = parent["corners"]
		var parent_mid := Vector3.ZERO
		for k in pc:
			parent_mid += f.points[k] / pc.size()
		if n.length() > 1e-6:
			hems += 1
			inward += 1 if n.dot(mid - parent_mid) <= 0.0 else 0
	t.check(hems > 0 and inward == 0, "all %d hems face out over their step, so a renderer that hides back faces draws them" % hems,
		"%d face inward" % inward)
	var cloak_noted := false
	for w in f.warnings:
		cloak_noted = cloak_noted or (w.begins_with("cloak") and w.contains("not on the low-poly figure yet"))
	t.check(cloak_noted, "an item's special shape not built for low-poly yet is named in the warnings (the cloak's cape)")
	req.features = [{"item": "short_crop", "colourway": "default"}]
	f = LowpolyAssembler.assemble(library, req)
	for p in f.polygons:
		if String(p["at"]) == "ear" and not String(p["by"]).is_empty():
			ears_bare = false
	t.check(ears_bare, "ears stay skin under hair")
	req.solo_item = "boots"
	f = LowpolyAssembler.assemble(library, req)
	var others := false
	for p in f.polygons:
		others = others or (not String(p["by"]).is_empty() and String(p["by"]) != "boots")
	t.check(not others, "with one item soloed, only that item is on the figure")
