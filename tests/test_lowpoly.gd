@tool
class_name TestLowpoly
extends RefCounted

## The low-poly characters in Godot (SPEC.md section 0): the figure the game and the editor draw.
##
## The bodies and heads are made in Python (lowpoly/) and read here from assets/lowpoly/. These checks hold that the
## game reads them whole, puts a head on a body as lowpoly/ does, and bends the figure in every test pose exactly as
## lowpoly/expected.py works out: tests/lowpoly_expected.json lists where every corner must be, and Godot's posed
## corners must be within its tolerance of each (Godot's vectors are single precision, the Python's double).

const EXPECTED_PATH := "res://tests/lowpoly_expected.json"


static func run(t: TestReport) -> void:
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
	var wardrobe := Wardrobe.create_default()
	_dressed_against_python(t, library, wardrobe)
	_dressing_rules(t, library, wardrobe)
	_cloth_in_the_rig(t, library, wardrobe)

	t.group("low-poly: faces and facial hair, as lowpoly/ draws them")
	_faces_against_python(t, library, wardrobe)
	_face_rules(t, library, wardrobe)


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
## with its corners where lowpoly/dress.py puts them, in its colour, made by the same worn item (straps among them);
## then its hanging cloth in each pose it was laid in, as lowpoly/hang.py lays it.
static func _dressed_against_python(t: TestReport, library: LowpolyLibrary, wardrobe: Wardrobe) -> void:
	var expected := JsonIO.read_dict(EXPECTED_PATH)
	var cases: Array = expected.get("dressed", [])
	if not t.check(not cases.is_empty(), "tests/lowpoly_expected.json has dressed figures", "run: python3 lowpoly/expected.py"):
		return
	var tolerance := float(expected.get("tolerance", 0.001))
	var w := Wardrobe.from_json(wardrobe.to_json())
	for c in cases:
		var case_: Dictionary = c
		var items: Dictionary = case_.get("items", {})
		for id in items.keys():
			if w.item(String(id)) == null:
				w.add_item(GarmentItem.from_json(String(id), items[id]))
		var req := CharacterRequest.new()
		req.body_id = String(case_["body"])
		req.head_shape = String(case_["head"])
		req.wardrobe = w
		for pair in case_["worn"]:
			req.worn.append({"item": String(pair[0]), "colourway": String(pair[1])})
		if not String(case_["hair"]).is_empty():
			req.features = [{"item": String(case_["hair"]), "colourway": String(case_["hair_colourway"])}]
		var f := LowpolyAssembler.assemble(library, req)
		var want: Array = case_["polygons"]
		var what := String(case_["outfit"]) if not String(case_["outfit"]).is_empty() else ", ".join(items.keys())
		var label := "%s, %s, %s: %d polygons as lowpoly/ makes them" % [case_["body"], what,
			"with %s" % case_["hair"] if not String(case_["hair"]).is_empty() else "bald", want.size()]
		var mine := _polygons_of(f, [], true)     # all but the face, drawn on top
		if f == null or mine.size() != want.size():
			t.check(false, label, "%d polygons" % (mine.size() if f != null else -1))
			continue
		var worst := 0.0
		var wrong := ""
		for i in want.size():
			var e: Dictionary = want[i]
			var got: Dictionary = mine[i]
			var corners: PackedInt32Array = got["corners"]
			var pts: Array = e["points"]
			var colour := "#" + (got["colour"] as Color).to_html(false)
			if corners.size() != pts.size() or colour != String(e["colour"]) or String(got["by"]) != String(e["by"]):
				wrong = "polygon %d: %d corners, %s by '%s'; expected %d, %s by '%s'" % [i, corners.size(), colour,
					got["by"], pts.size(), e["colour"], e["by"]]
				break
			for k in pts.size():
				worst = maxf(worst, Vec64.norm(Vec64.sub(f.point64(corners[k]), _vec64(pts[k]))))
		t.check(wrong.is_empty() and worst <= tolerance, label + " (colours, items, corners within %s)" % tolerance,
			wrong if not wrong.is_empty() else "off by %f" % worst)
		var cloths: Dictionary = case_.get("cloths", {})
		for pose_name in cloths.keys():
			var want_cloth: Array = cloths[pose_name]
			var laid: Array = []
			var pose := Poses.get_pose(String(pose_name))
			var custom: Dictionary = case_.get("custom_poses", {})
			if custom.has(pose_name):                       # not a game pose: listed with the case
				pose = {}
				for part in (custom[pose_name] as Dictionary).keys():
					var deg: Array = custom[pose_name][part]
					pose[String(part)] = Vector3(float(deg[0]), float(deg[1]), float(deg[2]))
			for pair in LowpolyCloth.lay_all(f, pose):
				for made in pair[1]:
					laid.append([made[0], made[1], (pair[0] as LowpolyCloth)])
			var cloth_label := "%s, %s, %s: its hanging cloth, %d pieces, as lowpoly/hang.py lays it" % [case_["body"], what,
				String(pose_name) if custom.has(pose_name) else Poses.display_name(String(pose_name)), want_cloth.size()]
			if laid.size() != want_cloth.size():
				t.check(false, cloth_label, "%d pieces" % laid.size())
				continue
			var off := 0.0
			var bad := ""
			for i in want_cloth.size():
				var e: Dictionary = want_cloth[i]
				var pts: PackedFloat64Array = laid[i][0]
				var cloth: LowpolyCloth = laid[i][2]
				var colour := "#" + (cloth.colours.get(laid[i][1], Color.MAGENTA) as Color).to_html(false)
				var expect_pts: Array = e["points"]
				if pts.size() != 3 * expect_pts.size() or String(laid[i][1]) != String(e["role"]) or colour != String(e["colour"]) \
						or cloth.by != String(e["by"]):
					bad = "piece %d: %d corners, %s %s by %s; expected %d, %s %s by %s" % [i, pts.size() / 3, laid[i][1], colour,
						cloth.by, expect_pts.size(), e["role"], e["colour"], e["by"]]
					break
				for k in expect_pts.size():
					off = maxf(off, Vec64.norm(Vec64.sub(Vec64.at(pts, k), _vec64(expect_pts[k]))))
			t.check(bad.is_empty() and off <= tolerance, cloth_label + " (within %s)" % tolerance,
				bad if not bad.is_empty() else "off by %f" % off)


static func _vec64(a: Array) -> PackedFloat64Array:
	return PackedFloat64Array([float(a[0]), float(a[1]), float(a[2])])


## The rules themselves, on one figure: what the cross-check above cannot say by itself.
static func _dressing_rules(t: TestReport, library: LowpolyLibrary, wardrobe: Wardrobe) -> void:
	var req := CharacterRequest.new()
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
	var hair_kept := false
	for p in f.polygons:
		others = others or (not String(p["by"]).is_empty() and String(p["by"]) not in ["boots", "short_crop"])
		hair_kept = hair_kept or String(p["by"]) == "short_crop"
	t.check(not others and hair_kept, "with one item soloed, only that item of the clothes is on the figure; hair stays")


## Hanging cloth as the game draws it: kept on the figure, laid afresh when the pose changes, in front of what it hides.
static func _cloth_in_the_rig(t: TestReport, library: LowpolyLibrary, wardrobe: Wardrobe) -> void:
	var req := CharacterRequest.new()
	req.body_id = "female_average"
	req.head_shape = "round"
	req.wardrobe = wardrobe
	req.worn = wardrobe.outfit("dress")
	var f := LowpolyAssembler.assemble(library, req)
	t.check(f.cloths.size() == 1 and (f.cloths[0] as LowpolyCloth).by == "skirt",
		"the dress's skirt is hanging cloth on the figure, not part of its skin")
	var rig := LowpolyRig.new()
	rig.build(f)
	var standing := rig.laid_cloth.duplicate()
	t.check(rig.cloth_instance != null and rig.cloth_instance.visible and rig.cloth_instance.mesh != null
		and not standing.is_empty(), "the rig draws the skirt (%d pieces) as a mesh of its own" % standing.size())
	rig.apply_pose(Poses.SITTING)
	var moved := false
	for i in mini(standing.size(), rig.laid_cloth.size()):
		moved = moved or Vec64.norm(Vec64.sub(Vec64.at(standing[i][0], 0), Vec64.at(rig.laid_cloth[i][0], 0))) > 0.5 \
			or Vec64.norm(Vec64.sub(Vec64.at(standing[i][0], 2), Vec64.at(rig.laid_cloth[i][0], 2))) > 0.5
	t.check(moved, "sitting, the skirt is laid again over the lap")
	rig.apply_pose(Poses.REST)
	t.check((rig.cloth_instance.material_override as ShaderMaterial).shader.code.contains("cull_disabled")
		and (rig.mesh_instance.material_override as ShaderMaterial).shader.code.contains("cull_back"),
		"hanging cloth is drawn from both sides (the inside of a skirt, a cape seen from in front); the skin is not")
	# a ray at the front of the thigh, under the skirt: the cloth is in front, so nothing is picked
	var hit := rig.pick(Vector3(0.12, 0.38, -3.0), Vector3(0, 0, 1))
	t.check(hit == -1, "a click on the skirt picks nothing under it",
		"picked %s" % (String(f.polygons[hit]["region"]) if hit >= 0 else "nothing"))
	rig.free()
	# settings of the wrong type, as a hand-edited file might have them: read as lowpoly/specials.py reads them
	var odd := Wardrobe.from_json(wardrobe.to_json())
	var skirt := odd.item("skirt")
	skirt.specials[0]["params"] = {"length": 3, "waistband": "false", "flare": null, "slant": "2", "panels": "two"}
	req.wardrobe = odd
	req.worn = [{"item": "skirt", "colourway": "default"}]
	var built := LowpolyAssembler.assemble(library, req)
	t.check(built.cloths.size() == 1 and built.warnings.is_empty(),
		"a skirt whose settings are of the wrong type still builds (a number for the length, text for a switch)",
		", ".join(built.warnings))
	req.wardrobe = wardrobe
	req.worn = wardrobe.outfit("everyday")
	var plain := LowpolyRig.new()
	plain.build(LowpolyAssembler.assemble(library, req))
	t.check(plain.laid_cloth.is_empty() and (plain.cloth_instance == null or not plain.cloth_instance.visible),
		"a figure with no hanging cloth draws none")
	plain.free()


## A figure's polygons whose piece is one of `pieces` (or, with `all_but_face`, every polygon but the face's).
static func _polygons_of(f: LowpolyFigure, pieces: Array, all_but_face: bool = false) -> Array:
	var out: Array = []
	if f == null:
		return out
	for p in f.polygons:
		var piece := String(p["piece"])
		if (all_but_face and piece != LowpolyAssembler.FACE_PIECE) or (not all_but_face and pieces.has(piece)):
			out.append(p)
	return out


## The facial hair item lowpoly/facial_hair.py item() makes for a case: these parts on, this length.
static func _facial_hair_item(record: Dictionary) -> GarmentItem:
	var params := {"length": String(record["length"])}
	for part in FacialHairSettings.PARTS:
		params[part] = (record["parts"] as Array).has(part)
	return GarmentItem.from_json(String(record["id"]), {"category": "facial_hair", "name": String(record["id"]),
		"colourways": {"default": {"hair": "@hair", "stubble": "@stubble"}}, "coverage": {},
		"draw_order": int(record["draw_order"]), "edge_style": "soft", "mirror": true, "roles": ["hair", "stubble"],
		"specials": [{"type": "facial_hair", "params": params}]}, "facial_hair")


## Every face in tests/lowpoly_expected.json: the head's polygons (cut and claimed by facial hair, some lifted, with
## their hems) and the face's (eyes, lids, brows, mouth), polygon by polygon, in lowpoly/dress.py's order.
static func _faces_against_python(t: TestReport, library: LowpolyLibrary, wardrobe: Wardrobe) -> void:
	var expected := JsonIO.read_dict(EXPECTED_PATH)
	var cases: Array = expected.get("faces", [])
	if not t.check(not cases.is_empty(), "tests/lowpoly_expected.json has faces", "run: python3 lowpoly/expected.py"):
		return
	var tolerance := float(expected.get("tolerance", 0.001))
	var w := Wardrobe.from_json(wardrobe.to_json())
	for c in cases:
		var case_: Dictionary = c
		var req := CharacterRequest.new()
		req.body_id = String(case_["body"])
		req.head_shape = String(case_["head"])
		req.wardrobe = w
		req.skin_tone = String(case_["skin"])
		req.eye_set_id = String(case_["eye_set"])
		req.eye_colourway = String(case_["eye_colourway"])
		req.lids = String(case_["lids"])
		req.mouth = String(case_["mouth"])
		var beard := "bare-faced"
		if not String(case_["hair"]).is_empty():
			req.features.append({"item": String(case_["hair"]), "colourway": String(case_["hair_colourway"])})
		if case_["facial_hair"] != null:
			var record: Dictionary = case_["facial_hair"]
			if w.item(String(record["id"])) == null:
				w.add_item(_facial_hair_item(record))
			req.features.append({"item": String(record["id"]), "colourway": "default"})
			beard = "%s (%s)" % [", ".join(record["parts"]), record["length"]]
		var f := LowpolyAssembler.assemble(library, req)
		var want: Array = case_["polygons"]
		var mine := _polygons_of(f, ["head", LowpolyAssembler.FACE_PIECE])
		var label := "%s, %s head, %s skin, %s, mouth %s, %s, %s: %d polygons" % [case_["body"], case_["head"],
			case_["skin"], case_["lids"], case_["mouth"], "hair %s" % case_["hair"] if not String(case_["hair"]).is_empty()
			else "bald", beard, want.size()]
		if mine.size() != want.size():
			t.check(false, label, "%d polygons" % mine.size())
			continue
		var worst := 0.0
		var wrong := ""
		for i in want.size():
			var e: Dictionary = want[i]
			var got: Dictionary = mine[i]
			var corners: PackedInt32Array = got["corners"]
			var pts: Array = e["points"]
			var colour := "#" + (got["colour"] as Color).to_html(false)
			if corners.size() != pts.size() or colour != String(e["colour"]) or String(got["by"]) != String(e["by"]) \
					or bool(got.get("unlit", false)) != bool(e["unlit"]) or String(got["piece"]) != String(e["piece"]):
				wrong = "polygon %d (%s): %d corners, %s by '%s'%s; expected %d, %s by '%s'%s" % [i, e["piece"],
					corners.size(), colour, got["by"], " unlit" if got.get("unlit", false) else "", pts.size(),
					e["colour"], e["by"], " unlit" if e["unlit"] else ""]
				break
			for k in pts.size():
				worst = maxf(worst, Vec64.norm(Vec64.sub(f.point64(corners[k]), _vec64(pts[k]))))
		t.check(wrong.is_empty() and worst <= tolerance, label + " as lowpoly/ draws them (colours, items, corners within %s)" % tolerance,
			wrong if not wrong.is_empty() else "off by %f" % worst)


## What the cross-check cannot say by itself: the face follows the request, and the mouth gives way to a moustache.
static func _face_rules(t: TestReport, library: LowpolyLibrary, wardrobe: Wardrobe) -> void:
	var req := CharacterRequest.new()
	req.body_id = "male_average"
	req.head_shape = "round"
	req.wardrobe = wardrobe
	req.eye_set_id = wardrobe.first_eye_set_id()
	var roles := {}
	for p in _polygons_of(LowpolyAssembler.assemble(library, req), [LowpolyAssembler.FACE_PIECE]):
		roles[String(p["role"])] = int(roles.get(String(p["role"]), 0)) + 1
	t.check(roles.has("white") and roles.has("pupil") and roles.has("line") and roles.has("lid") and roles.has("brow")
		and roles.has("mouth"), "a face has whites, pupils, lash lines, lids, brows and a mouth", str(roles))
	req.mouth = Mouths.OFF
	req.lids = EyeLids.OFF
	var bare := {}
	for p in _polygons_of(LowpolyAssembler.assemble(library, req), [LowpolyAssembler.FACE_PIECE]):
		bare[String(p["role"])] = true
	t.check(not bare.has("mouth") and not bare.has("brow") and not bare.has("lid"),
		"no mouth asked for, none drawn; the eye as drawn has no lids and no brow", str(bare.keys()))
	req.mouth = "smile"
	req.lids = EyeLids.DEFAULT
	var unlit_ok := true
	for p in _polygons_of(LowpolyAssembler.assemble(library, req), [LowpolyAssembler.FACE_PIECE]):
		unlit_ok = unlit_ok and bool(p["unlit"]) == LowpolyFace.UNLIT_ROLES.has(String(p["role"]))
	t.check(unlit_ok, "white, pupil and lash line are drawn unlit; lid, brow and mouth are lit like the skin")
	var rig := LowpolyRig.new()
	rig.build(LowpolyAssembler.assemble(library, req))
	var arrays := rig.mesh_instance.mesh.surface_get_arrays(0)
	var dark := 0
	for colour in (arrays[Mesh.ARRAY_COLOR] as PackedColorArray):
		dark += 1 if colour.a < 0.5 else 0
	t.check(dark > 0, "the rig marks the unlit polygons for its shader (%d corners)" % dark)
	rig.free()
	# a full beard grown out hides the mouth under its moustache; stubble does not
	var full := _facial_hair_item({"id": "test beard", "parts": FacialHairSettings.PARTS, "length": "medium", "draw_order": 65})
	var w := Wardrobe.from_json(wardrobe.to_json())
	w.add_item(full)
	req.wardrobe = w
	req.mouth = "open"
	var top := func(fig: LowpolyFigure) -> float:            # how high the mouth reaches
		var z := -INF
		for p in _polygons_of(fig, [LowpolyAssembler.FACE_PIECE]):
			if String(p["role"]) == "mouth":
				for k in p["corners"]:
					z = maxf(z, fig.points[k].z)
		return z
	var open_top: float = top.call(LowpolyAssembler.assemble(library, req))
	req.features = [{"item": "test beard", "colourway": "default"}]
	var f := LowpolyAssembler.assemble(library, req)
	var lifted := false
	for p in f.polygons:
		lifted = lifted or (String(p["by"]) == "test beard" and p.get("hem", false))
	t.check(lifted, "a medium beard is lifted off the head, with hems where it steps down to the skin")
	var hidden_top: float = top.call(f)
	t.check(hidden_top < open_top - 0.1, "the moustache hides the top of an open mouth (it reaches %.2f, %.2f without it)"
		% [hidden_top, open_top])
	var warned := false
	for warning in f.warnings:
		warned = warned or warning.contains("facial hair")
	t.check(not warned, "facial hair is built on the low-poly figure: no warning", ", ".join(f.warnings))

	# Settings: what an item does not set is the default, as the editor shows it; an unknown old style draws nothing
	# and says so; an item saved before the four parts gets both colour roles.
	var all_parts := LowpolyFacialHair.read({"length": "medium"})
	t.check((all_parts[0] as Array).size() == 4 and String(all_parts[1]) == "medium",
		"facial hair settings an item does not have are their defaults (every part on), as the editor shows them")
	var bogus := LowpolyFacialHair.read({"style": "bogus"})
	t.check((bogus[0] as Array).is_empty() and not (bogus[2] as Array).is_empty(), "an unknown old style draws nothing, and says so")
	var old := GarmentItem.from_json("old_stubble", {"category": "facial_hair", "roles": ["stubble"],
		"colourways": {"default": {"stubble": "@stubble"}}, "specials": [{"type": "facial_hair", "params": {"style": "stubble"}}]},
		"facial_hair")
	t.check(old.roles.has("hair") and old.roles.has("stubble") and String(old.colourways["default"].get("hair", "")) == "@hair"
		and bool(old.special_params(0)["cheeks"]) and String(old.special_params(0)["length"]) == "stubble",
		"an item saved with the old style gets its parts, its length and both colour roles")
	var kept := GarmentItem.from_json("odd", {"category": "facial_hair", "specials": [{"type": "facial_hair",
		"params": {"style": "bogus"}}]}, "facial_hair")
	t.check(String(kept.special_params(0).get("style", "")) == "bogus",
		"an unknown old style is kept, so a save does not lose it")

	# An eye erased in the grid: that eye is left out, the figure stays its own size.
	var erased := Wardrobe.from_json(wardrobe.to_json())
	var eyes := erased.eye_set(erased.first_eye_set_id())
	for cell in eyes.eye_cells(EyeSet.EYE_RIGHT).keys():
		eyes.set_cell(EyeSet.EYE_RIGHT, (cell as Vector2i).x, (cell as Vector2i).y, EyeSet.ROLE_SKIN)
	req.wardrobe = erased
	req.features = []
	req.eye_set_id = eyes.id
	var one_eye := LowpolyAssembler.assemble(library, req)
	t.check(one_eye.bounds().size.length() < 60.0 and not _polygons_of(one_eye, [LowpolyAssembler.FACE_PIECE]).is_empty(),
		"an eye with nothing drawn is left out; the other eye and the face are drawn, the figure keeps its size",
		"bounds %s" % one_eye.bounds())
	req.wardrobe = Wardrobe.new()
	var no_set := LowpolyAssembler.assemble(library, req)
	var said := false
	for warning in no_set.warnings:
		said = said or warning.contains("no eye set")
	t.check(said, "a wardrobe with no eye set: the figure says its face has no eyes")
