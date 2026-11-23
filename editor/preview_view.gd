@tool
class_name PreviewView
extends VBoxContainer

## One 3D preview: a figure, a camera you can orbit, the labelled view buttons,
## and optional region picking.
##
## Every workspace has its own, so cycling bodies in the Clothes tab does not
## disturb what the Preview tab is looking at. Only the visible one renders.
##
## Mouse: left or middle drag orbits, right drag or shift+drag pans, wheel
## zooms. Number keys 1-6 pick the fixed views (the shell forwards them to
## whichever tab is showing).
##
## The Items tab shows a held item on its own instead of a figure (show_item): an ItemStage, where the item is put
## together by hand. The stage sees the mouse and the keys first; what it does not use turns the camera.

signal region_picked(region: String)

## What "Fit" frames: the whole figure, or just the head.
enum Fit { FIGURE, HEAD }

var camera: OrbitCamera = null
## The figure shown.
var lowpoly_rig: LowpolyRig = null
var pose_name: String = Poses.REST
var fit_mode: int = Fit.FIGURE
var picking_enabled := false

var _container: SubViewportContainer = null
var _viewport: SubViewport = null
var _pick_toggle: CheckBox = null
var _buttons: HBoxContainer = null
var _ground: MeshInstance3D = null
## The item shown on its own (show_item); hidden while a figure is shown.
var item_stage: ItemStage = null
var showing_item := false
var _readout: Label = null
var _toolbars: Array[Control] = []


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	camera = OrbitCamera.new()

	_buttons = HBoxContainer.new()
	add_child(_buttons)
	for i in camera.view_names().size():
		var view := camera.view_names()[i]
		var button := Button.new()
		button.text = "%s (%d)" % [OrbitCamera.view_label(view), i + 1]
		button.pressed.connect(func() -> void: camera.set_view(view))
		_buttons.add_child(button)
	var fit := Button.new()
	fit.text = "Fit"
	fit.pressed.connect(func() -> void:
		camera.moved_by_user = false
		fit_view())
	_buttons.add_child(fit)

	_pick_toggle = CheckBox.new()
	_pick_toggle.text = "Click figure to pick regions"
	_pick_toggle.visible = false
	_pick_toggle.toggled.connect(func(on: bool) -> void:
		picking_enabled = on)
	_buttons.add_child(_pick_toggle)

	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_container.custom_minimum_size = Vector2(320, 320)
	_container.gui_input.connect(_on_container_input)
	# The view fits itself whenever the pane changes size, until the user
	# takes the camera over: _ready runs before layout settles, so a fit done
	# then is against a pane size that is about to change.
	_container.resized.connect(fit_if_untouched)
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_container.add_child(_viewport)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(32, 36, 46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	environment.environment = env
	_viewport.add_child(environment)
	_viewport.add_child(camera)

	lowpoly_rig = LowpolyRig.new()
	lowpoly_rig.name = "Figure"
	_viewport.add_child(lowpoly_rig)

	# A ground plane at the feet, so z = 0 is visible and pivots can be judged.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 2.4)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_material.albedo_color = Color8(48, 54, 68)
	ground.material_override = ground_material
	ground.position = Vector3(0, -0.001, 0)
	_viewport.add_child(ground)
	_ground = ground

	item_stage = ItemStage.new()
	item_stage.name = "Item"
	item_stage.visible = false
	item_stage.camera = camera
	item_stage.body_material = lowpoly_rig.material()
	_viewport.add_child(item_stage)

	# what a drag is doing, in words, by the pointer
	_readout = Label.new()
	_readout.visible = false
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.add_theme_font_size_override("font_size", 18)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	plate.set_content_margin_all(6)
	plate.set_corner_radius_all(4)
	_readout.add_theme_stylebox_override("normal", plate)
	_container.add_child(_readout)


## Offer "click to pick regions" -- the tabs that edit garments do.
func allow_picking(on: bool) -> void:
	_pick_toggle.visible = on
	if not on:
		picking_enabled = false
		_pick_toggle.button_pressed = false


## Show a figure.
func show_lowpoly(figure: LowpolyFigure, flat: bool) -> void:
	var was_item := showing_item
	showing_item = false
	item_stage.visible = false
	lowpoly_rig.visible = true
	_ground.visible = true
	_readout.visible = false
	_container.focus_mode = Control.FOCUS_NONE
	_container.mouse_default_cursor_shape = Control.CURSOR_ARROW
	for bar in _toolbars:
		bar.visible = false
	var first := lowpoly_rig.figure == null or was_item
	lowpoly_rig.figure = null           # so that the shading changes without making the old figure's mesh again
	lowpoly_rig.flat_shading = flat
	lowpoly_rig.build(figure, Poses.get_pose(pose_name))       # posed as it is built: the cloth is laid once
	if first:
		fit_if_untouched()


func set_flat_shading(on: bool) -> void:
	lowpoly_rig.flat_shading = on


func set_pose(name: String) -> void:
	pose_name = name
	lowpoly_rig.apply_pose(name)


func handle_key(event: InputEvent) -> bool:
	return camera.handle_input(event)


# --------------------------------------------------------------- framing ---

func fit_view() -> void:
	if camera == null:
		return
	var pane := _container.size
	var aspect := 1.0 if pane.y <= 0.0 else pane.x / pane.y
	if showing_item:
		camera.frame(item_stage.bounds, aspect)
		return
	if lowpoly_rig == null or lowpoly_rig.figure == null:
		return
	camera.frame(lowpoly_rig.figure_aabb("head" if fit_mode == Fit.HEAD else ""), aspect)


func fit_if_untouched() -> void:
	if camera != null and camera.moved_by_user:
		return
	fit_view()


# ----------------------------------------------------------------- input ---

func _on_container_input(event: InputEvent) -> void:
	if showing_item:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_container.grab_focus()                  # so that Delete and the arrow keys come here, not to a text box
		var used := item_stage.handle_input(event)
		_container.mouse_default_cursor_shape = item_stage.cursor as Control.CursorShape
		_readout.visible = not item_stage.readout.is_empty()
		if _readout.visible and event is InputEventMouse:
			_readout.text = item_stage.readout
			_readout.reset_size()
			_readout.position = ((event as InputEventMouse).position + Vector2(18, 18)).min(
				_container.size - _readout.size - Vector2(4, 4)).max(Vector2(4, 4))
		if used:
			_container.accept_event()
			return
	if picking_enabled and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.shift_pressed:
			_pick_at(mb.position)
			_container.accept_event()
			return
	if camera.handle_input(event):
		_container.accept_event()


## Pick the region of the polygon under the pointer, in whatever pose the figure is in.
func _pick_at(screen_position: Vector2) -> void:
	var from := camera.project_ray_origin(screen_position)
	var into := lowpoly_rig.global_transform.affine_inverse()
	var i := lowpoly_rig.pick(into * from, into.basis * camera.project_ray_normal(screen_position))
	if i >= 0:
		var region := String(lowpoly_rig.figure.polygons[i]["region"])
		if not region.is_empty():
			region_picked.emit(region)


# ------------------------------------------------------------ an item alone ---

## Show a held item on its own, to be put together by hand (ItemStage): `selected` is the part chosen (-1 for none),
## `mode` an ItemStage.Mode. `refit`: frame it afresh (another item), keeping the way the camera looks.
func show_item(item: GarmentItem, colours: Dictionary, selected: int, mode: int, refit: bool = false) -> void:
	var first := not showing_item
	showing_item = true
	lowpoly_rig.visible = false
	_ground.visible = false
	item_stage.visible = true
	_container.focus_mode = Control.FOCUS_CLICK
	for bar in _toolbars:
		bar.visible = true
	item_stage.show_item(item, colours, selected, mode)
	if first:
		fit_if_untouched()
	elif refit:
		fit_view()


## A row of controls between the view buttons and the view, shown while an item is shown on its own.
func add_item_toolbar(bar: Control) -> void:
	add_child(bar)
	move_child(bar, _container.get_index())
	bar.visible = showing_item
	_toolbars.append(bar)
