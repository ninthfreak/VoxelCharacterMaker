@tool
class_name RegionMap
extends RefCounted

## Regions of the body surface, shared by all six bodies (SPEC.md section 3.4).
##
## A region is a part family plus a row band, split left/right at the mirror
## line; torso and head bands also split front/back at the depth centre.
## Regions never use absolute x, so the same region set adapts to every body's
## widths and one garment definition fits all six bodies.
##
## Trim bands are deliberately one row thick: a cuff, belt, collar or hem is
## simply a trim band in another colour.
##
## Region key format:  "<band>.<side>"      for limb bands   e.g. "forearm.L"
##                     "<band>.<side>.<fb>" for torso/head   e.g. "belly.R.F"
## side is "L" (the character's left, +x) or "R". fb is "F" (front, -y) or "B".

## Families whose bands split front/back at the depth centre.
const SPLIT_FRONT_BACK: Array[String] = ["head", "chest", "pelvis"]

## Families that exist once per side, as separate parts.
const PAIRED_FAMILIES: Array[String] = ["upper_arm", "forearm", "thigh", "shin"]

## Families that are single, centred parts; their side comes from the cell's x.
const CENTRED_FAMILIES: Array[String] = ["head", "chest", "pelvis"]

const SIDE_LEFT := "L"
const SIDE_RIGHT := "R"
const FACE_FRONT := "F"
const FACE_BACK := "B"


class Band extends RefCounted:
	var name: String
	var z0: int
	var z1: int
	var family: String
	var trim: bool

	func _init(p_name: String, p_z0: int, p_z1: int, p_family: String, p_trim: bool) -> void:
		name = p_name
		z0 = p_z0
		z1 = p_z1
		family = p_family
		trim = p_trim

	func rows() -> int:
		return z1 - z0 + 1

	func contains_z(z: int) -> bool:
		return z >= z0 and z <= z1


var bands: Dictionary = {}          ## band name -> Band
var _bands_by_family: Dictionary = {}  ## family -> Array[Band], descending z
var _ordered_names: Array[String] = []


## Build from the "regions" block of a body JSON file.
static func from_json(regions: Dictionary) -> RegionMap:
	var map := RegionMap.new()
	for name in regions.keys():
		var r: Dictionary = regions[name]
		map.bands[name] = Band.new(
			String(name), int(r["z0"]), int(r["z1"]), String(r["part"]), bool(r["trim"])
		)
	map._reindex()
	return map


func _reindex() -> void:
	_bands_by_family.clear()
	var all: Array = []
	for name in bands.keys():
		var b: Band = bands[name]
		all.append(b)
		if not _bands_by_family.has(b.family):
			_bands_by_family[b.family] = []
		(_bands_by_family[b.family] as Array).append(b)
	for family in _bands_by_family.keys():
		var list: Array = _bands_by_family[family]
		list.sort_custom(func(x: Band, y: Band) -> bool: return x.z0 > y.z0)
	# Head to toe, then by family, so UI lists are always in the same order.
	all.sort_custom(func(x: Band, y: Band) -> bool:
		if x.z0 != y.z0:
			return x.z0 > y.z0
		return x.family < y.family)
	_ordered_names.clear()
	for band_object in all:
		_ordered_names.append((band_object as Band).name)


## Band names, head to toe.
func band_names() -> Array[String]:
	return _ordered_names.duplicate()


func band(name: String) -> Band:
	return bands.get(name, null) as Band


## Strip the _L / _R suffix from a part name to get its family.
static func family_of(part_name: String) -> String:
	if part_name.ends_with("_L") or part_name.ends_with("_R"):
		return part_name.substr(0, part_name.length() - 2)
	return part_name


## The side encoded in a part name, or "" for a centred part.
static func side_of_part(part_name: String) -> String:
	if part_name.ends_with("_L"):
		return SIDE_LEFT
	if part_name.ends_with("_R"):
		return SIDE_RIGHT
	return ""


## Part names that carry a family, for one assembled character.
static func parts_of_family(family: String) -> Array[String]:
	if family in PAIRED_FAMILIES:
		return [family + "_L", family + "_R"]
	return [family]


## The band that owns row z within a family, or null.
func band_at(family: String, z: int) -> Band:
	if not _bands_by_family.has(family):
		return null
	for b in (_bands_by_family[family] as Array):
		if (b as Band).contains_z(z):
			return b as Band
	return null


## Bands of one family, descending z. Plain Array of Band.
func bands_of_family(family: String) -> Array:
	if not _bands_by_family.has(family):
		return []
	return (_bands_by_family[family] as Array).duplicate()


static func splits_front_back(family: String) -> bool:
	return family in SPLIT_FRONT_BACK


## Compose a region key.
static func make_key(band_name: String, side: String, fb: String = "") -> String:
	if fb.is_empty():
		return band_name + "." + side
	return band_name + "." + side + "." + fb


## Split a region key into {"band": String, "side": String, "fb": String}.
static func parse_key(key: String) -> Dictionary:
	var bits := key.split(".")
	var out := {"band": "", "side": "", "fb": ""}
	if bits.size() >= 1:
		out["band"] = bits[0]
	if bits.size() >= 2:
		out["side"] = bits[1]
	if bits.size() >= 3:
		out["fb"] = bits[2]
	return out


## The same region on the other side of the body.
static func mirror_key(key: String) -> String:
	var p := parse_key(key)
	var side: String = SIDE_RIGHT if String(p["side"]) == SIDE_LEFT else SIDE_LEFT
	return make_key(String(p["band"]), side, String(p["fb"]))


static func key_side(key: String) -> String:
	return String(parse_key(key)["side"])


## The region key a cell of a given part belongs to, or "" if no band covers it.
func key_for_cell(part_name: String, cell: Vector3i) -> String:
	var family := family_of(part_name)
	var b := band_at(family, cell.z)
	if b == null:
		return ""
	var side := side_of_part(part_name)
	if side.is_empty():
		side = SIDE_LEFT if VoxelAxes.is_left(cell) else SIDE_RIGHT
	var fb := ""
	if splits_front_back(family):
		fb = FACE_FRONT if VoxelAxes.is_front(cell) else FACE_BACK
	return make_key(b.name, side, fb)


## Every region key that exists, in a stable head-to-toe order.
##
## NOTE (open question for the owner): SPEC section 3.4 says "30 regions per
## side". Applying the stated rule -- every head and torso band splits
## front/back -- gives 32 per side, because the two single-row trim bands in
## those families (neck and waist) split as well. Keeping the general rule is
## the more expressive choice and costs nothing, so that is what this does;
## see docs/NOTES.md. If the intent was that neck and waist stay whole, add
## them to a no-split list here and nowhere else.
func all_keys() -> Array[String]:
	var out: Array[String] = []
	for name in _ordered_names:
		var b: Band = bands[name]
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			if splits_front_back(b.family):
				out.append(make_key(name, side, FACE_FRONT))
				out.append(make_key(name, side, FACE_BACK))
			else:
				out.append(make_key(name, side))
	return out


## Keys for one side only, which is what a mirrored garment authors.
func keys_for_side(side: String) -> Array[String]:
	var out: Array[String] = []
	for key in all_keys():
		if key_side(key) == side:
			out.append(key)
	return out


## Short, readable label for UI lists. The owner is dyslexic: keep these brief
## and consistent, never abbreviated into ambiguity.
func label_for(key: String) -> String:
	var p := parse_key(key)
	var band_name := String(p["band"])
	var b := band(band_name)
	var text := band_name.replace("_", " ")
	if b != null and b.trim:
		text += " (trim)"
	var side_word := "left" if String(p["side"]) == SIDE_LEFT else "right"
	text += " - " + side_word
	var fb := String(p["fb"])
	if fb == FACE_FRONT:
		text += " front"
	elif fb == FACE_BACK:
		text += " back"
	return text
