@tool
class_name GripPanel
extends EditorPanel

## Where a held item's hand closes, and how the item turns in it (HeldItemShape). The grip is set by hand in the view
## (ItemStage: drag the hand, turn the ring), which marks it with two arrows: "ahead", the way the fist points, and
## "up", the way its thumb does, as the right arm hangs. These numbers follow. Most items need no change here: an
## item made standing up with its handle at its middle is held as a sword is.
##
## A second grip (for the other hand of a two-handed item) is kept in the file if it is there; nothing uses one yet,
## so there is no control for it.

var _place: Array[SpinBox] = []
var _turn: Array[SpinBox] = []


func items_tab() -> ItemsWorkspace:
	return workspace as ItemsWorkspace


func _build() -> void:
	var box := section("Grip: where the hand closes")
	_place = triple(box, "Place", ["x ", "y ", "z "], -96.0, 96.0, PartsPanel.STEP, PartsPanel.ARROW, "",
		func(values: Array) -> void: _set_grip("position", values, "Move grip"))
	_turn = triple(box, "Turn", ["fwd ", "side ", "round "], -180.0, 180.0, 0.01, PartsPanel.TURN_ARROW, "°",
		func(values: Array) -> void: _set_grip("rotation", values, "Turn grip"))
	button_row(box, [{"text": "Put the grip at the chosen part's middle", "action": _on_to_part}])
	hint(box, "In the view: drag the hand to move the grip, the ring to turn it. An item made standing up, such as a "
		+ "sword, is held pointing ahead with no turn. A bottle held upright: turn it sideways 90. The left hand "
		+ "holds the mirror image.")


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
	end_guard()
