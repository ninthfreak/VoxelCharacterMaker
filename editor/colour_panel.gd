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
var _picking := false              ## the colour picker is open and has made an edit already
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
	# The picker reports every step of a drag: while it is open they are one edit, so one undo.
	_palette_colour.color_changed.connect(func(c: Color) -> void:
		if is_guarded():
			return
		var key := _palette_name.text.strip_edges()
		if key.is_empty() or not wardrobe().palette.has(key):
			return
		wardrobe().set_colour(key, c)
		commit("Set colour %s" % key, _picking)
		_picking = true
		refresh())
	_palette_colour.popup_closed.connect(func() -> void: _picking = false)

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
		_show_colourway(_colourway_names[index]))
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
	if it != null:
		var at := _colourway_names.find(_way(it))
		if at >= 0:
			_colourways.select(at)
		if _colourway_name.text.is_empty():
			_colourway_name.text = _way(it)

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
	var colourway := _way(it)
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
		var names: Array = []
		var labels: Array = []
		# Colour references first: resolved per character (a beard that follows
		# the hair). Then the palette, each with its hex value.
		for ref in Palette.COLOUR_REFERENCES.keys():
			names.append(String(ref))
			labels.append(String(Palette.COLOUR_REFERENCES[ref]))
		for key in w.palette_names():
			names.append(key)
			labels.append("%s   %s" % [key, JsonIO.colour_to_hex(w.colour(key))])
		labelled(_assignments, role, option)
		if not names.has(current):                      # shown as it is, not as the first colour in the list
			names.append(current)
			labels.append(missing_colour_label(current))
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
	var users := wardrobe().colour_users(key)
	if not users.is_empty():
		var named := ", ".join(users.slice(0, 4)) + (" and %d more" % (users.size() - 4) if users.size() > 4 else "")
		editor.set_status_hint("%s is in use: %s. Give those another colour first." % [key, named])
		return
	wardrobe().remove_colour(key)
	commit("Remove colour %s" % key)
	refresh()


func _on_add_role() -> void:
	var it := item()
	var role := _role_name.text.strip_edges()
	if it == null or role.is_empty():
		return
	if it.roles.has(role):
		editor.set_status_hint("%s already has a role named %s." % [it.name, role])
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
	if it.roles.has(new_name):
		editor.set_status_hint("%s already has a role named %s." % [it.name, new_name])
		return
	if _shape_reads(it, old_name):
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
	if _shape_reads(it, role):
		return
	it.remove_role(role)
	commit("Remove role %s from %s" % [role, it.name])
	refresh()


func _on_add_colourway() -> void:
	var it := item()
	var name := _colourway_name.text.strip_edges()
	if it == null or name.is_empty():
		return
	if it.colourways.has(name):
		editor.set_status_hint("%s already has a colourway named %s." % [it.name, name])
		return
	it.add_colourway(name)
	commit("Add colourway %s to %s" % [name, it.name])
	_show_colourway(name)
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
	if it.colourways.has(name):
		editor.set_status_hint("%s already has a colourway named %s." % [it.name, name])
		return
	it.add_colourway(name, source)
	_colourway_name.text = name
	commit("Duplicate colourway %s" % source)
	_show_colourway(name)
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


## Whether one of the item's special shapes reads this role by name; if so, says so in the status line.
func _shape_reads(it: GarmentItem, role: String) -> bool:
	var by: Array = it.shape_roles().get(role, [])
	if by.is_empty():
		return false
	var names: Array[String] = []
	for type in by:
		names.append(SpecialItem.display_name(String(type)).to_lower())
	editor.set_status_hint("The %s on %s colours with \"%s\", so it keeps that name. Change its colour instead." % [
		" and ".join(names), it.name, role])
	return true


## The colourway whose colours the panel shows and edits: the one chosen for the item (in its list, or here), which
## is also the one the preview shows.
func _way(it: GarmentItem) -> String:
	if selection != null and it.has_colourway(selection.colourway):
		return selection.colourway
	return it.first_colourway()


## Choose a colourway for the item, here as in its list: the preview, and a worn item, show it.
func _show_colourway(name: String) -> void:
	if selection == null:
		_rebuild_assignments()
		return
	selection.set_colourway(name)
	if workspace != null and workspace.has_method("set_worn_colourway") and workspace.call("is_worn", selection.item_id):
		workspace.call("set_worn_colourway", selection.item_id, name)
