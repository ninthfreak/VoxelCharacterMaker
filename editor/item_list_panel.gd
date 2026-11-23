@tool
class_name ItemListPanel
extends EditorPanel

## The items of one wardrobe section -- clothing, a feature slot, or held items -- with the
## basics of the selected one: name, category, draw order (not for held items), colourway.
##
## For clothing, each item can be marked worn; the list says "worn" in words
## rather than relying on colour. A feature slot is always filled, so its list
## starts with "(none)" -- bald, clean-shaven -- which is a choice like any
## other rather than an absence of one.

const WORN_MARK := "worn"
const NONE_ID := ""

## Clothing shows worn toggles and categories; a feature slot shows "(none)".
var show_worn := false

var _list: ItemList = null
var _ids: Array[String] = []
var _name: LineEdit = null
var _category: OptionButton = null
var _draw_order: SpinBox = null
var _colourway: OptionButton = null
var _worn: CheckBox = null
var _details: VBoxContainer = null


func _build() -> void:
	var box := section("Items" if selection == null or selection.slot == GarmentItem.HELD
		else GarmentItem.slot_label(selection.slot))
	_list = make_list(box, 170)
	_list.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _ids.size():
			return
		selection.select(_ids[index]))

	button_row(box, [
		{"text": "New", "action": _on_new},
		{"text": "Duplicate", "action": _on_duplicate},
		{"text": "Delete", "action": _on_delete},
	])

	_details = VBoxContainer.new()
	box.add_child(_details)
	_name = labelled(_details, "Name", LineEdit.new()) as LineEdit
	_name.text_submitted.connect(func(text: String) -> void: _apply_name(text))
	_name.focus_exited.connect(func() -> void: _apply_name(_name.text))

	_category = labelled(_details, "Category", OptionButton.new()) as OptionButton
	_category.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		var it := item()
		if it == null:
			return
		it.category = option_value(_category)
		it.draw_order = GarmentItem.default_draw_order(it.category)
		commit("Set category of %s" % it.name)
		refresh())

	_draw_order = labelled(_details, "Draws at", SpinBox.new()) as SpinBox
	_draw_order.min_value = 0
	_draw_order.max_value = 200
	_draw_order.step = 1
	_draw_order.value_changed.connect(func(value: float) -> void:
		if is_guarded():
			return
		var it := item()
		if it == null or it.draw_order == int(value):
			return
		it.draw_order = int(value)
		commit("Set draw order of %s" % it.name)
		refresh.call_deferred())                # re-sorted once the spin box is done with the event

	_colourway = labelled(_details, "Colourway", OptionButton.new()) as OptionButton
	_colourway.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		selection.set_colourway(option_value(_colourway))
		if show_worn and workspace.has_method("set_worn_colourway"):
			workspace.call("set_worn_colourway", selection.item_id, option_value(_colourway)))

	_worn = CheckBox.new()
	_worn.text = "Worn"
	_worn.visible = show_worn
	_worn.toggled.connect(func(on: bool) -> void:
		if is_guarded():
			return
		workspace.call("set_worn", selection.item_id, on)
		refresh())
	_details.add_child(_worn)

	if selection == null or selection.slot != GarmentItem.HELD:
		hint(box, "Higher draws on top. Where two items claim the same region the one "
			+ "reaching further from the body wins, and draw order breaks a tie.")


func refresh() -> void:
	if selection == null or editor.wardrobe == null:
		return
	selection.validate()
	begin_guard()

	_ids.clear()
	_list.clear()
	var is_held := selection.slot == GarmentItem.HELD
	if not show_worn and not is_held:
		_ids.append(NONE_ID)
		var none_text := "(none)"
		if selection.slot == "hair":
			none_text = "(none - bald)"
		elif selection.slot == "facial_hair":
			none_text = "(none - clean-shaven)"
		elif selection.slot == "face_accessory":
			none_text = "(none)"
		_list.add_item(none_text)
	for id in editor.wardrobe.item_ids_by_draw_order(selection.slot):
		_ids.append(id)
		var it := editor.wardrobe.item(id)
		var text := it.name
		if not it.is_feature() or it.is_held():
			text += "  -  %s" % it.category
		if not it.is_held():
			text += "  (draws at %d)" % it.draw_order
		else:
			text += "  (%d part%s)" % [it.parts.size(), "" if it.parts.size() == 1 else "s"]
		if it.is_special():
			var types: Array[String] = []
			for type in it.special_types():
				types.append(SpecialItem.display_name(type).to_lower())
			text += "   [%s]" % ", ".join(types)
		if show_worn and workspace.has_method("is_worn") and workspace.call("is_worn", id):
			text += "   [%s]" % WORN_MARK
		_list.add_item(text)
	var at := _ids.find(selection.item_id)
	if at >= 0:
		_list.select(at)
		_list.ensure_current_is_visible()

	var it2 := item()
	_details.visible = it2 != null
	if it2 != null:
		_name.text = it2.name
		_category.get_parent().visible = not it2.is_feature() or it2.is_held()
		fill_options(_category, GarmentItem.HELD_CATEGORIES if it2.is_held() else GarmentItem.CATEGORIES, it2.category)
		_draw_order.get_parent().visible = not it2.is_held()
		_draw_order.value = it2.draw_order
		fill_options(_colourway, it2.colourway_names(), selection.colourway)
		_worn.visible = show_worn
		if show_worn and workspace.has_method("is_worn"):
			_worn.button_pressed = workspace.call("is_worn", it2.id)
	end_guard()


# ------------------------------------------------------------------ actions --

func _apply_name(text: String) -> void:
	if is_guarded():
		return
	var it := item()
	var trimmed := text.strip_edges()
	if it == null or trimmed.is_empty() or trimmed == it.name:
		return
	it.name = trimmed
	commit("Rename to %s" % trimmed)
	# Later, not now: typing often ends with a click on another row, and re-sorting first would put a different
	# item under that click.
	refresh.call_deferred()


func _on_new() -> void:
	var w := editor.wardrobe
	var label := "New item"
	if selection.slot == GarmentItem.HELD:
		label = "New held item"
	elif selection.slot != GarmentItem.CLOTHES:
		label = "New %s" % GarmentItem.slot_label(selection.slot).to_lower()
	var id := w.unique_item_id(label)
	var it: GarmentItem
	if selection.slot == GarmentItem.CLOTHES:
		it = GarmentItem.create(id, label, "top")
	elif selection.slot == GarmentItem.HELD:
		it = GarmentItem.create_held(id, label)
		# its starting colours, or (a wardrobe that has dropped them) whatever the palette has
		var names := w.palette_names()
		var way: Dictionary = it.colourways[GarmentItem.DEFAULT_COLOURWAY]
		for role in way.keys():
			if not w.palette.has(String(way[role])) and not names.is_empty():
				way[role] = names[0]
	else:
		it = GarmentItem.create_feature(id, label, selection.slot)
		it.roles = ["hair"]
		it.colourways = {"default": {"hair": "hair_brown"}}
	w.add_item(it)
	selection.select(id)
	commit("Add %s" % label.to_lower())
	refresh()


func _on_duplicate() -> void:
	var it := item()
	if it == null:
		return
	var w := editor.wardrobe
	var id := w.unique_item_id(it.name + " copy")
	w.add_item(it.duplicate_as(id, it.name + " copy"))
	selection.select(id)
	commit("Duplicate %s" % it.name)
	refresh()


func _on_delete() -> void:
	var it := item()
	if it == null:
		return
	var label := it.name
	if show_worn and workspace.has_method("set_worn"):
		workspace.call("set_worn", it.id, false)
	editor.wardrobe.remove_item(it.id)
	selection.select(NONE_ID)
	commit("Delete %s" % label)
	refresh()
