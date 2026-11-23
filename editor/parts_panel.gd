@tool
class_name PartsPanel
extends EditorPanel

## The parts of a held item (HeldItemShape): a list of them, and the chosen one's shape, colour role, place, turn,
## size, sides and mirror. The Items tab says which part is chosen (ItemsWorkspace.part, and the others chosen with
## it, .also); a click on a part in the view chooses it too. A drawn part's shape is drawn on the Drawing sub-tab
## (DrawingPanel).
##
## The numbers here are for fine work and exact places: parts are added, moved, sized and turned by hand in the view
## (ItemStage and the buttons above it), and these follow. They step by a quarter unit (a turn by 15 degrees) with
## the arrows; any value can be typed.

const STEP := 0.001                 ## what a typed number is kept to (ItemStage.PLACES)
const ARROW := 0.25                 ## what an arrow click adds
const TURN_ARROW := 15.0

var _list: ItemList = null
var _details: VBoxContainer = null
var _kind: OptionButton = null
var _role: OptionButton = null
var _place: Array[SpinBox] = []
var _turn: Array[SpinBox] = []
var _size: Array[SpinBox] = []
var _sides: SpinBox = null
var _sides_row: Control = null
var _mirror: CheckBox = null
var _draw: Button = null


func items_tab() -> ItemsWorkspace:
	return workspace as ItemsWorkspace


func _build() -> void:
	var box := section("Parts")
	_list = make_list(box, 150)
	_list.item_selected.connect(func(index: int) -> void:
		if not is_guarded():
			items_tab().select_part(index))

	button_row(box, [
		{"text": "Copy part", "action": func() -> void: items_tab().copy_part()},
		{"text": "Paste part", "action": func() -> void: items_tab().paste_part()},
		{"text": "Delete part", "action": func() -> void: items_tab().delete_chosen()},
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
		func(values: Array) -> void: _set_field("position", values, "Move part %d" % (items_tab().part + 1), true))
	_turn = triple(_details, "Turn", ["fwd ", "side ", "round "], -180.0, 180.0, 0.01, TURN_ARROW, "°",
		func(values: Array) -> void: _set_field("rotation", values, "Turn part %d" % (items_tab().part + 1), true))
	_size = triple(_details, "Size", ["w ", "d ", "h "], HeldItemShape.MIN_SIZE, 96.0, STEP, ARROW, "",
		func(values: Array) -> void: _set_field("size", values, "Resize part %d" % (items_tab().part + 1), true))
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

	_draw = Button.new()
	_draw.text = "Draw its shape (Drawing tab)"
	_draw.pressed.connect(func() -> void: items_tab().show_section("Drawing"))
	_details.add_child(_draw)


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
		_list.add_item("%d   %s   -   %s%s%s" % [i + 1, HeldItemShape.kind_name(String(p["kind"])),
			String(p["role"]), "   (mirrored)" if bool(p.get("mirror", false)) else "",
			"   [also chosen]" if items_tab().also.has(i) else ""])
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
		_draw.visible = kind in HeldItemShape.DRAWN
	end_guard()


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
