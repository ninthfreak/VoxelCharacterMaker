@tool
class_name TestEditor
extends RefCounted

## The editor shell, driven for real: the editor scene is instantiated and its
## own methods called, so these check the behaviour a user gets rather than a
## model of it.
##
## Each group pins down a bug the code review found:
##   undo timeline   the Edit menu described one edit while Ctrl+Z undid
##                   another, and wardrobe edits made during body editing
##                   could not be undone
##   unsaved guard   closing the window, or quitting with an edited body,
##                   lost work without asking; "Save first" on a never-saved
##                   file dropped the action; a cancelled prompt left it
##                   waiting to fire on some later save
##   solo            deleting the solo item hid every other worn item
##   hint            "Saved" was wiped by the rebuild that followed it
##   body picker     changing body in the Figure tab while editing did nothing
##
## The editor's remembered state is pointed at a scratch file first, so a test
## run never overwrites the state of whoever runs it.

const STATE_PATH := "user://test_editor_state.cfg"
const SAVE_PATH := "user://test_editor_wardrobe.json"


## Create the editor. Its _ready runs when it enters the tree, which the
## runner does on a later frame -- the tree is not running during _initialize.
static func make() -> Control:
	var packed: PackedScene = load("res://editor/editor_main.tscn")
	var editor: Control = packed.instantiate()
	editor.set("state_path", STATE_PATH)
	return editor


static func cleanup() -> void:
	for path in [STATE_PATH, SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func run(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: starts up")
	t.check(ed.rig != null and ed.rig.assembled != null, "the preview has a figure")
	t.check(ed.body_panel != null and ed.figure_panel != null, "every panel exists")
	t.check(not ed.get_tree().auto_accept_quit,
		"closing the window is routed through the editor, not accepted outright")

	_undo_timeline(t, ed)
	_unsaved_guard(t, ed)
	_solo(t, ed)
	_hint(t, ed)
	_body_picker(t, ed)


static func _fresh(ed: CharacterEditor) -> void:
	if ed.body_panel.is_editing():
		ed.body_panel.discard_unsaved()
		ed.body_panel._stop_now()
	ed.cancel_pending()
	ed._replace_wardrobe(Wardrobe.create_default(), "Test start")


# --------------------------------------------------------------- undo ------

static func _undo_timeline(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: one undo timeline across wardrobe and body")
	_fresh(ed)
	t.check_equal(ed.next_undo_doc(), "", "nothing to undo on a fresh wardrobe")

	var tunic := ed.wardrobe.item("tunic")
	var original_order := tunic.draw_order

	# A: a wardrobe edit
	ed.wardrobe.item("tunic").draw_order = 31
	ed.commit("Set draw order A")

	# B: a brush stroke on an open body
	ed.body_panel.start_editing_preview_body()
	t.check(ed.body_panel.is_editing(), "a body is open")
	var cell := Vector3i(5, 3, 30)
	var voxels_before := ed.body_panel.edit.total_voxels()
	ed.body_panel.edit.paint(cell, "chest")
	ed.body_panel._on_painted([cell], "chest")
	t.check(ed.body_panel.edit.total_voxels() > voxels_before, "the stroke added voxels")

	# C: another wardrobe edit, made while the body is still open
	ed.wardrobe.item("tunic").draw_order = 32
	ed.commit("Set draw order C")

	t.check_equal(ed.next_undo_doc(), CharacterEditor.DOC_WARDROBE,
		"the most recent edit was to the wardrobe, even with a body open")
	t.check(_menu_text(ed, 0).contains("Set draw order C"),
		"the Edit menu names that edit", _menu_text(ed, 0))

	ed.undo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, 31, "undo reverses C")
	t.check_equal(ed.next_undo_doc(), CharacterEditor.DOC_BODY, "next in line is the stroke")
	t.check(_menu_text(ed, 0).begins_with("Undo body:"),
		"and the menu says so", _menu_text(ed, 0))

	ed.undo()
	t.check_equal(ed.body_panel.edit.owner_at(cell), "", "undo reverses the stroke B")
	t.check_equal(ed.wardrobe.item("tunic").draw_order, 31,
		"without touching the wardrobe")

	ed.undo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, original_order, "undo reverses A")
	t.check(not ed.undo(), "and then there is nothing left")
	t.check(_menu_disabled(ed, 0), "so Undo is greyed out")

	ed.redo()
	ed.redo()
	t.check_equal(ed.body_panel.edit.owner_at(cell), "chest",
		"redo replays the stroke in its place in the sequence")
	ed.redo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, 32, "and C after it")
	t.check(_menu_disabled(ed, 1), "with nothing left to redo")

	# Closing the body takes its edits off the timeline, but not the wardrobe's.
	ed.body_panel.discard_unsaved()
	ed.body_panel._stop_now()
	var undo_docs: Array[String] = []
	while ed.next_undo_doc() != "":
		undo_docs.append(ed.next_undo_doc())
		ed.undo()
	t.check(not (CharacterEditor.DOC_BODY in undo_docs),
		"a closed body leaves nothing behind to undo", ", ".join(undo_docs))
	t.check_equal(undo_docs.size(), 2, "the two wardrobe edits are still undoable")


static func _menu_text(ed: CharacterEditor, index: int) -> String:
	var popup := ed._menu_edit.get_popup()
	return popup.get_item_text(index) if index < popup.item_count else ""


static func _menu_disabled(ed: CharacterEditor, index: int) -> bool:
	var popup := ed._menu_edit.get_popup()
	return index >= popup.item_count or popup.is_item_disabled(index)


# ------------------------------------------------------- unsaved guard -----

static func _unsaved_guard(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: nothing unsaved is lost without asking")
	_fresh(ed)
	var ran := [0]
	var action := func() -> void: ran[0] += 1

	# Clean: the action just runs.
	ed.guard_unsaved(action, true, true)
	t.check_equal(ran[0], 1, "with nothing unsaved the action runs at once")

	# A dirty wardrobe holds the action until it is answered.
	ed.wardrobe.item("tunic").draw_order = 40
	ed.commit("Make it dirty")
	ed.guard_unsaved(action, true, true)
	t.check_equal(ran[0], 1, "a dirty wardrobe stops the action")
	t.check(ed._unsaved_dialog.visible, "and asks")
	ed._on_discard_changes()
	t.check_equal(ran[0], 2, "Discard lets it run")

	# Cancel drops it for good: a later save must not set it off.
	ed.guard_unsaved(action, true, true)
	ed.cancel_pending()
	ed.resume_pending()
	t.check_equal(ran[0], 2, "a cancelled prompt's action never fires later")

	# "Save first" with a file to save to: saves, then carries on.
	ed.wardrobe.path = SAVE_PATH
	ed.guard_unsaved(action, true, true)
	ed._unsaved_dialog.hide()
	ed._on_save_then_continue()
	t.check(not ed.wardrobe.dirty, "Save first saved the wardrobe")
	t.check_equal(ran[0], 3, "and then ran the action")

	# An edited body is asked about too, before the wardrobe.
	ed.wardrobe.item("tunic").draw_order = 41
	ed.commit("Dirty again")
	ed.body_panel.start_editing_preview_body()
	var cell := Vector3i(4, 4, 31)
	ed.body_panel.edit.paint(cell, "chest")
	ed.body_panel._on_painted([cell], "chest")
	t.check(ed.body_panel.has_unsaved(), "the body has unsaved edits")

	ed.guard_unsaved(action, true, true)
	t.check_equal(ed._prompt_doc, CharacterEditor.DOC_BODY, "the body is asked about first")
	ed._on_discard_changes()
	t.check_equal(ran[0], 3, "discarding the body does not yet run the action")
	t.check_equal(ed._prompt_doc, CharacterEditor.DOC_WARDROBE, "the wardrobe is asked next")
	ed._on_discard_changes()
	t.check_equal(ran[0], 4, "and only then does the action run")

	# Stopping an edited body asks rather than quietly letting it go.
	ed.body_panel.start_editing_preview_body()
	ed.body_panel.edit.paint(cell, "chest")
	ed.body_panel._on_painted([cell], "chest")
	ed.body_panel._on_stop()
	t.check(ed.body_panel.is_editing(), "Stop editing with unsaved edits asks first")
	ed._on_discard_changes()
	t.check(not ed.body_panel.is_editing(), "and stops once the edits are discarded")

	# The window's close button goes through the same guard as File > Quit.
	ed.wardrobe.item("tunic").draw_order = 42
	ed.commit("Dirty before closing")
	ed._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	t.check(ed._unsaved_dialog.visible,
		"closing the window with unsaved changes asks instead of quitting")
	ed._unsaved_dialog.hide()
	ed.cancel_pending()


# ------------------------------------------------------------- solo --------

static func _solo(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: solo follows the item")
	_fresh(ed)
	ed.set_worn("boots", true)
	ed.set_solo("boots")
	t.check_equal(ed.solo_item, "boots", "boots are shown alone")
	ed.wardrobe.remove_item("boots")
	ed.commit("Delete boots")
	t.check_equal(ed.solo_item, "", "deleting the solo item ends solo mode")
	var owners := {}
	for name in ed.rig.assembled.order:
		var part := ed.rig.assembled.part(String(name))
		for cell in part.cells.keys():
			var owner := String(part.owners.get(cell, ""))
			if not owner.is_empty():
				owners[owner] = true
	t.check(owners.has("tunic"), "and the rest of the outfit is visible again",
		", ".join(owners.keys()))


# ------------------------------------------------------------- hint --------

static func _hint(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: messages survive the rebuild after them")
	_fresh(ed)
	ed.wardrobe.path = SAVE_PATH
	ed.wardrobe.item("tunic").draw_order = 43
	ed.commit("Dirty")
	ed._save_current()
	t.check(ed.status_hint().begins_with("Saved"),
		"the Saved message is still there after saving", ed.status_hint())
	ed.set_status_hint("Picked something")
	ed.rebuild()
	t.check_equal(ed.status_hint(), "Picked something", "a rebuild leaves the message alone")


# ------------------------------------------------------- body picker -------

static func _body_picker(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: the body picker says when it cannot apply")
	_fresh(ed)
	var picker: OptionButton = ed.figure_panel._body
	t.check(not picker.disabled, "the body picker works with no body open")
	ed.body_panel.start_editing_preview_body()
	t.check(picker.disabled, "it is disabled while the Body tab has a body open")
	t.check(ed.figure_panel._body_note.visible, "with a note saying why")
	ed.body_panel._stop_now()
	t.check(not picker.disabled, "and works again once editing stops")
	t.check(not ed.figure_panel._body_note.visible, "with the note gone")
