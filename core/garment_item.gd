@tool
class_name GarmentItem
extends RefCounted

## One wardrobe item (SPEC.md section 7.2 and 7.3).
##
## Parametric items -- the main system -- list the regions they cover, each with
## a colour role and a bulk, and regenerate from each body's surface, so one
## item fits all six bodies. Special items are generated shapes the bulk system
## cannot express (hoods, skirts, capes...) and carry parameters instead.
##
## The LEFT side is authored and the mirror flag says whether the right side
## mirrors it or has its own definition (sashes, one-shouldered tops). Turning
## mirror on does not delete right-side work; it is simply ignored while on.

enum Kind { PARAMETRIC, SPECIAL }

## Category and default draw order; higher draws on top (SPEC 7.2).
const CATEGORY_DRAW_ORDER := {
	"hat": 80,
	"hair": 70,
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
	"hat", "hair", "back", "accessory", "belt", "other", "hands", "top", "feet", "bottom",
]

const DEFAULT_COLOURWAY := "default"
const DEFAULT_ROLE := "cloth"

var id: String = ""
var name: String = ""
var category: String = "other"
var draw_order: int = 45
var kind: int = Kind.PARAMETRIC
var edge_style: int = BulkBuilder.EdgeStyle.SOFT
var mirror: bool = true

## Named parts of the design: cloth, trim, buckle...
var roles: Array[String] = [DEFAULT_ROLE]

## colourway name -> {role name -> palette colour name}
var colourways: Dictionary = {}

## region key -> {"role": String, "bulk": int}  (parametric only)
var coverage: Dictionary = {}

## Special items only.
var special_type: String = ""
var special_params: Dictionary = {}


static func create(p_id: String, p_name: String, p_category: String = "other") -> GarmentItem:
	var item := GarmentItem.new()
	item.id = p_id
	item.name = p_name
	item.category = p_category
	item.draw_order = int(CATEGORY_DRAW_ORDER.get(p_category, 45))
	item.colourways = {DEFAULT_COLOURWAY: {DEFAULT_ROLE: "ink"}}
	return item


static func default_draw_order(p_category: String) -> int:
	return int(CATEGORY_DRAW_ORDER.get(p_category, 45))


func is_special() -> bool:
	return kind == Kind.SPECIAL


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


## Regions this item adds volume to, as opposed to merely recolouring.
func bulked_regions() -> Array[String]:
	var out: Array[String] = []
	var c := effective_coverage()
	for key in c.keys():
		if int((c[key] as Dictionary)["bulk"]) > 0:
			out.append(String(key))
	return out


func max_bulk() -> int:
	var best := 0
	var c := effective_coverage()
	for key in c.keys():
		best = maxi(best, int((c[key] as Dictionary)["bulk"]))
	return best


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
	for colourway in colourways.keys():
		(colourways[colourway] as Dictionary).erase(role)
	for key in coverage.keys():
		if String((coverage[key] as Dictionary)["role"]) == role:
			(coverage[key] as Dictionary)["role"] = roles[0] if not roles.is_empty() else DEFAULT_ROLE


func rename_role(old_name: String, new_name: String) -> void:
	if old_name == new_name or new_name.is_empty():
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
		"kind": "special" if is_special() else "parametric",
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

	if is_special():
		out["special_type"] = special_type
		out["special_params"] = JsonIO.normalise_numbers(special_params)
	else:
		var cov := {}
		for key in coverage.keys():
			var entry: Dictionary = coverage[key]
			cov[String(key)] = {"role": String(entry["role"]), "bulk": int(entry["bulk"])}
		out["coverage"] = cov
	return out


static func from_json(p_id: String, data: Dictionary) -> GarmentItem:
	var item := GarmentItem.new()
	item.id = p_id
	item.name = String(data.get("name", p_id))
	item.category = String(data.get("category", "other"))
	item.draw_order = int(data.get("draw_order", default_draw_order(item.category)))
	item.kind = Kind.SPECIAL if String(data.get("kind", "parametric")) == "special" else Kind.PARAMETRIC
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

	if item.is_special():
		item.special_type = String(data.get("special_type", ""))
		# Free-form, so nothing casts these back the way the fixed fields are
		# cast; normalise or an int parameter comes back as a float and the
		# file stops round-tripping.
		item.special_params = JsonIO.normalise_numbers(
			data.get("special_params", {})) as Dictionary
	else:
		var raw_cov: Dictionary = data.get("coverage", {})
		for key in raw_cov.keys():
			var entry: Dictionary = raw_cov[key]
			item.coverage[String(key)] = {
				"role": String(entry.get("role", DEFAULT_ROLE)),
				"bulk": maxi(0, int(entry.get("bulk", 0))),
			}
	return item


func duplicate_as(new_id: String, new_name: String) -> GarmentItem:
	var copy := GarmentItem.from_json(new_id, to_json())
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
