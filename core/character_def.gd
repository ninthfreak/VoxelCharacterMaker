@tool
class_name CharacterDef
extends RefCounted

## One saved character: who someone is, as the Preview tab puts a character together and the game builds one. Kept
## in the wardrobe file beside the outfits, by id, and refers to the wardrobe's items, eye sets and colours by name.
##
## make_request() turns it into what LowpolyAssembler builds from. The Preview tab makes its request through it too,
## so a saved character is exactly what the Preview showed when it was saved.
##
## What is not here: the pose, the camera and the shading (how it is looked at, not who it is). The eyelids and the
## mouth are the character's resting expression; the game changes them as it goes (GameCharacter.set_expression).

var id: String = ""
var name: String = ""
var body_id: String = "male_average"
var head_shape: String = "round"
var skin_tone: String = Palette.DEFAULT_SKIN
var eye_set_id: String = ""
var eye_colourway: String = ""
## A hair palette colour whose brow to use; "" = follow the hair worn.
var brow_hair: String = ""
var lids: String = EyeLids.DEFAULT
var mouth: String = Mouths.DEFAULT
## The features, one per slot: an item id ("" = none) and its colourway ("" = the item's first).
var hair_id: String = ""
var hair_colourway: String = ""
var facial_id: String = ""
var facial_colourway: String = ""
var accessory_id: String = ""
var accessory_colourway: String = ""
## Clothing worn: Array of {"item": id, "colourway": name}, in the order put on.
var worn: Array = []
## What it holds in each hand: a held item's id ("" = nothing) and its colourway ("" = the item's first).
var right_hand_id: String = ""
var right_hand_colourway: String = ""
var left_hand_id: String = ""
var left_hand_colourway: String = ""

## The fields kept in the file, in this order: the fields above but id, which is the file's key.
const FIELDS: Array[String] = ["name", "body_id", "head_shape", "skin_tone", "eye_set_id", "eye_colourway",
	"brow_hair", "lids", "mouth", "hair_id", "hair_colourway", "facial_id", "facial_colourway", "accessory_id",
	"accessory_colourway", "right_hand_id", "right_hand_colourway", "left_hand_id", "left_hand_colourway"]

## The hands, as [id field, colourway field, side] (RegionMap's sides: "R" the figure's right).
const HANDS := [["right_hand_id", "right_hand_colourway", "R"], ["left_hand_id", "left_hand_colourway", "L"]]


static func create(p_id: String, p_name: String) -> CharacterDef:
	var c := CharacterDef.new()
	c.id = p_id
	c.name = p_name
	return c


## What the assembler builds this character from, against a wardrobe. Anything the wardrobe no longer has is left
## out (an item) or falls back (a colourway to the item's first; an eye set to the wardrobe's first, by the
## assembler), so a character never fails to build because something it wore was deleted.
func make_request(wardrobe: Wardrobe) -> CharacterRequest:
	var request := CharacterRequest.make(body_id, head_shape, wardrobe)
	request.skin_tone = skin_tone
	var eyes := _eyes(wardrobe)
	request.eye_set_id = eyes.id if eyes != null else ""
	request.eye_colourway = (eye_colourway if eyes.colourways.has(eye_colourway) else eyes.first_colourway()) \
		if eyes != null else ""
	request.lids = lids
	request.mouth = mouth
	if not brow_hair.is_empty() and wardrobe.palette.has(brow_hair):
		request.brow_colour = Palette.brow_from_hair(wardrobe.colour(brow_hair))
	request.worn = live_worn(wardrobe)
	var features: Array = []
	for pair in [[hair_id, hair_colourway], [facial_id, facial_colourway], [accessory_id, accessory_colourway]]:
		var it := wardrobe.item(String(pair[0])) if not String(pair[0]).is_empty() else null
		if it != null and it.is_feature():
			var way := String(pair[1])
			features.append({"item": it.id, "colourway": way if it.has_colourway(way) else it.first_colourway()})
	request.features = features
	var held: Array = []
	for hand in HANDS:
		var it2 := wardrobe.item(String(get(hand[0]))) if not String(get(hand[0])).is_empty() else null
		if it2 != null and it2.is_held():
			var way2 := String(get(hand[1]))
			held.append({"item": it2.id, "colourway": way2 if it2.has_colourway(way2) else it2.first_colourway(),
				"side": String(hand[2])})
	request.held = held
	return request


## The eye set it is drawn with: its own, or the wardrobe's first if the wardrobe lacks it (null with none at all).
func _eyes(wardrobe: Wardrobe) -> EyeSet:
	var eyes := wardrobe.eye_set(eye_set_id)
	return eyes if eyes != null else wardrobe.eye_set(wardrobe.first_eye_set_id())


## The same character with every choice as it resolves against the wardrobe: the eye set and colourways it is
## drawn in, and only the items the wardrobe has. Two characters that resolve the same look the same.
func resolved(wardrobe: Wardrobe) -> CharacterDef:
	var r := duplicate_as(id, name)
	var request := make_request(wardrobe)
	r.eye_set_id = request.eye_set_id
	r.eye_colourway = request.eye_colourway
	r.worn = request.worn
	for slot in [["hair_id", "hair_colourway"], ["facial_id", "facial_colourway"], ["accessory_id", "accessory_colourway"]]:
		var found := false
		for f in request.features:
			if String((f as Dictionary)["item"]) == String(r.get(slot[0])):
				r.set(slot[1], String((f as Dictionary)["colourway"]))
				found = true
		if not found:
			r.set(slot[0], "")
			r.set(slot[1], "")
	for hand in HANDS:
		var found2 := false
		for h in request.held:
			if String((h as Dictionary)["side"]) == String(hand[2]):
				r.set(hand[1], String((h as Dictionary)["colourway"]))
				found2 = true
		if not found2:
			r.set(hand[0], "")
			r.set(hand[1], "")
	if not wardrobe.palette.has(r.brow_hair):
		r.brow_hair = ""
	return r


## Whether two characters look the same against a wardrobe (the id and name aside).
func looks_like(other: CharacterDef, wardrobe: Wardrobe) -> bool:
	if other == null:
		return false
	var a := resolved(wardrobe).to_json()
	var b := other.resolved(wardrobe).to_json()
	a.erase("name")
	b.erase("name")
	return a == b


## The clothing worn that the wardrobe still has, each in a colourway it has.
func live_worn(wardrobe: Wardrobe) -> Array:
	var out: Array = []
	for entry in worn:
		var e: Dictionary = entry
		var it := wardrobe.item(String(e.get("item", "")))
		if it == null or it.is_feature():
			continue
		var way := String(e.get("colourway", ""))
		out.append({"item": it.id, "colourway": way if it.has_colourway(way) else it.first_colourway()})
	return out


## Whether it wears, has or holds this item: as clothing, as a feature or in a hand.
func uses_item(item_id: String) -> bool:
	if item_id in [hair_id, facial_id, accessory_id, right_hand_id, left_hand_id]:
		return true
	for entry in worn:
		if String((entry as Dictionary).get("item", "")) == item_id:
			return true
	return false


## Take an item off: out of the clothes, out of its feature slot, or out of its hand.
func drop_item(item_id: String) -> void:
	for i in range(worn.size() - 1, -1, -1):
		if String((worn[i] as Dictionary).get("item", "")) == item_id:
			worn.remove_at(i)
	if hair_id == item_id:
		hair_id = ""
		hair_colourway = ""
	if facial_id == item_id:
		facial_id = ""
		facial_colourway = ""
	if accessory_id == item_id:
		accessory_id = ""
		accessory_colourway = ""
	if right_hand_id == item_id:
		right_hand_id = ""
		right_hand_colourway = ""
	if left_hand_id == item_id:
		left_hand_id = ""
		left_hand_colourway = ""


func to_json() -> Dictionary:
	var out := {}
	for field in FIELDS:
		out[field] = String(get(field))
	var clothes: Array = []
	for entry in worn:
		var e: Dictionary = entry
		clothes.append({"item": String(e.get("item", "")), "colourway": String(e.get("colourway", ""))})
	out["worn"] = clothes
	return out


static func from_json(p_id: String, data: Dictionary) -> CharacterDef:
	var c := CharacterDef.new()
	c.id = p_id
	for field in FIELDS:
		if data.has(field) and data[field] is String:
			c.set(field, String(data[field]))
	if c.name.is_empty():
		c.name = p_id
	var clothes: Variant = data.get("worn", [])
	if clothes is Array:
		for entry in clothes:
			if entry is Dictionary:
				c.worn.append({"item": String((entry as Dictionary).get("item", "")),
					"colourway": String((entry as Dictionary).get("colourway", ""))})
	return c


func duplicate_as(p_id: String, p_name: String) -> CharacterDef:
	var c := CharacterDef.from_json(p_id, to_json())
	c.name = p_name
	return c


## Whether two characters are the same character, the id aside.
func same_as(other: CharacterDef) -> bool:
	return other != null and to_json() == other.to_json()
