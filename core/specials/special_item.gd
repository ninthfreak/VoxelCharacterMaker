@tool
class_name SpecialItem
extends RefCounted

## Special shapes: pieces the region-and-bulk system cannot express -- skirts, capes, straps, beards, hoods, drawn
## shapes (SPEC.md section 7.4). An item can carry several, alongside its regions; each has a few settings, and
## lengths are named by body bands ("to the knee"), not heights.
##
## This is the table of them: their names, their settings and their defaults, from which the editor builds its
## controls (a new type needs no editor change). The low-poly figure builds them (core/lowpoly/: LowpolyShapes for
## straps, skirt and cape, LowpolyFacialHair for facial hair). The hood and drawn shapes are kept in the wardrobe
## file with their settings, and not built yet: the figure's warnings say so.

const OPENINGS: Array[String] = ["none", "wrap", "front"]
const SIDES: Array[String] = ["left", "right"]
const MAX_SLANT := 6

## Where a drawn shape hangs from: name -> label. (The shapes themselves are drawn cells, kept in the file; the
## low-poly figure does not draw them yet.)
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


static func types() -> Array[String]:
	return ["skirt", "cape", "hood", "straps", "shape", "facial_hair"]


## Types that hang clear of the figure. They are placed after everything else that is worn, in draw order among
## themselves, so a skirt clears boots put on "after" it.
static func hangs_clear(type: String) -> bool:
	return type in ["skirt", "cape"]


## Whether the low-poly figure builds this type yet.
static func is_built(type: String) -> bool:
	return type in ["skirt", "cape", "straps", "facial_hair"]


static func display_name(type: String) -> String:
	match type:
		"hood": return "Hood"
		"skirt": return "Skirt"
		"cape": return "Cape"
		"shape": return "Drawn shape"
		"straps": return "Shoulder straps"
		"facial_hair": return "Facial hair"
	return type


## Where a type attaches, in words, for the editor. A drawn shape's anchor is a setting, so the caller passes the
## settings to get its actual anchor.
static func anchor_description(type: String, params: Dictionary = {}) -> String:
	match type:
		"hood": return "Anchored to the head. Not on the low-poly figure yet: its settings are kept."
		"skirt": return "Hangs from the waist line; laid afresh over the legs in every pose."
		"cape": return "Hangs from the shoulder line at the back; laid afresh in every pose."
		"shape":
			var anchor := String(params.get("anchor", "chest"))
			return "Anchored at: %s. Drawn shapes are not on the low-poly figure yet: the drawing is kept." \
				% String(ANCHORS.get(anchor, anchor))
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
			{"name": "depth", "label": "Thickness", "type": "int", "default": 1, "min": 1, "max": 3},
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
