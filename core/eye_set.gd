@tool
class_name EyeSet
extends RefCounted

## An eye style: the open eye, drawn once (SPEC.md 5).
##
## Every look -- neutral, blink, angry, a wink -- is made by the lid-and-brow
## system (EyeLids) over this one drawing, so a set is just the open eye and its
## colours. (The old per-expression drawings were retired by the owner; a file
## that still has them loads its "neutral" drawing as the eye.)
##
## Eyes work like clothes. Their roles -- white, pupil, line -- take colours from
## the wardrobe palette through colourways, so eye colour is a colourway. They
## are not optional: every character has exactly one eye set.
##
## The drawing is stored per eye in BOX CELLS: c counts from that eye's OUTER
## edge, r from its bottom row, and the screen-right eye is mirrored. Only
## painted cells are stored -- an absent cell is skin.

## The eye box, shared by every head (SPEC 5), from BodyLayout: 5 wide x 6
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

## The drawing's name in older files, which kept one per expression.
const LEGACY_NEUTRAL := "neutral"
const DEFAULT_COLOURWAY := "default"

var id: String = ""
var name: String = ""
## colourway name -> {role -> palette colour name}
var colourways: Dictionary = {}
## The open eye: {"left": {Vector2i: role}, "right": {Vector2i: role}}
var cells: Dictionary = {EYE_LEFT: {}, EYE_RIGHT: {}}


static func create(p_id: String, p_name: String) -> EyeSet:
	var eyes := EyeSet.new()
	eyes.id = p_id
	eyes.name = p_name
	eyes.colourways = {DEFAULT_COLOURWAY: default_colours()}
	return eyes


## The palette names the stock eye colours use. Wardrobe.create_default puts
## these in the palette.
static func default_colours() -> Dictionary:
	return {ROLE_WHITE: "eye_white", ROLE_PUPIL: "eye_dark", ROLE_LINE: "lid"}


## The shipped open eye (assets/face42_open.json) as an eye set.
static func from_library(library: AssetLibrary, p_id: String = "standard",
		p_name: String = "Standard") -> EyeSet:
	var eyes := EyeSet.create(p_id, p_name)
	var face := library.open_face()
	if face != null:
		eyes.cells = {EYE_LEFT: _painted(face.screen_left), EYE_RIGHT: _painted(face.screen_right)}
	return eyes


static func _painted(source: Dictionary) -> Dictionary:
	var out := {}
	for cell in source.keys():
		var role := String(source[cell])
		if role != ROLE_SKIN:
			out[cell] = role
	return out


# ---------------------------------------------------------------- drawing --

## The painted cells of one eye: Vector2i(c, r) -> role.
func eye_cells(eye: String) -> Dictionary:
	return cells.get(eye, {})


func role_at(eye: String, c: int, r: int) -> String:
	return String(eye_cells(eye).get(Vector2i(c, r), ROLE_SKIN))


## Paint one box cell. `role` of "skin" clears it. With `both_eyes`, the other
## eye gets the same cell -- the box cells already count from each eye's outer
## edge, so "the same cell" IS the mirror image.
func set_cell(eye: String, c: int, r: int, role: String, both_eyes: bool = false) -> void:
	if c < 0 or c >= BOX_W or r < 0 or r >= BOX_H:
		return
	var which_eyes: Array[String] = [eye]
	if both_eyes:
		which_eyes = [EYE_LEFT, EYE_RIGHT]
	for which in which_eyes:
		if not cells.has(which):
			cells[which] = {}
		var eye_map: Dictionary = cells[which]
		if role == ROLE_SKIN or role.is_empty():
			eye_map.erase(Vector2i(c, r))
		else:
			eye_map[Vector2i(c, r)] = role


func is_symmetric() -> bool:
	return eye_cells(EYE_LEFT) == eye_cells(EYE_RIGHT)


## Box cell -> absolute voxel, for one eye.
static func cell_to_voxel(c: int, r: int, eye: String) -> Vector3i:
	var x := (VoxelAxes.MIRROR_X_MAX - BOX_X0) - c if eye == EYE_RIGHT else BOX_X0 + c
	return Vector3i(x, VoxelAxes.FACE_PLANE_Y, BOX_Z0 + r)


## The drawing as absolute voxels: Vector3i -> role.
func to_absolute() -> Dictionary:
	var out := {}
	for eye in [EYE_LEFT, EYE_RIGHT]:
		var eye_map := eye_cells(eye)
		for cell in eye_map.keys():
			var c: Vector2i = cell
			out[cell_to_voxel(c.x, c.y, eye)] = eye_map[cell]
	return out


## Painted cells that do not land on a head's face plane: an eye drawn there
## would simply not appear on that head (SPEC 12: "no eye cell falls off").
func missing_on_head(head: HeadDef) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell in to_absolute().keys():
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
	return {"name": name, "colourways": ways, "eye": {
		EYE_LEFT: _cells_to_list(eye_cells(EYE_LEFT)),
		EYE_RIGHT: _cells_to_list(eye_cells(EYE_RIGHT)),
	}}


static func _cells_to_list(source: Dictionary) -> Array:
	var keys := source.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	var out: Array = []
	for k in keys:
		var c: Vector2i = k
		out.append([c.x, c.y, String(source[k])])
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
	# Older files kept a drawing per expression; their neutral one is the eye.
	var drawing: Dictionary = data.get("eye", {})
	if drawing.is_empty():
		drawing = (data.get("expressions", {}) as Dictionary).get(LEGACY_NEUTRAL, {})
	eyes.cells = {
		EYE_LEFT: _list_to_cells(drawing.get(EYE_LEFT, [])),
		EYE_RIGHT: _list_to_cells(drawing.get(EYE_RIGHT, [])),
	}
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
