@tool
class_name ColourPanel
extends EditorPanel

## Palette, colour roles and colourways (SPEC.md section 8).
##
## Every swatch is listed with its NAME and its hex value, never as colour
## alone: the owner is red/green colour blind, so a list of squares would be
## unusable. The default palette avoids pairs that differ only in red vs green.

var _palette: ItemList = null
var _palette_name: LineEdit = null
var _palette_colour: ColorPickerButton = null
var _roles: ItemList = null
var _role_name: LineEdit = null
var _colourways: ItemList = null
var _colourway_name: LineEdit = null
var _assignments: VBoxContainer = null

var _palette_keys: Array[String] = []
var _role_names: Array[String] = []
var _colourway_names: Array[String] = []


func _build() -> void:
	var palette_box := section("Palette")
	_palette = make_list(palette_box, 150)
	_palette.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _palette_keys.size():
			return
		begin_guard()
		_palette_name.text = _palette_keys[index]
		_palette_colour.color = wardrobe().colour(_palette_keys[index])
		end_guard())

	_palette_name = labelled(palette_box, "Name", LineEdit.new()) as LineEdit
	_palette_colour = labelled(palette_box, "Colour", ColorPickerButton.new()) as ColorPickerButton
	_palette_colour.edit_alpha = false
	_palette_colour.color_changed.connect(func(c: Color) -> void:
		if is_guarded():
			return
		var key := _palette_name.text.strip_edges()
		if key.is_empty() or not wardrobe().palette.has(key):
			return
		wardrobe().set_colour(key, c)
		commit("Set colour %s" % key)
		refresh())

	button_row(palette_box, [
		{"text": "Add or update", "action": _on_add_colour},
		{"text": "Remove", "action": _on_remove_colour},
	])
	hint(palette_box, "Items refer to palette colours by name, so changing one "
		+ "here restyles every item that uses it. A colour becomes light, mid "
		+ "and dark automatically.")

	var roles_box := section("Roles on the selected item")
	_roles = make_list(roles_box, 110)
	_roles.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _role_names.size():
			return
		begin_guard()
		_role_name.text = _role_names[index]
		end_guard())
	_role_name = labelled(roles_box, "Role name", LineEdit.new()) as LineEdit
	button_row(roles_box, [
		{"text": "Add", "action": _on_add_role},
		{"text": "Rename", "action": _on_rename_role},
		{"text": "Remove", "action": _on_remove_role},
	])
	hint(roles_box, "A role is a named part of the design: cloth, trim, buckle. "
		+ "Regions are painted with a role, and a colourway says what colour "
		+ "each role takes.")

	var ways_box := section("Colourways")
	_colourways = make_list(ways_box, 90)
	_colourways.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _colourway_names.size():
			return
		begin_guard()
		_colourway_name.text = _colourway_names[index]
		end_guard()
		_rebuild_assignments())
	_colourway_name = labelled(ways_box, "Name", LineEdit.new()) as LineEdit
	button_row(ways_box, [
		{"text": "Add", "action": _on_add_colourway},
		{"text": "Duplicate", "action": _on_duplicate_colourway},
		{"text": "Remove", "action": _on_remove_colourway},
	])

	_assignments = VBoxContainer.new()
	add_child(_assignments)


func refresh() -> void:
	var w := wardrobe()
	if w == null:
		return
	begin_guard()

	_palette_keys = w.palette_names()
	_palette.clear()
	for key in _palette_keys:
		_palette.add_item("%s   %s" % [key, JsonIO.colour_to_hex(w.colour(key))])

	var it := item()
	_role_names.clear()
	_colourway_names.clear()
	if it != null:
		_role_names.append_array(it.roles)
		_colourway_names.append_array(it.colourway_names())

	_roles.clear()
	for role in _role_names:
		_roles.add_item(role)

	_colourways.clear()
	for name in _colourway_names:
		_colourways.add_item(name)
	if _colourway_name.text.is_empty() and not _colourway_names.is_empty():
		_colourway_name.text = _colourway_names[0]

	end_guard()
	_rebuild_assignments()


## One row per role: which palette colour it takes in the chosen colourway.
func _rebuild_assignments() -> void:
	for child in _assignments.get_children():
		_assignments.remove_child(child)
		child.queue_free()

	var it := item()
	var w := wardrobe()
	if it == null or w == null:
		return
	var colourway := _colourway_name.text.strip_edges()
	if not it.has_colourway(colourway):
		colourway = it.first_colourway()
	if colourway.is_empty():
		return

	var heading := Label.new()
	heading.text = "Colours in \"%s\"" % colourway
	heading.add_theme_font_size_override("font_size", 15)
	_assignments.add_child(heading)
	_assignments.add_child(HSeparator.new())

	for role in it.roles:
		var option := OptionButton.new()
		var current := it.palette_key_for(colourway, role)
		var names := w.palette_names()
		var labels: Array = []
		for key in names:
			labels.append("%s   %s" % [key, JsonIO.colour_to_hex(w.colour(key))])
		labelled(_assignments, role, option)
		fill_options(option, names, current, labels)
		option.item_selected.connect(func(_i: int) -> void:
			if is_guarded():
				return
			it.set_palette_key(colourway, role, option_value(option))
			commit("Set %s colour in %s" % [role, colourway]))


# ------------------------------------------------------------------ actions --

func _on_add_colour() -> void:
	var key := _palette_name.text.strip_edges()
	if key.is_empty():
		editor.set_status_hint("Type a palette name first.")
		return
	wardrobe().set_colour(key, _palette_colour.color)
	commit("Add colour %s" % key)
	refresh()


func _on_remove_colour() -> void:
	var selected := _palette.get_selected_items()
	if selected.is_empty():
		return
	var key := _palette_keys[selected[0]]
	wardrobe().remove_colour(key)
	commit("Remove colour %s" % key)
	refresh()


func _on_add_role() -> void:
	var it := item()
	var role := _role_name.text.strip_edges()
	if it == null or role.is_empty():
		return
	it.add_role(role)
	commit("Add role %s to %s" % [role, it.name])
	refresh()


func _on_rename_role() -> void:
	var it := item()
	var selected := _roles.get_selected_items()
	var new_name := _role_name.text.strip_edges()
	if it == null or selected.is_empty() or new_name.is_empty():
		return
	var old_name := _role_names[selected[0]]
	if old_name == new_name:
		return
	it.rename_role(old_name, new_name)
	commit("Rename role %s to %s" % [old_name, new_name])
	refresh()


func _on_remove_role() -> void:
	var it := item()
	var selected := _roles.get_selected_items()
	if it == null or selected.is_empty():
		return
	if it.roles.size() <= 1:
		editor.set_status_hint("An item needs at least one role.")
		return
	var role := _role_names[selected[0]]
	it.remove_role(role)
	commit("Remove role %s from %s" % [role, it.name])
	refresh()


func _on_add_colourway() -> void:
	var it := item()
	var name := _colourway_name.text.strip_edges()
	if it == null or name.is_empty():
		return
	it.add_colourway(name)
	commit("Add colourway %s to %s" % [name, it.name])
	refresh()


func _on_duplicate_colourway() -> void:
	var it := item()
	var selected := _colourways.get_selected_items()
	var name := _colourway_name.text.strip_edges()
	if it == null or selected.is_empty() or name.is_empty():
		return
	var source := _colourway_names[selected[0]]
	if name == source:
		name = source + " copy"
	it.add_colourway(name, source)
	_colourway_name.text = name
	commit("Duplicate colourway %s" % source)
	refresh()


func _on_remove_colourway() -> void:
	var it := item()
	var selected := _colourways.get_selected_items()
	if it == null or selected.is_empty():
		return
	if it.colourways.size() <= 1:
		editor.set_status_hint("An item needs at least one colourway.")
		return
	var name := _colourway_names[selected[0]]
	it.colourways.erase(name)
	commit("Remove colourway %s" % name)
	refresh()
