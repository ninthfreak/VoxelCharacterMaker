@tool
class_name ShapeGrid
extends Control

## The grid for a drawn shape: one layer of it at a time, as it would be seen
## looking at the anchor.
##
## The axes are named from the anchor's own frame and written on the grid,
## because "across" and "up" mean different things on the face, the crown and
## the hip, and a wrong guess silently mirrors or rotates the work. The anchor
## point is marked; with mirroring on (for anchors on the centre line) the
## mirror line is drawn and the mirrored half shows as a ghost.
##
## Layer 0 is the first voxel outside the surface; -1 is the surface itself,
## which recolours rather than adds.

signal stroke_finished

const ROLE_INK := Color8(20, 20, 26)

## Vector3i(a, b, c) -> role
var cells: Dictionary = {}
var anchor_name: String = "chest"
var layer: int = 0
var mirror := true
var role: String = "cloth"
## role -> Color
var colours: Dictionary = {}

var _dragging := false
var _erasing := false
var _changed := false


func _init() -> void:
	custom_minimum_size = Vector2(340, 400)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func columns() -> int:
	return ShapeGenerator.A_MAX - ShapeGenerator.A_MIN + 1


func rows() -> int:
	return ShapeGenerator.C_MAX - ShapeGenerator.C_MIN + 1


func cell_size() -> float:
	return floorf(minf((size.x - 20.0) / float(columns()),
		(size.y - 52.0) / float(rows())))


func origin() -> Vector2:
	var s := cell_size()
	return Vector2((size.x - s * columns()) * 0.5, 22.0)


func rect_of(a: int, c: int) -> Rect2:
	var s := cell_size()
	var col := float(a - ShapeGenerator.A_MIN)
	var row := float(ShapeGenerator.C_MAX - c)
	return Rect2(origin() + Vector2(col * s, row * s), Vector2(s, s))


func hit(point: Vector2) -> Variant:
	var s := cell_size()
	if s <= 0.0:
		return null
	var local := point - origin()
	var a := floori(local.x / s) + ShapeGenerator.A_MIN
	var c := ShapeGenerator.C_MAX - floori(local.y / s)
	if a < ShapeGenerator.A_MIN or a > ShapeGenerator.A_MAX:
		return null
	if c < ShapeGenerator.C_MIN or c > ShapeGenerator.C_MAX:
		return null
	return Vector2i(a, c)


## Whether the anchor sits on the centre line, so the shape mirrors in-grid.
func mirrors_in_grid() -> bool:
	var d: Array = Anchors.DEFINITIONS.get(anchor_name, [])
	return mirror and not d.is_empty() and (d[3] as Vector3i) == Anchors.ACROSS


static func _axis_word(v: Vector3i) -> String:
	if v == Anchors.ACROSS:
		return "character's left"
	if v == Anchors.FORWARD:
		return "front"
	if v == Anchors.RISE:
		return "up"
	if v == Anchors.BACK:
		return "back"
	return str(v)


static func _out_word(v: Vector3i) -> String:
	if v == Anchors.FRONT:
		return "out of the front"
	if v == Anchors.BACK:
		return "out of the back"
	if v == Anchors.UP:
		return "up off the top"
	if v == Anchors.SIDE:
		return "out to the side"
	return str(v)


func layer_label() -> String:
	if layer < 0:
		return "layer %d: the surface itself (recolours, adds nothing)" % layer
	var d: Array = Anchors.DEFINITIONS.get(anchor_name, [])
	var out := _out_word(d[2]) if not d.is_empty() else ""
	return "layer %d: %d voxel%s %s" % [layer, layer + 1, "" if layer == 0 else "s", out]


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var s := cell_size()
	var o := origin()
	var dim := Color8(150, 158, 174)
	var full := Rect2(o, Vector2(s * columns(), s * rows()))
	draw_rect(full, Color8(24, 27, 35), true)

	var d: Array = Anchors.DEFINITIONS.get(anchor_name, [])
	var across := _axis_word(d[3]) if not d.is_empty() else "across"
	var up := _axis_word(d[4]) if not d.is_empty() else "up"
	draw_string(font, o + Vector2(0, -6), "%s ^" % up, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	draw_string(font, o + Vector2(s * columns() - 130, -6), "%s >" % across,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)

	# Other layers, faintly, so the shape is drawn with its depth in view.
	for key in cells.keys():
		var k: Vector3i = key
		if k.y == layer:
			continue
		var r := rect_of(k.x, k.z)
		draw_rect(Rect2(r.position + r.size * 0.3, r.size * 0.4), Color(1, 1, 1, 0.18), true)

	# The mirrored half, as a ghost.
	if mirrors_in_grid():
		for key2 in cells.keys():
			var m: Vector3i = key2
			if m.y != layer:
				continue
			var ma := -1 - m.x
			if ma < ShapeGenerator.A_MIN or ma > ShapeGenerator.A_MAX:
				continue
			if cells.has(Vector3i(ma, layer, m.z)):
				continue
			var colour: Color = colours.get(String(cells[key2]), Color.MAGENTA)
			colour.a = 0.35
			draw_rect(rect_of(ma, m.z), colour, true)

	# This layer.
	for key3 in cells.keys():
		var k3: Vector3i = key3
		if k3.y != layer:
			continue
		var rect := rect_of(k3.x, k3.z)
		var role_name := String(cells[key3])
		var colour2: Color = colours.get(role_name, Color.MAGENTA)
		draw_rect(rect, colour2, true)
		if s >= 12.0:
			var ink := Color.BLACK if colour2.get_luminance() > 0.5 else Color.WHITE
			draw_string(font, rect.position + Vector2(s * 0.3, s * 0.72),
				role_name.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(s * 0.5), ink)

	# Lattice, the anchor point, and the mirror line.
	var faint := Color(1, 1, 1, 0.07)
	for i in range(columns() + 1):
		var x := o.x + float(i) * s
		draw_line(Vector2(x, o.y), Vector2(x, o.y + s * rows()), faint, 1.0)
	for j in range(rows() + 1):
		var y := o.y + float(j) * s
		draw_line(Vector2(o.x, y), Vector2(o.x + s * columns(), y), faint, 1.0)
	var anchor_rect := rect_of(0, 0)
	draw_rect(anchor_rect, Palette.UI_SKY, false, 2.0)
	if mirrors_in_grid():
		var mx := rect_of(0, 0).position.x
		draw_line(Vector2(mx, o.y), Vector2(mx, o.y + s * rows()),
			Color8(240, 228, 66, 190), 2.0)
	draw_rect(full, Color(1, 1, 1, 0.22), false, 1.0)

	draw_string(font, Vector2(o.x, o.y + s * rows() + 16), layer_label(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	draw_string(font, Vector2(o.x, o.y + s * rows() + 30),
		"blue box: the anchor point   left click paints %s, right click erases" % role,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)


func _gui_input(event: InputEvent) -> void:
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
	var h: Variant = hit(point)
	if h == null:
		return
	var at: Vector2i = h
	var key := Vector3i(at.x, layer, at.y)
	if _erasing:
		if not cells.has(key):
			return
		cells.erase(key)
	else:
		if String(cells.get(key, "")) == role:
			return
		cells[key] = role
	_changed = true
	queue_redraw()
