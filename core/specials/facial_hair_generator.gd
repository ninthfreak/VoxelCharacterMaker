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


static func param_spec() -> Array:
	return [
		{"name": "style", "label": "Style", "type": "enum", "default": "stubble",
			"options": STYLES},
	]


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
	var style := String(params.get("style", "stubble"))
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
