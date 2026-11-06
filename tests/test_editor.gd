@tool
class_name TestEditor
extends RefCounted

## The editor, driven for real: the editor scene is instantiated and its own
## methods called, so these check what a user gets rather than a model of it.
##
## The four tabs are checked for what each one is FOR: Bodies shows a bare
## figure with only the basic eyes and edits bodies and heads; Face & Hair
## edits eyes, hair and facial hair, one of each; Clothes cycles the bodies
## and edits items with their special shapes; Preview puts anything together.
## The shell's guarantees -- one undo timeline, nothing unsaved lost without
## asking, messages that survive a rebuild -- are checked across them.
##
## The editor's remembered state and its saved body/head edits are pointed at
## scratch locations first, so a test run never touches the user's own.

const STATE_PATH := "user://test_editor_state.cfg"
const SAVE_PATH := "user://test_editor_wardrobe.json"
const EDITS_DIR := "user://test_editor_edits"


static func make() -> Control:
	var packed: PackedScene = load("res://editor/editor_main.tscn")
	var editor: Control = packed.instantiate()
	editor.set("state_path", STATE_PATH)
	editor.set("edited_dir", EDITS_DIR)
	return editor


static func cleanup() -> void:
	for path in [STATE_PATH, SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var dir := DirAccess.open(EDITS_DIR)
	if dir != null:
		for file in dir.get_files():
			DirAccess.remove_absolute("%s/%s" % [EDITS_DIR, file])
		DirAccess.remove_absolute(EDITS_DIR)


static func run(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: four separate tabs")
	var titles: Array[String] = []
	for ws in ed.workspaces:
		titles.append((ws as Workspace).title())
	t.check_equal(titles, ["Bodies", "Face & Hair", "Clothes", "Preview"] as Array[String],
		"the tabs are Bodies, Face & Hair, Clothes, Preview")
	t.check(not ed.get_tree().auto_accept_quit,
		"closing the window is routed through the editor, not accepted outright")
	for ws2 in ed.workspaces:
		var w: Workspace = ws2
		ed.show_tab(w.title())
		t.check(w.view.assembled != null and w.view.assembled.warnings.is_empty(),
			"%s shows a figure with no warnings" % w.title(),
			"" if w.view.assembled == null else ", ".join(w.view.assembled.warnings))

	_bodies(t, ed)
	_heads(t, ed)
	_face_hair(t, ed)
	_clothes(t, ed)
	_preview(t, ed)
	_undo_timeline(t, ed)
	_unsaved_guard(t, ed)
	_hint(t, ed)


static func _fresh(ed: CharacterEditor) -> void:
	if ed.bodies.is_editing():
		ed.bodies.discard_unsaved()
		ed.bodies._stop_now()
	ed.cancel_pending()
	ed._replace_wardrobe(Wardrobe.create_default(ed.library), "Test start")


static func _owners(assembled: CharacterAssembler.Assembled) -> Dictionary:
	var out := {}
	for name in assembled.order:
		var part := assembled.part(String(name))
		for cell in part.cells.keys():
			var owner := String(part.owners.get(cell, ""))
			if not owner.is_empty():
				out[owner] = true
	return out


# ------------------------------------------------------------------ bodies --

static func _bodies(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: the Bodies tab is bare, and edits go everywhere")
	_fresh(ed)
	ed.show_tab("Bodies")
	var bare := ed.bodies.view.assembled
	t.check(_owners(bare).is_empty(), "no hair, clothes or items on the body preview",
		", ".join(_owners(bare).keys()))
	var eye_cells := 0
	var head := bare.part(BodyDef.HEAD_PART)
	for cell in head.cells.keys():
		if int(head.sources.get(cell, 0)) == CharacterAssembler.Source.FACE:
			eye_cells += 1
	t.check(eye_cells > 0, "but the basic eyes are there")

	ed.bodies.body_id = "male_average"
	ed.bodies.start_editing(BodiesWorkspace.KIND_BODY)
	t.check(ed.bodies.edit is BodyEdit, "a body opens for editing")
	var before := ed.library.body("male_average").total_voxels()
	var cell := Vector3i(15, 6, 23)
	ed.bodies.edit.paint(cell, "chest")
	ed.bodies._after_stroke("Paint test")
	t.check(ed.bodies.has_unsaved(), "the stroke is unsaved")
	t.check(ed.library.body("male_average").total_voxels() > before,
		"the edit is in the library as it is drawn")

	# Another tab sees it straight away.
	ed.clothes.body_id = "male_average"
	ed.show_tab("Clothes")
	t.check(ed.clothes.view.assembled.body.part("chest").cells.has(cell),
		"the Clothes tab shows the edited body")

	# Discarding puts the library back.
	ed.show_tab("Bodies")
	ed.bodies.discard_unsaved()
	t.check_equal(ed.library.body("male_average").total_voxels(), before,
		"discarding puts the generated body back")
	ed.bodies._stop_now()

	# Saving writes to the edited folder, and reverting removes it.
	ed.bodies.start_editing(BodiesWorkspace.KIND_BODY)
	ed.bodies.edit.paint(cell, "chest")
	ed.bodies._after_stroke("Paint to save")
	ed.bodies._on_save()
	t.check(not ed.bodies.has_unsaved(), "Save clears the unsaved flag")
	t.check(ed.library.is_body_edited("male_average"),
		"and the body is now an edited version on disk")
	t.check(FileAccess.file_exists(ed.library.edited_body_path("male", "average")),
		"in the edited folder, not over the generated file")
	ed.bodies._do_revert()
	t.check(not ed.library.is_body_edited("male_average"), "Revert removes the edit")
	t.check_equal(ed.library.body("male_average").total_voxels(), before,
		"and the generated body is back")
	ed.bodies._stop_now()


static func _heads(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: heads are edited in the Bodies tab too")
	_fresh(ed)
	ed.show_tab("Bodies")
	ed.bodies.head_shape = "oval"
	ed.bodies.start_editing(BodiesWorkspace.KIND_HEAD)
	t.check(ed.bodies.edit is HeadEdit, "a head opens for editing")
	t.check_equal(ed.bodies.edit.paintable_parts(), ["head"] as Array[String],
		"with the head as its only layer")
	t.check(not ed.bodies.edit.paint(Vector3i(14, 12, HeadDef.NECK_ROW), HeadEdit.PART),
		"the neck socket cannot be painted")
	var findings := ed.bodies._findings()
	t.check(BodyEdit.all_ok(findings), "the shipped oval head passes the head checks")
	# A cell the shipped head has, so taking it away is a real change.
	var cell := Vector3i(12, 14, 40)
	t.check(ed.library.head("oval").cells.has(cell), "(the test cell is part of the head)")
	ed.bodies.edit.erase(cell)
	ed.bodies._after_stroke("Erase head")
	t.check(not ed.library.head("oval").cells.has(cell),
		"a head edit reaches the library too")
	ed.bodies.discard_unsaved()
	ed.bodies._stop_now()
	t.check(ed.library.head("oval").cells.has(cell),
		"and discarding puts the head back")


# -------------------------------------------------------------- face & hair --

static func _face_hair(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: Face & Hair -- eyes, hair, facial hair, one of each")
	_fresh(ed)
	ed.show_tab("Face & Hair")
	var fh := ed.face_hair
	t.check(not fh.eye_set_id.is_empty(), "an eye set is chosen")
	t.check(fh._eyes_panel._grid.eye_set == ed.wardrobe.eye_set(fh.eye_set_id),
		"and its open eye is on the drawing grid")

	fh.hair.select("")
	fh.facial_hair.select("")
	var bald := _owners(fh.view.assembled)
	t.check(bald.is_empty(), "with no hair chosen the head is bald",
		", ".join(bald.keys()))
	fh.hair.select("short_crop")
	fh.facial_hair.select("full_beard")
	var dressed := _owners(fh.view.assembled)
	t.check(dressed.has("short_crop") and dressed.has("full_beard"),
		"choosing hair and a beard shows both", ", ".join(dressed.keys()))

	# A head change keeps the choices.
	fh.head_shape = "heart"
	fh.rebuild()
	t.check(_owners(fh.view.assembled).has("full_beard"),
		"they stay on when the head changes")

	# Drawing the eye changes the face and is undoable.
	var eyes := ed.wardrobe.eye_set(fh.eye_set_id)
	var before := eyes.role_at(EyeSet.EYE_LEFT, 0, 0)
	eyes.set_cell(EyeSet.EYE_LEFT, 0, 0, EyeSet.ROLE_LINE, true)
	ed.commit("Draw eyes", fh)
	t.check_equal(ed.next_undo_doc(), CharacterEditor.DOC_WARDROBE,
		"drawing eyes is a wardrobe edit")
	ed.undo()
	t.check_equal(ed.wardrobe.eye_set(fh.eye_set_id).role_at(
		EyeSet.EYE_LEFT, 0, 0), before, "and undo takes it back")


# ----------------------------------------------------------------- clothes --

static func _clothes(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: Clothes -- every body, items with special shapes")
	_fresh(ed)
	ed.show_tab("Clothes")
	var cl := ed.clothes
	cl.clothes.select("dress")
	cl.show_mode = ClothesWorkspace.SHOW_ITEM
	var bodies_with_dress := 0
	for id in ed.library.body_ids():
		cl.body_id = id
		cl.rebuild()
		var a := cl.view.assembled
		var panels := 0
		for name in a.order:
			if a.part(String(name)).is_panel():
				panels += 1
		if _owners(a).has("dress") and panels > 0 and a.warnings.is_empty():
			bodies_with_dress += 1
	t.check_equal(bodies_with_dress, 6, "the dress, bodice and skirt, on all six bodies")

	t.check(_owners(cl.view.assembled).keys() == ["dress"],
		"'this item only' shows just the item", ", ".join(_owners(cl.view.assembled).keys()))
	cl.set_worn_list(ed.wardrobe.outfit("everyday"))
	t.check_equal(cl.show_mode, ClothesWorkspace.SHOW_WORN, "wearing an outfit shows the worn set")
	t.check(_owners(cl.view.assembled).has("tunic"), "with the outfit on")

	cl.hair_id = "short_crop"
	cl.rebuild()
	t.check(_owners(cl.view.assembled).has("short_crop"),
		"a hair style can be put on to check hats and hoods against")

	# Deleting the selected item clears the selection rather than dangling.
	cl.clothes.select("boots")
	ed.wardrobe.remove_item("boots")
	ed.commit("Delete boots", cl)
	cl.refresh()
	t.check_equal(cl.clothes.item_id, "", "deleting the selected item clears the selection")
	t.check(not cl.is_worn("boots"), "and it is no longer worn")


# ----------------------------------------------------------------- preview --

static func _preview(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: Preview -- any combination, as a whole character")
	_fresh(ed)
	ed.show_tab("Preview")
	var pv := ed.preview
	pv._choose("body_id", "female_heavy")
	pv._choose("head_shape", "strong")
	pv._choose("hair_id", "ponytail")
	pv._choose("facial_id", "chinstrap")
	pv._choose("accessory_id", "long_beard")
	pv._choose("lids", "angry")
	pv.worn = ed.wardrobe.outfit("travelling")
	pv.refresh()
	pv.rebuild()
	var a := pv.view.assembled
	t.check_equal(a.body.id, "female_heavy", "the chosen body")
	t.check_equal(a.head.shape, "strong", "the chosen head")
	var owners := _owners(a)
	for id in ["ponytail", "chinstrap", "long_beard", "cloak", "tunic", "trousers", "boots"]:
		t.check(owners.has(id), "%s is on the character" % id)
	t.check(a.warnings.is_empty(), "with no warnings", ", ".join(a.warnings))
	t.check(pv._summary.text.contains("Wearing:"), "and a summary of what is on")

	# Lids, skin tone and brows are chosen here and nowhere else.
	pv._choose("lids", "blink")
	pv._choose("skin_tone", "deep")
	pv.rebuild()
	var head := pv.view.assembled.part(BodyDef.HEAD_PART)
	var whites := 0
	var lid_cells := 0
	for cell in head.cells.keys():
		if int(head.sources.get(cell, 0)) == CharacterAssembler.Source.FACE:
			if head.colours[cell].is_equal_approx(Palette.EYE_WHITE):
				whites += 1
			if head.colours[cell].is_equal_approx(Palette.lid_colour("deep")):
				lid_cells += 1
	t.check(whites == 0 and lid_cells > 0, "choosing blink and a deep skin tone closes the eyes in that skin's lid colour",
		"%d white, %d lid" % [whites, lid_cells])
	t.check(pv._summary.text.contains("blink") and pv._summary.text.contains("deep"),
		"and the summary says so")


# ------------------------------------------------------------------- undo --

static func _undo_timeline(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: one undo timeline across the wardrobe and an open body")
	_fresh(ed)
	ed.show_tab("Clothes")
	var original_order := ed.wardrobe.item("tunic").draw_order

	ed.wardrobe.item("tunic").draw_order = 31
	ed.commit("Set draw order A", ed.clothes)

	ed.show_tab("Bodies")
	ed.bodies.start_editing(BodiesWorkspace.KIND_BODY)
	var cell := Vector3i(5, 3, 30)
	ed.bodies.edit.paint(cell, "chest")
	ed.bodies._after_stroke("Paint B")

	ed.wardrobe.item("tunic").draw_order = 32
	ed.commit("Set draw order C", ed.clothes)

	t.check_equal(ed.next_undo_doc(), CharacterEditor.DOC_WARDROBE,
		"the latest edit was to the wardrobe, even with a body open")
	ed.undo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, 31, "undo reverses C")
	t.check(ed._menu_edit.get_popup().get_item_text(0).begins_with("Undo body:"),
		"the menu names the body edit next", ed._menu_edit.get_popup().get_item_text(0))
	ed.undo()
	t.check_equal(ed.bodies.edit.owner_at(cell), "", "undo reverses the stroke B")
	ed.undo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, original_order, "undo reverses A")
	t.check(not ed.undo(), "and then there is nothing left")
	ed.redo()
	ed.redo()
	t.check_equal(ed.bodies.edit.owner_at(cell), "chest", "redo replays the stroke in order")
	ed.redo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, 32, "and C after it")
	ed.bodies.discard_unsaved()
	ed.bodies._stop_now()


# ---------------------------------------------------------- unsaved guard --

static func _unsaved_guard(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: nothing unsaved is lost without asking")
	_fresh(ed)
	var ran := [0]
	var action := func() -> void: ran[0] += 1

	ed.guard_unsaved(action, true, true)
	t.check_equal(ran[0], 1, "with nothing unsaved the action runs at once")

	ed.wardrobe.item("tunic").draw_order = 40
	ed.commit("Make it dirty", ed.clothes)
	ed.guard_unsaved(action, true, true)
	t.check_equal(ran[0], 1, "a dirty wardrobe stops the action")
	ed._on_discard_changes()
	t.check_equal(ran[0], 2, "Discard lets it run")

	ed.guard_unsaved(action, true, true)
	ed.cancel_pending()
	ed.resume_pending()
	t.check_equal(ran[0], 2, "a cancelled prompt's action never fires later")

	ed.wardrobe.path = SAVE_PATH
	ed.guard_unsaved(action, true, true)
	ed._unsaved_dialog.hide()
	ed._on_save_then_continue()
	t.check(not ed.wardrobe.dirty, "Save first saved the wardrobe")
	t.check_equal(ran[0], 3, "and then ran the action")

	# An edited body is asked about before the wardrobe.
	ed.wardrobe.item("tunic").draw_order = 41
	ed.commit("Dirty again", ed.clothes)
	ed.show_tab("Bodies")
	ed.bodies.start_editing(BodiesWorkspace.KIND_BODY)
	ed.bodies.edit.paint(Vector3i(4, 4, 31), "chest")
	ed.bodies._after_stroke("Paint")
	ed.guard_unsaved(action, true, true)
	t.check_equal(ed._prompt_doc, CharacterEditor.DOC_BODY, "the body is asked about first")
	ed._on_discard_changes()
	t.check_equal(ed._prompt_doc, CharacterEditor.DOC_WARDROBE, "the wardrobe next")
	ed._on_discard_changes()
	t.check_equal(ran[0], 4, "and only then does the action run")

	# Switching body with unsaved edits asks first.
	ed.bodies.edit.paint(Vector3i(4, 4, 31), "chest")
	ed.bodies._after_stroke("Paint again")
	ed.bodies._choose_body("female_slim")
	t.check_equal(ed.bodies.body_id, "male_average",
		"switching body with unsaved edits waits for an answer")
	ed._on_discard_changes()
	t.check_equal(ed.bodies.body_id, "female_slim", "and switches once they are discarded")
	ed.bodies._stop_now()

	# The window's close button goes through the same guard as File > Quit.
	ed.wardrobe.item("tunic").draw_order = 42
	ed.commit("Dirty before closing", ed.clothes)
	ed._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	t.check(ed._unsaved_dialog.visible,
		"closing the window with unsaved changes asks instead of quitting")
	ed._unsaved_dialog.hide()
	ed.cancel_pending()


static func _hint(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: messages survive the rebuild after them")
	_fresh(ed)
	ed.show_tab("Clothes")
	ed.wardrobe.path = SAVE_PATH
	ed.wardrobe.item("tunic").draw_order = 43
	ed.commit("Dirty", ed.clothes)
	ed._save_current()
	t.check(ed.status_hint().begins_with("Saved"), "the Saved message shows", ed.status_hint())
	ed.clothes.rebuild()
	t.check(ed.status_hint().begins_with("Saved"), "and is still there after a rebuild")
