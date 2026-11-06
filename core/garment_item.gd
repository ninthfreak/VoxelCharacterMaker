@tool
class_name GarmentItem
extends RefCounted

## One wearable item: clothing, or a feature such as a hair style (SPEC.md 7.2).
##
## Every item has the full parametric definition -- the regions it covers, each
## with a colour role and a bulk -- and, as well as that, any number of SPECIAL
## SHAPES: generated pieces anchored to the body at specific points whose shape
## is not otherwise derived from it (a skirt, a hood, a beard, a bun). A dress is
## therefore a bodice of regions plus a skirt shape; a hooded cloak is a hood and
## a cape. An item is never "parametric OR special" -- that was the first
## version's model, and it could not express a dress.
##
## The LEFT side is authored and the mirror flag says whether the right side
## mirrors it or has its own definition (sashes, one-shouldered tops). Turning
## mirror on does not delete right-side work; it is simply ignored while on.
##
## Features (hair, facial hair) are items like any other, but they live in
## their own section of the wardrobe file and fill a SLOT: a character has one
## hair style, chosen, rather than any number of worn items.

## Clothing categories and their default draw order; higher draws on top
## (SPEC 7.2).
const CATEGORY_DRAW_ORDER := {
	"hat": 80,
	"back": 60,
	"accessory": 55,
	"belt": 50,
	"other": 45,
	"hands": 40,
	"top": 30,
	"feet": 20,
	"bottom": 10,
}

## Listed top-down, matching draw order, so the editor's category menu reads
## the same way the figure stacks.
const CATEGORIES: Array[String] = [
	"hat", "back", "accessory", "belt", "other", "hands", "top", "feet", "bottom",
]

## Feature slots and their draw order. Hair sits under hats (80), facial hair
## under hair so a long fringe falls over facial hair, and both over clothes.
## The face itself draws below everything (CharacterAssembler.FACE_DRAW_ORDER).
const SLOT_DRAW_ORDER := {
	"hair": 70,
	"face_accessory": 67,
	"facial_hair": 65,
}
## Hair and facial hair: one per character, "none" allowed. A face accessory
## (a long beard...) is optional and also one at a time, so it is a slot too.
const FEATURE_SLOTS: Array[String] = ["hair", "facial_hair", "face_accessory"]

const CLOTHES := ""
const DEFAULT_COLOURWAY := "default"
const DEFAULT_ROLE := "cloth"

var id: String = ""
var name: String = ""
## "" for clothing, else the feature slot it fills.
var slot: String = CLOTHES
var category: String = "other"
var draw_order: int = 45
var edge_style: int = BulkBuilder.EdgeStyle.SOFT
var mirror: bool = true

## Named parts of the design: cloth, trim, buckle...
var roles: Array[String] = [DEFAULT_ROLE]

## colourway name -> {role name -> palette colour name}
var colourways: Dictionary = {}

## region key -> {"role": String, "bulk": int}
var coverage: Dictionary = {}

## Special shapes: Array of {"type": String, "params": Dictionary}
var specials: Array = []


static func create(p_id: String, p_name: String, p_category: String = "other") -> GarmentItem:
	var item := GarmentItem.new()
	item.id = p_id
	item.name = p_name
	item.category = p_category
	item.draw_order = default_draw_order(p_category)
	item.colourways = {DEFAULT_COLOURWAY: {DEFAULT_ROLE: "ink"}}
	return item


## A feature item for a slot: hair, facial hair.
static func create_feature(p_id: String, p_name: String, p_slot: String) -> GarmentItem:
	var item := create(p_id, p_name, p_slot)
	item.slot = p_slot
	item.draw_order = int(SLOT_DRAW_ORDER.get(p_slot, 70))
	return item


static func default_draw_order(p_category: String) -> int:
	if SLOT_DRAW_ORDER.has(p_category):
		return int(SLOT_DRAW_ORDER[p_category])
	return int(CATEGORY_DRAW_ORDER.get(p_category, 45))


static func slot_label(p_slot: String) -> String:
	match p_slot:
		"hair": return "Hair"
		"facial_hair": return "Facial hair"
		"face_accessory": return "Face accessory"
		CLOTHES: return "Clothes"
	return p_slot.capitalize()


func is_feature() -> bool:
	return slot != CLOTHES


## True when the item has any special shape.
func is_special() -> bool:
	return not specials.is_empty()


func has_coverage() -> bool:
	return not coverage.is_empty()


# ---------------------------------------------------------------- coverage --

## Set a region's role and bulk. Bulk 0 means recolour only.
func set_region(region_key: String, role: String, bulk: int) -> void:
	coverage[region_key] = {"role": role, "bulk": maxi(0, bulk)}


func clear_region(region_key: String) -> void:
	coverage.erase(region_key)


func covers(region_key: String) -> bool:
	return effective_coverage().has(region_key)


func role_for(region_key: String) -> String:
	var c := effective_coverage()
	if not c.has(region_key):
		return ""
	return String((c[region_key] as Dictionary)["role"])


## How far this item reaches in a region, which is what layering compares.
func bulk_for(region_key: String) -> int:
	var c := effective_coverage()
	if not c.has(region_key):
		return -1
	return int((c[region_key] as Dictionary)["bulk"])


## Coverage with the mirror flag applied: when mirror is on, the authored left
## side is reflected onto the right and any stored right-side entries are
## ignored (but kept on disk, so toggling the flag is not destructive).
func effective_coverage() -> Dictionary:
	if not mirror:
		return coverage
	var out := {}
	for key in coverage.keys():
		var k := String(key)
		if RegionMap.key_side(k) != RegionMap.SIDE_LEFT:
			continue
		out[k] = coverage[k]
		out[RegionMap.mirror_key(k)] = coverage[k]
	return out


func max_bulk() -> int:
	var best := 0
	var c := effective_coverage()
	for key in c.keys():
		best = maxi(best, int((c[key] as Dictionary)["bulk"]))
	return best


# ---------------------------------------------------------------- specials --

## Add a special shape with its default parameters. Returns its index.
func add_special(type: String) -> int:
	specials.append({"type": type, "params": SpecialItem.default_params(type)})
	return specials.size() - 1


func remove_special(index: int) -> void:
	if index >= 0 and index < specials.size():
		specials.remove_at(index)


func special_type(index: int) -> String:
	if index < 0 or index >= specials.size():
		return ""
	return String((specials[index] as Dictionary)["type"])


func special_params(index: int) -> Dictionary:
	if index < 0 or index >= specials.size():
		return {}
	return (specials[index] as Dictionary)["params"]


func set_special_param(index: int, key: String, value: Variant) -> void:
	if index < 0 or index >= specials.size():
		return
	((specials[index] as Dictionary)["params"] as Dictionary)[key] = value


func special_types() -> Array[String]:
	var out: Array[String] = []
	for entry in specials:
		out.append(String((entry as Dictionary)["type"]))
	return out


# -------------------------------------------------------------- colourways --

func colourway_names() -> Array[String]:
	var out: Array[String] = []
	for k in colourways.keys():
		out.append(String(k))
	out.sort()
	return out


func has_colourway(colourway: String) -> bool:
	return colourways.has(colourway)


func first_colourway() -> String:
	if colourways.has(DEFAULT_COLOURWAY):
		return DEFAULT_COLOURWAY
	var names := colourway_names()
	return names[0] if not names.is_empty() else ""


## The palette colour name for a role in a colourway, or "" if unset.
func palette_key_for(colourway: String, role: String) -> String:
	var set_for: Dictionary = colourways.get(colourway, {})
	return String(set_for.get(role, ""))


func set_palette_key(colourway: String, role: String, palette_key: String) -> void:
	if not colourways.has(colourway):
		colourways[colourway] = {}
	(colourways[colourway] as Dictionary)[role] = palette_key


func add_role(role: String) -> void:
	if role in roles:
		return
	roles.append(role)
	# A new role needs a colour in every colourway, or it would render magenta.
	for colourway in colourways.keys():
		var set_for: Dictionary = colourways[colourway]
		if not set_for.has(role):
			set_for[role] = "ink"


func remove_role(role: String) -> void:
	roles.erase(role)
	var fallback := roles[0] if not roles.is_empty() else DEFAULT_ROLE
	for colourway in colourways.keys():
		(colourways[colourway] as Dictionary).erase(role)
	for key in coverage.keys():
		if String((coverage[key] as Dictionary)["role"]) == role:
			(coverage[key] as Dictionary)["role"] = fallback
	_rename_shape_role(role, fallback)


func rename_role(old_name: String, new_name: String) -> void:
	if old_name == new_name or new_name.is_empty() or new_name in roles:
		return
	var at := roles.find(old_name)
	if at < 0:
		return
	roles[at] = new_name
	for colourway in colourways.keys():
		var set_for: Dictionary = colourways[colourway]
		if set_for.has(old_name):
			set_for[new_name] = set_for[old_name]
			set_for.erase(old_name)
	for key in coverage.keys():
		if String((coverage[key] as Dictionary)["role"]) == old_name:
			(coverage[key] as Dictionary)["role"] = new_name
	_rename_shape_role(old_name, new_name)


## Hand-drawn shapes paint with roles too, so a role change has to reach them.
func _rename_shape_role(old_name: String, new_name: String) -> void:
	for entry in specials:
		var params: Dictionary = (entry as Dictionary)["params"]
		if not params.has("cells"):
			continue
		for cell in (params["cells"] as Array):
			var c: Array = cell
			if c.size() >= 4 and String(c[3]) == old_name:
				c[3] = new_name


func add_colourway(colourway: String, copy_from: String = "") -> void:
	if colourways.has(colourway):
		return
	var source: Dictionary = colourways.get(copy_from, {})
	var set_for := {}
	for role in roles:
		set_for[role] = String(source.get(role, "ink"))
	colourways[colourway] = set_for


# --------------------------------------------------------------- JSON I/O ---

func to_json() -> Dictionary:
	var out := {
		"name": name,
		"category": category,
		"draw_order": draw_order,
		"edge_style": BulkBuilder.edge_style_name(edge_style),
		"mirror": mirror,
		"roles": _to_plain_array(roles),
		"colourways": {},
	}
	for colourway in colourways.keys():
		var set_for: Dictionary = colourways[colourway]
		var copy := {}
		for role in set_for.keys():
			copy[String(role)] = String(set_for[role])
		out["colourways"][String(colourway)] = copy

	var cov := {}
	for key in coverage.keys():
		var entry: Dictionary = coverage[key]
		cov[String(key)] = {"role": String(entry["role"]), "bulk": int(entry["bulk"])}
	out["coverage"] = cov

	if not specials.is_empty():
		var list: Array = []
		for entry in specials:
			var e: Dictionary = entry
			list.append({
				"type": String(e["type"]),
				# Free-form, so normalised: an int must come back as an int or
				# the file stops round-tripping (it once did, as 1 -> 1.0).
				"params": JsonIO.normalise_numbers(e.get("params", {})),
			})
		out["specials"] = list
	return out


static func from_json(p_id: String, data: Dictionary, p_slot: String = CLOTHES) -> GarmentItem:
	var item := GarmentItem.new()
	item.id = p_id
	item.slot = p_slot
	item.name = String(data.get("name", p_id))
	item.category = String(data.get("category", p_slot if p_slot != CLOTHES else "other"))
	item.draw_order = int(data.get("draw_order", default_draw_order(item.category)))
	item.edge_style = BulkBuilder.edge_style_from_name(String(data.get("edge_style", "soft")))
	item.mirror = bool(data.get("mirror", true))

	item.roles.clear()
	for role in (data.get("roles", [DEFAULT_ROLE]) as Array):
		item.roles.append(String(role))
	if item.roles.is_empty():
		item.roles.append(DEFAULT_ROLE)

	item.colourways.clear()
	var raw_ways: Dictionary = data.get("colourways", {})
	for colourway in raw_ways.keys():
		var set_for: Dictionary = raw_ways[colourway]
		var copy := {}
		for role in set_for.keys():
			copy[String(role)] = String(set_for[role])
		item.colourways[String(colourway)] = copy
	if item.colourways.is_empty():
		item.colourways[DEFAULT_COLOURWAY] = {item.roles[0]: "ink"}

	var raw_cov: Dictionary = data.get("coverage", {})
	for key in raw_cov.keys():
		var entry: Dictionary = raw_cov[key]
		item.coverage[String(key)] = {
			"role": String(entry.get("role", DEFAULT_ROLE)),
			"bulk": maxi(0, int(entry.get("bulk", 0))),
		}

	for entry in (data.get("specials", []) as Array):
		var e: Dictionary = entry
		item.specials.append({
			"type": String(e.get("type", "")),
			"params": JsonIO.normalise_numbers(e.get("params", {})) as Dictionary,
		})

	# Version 1 files: an item was either parametric or special, never both.
	if String(data.get("kind", "")) == "special" and data.has("special_type"):
		item.specials.append({
			"type": String(data["special_type"]),
			"params": JsonIO.normalise_numbers(data.get("special_params", {})) as Dictionary,
		})
	return item


func duplicate_as(new_id: String, new_name: String) -> GarmentItem:
	var copy := GarmentItem.from_json(new_id, to_json(), slot)
	copy.name = new_name
	return copy


## Roles keep their authored order: it drives the editor's role list, so it is
## meaningful and must not be sorted.
static func _to_plain_array(list: Array[String]) -> Array:
	var out: Array = []
	for s in list:
		out.append(s)
	return out


## Short label for lists: "Tunic - top".
func display_label() -> String:
	return "%s - %s" % [name, category]
