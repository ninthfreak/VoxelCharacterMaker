@tool
class_name ShapeGrid
extends Control

## The Items tab's drawing grid, for a part drawn by hand (HeldItemShape): an outline, given thickness, or half a side
## view, spun round its middle. HeldItemShape.GRID squares each way; points sit where the lines cross. The drawing is
## stretched to the part's size, so the grid is always square here, easy to click.
##
##   click            add a point after the last (or, on a line already drawn, into that line)
##   drag a point     move it
##   right-click one  remove it
##
## Points are numbered in the order they join up; the first is orange, the rest sky blue (no red against green).

## Something was drawn: the new points, a short name for the change, and whether it continues the last change (a
## drag: one undo for the whole of it).
signal drawn(points: Array, label: String, merge: bool)

const GRID := HeldItemShape.GRID
const NEAR := 0.45                  ## how close to a point, in squares, counts as on it

## [[across, up], ...] on the grid
var points: Array = []
## A spin: the left edge is the middle it spins round, and the drawing is not closed.
var spin := false

var _drag := -1
var _dragged := false


func _init() -> void:
	custom_minimum_size = Vector2(420, 500)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_points(p_points: Array, p_spin: bool) -> void:
	points = p_points.duplicate(true)
	spin = p_spin
	queue_redraw()


func cell() -> float:
	return floorf(minf((size.x - 70.0) / GRID, (size.y - 84.0) / GRID))


func origin() -> Vector2:
	var s := cell()
	return Vector2(maxf(56.0, (size.x - GRID * s) * 0.5), 16.0)


## A grid point (across, up) on the screen.
func to_screen(p: Array) -> Vector2:
	var s := cell()
	return origin() + Vector2(float(p[0]) * s, float(GRID - int(p[1])) * s)


## The grid point nearest a screen position, kept on the grid.
func to_grid(at: Vector2) -> Array:
	var s := cell()
	var q := (at - origin()) / s
	return [clampi(roundi(q.x), 0, GRID), clampi(GRID - roundi(q.y), 0, GRID)]


## The point under a screen position, or -1.
func point_at(at: Vector2) -> int:
	var s := cell()
	var best := -1
	var nearest := NEAR * s
	for i in points.size():
		var d := to_screen(points[i]).distance_to(at)
		if d <= nearest:
			nearest = d
			best = i
	return best


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var s := cell()
	var o := origin()
	var dim := Color8(150, 158, 174)
	draw_rect(Rect2(o, Vector2(GRID * s, GRID * s)), Color8(28, 32, 42), true)
	for i in GRID + 1:
		var strong := i % 4 == 0
		var colour := Color8(84, 92, 110) if strong else Color8(52, 58, 72)
		draw_line(o + Vector2(i * s, 0), o + Vector2(i * s, GRID * s), colour, 1.0)
		draw_line(o + Vector2(0, i * s), o + Vector2(GRID * s, i * s), colour, 1.0)
	if spin:
		draw_line(o, o + Vector2(0, GRID * s), Palette.UI_SKY, 3.0)
		draw_string(font, o + Vector2(-54, GRID * s * 0.5), "middle", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.UI_SKY)
	else:
		draw_line(o + Vector2(GRID * s * 0.5, 0), o + Vector2(GRID * s * 0.5, GRID * s), Color8(110, 118, 138), 1.0)
	draw_string(font, o + Vector2(0, GRID * s + 18), "out from the middle  >" if spin else "across  >",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)
	draw_string(font, o + Vector2(-54, 12), "up ^", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)

	var n := points.size()
	for i in n - 1:
		draw_line(to_screen(points[i]), to_screen(points[i + 1]), Color.WHITE, 2.0)
	if not spin and n > 2:
		draw_dashed_line(to_screen(points[n - 1]), to_screen(points[0]), Color(1, 1, 1, 0.6), 2.0, 6.0)
	for i in n:
		var at := to_screen(points[i])
		var colour := Palette.UI_ORANGE if i == 0 else Palette.UI_SKY
		draw_circle(at, 6.0 if i == 0 else 5.0, colour)
		draw_string(font, at + Vector2(7, -7), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, colour)
	draw_string(font, Vector2(o.x, size.y - 26), "click: add a point     drag a point: move it", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 14, dim)
	draw_string(font, Vector2(o.x, size.y - 6), "right-click a point: remove it", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var hit := point_at(mb.position)
			if hit >= 0:
				_drag = hit
				_dragged = false
			else:
				_add(to_grid(mb.position))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_drag = -1
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit2 := point_at(mb.position)
			if hit2 >= 0:
				points.remove_at(hit2)
				queue_redraw()
				drawn.emit(points.duplicate(true), "Remove a point", false)
			accept_event()
	elif event is InputEventMouseMotion and _drag >= 0:
		var to := to_grid((event as InputEventMouseMotion).position)
		if to != points[_drag]:
			points[_drag] = to
			queue_redraw()
			drawn.emit(points.duplicate(true), "Move a point", _dragged)
			_dragged = true
		accept_event()


## Add a point: into a line already drawn if it lies on one (between its ends), else after the last.
func _add(p: Array) -> void:
	for i in points.size() - 1:
		if _on_line(p, points[i], points[i + 1]):
			points.insert(i + 1, p)
			queue_redraw()
			drawn.emit(points.duplicate(true), "Add a point", false)
			return
	if not points.is_empty() and points[-1] == p:
		return
	points.append(p)
	queue_redraw()
	drawn.emit(points.duplicate(true), "Add a point", false)


static func _on_line(p: Array, a: Array, b: Array) -> bool:
	if p == a or p == b:
		return false
	var ab := Vector2i(int(b[0]) - int(a[0]), int(b[1]) - int(a[1]))
	var ap := Vector2i(int(p[0]) - int(a[0]), int(p[1]) - int(a[1]))
	if ab.x * ap.y - ab.y * ap.x != 0:
		return false
	var along := ab.x * ap.x + ab.y * ap.y
	return along > 0 and along < ab.x * ab.x + ab.y * ab.y
