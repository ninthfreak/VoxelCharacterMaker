@tool
class_name SpecialItem
extends RefCounted

## Special shapes: pieces the region-and-bulk system cannot express -- skirts, capes, straps, facial hair, hoods, and
## shapes of their own fixed at a place on the figure (a long beard, a ponytail, a bun, horns, pauldrons) (SPEC.md
## section 7.4). An item can carry several, alongside its regions; each has a few settings, and lengths are named by
## body bands ("to the knee"), not heights.
##
## This is the table of them: their names, their settings and their defaults, from which the editor builds its
## controls (a new type needs no editor change). The low-poly figure builds them (core/lowpoly/: LowpolyShapes for
## straps, skirt and cape, LowpolyFacialHair for facial hair, LowpolyHood, LowpolyDrawn for the shapes of their own).
##
## The voxel figure's drawn shape ("shape": cells drawn in a box at an anchor) has no low-poly form. The owner chose
## fixed types with settings instead (2026-11). An old file's drawn shape under the chin becomes a long beard, one at
## the nape a ponytail (GarmentItem.from_json); any other is kept in the file, with its drawing, and not drawn.

const OPENINGS: Array[String] = ["none", "wrap", "front"]
const SIDES: Array[String] = ["left", "right"]
const MAX_SLANT := 6

## Where an old drawn shape hung from: name -> label (kept so that its settings still read in the editor).
const ANCHORS := {
	"crown": "Top of the head",
	"brow": "Forehead, just above the eyes",
	"face": "Face, at the bottom row of the eyes",
	"chin": "Under the chin, hanging down",
	"nape": "Back of the head, level with the eyes",
	"shoulder": "Top of the shoulder (both sides when mirrored)",
	"chest": "Front of the chest",
	"back": "Middle of the back",
	"waist_front": "Front of the waist",
	"waist_back": "Back of the waist",
	"hip": "Side of the hip (both sides when mirrored)",
	"wrist": "Outside of the wrist (both sides when mirrored)",
	"ankle": "Outside of the ankle (both sides when mirrored)",
}


## The types an item can be given. The old drawn shape is not among them: it is only read from old files.
static func types() -> Array[String]:
	return ["skirt", "cape", "hood", "straps", "facial_hair", "long_beard", "ponytail", "bun", "horns", "pauldrons"]


## The shapes of their own, and the roles each colours, with the colour a new role starts in.
const OWN_SHAPES: Array[String] = ["long_beard", "ponytail", "bun", "horns", "pauldrons"]
const BUN_POSITIONS: Array[String] = ["top", "back", "nape"]


static func roles_of(type: String) -> Dictionary:
	match type:
		"long_beard", "bun": return {"hair": Palette.REF_HAIR}
		"ponytail": return {"hair": Palette.REF_HAIR, "tie": "rust"}
		"horns": return {"horn": "bone"}
		"pauldrons": return {"plate": "slate"}
	return {}


## Types that hang clear of the figure. They are placed after everything else that is worn, in draw order among
## themselves, so a skirt clears boots put on "after" it.
static func hangs_clear(type: String) -> bool:
	return type in ["skirt", "cape"]


## Whether the low-poly figure builds this type yet.
static func is_built(type: String) -> bool:
	return type in ["skirt", "cape", "straps", "facial_hair", "hood"] or type in OWN_SHAPES


static func display_name(type: String) -> String:
	match type:
		"hood": return "Hood"
		"skirt": return "Skirt"
		"cape": return "Cape"
		"shape": return "Drawn shape (old)"
		"straps": return "Shoulder straps"
		"facial_hair": return "Facial hair"
		"long_beard": return "Long beard"
		"ponytail": return "Ponytail"
		"bun": return "Bun"
		"horns": return "Horns"
		"pauldrons": return "Pauldrons"
	return type


## Where a type attaches, in words, for the editor. An old drawn shape's anchor is a setting, so the caller passes
## the settings to get its actual anchor.
static func anchor_description(type: String, params: Dictionary = {}) -> String:
	match type:
		"hood": return "Raised: over the head, the face left open, falling to a cowl on the shoulders. Down: a collar " \
			+ "with the hood lying on the back."
		"long_beard": return "Hangs from under the chin, clear of the chest."
		"ponytail": return "Tied at the back of the head, hanging clear of the back."
		"bun": return "On the head: on top, at the back, or at the nape."
		"horns": return "A pair, from the forehead."
		"pauldrons": return "A pair, one on each shoulder; each bends between the chest and its arm."
		"skirt": return "Hangs from the waist line; laid afresh over the legs in every pose."
		"cape": return "Hangs from the shoulder line at the back; laid afresh in every pose."
		"shape":
			var anchor := String(params.get("anchor", "chest"))
			return "Anchored at: %s. An old drawn shape: the low-poly figure does not draw these, and its drawing is " \
				% String(ANCHORS.get(anchor, anchor)) + "kept in the file. The shapes of their own replace it."
		"facial_hair":
			return "Cut from the head's own polygons on every head: moustache, sideburns, goatee and cheeks."
		"straps":
			return "Over both shoulders: up the chest, across the top, and straight down the back."
	return ""


## Settings for the editor, so a new special type does not need any editor changes. Each entry:
##   {"name", "label", "type": "int"|"bool"|"enum"|"cells", "default", "min", "max" (int), "options" (enum),
##    "hint"}
static func param_spec(type: String) -> Array:
	match type:
		"skirt": return [
			{"name": "length", "label": "Length", "type": "enum", "default": "to_knee",
				"options": ["to_knee", "to_shin", "to_ankle"]},
			{"name": "flare", "label": "Flare", "type": "int", "default": 1, "min": 0, "max": 3,
				"hint": "How much wider the hem is than the hips"},
			{"name": "panels", "label": "Panels", "type": "enum", "default": "four", "options": ["two", "four"],
				"hint": "Four: one cloth all round. Two: a front and a back, the sides open"},
			{"name": "slant", "label": "Hem slant", "type": "int", "default": 0, "min": 0, "max": MAX_SLANT,
				"hint": "How far the hem rises across the skirt. 0 is level"},
			{"name": "opening", "label": "Opening", "type": "enum", "default": "none", "options": OPENINGS,
				"hint": "Wrap shows one leg. Front opens down the middle, like a robe"},
			{"name": "side", "label": "Side", "type": "enum", "default": "left", "options": SIDES,
				"hint": "The character's own left or right: where the hem rises and the wrap opens"},
			{"name": "waistband", "label": "Waistband", "type": "bool", "default": true},
			{"name": "hem_trim", "label": "Hem in its own colour", "type": "bool", "default": true},
		]
		"cape": return [
			{"name": "length", "label": "Length", "type": "enum", "default": "to_knee",
				"options": ["to_waist", "to_knee", "to_ankle"]},
			{"name": "width", "label": "Width", "type": "enum", "default": "shoulders",
				"options": ["narrow", "shoulders", "wide"]},
			{"name": "flare", "label": "Flare", "type": "int", "default": 1, "min": 0, "max": 3},
			{"name": "hem_trim", "label": "Hem in its own colour", "type": "bool", "default": true},
		]
		"hood": return [
			{"name": "raised", "label": "Up (over the head)", "type": "bool", "default": true},
			{"name": "depth", "label": "Looseness", "type": "int", "default": 1, "min": 1, "max": 3,
				"hint": "How far the hood stands off the head"},
			{"name": "opening", "label": "Face opening", "type": "int", "default": 1, "min": 0, "max": 3,
				"hint": "How far past the eye box the opening reaches"},
			{"name": "lined", "label": "Separate lining colour", "type": "bool", "default": false},
		]
		"shape": return [
			{"name": "anchor", "label": "Anchored at", "type": "enum", "default": "chest", "options": anchor_names()},
			{"name": "wrap", "label": "Wrap onto the surface", "type": "bool", "default": true,
				"hint": "On: follows the body's curve. Off: keeps its own shape."},
			{"name": "mirror", "label": "Mirror onto the other side", "type": "bool", "default": true},
			# the drawing itself: kept in the file, not edited with a control
			{"name": "cells", "label": "Shape", "type": "cells", "default": []},
		]
		"facial_hair": return FacialHairSettings.param_spec()
		"long_beard": return [
			{"name": "length", "label": "Length", "type": "int", "default": 3, "min": 1, "max": 5},
			{"name": "width", "label": "Width", "type": "int", "default": 3, "min": 1, "max": 4},
			{"name": "point", "label": "Point", "type": "int", "default": 2, "min": 0, "max": 3,
				"hint": "0 is blunt, 3 comes to a point"},
			{"name": "jut", "label": "Jut", "type": "int", "default": 1, "min": 0, "max": 3,
				"hint": "How far forward it comes"},
		]
		"ponytail": return [
			{"name": "height", "label": "Height", "type": "int", "default": 1, "min": 0, "max": 3,
				"hint": "0 at the nape, 3 at the crown"},
			{"name": "length", "label": "Length", "type": "int", "default": 3, "min": 1, "max": 5},
			{"name": "thickness", "label": "Thickness", "type": "int", "default": 2, "min": 1, "max": 3},
			{"name": "tie", "label": "Tie in its own colour", "type": "bool", "default": true},
		]
		"bun": return [
			{"name": "position", "label": "Position", "type": "enum", "default": "back", "options": BUN_POSITIONS},
			{"name": "size", "label": "Size", "type": "int", "default": 2, "min": 1, "max": 3},
		]
		"horns": return [
			{"name": "length", "label": "Length", "type": "int", "default": 2, "min": 1, "max": 5},
			{"name": "curve", "label": "Curve", "type": "int", "default": 1, "min": 0, "max": 3,
				"hint": "0 straight up, 3 swept back"},
			{"name": "spread", "label": "Spread", "type": "int", "default": 1, "min": 0, "max": 3},
			{"name": "thickness", "label": "Thickness", "type": "int", "default": 2, "min": 1, "max": 3},
		]
		"pauldrons": return [
			{"name": "size", "label": "Size", "type": "int", "default": 2, "min": 1, "max": 3},
			{"name": "drop", "label": "Drop", "type": "int", "default": 1, "min": 0, "max": 3,
				"hint": "How far down the arm"},
		]
		"straps": return [
			{"name": "width", "label": "Strap width", "type": "int", "default": 1, "min": 1, "max": 2},
		]
	return []


static func anchor_names() -> Array[String]:
	var out: Array[String] = []
	for key in ANCHORS.keys():
		out.append(String(key))
	return out


static func default_params(type: String) -> Dictionary:
	var out := {}
	for entry in param_spec(type):
		var e: Dictionary = entry
		var value: Variant = e["default"]
		# A fresh copy: a shared default array would be one shape's cells drawn into every new shape.
		if value is Array:
			value = (value as Array).duplicate(true)
		out[String(e["name"])] = value
	return out


## Fill in anything the stored settings are missing, so an item saved before a setting existed still builds.
static func with_defaults(type: String, params: Dictionary) -> Dictionary:
	var out := default_params(type)
	for key in params.keys():
		if out.has(key):
			out[key] = params[key]
	return out
