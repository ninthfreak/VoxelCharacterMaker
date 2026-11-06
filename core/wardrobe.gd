@tool
class_name Wardrobe
extends RefCounted

## The one wardrobe file (SPEC.md section 7.1).
##
## Everything a character wears or grows lives here: the palette, every
## clothing item, every feature (hair styles, facial hair), every eye set, and
## the saved outfits. Bodies and heads are separate library files.
##
## Clothing and features are both GarmentItems -- features "work like clothes"
## -- but they are kept in their own sections, because they are used
## differently: clothes are worn in any number, a feature fills a slot.
##
## SPEC section 12 requires that save -> load -> save be identical. That holds
## because JsonIO sorts every key, colours are stored as "#rrggbb" rather than
## floats, free-form numbers are normalised, and nothing here depends on
## dictionary insertion order.
##
## File versions:
##   1  palette, items, outfits. Hair was a clothing category.
##   2  adds "features" (by slot) and "eye_sets"; items may carry several
##      special shapes alongside their regions. Version 1 files load, and hair
##      items move to the hair slot.

const FORMAT := "voxel_wardrobe"
const VERSION := 2
const DEFAULT_EXTENSION := "vxwardrobe.json"

signal changed

## palette colour name -> Color
var palette: Dictionary = {}

## item id -> GarmentItem, clothing AND features. One namespace, so an id is
## unique across both and the assembler finds either the same way.
var items: Dictionary = {}

## eye set id -> EyeSet
var eye_sets: Dictionary = {}

## outfit name -> Array of {"item": id, "colourway": name}
var outfits: Dictionary = {}

var path: String = ""
var dirty: bool = false


## A wardrobe with starter content. With the asset library, the shipped
## expressions become the "Standard" eye set; without it there is no eye set and
## the assembler falls back to the library's faces, which is what the body
## workspace shows anyway.
static func create_default(library: AssetLibrary = null) -> Wardrobe:
	var w := Wardrobe.new()
	w.palette = Palette.default_wardrobe_colours()
	w._add_starter_clothes()
	w._add_starter_features()
	if library != null:
		var standard := EyeSet.from_library(library)
		w.eye_sets[standard.id] = standard
	w.dirty = false
	return w


func _add_starter_clothes() -> void:
	var tunic := GarmentItem.create("tunic", "Tunic", "top")
	tunic.roles = ["cloth", "trim"]
	tunic.colourways = {
		"default": {"cloth": "teal", "trim": "bone"},
		"rust": {"cloth": "rust", "trim": "ochre"},
	}
	# Left side only: mirror is on, so the right side follows.
	for key in ["upper_chest.L.F", "upper_chest.L.B", "lower_chest.L.F",
			"lower_chest.L.B", "belly.L.F", "belly.L.B"]:
		tunic.set_region(key, "cloth", 1)
	tunic.set_region("collar.L.F", "trim", 1)
	tunic.set_region("collar.L.B", "trim", 1)
	tunic.set_region("shoulder.L", "cloth", 1)
	tunic.set_region("upper_arm.L", "cloth", 1)
	tunic.set_region("waist.L.F", "trim", 1)
	tunic.set_region("waist.L.B", "trim", 1)
	add_item(tunic)

	var trousers := GarmentItem.create("trousers", "Trousers", "bottom")
	trousers.roles = ["cloth", "trim"]
	trousers.colourways = {"default": {"cloth": "slate", "trim": "ink"}}
	for key in ["hips.L.F", "hips.L.B", "upper_thigh.L", "lower_thigh.L", "shin.L"]:
		trousers.set_region(key, "cloth", 1)
	trousers.set_region("knee.L", "trim", 1)
	trousers.set_region("ankle.L", "trim", 1)
	add_item(trousers)

	var boots := GarmentItem.create("boots", "Boots", "feet")
	boots.edge_style = BulkBuilder.EdgeStyle.HARD
	boots.roles = ["leather"]
	boots.colourways = {"default": {"leather": "ink"}}
	boots.set_region("foot.L", "leather", 1)
	boots.set_region("ankle.L", "leather", 1)
	add_item(boots)

	# A dress is a bodice of regions plus a skirt shape: one item, both kinds.
	var dress := GarmentItem.create("dress", "Dress", "top")
	dress.roles = ["cloth", "trim", "hem"]
	dress.colourways = {
		"default": {"cloth": "plum", "trim": "bone", "hem": "ochre"},
		"moss": {"cloth": "moss", "trim": "bone", "hem": "ink"},
	}
	for key in ["upper_chest.L.F", "upper_chest.L.B", "lower_chest.L.F",
			"lower_chest.L.B", "belly.L.F", "belly.L.B", "hips.L.F", "hips.L.B",
			"shoulder.L"]:
		dress.set_region(key, "cloth", 1)
	dress.set_region("collar.L.F", "trim", 1)
	dress.set_region("collar.L.B", "trim", 1)
	dress.set_region("waist.L.F", "trim", 1)
	dress.set_region("waist.L.B", "trim", 1)
	var skirt_at := dress.add_special("skirt")
	dress.set_special_param(skirt_at, "length", "to_shin")
	dress.set_special_param(skirt_at, "waistband", false)
	add_item(dress)

	# A cloak: a hood and a cape, both anchored, plus a collar of regions.
	var cloak := GarmentItem.create("cloak", "Hooded cloak", "back")
	cloak.roles = ["cloth", "lining", "hem"]
	cloak.colourways = {"default": {"cloth": "ink", "lining": "rust", "hem": "slate"}}
	cloak.set_region("collar.L.F", "cloth", 1)
	cloak.set_region("collar.L.B", "cloth", 1)
	cloak.add_special("cape")
	var hood_at := cloak.add_special("hood")
	cloak.set_special_param(hood_at, "raised", false)
	add_item(cloak)

	outfits["everyday"] = [
		{"item": "boots", "colourway": "default"},
		{"item": "trousers", "colourway": "default"},
		{"item": "tunic", "colourway": "default"},
	]
	outfits["travelling"] = [
		{"item": "boots", "colourway": "default"},
		{"item": "cloak", "colourway": "default"},
		{"item": "trousers", "colourway": "default"},
		{"item": "tunic", "colourway": "rust"},
	]
	outfits["dressed up"] = [
		{"item": "boots", "colourway": "default"},
		{"item": "dress", "colourway": "default"},
	]


func _add_starter_features() -> void:
	# Hair can only use the head's BACK and CROWN regions without covering the
	# eyes: the front of mid_head (z32-36) contains the eye rows (z30-34). That
	# is a real limit of the region bands for faces; see docs/NOTES.md.
	var crop := GarmentItem.create_feature("short_crop", "Short crop", "hair")
	crop.roles = ["hair"]
	crop.colourways = {"default": {"hair": "hair_brown"}, "black": {"hair": "hair_black"},
		"auburn": {"hair": "hair_auburn"}}
	for key in ["crown.L.F", "crown.L.B", "mid_head.L.B", "lower_head.L.B"]:
		crop.set_region(key, "hair", 1)
	add_item(crop)

	var tail := GarmentItem.create_feature("ponytail", "Ponytail", "hair")
	tail.roles = ["hair", "tie"]
	tail.colourways = {"default": {"hair": "hair_black", "tie": "rust"}}
	for key in ["crown.L.F", "crown.L.B", "mid_head.L.B", "lower_head.L.B"]:
		tail.set_region(key, "hair", 1)
	var at := tail.add_special("shape")
	tail.set_special_param(at, "anchor", "nape")
	tail.set_special_param(at, "wrap", false)
	tail.set_special_param(at, "mirror", true)
	# Two columns each side of the mirror line: four voxels wide. One column
	# (two wide) read as a string rather than a ponytail.
	var cells: Array = []
	for a in [0, 1]:
		cells.append([a, 1, 4, "tie"])
		cells.append([a, 2, 4, "tie"])
		for c in [3, 2, 1, 0, -1, -2, -3, -4]:
			if a == 1 and c < -2:
				continue  # taper toward the tip
			cells.append([a, 1, c, "hair"])
			if c > -3:
				cells.append([a, 2, c, "hair"])
	tail.set_special_param(at, "cells", cells)
	add_item(tail)

	# Facial hair cannot be regions at all: lower_head (z28-31) also contains
	# the bottom two eye rows. So a beard is a hand-drawn shape anchored to the
	# face and wrapped onto it, which fits every head's jaw line.
	var beard := GarmentItem.create_feature("short_beard", "Short beard", "facial_hair")
	beard.roles = ["hair"]
	beard.colourways = {"default": {"hair": "hair_brown"}, "black": {"hair": "hair_black"}}
	var b := beard.add_special("shape")
	beard.set_special_param(b, "anchor", "face")
	beard.set_special_param(b, "wrap", true)
	beard.set_special_param(b, "mirror", true)
	var beard_cells: Array = []
	for a in range(0, 7):
		beard_cells.append([a, 0, -2, "hair"])
		beard_cells.append([a, 0, -1, "hair"])
	for side in [5, 6]:
		beard_cells.append([side, 0, 0, "hair"])
		beard_cells.append([side, 0, 1, "hair"])
	beard_cells.append([0, 1, -2, "hair"])
	beard.set_special_param(b, "cells", beard_cells)
	add_item(beard)

	var tache := GarmentItem.create_feature("moustache", "Moustache", "facial_hair")
	tache.roles = ["hair"]
	tache.colourways = {"default": {"hair": "hair_brown"}}
	var m := tache.add_special("shape")
	tache.set_special_param(m, "anchor", "face")
	tache.set_special_param(m, "wrap", true)
	tache.set_special_param(m, "mirror", true)
	tache.set_special_param(m, "cells", [[0, 0, -1, "hair"], [1, 0, -1, "hair"],
		[2, 0, -1, "hair"], [3, 0, -2, "hair"]])
	add_item(tache)


# -------------------------------------------------------------------- items --

func add_item(item: GarmentItem) -> void:
	items[item.id] = item
	mark_dirty()


func remove_item(item_id: String) -> void:
	items.erase(item_id)
	for outfit in outfits.keys():
		var worn: Array = outfits[outfit]
		for i in range(worn.size() - 1, -1, -1):
			if String((worn[i] as Dictionary)["item"]) == item_id:
				worn.remove_at(i)
	mark_dirty()


func item(item_id: String) -> GarmentItem:
	return items.get(item_id, null) as GarmentItem


## Ids of the items in one section -- clothing ("") or a feature slot -- by draw
## order then name, so lists are stable and read the same way every time.
func item_ids_by_draw_order(p_slot: String = GarmentItem.CLOTHES) -> Array[String]:
	var ids: Array[String] = []
	for k in items.keys():
		if (items[k] as GarmentItem).slot == p_slot:
			ids.append(String(k))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ia: GarmentItem = items[a]
		var ib: GarmentItem = items[b]
		if ia.draw_order != ib.draw_order:
			return ia.draw_order < ib.draw_order
		return ia.name.naturalnocasecmp_to(ib.name) < 0)
	return ids


func clothing_ids() -> Array[String]:
	return item_ids_by_draw_order(GarmentItem.CLOTHES)


func feature_ids(p_slot: String) -> Array[String]:
	return item_ids_by_draw_order(p_slot)


func unique_item_id(base: String) -> String:
	return _unique(base, items, "item")


func _unique(base: String, taken: Dictionary, fallback: String) -> String:
	var stem := base.to_snake_case()
	if stem.is_empty():
		stem = fallback
	if not taken.has(stem):
		return stem
	var n := 2
	while taken.has("%s_%d" % [stem, n]):
		n += 1
	return "%s_%d" % [stem, n]


# ----------------------------------------------------------------- eye sets --

func add_eye_set(eyes: EyeSet) -> void:
	eye_sets[eyes.id] = eyes
	mark_dirty()


func remove_eye_set(eye_set_id: String) -> void:
	eye_sets.erase(eye_set_id)
	mark_dirty()


func eye_set(eye_set_id: String) -> EyeSet:
	return eye_sets.get(eye_set_id, null) as EyeSet


func eye_set_ids() -> Array[String]:
	var out: Array[String] = []
	for k in eye_sets.keys():
		out.append(String(k))
	out.sort_custom(func(a: String, b: String) -> bool:
		return (eye_sets[a] as EyeSet).name.naturalnocasecmp_to(
			(eye_sets[b] as EyeSet).name) < 0)
	return out


func first_eye_set_id() -> String:
	var ids := eye_set_ids()
	return ids[0] if not ids.is_empty() else ""


func unique_eye_set_id(base: String) -> String:
	return _unique(base, eye_sets, "eyes")


# ------------------------------------------------------------------ palette --

func palette_names() -> Array[String]:
	var out: Array[String] = []
	for k in palette.keys():
		out.append(String(k))
	out.sort()
	return out


## Resolve a palette colour name. Unknown names render magenta on purpose: a
## missing colour should be obvious, not quietly plausible.
func colour(palette_key: String) -> Color:
	if palette.has(palette_key):
		return palette[palette_key]
	return Color.MAGENTA


func set_colour(palette_key: String, value: Color) -> void:
	palette[palette_key] = value
	mark_dirty()


func remove_colour(palette_key: String) -> void:
	palette.erase(palette_key)
	mark_dirty()


## The light/mid/dark triple an item role resolves to in a colourway.
func tones_for(item_id: String, colourway: String, role: String) -> Array[Color]:
	var it := item(item_id)
	if it == null:
		return Palette.garment_tones(Color.MAGENTA)
	var key := it.palette_key_for(colourway, role)
	return Palette.garment_tones(colour(key))


## An eye role's flat colour in an eye set's colourway. Eyes are not toned:
## shading a 4x5 eye would only muddy it.
func eye_colour(eye_set_id: String, colourway: String, role: String) -> Color:
	var eyes := eye_set(eye_set_id)
	if eyes == null:
		return Color.MAGENTA
	var way := colourway if eyes.colourways.has(colourway) else eyes.first_colourway()
	return colour(eyes.palette_key_for(way, role))


# ------------------------------------------------------------------ outfits --

func outfit_names() -> Array[String]:
	var out: Array[String] = []
	for k in outfits.keys():
		out.append(String(k))
	out.sort()
	return out


## An outfit as a list of {"item": id, "colourway": name}, items missing from
## the wardrobe dropped.
func outfit(name: String) -> Array:
	var out: Array = []
	for entry in (outfits.get(name, []) as Array):
		var e: Dictionary = entry
		var item_id := String(e["item"])
		if not items.has(item_id):
			continue
		var it: GarmentItem = items[item_id]
		var colourway := String(e.get("colourway", it.first_colourway()))
		if not it.has_colourway(colourway):
			colourway = it.first_colourway()
		out.append({"item": item_id, "colourway": colourway})
	return out


func save_outfit(name: String, worn: Array) -> void:
	var copy: Array = []
	for entry in worn:
		var e: Dictionary = entry
		copy.append({"item": String(e["item"]), "colourway": String(e["colourway"])})
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["item"]) < String(b["item"]))
	outfits[name] = copy
	mark_dirty()


func remove_outfit(name: String) -> void:
	outfits.erase(name)
	mark_dirty()


# --------------------------------------------------------------- JSON I/O ---

func to_json() -> Dictionary:
	var palette_out := {}
	for key in palette.keys():
		palette_out[String(key)] = JsonIO.colour_to_hex(palette[key])

	var clothes_out := {}
	var features_out := {}
	for slot in GarmentItem.FEATURE_SLOTS:
		features_out[slot] = {}
	for item_id in items.keys():
		var it: GarmentItem = items[item_id]
		if it.is_feature():
			if not features_out.has(it.slot):
				features_out[it.slot] = {}
			(features_out[it.slot] as Dictionary)[String(item_id)] = it.to_json()
		else:
			clothes_out[String(item_id)] = it.to_json()

	var eyes_out := {}
	for set_id in eye_sets.keys():
		eyes_out[String(set_id)] = (eye_sets[set_id] as EyeSet).to_json()

	var outfits_out := {}
	for name in outfits.keys():
		var worn: Array = []
		for entry in (outfits[name] as Array):
			var e: Dictionary = entry
			worn.append({"item": String(e["item"]), "colourway": String(e["colourway"])})
		outfits_out[String(name)] = worn

	return {
		"format": FORMAT,
		"version": VERSION,
		"palette": palette_out,
		"items": clothes_out,
		"features": features_out,
		"eye_sets": eyes_out,
		"outfits": outfits_out,
	}


static func from_json(data: Dictionary) -> Wardrobe:
	if String(data.get("format", "")) != FORMAT:
		push_error("not a wardrobe file (format is '%s')" % data.get("format", ""))
		return null
	var version := int(data.get("version", 0))
	if version > VERSION:
		push_error("wardrobe file version %d is newer than this build understands (%d)"
			% [version, VERSION])
		return null

	var w := Wardrobe.new()
	var raw_palette: Dictionary = data.get("palette", {})
	for key in raw_palette.keys():
		w.palette[String(key)] = JsonIO.hex_to_colour(String(raw_palette[key]))

	var raw_items: Dictionary = data.get("items", {})
	for item_id in raw_items.keys():
		var raw: Dictionary = raw_items[item_id]
		# Version 1 kept hair among the clothes; it is a feature slot now.
		var slot := GarmentItem.CLOTHES
		if version < 2 and String(raw.get("category", "")) == "hair":
			slot = "hair"
		w.items[String(item_id)] = GarmentItem.from_json(String(item_id), raw, slot)

	var raw_features: Dictionary = data.get("features", {})
	for slot_name in raw_features.keys():
		var section: Dictionary = raw_features[slot_name]
		for item_id2 in section.keys():
			w.items[String(item_id2)] = GarmentItem.from_json(
				String(item_id2), section[item_id2], String(slot_name))

	var raw_eyes: Dictionary = data.get("eye_sets", {})
	for set_id in raw_eyes.keys():
		w.eye_sets[String(set_id)] = EyeSet.from_json(String(set_id), raw_eyes[set_id])

	var raw_outfits: Dictionary = data.get("outfits", {})
	for name in raw_outfits.keys():
		var worn: Array = []
		for entry in (raw_outfits[name] as Array):
			var e: Dictionary = entry
			worn.append({
				"item": String(e.get("item", "")),
				"colourway": String(e.get("colourway", GarmentItem.DEFAULT_COLOURWAY)),
			})
		w.outfits[String(name)] = worn

	w.dirty = false
	return w


static func load_from(p_path: String) -> Wardrobe:
	var data := JsonIO.read_dict(p_path)
	if data.is_empty():
		return null
	var w := Wardrobe.from_json(data)
	if w != null:
		w.path = p_path
	return w


## Save to `path`, or to a new path. Returns "" on success, else the error.
func save_to(p_path: String = "") -> String:
	var target := p_path if not p_path.is_empty() else path
	if target.is_empty():
		return "no path to save to"
	var err := JsonIO.write_dict(target, to_json())
	if not err.is_empty():
		return err
	path = target
	dirty = false
	changed.emit()
	return ""


## The serialised text, for the unsaved-changes check and the round-trip test.
func to_text() -> String:
	return JsonIO.to_text(to_json())


func mark_dirty() -> void:
	dirty = true
	changed.emit()


func display_path() -> String:
	if path.is_empty():
		return "(unsaved wardrobe)"
	return path.get_file()
