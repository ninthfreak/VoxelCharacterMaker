@tool
class_name TestModel
extends RefCounted

## The wardrobe's model: eye sets, features, the region table, special shapes' settings, the file's versions, and
## what the starter wardrobe promises (a dress is an outfit, the toga's top leaves a shoulder bare, overalls are one
## colour). The figure built from them is checked in test_lowpoly.gd.


static func run(t: TestReport, library: LowpolyLibrary) -> void:
	_eye_sets(t, library)
	_wardrobe_v2(t)
	_regions(t, library)
	_special_settings(t)
	_starter_outfits(t, library)


static func _figure(library: LowpolyLibrary, w: Wardrobe, body: String, worn: Array, eye_set: String = "",
		colourway: String = "") -> LowpolyFigure:
	var req := CharacterRequest.make(body, "round", w)
	req.worn = worn
	req.eye_set_id = eye_set
	req.eye_colourway = colourway
	return LowpolyAssembler.assemble(library, req)


# ------------------------------------------------------------- eye sets ----

static func _eye_sets(t: TestReport, library: LowpolyLibrary) -> void:
	t.group("model: the standard eye set")
	var eyes := EyeSet.standard()
	t.check(eyes.eye_cells(EyeSet.EYE_LEFT).size() == EyeSet.STANDARD_CELLS.size() and eyes.is_symmetric(),
		"it is the game's open eye, %d cells, the same for both eyes" % EyeSet.STANDARD_CELLS.size())
	var inside := true
	for cell in eyes.eye_cells(EyeSet.EYE_LEFT).keys():
		var c: Vector2i = cell
		inside = inside and c.x >= 0 and c.x < EyeSet.BOX_W and c.y >= 0 and c.y < EyeSet.BOX_H
	t.check(inside, "every cell is inside the %d by %d eye box" % [EyeSet.BOX_W, EyeSet.BOX_H])

	t.group("model: editing an eye set")
	var edited := eyes.duplicate_as("test", "Test")
	edited.set_cell(EyeSet.EYE_LEFT, 0, 2, EyeSet.ROLE_LINE, true)
	t.check(edited.is_symmetric(), "painting both eyes keeps it symmetric")
	t.check_equal(edited.role_at(EyeSet.EYE_RIGHT, 0, 2), EyeSet.ROLE_LINE, "and the other eye has the cell")
	edited.set_cell(EyeSet.EYE_LEFT, 0, 2, EyeSet.ROLE_SKIN, false)
	t.check(not edited.is_symmetric(), "painting one eye alone breaks symmetry")
	t.check_equal(edited.role_at(EyeSet.EYE_LEFT, 0, 2), EyeSet.ROLE_SKIN, "and skin clears the cell")
	# Files from before the expressions were retired load their neutral drawing.
	var legacy := {"name": "Old", "colourways": {}, "expressions": {
		"neutral": {"left": [[2, 2, "pupil"]], "right": [[2, 2, "pupil"]]},
		"happy": {"left": [[0, 0, "line"]], "right": [[0, 0, "line"]]}}}
	var old := EyeSet.from_json("old", legacy)
	t.check(old.role_at(EyeSet.EYE_LEFT, 2, 2) == EyeSet.ROLE_PUPIL and old.role_at(EyeSet.EYE_LEFT, 0, 0) == EyeSet.ROLE_SKIN,
		"an older file's neutral drawing becomes the eye; its other expressions are dropped")
	var json := edited.to_json()
	t.check(JSON.stringify(EyeSet.from_json("test", json).to_json(), "", true) == JSON.stringify(json, "", true),
		"an eye set round-trips")

	t.group("model: an eye colourway colours the pupils")
	var w := Wardrobe.create_default()
	t.check(w.eye_set("standard") != null, "the default wardrobe has the standard set")
	var set_: EyeSet = w.eye_set("standard")
	set_.add_colourway("blue")
	set_.set_palette_key("blue", EyeSet.ROLE_PUPIL, "eye_blue")
	var blue := false
	for p in _figure(library, w, "male_average", [], "standard", "blue").polygons:
		if String(p.get("role", "")) == EyeSet.ROLE_PUPIL:
			blue = (p["colour"] as Color).is_equal_approx(w.colour("eye_blue"))
	t.check(blue, "the pupils take the colourway's colour from the palette")


# ---------------------------------------------------------- wardrobe v2 ----

static func _wardrobe_v2(t: TestReport) -> void:
	t.group("model: the wardrobe file keeps features and eye sets apart")
	var w := Wardrobe.create_default()
	var json := w.to_json()
	t.check_equal(int(json["version"]), Wardrobe.VERSION, "written as the current version")
	t.check((json["features"] as Dictionary).has("hair"), "hair has its own section")
	t.check(((json["features"] as Dictionary)["hair"] as Dictionary).has("short_crop"), "with the hair styles in it")
	t.check(not (json["items"] as Dictionary).has("short_crop"), "and not among the clothes")
	t.check((json["eye_sets"] as Dictionary).has("standard"), "eye sets have their own")
	var once := w.to_text()
	t.check(Wardrobe.from_json(JSON.parse_string(once)).to_text() == once,
		"a wardrobe with features and eye sets round-trips")
	t.check(w.clothing_ids().has("tunic") and not w.clothing_ids().has("short_crop"), "clothing lists hold only clothing")
	t.check(w.feature_ids("hair").has("short_crop"), "and hair lists only hair")

	t.group("model: version 1 files still load")
	var v1 := {
		"format": Wardrobe.FORMAT, "version": 1,
		"palette": {"ink": "#262a3a"},
		"items": {
			"old_hair": {"name": "Old hair", "category": "hair", "draw_order": 70, "kind": "parametric",
				"edge_style": "soft", "mirror": true, "roles": ["hair"], "colourways": {"default": {"hair": "ink"}},
				"coverage": {"crown.L.F": {"role": "hair", "bulk": 1}}},
			"old_skirt": {"name": "Old skirt", "category": "bottom", "draw_order": 10, "kind": "special",
				"special_type": "skirt", "special_params": {"length": "to_knee", "flare": 2.0}, "edge_style": "soft",
				"mirror": true, "roles": ["cloth"], "colourways": {"default": {"cloth": "ink"}}},
		},
		"outfits": {},
	}
	var migrated := Wardrobe.from_json(v1)
	if t.check(migrated != null, "a version 1 file loads"):
		t.check_equal(migrated.item("old_hair").slot, "hair", "its hair item moves to the hair slot")
		t.check_equal(migrated.item("old_skirt").special_types(), ["skirt"] as Array[String],
			"its special item becomes an item with one special shape")
		t.check_equal(typeof(migrated.item("old_skirt").special_params(0)["flare"]), TYPE_INT,
			"with its settings normalised")


# --------------------------------------------------------------- regions ----

static func _regions(t: TestReport, library: LowpolyLibrary) -> void:
	t.group("model: the region table (SPEC 3.4)")
	var map := library.region_map()
	if not t.check(map != null, "assets/lowpoly/regions.json reads"):
		return
	t.check_equal(map.keys_for_side(RegionMap.SIDE_LEFT).size(), 32, "32 regions a side")
	t.check_equal(map.all_keys().size(), 64, "64 in all")
	var unknown := {}
	for id in library.body_ids():
		for p in library.body(id).polygons:
			if not map.all_keys().has(String(p["region"])):
				unknown[String(p["region"])] = true
	for shape in library.head_shapes():
		for p in library.head(shape).polygons:
			if not map.all_keys().has(String(p["region"])):
				unknown[String(p["region"])] = true
	t.check(unknown.is_empty(), "every polygon of every body and head is in a region the table has",
		", ".join(unknown.keys()))
	t.check_equal(RegionMap.mirror_key("forearm.L"), "forearm.R", "a limb region mirrors")
	t.check_equal(RegionMap.mirror_key("belly.R.F"), "belly.L.F", "a torso region mirrors and keeps its face")


# ------------------------------------------------------ special settings ----

static func _special_settings(t: TestReport) -> void:
	t.group("model: special shapes' settings")
	for type in SpecialItem.types():
		var spec := SpecialItem.param_spec(type)
		var defaults := SpecialItem.default_params(type)
		t.check(not spec.is_empty() and defaults.size() == spec.size(), "%s: every setting has a default" % type)
	var all_built := true
	for type in SpecialItem.types():
		all_built = all_built and SpecialItem.is_built(type)
	t.check(all_built and not SpecialItem.types().has("shape") and not SpecialItem.is_built("shape"),
		"the figure builds every type an item can be given; the old drawn shape is not among them")
	var w := Wardrobe.create_default()
	var cloak := w.item("cloak")
	var again := Wardrobe.from_json(JSON.parse_string(w.to_text()))
	t.check(cloak != null and cloak.special_types().has("hood")
		and JSON.stringify(again.item("cloak").to_json()) == JSON.stringify(cloak.to_json()),
		"the cloak's hood keeps its settings in the file")
	t.check(w.item("long_beard") != null and w.item("long_beard").special_types() == (["long_beard"] as Array[String])
		and w.item("ponytail") != null and w.item("ponytail").special_types() == (["ponytail"] as Array[String]),
		"the starter long beard and ponytail are the shapes of their own")

	t.group("model: old drawn shapes")
	var old := {"name": "Old", "category": "hair", "draw_order": 70, "roles": ["hair"],
		"colourways": {"default": {"hair": "hair_black"}}, "coverage": {}, "specials": [
			{"type": "shape", "params": {"anchor": "nape", "wrap": false, "mirror": true, "cells": [[0, 1, 0, "hair"]]}},
			{"type": "shape", "params": {"anchor": "chin", "wrap": false, "mirror": true, "cells": [[0, 0, 0, "hair"]]}},
			{"type": "shape", "params": {"anchor": "hip", "wrap": true, "mirror": true, "cells": [[0, 0, 0, "hair"]]}}]}
	var read := GarmentItem.from_json("old", old)
	t.check_equal(read.special_types(), ["ponytail", "long_beard", "shape"] as Array[String],
		"one at the nape becomes a ponytail, one under the chin a long beard; any other is kept as it was")
	t.check(JSON.stringify(read.special_params(0)) == JSON.stringify(SpecialItem.default_params("ponytail"))
		and not (read.special_params(2)["cells"] as Array).is_empty(),
		"at the type's own defaults; the one kept keeps its drawing")
	t.check(read.roles.has("tie") and String(read.colourways["default"]["tie"]) == "rust",
		"the item gains the roles its new shapes colour, in every colourway")
	var fresh := GarmentItem.create("plain", "Plain", "accessory")
	fresh.colourways = {"default": {}}
	fresh.add_special("horns")
	t.check(fresh.roles.has("horn") and String(fresh.colourways["default"]["horn"]) == "bone",
		"adding a shape of its own adds the roles it colours")
	t.check(int(SpecialItem.with_defaults("skirt", {"length": "to_ankle"})["flare"]) == 1, "a setting not saved is its default")


# -------------------------------------------------------- starter outfits ----

static func _starter_outfits(t: TestReport, library: LowpolyLibrary) -> void:
	var w := Wardrobe.create_default()
	t.group("model: a dress is an outfit, not an item")
	t.check(w.item("dress") == null, "there is no one-piece dress item")
	for outfit in ["dress", "toga", "robe"]:
		t.check(outfit in w.outfit_names(), "the '%s' outfit exists" % outfit)
	for id in ["skirt", "wrap_skirt", "robe_skirt"]:
		var item := w.item(id)
		t.check(item != null and item.category == "bottom" and item.special_types().has("skirt") and item.has_coverage(),
			"%s is a skirt-only item: hips and a skirt shape" % id)

	t.group("model: the toga's top leaves one shoulder bare")
	var toga := _figure(library, w, "male_average", w.outfit("toga"))
	var left := 0
	var right := 0
	for p in toga.polygons:
		if String(p["by"]) == "one_shoulder_top" and RegionMap.key_band(String(p["region"])) == "upper_chest":
			if RegionMap.key_side(String(p["region"])) == RegionMap.SIDE_LEFT:
				left += 1
			else:
				right += 1
	t.check(left > 0 and right == 0, "the top of the chest is covered on the left only",
		"left %d, right %d" % [left, right])

	t.group("model: overalls are an outfit of three pieces in one colour")
	t.check(w.outfit_names().has("overalls") and w.outfit_names().has("shirt and suspenders"),
		"the starter wardrobe has both outfits", ", ".join(w.outfit_names()))
	var denim := w.colour("denim")
	for id in library.body_ids():
		var o := _figure(library, w, id, w.outfit("overalls"))
		var seen := {}
		var one_colour := true
		for p in o.polygons:
			var by := String(p["by"])
			if by.is_empty():
				continue
			seen[by] = true
			if by in ["bib", "suspenders", "trousers"]:
				one_colour = one_colour and (p["colour"] as Color).is_equal_approx(denim)
		t.check(seen.has("bib") and seen.has("suspenders") and seen.has("trousers") and seen.has("shirt"),
			"%s: trousers, shirt, bib and suspenders all show" % id, ", ".join(seen.keys()))
		t.check(one_colour, "%s: trousers, bib and suspenders are one colour" % id)
