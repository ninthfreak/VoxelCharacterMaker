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
	_shape_colours(t, ed)
	_panels_together(t, ed)
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


## A special shape colours with roles by name, and an item colours with palette colours by name: the Colours panel
## will not rename or remove either while something uses it (that left a cape magenta and a hood grey).
static func _shape_colours(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: colours that special shapes and items use")
	_fresh(ed)
	ed.show_tab("Clothes")
	var cl := ed.clothes
	var colours: ColourPanel = null
	var looking: Array[Node] = [cl]
	while colours == null and not looking.is_empty():
		var node: Node = looking.pop_back()
		if node is ColourPanel:
			colours = node
		looking.append_array(node.get_children())
	cl.clothes.select("cloak")
	colours.refresh()
	colours._roles.select(colours._role_names.find("cloth"))
	colours._role_name.text = "fabric"
	colours._on_rename_role()
	var cloak := ed.wardrobe.item("cloak")
	t.check(cloak.roles.has("cloth") and not cloak.roles.has("fabric"), "renaming the cloak's 'cloth' is refused",
		str(cloak.roles))
	t.check(ed.status_hint().contains("keeps that name"), "and the status line says why", ed.status_hint())
	colours._roles.select(colours._role_names.find("lining"))
	colours._on_remove_role()
	t.check(cloak.roles.has("lining"), "removing its 'lining' (the hood's) is refused")
	cloak.add_role("extra")
	colours.refresh()
	colours._roles.select(colours._role_names.find("extra"))
	colours._on_remove_role()
	t.check(not cloak.roles.has("extra"), "a role no shape reads can still be removed")

	colours._palette.select(colours._palette_keys.find("rust"))
	colours._on_remove_colour()
	t.check(ed.wardrobe.palette.has("rust"), "removing a palette colour items use is refused")
	t.check(ed.status_hint().contains("Hooded cloak (default)"), "and the status line names who uses it", ed.status_hint())
	ed.wardrobe.set_colour("unused_grey", Color8(90, 90, 90))
	colours.refresh()
	colours._palette.select(colours._palette_keys.find("unused_grey"))
	colours._on_remove_colour()
	t.check(not ed.wardrobe.palette.has("unused_grey"), "a colour nothing uses can be removed")

	# Adding a shape to an item gives it the roles the shape reads: a cape on the tunic gets a hem colour.
	var tunic := ed.wardrobe.item("tunic")
	tunic.add_special("cape")
	t.check(tunic.roles.has("hem") and tunic.palette_key_for("default", "hem") == "ink",
		"a cape added to the tunic brings a 'hem' role, in ink", str(tunic.roles))

	# A file made elsewhere can still lack them: the figure says so rather than showing magenta in silence.
	var w := Wardrobe.from_json(ed.wardrobe.to_json())
	var bare := w.item("cloak")
	for way in bare.colourways.keys():
		(bare.colourways[way] as Dictionary)["cloth"] = "no_such_colour"
	bare.roles.erase("lining")
	bare.set_special_param(1, "lined", true)
	var req := CharacterRequest.make("female_average", "round", w)
	req.worn = [{"item": "cloak", "colourway": "default"}]
	var said := ", ".join(LowpolyAssembler.assemble(ed.library, req).warnings)
	t.check(said.contains("'no_such_colour' is not in the palette"), "a colour not in the palette is named in the warnings",
		said)
	t.check(said.contains("role named 'lining'"), "a lined hood on an item with no 'lining' role is named too", said)

	# Edits that change nothing make no undo step.
	var steps: int = ed.history._entries.size()
	colours.refresh()
	colours._roles.select(colours._role_names.find("lining"))
	colours._role_name.text = "hem"
	colours._on_rename_role()
	t.check(cloak.roles.has("lining") and ed.history._entries.size() == steps,
		"renaming a role to a name the item already has is refused, with no undo step", ed.status_hint())

	# Dragging the colour picker is one edit while it is open.
	colours._palette_name.text = "slate"
	steps = ed.history._entries.size()
	for v in [40, 60, 80, 100]:
		colours._palette_colour.color_changed.emit(Color8(v, v, v))
	t.check_equal(ed.history._entries.size(), steps + 1, "a colour dragged through four values is one undo step")
	colours._palette_colour.popup_closed.emit()
	colours._palette_colour.color_changed.emit(Color8(150, 150, 150))
	t.check_equal(ed.history._entries.size(), steps + 2, "and the next time the picker is used is another")
	ed.undo()
	t.check(ed.wardrobe.colour("slate").is_equal_approx(Color8(100, 100, 100)), "undo goes back to where the drag ended",
		str(ed.wardrobe.colour("slate")))
	ed.undo()
	t.check(ed.wardrobe.colour("slate").is_equal_approx(Wardrobe.create_default().colour("slate")),
		"and once more, to before it")

	# A file from before eye sets has none of their colours: the standard eye set brings them.
	var old := Wardrobe.create_default()
	old.eye_sets.clear()
	for key in EyeSet.default_colours().values():
		old.palette.erase(key)
	ed._replace_wardrobe(old, "Old file")
	var has_all := true
	for key in EyeSet.default_colours().values():
		has_all = has_all and ed.wardrobe.palette.has(key)
	t.check(has_all and not ed.wardrobe.eye_set_ids().is_empty(),
		"a wardrobe with no eye sets gets the standard one, and its colours when the palette lacks them")


## The first panel of this type under a node.
static func _panel(under: Node, type: Variant) -> Node:
	var looking: Array[Node] = [under]
	while not looking.is_empty():
		var node: Node = looking.pop_front()
		if is_instance_of(node, type):
			return node
		looking.append_array(node.get_children())
	return null


## Panels that share an item see each other's edits; the camera lets go; a new wardrobe starts afresh.
static func _panels_together(t: TestReport, ed: CharacterEditor) -> void:
	t.group("editor: panels see each other's edits")
	_fresh(ed)
	ed.show_tab("Clothes")
	var cl := ed.clothes
	var colours := _panel(cl, ColourPanel) as ColourPanel
	var garment := cl._garment
	cl.clothes.select("tunic")
	colours._role_name.text = "buckle"
	colours._on_add_role()
	var offered: Array = []
	for i in garment._role.item_count:
		offered.append(garment._role.get_item_metadata(i))
	t.check(offered.has("buckle"), "a role added in the Colours panel is offered by the item's role picker at once",
		str(offered))
	garment._role.select(offered.find("trim"))
	colours._role_name.text = "strap"
	colours._on_add_role()
	t.check_equal(garment.option_value(garment._role), "trim", "and the picker keeps the role chosen in it")

	cl.clothes.select("tunic")
	cl.clothes.set_colourway("rust")
	colours.refresh()
	t.check_equal(colours._way(ed.wardrobe.item("tunic")), "rust",
		"the Colours panel edits the colourway chosen for the item (the one the preview shows)")
	colours._colourways.item_selected.emit(colours._colourway_names.find("default"))
	t.check_equal(cl.clothes.colourway, "default", "and choosing one in the Colours panel chooses it for the item")

	var steps: int = ed.history._entries.size()
	colours._role_name.text = "trim"
	colours._on_add_role()
	garment._regions.deselect_all()
	garment._regions.select(garment._region_keys.find("upper_arm.L"))
	ed.wardrobe.item("tunic").clear_region("upper_arm.L")
	garment._on_clear()
	t.check_equal(ed.history._entries.size(), steps, "adding a role the item has, or clearing uncovered regions, makes no undo step")

	# A region picked on the figure stays selected through an edit made in another panel.
	garment._regions.deselect_all()
	garment._regions.select(garment._region_keys.find("belly.L.F"))
	colours._role_name.text = "patch"
	colours._on_add_role()
	t.check_equal(garment._selected_keys(), ["belly.L.F"] as Array[String], "the selected regions survive the refresh")
	t.check(garment.select_region("belly.R.F").begins_with("Picked"), "a pick of a region the item covers says Picked")
	cl.clothes.select("")
	t.check(garment.select_region("belly.R.F").contains("select an item first"),
		"a pick with no item selected says to select one, not Picked")
	cl.clothes.select("tunic")

	# The camera: letting go of Shift before the button still ends the drag.
	var cam: OrbitCamera = cl.view.camera
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = true
	cam.handle_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	cam.handle_input(release)
	t.check(not cam._dragging_pan and not cam._dragging_orbit, "a drag ends when the button is let go, Shift or not")

	# A new wardrobe: each tab wears its "everyday" outfit again.
	cl.set_worn_list([])
	ed.preview.worn = []
	_fresh(ed)
	t.check(not cl.worn.is_empty() and not ed.preview.worn.is_empty(), "a new wardrobe puts the everyday outfit on again")


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
	var pieces := {}
	for poly in lp.figure.polygons:
		pieces[String(poly["piece"])] = true
	t.check(pieces.has("shape:hood") and pieces.has("shape:long_beard") and pieces.has("shape:ponytail"),
		"the cloak's hood, the long beard and the ponytail's tail are drawn", ", ".join(pieces.keys()))
	var named := " ".join(lp.figure.warnings)
	t.check(not named.contains("hood") and not named.contains("long_beard"),
		"and nothing is left out for want of a low-poly form", named)
	t.check(pv._summary.text.contains("Wearing:") and pv._summary.text.contains("masculine short"),
		"and a summary of what is on, naming the body", pv._summary.text)

	# A choice for the face alone draws the face again on the figure already dressed; anything else dresses afresh.
	var dressed_before := lp.figure
	pv._choose("lids", "angry")
	var face_only := lp.figure
	pv._choose("skin_tone", "light")
	var redressed := lp.figure
	t.check(face_only != dressed_before and is_same(face_only.polygons[0], dressed_before.polygons[0])
		and not is_same(redressed.polygons[0], face_only.polygons[0]),
		"a new lid state redraws only the face; a new skin tone dresses the figure again")
	pv._choose("skin_tone", "deep")

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
