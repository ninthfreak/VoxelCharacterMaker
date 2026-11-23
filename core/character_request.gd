@tool
class_name CharacterRequest
extends RefCounted

## What a character is made of: a body, a head, a skin tone, the wardrobe, the clothes worn, the features (hair,
## facial hair, a face accessory), what it holds, the eyes and their lid state, and a mouth. LowpolyAssembler builds the figure from
## it; every editor tab makes one.
##
## Also here: the colours a request resolves to, which the game works out per character rather than per item (the
## brow from the hair, "@hair" and "@stubble" in a colourway).

var body_id: String = "male_average"
var head_shape: String = "round"
var wardrobe: Wardrobe = null
## Clothing: Array of {"item": id, "colourway": name}
var worn: Array = []
## Features filling slots -- hair, facial hair, a face accessory: the same shape as `worn`. Kept apart because they
## come from a character's chosen features, not an outfit; dressed exactly like clothing.
var features: Array = []
## Held items: Array of {"item": id, "colourway": name, "side": "R" or "L"} (RegionMap's sides; "R" the figure's
## right hand). Drawn with the face, after everything worn (LowpolyAssembler.face_on), so a change of what is held
## does not dress the figure again.
var held: Array = []
## The eye set to draw, by id in the wardrobe, and its colourway. With none (or one the wardrobe does not have) the
## wardrobe's first eye set is drawn.
var eye_set_id: String = ""
var eye_colourway: String = ""
## The lid state over the eyes, by name (EyeLids.STATES). EyeLids.OFF draws the eye as drawn: no lids, no brow.
var lids: String = EyeLids.DEFAULT
## The mouth, by name (Mouths.STATES); Mouths.OFF for none.
var mouth: String = Mouths.DEFAULT
## The character's skin tone (Palette.SKIN_TONE_NAMES).
var skin_tone: String = Palette.DEFAULT_SKIN
## The brow colour. Transparent (the default) means "follow the hair": the hair's colour one shade darker, or dark
## brown with no hair.
var brow_colour: Color = Color(0, 0, 0, 0)
## Only this item of the clothes is worn, for the editor's "solo an item"; hair and facial hair stay. "" = all.
var solo_item: String = ""


static func make(p_body: String, p_head: String, p_wardrobe: Wardrobe = null) -> CharacterRequest:
	var r := CharacterRequest.new()
	r.body_id = p_body
	r.head_shape = p_head
	r.wardrobe = p_wardrobe
	return r


## The brow colour a request resolves to: set explicitly, or the hair's colour one shade darker, or -- bald -- the
## brow of dark brown hair.
static func brow_colour_of(req: CharacterRequest) -> Color:
	if req.brow_colour.a > 0.0:
		return req.brow_colour
	return hair_tones(req)[2]


## The light/mid/dark of the hair a request wears (its hair item's "hair" role), or of dark brown hair when bald.
## What "@hair" resolves to.
static func hair_tones(req: CharacterRequest) -> Array[Color]:
	if req.wardrobe != null:
		for entry in req.features:
			var e: Dictionary = entry
			var it := req.wardrobe.item(String(e.get("item", "")))
			if it == null or it.slot != "hair":
				continue
			var role := "hair" if it.roles.has("hair") else (it.roles[0] if not it.roles.is_empty() else "")
			if role.is_empty():
				continue
			var way := String(e.get("colourway", ""))
			if not it.has_colourway(way):
				way = it.first_colourway()
			var key := it.palette_key_for(way, role)
			if not Palette.is_reference(key):
				return req.wardrobe.tones_for(it.id, way, role)
		if req.wardrobe.palette.has(Palette.DEFAULT_BROW_HAIR):
			return Palette.garment_tones(req.wardrobe.colour(Palette.DEFAULT_BROW_HAIR))
	return Palette.garment_tones(Color8(98, 66, 44))


## An item role's tones, resolving colour references against the request.
static func role_tones(req: CharacterRequest, item_id: String, colourway: String, role: String) -> Array[Color]:
	var it := req.wardrobe.item(item_id)
	var key := it.palette_key_for(colourway, role) if it != null else ""
	match key:
		Palette.REF_HAIR:
			return hair_tones(req)
		Palette.REF_STUBBLE:
			return Palette.skin_like_tones(Palette.stubble_colour(req.skin_tone, hair_tones(req)[1]))
	return req.wardrobe.tones_for(item_id, colourway, role)
