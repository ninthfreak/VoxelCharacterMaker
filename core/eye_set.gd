@tool
class_name EyeSet
extends RefCounted

## An eye style: the whole expression list drawn in one style (SPEC.md 5).
##
## The hand-off's eye-set sheet shows two sets, "G" and "H", each drawn through
## the same eleven expressions. So a set is a STYLE and the expression list is
## shared: switching a character's eye set keeps the expression it is making,
## and blinking works the same whichever set is on.
##
## Eyes work like clothes. Their roles -- white, pupil, line -- take colours from
## the wardrobe palette through colourways, so eye colour is a colourway. They
## are not optional: every character has exactly one eye eyes.
##
## Each expression is stored per eye in BOX CELLS, exactly as the shipped face
## files are: c counts from that eye's OUTER edge, r from its bottom row, and
## the screen-right eye is mirrored. Symmetric expressions hold the same cells
## twice; asymmetric ones (wink, look left/right) differ. Only painted cells are
## stored -- an absent cell is skin, which is what the overlay leaves alone.

## The eye box, shared by every head (SPEC 5), from BodyLayout: 4 wide x 5
## tall, screen-left eye starting at BOX_X0, bottom row BOX_Z0, on the face plane.
const BOX_W := BodyLayout.EYE_W
const BOX_H := BodyLayout.EYE_H
const BOX_X0 := BodyLayout.EYE_X0
const BOX_Z0 := BodyLayout.EYE_Z0

const ROLE_WHITE := "white"
const ROLE_PUPIL := "pupil"
const ROLE_LINE := "line"
const ROLE_SKIN := "skin"
## The roles a cell can be painted with. Skin is "not painted".
const ROLES: Array[String] = [ROLE_WHITE, ROLE_PUPIL, ROLE_LINE]

const EYE_LEFT := "left"     ## the SCREEN-left eye (the character's right)
const EYE_RIGHT := "right"   ## the screen-right eye

const NEUTRAL := "neutral"
const DEFAULT_COLOURWAY := "default"

var id: String = ""
var name: String = ""
## colourway name -> {role -> palette colour name}
var colourways: Dictionary = {}
## expression name -> {"left": {Vector2i: role}, "right": {Vector2i: role}}
var expressions: Dictionary = {}


static func create(p_id: String, p_name: String) -> EyeSet:
	var eyes := EyeSet.new()
	eyes.id = p_id
	eyes.name = p_name
	eyes.colourways = {DEFAULT_COLOURWAY: default_colours()}
	eyes.expressions = {NEUTRAL: {EYE_LEFT: {}, EYE_RIGHT: {}}}
	return eyes


## The palette names the stock eye colours use. Wardrobe.create_default puts
## these in the palette.
static func default_colours() -> Dictionary:
	return {ROLE_WHITE: "eye_white", ROLE_PUPIL: "eye_dark", ROLE_LINE: "lid"}


## The shipped expressions (assets/face42_*.json) as an eye eyes.
static func from_library(library: AssetLibrary, p_id: String = "standard",
		p_name: String = "Standard") -> EyeSet:
	var eyes := EyeSet.create(p_id, p_name)
	eyes.expressions.clear()
	for expression in library.expression_names():
		var face := library.face(expression)
		if face == null:
			continue
		eyes.expressions[expression] = {
			EYE_LEFT: _painted(face.screen_left),
			EYE_RIGHT: _painted(face.screen_right),
		}
	if not eyes.expressions.has(NEUTRAL):
		eyes.expressions[NEUTRAL] = {EYE_LEFT: {}, EYE_RIGHT: {}}
	return eyes


static func _painted(cells: Dictionary) -> Dictionary:
	var out := {}
	for cell in cells.keys():
		var role := String(cells[cell])
		if role != ROLE_SKIN:
			out[cell] = role
	return out


# ------------------------------------------------------------ expressions --

## Expression names, the stock ones first in their usual order.
func expression_names() -> Array[String]:
	var out: Array[String] = []
	for stock in AssetLibrary.EXPRESSION_ORDER:
		if expressions.has(stock):
			out.append(stock)
	var extras: Array[String] = []
	for key in expressions.keys():
		if not (String(key) in out):
			extras.append(String(key))
	extras.sort()
	out.append_array(extras)
	return out


func has_expression(expression: String) -> bool:
	return expressions.has(expression)


## The expression actually drawn: the one asked for, or neutral when this set
## does not define it, so a character never loses its eyes.
func resolve(expression: String) -> String:
	if expressions.has(expression):
		return expression
	return NEUTRAL if expressions.has(NEUTRAL) else (expression_names()[0]
		if not expressions.is_empty() else "")


## The painted cells of one eye: Vector2i(c, r) -> role.
func eye_cells(expression: String, eye: String) -> Dictionary:
	var e: Dictionary = expressions.get(resolve(expression), {})
	return e.get(eye, {})


func role_at(expression: String, eye: String, c: int, r: int) -> String:
	return String(eye_cells(expression, eye).get(Vector2i(c, r), ROLE_SKIN))


## Paint one box cell. `role` of "skin" clears it. With `both_eyes`, the other
## eye gets the same cell -- the box cells already count from each eye's outer
## edge, so "the same cell" IS the mirror image.
func set_cell(expression: String, eye: String, c: int, r: int, role: String,
		both_eyes: bool = false) -> void:
	if not expressions.has(expression):
		return
	if c < 0 or c >= BOX_W or r < 0 or r >= BOX_H:
		return
	var eyes: Array[String] = [eye]
	if both_eyes:
		eyes = [EYE_LEFT, EYE_RIGHT]
	for which in eyes:
		var cells: Dictionary = (expressions[expression] as Dictionary)[which]
		if role == ROLE_SKIN or role.is_empty():
			cells.erase(Vector2i(c, r))
		else:
			cells[Vector2i(c, r)] = role


func is_symmetric(expression: String) -> bool:
	return eye_cells(expression, EYE_LEFT) == eye_cells(expression, EYE_RIGHT)


func add_expression(expression: String, copy_from: String = "") -> bool:
	if expression.is_empty() or expressions.has(expression):
		return false
	var source: Dictionary = expressions.get(copy_from, {})
	expressions[expression] = {
		EYE_LEFT: (source.get(EYE_LEFT, {}) as Dictionary).duplicate(),
		EYE_RIGHT: (source.get(EYE_RIGHT, {}) as Dictionary).duplicate(),
	}
	return true


func rename_expression(old_name: String, new_name: String) -> bool:
	if old_name == NEUTRAL or new_name.is_empty() or expressions.has(new_name):
		return false
	if not expressions.has(old_name):
		return false
	expressions[new_name] = expressions[old_name]
	expressions.erase(old_name)
	return true


## Neutral cannot go: it is what every missing expression falls back to.
func remove_expression(expression: String) -> bool:
	if expression == NEUTRAL or not expressions.has(expression):
		return false
	expressions.erase(expression)
	return true


## Box cell -> absolute voxel, for one eye.
static func cell_to_voxel(c: int, r: int, eye: String) -> Vector3i:
	var x := (VoxelAxes.MIRROR_X_MAX - BOX_X0) - c if eye == EYE_RIGHT else BOX_X0 + c
	return Vector3i(x, VoxelAxes.FACE_PLANE_Y, BOX_Z0 + r)


## The whole expression as absolute voxels: Vector3i -> role.
func to_absolute(expression: String) -> Dictionary:
	var out := {}
	for eye in [EYE_LEFT, EYE_RIGHT]:
		var cells := eye_cells(expression, eye)
		for cell in cells.keys():
			var c: Vector2i = cell
			out[cell_to_voxel(c.x, c.y, eye)] = cells[cell]
	return out


## Painted cells that do not land on a head's face plane: an eye drawn there
## would simply not appear on that head (SPEC 12: "no eye cell falls off").
func missing_on_head(expression: String, head: HeadDef) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell in to_absolute(expression).keys():
		if not head.cells.has(cell):
			out.append(cell)
	return out


# -------------------------------------------------------------- colours ----

func colourway_names() -> Array[String]:
	var out: Array[String] = []
	for k in colourways.keys():
		out.append(String(k))
	out.sort()
	return out


func first_colourway() -> String:
	if colourways.has(DEFAULT_COLOURWAY):
		return DEFAULT_COLOURWAY
	var names := colourway_names()
	return names[0] if not names.is_empty() else ""


func palette_key_for(colourway: String, role: String) -> String:
	var set_for: Dictionary = colourways.get(colourway, {})
	return String(set_for.get(role, ""))


func set_palette_key(colourway: String, role: String, palette_key: String) -> void:
	if not colourways.has(colourway):
		colourways[colourway] = {}
	(colourways[colourway] as Dictionary)[role] = palette_key


func add_colourway(colourway: String, copy_from: String = "") -> void:
	if colourways.has(colourway):
		return
	var source: Dictionary = colourways.get(copy_from, default_colours())
	colourways[colourway] = source.duplicate()


# --------------------------------------------------------------- JSON I/O ---

func to_json() -> Dictionary:
	var ways := {}
	for colourway in colourways.keys():
		var set_for: Dictionary = colourways[colourway]
		var copy := {}
		for role in set_for.keys():
			copy[String(role)] = String(set_for[role])
		ways[String(colourway)] = copy
	var exprs := {}
	for expression in expressions.keys():
		var e: Dictionary = expressions[expression]
		exprs[String(expression)] = {
			EYE_LEFT: _cells_to_list(e.get(EYE_LEFT, {})),
			EYE_RIGHT: _cells_to_list(e.get(EYE_RIGHT, {})),
		}
	return {"name": name, "colourways": ways, "expressions": exprs}


static func _cells_to_list(cells: Dictionary) -> Array:
	var keys := cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	var out: Array = []
	for k in keys:
		var c: Vector2i = k
		out.append([c.x, c.y, String(cells[k])])
	return out


static func from_json(p_id: String, data: Dictionary) -> EyeSet:
	var eyes := EyeSet.new()
	eyes.id = p_id
	eyes.name = String(data.get("name", p_id))
	var ways: Dictionary = data.get("colourways", {})
	for colourway in ways.keys():
		var set_for: Dictionary = ways[colourway]
		var copy := {}
		for role in set_for.keys():
			copy[String(role)] = String(set_for[role])
		eyes.colourways[String(colourway)] = copy
	if eyes.colourways.is_empty():
		eyes.colourways[DEFAULT_COLOURWAY] = default_colours()
	var exprs: Dictionary = data.get("expressions", {})
	for expression in exprs.keys():
		var e: Dictionary = exprs[expression]
		eyes.expressions[String(expression)] = {
			EYE_LEFT: _list_to_cells(e.get(EYE_LEFT, [])),
			EYE_RIGHT: _list_to_cells(e.get(EYE_RIGHT, [])),
		}
	if not eyes.expressions.has(NEUTRAL):
		eyes.expressions[NEUTRAL] = {EYE_LEFT: {}, EYE_RIGHT: {}}
	return eyes


static func _list_to_cells(list: Variant) -> Dictionary:
	var out := {}
	for entry in (list as Array):
		var e: Array = entry
		var role := String(e[2])
		if role == ROLE_SKIN:
			continue
		out[Vector2i(int(e[0]), int(e[1]))] = role
	return out


func duplicate_as(new_id: String, new_name: String) -> EyeSet:
	var copy := EyeSet.from_json(new_id, to_json())
	copy.name = new_name
	return copy
