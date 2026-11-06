@tool
class_name BodyPanel
extends EditorPanel

## Body editing (SPEC.md section 8, step 8 of the build order).
##
## What the spec asks for, and where each piece is:
##
##   parts as layers        the part list; the active part paints, the others
##                          are dimmed but still visible
##   one owner per cell     BodyEdit, not here -- a cell painted into a part
##                          leaves whatever part held it
##   mandatory mirror pairs BodyEdit again; there is no way to make an
##                          asymmetric body through this panel at all
##   row-band guides        the row slider is labelled with its band, and the
##                          band's extent is shown, so you always know whether
##                          you are on a trim row
##   pivot markers          the measured pivot of the active part, and whether
##                          it lands on a voxel boundary (the parity rule)
##   pose preview           the Figure tab's pose applies to the edited body
##                          live, which is the real test of part splits
##
## Validation runs after every stroke against the same VoxelTopology the
## acceptance tests use, so "valid here" and "valid in the suite" cannot drift.

const UNSAVED := "(unsaved body)"

var edit: BodyEdit = null
var history := EditHistory.new()

var _grid: SliceGrid = null
var _row: HSlider = null
var _row_label: Label = null
var _band_label: Label = null
var _parts: ItemList = null
var _pivot_label: Label = null
var _validation: RichTextLabel = null
var _counts: Label = null
var _file_label: Label = null
var _hover_label: Label = null
var _neighbours: CheckBox = null

var _part_names: Array[String] = []
var _open_dialog: FileDialog = null
var _save_dialog: FileDialog = null
var _dirty := false
## Where this body was last saved by the user, as opposed to the library file
## it came from. Only a path chosen here is safe to save over without asking:
## the library file is what build_bodies.py regenerates.
var _saved_path := ""


func _build() -> void:
	var top := section("Body")
	_file_label = Label.new()
	_file_label.text = UNSAVED
	top.add_child(_file_label)
	hint(top, "Edits are mirrored automatically and a cell can belong to only "
		+ "one part, so the two halves always match.")

	button_row(top, [
		{"text": "Edit this body", "action": _on_edit_current},
		{"text": "Open...", "action": _on_open},
		{"text": "Save as...", "action": _on_save_as},
		{"text": "Stop editing", "action": _on_stop},
	])
	_warn_about_regeneration(top)

	# -- the slice -----------------------------------------------------------
	var slice := section("Row")
	var row_line := HBoxContainer.new()
	slice.add_child(row_line)
	_row_label = Label.new()
	_row_label.custom_minimum_size = Vector2(92, 0)
	row_line.add_child(_row_label)
	_row = HSlider.new()
	_row.min_value = 0
	_row.max_value = VoxelAxes.GRID.z - 1
	_row.step = 1
	_row.value = 22
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.value_changed.connect(func(v: float) -> void:
		if is_guarded():
			return
		_grid.z = int(v)
		_grid.queue_redraw()
		_refresh_row_labels())
	row_line.add_child(_row)

	_band_label = Label.new()
	_band_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slice.add_child(_band_label)

	_grid = SliceGrid.new()
	_grid.painted.connect(_on_painted)
	_grid.erased.connect(_on_erased)
	_grid.hovered.connect(_on_hovered)
	add_child(_grid)

	_hover_label = Label.new()
	_hover_label.add_theme_color_override("font_color", Color8(150, 158, 174))
	add_child(_hover_label)

	_neighbours = CheckBox.new()
	_neighbours.text = "Show the rows above and below"
	_neighbours.button_pressed = true
	_neighbours.toggled.connect(func(on: bool) -> void:
		_grid.show_neighbour_rows = on
		_grid.queue_redraw())
	add_child(_neighbours)

	# -- parts as layers -----------------------------------------------------
	var layers := section("Parts")
	_parts = make_list(layers, 150)
	_parts.item_selected.connect(func(index: int) -> void:
		if is_guarded() or index < 0 or index >= _part_names.size():
			return
		_grid.active_part = _part_names[index]
		_grid.queue_redraw()
		_refresh_pivot())
	hint(layers, "The selected part is what you paint with. Left button paints, "
		+ "right button erases.")

	_pivot_label = Label.new()
	_pivot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layers.add_child(_pivot_label)

	# -- validation ----------------------------------------------------------
	var checks := section("Checks")
	_validation = RichTextLabel.new()
	_validation.bbcode_enabled = true
	_validation.fit_content = true
	_validation.custom_minimum_size = Vector2(0, 150)
	checks.add_child(_validation)
	_counts = Label.new()
	checks.add_child(_counts)
	button_row(checks, [
		{"text": "Show problem cells", "action": _on_show_problems},
		{"text": "Clear marks", "action": _on_clear_problems},
	])

	_build_dialogs()


## The editor writes body files in the same schema build_bodies.py generates,
## and that script rewrites every file in assets/. Worth saying plainly rather
## than letting someone lose an afternoon's drawing to a regeneration.
func _warn_about_regeneration(parent: Container) -> void:
	var warning := Label.new()
	warning.text = "Note: running tools/build_bodies.py rewrites every file in " \
		+ "assets/. Save edited bodies under another name, or treat the saved " \
		+ "file as the new source and retire that script."
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_color_override("font_color", Palette.UI_ORANGE)
	parent.add_child(warning)


func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.use_native_dialog = true
	_open_dialog.title = "Open a body file"
	_open_dialog.add_filter("*.json", "Body file")
	_open_dialog.file_selected.connect(_do_open)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.use_native_dialog = true
	_save_dialog.title = "Save the body as"
	_save_dialog.add_filter("*.json", "Body file")
	_save_dialog.file_selected.connect(_do_save)
	# If this save was answering an unsaved-changes prompt and gets cancelled,
	# whatever the prompt was guarding must not run later on its own.
	_save_dialog.canceled.connect(func() -> void: editor.cancel_pending())
	add_child(_save_dialog)


# ------------------------------------------------------------------- state --

func is_editing() -> bool:
	return edit != null


## Unsaved edits that would be lost by closing this body.
func has_unsaved() -> bool:
	return is_editing() and _dirty


func edit_display_name() -> String:
	return edit.display_name() if edit != null else ""


## Restore a snapshot from the editor's undo timeline.
func restore_snapshot(snapshot: Dictionary) -> void:
	if edit == null:
		return
	edit.restore(snapshot)
	_dirty = true
	_push_preview()
	refresh()


## "Save first" from an unsaved-changes prompt. A body saved here before goes
## straight back to that file; one that has only ever been the library's copy
## goes through Save As, because overwriting the generated file should be a
## deliberate choice rather than a side effect of quitting.
func save_for_prompt() -> void:
	if not _saved_path.is_empty():
		_do_save(_saved_path)
	else:
		_on_save_as()


## "Discard changes" from a prompt: the edits are let go. Whatever the prompt
## was guarding (stop, open another, quit) does the rest.
func discard_unsaved() -> void:
	_dirty = false


## Jump the slice to a given row, for a screenshot or a future shortcut.
func set_row(z: int) -> void:
	begin_guard()
	_row.value = clampi(z, 0, VoxelAxes.GRID.z - 1)
	end_guard()
	_grid.z = int(_row.value)
	_refresh_row_labels()
	_grid.queue_redraw()


## Start editing whatever body the preview is showing. Public so a screenshot
## or a future shortcut can open the editor the same way the button does.
func start_editing_preview_body() -> void:
	_on_edit_current()


func _on_edit_current() -> void:
	var body := editor.library.body(editor.body_id)
	if body == null:
		editor.set_status_hint("No body to edit.")
		return
	var start := func() -> void:
		_begin(BodyEdit.from_body(body), "Edit %s" % body.display_name())
	editor.guard_unsaved(start, true, false)


func _begin(new_edit: BodyEdit, label: String) -> void:
	edit = new_edit
	history.reset(edit.snapshot(), label)
	editor.forget_edits(CharacterEditor.DOC_BODY)
	_dirty = false
	_saved_path = ""
	if _part_names.is_empty():
		_grid.active_part = BodyEdit.PAINTABLE[0]
	_grid.body = edit
	_push_preview()
	refresh()
	editor.body_editing_changed.emit()
	editor.set_status_hint("Editing %s. The preview follows what you draw."
		% edit.display_name())


func _on_stop() -> void:
	if edit == null:
		return
	# The same Save / Discard / Cancel prompt as quitting, rather than a
	# press-twice rule that quietly forgot the edits were unsaved.
	editor.guard_unsaved(_stop_now, true, false)


func _stop_now() -> void:
	edit = null
	_dirty = false
	_saved_path = ""
	_grid.body = null
	history.reset({}, "No body open")
	editor.forget_edits(CharacterEditor.DOC_BODY)
	editor.body_override = null
	editor.rebuild()
	refresh()
	editor.body_editing_changed.emit()


## Hand the edited body to the preview, so the pose preview and every garment
## regenerate against what is being drawn.
func _push_preview() -> void:
	if editor == null:
		return
	editor.body_override = edit.to_body_def() if edit != null else null
	editor.rebuild()


# ------------------------------------------------------------------ editing --

func _on_painted(cells: Array, part_name: String) -> void:
	_after_stroke("Paint %d cell%s as %s" % [
		cells.size(), "" if cells.size() == 1 else "s", part_name])


func _on_erased(cells: Array) -> void:
	_after_stroke("Erase %d cell%s" % [cells.size(), "" if cells.size() == 1 else "s"])


func _after_stroke(label: String) -> void:
	_dirty = true
	history.commit(label, edit.snapshot())
	editor.note_edit(CharacterEditor.DOC_BODY)
	_push_preview()
	refresh()


func _on_hovered(cell: Vector3i, owner_part: String) -> void:
	var where := "x%d y%d z%d" % [cell.x, cell.y, cell.z]
	var side := "character's left" if VoxelAxes.is_left(cell) else "character's right"
	var depth := "front" if VoxelAxes.is_front(cell) else "back"
	var who := owner_part if not owner_part.is_empty() else "empty"
	_hover_label.text = "%s  -  %s, %s  -  %s" % [where, side, depth, who]


# ---------------------------------------------------------------- refresh ---

func refresh() -> void:
	if _grid == null:
		return
	begin_guard()

	var editing := is_editing()
	_file_label.text = UNSAVED if not editing else "%s%s" % [
		edit.source_path.get_file() if not edit.source_path.is_empty()
			else "%s (from the library)" % edit.display_name(),
		" - edited" if _dirty else ""]

	_part_names.clear()
	_parts.clear()
	if editing:
		for name in BodyEdit.PAINTABLE:
			_part_names.append(name)
			var count := edit.part_cells(name).size()
			var index := _parts.add_item("%s   %d voxels" % [name, count])
			_parts.set_item_custom_fg_color(index, _grid.colour_for(name))
			if name == _grid.active_part:
				_parts.select(index)
		_grid.body = edit
		_grid.z = int(_row.value)

	end_guard()
	_refresh_row_labels()
	_refresh_pivot()
	_refresh_validation()
	_grid.queue_redraw()


func _refresh_row_labels() -> void:
	var z := int(_row.value)
	_row_label.text = "Row z%d" % z
	var map := editor.library.region_map() if editor != null else null
	if map == null:
		_band_label.text = ""
		return
	var parts_here: Array[String] = []
	for family in ["head", "chest", "pelvis", "upper_arm", "forearm", "thigh", "shin"]:
		var band := map.band_at(family, z)
		if band == null:
			continue
		# The band often carries its family's name ("upper_arm upper_arm"), so
		# only say it twice when the two actually differ.
		var label := band.name if band.name == family else "%s %s" % [family, band.name]
		parts_here.append("%s (z%d-%d)%s" % [
			label, band.z0, band.z1, " trim" if band.trim else ""])
	_band_label.text = "Bands on this row: %s" % (
		", ".join(parts_here) if not parts_here.is_empty() else "none")


func _refresh_pivot() -> void:
	if not is_editing():
		_pivot_label.text = ""
		return
	var name := _grid.active_part
	var pivot := edit.pivot_of(name)
	var on_boundary := edit.pivot_on_boundary(name)
	var parity := "on a voxel boundary" if on_boundary else \
		"on a voxel centre - sideways turns leave the grid, forward swing is fine"
	_pivot_label.text = "Pivot of %s: (%s, %s, %s), %s" % [
		name, _trim(pivot.x), _trim(pivot.y), _trim(pivot.z), parity]


static func _trim(f: float) -> String:
	return str(int(roundf(f))) if is_equal_approx(f, roundf(f)) else "%.1f" % f


func _refresh_validation() -> void:
	if not is_editing():
		_validation.text = "No body open. \"Edit this body\" starts from the one "
		_validation.text += "in the preview."
		_counts.text = ""
		return
	var head := editor.library.head(editor.head_shape)
	var findings := edit.validate(head)
	var lines: Array[String] = []
	for entry in findings:
		var finding: BodyEdit.Finding = entry
		# A word, not a colour: the owner is red/green colour blind.
		var mark := "ok  " if finding.ok else "FAIL"
		var colour := "#8c94a6" if finding.ok else "#e69f00"
		var text := finding.label
		if not finding.detail.is_empty():
			text += " - " + finding.detail
		lines.append("[color=%s]%s[/color]  %s" % [colour, mark, text])
	_validation.text = "\n".join(lines)
	_counts.text = "%d voxels across %d parts, checked against %s" % [
		edit.total_voxels(), BodyEdit.PAINTABLE.size(),
		"the %s head" % editor.head_shape if head != null else "no head"]


func _on_show_problems() -> void:
	if not is_editing():
		return
	var head := editor.library.head(editor.head_shape)
	var marks := {}
	for entry in edit.validate(head):
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
	# Jump to a row that actually has one, so the mark is not off-screen.
	var rows := {}
	for cell in marks.keys():
		rows[(cell as Vector3i).z] = true
	var sorted := rows.keys()
	sorted.sort()
	begin_guard()
	_row.value = sorted[0]
	_grid.z = int(sorted[0])
	end_guard()
	_refresh_row_labels()
	editor.set_status_hint("Marked %d cell(s); jumped to row z%d."
		% [marks.size(), sorted[0]])


func _on_clear_problems() -> void:
	_grid.problem_cells = {}
	_grid.queue_redraw()


# -------------------------------------------------------------------- files --

func _on_open() -> void:
	var show := func() -> void: _open_dialog.popup_centered_ratio(0.6)
	editor.guard_unsaved(show, true, false)


func _do_open(path: String) -> void:
	var loaded := BodyEdit.load_from(path)
	if loaded == null:
		editor.set_status_hint("Could not open %s as a body file." % path.get_file())
		return
	_begin(loaded, "Opened %s" % path.get_file())


func _on_save_as() -> void:
	if not is_editing():
		editor.set_status_hint("Open a body to edit first.")
		return
	_save_dialog.current_file = "body42_%s_%s_parts.json" % [edit.sex, edit.build]
	_save_dialog.popup_centered_ratio(0.6)


func _do_save(path: String) -> void:
	var target := path
	if not target.ends_with(".json"):
		target += ".json"
	var err := edit.save_to(target)
	if not err.is_empty():
		editor.cancel_pending()
		editor.set_status_hint("Could not save: %s" % err)
		return
	_dirty = false
	_saved_path = target
	refresh()
	editor.set_status_hint("Saved %s" % target.get_file())
	# If this save answered an unsaved-changes prompt, carry on with what it
	# was guarding.
	editor.resume_pending()
