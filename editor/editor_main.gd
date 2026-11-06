@tool
class_name CharacterEditor
extends Control

## The in-engine character editor (SPEC.md section 8), as four separate tabs:
##
##   Bodies        the six body types and the head shapes, bare, with only the
##                 basic eyes -- edited on slices
##   Face & Hair   eye sets and expressions, hair, facial hair: like clothes,
##                 but one of each per character, in their own area
##   Clothes       every clothing item with all its parameters and its special
##                 shapes, cycled through the six bodies
##   Preview       any combination of the above, as a whole character
##
## This shell owns what the tabs share and nothing else: the asset library,
## the one wardrobe file, undo, the unsaved-changes prompt, files, and the
## status line. Each tab owns its own preview and its own idea of what to show.
## Every preview goes through the same CharacterAssembler the game will use.
##
## Accessibility (the owner is red/green colour blind, dyslexic, has ADHD): no
## state is signalled by red vs green alone; worn items say "worn", checks say
## "ok" or "FAIL"; labels are short and literal; the open file and what each tab
## is showing are always on screen.

const STATE_PATH := "user://editor_state.cfg"

signal wardrobe_replaced

## Where the last file is remembered. A variable so the tests can point it
## elsewhere before the editor starts, rather than overwrite a user's state.
var state_path := STATE_PATH
## Where edited bodies and heads go. Tests point this at a scratch folder.
var edited_dir := AssetLibrary.EDITED_DIR

var library: AssetLibrary = null
var wardrobe: Wardrobe = null
var history := EditHistory.new()

var bodies: BodiesWorkspace = null
var face_hair: FaceHairWorkspace = null
var clothes: ClothesWorkspace = null
var preview: PreviewWorkspace = null
var workspaces: Array = []

var _tabs: TabContainer = null
var _title: Label = null
var _status: Label = null
var _warning: Label = null
## Messages from the last action ("Saved ..."). Kept apart from _warning, which
## the tabs' rebuilds own: sharing one label meant every rebuild wiped the
## message an action had just set.
var _hint: Label = null
var _menu_file: MenuButton = null
var _menu_edit: MenuButton = null

var _open_dialog: FileDialog = null
var _save_dialog: FileDialog = null
var _unsaved_dialog: ConfirmationDialog = null
var _message_dialog: AcceptDialog = null
var _pending_after_prompt: Callable = Callable()
## Which document the open unsaved-changes prompt is about.
var _prompt_doc := ""

enum FileMenu { NEW, OPEN, SAVE, SAVE_AS, REOPEN_LAST, QUIT }
enum EditMenu { UNDO, REDO }


func _ready() -> void:
	# The script is @tool so the panels' helpers can run in the editor, but the
	# app itself must not: opening this scene in the Godot editor would build
	# the whole UI inside the editor's viewport, read and write user state, and
	# interfere with closing Godot itself.
	if Engine.is_editor_hint():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Closing the window goes through the unsaved-changes prompt like Quit does.
	get_tree().set_auto_accept_quit(false)

	library = AssetLibrary.new()
	library.edited_dir = edited_dir
	if not library.load_all():
		push_error("asset library: %s" % ", ".join(library.errors))

	# The model is loaded BEFORE any control exists: tabs refresh themselves as
	# they are set up, and must find nothing half-built.
	var state := _load_state()
	var last_path := String(state.get("wardrobe_path", ""))
	if not last_path.is_empty() and FileAccess.file_exists(last_path):
		wardrobe = Wardrobe.load_from(last_path)
	if wardrobe == null:
		wardrobe = Wardrobe.create_default(library)
	_ensure_eye_set()
	history.reset(wardrobe.to_json())

	_build_ui()
	history.changed.connect(_refresh_edit_menu)
	_refresh_edit_menu()
	_refresh_title()
	var last_tab := String(state.get("tab", ""))
	if not last_tab.is_empty():
		show_tab(last_tab)
	_current().on_shown()


## A wardrobe always offers at least the shipped eyes as an eye set, so the
## Face & Hair tab has something to draw on. Not a change the user made, so it
## does not mark the file dirty.
func _ensure_eye_set() -> void:
	if wardrobe.eye_sets.is_empty():
		var standard := EyeSet.from_library(library)
		wardrobe.eye_sets[standard.id] = standard


# ----------------------------------------------------------------------- UI --

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	_menu_file = MenuButton.new()
	_menu_file.text = "File"
	_menu_file.switch_on_hover = true
	var file_popup := _menu_file.get_popup()
	file_popup.add_item("New wardrobe", FileMenu.NEW)
	file_popup.add_item("Open...", FileMenu.OPEN)
	file_popup.add_separator()
	file_popup.add_item("Save", FileMenu.SAVE)
	file_popup.add_item("Save as...", FileMenu.SAVE_AS)
	file_popup.add_separator()
	file_popup.add_item("Reopen last file", FileMenu.REOPEN_LAST)
	file_popup.add_separator()
	file_popup.add_item("Quit", FileMenu.QUIT)
	file_popup.id_pressed.connect(_on_file_menu)
	bar.add_child(_menu_file)
	_menu_edit = MenuButton.new()
	_menu_edit.text = "Edit"
	_menu_edit.switch_on_hover = true
	_menu_edit.get_popup().id_pressed.connect(_on_edit_menu)
	bar.add_child(_menu_edit)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	var status_row := HBoxContainer.new()
	root.add_child(status_row)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_stretch_ratio = 1.4
	_status.clip_text = true
	status_row.add_child(_status)
	_warning = Label.new()
	_warning.add_theme_color_override("font_color", Palette.UI_ORANGE)
	_warning.clip_text = true
	status_row.add_child(_warning)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Palette.UI_SKY)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.clip_text = true
	status_row.add_child(_hint)

	_build_dialogs()

	bodies = BodiesWorkspace.new()
	face_hair = FaceHairWorkspace.new()
	clothes = ClothesWorkspace.new()
	preview = PreviewWorkspace.new()
	workspaces = [bodies, face_hair, clothes, preview]
	for ws in workspaces:
		var w: Workspace = ws
		w.name = w.title()
		_tabs.add_child(w)
		w.setup(self)
	# Connected after the tabs exist, so adding them does not fire it early.
	_tabs.tab_changed.connect(func(_index: int) -> void:
		var current: Workspace = _current()
		if current != null:
			current.on_shown())


func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.use_native_dialog = true
	_open_dialog.title = "Open wardrobe"
	_open_dialog.add_filter("*.json", "Wardrobe file")
	_open_dialog.file_selected.connect(_do_open)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.use_native_dialog = true
	_save_dialog.title = "Save wardrobe as"
	_save_dialog.add_filter("*.json", "Wardrobe file")
	_save_dialog.file_selected.connect(_do_save_as)
	# A cancelled save must drop whatever was waiting on it, or a later save
	# would carry it out -- quitting, say, long after the user changed their mind.
	_save_dialog.canceled.connect(cancel_pending)
	add_child(_save_dialog)

	# Save / Discard / Cancel, spelled out rather than Yes/No.
	_unsaved_dialog = ConfirmationDialog.new()
	_unsaved_dialog.title = "Unsaved changes"
	_unsaved_dialog.ok_button_text = "Save first"
	_unsaved_dialog.cancel_button_text = "Cancel"
	var discard := _unsaved_dialog.add_button("Discard changes", true, "discard")
	discard.pressed.connect(_on_discard_changes)
	_unsaved_dialog.confirmed.connect(_on_save_then_continue)
	_unsaved_dialog.canceled.connect(cancel_pending)
	add_child(_unsaved_dialog)

	_message_dialog = AcceptDialog.new()
	_message_dialog.title = "Voxel Character Maker"
	add_child(_message_dialog)


func _current() -> Workspace:
	if _tabs == null or _tabs.current_tab < 0:
		return null
	return _tabs.get_child(_tabs.current_tab) as Workspace


## Bring a tab to the front by its title.
func show_tab(title: String) -> void:
	if _tabs == null:
		return
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == title:
			_tabs.current_tab = i
			return


func current_tab_title() -> String:
	var ws := _current()
	return ws.title() if ws != null else ""


# -------------------------------------------------------------- documents --

## Panels call this after changing the wardrobe: undo entry, dirty flag, and a
## refreshed preview in the tab that made the change. The other tabs catch up
## when they are next shown.
func commit(label: String, from: Workspace = null) -> void:
	if wardrobe == null:
		return
	wardrobe.mark_dirty()
	history.commit(label, wardrobe.to_json())
	note_edit(DOC_WARDROBE)
	mark_others_stale(from)
	if from != null:
		from.rebuild()
	_refresh_title()


func mark_others_stale(except: Workspace) -> void:
	for ws in workspaces:
		if ws != except:
			(ws as Workspace).mark_stale()


## A tab reports what its preview is showing.
func show_status(from: Workspace, assembled: CharacterAssembler.Assembled) -> void:
	if from != _current() or _status == null:
		return
	_status.text = from.status_text(assembled)
	_warning.text = "" if assembled.warnings.is_empty() \
		else "warning: %s" % assembled.warnings[0]
	_refresh_title()


func set_status_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text


func status_hint() -> String:
	return _hint.text if _hint != null else ""


func _refresh_title() -> void:
	if _title == null:
		return
	_title.text = "%s%s" % [
		wardrobe.display_path() if wardrobe != null else "(no wardrobe)",
		" - edited" if wardrobe != null and wardrobe.dirty else ""]


# ------------------------------------------------------------------- undo ----
#
# Two documents can be edited at once -- the wardrobe (clothes, features, eye
# sets), and a body or head open in the Bodies tab -- each with its own
# snapshot history. The timeline records which document each edit belonged to,
# in order, so Ctrl+Z always reverses the most recent edit whichever document
# it was in, and the Edit menu names exactly what that will be.

const DOC_WARDROBE := "wardrobe"
const DOC_BODY := "body"

var _timeline: Array[String] = []
var _timeline_at := -1  ## index of the most recent edit still applied


func note_edit(doc: String) -> void:
	while _timeline.size() > _timeline_at + 1:
		_timeline.remove_at(_timeline.size() - 1)
	_timeline.append(doc)
	_timeline_at = _timeline.size() - 1
	_refresh_edit_menu()


## Drop every timeline entry for `doc`, because its history was replaced.
func forget_edits(doc: String) -> void:
	var kept: Array[String] = []
	var new_at := -1
	for i in _timeline.size():
		if _timeline[i] == doc:
			continue
		kept.append(_timeline[i])
		if i <= _timeline_at:
			new_at = kept.size() - 1
	_timeline = kept
	_timeline_at = new_at
	_refresh_edit_menu()


func _history_for(doc: String) -> EditHistory:
	if doc == DOC_BODY:
		return bodies.history if bodies != null else null
	return history


func next_undo_doc() -> String:
	return _timeline[_timeline_at] if _timeline_at >= 0 else ""


func next_redo_doc() -> String:
	return _timeline[_timeline_at + 1] if _timeline_at + 1 < _timeline.size() else ""


func _menu_label(verb: String, doc: String, undoing: bool) -> String:
	if doc.is_empty():
		return verb
	var h := _history_for(doc)
	var what := ""
	if h != null:
		what = h.undo_label() if undoing else h.redo_label()
	var prefix := ""
	if doc == DOC_BODY and bodies != null and not bodies.edit_kind().is_empty():
		prefix = "%s: " % bodies.edit_kind()
	return "%s %s%s" % [verb, prefix, what]


func _refresh_edit_menu() -> void:
	if _menu_edit == null:
		return
	var popup := _menu_edit.get_popup()
	popup.clear()
	var undo_doc := next_undo_doc()
	var redo_doc := next_redo_doc()
	popup.add_item(_menu_label("Undo", undo_doc, true), EditMenu.UNDO)
	popup.set_item_disabled(0, undo_doc.is_empty())
	popup.add_item(_menu_label("Redo", redo_doc, false), EditMenu.REDO)
	popup.set_item_disabled(1, redo_doc.is_empty())


func _on_edit_menu(id: int) -> void:
	if id == EditMenu.REDO:
		redo()
	else:
		undo()


func undo() -> bool:
	while _timeline_at >= 0:
		var doc := _timeline[_timeline_at]
		var h := _history_for(doc)
		if h == null or not h.can_undo():
			# Older than that document's history reaches (it caps its length).
			_timeline.remove_at(_timeline_at)
			_timeline_at -= 1
			continue
		_timeline_at -= 1
		_apply_snapshot(doc, h.undo())
		_refresh_edit_menu()
		return true
	_refresh_edit_menu()
	return false


func redo() -> bool:
	var doc := next_redo_doc()
	if doc.is_empty():
		return false
	var h := _history_for(doc)
	if h == null or not h.can_redo():
		return false
	_timeline_at += 1
	_apply_snapshot(doc, h.redo())
	_refresh_edit_menu()
	return true


func _apply_snapshot(doc: String, snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	if doc == DOC_BODY:
		if bodies != null:
			bodies.restore_snapshot(snapshot)
		return
	var restored := Wardrobe.from_json(snapshot)
	if restored == null:
		return
	restored.path = wardrobe.path
	restored.dirty = true
	wardrobe = restored
	_announce_wardrobe()


## Everything that shows the wardrobe has to look again.
func _announce_wardrobe() -> void:
	wardrobe_replaced.emit()
	var ws := _current()
	if ws != null:
		ws.on_shown()
	_refresh_title()


# -------------------------------------------------------------------- files --

func _on_file_menu(id: int) -> void:
	match id:
		FileMenu.NEW:
			var start_new := func() -> void:
				_replace_wardrobe(Wardrobe.create_default(library), "New wardrobe")
			guard_unsaved(start_new, false, true)
		FileMenu.OPEN:
			var show_open := func() -> void: _open_dialog.popup_centered_ratio(0.6)
			guard_unsaved(show_open, false, true)
		FileMenu.SAVE:
			_save_current()
		FileMenu.SAVE_AS:
			_save_dialog.current_file = wardrobe.path.get_file() if not wardrobe.path.is_empty() \
				else "wardrobe.%s" % Wardrobe.DEFAULT_EXTENSION
			_save_dialog.popup_centered_ratio(0.6)
		FileMenu.REOPEN_LAST:
			var last := String(_load_state().get("wardrobe_path", ""))
			if last.is_empty():
				_message("No previous file to reopen.")
				return
			var reopen := func() -> void: _do_open(last)
			guard_unsaved(reopen, false, true)
		FileMenu.QUIT:
			_quit_when_safe()


## Quit, after asking about anything unsaved in either document. File > Quit
## and the window's close button both come here.
func _quit_when_safe() -> void:
	var quit_now := func() -> void:
		_save_state()
		get_tree().quit()
	guard_unsaved(quit_now, true, true)


func _replace_wardrobe(new_wardrobe: Wardrobe, label: String) -> void:
	wardrobe = new_wardrobe
	_ensure_eye_set()
	history.reset(wardrobe.to_json(), label)
	forget_edits(DOC_WARDROBE)
	_announce_wardrobe()


func _save_current() -> void:
	if wardrobe == null:
		return
	if wardrobe.path.is_empty():
		_on_file_menu(FileMenu.SAVE_AS)
		return
	var err := wardrobe.save_to()
	if err.is_empty():
		_after_wardrobe_saved()
	else:
		cancel_pending()
		_message("Could not save: %s" % err)


func _do_save_as(path: String) -> void:
	var target := path
	if not target.ends_with(".json"):
		target += ".json"
	var err := wardrobe.save_to(target)
	if err.is_empty():
		_after_wardrobe_saved()
	else:
		cancel_pending()
		_message("Could not save: %s" % err)


func _after_wardrobe_saved() -> void:
	_save_state()
	_refresh_title()
	set_status_hint("Saved %s" % wardrobe.display_path())
	# If this save was the "Save first" answer to a prompt, carry on with what
	# the prompt was guarding. A file dialog answers later than the prompt
	# does, so this is the only place that can.
	resume_pending()


func _do_open(path: String) -> void:
	var loaded := Wardrobe.load_from(path)
	if loaded == null:
		_message("Could not open %s.\n%s" % [path.get_file(), JsonIO.last_error()])
		return
	loaded.path = path
	_replace_wardrobe(loaded, "Opened %s" % path.get_file())
	_save_state()
	set_status_hint("Opened %s" % wardrobe.display_path())


# ----------------------------------------------------------- unsaved guard --

## Run `action` once it is safe to lose what it would discard.
##
## check_body      ask about an unsaved body or head in the Bodies tab
## check_wardrobe  ask about unsaved changes to the wardrobe
##
## The body or head is asked about first; once saved or discarded the wardrobe
## gets its turn, and only then does the action run. Every way out of a prompt
## either resumes the action or drops it.
func guard_unsaved(action: Callable, check_body: bool, check_wardrobe: bool) -> void:
	if check_body and bodies != null and bodies.has_unsaved():
		_pending_after_prompt = func() -> void:
			guard_unsaved(action, false, check_wardrobe)
		_prompt(DOC_BODY, "The %s you are editing has unsaved changes."
			% bodies.edit_display_name())
		return
	if check_wardrobe and wardrobe != null and wardrobe.dirty:
		_pending_after_prompt = action
		_prompt(DOC_WARDROBE, "%s has unsaved changes." % wardrobe.display_path())
		return
	action.call()


func _prompt(doc: String, text: String) -> void:
	_prompt_doc = doc
	_unsaved_dialog.dialog_text = text
	_unsaved_dialog.popup_centered()


func _on_save_then_continue() -> void:
	if _prompt_doc == DOC_BODY and bodies != null:
		bodies.save_for_prompt()
	else:
		_save_current()


func _on_discard_changes() -> void:
	# Take the action before hiding: the dialog's own signals must not get a
	# chance to drop it first.
	var action := _pending_after_prompt
	var doc := _prompt_doc
	_pending_after_prompt = Callable()
	_prompt_doc = ""
	_unsaved_dialog.hide()
	if doc == DOC_BODY and bodies != null:
		bodies.discard_unsaved()
	if action.is_valid():
		action.call()


## Carry on with whatever a prompt was guarding. Harmless when nothing is.
func resume_pending() -> void:
	var action := _pending_after_prompt
	_pending_after_prompt = Callable()
	_prompt_doc = ""
	if action.is_valid():
		action.call()


func cancel_pending() -> void:
	_pending_after_prompt = Callable()
	_prompt_doc = ""


func _message(text: String) -> void:
	_message_dialog.dialog_text = text
	_message_dialog.popup_centered()


# -------------------------------------------------------------------- input --

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed or key.meta_pressed:
		match key.keycode:
			KEY_S:
				_on_file_menu(FileMenu.SAVE_AS if key.shift_pressed else FileMenu.SAVE)
				accept_event()
			KEY_O:
				_on_file_menu(FileMenu.OPEN)
				accept_event()
			KEY_N:
				_on_file_menu(FileMenu.NEW)
				accept_event()
			KEY_Z:
				if key.shift_pressed:
					redo()
				else:
					undo()
				accept_event()
			KEY_Y:
				redo()
				accept_event()
		return
	# Number keys pick the camera views of whichever tab is showing.
	var ws := _current()
	if ws != null and ws.view.handle_key(event):
		accept_event()


# -------------------------------------------------------------------- state --

func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("editor", "wardrobe_path", wardrobe.path if wardrobe != null else "")
	cfg.set_value("editor", "tab", current_tab_title())
	cfg.save(state_path)


func _load_state() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(state_path) != OK:
		return {}
	var out := {}
	for key in cfg.get_section_keys("editor"):
		out[key] = cfg.get_value("editor", key)
	return out


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Same path as File > Quit: ask first, quit only when it is safe.
		_quit_when_safe()
