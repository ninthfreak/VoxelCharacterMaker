@tool
class_name WardrobePanel
extends EditorPanel

## Items and outfits (SPEC.md section 8, "Wardrobe panel").
##
## The item list carries the word "worn" rather than a colour, so which items
## are on the figure is readable without relying on red vs green.

const WORN_MARK := "worn"

var _items: ItemList = null
var _name: LineEdit = null
var _category: OptionButton = null
var _draw_order: SpinBox = null
var _worn: CheckBox = null
var _solo: CheckBox = null
var _colourway: OptionButton = null
var _outfits: ItemList = null
var _outfit_name: LineEdit = null

var _item_ids: Array[String] = []
var _outfit_names: Array[String] = []


func _build() -> void:
	var items_box := section("Items")
	_items = make_list(items_box, 180)
	_items.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _item_ids.size():
			return
		editor.select_item(_item_ids[index]))

	button_row(items_box, [
		{"text": "New", "action": _on_new_item},
		{"text": "New special", "action": _on_new_special},
		{"text": "Duplicate", "action": _on_duplicate_item},
		{"text": "Delete", "action": _on_delete_item},
	])

	var detail := section("Selected item")
	_name = labelled(detail, "Name", LineEdit.new()) as LineEdit
	_name.text_submitted.connect(func(text: String) -> void: _apply_name(text))
	_name.focus_exited.connect(func() -> void: _apply_name(_name.text))

	_category = labelled(detail, "Category", OptionButton.new()) as OptionButton
	_category.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		var item := editor.selected_item()
		if item == null:
			return
		item.category = option_value(_category)
		item.draw_order = GarmentItem.default_draw_order(item.category)
		editor.commit("Set category of %s" % item.name)
		refresh())

	_draw_order = labelled(detail, "Draws at", SpinBox.new()) as SpinBox
	_draw_order.min_value = 0
	_draw_order.max_value = 200
	_draw_order.step = 1
	_draw_order.value_changed.connect(func(value: float) -> void:
		if is_guarded():
			return
		var item := editor.selected_item()
		if item == null or item.draw_order == int(value):
			return
		item.draw_order = int(value)
		editor.commit("Set draw order of %s" % item.name))
	hint(detail, "Higher draws on top. Where two items claim the same voxel the "
		+ "one reaching farther from the body wins, and this breaks the tie.")

	_colourway = labelled(detail, "Colourway", OptionButton.new()) as OptionButton
	_colourway.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		editor.set_worn_colourway(editor.selected_item_id, option_value(_colourway)))

	var toggles := HBoxContainer.new()
	detail.add_child(toggles)
	_worn = CheckBox.new()
	_worn.text = "Worn"
	_worn.toggled.connect(func(on: bool) -> void:
		if is_guarded():
			return
		editor.set_worn(editor.selected_item_id, on)
		refresh())
	toggles.add_child(_worn)

	_solo = CheckBox.new()
	_solo.text = "Show this item only"
	_solo.toggled.connect(func(on: bool) -> void:
		if is_guarded():
			return
		editor.set_solo(editor.selected_item_id if on else ""))
	toggles.add_child(_solo)

	var outfits_box := section("Outfits")
	_outfits = make_list(outfits_box, 110)
	_outfits.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _outfit_names.size():
			return
		_outfit_name.text = _outfit_names[index])

	_outfit_name = labelled(outfits_box, "Name", LineEdit.new()) as LineEdit
	button_row(outfits_box, [
		{"text": "Wear", "action": _on_wear_outfit},
		{"text": "Save as", "action": _on_save_outfit},
		{"text": "Update", "action": _on_update_outfit},
		{"text": "Delete", "action": _on_delete_outfit},
	])
	hint(outfits_box, "An outfit records which items are worn and in which "
		+ "colourway. \"Save as\" uses the name box; \"Update\" overwrites the "
		+ "selected outfit with what is on the figure now.")


func refresh() -> void:
	var w := wardrobe()
	if w == null:
		return
	begin_guard()

	_item_ids = w.item_ids_by_draw_order()
	_items.clear()
	for index in _item_ids.size():
		var item := w.item(_item_ids[index])
		var text := "%s  -  %s  (%d)" % [item.name, item.category, item.draw_order]
		if editor.is_worn(item.id):
			text += "   [%s]" % WORN_MARK
		if item.is_special():
			text += "   [special: %s]" % item.special_type
		_items.add_item(text)
		if item.id == editor.selected_item_id:
			_items.select(index)

	if editor.selected_item_id.is_empty() and not _item_ids.is_empty():
		end_guard()
		editor.select_item(_item_ids[0])
		return

	var selected := editor.selected_item()
	var have := selected != null
	_name.editable = have
	_category.disabled = not have
	_draw_order.editable = have
	_worn.disabled = not have
	_solo.disabled = not have
	_colourway.disabled = not have

	if have:
		_name.text = selected.name
		fill_options(_category, GarmentItem.CATEGORIES, selected.category)
		_draw_order.value = selected.draw_order
		_worn.button_pressed = editor.is_worn(selected.id)
		_solo.button_pressed = editor.solo_item == selected.id
		fill_options(_colourway, selected.colourway_names(),
			editor.worn_colourway(selected.id))
	else:
		_name.text = ""

	_outfit_names = w.outfit_names()
	_outfits.clear()
	for name in _outfit_names:
		_outfits.add_item("%s  (%d items)" % [name, w.outfit(name).size()])

	end_guard()


# ------------------------------------------------------------------ actions --

func _apply_name(text: String) -> void:
	if is_guarded():
		return
	var item := editor.selected_item()
	var trimmed := text.strip_edges()
	if item == null or trimmed.is_empty() or trimmed == item.name:
		return
	item.name = trimmed
	editor.commit("Rename item to %s" % trimmed)
	refresh()


func _on_new_item() -> void:
	var w := wardrobe()
	var id := w.unique_item_id("new item")
	var item := GarmentItem.create(id, "New item", "top")
	w.add_item(item)
	editor.select_item(id)
	editor.commit("Add item %s" % item.name)
	refresh()


func _on_new_special() -> void:
	var w := wardrobe()
	var type := SpecialItem.types()[0]
	var id := w.unique_item_id(type)
	var item := GarmentItem.create(id, SpecialItem.display_name(type), "bottom")
	item.kind = GarmentItem.Kind.SPECIAL
	item.special_type = type
	item.special_params = SpecialItem.default_params(type)
	item.roles = ["cloth", "hem"]
	item.colourways = {"default": {"cloth": "moss", "hem": "ochre"}}
	w.add_item(item)
	editor.select_item(id)
	editor.commit("Add special item %s" % item.name)
	refresh()


func _on_duplicate_item() -> void:
	var item := editor.selected_item()
	if item == null:
		return
	var w := wardrobe()
	var id := w.unique_item_id(item.name + " copy")
	var copy := item.duplicate_as(id, item.name + " copy")
	w.add_item(copy)
	editor.select_item(id)
	editor.commit("Duplicate %s" % item.name)
	refresh()


func _on_delete_item() -> void:
	var item := editor.selected_item()
	if item == null:
		return
	var label := item.name
	editor.set_worn(item.id, false)
	wardrobe().remove_item(item.id)
	editor.select_item("")
	editor.commit("Delete %s" % label)
	refresh()


func _on_wear_outfit() -> void:
	var index := _outfits.get_selected_items()
	if index.is_empty():
		return
	var name := _outfit_names[index[0]]
	editor.worn = wardrobe().outfit(name)
	editor.rebuild()
	refresh()
	editor.set_status_hint("Wearing outfit %s" % name)


func _on_save_outfit() -> void:
	var name := _outfit_name.text.strip_edges()
	if name.is_empty():
		editor.set_status_hint("Type a name for the outfit first.")
		return
	wardrobe().save_outfit(name, editor.worn)
	editor.commit("Save outfit %s" % name)
	refresh()


func _on_update_outfit() -> void:
	var index := _outfits.get_selected_items()
	if index.is_empty():
		editor.set_status_hint("Select an outfit to update.")
		return
	var name := _outfit_names[index[0]]
	wardrobe().save_outfit(name, editor.worn)
	editor.commit("Update outfit %s" % name)
	refresh()


func _on_delete_outfit() -> void:
	var index := _outfits.get_selected_items()
	if index.is_empty():
		return
	var name := _outfit_names[index[0]]
	wardrobe().remove_outfit(name)
	editor.commit("Delete outfit %s" % name)
	refresh()
