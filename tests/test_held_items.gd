class_name TestHeldItems
extends RefCounted

## Held items (core/held_item_shape.gd): every kind of part a closed piece facing outward that fills its size; the
## same corners as lowpoly/held.py; the file keeps them; a figure holds them at the palm, riding the forearm, the left
## hand the right's mirror image.

const EXPECTED_PATH := "res://tests/lowpoly_expected.json"


static func run(t: TestReport, library: LowpolyLibrary) -> void:
	_shapes(t)
	_against_python(t, library)
	_file(t)
	_holding(t, library)
	_characters(t)


## [closed, every edge met once each way; volume (positive: faces outward); lowest corner; highest corner]
static func _solid(polys: Array) -> Array:
	var edges := {}
	var volume := 0.0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var key := func(p: PackedFloat64Array) -> String:           # to a millionth (and no "-0")
		return "%d,%d,%d" % [roundi(p[0] * 1e6), roundi(p[1] * 1e6), roundi(p[2] * 1e6)]
	for flat in polys:
		var f: PackedFloat64Array = flat
		var n := f.size() / 3
		for i in n:
			var a := Vec64.at(f, i)
			var b := Vec64.at(f, (i + 1) % n)
			var e: String = key.call(a) + ">" + key.call(b)
			edges[e] = int(edges.get(e, 0)) + 1
			var v := Vec64.to_vector3(a)
			lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
			hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
		for i in range(1, n - 1):
			volume += Vec64.dot(Vec64.at(f, 0), Vec64.cross(Vec64.at(f, i), Vec64.at(f, i + 1))) / 6.0
	var closed := not edges.is_empty()
	for e in edges.keys():
		var parts := String(e).split(">")
		closed = closed and int(edges[e]) == 1 and int(edges.get(parts[1] + ">" + parts[0], 0)) == 1
	return [closed, volume, lo, hi]


static func _flats(item: GarmentItem) -> Array:
	var out: Array = []
	for q in HeldItemShape.polygons(item, {}):
		out.append(q["pts"])
	return out


static func _shapes(t: TestReport) -> void:
	t.group("held items: every kind of part is a closed piece, facing outward, filling its size")
	var size := [3.0, 2.0, 5.0]
	for kind in HeldItemShape.KINDS:
		for sides in ([3, 4, 5, 8, 12] if kind in HeldItemShape.ROUND else [8]):
			var part := HeldItemShape.new_part(kind, "main")
			part["size"] = size
			part["sides"] = sides
			var s := _solid(HeldItemShape.part_polygons(part))
			var box: Vector3 = (s[3] as Vector3) - (s[2] as Vector3)
			var fills := box.distance_to(Vector3(size[0], size[1], size[2])) < 1e-9
			var centred := ((s[3] as Vector3) + (s[2] as Vector3)).length() < 1e-9
			t.check(bool(s[0]) and float(s[1]) > 0.0 and fills and centred,
				"%s%s: closed, faces outward, fills 3 x 2 x 5 about its middle" % [kind,
					(" (%d sides)" % sides) if kind in HeldItemShape.ROUND else ""],
				"closed %s, volume %.3f, box %s" % [s[0], s[1], box])
	var cube := _solid(HeldItemShape.part_polygons(HeldItemShape.new_part("box", "main")))
	t.check(absf(float(cube[1]) - 8.0) < 1e-9, "a 2 x 2 x 2 box holds 8 cubic units", "%.4f" % cube[1])
	var wedge := HeldItemShape.new_part("wedge", "main")
	t.check(absf(float(_solid(HeldItemShape.part_polygons(wedge))[1]) - 4.0) < 1e-9, "and a wedge of it half that")

	# a drawn blade: a point at the top, narrower than its guard; and one that crosses itself
	var blade := HeldItemShape.new_part("outline", "main")
	blade["points"] = [[6, 0], [10, 0], [10, 12], [8, 16], [6, 12]]
	var b := _solid(HeldItemShape.part_polygons(blade))
	t.check(bool(b[0]) and float(b[1]) > 0.0, "a drawn blade (five points, any way round) is closed and faces outward")
	blade["points"] = [[6, 12], [8, 16], [10, 12], [10, 0], [6, 0]]
	var b2 := _solid(HeldItemShape.part_polygons(blade))
	t.check(bool(b2[0]) and absf(float(b2[1]) - float(b[1])) < 1e-9, "drawn the other way round, the same piece")
	var axe := HeldItemShape.new_part("outline", "main")
	axe["points"] = [[0, 0], [16, 0], [16, 16], [8, 6], [0, 16]]               # a notch: not convex
	var a := _solid(HeldItemShape.part_polygons(axe))
	t.check(bool(a[0]) and float(a[1]) > 0.0, "an outline with a notch in it (not convex) too")
	var run_ := HeldItemShape.new_part("outline", "main")
	run_["points"] = [[0, 0], [8, 0], [16, 0], [16, 8], [16, 16], [8, 16], [0, 16], [0, 8]]
	t.check(bool(_solid(HeldItemShape.part_polygons(run_))[0]), "an outline with points in a straight run between corners")
	var crossed := HeldItemShape.new_part("outline", "main")
	crossed["points"] = [[0, 0], [16, 16], [16, 0], [0, 16]]
	t.check(HeldItemShape.part_polygons(crossed).size() >= 4, "an outline that crosses itself still makes something")
	var bottle := HeldItemShape.new_part("spin", "main")
	bottle["points"] = [[0, 0], [12, 0], [16, 4], [16, 9], [6, 12], [6, 16], [0, 16]]
	var sp := _solid(HeldItemShape.part_polygons(bottle))
	t.check(bool(sp[0]) and float(sp[1]) > 0.0, "a bottle drawn as half its side view, spun: closed, faces outward")
	bottle["points"] = [[12, 0], [16, 4], [16, 9], [6, 12], [6, 16]]          # not reaching the middle: capped
	t.check(bool(_solid(HeldItemShape.part_polygons(bottle))[0]), "and drawn without touching the middle, capped")

	var turned := HeldItemShape.new_part("box", "main")
	turned["size"] = [1.0, 2.0, 3.0]
	turned["rotation"] = [90.0, 0.0, 0.0]
	turned["position"] = [1.0, 0.0, 0.0]
	var tb := _solid(HeldItemShape.part_polygons(turned))
	t.check(((tb[3] as Vector3) - (tb[2] as Vector3)).distance_to(Vector3(1, 3, 2)) < 1e-9
		and ((tb[3] as Vector3) + (tb[2] as Vector3)).distance_to(Vector3(2, 0, 0)) < 1e-9,
		"a part tipped 90 degrees forward and moved 1 across: its height lies along its depth, its middle at 1")

	var item := GarmentItem.create_held("test", "Test")
	item.parts[0]["position"] = [2.0, 0.0, 0.0]
	item.parts[0]["mirror"] = true
	var both := _solid(_flats(item))
	t.check(bool(both[0]) and absf(float(both[1]) - 16.0) < 1e-9
		and ((both[3] as Vector3) - (both[2] as Vector3)).distance_to(Vector3(6, 2, 2)) < 1e-9,
		"a mirrored part is drawn twice, across the middle, both facing outward")


## Each held item in tests/lowpoly_expected.json, held on a bare body: the same polygons in the same order, each corner
## where lowpoly/held.py puts it.
static func _against_python(t: TestReport, library: LowpolyLibrary) -> void:
	t.group("held items: as lowpoly/held.py makes and holds them")
	var expected := JsonIO.read_dict(EXPECTED_PATH)
	var cases: Array = expected.get("held", [])
	if not t.check(not cases.is_empty(), "tests/lowpoly_expected.json has held items", "run: python3 lowpoly/expected.py"):
		return
	var tolerance := float(expected.get("tolerance", 0.001))
	for c in cases:
		var case_: Dictionary = c
		var item := GarmentItem.from_json(String(case_["id"]), case_["item"], GarmentItem.HELD)
		var f := LowpolyFigure.make(library, String(case_["body"]), String(case_["head"]), Palette.SKIN_MID)
		var first := f.polygons.size()
		HeldItemShape.add_to_figure(f, item, {}, String(case_["side"]))
		var want: Array = case_["polygons"]
		var worst := 0.0
		var where := ""
		if f.polygons.size() - first != want.size():
			worst = INF
			where = "%d polygons, expected %d" % [f.polygons.size() - first, want.size()]
		else:
			for i in want.size():
				var corners: PackedInt32Array = f.polygons[first + i]["corners"]
				var pts: Array = want[i]["points"]
				if corners.size() != pts.size():
					worst = INF
					where = "polygon %d: %d corners, expected %d" % [i, corners.size(), pts.size()]
					break
				for k in pts.size():
					var d := Vec64.norm(Vec64.sub(f.point64(corners[k]), Vec64.v(pts[k][0], pts[k][1], pts[k][2])))
					if d > worst:
						worst = d
						where = "polygon %d corner %d" % [i, k]
		t.check(worst <= tolerance, "%s in the %s hand of the %s: %d polygons, every corner within %s units" % [
			item.name, "left" if case_["side"] == "L" else "right", case_["body"], want.size(), tolerance],
			"off by %f at %s" % [worst, where])


static func _file(t: TestReport) -> void:
	t.group("held items: in the wardrobe file")
	var w := Wardrobe.create_default()
	t.check(w.held_ids().is_empty(), "the starter wardrobe has no held items (the owner makes them)")
	var item := GarmentItem.create_held("short_sword", "Short sword")
	item.parts.append(HeldItemShape.new_part("outline", "detail"))
	item.parts.append(HeldItemShape.new_part("spin", "main"))
	item.grip = {"position": [0.0, 0.0, -2.0], "rotation": [0.0, 15.0, 0.0]}
	item.second_grip = {"position": [0.0, 0.0, -4.0], "rotation": [0.0, 0.0, 0.0]}
	w.add_item(item)
	var data := w.to_json()
	t.check(int(data["version"]) == 4 and (data["held_items"] as Dictionary).has("short_sword")
		and not (data["items"] as Dictionary).has("short_sword"),
		"a held item is kept in its own section, not among the clothes or features")
	var back := Wardrobe.from_json(JSON.parse_string(JsonIO.to_text(data)))
	t.check(back != null and back.item("short_sword") != null and back.item("short_sword").is_held()
		and back.held_ids() == ["short_sword"], "and read back as a held item")
	t.check(back != null and JsonIO.to_text(back.to_json()) == JsonIO.to_text(data), "save, load, save: the same file")
	var raw := {"kind": "nonsense", "size": [-1, 0.0, 999], "sides": 99, "points": [[-5, 40], [3, 3]], "mirror": "yes"}
	var clean := HeldItemShape.clean_part(raw, "main")
	t.check(clean["kind"] == "box" and clean["size"] == [HeldItemShape.MIN_SIZE, HeldItemShape.MIN_SIZE, 999.0]
		and clean["sides"] == HeldItemShape.MAX_SIDES and clean["mirror"] == false and clean["role"] == "main",
		"a part read with nonsense in it comes back within its limits")
	var drawn := HeldItemShape.clean_part({"kind": "outline", "points": [[-5, 40], [3, 3], "x"]}, "main")
	t.check(drawn["points"] == [[0, HeldItemShape.GRID], [3, 3]], "a drawing's points are kept on the grid")
	var old := w.to_json()
	old["version"] = 3
	old.erase("held_items")
	t.check(Wardrobe.from_json(old) != null and Wardrobe.from_json(old).held_ids().is_empty(),
		"a version 3 file (before held items) still opens")
	item.rename_role("main", "blade")
	t.check(String(item.parts[0]["role"]) == "blade" and String(item.parts[2]["role"]) == "blade",
		"renaming a role renames it on the parts")
	item.remove_role("blade")
	t.check(String(item.parts[0]["role"]) == "detail", "and removing one gives its parts another")


## A held item: a sword made standing up (a grip, a guard across it, a blade above), the grip at its middle.
static func _sword() -> GarmentItem:
	var sword := GarmentItem.create_held("test_sword", "Test sword")
	sword.parts = [HeldItemShape.new_part("cylinder", "detail"), HeldItemShape.new_part("box", "detail"),
		HeldItemShape.new_part("outline", "main")]
	sword.parts[0]["size"] = [1.0, 1.0, 4.0]
	sword.parts[1]["size"] = [5.0, 1.0, 0.75]
	sword.parts[1]["position"] = [0.0, 0.0, 2.25]
	sword.parts[2]["size"] = [2.0, 0.5, 14.0]
	sword.parts[2]["position"] = [0.0, 0.0, 9.5]
	sword.parts[2]["points"] = [[0, 0], [16, 0], [16, 13], [8, 16], [0, 13]]
	return sword


static func _holding(t: TestReport, library: LowpolyLibrary) -> void:
	t.group("held items: held in a hand")
	var w := Wardrobe.create_default()
	var sword := _sword()
	w.add_item(sword)
	var req := w.character("villager").make_request(w)
	var bare := LowpolyAssembler.assemble(library, req)
	req.held = [{"item": sword.id, "colourway": "", "side": "R"}]
	var f := LowpolyAssembler.assemble(library, req)
	var held: Array = []
	for p in f.polygons:
		if String(p["piece"]) == HeldItemShape.PIECE:
			held.append(p)
	t.check(held.size() == HeldItemShape.polygons(sword, {}).size() and f.polygons.size() == bare.polygons.size() + held.size(),
		"the villager holding a sword in the right hand: the sword's polygons added, nothing else changed")
	var rides := true
	var tip := Vec64.v(0, INF, 0)                  # the corner furthest ahead (-y)
	var palm := HeldItemShape.palm(f, "R")
	for p in held:
		for k in p["corners"]:
			rides = rides and f.weights[k] == {"forearm_R": 1.0}
			var at := f.point64(k)
			if at[1] < tip[1]:
				tip = at
	t.check(rides, "every corner of it rides the right forearm")
	t.check(palm[0] < 12.0 and tip[1] < palm[1] - 10.0 and absf(tip[0] - palm[0]) < 0.5 and absf(tip[2] - palm[2]) < 0.5,
		"its grip is at the right palm, and a sword made standing up points straight ahead",
		"palm %s, tip %s" % [palm, tip])
	t.check(String(held[0]["region"]).is_empty() and String(held[0]["by"]) == sword.id and String(held[0]["at"]) == "R",
		"its polygons are no body region (a click on one picks nothing), and say what they are")
	var colours := {}
	for p in held:
		colours[p["colour"]] = true
	t.check(colours.size() == 2, "drawn in its colourway's two colours")

	req.held = [{"item": sword.id, "colourway": "", "side": "L"}]
	var fl := LowpolyAssembler.assemble(library, req)
	var left_palm := HeldItemShape.palm(fl, "L")
	var right_pts: Array = []
	var left_pts: Array = []
	var left_flats: Array = []
	for p in f.polygons:
		if String(p["piece"]) == HeldItemShape.PIECE:
			for k in p["corners"]:
				right_pts.append(Vec64.sub(f.point64(k), palm))
	for p in fl.polygons:
		if String(p["piece"]) == HeldItemShape.PIECE:
			var flat := PackedFloat64Array()
			for k in p["corners"]:
				flat.append_array(fl.point64(k))
			left_flats.append(flat)
	var mirror_ok := true
	var n := 0
	for p in fl.polygons:
		if String(p["piece"]) == HeldItemShape.PIECE:
			var corners: PackedInt32Array = p["corners"]
			for i in corners.size():
				left_pts.append(Vec64.sub(fl.point64(corners[corners.size() - 1 - i]), left_palm))
	for i in mini(right_pts.size(), left_pts.size()):
		var r: PackedFloat64Array = right_pts[i]
		mirror_ok = mirror_ok and Vec64.norm(Vec64.sub(left_pts[i], Vec64.v(-r[0], r[1], r[2]))) < 1e-9
		n += 1
	t.check(mirror_ok and n == right_pts.size() and right_pts.size() == left_pts.size(),
		"in the left hand: the mirror image of the right hand's")
	t.check(float(_solid(left_flats)[1]) > 0.0, "and facing outward there too")

	req.held = [{"item": sword.id, "colourway": "", "side": "R"}, {"item": sword.id, "colourway": "", "side": "R"}]
	var two := LowpolyAssembler.assemble(library, req)
	var count := 0
	for p in two.polygons:
		count += 1 if String(p["piece"]) == HeldItemShape.PIECE else 0
	t.check(count == held.size() and not two.warnings.is_empty(), "two items for one hand: the first is held, and a warning")

	var bottle := GarmentItem.create_held("test_bottle", "Test bottle")
	bottle.parts[0] = HeldItemShape.new_part("cylinder", "main")
	bottle.parts[0]["size"] = [2.0, 2.0, 4.0]
	bottle.grip["rotation"] = [0.0, 90.0, 0.0]
	var upright := true
	for side in ["R", "L"]:
		var fb := LowpolyFigure.make(library, "male_average", "round", Palette.SKIN_MID)
		var at := HeldItemShape.palm(fb, side)
		var placed := HeldItemShape.in_hand(bottle, at, side)
		var top := Vec64.add(Vec64.apply(placed[0], Vec64.v(0, 0, 2)), placed[1])
		upright = upright and Vec64.norm(Vec64.sub(top, Vec64.add(at, Vec64.v(0, 0, 2)))) < 1e-9
	t.check(upright, "a bottle with its grip turned 90 degrees sideways stands upright, in either hand")

	var rig := LowpolyRig.new()
	rig.build(f, Poses.get_pose(Poses.SITTING))
	var posed := rig.posed_points()
	var keep := true
	var corners_held: Array = []
	for p in held:
		for k in p["corners"]:
			corners_held.append(k)
	for i in range(0, corners_held.size() - 1, 7):
		var a: int = corners_held[i]
		var b: int = corners_held[i + 1]
		keep = keep and absf((posed[a] - posed[b]).length() - (f.points[a] - f.points[b]).length()) < 1e-3
	t.check(keep, "posed (sitting), it moves with the forearm as one solid piece")
	rig.free()


static func _characters(t: TestReport) -> void:
	t.group("held items: saved characters and the game")
	var w := Wardrobe.create_default()
	var sword := _sword()
	w.add_item(sword)
	var who := w.character("villager")
	who.right_hand_id = sword.id
	var req := who.make_request(w)
	t.check(req.held == [{"item": sword.id, "colourway": "default", "side": "R"}],
		"a saved character's right hand: held, in the item's first colourway")
	var back := CharacterDef.from_json(who.id, who.to_json())
	t.check(back.right_hand_id == sword.id and back.same_as(who), "kept in the file")
	t.check(who.uses_item(sword.id), "the character uses the item")
	var copy := who.duplicate_as("copy", "Copy")
	copy.right_hand_colourway = "nonsense"
	t.check(copy.looks_like(who, w), "a colourway the item lacks looks like the item's first")
	copy.left_hand_id = "boots"
	t.check(copy.make_request(w).held.size() == 1 and copy.looks_like(who, w),
		"clothing put in a hand is not held, and is as if the hand were empty")
	w.remove_item(sword.id)
	t.check(who.right_hand_id.is_empty() and who.make_request(w).held.is_empty(),
		"deleting the item empties the hand")

	var w2 := Wardrobe.create_default()
	w2.add_item(_sword())
	var game := GameCharacter.new()
	game.setup(w2, "villager")
	var dressed: Array = game._dressed
	var before := game.figure.polygons.size()
	t.check(game.hold("test_sword", "R") and game.held_in("R") == "test_sword"
		and game.figure.polygons.size() == before + HeldItemShape.polygons(w2.item("test_sword"), {}).size()
		and is_same(game._dressed, dressed), "the game: a character takes a sword in its right hand, without dressing again")
	t.check(w2.character("villager").right_hand_id.is_empty(), "the saved character is not changed")
	game.release("R")
	t.check(game.held_in("R").is_empty() and game.figure.polygons.size() == before, "and puts it down")
	t.check(not game.hold("boots", "R") and not game.hold("test_sword", "X"), "only a held item, in a hand that exists")
	game.free()
