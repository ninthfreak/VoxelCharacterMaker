@tool
class_name CharacterPanel
extends EditorPanel

## Saved characters, at the top of the Preview tab: a list of them, and a name.
##
##   pick one in the list   the Preview takes up its choices (looking, not editing)
##   Save as new            the Preview's choices become a new character, under the name typed
##   Update                 the loaded character takes the Preview's choices as they are now
##   Rename                 the loaded character takes the name typed
##   Delete                 the loaded character goes
##
## The last four are edits of the wardrobe, so they can be undone and they mark the file as changed. The workspace
## is a PreviewWorkspace: current_character(), load_character(), character_id.

var _list: ItemList = null
var _ids: Array[String] = []
var _name: LineEdit = null


func _build() -> void:
	var box := section("Saved characters")
	_list = make_list(box, 110)
	_list.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _ids.size():
			return
		var who := wardrobe().character(_ids[index])
		begin_guard()
		_name.text = who.name
		end_guard()
		workspace.call("load_character", who))
	_name = labelled(box, "Name", LineEdit.new()) as LineEdit
	_name.placeholder_text = "a name for the character"
	button_row(box, [
		{"text": "Save as new", "action": _on_save_new},
		{"text": "Update", "action": _on_update},
		{"text": "Rename", "action": _on_rename},
		{"text": "Delete", "action": _on_delete},
	])
	hint(box, "A character is everything chosen on this tab but the pose and the shading. The game builds one by "
		+ "its name (GameCharacter). Pick one to see it; Update saves the changes made to it.")


func refresh() -> void:
	var w := wardrobe()
	if w == null:
		return
	begin_guard()
	_ids = w.character_ids()
	_list.clear()
	var loaded := String(workspace.get("character_id"))
	for id in _ids:
		_list.add_item(w.character(id).name)
	var at := _ids.find(loaded)
	if at >= 0:
		_list.select(at)
	else:
		_list.deselect_all()
	end_guard()


func _loaded() -> CharacterDef:
	var id := String(workspace.get("character_id"))
	return wardrobe().character(id) if not id.is_empty() else null


func _on_save_new() -> void:
	var name := _name.text.strip_edges()
	if name.is_empty():
		editor.set_status_hint("Type a name for the character first.")
		return
	var id := wardrobe().unique_character_id(name)
	var who := (workspace.call("current_character") as CharacterDef).duplicate_as(id, name)
	wardrobe().add_character(who)
	workspace.set("character_id", id)
	commit("Save character %s" % name)
	_after()


func _on_update() -> void:
	var loaded := _loaded()
	if loaded == null:
		editor.set_status_hint("Pick a character in the list first, or Save as new.")
		return
	var now := workspace.call("current_character") as CharacterDef
	if now.looks_like(loaded, wardrobe()):
		editor.set_status_hint("%s is already saved as it is." % loaded.name)
		return
	wardrobe().add_character(now.duplicate_as(loaded.id, loaded.name))
	commit("Update character %s" % loaded.name)
	_after()


func _on_rename() -> void:
	var loaded := _loaded()
	var name := _name.text.strip_edges()
	if loaded == null:
		editor.set_status_hint("Pick a character in the list first.")
		return
	if name.is_empty() or name == loaded.name:
		editor.set_status_hint("Type the new name first.")
		return
	var old := loaded.name
	loaded.name = name
	commit("Rename character %s to %s" % [old, name])
	_after()


func _on_delete() -> void:
	var loaded := _loaded()
	if loaded == null:
		editor.set_status_hint("Pick a character in the list first.")
		return
	wardrobe().remove_character(loaded.id)
	workspace.set("character_id", "")
	commit("Delete character %s" % loaded.name)
	_after()


func _after() -> void:
	refresh()
	workspace.call("refresh_summary")
