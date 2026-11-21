@tool
class_name FacialHairGenerator
extends RefCounted

## Facial hair that follows each head's own surface (SPEC.md section 5).
##
## At 24 voxels a metre there are three rows of face under the eyes, so facial
## hair is a matter of coverage and depth, not detail. The owner chose three
## styles, built from two layers:
##
##   STUBBLE  recolours the skin over the jaw, the chin, the jaw's sides and
##            the underside of the chin, and a sideburn strip on each side of
##            the head in front of the ear. No volume. Its colour (role
##            "stubble") is meant to be the "@stubble" reference: always darker
##            than the skin, leaning toward the hair.
##   STRAP    one voxel of hair out from the surface: along the bottom row of
##            the face and jaw sides, and up each side as a raised sideburn.
##            Role "hair", meant to be "@hair".
##
##   stubble     = stubble
##   chinstrap   = strap
##   full_beard  = stubble + strap
##
## Every cell is found by looking at the head itself -- its frontmost cell in
## each column, its outermost cell on each side -- so one definition fits all
## five heads, the narrow-jawed ones included, and an edited head too.

const STYLES: Array[String] = ["stubble", "chinstrap", "full_beard"]
const ROLE_STUBBLE := "stubble"
const ROLE_HAIR := "hair"

## The settings (owner, 2026-11; lowpoly/facial_hair.py): four parts, each on or off, and one length for all of
## them. Stubble is a tint flush with the face, short is opaque and still flush, medium and long grow out. The
## low-poly figure draws exactly that; this voxel generator shows the nearest of its three styles (voxel_style) until
## the editor's move to low-poly retires it.
const PARTS: Array[String] = ["moustache", "sideburns", "goatee", "cheeks"]
const LENGTHS: Array[String] = ["stubble", "short", "medium", "long"]
## The three voxel styles as parts and a length: how a wardrobe file saved with "style" is read now.
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


## The voxel style nearest to a set of parts and a length: "" for no part at all (nothing is drawn), stubble at
## stubble length, the full beard for a moustache with cheeks (or a moustache alone: the voxel face has no moustache,
## and the full beard is the one that covers the lip), the chinstrap for the rest.
static func voxel_style(params: Dictionary) -> String:
	if params.has("style"):
		return ""                           # a style this does not know (migrate keeps it): nothing is drawn
	var any := false
	for part in PARTS:
		any = any or bool(params.get(part, false))
	if not any:
		return ""
	if String(params.get("length", "stubble")) == "stubble":
		return "stubble"
	if bool(params.get("moustache", false)) and bool(params.get("cheeks", false)):
		return "full_beard"
	if bool(params.get("sideburns", false)) or bool(params.get("cheeks", false)) or bool(params.get("goatee", false)):
		return "chinstrap"
	return "full_beard"


## The rows the layers use, all from the shared layout.
static func jaw_rows() -> Vector2i:
	return Vector2i(BodyLayout.HEAD_BOTTOM, BodyLayout.EYE_Z0 - 1)


static func sideburn_rows() -> Vector2i:
	return Vector2i(BodyLayout.EYE_Z0, BodyLayout.EYE_Z1 - 1)


## Depths on the head's side: the jaw from the face back to the middle, the
## sideburn a three-deep strip just in front of the ears.
static func jaw_depths() -> Vector2i:
	return Vector2i(BodyLayout.FACE_PLANE_Y, VoxelAxes.DEPTH_CENTRE)


static func sideburn_depths() -> Vector2i:
	return Vector2i(VoxelAxes.DEPTH_CENTRE - 4, VoxelAxes.DEPTH_CENTRE - 2)


static func generate(ctx: SpecialItem.Context, params: Dictionary) -> SpecialItem.Result:
	var out := SpecialItem.Result.new()
	var head := ctx.cells_of(BodyDef.HEAD_PART)
	if head.is_empty():
		out.warnings.append("no head to grow facial hair on")
		return out
	var style := voxel_style(params)
	if style.is_empty():
		return out                          # every part switched off: clean-shaven
	if not (style in STYLES):
		out.warnings.append("unknown facial hair style '%s'" % style)
		return out
	var front := _frontmost(head)
	var sides := _outermost(head)
	if style == "stubble" or style == "full_beard":
		_stubble(head, front, sides, out)
	if style == "chinstrap" or style == "full_beard":
		_strap(head, front, sides, out)
	return out


static func _stubble(head: Dictionary, front: Dictionary, sides: Dictionary,
		out: SpecialItem.Result) -> void:
	var done := {}
	var jaw := jaw_rows()
	for key in front.keys():
		var xz: Vector2i = key
		if xz.y >= jaw.x and xz.y <= jaw.y:
			_recolour(out, done, front[key])
	var jd := jaw_depths()
	var sd := sideburn_depths()
	var sb := sideburn_rows()
	for key in sides.keys():
		var yz: Vector2i = key
		var on_jaw := yz.y >= jaw.x and yz.y <= jaw.y and yz.x >= jd.x and yz.x <= jd.y
		var on_sideburn := yz.y >= sb.x and yz.y <= sb.y and yz.x >= sd.x and yz.x <= sd.y
		if on_jaw or on_sideburn:
			for cell in sides[key]:
				_recolour(out, done, cell)
	# The underside of the chin, in front of the neck.
	for cell in head.keys():
		var c: Vector3i = cell
		if c.z == jaw.x and c.y <= BodyLayout.FACE_PLANE_Y + 3 \
				and absi(2 * c.x - (VoxelAxes.MIRROR_X_MAX)) <= 9:
			_recolour(out, done, c)


static func _strap(head: Dictionary, front: Dictionary, sides: Dictionary,
		out: SpecialItem.Result) -> void:
	var done := {}
	var bottom := BodyLayout.HEAD_BOTTOM
	for key in front.keys():
		var xz: Vector2i = key
		if xz.y == bottom:
			_add(out, done, head, (front[key] as Vector3i) + Vector3i(0, -1, 0))
	var jd := jaw_depths()
	var sd := sideburn_depths()
	var sb_top := sideburn_rows().y
	for key in sides.keys():
		var yz: Vector2i = key
		var on_jaw := yz.y == bottom and yz.x >= jd.x and yz.x <= jd.y
		var on_sideburn := yz.y > bottom and yz.y <= sb_top and yz.x >= sd.x and yz.x <= sd.y
		if on_jaw or on_sideburn:
			var pair: Array = sides[key]
			_add(out, done, head, (pair[0] as Vector3i) + Vector3i(-1, 0, 0))
			_add(out, done, head, (pair[1] as Vector3i) + Vector3i(1, 0, 0))


static func _recolour(out: SpecialItem.Result, done: Dictionary, cell: Vector3i) -> void:
	if done.has(cell):
		return
	done[cell] = true
	out.claim(BodyDef.HEAD_PART, cell, ROLE_STUBBLE, 0, true)


static func _add(out: SpecialItem.Result, done: Dictionary, head: Dictionary,
		cell: Vector3i) -> void:
	if done.has(cell) or head.has(cell) or not VoxelAxes.in_grid(cell):
		return
	done[cell] = true
	out.claim(BodyDef.HEAD_PART, cell, ROLE_HAIR, 1)


## Vector2i(x, z) -> the head's frontmost cell (smallest y) in that column.
static func _frontmost(head: Dictionary) -> Dictionary:
	var out := {}
	for cell in head.keys():
		var c: Vector3i = cell
		var key := Vector2i(c.x, c.z)
		if not out.has(key) or c.y < (out[key] as Vector3i).y:
			out[key] = c
	return out


## Vector2i(y, z) -> [leftmost-x cell, rightmost-x cell] of the head in that row.
static func _outermost(head: Dictionary) -> Dictionary:
	var out := {}
	for cell in head.keys():
		var c: Vector3i = cell
		var key := Vector2i(c.y, c.z)
		if not out.has(key):
			out[key] = [c, c]
		else:
			var pair: Array = out[key]
			if c.x < (pair[0] as Vector3i).x:
				pair[0] = c
			if c.x > (pair[1] as Vector3i).x:
				pair[1] = c
	return out
