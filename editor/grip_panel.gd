@tool
class_name GripPanel
extends EditorPanel

## Where a held item's hand closes, and how the item turns in it (HeldItemShape); and, for a two-handed item, where
## the other hand goes. The view marks the grip with two arrows: "ahead", the way the fist points, and "up", the way
## its thumb does, as the right arm hangs.

var _place: Array[SpinBox] = []
var _turn: Array[SpinBox] = []
var _two_handed: CheckBox = null
var _second: Array[SpinBox] = []
var _second_row: Control = null


func items_tab() -> ItemsWorkspace:
	return workspace as ItemsWorkspace


func _build() -> void:
	var box := section("Grip: where the hand closes")
	_place = triple(box, "Place", ["x ", "y ", "z "], -96.0, 96.0, PartsPanel.STEP, PartsPanel.ARROW, "",
		func(values: Array) -> void: _set_grip("position", values, "Move grip"))
	_turn = triple(box, "Turn", ["fwd ", "side ", "round "], -180.0, 180.0, 0.01, PartsPanel.TURN_ARROW, "°",
		func(values: Array) -> void: _set_grip("rotation", values, "Turn grip"))
	button_row(box, [{"text": "Put the grip at the chosen part's middle", "action": _on_to_part}])
	hint(box, "Unturned, the item's top points ahead out of the fist, its front faces outward and its left side "
		+ "down: a sword or an axe made standing up needs no turn. A bottle held upright: turn it sideways 90. The "
		+ "left hand holds the mirror image. In the view: drag the hand to move the grip, the ring to turn it.")

	var two := section("Second hand")
	_two_handed = CheckBox.new()
	_two_handed.text = "Two-handed: mark where the other hand goes"
	_two_handed.toggled.connect(func(on: bool) -> void:
		var it := item()
		if is_guarded() or it == null or on == not it.second_grip.is_empty():
			return
		it.second_grip = {"position": it.grip["position"].duplicate(), "rotation": [0.0, 0.0, 0.0]} if on else {}
		commit("Two-handed" if on else "One-handed")
		refresh())
	two.add_child(_two_handed)
	_second = triple(two, "Place", ["x ", "y ", "z "], -96.0, 96.0, PartsPanel.STEP, PartsPanel.ARROW, "",
		func(values: Array) -> void:
			var it := item()
			if it == null or it.second_grip.is_empty() or it.second_grip["position"] == values:
				return
			it.second_grip["position"] = values
			commit("Move second grip", true))
	_second_row = _second[0].get_parent().get_parent()
	hint(two, "Kept for later: the other hand does not reach for it yet.")


func _set_grip(field: String, values: Array, label: String) -> void:
	var it := item()
	if it == null or it.grip[field] == values:
		return
	it.grip[field] = values
	commit(label, true)


func _on_to_part() -> void:
	var it := item()
	var i := items_tab().part
	if it == null or i < 0 or i >= it.parts.size():
		return
	it.grip["position"] = (it.parts[i]["position"] as Array).duplicate()
	commit("Move grip to part %d" % (i + 1))
	refresh()


func refresh() -> void:
	var it := item()
	visible = it != null
	if it == null:
		return
	begin_guard()
	for i in 3:
		_place[i].value = float(it.grip["position"][i])
		_turn[i].value = float(it.grip["rotation"][i])
	_two_handed.button_pressed = not it.second_grip.is_empty()
	_second_row.visible = not it.second_grip.is_empty()
	if not it.second_grip.is_empty():
		for i in 3:
			_second[i].value = float(it.second_grip["position"][i])
	end_guard()
