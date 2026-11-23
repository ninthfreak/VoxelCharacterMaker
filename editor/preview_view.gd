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
## The Items tab shows a held item on its own instead of a figure (show_item): standing on a grid of one-unit squares,
## the chosen part's edges drawn over everything, and the grip marked.

signal region_picked(region: String)
## A part of the item shown was clicked (show_item): its number.
signal part_picked(part: int)

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
## The item shown on its own, and what goes with it (show_item); hidden while a figure is shown.
var _item_root: Node3D = null
var _item_polys: Array = []               ## [[Godot corners], part]
var _item_bounds := AABB()
var showing_item := false


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

	_item_root = Node3D.new()
	_item_root.name = "Item"
	_item_root.visible = false
	_viewport.add_child(_item_root)


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
	_item_root.visible = false
	lowpoly_rig.visible = true
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
		camera.frame(_item_bounds, aspect)
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
	if showing_item and event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.double_click:
			var part := _part_at(click.position)
			if part >= 0:
				part_picked.emit(part)
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

const ITEM_GRID := 12                       ## the grid reaches this many units each way from the middle
const ARROW_AHEAD := 4.0                    ## the grip's arrows, in units
const ARROW_UP := 2.5


## Show a held item on its own: `polys` from HeldItemShape.polygons, standing with its lowest point on the ground and
## its middle over the grid's. `selected` is a part number whose edges are drawn over everything (-1 for none); the
## grip is marked with an arrow the way the fist points ("ahead") and one the way its thumb does ("up"), and a second
## grip, if it has one, with a cross.
func show_item(polys: Array, selected: int, grip: Dictionary, second_grip: Dictionary) -> void:
	var first := not showing_item
	showing_item = true
	lowpoly_rig.visible = false
	_item_root.visible = true
	for child in _item_root.get_children():
		child.queue_free()
	_item_polys.clear()

	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for q in polys:
		var flat: PackedFloat64Array = q["pts"]
		for k in flat.size() / 3:
			var p := Vector3(flat[3 * k], flat[3 * k + 1], flat[3 * k + 2])
			lo = lo.min(p)
			hi = hi.max(p)
	if polys.is_empty():
		lo = Vector3(-1, -1, 0)
		hi = Vector3(1, 1, 2)
	# the item's own space to the view: its middle (across and in depth) over the grid's, its lowest point on the ground
	var lift := Vector3(-0.5 * (lo.x + hi.x), -0.5 * (lo.y + hi.y), -lo.z)
	var to_view := func(p: Vector3) -> Vector3:
		var q := p + lift
		return Vector3(-q.x, q.z, q.y) * FigureAxes.UNIT

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var edges := PackedVector3Array()
	for q in polys:
		var flat: PackedFloat64Array = q["pts"]
		var corners := PackedVector3Array()
		for k in flat.size() / 3:
			corners.push_back(to_view.call(Vector3(flat[3 * k], flat[3 * k + 1], flat[3 * k + 2])))
		_item_polys.append([corners, int(q["part"])])
		var n := Vector3.ZERO
		for k in corners.size():
			n += corners[k].cross(corners[(k + 1) % corners.size()])
		# the view's axes are a mirror image of the item's (x is turned round), so the item's outward faces come out
		# clockwise here, which is what Godot draws as their front: no reversing, unlike the rig's polygons
		n = -n.normalized()
		var base := verts.size()
		for c in corners:
			verts.push_back(c)
			normals.push_back(n)
			colours.push_back(q["colour"])
		for i in range(1, corners.size() - 1):
			indices.append_array(PackedInt32Array([base, base + i, base + i + 1]))
		if int(q["part"]) == selected:
			for k in corners.size():
				edges.push_back(corners[k])
				edges.push_back(corners[(k + 1) % corners.size()])
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.material_override = lowpoly_rig.material()
		_item_root.add_child(body)
	_lines(edges, Color.WHITE)

	# the grid: one-unit squares, the middle lines brighter, and the front marked
	var grid := PackedVector3Array()
	var middle := PackedVector3Array()
	for i in range(-ITEM_GRID, ITEM_GRID + 1):
		var a := Vector3(i, -ITEM_GRID, 0) * FigureAxes.UNIT
		var b := Vector3(i, ITEM_GRID, 0) * FigureAxes.UNIT
		var c := Vector3(-ITEM_GRID, i, 0) * FigureAxes.UNIT
		var d := Vector3(ITEM_GRID, i, 0) * FigureAxes.UNIT
		var target := middle if i == 0 else grid
		target.append_array(PackedVector3Array([Vector3(a.x, 0.0005, a.y), Vector3(b.x, 0.0005, b.y),
			Vector3(c.x, 0.0005, c.y), Vector3(d.x, 0.0005, d.y)]))
	_lines(grid, Color8(70, 78, 96), true)
	_lines(middle, Color8(120, 130, 150), true)
	_label("front", Vector3(0, 0.002, -(ITEM_GRID + 1.5) * FigureAxes.UNIT), Color8(160, 168, 184))

	# the grip: where the hand closes, the way the fist points and the way its thumb does
	var turn := HeldItemShape.turn(grip.get("rotation", [0, 0, 0]))
	var at_: Array = grip.get("position", [0, 0, 0])
	var g := Vector3(float(at_[0]), float(at_[1]), float(at_[2]))
	var ahead := Vec64.to_vector3(Vec64.apply(turn, Vec64.v(0, 0, 1)))
	var up := Vec64.to_vector3(Vec64.apply(turn, Vec64.v(-1, 0, 0)))
	var shown: Array = [lo, hi]
	if not grip.is_empty():
		_arrow(to_view.call(g), to_view.call(g + ahead * ARROW_AHEAD), Palette.UI_SKY, "ahead")
		_arrow(to_view.call(g), to_view.call(g + up * ARROW_UP), Palette.UI_ORANGE, "up")
		shown += [g + ahead * (ARROW_AHEAD + 1.5), g + up * (ARROW_UP + 1.5)]
	if not second_grip.is_empty():
		var s2: Array = second_grip.get("position", [0, 0, 0])
		var g2 := Vector3(float(s2[0]), float(s2[1]), float(s2[2]))
		var cross := PackedVector3Array()
		for axis in [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP]:
			cross.push_back(to_view.call(g2 - axis * 0.75))
			cross.push_back(to_view.call(g2 + axis * 0.75))
		_lines(cross, Palette.UI_SKY)
		_label("2nd hand", to_view.call(g2 + Vector3(0, 0, 1.2)), Palette.UI_SKY)

	# framed to show the item and the grip's arrows with their words
	var box_lo := Vector3(INF, INF, INF)
	var box_hi := Vector3(-INF, -INF, -INF)
	for p in shown:
		var v: Vector3 = to_view.call(p)
		box_lo = box_lo.min(v)
		box_hi = box_hi.max(v)
	_item_bounds = AABB(box_lo, box_hi - box_lo)
	if first:
		fit_if_untouched()


## Lines between pairs of points, drawn over everything unless `in_scene`.
func _lines(points: PackedVector3Array, colour: Color, in_scene: bool = false) -> void:
	if points.is_empty():
		return
	var mesh := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	m.no_depth_test = not in_scene
	m.render_priority = 0 if in_scene else 10
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, m)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = mesh
	_item_root.add_child(lines)


## A solid arrow (a thin square shaft and a pointed head), drawn over everything, with a word at its tip.
func _arrow(from: Vector3, to: Vector3, colour: Color, text: String) -> void:
	var along := (to - from).normalized()
	var u := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := along.cross(u)
	var shaft := 0.15 * FigureAxes.UNIT
	var head := 0.45 * FigureAxes.UNIT
	var back := to - along * 1.0 * FigureAxes.UNIT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := func(at: Vector3, r: float) -> Array:
		return [at + (u + v) * r, at + (u - v) * r, at - (u + v) * r, at - (u - v) * r]
	var a: Array = ring.call(from, shaft)
	var b: Array = ring.call(back, shaft)
	var c: Array = ring.call(back, head)
	for k in 4:
		for p in [a[k], a[(k + 1) % 4], b[(k + 1) % 4], a[k], b[(k + 1) % 4], b[k], c[k], c[(k + 1) % 4], to]:
			st.add_vertex(p)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	m.no_depth_test = true
	m.render_priority = 10
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arrow := MeshInstance3D.new()
	arrow.mesh = st.commit()
	arrow.material_override = m
	_item_root.add_child(arrow)
	_label(text, to + along * 0.03, colour)


func _label(text: String, at: Vector3, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 18
	label.outline_size = 6
	label.modulate = colour
	_item_root.add_child(label)


## The part under the pointer, nearest the camera: its number, or -1.
func _part_at(screen_position: Vector2) -> int:
	var from := camera.project_ray_origin(screen_position)
	var dir := camera.project_ray_normal(screen_position)
	var best := INF
	var hit := -1
	for entry in _item_polys:
		var c: PackedVector3Array = entry[0]
		for j in range(1, c.size() - 1):
			var t := LowpolyRig._ray_triangle(from, dir, c[0], c[j], c[j + 1])
			if t > 0.0 and t < best:
				best = t
				hit = int(entry[1])
	return hit
