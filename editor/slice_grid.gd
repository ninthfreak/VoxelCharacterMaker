@tool
class_name SliceGrid
extends Control

## One horizontal slice through the body, drawn as a paintable grid.
##
## A z-slice is the natural unit here because the whole body is organised by
## row bands: a row belongs to exactly one band, and build_bodies.py builds
## each body as boxes over row ranges. So "edit row 22" is the same thought the
## body was designed with.
##
## The view looks DOWN at the slice. The axes are labelled on the grid rather
## than left to intuition, because which way round a top-down cut goes is
## genuinely ambiguous and getting it wrong silently mirrors your work:
##
##   up the screen    = the figure's front (-y), the way it faces
##   right the screen = the character's LEFT (+x)
##
## The mirror line is drawn down the middle. Every edit is mirrored by
## BodyEdit, so the two halves always match and only one of them needs drawing
## attention; the line is there so you can see which half you are on.

signal painted(cells: Array, part_name: String)
signal erased(cells: Array)
signal hovered(cell: Vector3i, owner_part: String)

const GRID := 24
const MIN_CELL := 8.0

## Room reserved inside the control for the axis labels. They used to be drawn
## at negative offsets, which put them on top of whatever sat above the grid.
const MARGIN_TOP := 18.0
const MARGIN_BOTTOM := 34.0

var body: BodyEdit = null
var z: int = 22
var active_part: String = "chest"
## Cells to call out: whatever the validation is complaining about.
var problem_cells: Dictionary = {}
## Draw the part below and above as a faint outline, so a part can be lined up
## with its neighbours without flipping back and forth.
var show_neighbour_rows := true

var _colours: Dictionary = {}
var _dragging := false
var _erasing := false
var _stroke: Array = []
var _hover := Vector3i(-1, -1, -1)


func _init() -> void:
	custom_minimum_size = Vector2(320, 320 + MARGIN_TOP + MARGIN_BOTTOM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


## A stable colour per part. Okabe-Ito, so no two parts are told apart by red
## versus green alone, and left/right of a pair share a hue with different
## lightness rather than being a red/green pair.
func colour_for(part_name: String) -> Color:
	if _colours.has(part_name):
		return _colours[part_name]
	var family := RegionMap.family_of(part_name)
	var families := ["pelvis", "chest", "head", "upper_arm", "forearm", "thigh", "shin"]
	var index := families.find(family)
	var base := Palette.ui_colour(index if index >= 0 else 0)
	if part_name.ends_with("_R"):
		base = base.lightened(0.28)
	_colours[part_name] = base
	return base


func cell_size() -> float:
	var usable := Vector2(size.x, size.y - MARGIN_TOP - MARGIN_BOTTOM)
	return maxf(MIN_CELL, minf(usable.x, usable.y) / float(GRID))


func origin() -> Vector2:
	var s := cell_size()
	var usable_height := size.y - MARGIN_TOP - MARGIN_BOTTOM
	return Vector2(
		(size.x - s * GRID) * 0.5,
		MARGIN_TOP + maxf(0.0, (usable_height - s * GRID) * 0.5))


## Screen point -> the cell under it, or a cell outside the grid.
func cell_at(point: Vector2) -> Vector3i:
	var s := cell_size()
	var local := point - origin()
	var gx := floori(local.x / s)
	var gy := floori(local.y / s)
	return Vector3i(gx, gy, z)


func rect_of(x: int, y: int) -> Rect2:
	var s := cell_size()
	return Rect2(origin() + Vector2(float(x) * s, float(y) * s), Vector2(s, s))


func _draw() -> void:
	var s := cell_size()
	var o := origin()
	var full := Rect2(o, Vector2(s * GRID, s * GRID))
	draw_rect(full, Color8(24, 27, 35), true)

	if body != null:
		if show_neighbour_rows:
			_draw_neighbour_row(z - 1, Color(1, 1, 1, 0.09))
			_draw_neighbour_row(z + 1, Color(1, 1, 1, 0.055))
		_draw_cells(s)

	_draw_lattice(s, o)
	_draw_axis_labels(o, s)
	_draw_hover(s)


func _draw_cells(s: float) -> void:
	for x in GRID:
		for y in GRID:
			var cell := Vector3i(x, y, z)
			var part := body.owner_at(cell)
			if part.is_empty():
				continue
			var colour := colour_for(part)
			if part != active_part and not active_part.is_empty():
				colour = colour.darkened(0.35)
			draw_rect(rect_of(x, y), colour, true)
			if problem_cells.has(cell):
				# A problem is marked with a shape, not only a colour.
				var r := rect_of(x, y)
				draw_rect(r, Palette.UI_ORANGE, false, maxf(1.5, s * 0.14))
				draw_line(r.position, r.position + r.size, Palette.UI_ORANGE,
					maxf(1.0, s * 0.1))


func _draw_neighbour_row(other_z: int, tint: Color) -> void:
	if other_z < 0 or other_z >= VoxelAxes.GRID.z:
		return
	for x in GRID:
		for y in GRID:
			if body.owner_at(Vector3i(x, y, other_z)).is_empty():
				continue
			draw_rect(rect_of(x, y), tint, true)


func _draw_lattice(s: float, o: Vector2) -> void:
	var faint := Color(1, 1, 1, 0.07)
	for i in range(GRID + 1):
		var at := float(i) * s
		draw_line(o + Vector2(at, 0), o + Vector2(at, s * GRID), faint, 1.0)
		draw_line(o + Vector2(0, at), o + Vector2(s * GRID, at), faint, 1.0)

	# The mirror line, between x11 and x12, and the depth centre.
	var mid := o.x + 12.0 * s
	draw_line(Vector2(mid, o.y), Vector2(mid, o.y + s * GRID),
		Color8(240, 228, 66, 190), 2.0)
	var depth := o.y + 12.0 * s
	draw_line(Vector2(o.x, depth), Vector2(o.x + s * GRID, depth),
		Color(1, 1, 1, 0.18), 1.0)
	draw_rect(Rect2(o, Vector2(s * GRID, s * GRID)), Color(1, 1, 1, 0.22), false, 1.0)


## Spelled out, because a top-down slice is ambiguous and a wrong guess
## silently mirrors the work.
func _draw_axis_labels(o: Vector2, s: float) -> void:
	var font := ThemeDB.fallback_font
	var fs := 12
	var dim := Color8(150, 158, 174)
	draw_string(font, o + Vector2(2, -5), "front",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	draw_string(font, o + Vector2(s * GRID - 86, -5), "character's left",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	draw_string(font, o + Vector2(2, s * GRID + 14), "back",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	draw_string(font, o + Vector2(2, s * GRID + 28),
		"row z%d, mirror line down the middle" % z,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)


func _draw_hover(s: float) -> void:
	if _hover.x < 0 or _hover.x >= GRID or _hover.y < 0 or _hover.y >= GRID:
		return
	draw_rect(rect_of(_hover.x, _hover.y), Color(1, 1, 1, 0.75), false, maxf(1.5, s * 0.1))
	# and its mirror, so it is obvious the edit lands twice
	var mirror_x := VoxelAxes.MIRROR_X_MAX - _hover.x
	if mirror_x != _hover.x:
		draw_rect(rect_of(mirror_x, _hover.y), Color(1, 1, 1, 0.33),
			false, maxf(1.0, s * 0.07))


func _gui_input(event: InputEvent) -> void:
	if body == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mb.pressed:
			_dragging = true
			# Right button erases, which saves swapping tools mid-stroke.
			_erasing = mb.button_index == MOUSE_BUTTON_RIGHT
			_stroke.clear()
			_apply_at(mb.position)
		else:
			_finish_stroke()
		accept_event()
		return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var cell := cell_at(mm.position)
		if cell != _hover:
			_hover = cell
			queue_redraw()
			if _in_grid(cell):
				hovered.emit(cell, body.owner_at(cell))
		if _dragging:
			_apply_at(mm.position)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector3i(-1, -1, -1)
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


func _in_grid(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.x < GRID and cell.y >= 0 and cell.y < GRID


## Collect the stroke rather than committing per cell, so a drag is one undo
## step and the pivots are measured once at the end.
func _apply_at(point: Vector2) -> void:
	var cell := cell_at(point)
	if not _in_grid(cell):
		return
	if cell in _stroke:
		return
	_stroke.append(cell)
	# Paint immediately so the grid follows the cursor; the stroke is what gets
	# committed to the undo stack when the button comes up.
	if _erasing:
		body.erase(cell)
	else:
		body.paint(cell, active_part)
	queue_redraw()


func _finish_stroke() -> void:
	_dragging = false
	if _stroke.is_empty():
		return
	var cells := _stroke.duplicate()
	_stroke.clear()
	if _erasing:
		erased.emit(cells)
	else:
		painted.emit(cells, active_part)
