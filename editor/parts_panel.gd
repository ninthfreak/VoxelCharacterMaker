@tool
class_name PartsPanel
extends EditorPanel

## The parts of a held item (HeldItemShape): a list of them, and the chosen one's shape, colour role, place, turn,
## size, sides, mirror and, for a drawn part, its drawing. The Items tab says which part is chosen (ItemsWorkspace.part);
## a double-click on a part in the view chooses it too.
##
## Numbers step by a quarter unit (a turn by 15 degrees) with the arrows; any value can be typed.

const STEP := 0.05                  ## what a typed number is kept to
const ARROW := 0.25                 ## what an arrow click adds
const TURN_ARROW := 15.0

var _list: ItemList = null
var _add_kind: OptionButton = null
var _details: VBoxContainer = null
var _kind: OptionButton = null
var _role: OptionButton = null
var _place: Array[SpinBox] = []
var _turn: Array[SpinBox] = []
var _size: Array[SpinBox] = []
var _sides: SpinBox = null
var _sides_row: Control = null
var _mirror: CheckBox = null
var _drawing: VBoxContainer = null
var _grid: ShapeGrid = null
var _stretch: Label = null


func items_tab() -> ItemsWorkspace:
	return workspace as ItemsWorkspace


func _build() -> void:
	var box := section("Parts")
	_list = make_list(box, 150)
	_list.item_selected.connect(func(index: int) -> void:
		if not is_guarded():
			items_tab().select_part(index))

	var add_row := HBoxContainer.new()
	var add_label := Label.new()
	add_label.text = "Add a"
	add_label.custom_minimum_size = Vector2(104, 0)
	add_row.add_child(add_label)
	_add_kind = OptionButton.new()
	_add_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in HeldItemShape.KINDS.size():
		_add_kind.add_item(HeldItemShape.kind_label(HeldItemShape.KINDS[i]), i)
		_add_kind.set_item_metadata(i, HeldItemShape.KINDS[i])
	add_row.add_child(_add_kind)
	var add := Button.new()
	add.text = "Add part"
	add.pressed.connect(_on_add)
	add_row.add_child(add)
	box.add_child(add_row)
	button_row(box, [
		{"text": "Duplicate part", "action": _on_duplicate},
		{"text": "Delete part", "action": _on_delete},
	])

	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	box.add_child(_details)
	_kind = labelled(_details, "Shape", OptionButton.new()) as OptionButton
	for i in HeldItemShape.KINDS.size():
		_kind.add_item(HeldItemShape.kind_label(HeldItemShape.KINDS[i]), i)
		_kind.set_item_metadata(i, HeldItemShape.KINDS[i])
	_kind.item_selected.connect(func(_i: int) -> void: _on_kind(option_value(_kind)))
	_role = labelled(_details, "Colour role", OptionButton.new()) as OptionButton
	_role.item_selected.connect(func(_i: int) -> void:
		_set_field("role", option_value(_role), "Set part colour role"))

	_place = triple(_details, "Place", ["x ", "y ", "z "], -96.0, 96.0, STEP, ARROW, "",
		func(values: Array) -> void: _set_field("position", values, "Move part", true))
	_turn = triple(_details, "Turn", ["fwd ", "side ", "round "], -180.0, 180.0, 1.0, TURN_ARROW, " deg",
		func(values: Array) -> void: _set_field("rotation", values, "Turn part", true))
	_size = triple(_details, "Size", ["w ", "d ", "h "], HeldItemShape.MIN_SIZE, 96.0, STEP, ARROW, "",
		func(values: Array) -> void: _set_field("size", values, "Resize part", true))
	hint(_details, "x across (+ is the item's left, your right as you face it), y depth (the front is -), z up. "
		+ "Turns: tip forward, lean sideways, spin round. Units: 24 to a metre; a hand is about 3 across.")

	_sides = SpinBox.new()
	_sides.min_value = HeldItemShape.MIN_SIDES
	_sides.max_value = HeldItemShape.MAX_SIDES
	_sides.step = 1
	_sides.value_changed.connect(func(value: float) -> void: _set_field("sides", int(value), "Set part sides", true))
	_sides_row = labelled(_details, "Sides", _sides).get_parent()
	_mirror = CheckBox.new()
	_mirror.text = "Mirror: draw it again across the middle"
	_mirror.toggled.connect(func(on: bool) -> void: _set_field("mirror", on, "Mirror part"))
	_details.add_child(_mirror)

	_drawing = VBoxContainer.new()
	_details.add_child(_drawing)
	var drawing_title := Label.new()
	drawing_title.text = "Drawing"
	drawing_title.add_theme_font_size_override("font_size", 15)
	_drawing.add_child(drawing_title)
	_stretch = hint(_drawing, "")
	_grid = ShapeGrid.new()
	_grid.drawn.connect(func(points: Array, label: String, merge: bool) -> void:
		_set_field("points", points, label, merge))
	_drawing.add_child(_grid)
	button_row(_drawing, [
		{"text": "Remove last point", "action": func() -> void:
			var part: Variant = _part()
			if part != null and not (part["points"] as Array).is_empty():
				var points: Array = (part["points"] as Array).duplicate(true)
				points.pop_back()
				_set_field("points", points, "Remove a point")},
		{"text": "Clear drawing", "action": func() -> void: _set_field("points", [], "Clear drawing")},
	])


## The chosen part of the item being edited, or null.
func _part() -> Variant:
	var it := item()
	var i := items_tab().part if workspace != null else -1
	if it == null or i < 0 or i >= it.parts.size():
		return null
	return it.parts[i]


func _set_field(field: String, value: Variant, label: String, merge: bool = false) -> void:
	if is_guarded():
		return
	var part: Variant = _part()
	if part == null or (part as Dictionary).get(field) == value:
		return
	(part as Dictionary)[field] = value
	commit(label, merge)
	if field == "points":
		_refresh_grid_note(part)
	if field == "role" or field == "mirror":
		refresh()


func refresh() -> void:
	var it := item()
	if it == null or editor.wardrobe == null:
		visible = false
		return
	visible = true
	begin_guard()
	var chosen := items_tab().part
	_list.clear()
	for i in it.parts.size():
		var p: Dictionary = it.parts[i]
		_list.add_item("%d   %s   -   %s%s" % [i + 1, HeldItemShape.kind_label(String(p["kind"])).split(",")[0],
			String(p["role"]), "   (mirrored)" if bool(p.get("mirror", false)) else ""])
	if chosen >= 0 and chosen < it.parts.size():
		_list.select(chosen)
		_list.ensure_current_is_visible()
	var part: Variant = _part()
	_details.visible = part != null
	if part != null:
		var p2: Dictionary = part
		var kind := String(p2["kind"])
		Workspace.select_value(_kind, kind)
		fill_options(_role, it.roles, String(p2["role"]))
		for i in 3:
			_place[i].value = float(p2["position"][i])
			_turn[i].value = float(p2["rotation"][i])
			_size[i].value = float(p2["size"][i])
		_sides_row.visible = kind in HeldItemShape.ROUND
		_sides.value = int(p2.get("sides", 8))
		_mirror.button_pressed = bool(p2.get("mirror", false))
		_drawing.visible = kind in HeldItemShape.DRAWN
		if _drawing.visible:
			_grid.show_points(p2.get("points", []), kind == "spin")
			_refresh_grid_note(p2)
	end_guard()


func _refresh_grid_note(part: Dictionary) -> void:
	var size: Array = part["size"]
	var spin := String(part["kind"]) == "spin"
	var n := (part.get("points", []) as Array).size()
	var least := 2 if spin else 3
	_stretch.text = "%s Stretched to the part's size: %s wide, %s tall. %d point%s%s." % [
		"Half a side view, spun round the middle (the blue line)." if spin
			else "An outline; the part's depth is its thickness.",
		_num(float(size[0])), _num(float(size[2])), n, "" if n == 1 else "s",
		"" if n >= least else " (it needs %d at least)" % least]


static func _num(v: float) -> String:
	return str(snappedf(v, 0.01))


# ------------------------------------------------------------------ actions --

func _on_add() -> void:
	var it := item()
	if it == null:
		return
	var kind := option_value(_add_kind)
	var part := HeldItemShape.new_part(kind, it.roles[0] if not it.roles.is_empty() else GarmentItem.DEFAULT_ROLE)
	it.parts.append(part)
	items_tab().part = it.parts.size() - 1
	commit("Add %s" % HeldItemShape.kind_label(kind).split(",")[0].to_lower())
	items_tab().select_part(it.parts.size() - 1)


func _on_duplicate() -> void:
	var it := item()
	var part: Variant = _part()
	if it == null or part == null:
		return
	var copy: Dictionary = (part as Dictionary).duplicate(true)
	it.parts.insert(items_tab().part + 1, copy)
	commit("Duplicate part")
	items_tab().select_part(items_tab().part + 1)


func _on_delete() -> void:
	var it := item()
	if it == null or _part() == null:
		return
	it.parts.remove_at(items_tab().part)
	commit("Delete part")
	items_tab().select_part(mini(items_tab().part, it.parts.size() - 1))


## Another kind of shape, keeping the place, turn, size and role; a drawn kind starts from its default drawing.
func _on_kind(kind: String) -> void:
	if is_guarded():
		return
	var part: Variant = _part()
	if part == null or String((part as Dictionary)["kind"]) == kind:
		return
	var p: Dictionary = part
	var fresh := HeldItemShape.new_part(kind, String(p["role"]))
	p["kind"] = kind
	if kind in HeldItemShape.DRAWN:
		p["points"] = fresh["points"]
	commit("Change part shape")
	refresh()
