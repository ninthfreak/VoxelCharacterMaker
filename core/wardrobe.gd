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

## The file's format name, from when the characters were voxels; kept so that every wardrobe file saved since still
## opens (lowpoly/ checks it too).
const FORMAT := "voxel_wardrobe"
const VERSION := 3                  ## 3: saved characters (2: features and eye sets)
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

## character id -> CharacterDef: saved characters, made in the Preview tab and built by the game (GameCharacter)
var characters: Dictionary = {}

var path: String = ""
var dirty: bool = false


## A wardrobe with starter content, the game's standard open eye among it.
static func create_default() -> Wardrobe:
	var w := Wardrobe.new()
	w.palette = Palette.default_wardrobe_colours()
	w._add_starter_clothes()
	w._add_starter_features()
	var standard := EyeSet.standard()
	w.eye_sets[standard.id] = standard
	w._add_starter_characters()
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

	# Skin-tight (bulk 0) is the norm for trousers (owner): slender legs, the
	# classic sprite look, and a top's hem then reads as worn over them. Bulk
	# is for legwear meant to look thick; rule 8 keeps the legs apart either way.
	# The waist is theirs too (a waistband), so under a top that stops short
	# (the shirt) no skin shows; a top that covers the waist stands over it.
	# Knee and ankle are a trim role in the cloth's own colour: in a dark one
	# they read as garters (owner's review); a colourway can still set them apart.
	var trousers := GarmentItem.create("trousers", "Trousers", "bottom")
	trousers.roles = ["cloth", "trim"]
	trousers.colourways = {
		"default": {"cloth": "slate", "trim": "slate"},
		"denim": {"cloth": "denim", "trim": "denim"},
	}
	for key in ["waist.L.F", "waist.L.B", "hips.L.F", "hips.L.B", "upper_thigh.L", "lower_thigh.L", "shin.L"]:
		trousers.set_region(key, "cloth", 0)
	trousers.set_region("knee.L", "trim", 0)
	trousers.set_region("ankle.L", "trim", 0)
	add_item(trousers)

	var boots := GarmentItem.create("boots", "Boots", "feet")
	boots.edge_style = GarmentItem.EdgeStyle.HARD
	boots.roles = ["leather"]
	boots.colourways = {"default": {"leather": "ink"}}
	boots.set_region("foot.L", "leather", 1)
	boots.set_region("ankle.L", "leather", 1)
	add_item(boots)

	# A plain shirt, skin-tight like the trousers: what a bib or straps go over.
	var shirt := GarmentItem.create("shirt", "Shirt", "top")
	shirt.roles = ["cloth"]
	shirt.colourways = {"default": {"cloth": "bone"}, "rust": {"cloth": "rust"}}
	for key in ["upper_chest.L.F", "upper_chest.L.B", "lower_chest.L.F", "lower_chest.L.B",
			"belly.L.F", "belly.L.B", "collar.L.F", "collar.L.B", "shoulder.L", "upper_arm.L"]:
		shirt.set_region(key, "cloth", 0)
	add_item(shirt)

	# Overalls are not a garment but an outfit of three pieces in one colour
	# (owner's idea): trousers, this bib, and the suspenders. Each is useful on
	# its own. The bib is zones only -- waist, belly and the front of the lower
	# chest -- and draws above tops so it shows over a shirt. Skin-tight, so
	# under a thick top it is hidden: raise its bulk to wear it over one.
	var bib := GarmentItem.create("bib", "Bib", "other")
	bib.roles = ["cloth"]
	bib.colourways = {"default": {"cloth": "denim"}, "bone": {"cloth": "bone"}}
	for key in ["waist.L.F", "waist.L.B", "belly.L.F", "belly.L.B", "lower_chest.L.F"]:
		bib.set_region(key, "cloth", 0)
	add_item(bib)

	# Suspenders: a pair of shoulder straps, placed on each chest by the strap
	# generator. An accessory, so they draw over tops and under a thick coat.
	var suspenders := GarmentItem.create("suspenders", "Suspenders", "accessory")
	suspenders.roles = ["strap"]
	suspenders.colourways = {"default": {"strap": "rust"}, "denim": {"strap": "denim"}}
	suspenders.add_special("straps")
	add_item(suspenders)

	# A dress is not a garment but an outfit (owner): a top and a skirt in one
	# colour, which assemble into exactly the figure a one-piece dress would.
	# Skirts are always their own items, so each also goes with any other top.
	#
	# The bodice is the top half: it ends at the waist with a trim line.
	var bodice := GarmentItem.create("bodice", "Bodice", "top")
	bodice.roles = ["cloth", "trim"]
	bodice.colourways = {
		"default": {"cloth": "plum", "trim": "bone"},
		"moss": {"cloth": "moss", "trim": "bone"},
	}
	for key in ["upper_chest.L.F", "upper_chest.L.B", "lower_chest.L.F",
			"lower_chest.L.B", "belly.L.F", "belly.L.B", "shoulder.L"]:
		bodice.set_region(key, "cloth", 1)
	for key in ["collar.L.F", "collar.L.B", "waist.L.F", "waist.L.B"]:
		bodice.set_region(key, "trim", 1)
	add_item(bodice)

	# A skirt item is the hips in cloth plus the skirt shape. Its waistband is
	# on, so under a top that stops short (the shirt) no skin shows at the waist
	# (the trousers' waist does the same).
	var skirt := _skirt_item("skirt", "Skirt", {"length": "to_shin"})
	skirt.colourways = {
		"default": {"cloth": "plum", "hem": "ochre"},
		"moss": {"cloth": "moss", "hem": "ink"},
		"ink": {"cloth": "ink", "hem": "rust"},
	}

	# The asymmetric skirt: hem slanted up to the character's left, and the
	# front wrapped open on that side so the leg shows. The lower half of a
	# toga, or of a dress cut that way.
	var wrap := _skirt_item("wrap_skirt", "Wrap skirt",
		{"length": "to_ankle", "slant": 4, "opening": "wrap", "side": "left"})
	wrap.colourways = {
		"default": {"cloth": "bone", "hem": "ochre"},
		"plum": {"cloth": "plum", "hem": "ochre"},
	}

	# One shoulder covered, the other bare: mirror is off and each side has
	# its own regions. With the wrap skirt in the same colour it is a toga.
	var drape := GarmentItem.create("one_shoulder_top", "One-shoulder top", "top")
	drape.mirror = false
	drape.roles = ["cloth"]
	drape.colourways = {"default": {"cloth": "bone"}, "plum": {"cloth": "plum"}}
	for key in ["upper_chest.L.F", "upper_chest.L.B", "shoulder.L",
			"lower_chest.L.F", "lower_chest.L.B", "belly.L.F", "belly.L.B",
			"waist.L.F", "waist.L.B",
			"lower_chest.R.F", "lower_chest.R.B", "belly.R.F", "belly.R.B",
			"waist.R.F", "waist.R.B"]:
		drape.set_region(key, "cloth", 1)
	add_item(drape)

	# A robe, again as two pieces: a long-sleeved top with a sash at the
	# waist, and a long skirt open down the front over whatever is worn below.
	var robe_top := GarmentItem.create("robe_top", "Robe top", "top")
	robe_top.roles = ["cloth", "trim"]
	robe_top.colourways = {
		"default": {"cloth": "ink", "trim": "rust"},
		"moss": {"cloth": "moss", "trim": "ochre"},
	}
	for key in ["upper_chest.L.F", "upper_chest.L.B", "lower_chest.L.F",
			"lower_chest.L.B", "belly.L.F", "belly.L.B", "shoulder.L",
			"upper_arm.L", "elbow.L", "forearm.L"]:
		robe_top.set_region(key, "cloth", 1)
	for key in ["collar.L.F", "collar.L.B", "waist.L.F", "waist.L.B"]:
		robe_top.set_region(key, "trim", 1)
	add_item(robe_top)

	var robe_skirt := _skirt_item("robe_skirt", "Robe skirt",
		{"length": "to_ankle", "opening": "front"})
	robe_skirt.colourways = {
		"default": {"cloth": "ink", "hem": "rust"},
		"moss": {"cloth": "moss", "hem": "ochre"},
	}

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
	outfits["dress"] = [
		{"item": "boots", "colourway": "default"},
		{"item": "bodice", "colourway": "default"},
		{"item": "skirt", "colourway": "default"},
	]
	outfits["toga"] = [
		{"item": "one_shoulder_top", "colourway": "default"},
		{"item": "wrap_skirt", "colourway": "default"},
	]
	outfits["robe"] = [
		{"item": "boots", "colourway": "default"},
		{"item": "trousers", "colourway": "default"},
		{"item": "robe_top", "colourway": "default"},
		{"item": "robe_skirt", "colourway": "default"},
	]
	outfits["shirt and suspenders"] = [
		{"item": "boots", "colourway": "default"},
		{"item": "trousers", "colourway": "default"},
		{"item": "shirt", "colourway": "default"},
		{"item": "suspenders", "colourway": "default"},
	]
	outfits["overalls"] = [
		{"item": "boots", "colourway": "default"},
		{"item": "trousers", "colourway": "denim"},
		{"item": "shirt", "colourway": "default"},
		{"item": "bib", "colourway": "default"},
		{"item": "suspenders", "colourway": "denim"},
	]


## A skirt-only item: the hips in cloth, and the skirt shape with these
## settings (anything left out keeps the generator's default).
func _skirt_item(id: String, label: String, settings: Dictionary) -> GarmentItem:
	var item := GarmentItem.create(id, label, "bottom")
	item.roles = ["cloth", "hem"]
	item.set_region("hips.L.F", "cloth", 1)
	item.set_region("hips.L.B", "cloth", 1)
	var at := item.add_special("skirt")
	for key in settings.keys():
		item.set_special_param(at, String(key), settings[key])
	add_item(item)
	return item


func _add_starter_features() -> void:
	# Hair can only use the head's BACK and CROWN regions without covering the
	# eyes: the front of mid_head (z31-36) contains the eye rows (z29-33). That
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
	tail.add_special("ponytail")
	add_item(tail)

	# Facial hair follows each head's own surface, and takes its colours from
	# the character: "@stubble" is always darker than the skin, "@hair" is the
	# hair worn. Four parts, each on or off, and one length (FacialHairSettings);
	# the three starter items are the owner's three original styles, so named.
	for style in [["stubble", "Stubble"], ["chinstrap", "Chinstrap"], ["full_beard", "Full beard"]]:
		var fh := GarmentItem.create_feature(String(style[0]), String(style[1]), "facial_hair")
		fh.roles = ["hair", "stubble"]
		fh.colourways = {"default": {"hair": Palette.REF_HAIR, "stubble": Palette.REF_STUBBLE}}
		var at_fh := fh.add_special("facial_hair")
		var settings := FacialHairSettings.migrate({"style": String(style[0])})
		for key in settings.keys():
			fh.set_special_param(at_fh, String(key), settings[key])
		add_item(fh)

	# A face accessory, not a facial hair style: optional, hung under the chin, worn with facial hair or without.
	var long_beard := GarmentItem.create_feature("long_beard", "Long beard", "face_accessory")
	long_beard.roles = ["hair"]
	long_beard.colourways = {"default": {"hair": Palette.REF_HAIR}}
	long_beard.add_special("long_beard")
	add_item(long_beard)


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
	for character_id in characters.keys():
		(characters[character_id] as CharacterDef).drop_item(item_id)
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


## Who uses a palette colour, in words: "Tunic (rust)" for an item's colourway, "eye set Round (default)" for an
## eye set's. Empty when nothing does, and only then can it be removed without leaving something with no colour.
func colour_users(palette_key: String) -> Array[String]:
	var out: Array[String] = []
	for id in items.keys():
		var it: GarmentItem = items[id]
		for way in it.colourways.keys():
			if (it.colourways[way] as Dictionary).values().has(palette_key):
				out.append("%s (%s)" % [it.name, way])
	for id in eye_sets.keys():
		var eyes: EyeSet = eye_sets[id]
		for way in eyes.colourways.keys():
			if (eyes.colourways[way] as Dictionary).values().has(palette_key):
				out.append("eye set %s (%s)" % [eyes.name, way])
	for id in characters.keys():
		var who: CharacterDef = characters[id]
		if who.brow_hair == palette_key:
			out.append("character %s (brows)" % who.name)
	out.sort()
	return out


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


# --------------------------------------------------------------- characters --

func add_character(who: CharacterDef) -> void:
	characters[who.id] = who
	mark_dirty()


func remove_character(character_id: String) -> void:
	characters.erase(character_id)
	mark_dirty()


func character(character_id: String) -> CharacterDef:
	return characters.get(character_id, null) as CharacterDef


## Ids of the saved characters, by name.
func character_ids() -> Array[String]:
	var out: Array[String] = []
	for k in characters.keys():
		out.append(String(k))
	out.sort_custom(func(a: String, b: String) -> bool:
		return (characters[a] as CharacterDef).name.naturalnocasecmp_to((characters[b] as CharacterDef).name) < 0)
	return out


func unique_character_id(base: String) -> String:
	return _unique(base, characters, "character")


## A few characters to start from, one in each starter outfit that makes a whole look: examples of what a saved
## character holds, and something for the game to build by id from the first run.
func _add_starter_characters() -> void:
	var traveller := CharacterDef.create("traveller", "Traveller")
	traveller.body_id = "female_average"
	traveller.head_shape = "oval"
	traveller.skin_tone = "tan"
	traveller.hair_id = "ponytail"
	traveller.worn = outfit("travelling")
	add_character(traveller)

	var farmer := CharacterDef.create("farmer", "Farmer")
	farmer.body_id = "male_heavy"
	farmer.head_shape = "round"
	farmer.skin_tone = "light"
	farmer.hair_id = "short_crop"
	farmer.facial_id = "full_beard"
	farmer.worn = outfit("overalls")
	add_character(farmer)

	var elder := CharacterDef.create("elder", "Elder")
	elder.body_id = "male_short"
	elder.head_shape = "strong"
	elder.skin_tone = "brown"
	elder.accessory_id = "long_beard"
	elder.worn = outfit("robe")
	add_character(elder)

	var villager := CharacterDef.create("villager", "Villager")
	villager.body_id = "female_slim"
	villager.head_shape = "heart"
	villager.skin_tone = "pale"
	villager.hair_id = "short_crop"
	villager.hair_colourway = "auburn"
	villager.worn = outfit("dress")
	add_character(villager)


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

	var characters_out := {}
	for character_id in characters.keys():
		characters_out[String(character_id)] = (characters[character_id] as CharacterDef).to_json()

	return {
		"format": FORMAT,
		"version": VERSION,
		"palette": palette_out,
		"items": clothes_out,
		"features": features_out,
		"eye_sets": eyes_out,
		"outfits": outfits_out,
		"characters": characters_out,
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

	var raw_characters: Variant = data.get("characters", {})       # version 3
	if raw_characters is Dictionary:
		for character_id in (raw_characters as Dictionary).keys():
			var raw_one: Variant = raw_characters[character_id]
			if raw_one is Dictionary:
				w.characters[String(character_id)] = CharacterDef.from_json(String(character_id), raw_one)

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
