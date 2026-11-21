@tool
class_name FacialHairSettings
extends RefCounted

## Facial hair's settings (owner, 2026-11; SPEC.md section 0): four parts, each on or off, and one length for all of
## them. The low-poly figure grows them from the head's own polygons (LowpolyFacialHair).
##
##   moustache, sideburns, goatee, cheeks (the rest of a beard, between the sideburns and the goatee)
##   stubble   a tint over the skin, flush with the face, in the stubble colour ("@stubble": from the skin and hair)
##   short     the hair's colour ("@hair"), opaque, still flush
##   medium    grown out by half a step of bulk
##   long      grown out by a whole step
##
## Before these settings a facial hair item had one "style" (stubble, chinstrap, full beard); a file saved that way
## is read as parts and a length (migrate).

const ROLE_STUBBLE := "stubble"
const ROLE_HAIR := "hair"
const PARTS: Array[String] = ["moustache", "sideburns", "goatee", "cheeks"]
const LENGTHS: Array[String] = ["stubble", "short", "medium", "long"]
## The three old styles as parts and a length.
const FROM_STYLE := {
	"stubble": [["moustache", "sideburns", "goatee", "cheeks"], "stubble"],
	"chinstrap": [["sideburns", "goatee", "cheeks"], "medium"],
	"full_beard": [["moustache", "sideburns", "goatee", "cheeks"], "medium"],
}


static func param_spec() -> Array:
	return [
		{"name": "moustache", "label": "Moustache", "type": "bool", "default": true},
		{"name": "sideburns", "label": "Sideburns", "type": "bool", "default": true},
		{"name": "goatee", "label": "Goatee", "type": "bool", "default": true},
		{"name": "cheeks", "label": "Cheeks (between sideburns and goatee)", "type": "bool", "default": true},
		{"name": "length", "label": "Length", "type": "enum", "default": "stubble", "options": LENGTHS},
	]


## Settings as parts and a length, from a file saved with the old "style" setting (or as they are). A style this
## does not know is left as it is, so that the figure can say so and a save does not lose it.
static func migrate(params: Dictionary) -> Dictionary:
	if not params.has("style") or not FROM_STYLE.has(String(params["style"])):
		return params
	var style := String(params["style"])
	var out := params.duplicate()
	out.erase("style")
	var parts: Array = FROM_STYLE[style][0]
	for part in PARTS:
		out[part] = parts.has(part)
	out["length"] = FROM_STYLE[style][1]
	return out


## The two colours facial hair needs, whatever an item was saved with: before the four parts and the length, a
## stubble item had only "stubble" and a chinstrap only "hair". Each colourway gets the character's own for a role
## it lacks.
static func complete_roles(item: GarmentItem) -> void:
	for role in [ROLE_HAIR, ROLE_STUBBLE]:
		if not item.roles.has(role):
			item.roles.append(role)
		for way in item.colourways.keys():
			var set_for: Dictionary = item.colourways[way]
			if not set_for.has(role):
				set_for[role] = Palette.REF_HAIR if role == ROLE_HAIR else Palette.REF_STUBBLE
