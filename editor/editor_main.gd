@tool
class_name CharacterEditor
extends Control

## The in-engine character editor (SPEC.md section 8).
##
## Built inside the game's own project and sharing CharacterAssembler with the
## runtime, because two implementations of bulk generation would drift. Every
## preview here goes through exactly the same code the game will.
##
## The UI is built in code rather than laid out in a .tscn. That is deliberate:
## a scene file is the better place for layout once someone can click around in
## the Godot editor, but a hand-written .tscn cannot be read for correctness the
## way a script can, and this project's tests run headless. See docs/NOTES.md.
##
## Accessibility (the owner is red/green colour blind, dyslexic, has ADHD):
##   - no state is signalled by red vs green alone; worn items carry a "worn"
##     word, warnings carry the word "warning", and swatches carry their name
##   - labels are short and literal, hints are one line
##   - the figure, the file and the current selection are always on screen, so
##     nothing depends on remembering what mode you are in

const STATE_PATH := "user://editor_state.cfg"
## Where the last file and figure are remembered. A variable so the test suite
## can point it elsewhere before the editor starts, rather than overwrite the
## state of whoever runs the tests.
var state_path := STATE_PATH
const DEFAULT_WARDROBE := "user://wardrobe.vxwardrobe.json"

signal figure_changed
signal wardrobe_replaced
signal selection_changed
## A body was opened in, or closed from, the Body tab.
signal body_editing_changed

## The item the Wardrobe and Garment tabs are both working on. Shared so that
## picking a region on the figure edits the item you were already looking at,
## with no second selection to keep in your head.
var selected_item_id: String = ""

# -- model -------------------------------------------------------------------
var library: AssetLibrary = null
var wardrobe: Wardrobe = null
var history := EditHistory.new()

# -- figure state ------------------------------------------------------------
var body_id: String = "male_average"
var head_shape: String = "round"
var expression: String = "neutral"
var pose_name: String = Poses.REST
var eye_colour: Color = Palette.EYE_BLACK
var use_face_multiplier: bool = true
## Array of {"item": id, "colourway": name}
var worn: Array = []
var solo_item: String = ""
var picking_enabled: bool = false

# -- nodes -------------------------------------------------------------------
var rig: CharacterRig = null
var camera: OrbitCamera = null
var _subviewport: SubViewport = null
var _viewport_container: SubViewportContainer = null
var _status: Label = null
var _title: Label = null
var _warning: Label = null
## Messages from the last action ("Saved ...", "Picked ..."). Kept apart from
## _warning, which rebuild() owns: sharing one label meant every rebuild wiped
## the message the action had just set, so "Saved" was never seen.
var _hint: Label = null
var _tabs: TabContainer = null
var _menu_file: MenuButton = null
var _menu_edit: MenuButton = null

var figure_panel: FigurePanel = null
var wardrobe_panel: WardrobePanel = null
var garment_panel: GarmentPanel = null
var colour_panel: ColourPanel = null
var body_panel: BodyPanel = null

## Set by the body editor while it has a body open, so the preview shows what
## is being drawn instead of the library's copy.
var body_override: BodyDef = null

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
	# This script is @tool so its panels' helpers can run in the editor, but the
	# app itself must not: opening this scene in the Godot editor would
	# otherwise build the whole UI inside the editor's viewport, read and write
	# user state, and -- with the close request taken over below -- interfere
	# with closing Godot itself.
	if Engine.is_editor_hint():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Closing the window must go through the unsaved-changes prompt like Quit
	# does; Godot accepts the close straight away unless told not to.
	get_tree().set_auto_accept_quit(false)
	library = AssetLibrary.new()
	if not library.load_all():
		push_error("asset library: %s" % ", ".join(library.errors))

	# The model is loaded BEFORE any control exists. Panels refresh themselves
	# as they are set up, and a refresh can reach back into rebuild(), so there
	# must be no half-built state for it to find.
	var state := _load_state()
	var last_path := String(state.get("wardrobe_path", ""))
	if not last_path.is_empty() and FileAccess.file_exists(last_path):
		wardrobe = Wardrobe.load_from(last_path)
	if wardrobe == null:
		wardrobe = Wardrobe.create_default()
	history.reset(wardrobe.to_json())

	body_id = String(state.get("body_id", body_id))
	head_shape = String(state.get("head_shape", head_shape))
	expression = String(state.get("expression", expression))
	pose_name = String(state.get("pose_name", pose_name))
	if library.body(body_id) == null:
		body_id = library.body_ids()[0] if not library.body_ids().is_empty() else ""
	if library.head(head_shape) == null:
		head_shape = "round"
	_wear_default_outfit()

	_build_ui()
	history.changed.connect(_refresh_edit_menu)

	_refresh_all_panels()
	rebuild()
	_fit_view_if_untouched()


# ----------------------------------------------------------------------- UI --

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Menu row, plus the file name so it is never a mystery which file is open.
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
	_refresh_edit_menu()

	_title = Label.new()
	_title.text = "(unsaved wardrobe)"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)

	# Main split: figure on the left, panels on the right.
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 1000
	root.add_child(split)

	split.add_child(_build_viewport())

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	split.add_child(right)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_tabs)

	figure_panel = FigurePanel.new()
	wardrobe_panel = WardrobePanel.new()
	garment_panel = GarmentPanel.new()
	colour_panel = ColourPanel.new()
	body_panel = BodyPanel.new()

	# Each panel goes in its own scroller. Several of them are taller than the
	# window on a laptop, and a control you cannot reach may as well not exist.
	_add_tab("Figure", figure_panel)
	_add_tab("Wardrobe", wardrobe_panel)
	_add_tab("Garment", garment_panel)
	_add_tab("Colours", colour_panel)
	_add_tab("Body", body_panel)

	# Status row: counts, then warnings spelled out as words. Built before the
	# panels are set up, because setting a panel up refreshes it and a refresh
	# can reach rebuild(), which writes here.
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
	# Shares the row rather than being squeezed off the end of it.
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.clip_text = true
	status_row.add_child(_hint)

	_build_dialogs()

	for panel in [figure_panel, wardrobe_panel, garment_panel, colour_panel, body_panel]:
		panel.setup(self)


## Put one panel in the tab strip, inside a scroller that carries the title.
func _add_tab(title: String, panel: EditorPanel) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	_tabs.add_child(scroll)


func _build_viewport() -> Control:
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# View buttons, labelled. Number keys do the same thing.
	var views := HBoxContainer.new()
	holder.add_child(views)
	camera = OrbitCamera.new()
	for i in camera.view_names().size():
		var view := camera.view_names()[i]
		var button := Button.new()
		button.text = "%s (%d)" % [OrbitCamera.view_label(view), i + 1]
		button.pressed.connect(func() -> void: camera.set_view(view))
		views.add_child(button)

	var frame_button := Button.new()
	frame_button.text = "Fit"
	frame_button.pressed.connect(func() -> void:
		camera.moved_by_user = false
		_fit_view())
	views.add_child(frame_button)

	var pick_toggle := CheckBox.new()
	pick_toggle.text = "Click figure to pick regions"
	pick_toggle.toggled.connect(_on_picking_toggled)
	views.add_child(pick_toggle)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(_viewport_container)

	_subviewport = SubViewport.new()
	_subviewport.own_world_3d = true
	_subviewport.handle_input_locally = false
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_subviewport)
	# The view fits itself whenever the pane changes size. This matters at
	# startup: _ready runs before the layout has settled, so a fit done there
	# is computed against a pane size that is about to change.
	_viewport_container.resized.connect(_fit_view_if_untouched)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(32, 36, 46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	environment.environment = env
	_subviewport.add_child(environment)

	_subviewport.add_child(camera)

	rig = CharacterRig.new()
	rig.name = "Figure"
	_subviewport.add_child(rig)

	# A ground line at the feet, so z = 0 is visible and pivots can be judged.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 2.4)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_material.albedo_color = Color8(48, 54, 68)
	ground.material_override = ground_material
	ground.position = Vector3(0, -0.001, 0)
	_subviewport.add_child(ground)

	return holder


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
	_unsaved_dialog.dialog_text = "This wardrobe has unsaved changes."
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


## Fit the figure in the pane, using the pane's real aspect.
func _fit_view() -> void:
	if camera == null or rig == null or _viewport_container == null:
		return
	var pane := _viewport_container.size
	var aspect := 1.0 if pane.y <= 0.0 else pane.x / pane.y
	camera.frame(rig.figure_aabb(), aspect)


func _fit_view_if_untouched() -> void:
	if camera != null and camera.moved_by_user:
		return
	_fit_view()


# ------------------------------------------------------------------ rebuild --

## Re-assemble and re-mesh the figure. Everything that changes the figure ends
## here, and it is the only place the assembler is called from the editor.
func rebuild() -> void:
	if library == null:
		return
	# One place, rather than at every delete, undo and load: a solo item that
	# is gone hides every other worn item while showing nothing itself.
	if not solo_item.is_empty() and (wardrobe == null or wardrobe.item(solo_item) == null):
		solo_item = ""
	var request := CharacterAssembler.Request.make(library, body_id, head_shape, expression)
	request.body_override = body_override
	request.wardrobe = wardrobe
	request.worn = worn
	request.solo_item = solo_item
	request.eye_colour = eye_colour
	request.use_face_multiplier = use_face_multiplier

	var assembled := CharacterAssembler.assemble(request)
	rig.use_face_multiplier = use_face_multiplier
	rig.build(assembled)
	rig.apply_pose(pose_name)

	if picking_enabled:
		_build_pick_bodies()

	var body := assembled.body
	var pieces := assembled.order.size()
	_status.text = "%s - %s head - %s   |   %d voxels, %d faces, %d parts   |   %s" % [
		"%s%s" % [body.display_name() if body != null else body_id,
			" (editing)" if body_override != null else ""],
		head_shape, expression,
		assembled.total_voxels(), rig.total_faces(), pieces,
		"solo: %s" % solo_item if not solo_item.is_empty() else "whole outfit",
	]
	if assembled.warnings.is_empty():
		_warning.text = ""
	else:
		_warning.text = "warning: %s" % assembled.warnings[0]

	_title.text = "%s%s" % [
		wardrobe.display_path() if wardrobe != null else "(no wardrobe)",
		" - edited" if wardrobe != null and wardrobe.dirty else "",
	]
	figure_changed.emit()


## Panels call this after mutating the wardrobe: it records undo, marks the
## file dirty and refreshes the figure in one step.
func commit(label: String) -> void:
	if wardrobe == null:
		return
	wardrobe.mark_dirty()
	history.commit(label, wardrobe.to_json())
	note_edit(DOC_WARDROBE)
	rebuild()


func _refresh_all_panels() -> void:
	for panel in [figure_panel, wardrobe_panel, garment_panel, colour_panel, body_panel]:
		if panel != null:
			panel.refresh()


func _wear_default_outfit() -> void:
	worn.clear()
	if wardrobe == null:
		return
	var names := wardrobe.outfit_names()
	if not names.is_empty():
		worn = wardrobe.outfit(names[0])
		return
	for item_id in wardrobe.item_ids_by_draw_order():
		var item := wardrobe.item(item_id)
		worn.append({"item": item_id, "colourway": item.first_colourway()})


# -------------------------------------------------------------- worn items --

func is_worn(item_id: String) -> bool:
	for entry in worn:
		if String((entry as Dictionary)["item"]) == item_id:
			return true
	return false


func worn_colourway(item_id: String) -> String:
	for entry in worn:
		var e: Dictionary = entry
		if String(e["item"]) == item_id:
			return String(e["colourway"])
	var item := wardrobe.item(item_id) if wardrobe != null else null
	return item.first_colourway() if item != null else ""


func set_worn(item_id: String, wear: bool) -> void:
	var item := wardrobe.item(item_id) if wardrobe != null else null
	if item == null:
		return
	if wear and not is_worn(item_id):
		worn.append({"item": item_id, "colourway": item.first_colourway()})
	elif not wear:
		for i in range(worn.size() - 1, -1, -1):
			if String((worn[i] as Dictionary)["item"]) == item_id:
				worn.remove_at(i)
	rebuild()


func set_worn_colourway(item_id: String, colourway: String) -> void:
	for entry in worn:
		var e: Dictionary = entry
		if String(e["item"]) == item_id:
			e["colourway"] = colourway
	rebuild()


func set_solo(item_id: String) -> void:
	solo_item = item_id
	rebuild()


## Bring a tab to the front by its name. Used by region picking, which jumps
## to the Garment tab, and by tools/screenshot_editor.gd.
func show_tab(title: String) -> void:
	if _tabs == null:
		return
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == title:
			_tabs.current_tab = i
			return


func select_item(item_id: String) -> void:
	if selected_item_id == item_id:
		return
	selected_item_id = item_id
	selection_changed.emit()


func selected_item() -> GarmentItem:
	if wardrobe == null:
		return null
	return wardrobe.item(selected_item_id)


# ------------------------------------------------------------------ picking --

## Trimesh collision, built only while picking is on: it costs real time on a
## few thousand quads and most editing is done from the region list.
func _build_pick_bodies() -> void:
	for name in rig.mesh_instances.keys():
		var instance: MeshInstance3D = rig.mesh_instances[name]
		instance.create_trimesh_collision()


func _on_picking_toggled(on: bool) -> void:
	picking_enabled = on
	rebuild()
	set_status_hint("Click the figure to select that region." if on
		else "Region picking off; use the Garment tab's list.")


func _pick_region_at(screen_position: Vector2) -> void:
	var space := _subviewport.world_3d.direct_space_state
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	# The collision body hangs under the part's MeshInstance3D, so the part is
	# two levels up, and its joint transform takes the point back to asset space.
	var collider: Node = hit.get("collider")
	if collider == null:
		return
	var part_name := ""
	var node: Node = collider
	while node != null:
		if rig.joints.has(node.name):
			part_name = String(node.name)
			break
		node = node.get_parent()
	if part_name.is_empty():
		return

	var part := rig.assembled.part(part_name)
	if part == null:
		return
	var joint: Node3D = rig.joints[part_name]
	# Step just inside the surface, then convert to a voxel index.
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var local := joint.global_transform.affine_inverse() * (
		(hit.get("position") as Vector3) - normal * (VoxelAxes.VOXEL_SIZE * 0.5))
	var cell := _godot_local_to_cell(local, part.pivot)
	var region := String(part.regions.get(cell, ""))
	if region.is_empty():
		set_status_hint("That cell is not in any region.")
		return
	show_tab("Garment")
	garment_panel.select_region(region)
	set_status_hint("Picked %s" % wardrobe_region_label(region))


## A point in a joint's local space -> the voxel under it. The conversion
## itself is VoxelAxes's, so a change of convention there reaches picking too.
func _godot_local_to_cell(local: Vector3, pivot: Vector3) -> Vector3i:
	var asset := VoxelAxes.godot_to_point(local + VoxelAxes.point_to_godot(pivot))
	return Vector3i(floori(asset.x), floori(asset.y), floori(asset.z))


func wardrobe_region_label(region_key: String) -> String:
	var map := library.region_map()
	return map.label_for(region_key) if map != null else region_key


# -------------------------------------------------------------------- input --

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	_route_viewport_input(event)


func _route_viewport_input(event: InputEvent) -> void:
	if _viewport_container == null:
		return
	if event is InputEventMouse:
		var mouse := event as InputEventMouse
		if not _viewport_container.get_global_rect().has_point(mouse.global_position):
			return
		if picking_enabled and event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.shift_pressed:
				_pick_region_at(mouse.global_position - _viewport_container.global_position)
				accept_event()
				return
	if camera != null and camera.handle_input(event):
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed or key.meta_pressed:
		match key.keycode:
			KEY_S:
				if key.shift_pressed:
					_on_file_menu(FileMenu.SAVE_AS)
				else:
					_on_file_menu(FileMenu.SAVE)
				accept_event()
			KEY_O:
				_on_file_menu(FileMenu.OPEN)
				accept_event()
			KEY_N:
				_on_file_menu(FileMenu.NEW)
				accept_event()
			KEY_Z:
				if key.shift_pressed:
					_on_edit_menu(EditMenu.REDO)
				else:
					_on_edit_menu(EditMenu.UNDO)
				accept_event()
			KEY_Y:
				_on_edit_menu(EditMenu.REDO)
				accept_event()
		return
	if camera != null and camera.handle_input(event):
		accept_event()


# ------------------------------------------------------------------- undo ----
#
# Two documents can be edited at once -- the wardrobe, and a body open in the
# Body tab -- and each keeps its own snapshot history. The timeline records
# which document each edit belonged to, in the order they happened, so Ctrl+Z
# always reverses the most recent edit, whichever document it was in, and the
# Edit menu names exactly what that will be.
#
# (Routing every undo to the body while one was open, as this used to, made
# the menu describe one edit while Ctrl+Z undid another, and left wardrobe
# edits made during body editing impossible to undo until editing stopped.)

const DOC_WARDROBE := "wardrobe"
const DOC_BODY := "body"

var _timeline: Array[String] = []
var _timeline_at := -1  ## index of the most recent edit still applied


## Record that an edit just landed in `doc`. Anything that had been undone is
## no longer reachable, exactly as with a single stack.
func note_edit(doc: String) -> void:
	while _timeline.size() > _timeline_at + 1:
		_timeline.remove_at(_timeline.size() - 1)
	_timeline.append(doc)
	_timeline_at = _timeline.size() - 1
	_refresh_edit_menu()


## Drop every timeline entry for `doc`, because its history was replaced (a
## new or opened wardrobe, a body opened or closed).
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
		return body_panel.history if body_panel != null else null
	return history


## The document the next undo would act on, or "" when there is nothing.
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
	var prefix := "body: " if doc == DOC_BODY else ""
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


## Reverse the most recent edit in either document. Returns false when there
## was nothing to undo.
func undo() -> bool:
	while _timeline_at >= 0:
		var doc := _timeline[_timeline_at]
		var h := _history_for(doc)
		if h == null or not h.can_undo():
			# Older than that document's history reaches (it caps its length),
			# so this entry can never be undone; drop it and look further back.
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
		if body_panel != null:
			body_panel.restore_snapshot(snapshot)
		return
	var restored := Wardrobe.from_json(snapshot)
	if restored == null:
		return
	restored.path = wardrobe.path
	restored.dirty = true
	wardrobe = restored
	_prune_worn()
	wardrobe_replaced.emit()
	_refresh_all_panels()
	rebuild()


## After an undo or a load, drop worn entries whose item or colourway is gone.
func _prune_worn() -> void:
	var kept: Array = []
	for entry in worn:
		var e: Dictionary = entry
		var item := wardrobe.item(String(e["item"]))
		if item == null:
			continue
		var colourway := String(e["colourway"])
		if not item.has_colourway(colourway):
			colourway = item.first_colourway()
		kept.append({"item": item.id, "colourway": colourway})
	worn = kept


# -------------------------------------------------------------------- files --

func _on_file_menu(id: int) -> void:
	match id:
		FileMenu.NEW:
			var start_new := func() -> void:
				_replace_wardrobe(Wardrobe.create_default(), "New wardrobe")
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


## Quit, after asking about anything unsaved in either document. Both File >
## Quit and the window's close button come here.
func _quit_when_safe() -> void:
	var quit_now := func() -> void:
		_save_state()
		get_tree().quit()
	guard_unsaved(quit_now, true, true)


## Swap in a different wardrobe: the history and its timeline entries go with
## the old one.
func _replace_wardrobe(new_wardrobe: Wardrobe, label: String) -> void:
	wardrobe = new_wardrobe
	history.reset(wardrobe.to_json(), label)
	forget_edits(DOC_WARDROBE)
	_wear_default_outfit()
	wardrobe_replaced.emit()
	_refresh_all_panels()
	rebuild()


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
	rebuild()
	set_status_hint("Saved %s" % wardrobe.display_path())
	# If this save was the "Save first" answer to a prompt, carry on with
	# whatever the prompt was guarding. Saving through a file dialog answers
	# later than the prompt does, so this is the only place that can.
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
## check_body      ask about unsaved edits to the body open in the Body tab
## check_wardrobe  ask about unsaved changes to the wardrobe
##
## The body is asked about first; once it is saved or discarded the wardrobe
## gets its turn, and only then does the action run. Every way out of a prompt
## either resumes the action or drops it -- nothing is left waiting to fire
## later on an unrelated save.
func guard_unsaved(action: Callable, check_body: bool, check_wardrobe: bool) -> void:
	if check_body and body_panel != null and body_panel.has_unsaved():
		_pending_after_prompt = func() -> void:
			guard_unsaved(action, false, check_wardrobe)
		_prompt(DOC_BODY, "The body you are editing (%s) has unsaved changes."
			% body_panel.edit_display_name())
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


## "Save first". Saving may need a file dialog, which answers later; the
## pending action then resumes from resume_pending() once the save lands, or
## is dropped by cancel_pending() if the dialog is cancelled.
func _on_save_then_continue() -> void:
	if _prompt_doc == DOC_BODY and body_panel != null:
		body_panel.save_for_prompt()
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
	if doc == DOC_BODY and body_panel != null:
		body_panel.discard_unsaved()
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


func set_status_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text


func status_hint() -> String:
	return _hint.text if _hint != null else ""


# -------------------------------------------------------------------- state --

func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("editor", "wardrobe_path", wardrobe.path if wardrobe != null else "")
	cfg.set_value("editor", "body_id", body_id)
	cfg.set_value("editor", "head_shape", head_shape)
	cfg.set_value("editor", "expression", expression)
	cfg.set_value("editor", "pose_name", pose_name)
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
