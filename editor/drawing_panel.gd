@tool
class_name DrawingPanel
extends EditorPanel

## The Items tab's Drawing sub-tab: the grid a drawn part's shape is drawn on (ShapeGrid), for the chosen part if it
## is a drawn outline or a drawn side view. It has a sub-tab to itself so that it is in sight, at the top of the
## panel, without scrolling: under the part's numbers it sat below the bottom of the panel.

var _none: Label = null
var _box: VBoxContainer = null
var _stretch: Label = null
var _grid: ShapeGrid = null


func items_tab() -> ItemsWorkspace:
	return workspace as ItemsWorkspace


func _build() -> void:
	var box := section("Drawing")
	_none = hint(box, "Choose a drawn part to draw its shape here: add one with Drawn outline (a flat shape, given "
		+ "thickness) or Drawn side view (half a side view, spun round) above the view.")
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	box.add_child(_box)
	_stretch = hint(_box, "")
	_grid = ShapeGrid.new()
	_grid.drawn.connect(func(points: Array, label: String, merge: bool) -> void: _set_points(points, label, merge))
	_box.add_child(_grid)
	button_row(_box, [
		{"text": "Remove last point", "action": func() -> void:
			var part: Variant = _part()
			if part != null and not (part["points"] as Array).is_empty():
				var points: Array = (part["points"] as Array).duplicate(true)
				points.pop_back()
				_set_points(points, "Remove a point")},
		{"text": "Clear drawing", "action": func() -> void: _set_points([], "Clear drawing")},
	])


## The chosen part if it is a drawn one, or null.
func _part() -> Variant:
	var it := item()
	var i := items_tab().part if workspace != null else -1
	if it == null or i < 0 or i >= it.parts.size() or not (String(it.parts[i]["kind"]) in HeldItemShape.DRAWN):
		return null
	return it.parts[i]


func _set_points(points: Array, label: String, merge: bool = false) -> void:
	var part: Variant = _part()
	if is_guarded() or part == null or (part as Dictionary).get("points") == points:
		return
	(part as Dictionary)["points"] = points
	commit(label, merge)
	_note(part)


func refresh() -> void:
	var part: Variant = _part()
	_none.visible = part == null
	_box.visible = part != null
	if part == null:
		return
	begin_guard()
	_grid.show_points((part as Dictionary).get("points", []), String(part["kind"]) == "spin")
	_note(part)
	end_guard()


func _note(part: Dictionary) -> void:
	var size: Array = part["size"]
	var spin := String(part["kind"]) == "spin"
	var n := (part.get("points", []) as Array).size()
	var least := 2 if spin else 3
	_stretch.text = "Part %d. %s Stretched to the part's size: %s wide, %s tall. %d point%s%s." % [
		items_tab().part + 1,
		"Half a side view, spun round the middle (the blue line)." if spin
			else "An outline; the part's depth is its thickness.",
		str(snappedf(float(size[0]), 0.01)), str(snappedf(float(size[2]), 0.01)), n, "" if n == 1 else "s",
		"" if n >= least else " (it needs %d at least)" % least]
