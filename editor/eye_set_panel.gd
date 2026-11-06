@tool
class_name EyeSetPanel
extends EditorPanel

## Eyes (SPEC.md section 5, and the face editor of section 8).
##
## Eye sets are styles; every set is drawn through the same expression list, so
## the expression chosen here carries across when the set changes. Expressions
## are edited on the eye-box grid, one eye with the other mirroring, or each
## eye separately for a wink or a sideways look. Eye colour is a colourway.
##
## The workspace owns what the preview shows -- eye_set_id, expression and
## eye_colourway -- and this panel changes them.

var _sets: ItemList = null
var _set_ids: Array[String] = []
var _set_name: LineEdit = null
var _expressions: ItemList = null
var _expression_names: Array[String] = []
var _expression_name: LineEdit = null
var _role: OptionButton = null
var _both: CheckBox = null
var _grid: EyeBoxGrid = null
var _fit: Label = null
var _colourway: OptionButton = null
var _assignments: VBoxContainer = null
var _new_colourway: LineEdit = null


func _build() -> void:
	var sets := section("Eye sets")
	_sets = make_list(sets, 90)
	_sets.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _set_ids.size():
			return
		workspace.set("eye_set_id", _set_ids[index])
		workspace.call("on_eyes_changed")
		refresh())
	_set_name = labelled(sets, "Name", LineEdit.new()) as LineEdit
	_set_name.text_submitted.connect(func(text: String) -> void: _rename_set(text))
	button_row(sets, [
		{"text": "New from standard", "action": _on_new_set},
		{"text": "Duplicate", "action": _on_duplicate_set},
		{"text": "Delete", "action": _on_delete_set},
	])

	var faces := section("Expressions")
	_expressions = make_list(faces, 150)
	_expressions.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _expression_names.size():
			return
		workspace.set("expression", _expression_names[index])
		workspace.call("on_eyes_changed")
		refresh())
	_expression_name = labelled(faces, "Name", LineEdit.new()) as LineEdit
	button_row(faces, [
		{"text": "Add (copy of selected)", "action": _on_add_expression},
		{"text": "Rename", "action": _on_rename_expression},
		{"text": "Remove", "action": _on_remove_expression},
	])
	hint(faces, "Every eye set has the same expressions, so changing set keeps the "
		+ "face being made. Neutral cannot be removed: a missing expression falls "
		+ "back to it.")

	var draw := section("Draw")
	var tools := HFlowContainer.new()
	draw.add_child(tools)
	var paint_label := Label.new()
	paint_label.text = "Paint with"
	tools.add_child(paint_label)
	_role = OptionButton.new()
	fill_options(_role, EyeSet.ROLES, EyeSet.ROLE_PUPIL,
		["white (W)", "pupil (P)", "lid line (L)"])
	_role.item_selected.connect(func(_i: int) -> void:
		_grid.role = option_value(_role)
		_grid.queue_redraw())
	tools.add_child(_role)
	_both = CheckBox.new()
	_both.text = "Both eyes (mirrored)"
	_both.button_pressed = true
	_both.toggled.connect(func(on: bool) -> void:
		_grid.both_eyes = on
		_grid.queue_redraw())
	tools.add_child(_both)
	_grid = EyeBoxGrid.new()
	_grid.stroke_finished.connect(_on_drawn)
	draw.add_child(_grid)
	_fit = Label.new()
	_fit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draw.add_child(_fit)
	hint(draw, "Turn \"both eyes\" off for a wink or a sideways look.")

	var colour := section("Eye colours")
	_colourway = labelled(colour, "Colourway", OptionButton.new()) as OptionButton
	_colourway.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		workspace.set("eye_colourway", option_value(_colourway))
		workspace.call("on_eyes_changed")
		refresh())
	_assignments = VBoxContainer.new()
	colour.add_child(_assignments)
	_new_colourway = labelled(colour, "New name", LineEdit.new()) as LineEdit
	button_row(colour, [{"text": "Add colourway", "action": _on_add_colourway}])


func _eyes() -> EyeSet:
	return editor.wardrobe.eye_set(String(workspace.get("eye_set_id"))) \
		if editor.wardrobe != null else null


func refresh() -> void:
	if editor.wardrobe == null:
		return
	begin_guard()
	_set_ids = editor.wardrobe.eye_set_ids()
	_sets.clear()
	var current := String(workspace.get("eye_set_id"))
	for id in _set_ids:
		_sets.add_item(editor.wardrobe.eye_set(id).name)
		if id == current:
			_sets.select(_sets.item_count - 1)

	var eyes := _eyes()
	_set_name.text = eyes.name if eyes != null else ""
	_expression_names.clear()
	_expressions.clear()
	var expression := String(workspace.get("expression"))
	if eyes != null:
		for name in eyes.expression_names():
			_expression_names.append(name)
			var text := name.replace("_", " ")
			if not eyes.is_symmetric(name):
				text += "   [each eye drawn]"
			_expressions.add_item(text)
			if name == eyes.resolve(expression):
				_expressions.select(_expressions.item_count - 1)
		_expression_name.text = eyes.resolve(expression)

	var way := String(workspace.get("eye_colourway"))
	if eyes != null:
		fill_options(_colourway, eyes.colourway_names(),
			way if eyes.colourways.has(way) else eyes.first_colourway())
	end_guard()

	_grid.eye_set = eyes
	_grid.expression = eyes.resolve(expression) if eyes != null else EyeSet.NEUTRAL
	_grid.role = option_value(_role)
	var colours := {}
	if eyes != null:
		for role in EyeSet.ROLES:
			colours[role] = editor.wardrobe.eye_colour(eyes.id, option_value(_colourway), role)
	_grid.colours = colours
	_grid.queue_redraw()
	_refresh_fit(eyes)
	_rebuild_assignments(eyes)


## Whether the expression fits every head. SPEC 12: "no eye cell falls off the
## face plane". A cell that does would simply not appear on that head.
func _refresh_fit(eyes: EyeSet) -> void:
	if eyes == null:
		_fit.text = ""
		return
	var expression := eyes.resolve(String(workspace.get("expression")))
	var problems: Array[String] = []
	for shape in editor.library.head_shapes():
		var missing := eyes.missing_on_head(expression, editor.library.head(shape))
		if not missing.is_empty():
			problems.append("%s (%d cell%s)" % [shape, missing.size(),
				"" if missing.size() == 1 else "s"])
	if problems.is_empty():
		_fit.text = "ok  This expression fits all %d heads." % editor.library.head_shapes().size()
		_fit.add_theme_color_override("font_color", Color8(160, 168, 184))
	else:
		_fit.text = "FAIL  Falls off: %s." % ", ".join(problems)
		_fit.add_theme_color_override("font_color", Palette.UI_ORANGE)


func _rebuild_assignments(eyes: EyeSet) -> void:
	for child in _assignments.get_children():
		_assignments.remove_child(child)
		child.queue_free()
	if eyes == null:
		return
	var way := option_value(_colourway)
	var names := editor.wardrobe.palette_names()
	var labels: Array = []
	for key in names:
		labels.append("%s   %s" % [key, JsonIO.colour_to_hex(editor.wardrobe.colour(key))])
	for role in EyeSet.ROLES:
		var option := OptionButton.new()
		labelled(_assignments, role, option)
		fill_options(option, names, eyes.palette_key_for(way, role), labels)
		option.item_selected.connect(func(_i: int) -> void:
			if is_guarded():
				return
			eyes.set_palette_key(way, role, option_value(option))
			commit("Set %s colour in %s" % [role, way])
			refresh())


# ------------------------------------------------------------------ actions --

func _on_drawn() -> void:
	commit("Draw eyes: %s" % _grid.expression.replace("_", " "))
	refresh()


func _on_new_set() -> void:
	var standard := EyeSet.from_library(editor.library)
	var id := editor.wardrobe.unique_eye_set_id("eyes")
	var fresh := standard.duplicate_as(id, "New eyes")
	editor.wardrobe.add_eye_set(fresh)
	workspace.set("eye_set_id", id)
	commit("Add eye set")
	refresh()


func _on_duplicate_set() -> void:
	var eyes := _eyes()
	if eyes == null:
		return
	var id := editor.wardrobe.unique_eye_set_id(eyes.name + " copy")
	editor.wardrobe.add_eye_set(eyes.duplicate_as(id, eyes.name + " copy"))
	workspace.set("eye_set_id", id)
	commit("Duplicate eye set %s" % eyes.name)
	refresh()


func _on_delete_set() -> void:
	var eyes := _eyes()
	if eyes == null:
		return
	if editor.wardrobe.eye_set_ids().size() <= 1:
		editor.set_status_hint("Every character needs eyes: keep at least one eye set.")
		return
	editor.wardrobe.remove_eye_set(eyes.id)
	workspace.set("eye_set_id", editor.wardrobe.first_eye_set_id())
	commit("Delete eye set %s" % eyes.name)
	refresh()


func _rename_set(text: String) -> void:
	var eyes := _eyes()
	var trimmed := text.strip_edges()
	if eyes == null or trimmed.is_empty() or trimmed == eyes.name:
		return
	eyes.name = trimmed
	commit("Rename eye set to %s" % trimmed)
	refresh()


func _on_add_expression() -> void:
	var eyes := _eyes()
	var name := _expression_name.text.strip_edges().to_snake_case()
	if eyes == null or name.is_empty():
		return
	var source := eyes.resolve(String(workspace.get("expression")))
	if not eyes.add_expression(name, source):
		editor.set_status_hint("There is already an expression called %s." % name)
		return
	workspace.set("expression", name)
	commit("Add expression %s" % name)
	refresh()


func _on_rename_expression() -> void:
	var eyes := _eyes()
	var old_name := eyes.resolve(String(workspace.get("expression"))) if eyes != null else ""
	var name := _expression_name.text.strip_edges().to_snake_case()
	if eyes == null or name.is_empty() or name == old_name:
		return
	if not eyes.rename_expression(old_name, name):
		editor.set_status_hint("Neutral keeps its name, and names must be unique.")
		return
	workspace.set("expression", name)
	commit("Rename expression %s to %s" % [old_name, name])
	refresh()


func _on_remove_expression() -> void:
	var eyes := _eyes()
	if eyes == null:
		return
	var name := eyes.resolve(String(workspace.get("expression")))
	if not eyes.remove_expression(name):
		editor.set_status_hint("Neutral cannot be removed.")
		return
	workspace.set("expression", EyeSet.NEUTRAL)
	commit("Remove expression %s" % name)
	refresh()


func _on_add_colourway() -> void:
	var eyes := _eyes()
	var name := _new_colourway.text.strip_edges()
	if eyes == null or name.is_empty():
		return
	eyes.add_colourway(name, option_value(_colourway))
	workspace.set("eye_colourway", name)
	commit("Add eye colourway %s" % name)
	refresh()
