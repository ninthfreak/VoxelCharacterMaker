@tool
class_name OutfitPanel
extends EditorPanel

## Saved outfits: which clothes are worn, and in which colourway (SPEC 7.2).
##
## Works on the worn list of the workspace it sits in, through
## get_worn() / set_worn_list(), so the same panel serves the Clothes tab and
## the Preview tab.

var _list: ItemList = null
var _names: Array[String] = []
var _name: LineEdit = null


func _build() -> void:
	var box := section("Outfits")
	_list = make_list(box, 110)
	_list.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _names.size():
			return
		_name.text = _names[index])
	_name = labelled(box, "Name", LineEdit.new()) as LineEdit
	button_row(box, [
		{"text": "Wear", "action": _on_wear},
		{"text": "Save as new", "action": _on_save},
		{"text": "Update selected", "action": _on_update},
		{"text": "Delete", "action": _on_delete},
	])
	hint(box, "\"Save as new\" uses the name box. \"Update selected\" overwrites the "
		+ "selected outfit with what is worn now.")


func refresh() -> void:
	if editor.wardrobe == null:
		return
	begin_guard()
	_names = editor.wardrobe.outfit_names()
	_list.clear()
	for name in _names:
		var worn := editor.wardrobe.outfit(name)
		var labels: Array[String] = []
		for entry in worn:
			var it := editor.wardrobe.item(String((entry as Dictionary)["item"]))
			if it != null:
				labels.append(it.name)
		_list.add_item("%s:  %s" % [name, ", ".join(labels)])
	end_guard()


func _selected_name() -> String:
	var index := _list.get_selected_items()
	return _names[index[0]] if not index.is_empty() else ""


func _on_wear() -> void:
	var name := _selected_name()
	if name.is_empty():
		editor.set_status_hint("Select an outfit to wear.")
		return
	workspace.call("set_worn_list", editor.wardrobe.outfit(name))
	editor.set_status_hint("Wearing %s" % name)


func _on_save() -> void:
	var name := _name.text.strip_edges()
	if name.is_empty():
		editor.set_status_hint("Type a name for the outfit first.")
		return
	editor.wardrobe.save_outfit(name, workspace.call("get_worn"))
	commit("Save outfit %s" % name)
	refresh()


func _on_update() -> void:
	var name := _selected_name()
	if name.is_empty():
		editor.set_status_hint("Select an outfit to update.")
		return
	editor.wardrobe.save_outfit(name, workspace.call("get_worn"))
	commit("Update outfit %s" % name)
	refresh()


func _on_delete() -> void:
	var name := _selected_name()
	if name.is_empty():
		return
	editor.wardrobe.remove_outfit(name)
	commit("Delete outfit %s" % name)
	refresh()
