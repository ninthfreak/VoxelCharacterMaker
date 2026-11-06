@tool
class_name BodiesWorkspace
extends Workspace

## The Bodies tab: the six body types and the head shapes, bare.
##
## No hair, no clothes, no items; only the basic profile of the eyes, so the
## face's orientation and the eye box are always in view while a head is
## reshaped. Bodies and heads are edited on horizontal slices -- the unit they
## were designed in -- with the mirror and one-owner rules enforced by the
## model, row-band guides, pivot markers, live checks, and the pose preview the
## spec calls the real test of part splits and pivots.
##
## An edit goes into the asset library as it is drawn, so every other tab sees
## it straight away. Saving writes it to assets/edited/, which the library
## prefers over the generated file; "Revert to generated" deletes that file.

const KIND_BODY := "body"
const KIND_HEAD := "head"

var body_id: String = "male_average"
var head_shape: String = "round"
var pose: String = Poses.REST

## What is open for editing: a BodyEdit, a HeadEdit, or null.
var edit: VoxelEditModel = null
var history := EditHistory.new()
var _dirty := false

var _body_pick: OptionButton = null
var _head_pick: OptionButton = null
var _pose_pick: OptionButton = null
var _status_label: Label = null
var _edit_buttons: HFlowContainer = null
var _editing_buttons: HFlowContainer = null
var _edited_note: Label = null
var _row: HSlider = null
var _row_label: Label = null
var _band_label: Label = null
var _grid: SliceGrid = null
var _hover_label: Label = null
var _parts: ItemList = null
var _part_names: Array[String] = []
var _pivot_label: Label = null
var _validation: RichTextLabel = null
var _revert_dialog: ConfirmationDialog = null
var _guard := 0


func title() -> String:
	return "Bodies"


func _build() -> void:
	heading(side, "Bodies and heads")
	note(side, "Bare figures with only the basic eyes. Edits are mirrored and a "
		+ "voxel belongs to one part only, so the halves always match.")

	_body_pick = cycler(side, "Body", editor.library.body_ids(), body_labels(),
		func(value: String) -> void: _choose_body(value))
	_head_pick = cycler(side, "Head", editor.library.head_shapes(), [],
		func(value: String) -> void: _choose_head(value))
	_pose_pick = picker(side, "Pose", Poses.names(), pose_labels(),
		func(value: String) -> void:
			pose = value
			view.set_pose(value))

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_status_label)
	_edited_note = note(side, "")

	_edit_buttons = HFlowContainer.new()
	side.add_child(_edit_buttons)
	for entry in [["Edit this body", KIND_BODY], ["Edit this head", KIND_HEAD]]:
		var button := Button.new()
		button.text = String(entry[0])
		var kind := String(entry[1])
		button.pressed.connect(func() -> void: start_editing(kind))
		_edit_buttons.add_child(button)

	_editing_buttons = HFlowContainer.new()
	side.add_child(_editing_buttons)
	for entry2 in [["Save", _on_save], ["Stop editing", _on_stop],
			["Revert to generated", _on_revert]]:
		var button2 := Button.new()
		button2.text = String(entry2[0])
		button2.pressed.connect(entry2[1] as Callable)
		_editing_buttons.add_child(button2)

	_build_slice()
	_build_layers()
	_build_checks()

	_revert_dialog = ConfirmationDialog.new()
	_revert_dialog.title = "Revert to generated"
	_revert_dialog.ok_button_text = "Delete the edit"
	_revert_dialog.cancel_button_text = "Keep it"
	_revert_dialog.confirmed.connect(_do_revert)
	add_child(_revert_dialog)


func _build_slice() -> void:
	heading(side, "Slice")
	var line := HBoxContainer.new()
	side.add_child(line)
	_row_label = Label.new()
	_row_label.custom_minimum_size = Vector2(90, 0)
	line.add_child(_row_label)
	_row = HSlider.new()
	_row.min_value = 0
	_row.max_value = VoxelAxes.GRID.z - 1
	_row.step = 1
	_row.value = 22
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.value_changed.connect(func(v: float) -> void:
		if _guard > 0:
			return
		_grid.z = int(v)
		_grid.queue_redraw()
		_refresh_row_labels())
	line.add_child(_row)
	_band_label = Label.new()
	_band_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_band_label)

	_grid = SliceGrid.new()
	_grid.painted.connect(func(cells: Array, part_name: String) -> void:
		_after_stroke("Paint %d cell%s as %s" % [
			cells.size(), "" if cells.size() == 1 else "s", part_name]))
	_grid.erased.connect(func(cells: Array) -> void:
		_after_stroke("Erase %d cell%s" % [cells.size(), "" if cells.size() == 1 else "s"]))
	_grid.hovered.connect(_on_hovered)
	side.add_child(_grid)
	_hover_label = note(side, "")
	var neighbours := CheckBox.new()
	neighbours.text = "Show the rows above and below"
	neighbours.button_pressed = true
	neighbours.toggled.connect(func(on: bool) -> void:
		_grid.show_neighbour_rows = on
		_grid.queue_redraw())
	side.add_child(neighbours)


func _build_layers() -> void:
	heading(side, "Parts")
	_parts = ItemList.new()
	_parts.custom_minimum_size = Vector2(0, 140)
	_parts.item_selected.connect(func(index: int) -> void:
		if _guard > 0 or index < 0 or index >= _part_names.size():
			return
		_grid.active_part = _part_names[index]
		_grid.queue_redraw()
		_refresh_pivot())
	side.add_child(_parts)
	note(side, "The selected part is what you paint with. Left button paints, right "
		+ "button erases.")
	_pivot_label = Label.new()
	_pivot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_pivot_label)


func _build_checks() -> void:
	heading(side, "Checks")
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = true
	_validation.fit_content = true
	_validation.custom_minimum_size = Vector2(0, 150)
	side.add_child(_validation)
	var buttons := HFlowContainer.new()
	side.add_child(buttons)
	var show := Button.new()
	show.text = "Show problem cells"
	show.pressed.connect(_on_show_problems)
	buttons.add_child(show)
	var clear := Button.new()
	clear.text = "Clear marks"
	clear.pressed.connect(func() -> void:
		_grid.problem_cells = {}
		_grid.queue_redraw())
	buttons.add_child(clear)


# ---------------------------------------------------------------- preview --

func make_request() -> CharacterAssembler.Request:
	# Bare: no wardrobe items, no features, and the library's own neutral eyes.
	var request := CharacterAssembler.Request.make(editor.library, body_id, head_shape,
		EyeSet.NEUTRAL)
	return request


func status_text(assembled: CharacterAssembler.Assembled) -> String:
	var base := super.status_text(assembled)
	if edit != null:
		base += "   |   editing the %s%s" % [edit.display_name(), " (unsaved)" if _dirty else ""]
	return base


# ---------------------------------------------------------------- choices --

func _choose_body(value: String) -> void:
	if edit is BodyEdit and value != body_id:
		# Switching body while one is open: save or discard it first.
		var switch := func() -> void:
			body_id = value
			_open(KIND_BODY)
		editor.guard_unsaved(switch, true, false)
		select_value(_body_pick, body_id)
		return
	body_id = value
	refresh()
	rebuild()


func _choose_head(value: String) -> void:
	if edit is HeadEdit and value != head_shape:
		var switch := func() -> void:
			head_shape = value
			_open(KIND_HEAD)
		editor.guard_unsaved(switch, true, false)
		select_value(_head_pick, head_shape)
		return
	head_shape = value
	refresh()
	rebuild()


# ---------------------------------------------------------------- editing --

func is_editing() -> bool:
	return edit != null


func has_unsaved() -> bool:
	return edit != null and _dirty


func edit_kind() -> String:
	return edit.kind() if edit != null else ""


func edit_display_name() -> String:
	return edit.display_name() if edit != null else ""


## Open the body or head currently chosen, asking first if another is unsaved.
func start_editing(kind: String) -> void:
	var start := func() -> void: _open(kind)
	editor.guard_unsaved(start, true, false)


func _open(kind: String) -> void:
	if kind == KIND_HEAD:
		edit = HeadEdit.from_head(editor.library.head(head_shape))
		_grid.active_part = HeadEdit.PART
		_set_row(BodyLayout.EYE_Z0 + 2)   # through the eyes
	else:
		edit = BodyEdit.from_body(editor.library.body(body_id))
		if not (_grid.active_part in edit.paintable_parts()):
			_grid.active_part = edit.paintable_parts()[1]
		_set_row(BodyLayout.z0("upper_chest"))
	history.reset(edit.snapshot(), "Open the %s" % edit.display_name())
	editor.forget_edits(CharacterEditor.DOC_BODY)
	_dirty = false
	_grid.body = edit
	_grid.problem_cells = {}
	refresh()
	rebuild()
	editor.set_status_hint("Editing the %s. Every tab sees the change as you draw."
		% edit.display_name())


func _stop_now() -> void:
	edit = null
	_dirty = false
	_grid.body = null
	history.reset({}, "Nothing open")
	editor.forget_edits(CharacterEditor.DOC_BODY)
	refresh()
	rebuild()


func _after_stroke(label: String) -> void:
	_dirty = true
	history.commit(label, edit.snapshot())
	editor.note_edit(CharacterEditor.DOC_BODY)
	_push_to_library()


## The edit goes into the library as it stands, so every tab shows it.
func _push_to_library() -> void:
	if edit is BodyEdit:
		editor.library.replace_body((edit as BodyEdit).to_body_def())
	elif edit is HeadEdit:
		editor.library.replace_head((edit as HeadEdit).to_head_def())
	editor.mark_others_stale(self)
	refresh()
	rebuild()


## From the undo timeline.
func restore_snapshot(snapshot: Dictionary) -> void:
	if edit == null:
		return
	edit.restore(snapshot)
	_dirty = true
	_push_to_library()


## "Save first" from an unsaved-changes prompt.
func save_for_prompt() -> void:
	_on_save()


## "Discard changes" from a prompt: put the library back to what is on disk.
func discard_unsaved() -> void:
	if edit is BodyEdit:
		editor.library.reload_body((edit as BodyEdit).id())
	elif edit is HeadEdit:
		editor.library.reload_head((edit as HeadEdit).shape)
	_dirty = false
	editor.mark_others_stale(self)


func _on_save() -> void:
	if edit == null:
		editor.set_status_hint("Open a body or head first.")
		editor.cancel_pending()
		return
	var path := ""
	if edit is BodyEdit:
		var b := edit as BodyEdit
		path = editor.library.edited_body_path(b.sex, b.build)
		editor.library.replace_body(b.to_body_def())
	else:
		path = editor.library.edited_head_path((edit as HeadEdit).shape)
		editor.library.replace_head((edit as HeadEdit).to_head_def())
	var err := ""
	if edit is BodyEdit:
		err = (edit as BodyEdit).save_to(path)
	else:
		err = (edit as HeadEdit).save_to(path)
	if not err.is_empty():
		editor.cancel_pending()
		editor.set_status_hint("Could not save: %s" % err)
		return
	_dirty = false
	refresh()
	rebuild()
	editor.set_status_hint("Saved the %s to %s" % [edit.display_name(), path])
	editor.resume_pending()


func _on_stop() -> void:
	if edit == null:
		return
	editor.guard_unsaved(_stop_now, true, false)


func _on_revert() -> void:
	if edit == null:
		return
	var edited := editor.library.is_body_edited(body_id) if edit is BodyEdit \
		else editor.library.is_head_edited(head_shape)
	if not edited and not _dirty:
		editor.set_status_hint("The %s is already the generated one." % edit.display_name())
		return
	_revert_dialog.dialog_text = ("Delete the saved edit of the %s and go back to the "
		+ "one tools/build_bodies.py generates?") % edit.display_name()
	_revert_dialog.popup_centered()


func _do_revert() -> void:
	if edit == null:
		return
	var kind := edit.kind()
	var err := editor.library.revert_body(body_id) if kind == KIND_BODY \
		else editor.library.revert_head(head_shape)
	if not err.is_empty():
		editor.set_status_hint("Could not revert: %s" % err)
		return
	_dirty = false
	editor.mark_others_stale(self)
	_open(kind)
	editor.set_status_hint("Back to the generated %s." % edit.display_name())


func _on_hovered(cell: Vector3i, owner_part: String) -> void:
	var side_word := "character's left" if VoxelAxes.is_left(cell) else "character's right"
	var depth := "front" if VoxelAxes.is_front(cell) else "back"
	_hover_label.text = "x%d y%d z%d  -  %s, %s  -  %s" % [cell.x, cell.y, cell.z,
		side_word, depth, owner_part if not owner_part.is_empty() else "empty"]


# ---------------------------------------------------------------- refresh --

func refresh() -> void:
	if _grid == null:
		return
	_guard += 1
	select_value(_body_pick, body_id)
	select_value(_head_pick, head_shape)
	select_value(_pose_pick, pose)

	var editing := edit != null
	_edit_buttons.visible = not editing
	_editing_buttons.visible = editing
	if editing:
		_status_label.text = "Editing the %s%s" % [edit.display_name(),
			" - unsaved changes" if _dirty else ""]
	else:
		_status_label.text = "Nothing open. Choose a body and head, then edit one."
	var notes: Array[String] = []
	if editor.library.is_body_edited(body_id):
		notes.append("this body is an edited version (assets/edited/)")
	if editor.library.is_head_edited(head_shape):
		notes.append("this head is an edited version (assets/edited/)")
	_edited_note.text = "" if notes.is_empty() else "Note: %s." % "; ".join(notes)

	_part_names.clear()
	_parts.clear()
	if editing:
		for name in edit.paintable_parts():
			_part_names.append(name)
			var index := _parts.add_item("%s   %d voxels" % [name, edit.part_cells(name).size()])
			_parts.set_item_custom_fg_color(index, _grid.colour_for(name))
			if name == _grid.active_part:
				_parts.select(index)
	_grid.body = edit
	_guard -= 1
	_refresh_row_labels()
	_refresh_pivot()
	_refresh_validation()
	_grid.queue_redraw()


func _set_row(z: int) -> void:
	_guard += 1
	_row.value = z
	_guard -= 1
	_grid.z = z
	_refresh_row_labels()


## Public, for a screenshot or a shortcut.
func set_row(z: int) -> void:
	_set_row(z)
	_grid.queue_redraw()


func _refresh_row_labels() -> void:
	var z := int(_row.value)
	_row_label.text = "Row z%d" % z
	var map := editor.library.region_map()
	if map == null:
		_band_label.text = ""
		return
	var here: Array[String] = []
	for family in ["head", "chest", "pelvis", "upper_arm", "forearm", "thigh", "shin"]:
		var band := map.band_at(family, z)
		if band == null:
			continue
		var label := band.name if band.name == family else "%s %s" % [family, band.name]
		here.append("%s (z%d-%d)%s" % [label, band.z0, band.z1, " trim" if band.trim else ""])
	var text := "Bands on this row: %s" % (", ".join(here) if not here.is_empty() else "none")
	if edit is HeadEdit and z == HeadDef.NECK_ROW:
		text += ". This is the neck socket every head shares: it is locked."
	_band_label.text = text


func _refresh_pivot() -> void:
	if edit == null:
		_pivot_label.text = ""
		return
	var name := _grid.active_part
	var pivot := edit.pivot_of(name)
	var parity := "on a voxel boundary" if edit.pivot_on_boundary(name) else \
		"on a voxel centre - sideways turns leave the grid, forward swing is fine"
	_pivot_label.text = "Pivot of %s: (%s, %s, %s), %s" % [
		name, _num(pivot.x), _num(pivot.y), _num(pivot.z), parity]


static func _num(f: float) -> String:
	return str(int(roundf(f))) if is_equal_approx(f, roundf(f)) else "%.1f" % f


## Every cell some expression paints, from the shipped faces and every eye set
## in the wardrobe: a head has to carry all of them.
func eye_cells() -> Dictionary:
	var out := {}
	for name in editor.library.expression_names():
		for cell in editor.library.face(name).ink_cells().keys():
			out[cell] = true
	if editor.wardrobe != null:
		for id in editor.wardrobe.eye_set_ids():
			var eyes := editor.wardrobe.eye_set(id)
			for expression in eyes.expression_names():
				for cell2 in eyes.to_absolute(expression).keys():
					out[cell2] = true
	return out


func _findings() -> Array:
	if edit is BodyEdit:
		return (edit as BodyEdit).validate(editor.library.head(head_shape))
	if edit is HeadEdit:
		return (edit as HeadEdit).validate(eye_cells())
	return []


func _refresh_validation() -> void:
	if edit == null:
		_validation.text = "Nothing open to check."
		return
	var lines: Array[String] = []
	for entry in _findings():
		var finding: BodyEdit.Finding = entry
		# A word, not a colour: the owner is red/green colour blind.
		var mark := "ok  " if finding.ok else "FAIL"
		var colour := "#8c94a6" if finding.ok else "#e69f00"
		var text := finding.label
		if not finding.detail.is_empty():
			text += " - " + finding.detail
		lines.append("[color=%s]%s[/color]  %s" % [colour, mark, text])
	_validation.text = "\n".join(lines)


func _on_show_problems() -> void:
	if edit == null:
		return
	var marks := {}
	for entry in _findings():
		var finding: BodyEdit.Finding = entry
		if finding.ok:
			continue
		for cell in finding.cells:
			marks[cell] = true
	_grid.problem_cells = marks
	_grid.queue_redraw()
	if marks.is_empty():
		editor.set_status_hint("Nothing to mark: every check passes.")
		return
	var rows := {}
	for cell2 in marks.keys():
		rows[(cell2 as Vector3i).z] = true
	var sorted := rows.keys()
	sorted.sort()
	_set_row(int(sorted[0]))
	_grid.queue_redraw()
	editor.set_status_hint("Marked %d cell(s); jumped to row z%d." % [marks.size(), sorted[0]])
