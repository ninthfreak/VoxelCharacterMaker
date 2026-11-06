@tool
class_name EyeBoxGrid
extends Control

## The face editor's grid (SPEC.md section 8: "a grid of the eye box; edit one
## eye, the other mirrors").
##
## Both eyes are drawn side by side as they appear on the face -- screen-left
## eye on the left -- each EyeSet.BOX_W wide by EyeSet.BOX_H tall. With "both eyes" on, painting one
## paints the same box cell in the other, which IS the mirror image because box
## cells count from each eye's outer edge.
##
## Every painted cell carries its role's first letter (W, P, L) as well as its
## colour. Pupil-dark and lid-brown are both dark, and the owner is red/green
## colour blind: the letter is what tells them apart.

signal painted(eye: String, c: int, r: int, role: String)
signal stroke_finished

const GAP := 1.5   ## gap between the two eyes, in cells

var eye_set: EyeSet = null
## The role a left click paints; right click always paints skin (clears).
var role: String = EyeSet.ROLE_PUPIL
var both_eyes := true
## role -> Color, from the colourway being looked at.
var colours: Dictionary = {}
var skin_colour: Color = Palette.SKIN_MID

var _dragging := false
var _erasing := false
var _changed := false


func _init() -> void:
	custom_minimum_size = Vector2(320, 230)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func cell_size() -> float:
	var across := float(EyeSet.BOX_W * 2) + GAP
	return floorf(minf((size.x - 16.0) / across, (size.y - 48.0) / float(EyeSet.BOX_H)))


func origin() -> Vector2:
	var s := cell_size()
	var w := (float(EyeSet.BOX_W * 2) + GAP) * s
	return Vector2((size.x - w) * 0.5, 22.0)


## The screen position of a box cell. The screen-left eye's outer edge is its
## LEFT side; the screen-right eye's outer edge is its RIGHT side, so its c
## runs right to left. r = 0 is the bottom row.
func rect_of(eye: String, c: int, r: int) -> Rect2:
	var s := cell_size()
	var o := origin()
	var col := float(c) if eye == EyeSet.EYE_LEFT \
		else float(EyeSet.BOX_W) + GAP + float(EyeSet.BOX_W - 1 - c)
	var row := float(EyeSet.BOX_H - 1 - r)
	return Rect2(o + Vector2(col * s, row * s), Vector2(s, s))


func hit(point: Vector2) -> Dictionary:
	for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
		for c in EyeSet.BOX_W:
			for r in EyeSet.BOX_H:
				if rect_of(eye, c, r).has_point(point):
					return {"eye": eye, "c": c, "r": r}
	return {}


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var s := cell_size()
	var dim := Color8(150, 158, 174)
	draw_string(font, Vector2(rect_of(EyeSet.EYE_LEFT, 0, EyeSet.BOX_H - 1).position.x, 14),
		"screen-left eye", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	draw_string(font, Vector2(rect_of(EyeSet.EYE_RIGHT, EyeSet.BOX_W - 1,
		EyeSet.BOX_H - 1).position.x, 14), "screen-right eye", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 12, dim)
	if eye_set == null:
		return
	for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
		for c in EyeSet.BOX_W:
			for r in EyeSet.BOX_H:
				var rect := rect_of(eye, c, r)
				var cell_role := eye_set.role_at(eye, c, r)
				var colour: Color = skin_colour if cell_role == EyeSet.ROLE_SKIN \
					else colours.get(cell_role, Color.MAGENTA)
				draw_rect(rect, colour, true)
				draw_rect(rect, Color(0, 0, 0, 0.35), false, 1.0)
				if cell_role != EyeSet.ROLE_SKIN:
					var letter := cell_role.substr(0, 1).to_upper()
					var ink := Color.BLACK if colour.get_luminance() > 0.5 else Color.WHITE
					draw_string(font, rect.position + Vector2(s * 0.34, s * 0.66), letter,
						HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.42), ink)
	draw_string(font, Vector2(origin().x, size.y - 6),
		"left click paints %s, right click clears to skin%s" % [
			role, ", both eyes" if both_eyes else ", this eye only"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)


func _gui_input(event: InputEvent) -> void:
	if eye_set == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mb.pressed:
			_dragging = true
			_erasing = mb.button_index == MOUSE_BUTTON_RIGHT
			_changed = false
			_paint_at(mb.position)
		else:
			_dragging = false
			if _changed:
				stroke_finished.emit()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_paint_at((event as InputEventMouseMotion).position)
		accept_event()


func _paint_at(point: Vector2) -> void:
	var h := hit(point)
	if h.is_empty():
		return
	var paint_role := EyeSet.ROLE_SKIN if _erasing else role
	var eye := String(h["eye"])
	var c := int(h["c"])
	var r := int(h["r"])
	if eye_set.role_at(eye, c, r) == paint_role \
			and (not both_eyes or eye_set.role_at(
				EyeSet.EYE_RIGHT if eye == EyeSet.EYE_LEFT else EyeSet.EYE_LEFT, c, r) == paint_role):
		return
	eye_set.set_cell(eye, c, r, paint_role, both_eyes)
	_changed = true
	painted.emit(eye, c, r, paint_role)
	queue_redraw()
