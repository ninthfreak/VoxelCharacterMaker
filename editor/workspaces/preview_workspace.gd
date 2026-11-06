@tool
class_name PreviewWorkspace
extends Workspace

## The Preview tab: put together anything made in the other tabs -- a body, a
## head, eyes in a colour, hair, facial hair, and clothes -- and see the whole
## character, posed.
##
## Nothing is edited here, so nothing here can be lost. It is a place to look.

var body_id: String = "male_average"
var head_shape: String = "round"
var pose: String = Poses.REST
var expression: String = EyeSet.NEUTRAL
var eye_set_id: String = ""
var eye_colourway: String = ""
var hair_id: String = ""
var hair_colourway: String = ""
var facial_id: String = ""
var facial_colourway: String = ""
## Clothing worn: Array of {"item": id, "colourway": name}
var worn: Array = []

var _body_pick: OptionButton = null
var _head_pick: OptionButton = null
var _pose_pick: OptionButton = null
var _expression_pick: OptionButton = null
var _eye_pick: OptionButton = null
var _eye_way_pick: OptionButton = null
var _hair_pick: OptionButton = null
var _hair_way_pick: OptionButton = null
var _facial_pick: OptionButton = null
var _facial_way_pick: OptionButton = null
var _outfit_pick: OptionButton = null
var _clothes_rows: VBoxContainer = null
var _summary: Label = null
var _guard := 0


func title() -> String:
	return "Preview"


func _build() -> void:
	heading(side, "The whole character")
	note(side, "Put together anything made in the other tabs. Nothing is edited "
		+ "here.")

	_body_pick = cycler(side, "Body", editor.library.body_ids(), body_labels(),
		func(value: String) -> void: _choose("body_id", value))
	_head_pick = cycler(side, "Head", editor.library.head_shapes(), [],
		func(value: String) -> void: _choose("head_shape", value))
	_pose_pick = picker(side, "Pose", Poses.names(), pose_labels(),
		func(value: String) -> void:
			pose = value
			view.set_pose(value))

	heading(side, "Eyes")
	_eye_pick = picker(side, "Eye set", [], [], func(value: String) -> void:
		_choose("eye_set_id", value))
	_expression_pick = picker(side, "Expression", [], [], func(value: String) -> void:
		_choose("expression", value))
	_eye_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("eye_colourway", value))

	heading(side, "Hair")
	_hair_pick = picker(side, "Style", [], [], func(value: String) -> void:
		_choose("hair_id", value))
	_hair_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("hair_colourway", value))
	_facial_pick = picker(side, "Facial hair", [], [], func(value: String) -> void:
		_choose("facial_id", value))
	_facial_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("facial_colourway", value))

	heading(side, "Clothes")
	_outfit_pick = picker(side, "Outfit", [], [], func(value: String) -> void:
		if value.is_empty():
			return
		worn = editor.wardrobe.outfit(value)
		refresh()
		rebuild())
	note(side, "Choosing an outfit wears it; the list below can then be changed "
		+ "item by item without touching the saved outfit.")
	_clothes_rows = VBoxContainer.new()
	side.add_child(_clothes_rows)

	heading(side, "Summary")
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_summary)

	eye_set_id = editor.wardrobe.first_eye_set_id()
	var hair_ids := editor.wardrobe.feature_ids("hair")
	if not hair_ids.is_empty():
		hair_id = hair_ids[0]
	if editor.wardrobe.outfit_names().has("everyday"):
		worn = editor.wardrobe.outfit("everyday")


func _choose(field: String, value: String) -> void:
	if _guard > 0:
		return
	set(field, value)
	refresh()
	rebuild()


func make_request() -> CharacterAssembler.Request:
	var request := CharacterAssembler.Request.make(editor.library, body_id, head_shape,
		expression)
	request.wardrobe = editor.wardrobe
	request.eye_set_id = eye_set_id
	request.eye_colourway = eye_colourway
	request.worn = _live_worn()
	var features: Array = []
	for pair in [[hair_id, hair_colourway], [facial_id, facial_colourway]]:
		var it := editor.wardrobe.item(String(pair[0])) if not String(pair[0]).is_empty() \
			else null
		if it != null:
			var way := String(pair[1])
			features.append({"item": it.id,
				"colourway": way if it.has_colourway(way) else it.first_colourway()})
	request.features = features
	return request


func refresh() -> void:
	var w := editor.wardrobe
	if w == null or _body_pick == null:
		return
	_guard += 1
	select_value(_body_pick, body_id)
	select_value(_head_pick, head_shape)
	select_value(_pose_pick, pose)

	# Eyes: a set always, and its expressions and colours.
	if w.eye_set(eye_set_id) == null:
		eye_set_id = w.first_eye_set_id()
	var eye_ids: Array = []
	var eye_labels: Array = []
	for id in w.eye_set_ids():
		eye_ids.append(id)
		eye_labels.append(w.eye_set(id).name)
	if eye_ids.is_empty():
		eye_ids = [""]
		eye_labels = ["basic (no eye set saved)"]
	refill(_eye_pick, eye_ids, eye_labels, eye_set_id)
	var eyes := w.eye_set(eye_set_id)
	var expressions: Array = []
	var expression_labels: Array = []
	var source: Array[String] = eyes.expression_names() if eyes != null \
		else editor.library.expression_names()
	for name in source:
		expressions.append(name)
		expression_labels.append(name.replace("_", " "))
	refill(_expression_pick, expressions, expression_labels, expression)
	expression = option_value(_expression_pick)
	var ways: Array = []
	if eyes != null:
		for way in eyes.colourway_names():
			ways.append(way)
	refill(_eye_way_pick, ways, [], eye_colourway)
	eye_colourway = option_value(_eye_way_pick)

	# Hair and facial hair: a choice per slot, "none" included.
	hair_id = _fill_slot(_hair_pick, "hair", hair_id, "(none - bald)")
	hair_colourway = _fill_ways(_hair_way_pick, hair_id, hair_colourway)
	facial_id = _fill_slot(_facial_pick, "facial_hair", facial_id, "(none - clean-shaven)")
	facial_colourway = _fill_ways(_facial_way_pick, facial_id, facial_colourway)

	# Clothes.
	var outfit_values: Array = [""]
	var outfit_labels: Array = ["(choose an outfit to wear)"]
	for name2 in w.outfit_names():
		outfit_values.append(name2)
		outfit_labels.append(name2)
	refill(_outfit_pick, outfit_values, outfit_labels, "")
	worn = _live_worn()
	_rebuild_clothes_rows()
	_guard -= 1
	_refresh_summary()


func _fill_slot(option: OptionButton, slot: String, current: String, none_label: String) -> String:
	var values: Array = [""]
	var labels: Array = [none_label]
	for id in editor.wardrobe.feature_ids(slot):
		values.append(id)
		labels.append(editor.wardrobe.item(id).name)
	if not (current in values):
		current = ""
	refill(option, values, labels, current)
	return current


func _fill_ways(option: OptionButton, item_id: String, current: String) -> String:
	var it := editor.wardrobe.item(item_id) if not item_id.is_empty() else null
	var ways: Array = []
	if it != null:
		for way in it.colourway_names():
			ways.append(way)
	refill(option, ways, [], current)
	option.disabled = it == null
	return option_value(option)


## One row per clothing item: worn or not, and in which colourway. "worn" is
## said by the checkbox's tick and its label, not by colour.
func _rebuild_clothes_rows() -> void:
	for child in _clothes_rows.get_children():
		_clothes_rows.remove_child(child)
		child.queue_free()
	for id in editor.wardrobe.clothing_ids():
		var it := editor.wardrobe.item(id)
		var line := HBoxContainer.new()
		var check := CheckBox.new()
		check.text = it.name
		check.button_pressed = _worn_index(id) >= 0
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var way := OptionButton.new()
		var current := it.first_colourway()
		var at := _worn_index(id)
		if at >= 0:
			current = String((worn[at] as Dictionary)["colourway"])
		refill(way, it.colourway_names(), [], current)
		way.disabled = at < 0
		check.toggled.connect(func(on: bool) -> void:
			if on and _worn_index(id) < 0:
				worn.append({"item": id, "colourway": option_value(way)})
			elif not on:
				var index := _worn_index(id)
				if index >= 0:
					worn.remove_at(index)
			way.disabled = not on
			_refresh_summary()
			rebuild())
		way.item_selected.connect(func(_i: int) -> void:
			var index := _worn_index(id)
			if index >= 0:
				(worn[index] as Dictionary)["colourway"] = option_value(way)
				rebuild())
		line.add_child(check)
		line.add_child(way)
		_clothes_rows.add_child(line)


func _worn_index(item_id: String) -> int:
	for i in worn.size():
		if String((worn[i] as Dictionary)["item"]) == item_id:
			return i
	return -1


func _live_worn() -> Array:
	var out: Array = []
	for entry in worn:
		var e: Dictionary = entry
		var it := editor.wardrobe.item(String(e["item"]))
		if it == null or it.is_feature():
			continue
		var way := String(e["colourway"])
		out.append({"item": it.id, "colourway": way if it.has_colourway(way)
			else it.first_colourway()})
	return out


func _refresh_summary() -> void:
	var w := editor.wardrobe
	var body := editor.library.body(body_id)
	var eyes := w.eye_set(eye_set_id)
	var lines: Array[String] = []
	lines.append("Body: %s, %s head" % [body.display_name() if body != null else body_id,
		head_shape])
	lines.append("Eyes: %s, %s, %s" % [eyes.name if eyes != null else "basic",
		expression.replace("_", " "), eye_colourway if not eye_colourway.is_empty() else "-"])
	var hair := w.item(hair_id) if not hair_id.is_empty() else null
	var facial := w.item(facial_id) if not facial_id.is_empty() else null
	lines.append("Hair: %s" % ("%s (%s)" % [hair.name, hair_colourway] if hair != null
		else "none"))
	lines.append("Facial hair: %s" % ("%s (%s)" % [facial.name, facial_colourway]
		if facial != null else "none"))
	var names: Array[String] = []
	for entry in _live_worn():
		var e: Dictionary = entry
		names.append("%s (%s)" % [w.item(String(e["item"])).name, String(e["colourway"])])
	lines.append("Wearing: %s" % (", ".join(names) if not names.is_empty() else "nothing"))
	_summary.text = "\n".join(lines)


func status_text(assembled: CharacterAssembler.Assembled) -> String:
	return "%s   |   %d worn   |   %s" % [super.status_text(assembled), _live_worn().size(),
		Poses.display_name(pose)]
