@tool
class_name PreviewView
extends VBoxContainer

## One 3D preview: a figure, a camera you can orbit, the labelled view buttons,
## and optional region picking.
##
## Every workspace has its own, so cycling bodies in the Clothes tab does not
## disturb what the Bodies tab is looking at. Only the visible one renders.
##
## Mouse: left or middle drag orbits, right drag or shift+drag pans, wheel
## zooms. Number keys 1-6 pick the fixed views (the shell forwards them to
## whichever tab is showing).

signal region_picked(region: String)

## What "Fit" frames: the whole figure, or just the head.
enum Fit { FIGURE, HEAD }

var camera: OrbitCamera = null
var rig: CharacterRig = null
var assembled: CharacterAssembler.Assembled = null
var pose_name: String = Poses.REST
var fit_mode: int = Fit.FIGURE
var picking_enabled := false
var use_face_multiplier := true

var _container: SubViewportContainer = null
var _viewport: SubViewport = null
var _pick_toggle: CheckBox = null
var _buttons: HBoxContainer = null


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
		picking_enabled = on
		_build_pick_bodies())
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

	rig = CharacterRig.new()
	rig.name = "Figure"
	_viewport.add_child(rig)

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


## Offer "click to pick regions" -- the tabs that edit garments do.
func allow_picking(on: bool) -> void:
	_pick_toggle.visible = on
	if not on:
		picking_enabled = false
		_pick_toggle.button_pressed = false


## Assemble and show a figure. Returns what was assembled.
func show_request(request: CharacterAssembler.Request) -> CharacterAssembler.Assembled:
	request.use_face_multiplier = use_face_multiplier
	var first := assembled == null
	assembled = CharacterAssembler.assemble(request)
	rig.use_face_multiplier = use_face_multiplier
	rig.build(assembled)
	rig.apply_pose(pose_name)
	if picking_enabled:
		_build_pick_bodies()
	if first:
		fit_if_untouched()
	return assembled


func set_pose(name: String) -> void:
	pose_name = name
	rig.apply_pose(name)


func handle_key(event: InputEvent) -> bool:
	return camera.handle_input(event)


# --------------------------------------------------------------- framing ---

func fit_view() -> void:
	if camera == null or rig == null or rig.assembled == null:
		return
	var pane := _container.size
	var aspect := 1.0 if pane.y <= 0.0 else pane.x / pane.y
	var bounds := rig.figure_aabb()
	if fit_mode == Fit.HEAD:
		bounds = _part_aabb(BodyDef.HEAD_PART)
	camera.frame(bounds, aspect)


func fit_if_untouched() -> void:
	if camera != null and camera.moved_by_user:
		return
	fit_view()


## Bounds of one part in its rest position, padded so hair and hats fit.
func _part_aabb(part_name: String) -> AABB:
	if assembled == null or assembled.part(part_name) == null:
		return rig.figure_aabb()
	var cells: Dictionary = assembled.part(part_name).cells
	if cells.is_empty():
		return rig.figure_aabb()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for cell in cells.keys():
		var p := VoxelAxes.voxel_centre_to_godot(cell)
		lo = lo.min(p)
		hi = hi.max(p)
	var pad := Vector3.ONE * (VoxelAxes.VOXEL_SIZE * 3.0)
	return AABB(lo - pad, (hi - lo) + pad * 2.0)


# ----------------------------------------------------------------- input ---

func _on_container_input(event: InputEvent) -> void:
	if picking_enabled and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.shift_pressed:
			_pick_at(mb.position)
			_container.accept_event()
			return
	if camera.handle_input(event):
		_container.accept_event()


## Trimesh collision, built only while picking is on: it costs real time on a
## few thousand quads and most editing is done from the region list.
func _build_pick_bodies() -> void:
	if not picking_enabled:
		return
	for name in rig.mesh_instances.keys():
		var instance: MeshInstance3D = rig.mesh_instances[name]
		instance.create_trimesh_collision()


func _pick_at(screen_position: Vector2) -> void:
	var space := _viewport.world_3d.direct_space_state
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * 100.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return
	# The collision body hangs under the part's MeshInstance3D; walk up to the
	# joint, whose transform takes the point back to the part's own space.
	var node: Node = hit.get("collider")
	var part_name := ""
	while node != null:
		if rig.joints.has(node.name):
			part_name = String(node.name)
			break
		node = node.get_parent()
	if part_name.is_empty():
		return
	var part := assembled.part(part_name)
	if part == null:
		return
	var joint: Node3D = rig.joints[part_name]
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	# Step just inside the surface before converting to a voxel.
	var local := joint.global_transform.affine_inverse() * (
		(hit.get("position") as Vector3) - normal * (VoxelAxes.VOXEL_SIZE * 0.5))
	var asset := VoxelAxes.godot_to_point(local + VoxelAxes.point_to_godot(part.pivot))
	var cell := Vector3i(floori(asset.x), floori(asset.y), floori(asset.z))
	var region := String(part.regions.get(cell, ""))
	if not region.is_empty():
		region_picked.emit(region)
