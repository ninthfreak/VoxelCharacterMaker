@tool
class_name TestEditor
extends RefCounted

## The editor, driven for real: the editor scene is instantiated and its own methods called, so these check what a
## user gets rather than a model of it.
##
## The three tabs are checked for what each one is FOR: Face & Hair edits eyes, hair and facial hair, one of each;
## Clothes cycles the bodies and edits items with their special shapes; Preview puts anything together. The shell's
## guarantees -- one undo timeline, nothing unsaved lost without asking, messages that survive a rebuild -- are
## checked across them.
##
## The editor's remembered state is pointed at a scratch location first, so a test run never touches the user's own.

const STATE_PATH := "user://test_editor_state.cfg"
const SAVE_PATH := "user://test_editor_wardrobe.json"


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
	t.group("editor: three separate tabs")
	var titles: Array[String] = []
	for ws in ed.workspaces:
		titles.append((ws as Workspace).title())
	t.check_equal(titles, ["Face & Hair", "Clothes", "Preview"] as Array[String],
		"the tabs are Face & Hair, Clothes, Preview")
	t.check(not ed.get_tree().auto_accept_quit, "closing the window is routed through the editor, not accepted outright")
	for ws2 in ed.workspaces:
		var w: Workspace = ws2
		ed.show_tab(w.title())
		var f := w.view.lowpoly_rig.figure
		t.check(f != null and f.visible_polygons() > 0, "%s shows a figure" % w.title())
	t.check_equal(ed.library.body_ids().size(), 8, "eight bodies to choose from, a short one for each sex")

	_face_hair(t, ed)
	_clothes(t, ed)
	_preview(t, ed)
	_undo_timeline(t, ed)
	_unsaved_guard(t, ed)
	_hint(t, ed)


static func _fresh(ed: CharacterEditor) -> void:
	ed.cancel_pending()
	ed._replace_wardrobe(Wardrobe.create_default(), "Test start")


## Which worn items made the polygons a tab shows.
static func _owners(w: Workspace) -> Dictionary:
	var out := {}
	var f := w.view.lowpoly_rig.figure
	if f != null:
		for p in f.polygons:
			if not String(p["by"]).is_empty():
				out[String(p["by"])] = true
		for c in f.cloths:
			out[(c as LowpolyCloth).by] = true
	return out


static func _face_roles(w: Workspace) -> Dictionary:
	var roles := {}
	for p in w.view.lowpoly_rig.figure.polygons:
		if String(p["piece"]) == LowpolyAssembler.FACE_PIECE:
			roles[String(p["role"])] = int(roles.get(String(p["role"]), 0)) + 1
	return roles


# -------------------------------------------------------------- face & hair --

static func _face_hair(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: Face & Hair -- eyes, hair, facial hair, one of each")
	_fresh(ed)
	ed.show_tab("Face & Hair")
	var fh := ed.face_hair
	t.check(not fh.eye_set_id.is_empty(), "an eye set is chosen")
	t.check(fh._eyes_panel._grid.eye_set == ed.wardrobe.eye_set(fh.eye_set_id), "and its open eye is on the drawing grid")

	fh.hair.select("")
	fh.facial_hair.select("")
	t.check(_owners(fh).is_empty(), "with no hair chosen the head is bald", ", ".join(_owners(fh).keys()))
	fh.hair.select("short_crop")
	fh.facial_hair.select("full_beard")
	t.check(_owners(fh).has("short_crop") and _owners(fh).has("full_beard"), "choosing hair and a beard shows both",
		", ".join(_owners(fh).keys()))
	var roles := _face_roles(fh)
	t.check(roles.has("white") and roles.has("pupil") and roles.has("brow"), "and the eyes, pupils and brows",
		str(roles.keys()))
	t.check(fh.view.lowpoly_rig.figure.warnings.is_empty(), "with nothing the figure cannot show",
		", ".join(fh.view.lowpoly_rig.figure.warnings))

	# A head change keeps the choices.
	fh.head_shape = "heart"
	fh.rebuild()
	t.check(_owners(fh).has("full_beard"), "they stay on when the head changes")

	# Facial hair's settings: four parts and a length, reaching the figure.
	var beard := ed.wardrobe.item("full_beard")
	var names: Array = []
	for e in FacialHairSettings.param_spec():
		names.append(String(e["name"]))
	t.check(names == ["moustache", "sideburns", "goatee", "cheeks", "length"]
		and beard.special_params(0).has("moustache") and String(beard.special_params(0)["length"]) == "medium",
		"facial hair is set as four parts and a length; the full beard is all four, medium")
	var count := func() -> int:
		var n := 0
		for poly in fh.view.lowpoly_rig.figure.polygons:
			n += 1 if String(poly["by"]) == "full_beard" else 0
		return n
	var with_moustache: int = count.call()
	beard.set_special_param(0, "moustache", false)
	fh.rebuild()
	var without: int = count.call()
	t.check(without < with_moustache, "turning the moustache off takes it off the figure (%d polygons, %d with it)"
		% [without, with_moustache])
	beard.set_special_param(0, "moustache", true)

	# Drawing the eye changes the face and is undoable.
	var eyes := ed.wardrobe.eye_set(fh.eye_set_id)
	var before := eyes.role_at(EyeSet.EYE_LEFT, 0, 0)
	eyes.set_cell(EyeSet.EYE_LEFT, 0, 0, EyeSet.ROLE_LINE, true)
	ed.commit("Draw eyes", fh)
	t.check_equal(ed.next_undo_doc(), CharacterEditor.DOC_WARDROBE, "drawing eyes is a wardrobe edit")
	ed.undo()
	t.check_equal(ed.wardrobe.eye_set(fh.eye_set_id).role_at(EyeSet.EYE_LEFT, 0, 0), before, "and undo takes it back")


# ----------------------------------------------------------------- clothes --

static func _clothes(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: Clothes -- every body, items with special shapes")
	_fresh(ed)
	ed.show_tab("Clothes")
	var cl := ed.clothes
	cl.clothes.select("skirt")
	cl.show_mode = ClothesWorkspace.SHOW_ITEM
	var with_skirt := 0
	for id in ed.library.body_ids():
		cl.body_id = id
		cl.rebuild()
		var rig := cl.view.lowpoly_rig
		if _owners(cl).has("skirt") and not rig.laid_cloth.is_empty() and rig.figure.warnings.is_empty():
			with_skirt += 1
	t.check_equal(with_skirt, 8, "the skirt, its waistband and its hanging cloth, on all eight bodies")
	t.check(_owners(cl).keys() == ["skirt"], "'this item only' shows just the item", ", ".join(_owners(cl).keys()))
	cl.set_worn_list(ed.wardrobe.outfit("everyday"))
	t.check_equal(cl.show_mode, ClothesWorkspace.SHOW_WORN, "wearing an outfit shows the worn set")
	t.check(_owners(cl).has("tunic"), "with the outfit on")
	cl.hair_id = "short_crop"
	cl.rebuild()
	t.check(_owners(cl).has("short_crop"), "a hair style can be put on to check hats and hoods against")

	# Clicking the figure picks the region of the polygon hit, in whatever pose it is in.
	cl.body_id = "female_average"
	cl.rebuild()
	var rig := cl.view.lowpoly_rig
	var hit := rig.pick(Vector3(0.02, 0.8, -3.0), Vector3(0, 0, 1))
	t.check(hit >= 0 and String(rig.figure.polygons[hit]["region"]) == "lower_chest.R.F",
		"a ray from in front, just right of the middle, at chest height, picks the lower chest, right, front",
		"picked %s" % (String(rig.figure.polygons[hit]["region"]) if hit >= 0 else "nothing"))
	rig.apply_pose(Poses.T_POSE)
	hit = rig.pick(Vector3(0.5, 0.92, -3.0), Vector3(0, 0, 1))     # Godot's +x is the character's right
	t.check(hit >= 0 and String(rig.figure.polygons[hit]["region"]).ends_with(".R")
		and String(rig.figure.polygons[hit]["part"]).ends_with("arm_R"),
		"in a T-pose, the same kind of ray far out to the right picks the raised right arm: picking follows the pose",
		"picked %s" % (String(rig.figure.polygons[hit]["region"]) if hit >= 0 else "nothing"))
	rig.apply_pose(Poses.REST)

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
	pv._choose("body_id", "male_short")
	pv._choose("head_shape", "strong")
	pv._choose("hair_id", "ponytail")
	pv._choose("facial_id", "chinstrap")
	pv._choose("accessory_id", "long_beard")
	pv._choose("lids", "angry")
	pv._choose("skin_tone", "deep")
	pv.worn = ed.wardrobe.outfit("travelling")
	pv.refresh()
	pv.rebuild()
	var lp := pv.view.lowpoly_rig
	t.check(lp.figure != null and lp.figure.body_id == "male_short" and lp.figure.head_shape == "strong",
		"the chosen body and head")
	var on := _owners(pv)
	for id in ["ponytail", "chinstrap", "cloak", "tunic", "trousers", "boots"]:
		t.check(on.has(id), "%s is on the character" % id)
	t.check(not lp.laid_cloth.is_empty(), "the cloak's cape hangs")
	var skin_ok := true
	for poly in lp.figure.polygons:
		if String(poly["by"]).is_empty() and not bool(poly["hidden"]) and String(poly["piece"]) != LowpolyAssembler.FACE_PIECE:
			skin_ok = skin_ok and (poly["colour"] as Color).is_equal_approx(Palette.skin_tones("deep")[1])
	t.check(skin_ok, "bare skin is in the chosen skin tone")
	var named := " ".join(lp.figure.warnings)
	t.check(named.contains("hood") and named.contains("long_beard"),
		"what the figure cannot show yet (the cloak's hood, the long beard) is named in the warnings", named)
	t.check(pv._summary.text.contains("Wearing:") and pv._summary.text.contains("masculine short"),
		"and a summary of what is on, naming the body", pv._summary.text)

	# Lids, skin tone, brows and the mouth are chosen here and nowhere else.
	pv._choose("lids", EyeLids.DEFAULT)
	pv._choose("mouth", "open")
	var with_mouth := _face_roles(pv)
	pv._choose("mouth", Mouths.OFF)
	var no_mouth := _face_roles(pv)
	t.check(with_mouth.has("mouth") and with_mouth.has("white") and with_mouth.has("brow") and not no_mouth.has("mouth"),
		"the face is drawn, and the Mouth choice reaches it (none drawn for no mouth)", "%s / %s" % [with_mouth, no_mouth])
	pv._choose("lids", "blink")
	var closed := _face_roles(pv)
	t.check(not closed.has("white") and not closed.has("pupil") and closed.has("lid"), "blink closes the eyes", str(closed))
	t.check(pv._summary.text.contains("blink") and pv._summary.text.contains("deep"), "and the summary says so")
	pv._choose("mouth", Mouths.DEFAULT)

	# A pose lays the cloth again; the shading switch reaches the figure.
	var standing := lp.laid_cloth.duplicate()
	pv.view.set_pose(Poses.SITTING)
	t.check(lp.laid_cloth.size() == standing.size() and lp.laid_cloth != standing, "sitting lays the cape again")
	pv.view.set_pose(Poses.REST)
	pv._shading_pick.select(1)
	pv._shading_pick.item_selected.emit(1)
	t.check(not lp.flat_shading, "the shading switch reaches the figure")
	pv._shading_pick.select(0)
	pv._shading_pick.item_selected.emit(0)


# ------------------------------------------------------------------- undo --

static func _undo_timeline(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: one undo timeline")
	_fresh(ed)
	ed.show_tab("Clothes")
	var original_order := ed.wardrobe.item("tunic").draw_order
	ed.wardrobe.item("tunic").draw_order = 31
	ed.commit("Set draw order A", ed.clothes)
	ed.wardrobe.item("tunic").draw_order = 32
	ed.commit("Set draw order B", ed.clothes)
	t.check(ed._menu_edit.get_popup().get_item_text(0).contains("Set draw order B"),
		"the menu names the edit undo will reverse", ed._menu_edit.get_popup().get_item_text(0))
	ed.undo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, 31, "undo reverses B")
	ed.undo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, original_order, "undo reverses A")
	t.check(not ed.undo(), "and then there is nothing left")
	ed.redo()
	ed.redo()
	t.check_equal(ed.wardrobe.item("tunic").draw_order, 32, "redo replays them in order")


# ---------------------------------------------------------- unsaved guard --

static func _unsaved_guard(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: nothing unsaved is lost without asking")
	_fresh(ed)
	var ran := [0]
	var action := func() -> void: ran[0] += 1

	ed.guard_unsaved(action)
	t.check_equal(ran[0], 1, "with nothing unsaved the action runs at once")

	ed.wardrobe.item("tunic").draw_order = 40
	ed.commit("Make it dirty", ed.clothes)
	ed.guard_unsaved(action)
	t.check_equal(ran[0], 1, "a dirty wardrobe stops the action")
	ed._on_discard_changes()
	t.check_equal(ran[0], 2, "Discard lets it run")

	ed.guard_unsaved(action)
	ed.cancel_pending()
	ed.resume_pending()
	t.check_equal(ran[0], 2, "a cancelled prompt's action never fires later")

	ed.wardrobe.path = SAVE_PATH
	ed.guard_unsaved(action)
	ed._unsaved_dialog.hide()
	ed._on_save_then_continue()
	t.check(not ed.wardrobe.dirty, "Save first saved the wardrobe")
	t.check_equal(ran[0], 3, "and then ran the action")

	# The window's close button goes through the same guard as File > Quit.
	ed.wardrobe.item("tunic").draw_order = 42
	ed.commit("Dirty before closing", ed.clothes)
	ed._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	t.check(ed._unsaved_dialog.visible, "closing the window with unsaved changes asks instead of quitting")
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
