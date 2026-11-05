@tool
class_name EditorPanel
extends VBoxContainer

## Base for the editor's tab panels. Each one gets a reference to the editor and
## rebuilds its own controls on refresh().
##
## The small helpers below exist so every panel looks and reads the same way:
## one short label per control, a single hint line where a control needs one,
## and never a bare colour as the only signal (the owner is red/green colour
## blind).

var editor: CharacterEditor = null
var _guard := false  ## set while repopulating, so signals do not loop back


func setup(p_editor: CharacterEditor) -> void:
	editor = p_editor
	add_theme_constant_override("separation", 6)
	_build()
	if editor != null:
		editor.wardrobe_replaced.connect(refresh)
		editor.selection_changed.connect(refresh)
	refresh()


## Override: create the controls once.
func _build() -> void:
	pass


## Override: push the current model into the controls.
func refresh() -> void:
	pass


func wardrobe() -> Wardrobe:
	return editor.wardrobe if editor != null else null


# ------------------------------------------------------------------ helpers --

func section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 15)
	box.add_child(heading)
	box.add_child(HSeparator.new())
	add_child(box)
	return box


func labelled(parent: Container, text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)
	return control


func hint(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color8(160, 168, 184))
	parent.add_child(label)
	return label


func button_row(parent: Container, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for entry in buttons:
		var e: Dictionary = entry
		var button := Button.new()
		button.text = String(e["text"])
		button.pressed.connect(e["action"] as Callable)
		row.add_child(button)
	parent.add_child(row)
	return row


func make_list(parent: Container, height: int, multi: bool = false) -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, height)
	list.select_mode = ItemList.SELECT_MULTI if multi else ItemList.SELECT_SINGLE
	list.allow_reselect = true
	parent.add_child(list)
	return list


## Fill an OptionButton and select `current`, without firing item_selected.
func fill_options(option: OptionButton, values: Array, current: String,
		labels: Array = []) -> void:
	_guard = true
	option.clear()
	for i in values.size():
		var value := String(values[i])
		var text := String(labels[i]) if i < labels.size() else value
		option.add_item(text, i)
		option.set_item_metadata(i, value)
		if value == current:
			option.select(i)
	if option.selected < 0 and option.item_count > 0:
		option.select(0)
	_guard = false


func option_value(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func is_guarded() -> bool:
	return _guard


func begin_guard() -> void:
	_guard = true


func end_guard() -> void:
	_guard = false
