@tool
class_name ItemStage
extends Node3D

## A held item on its own in a PreviewView, put together by hand (the Items tab; SPEC.md section 8).
##
## The item stands where its own space puts it: its middle (x 0, y 0) over the grid's brighter middle lines, the grid
## lying under its lowest point. Nothing jumps as a part is dragged: only the grid goes down or up, once the drag is over.
##
## One rule for every drag: it moves flat to the view being faced. The FACING AXIS is the item's axis the camera
## looks along most (front or back: its depth, y; from a side: x; from above: z); a part dragged slides in the
## plane across it, and the turning ring turns about it.
##
##   PARTS   click a part to choose it; drag it to move it. The chosen part has a square on four of its sides, those
##           not seen end on (w, d, h: pull one and that side moves, the opposite side stays; with Shift held the part
##           keeps its shape, every size changing together about its middle), a ring to turn it, and two lines through
##           its middle that say which way a drag goes (x, y, z). Shift+click chooses more parts (or lets one go):
##           a drag, the arrow keys, Delete and copying then work on all of them; the squares and the ring stay on
##           the one clicked last. The part under the pointer is outlined before it is clicked.
##   GRIP    the forearm and hand that will hold the item are shown at its grip: drag the hand (or the diamond at the
##           grip) to move the grip, the ring to turn it.
##
## Everything goes in steps of a quarter unit and 15 degrees: items are a handful of parts and small in the game, so
## nothing finer is offered by hand (the panels' numbers take any value). A move steps from where the part is, so
## its sides stay on the grid they were on (snapping its middle to the grid knocked them off it by an eighth after
## one side had been pulled). Escape gives up a drag; Delete removes the chosen
## part; the arrow keys nudge it. Copy, cut and paste are the tab's (Ctrl+C, Ctrl+X, Ctrl+V).
## Told apart by shape and a letter, never by red against green: squares resize, the ring turns, a diamond is a grip.
##
## The stage changes the item itself while a drag goes on (`edited`: the panels follow) and says when the drag is
## over (`edit_finished`: one undo step for whoever owns the wardrobe).

## What is chosen changed here: the part with the handles, and the others chosen with it.
signal selection_changed(part: int, also: Array)
signal edited
signal edit_finished(label: String, merge: bool)
signal delete_requested

enum Mode { PARTS, GRIP }
enum Grab { NONE, PART, SIZE, TURN, GRIP, GRIP_TURN }

const GRID := 12                    ## the grid reaches this many units each way from the middle
const SNAP := 0.25
const TURN_SNAP := 15.0
const PLACES := 0.001               ## what a place or a size is kept to (the panels' number boxes show as much)
const HANDLE_PX := 10.0             ## half a square handle, in pixels
const HANDLE_OUT_PX := 20.0         ## how far off the part's side a handle sits
const RING_PX := 78.0               ## the turning ring's radius
const GUIDE_PX := 112.0             ## how far the two guide lines reach from the part's middle
const NEAR_PX := 13.0               ## how close to a handle counts as on it
const RING_NEAR_PX := 6.0
const DRAG_PX := 4.0                ## a press becomes a drag once the pointer has gone this far
const END_ON := 0.8                 ## a side whose way lies this close to the line of sight (a cosine) has no handle
const ARROW_AHEAD := 4.0            ## the grip's arrows, in units
const ARROW_UP := 2.5
const TEXT_SCALE := 1.3              ## a label's letters: this many screen pixels to a pixel of its font size
const AXES: Array[String] = ["x", "y", "z"]
const SIZES: Array[String] = ["w", "d", "h"]
const SIZE_WORDS: Array[String] = ["width", "depth", "height"]

var camera: Camera3D = null
## The figure's material (LowpolyRig.material()): the item is lit as a figure is.
var body_material: Material = null
var item: GarmentItem = null
var colours: Dictionary = {}
var selected: int = -1
## The other parts chosen along with `selected` (Shift+click): moved, nudged, deleted and copied with it.
var also: Array = []
var mode: int = Mode.PARTS
## The forearm and hand that hold the item, in the hand's own frame (the palm at 0; HeldItemShape.RIGHT_HAND undone):
## Array of [corners (PackedVector3Array), whether it is of the hand itself (not the forearm above it)]. hand_of()
## makes it. With parts being edited only the hand is shown, for size; with the grip being edited, the forearm too,
## which is what says how the item will lie along the arm.
var hand: Array = []
## What a drag is doing, in words, for the view to show by the pointer ("" when nothing is dragged).
var readout := ""
## The cursor for what the pointer is over (Control.CURSOR_*).
var cursor: int = Control.CURSOR_ARROW
## What the camera should frame (Godot space).
var bounds := AABB(Vector3(-0.05, 0, -0.05), Vector3(0.1, 0.1, 0.1))

var _scene: Node3D = null
var _gizmo: MeshInstance3D = null
var _letters: Array[Label3D] = []
var _polys: Array = []              ## [corners (item space), part, mirrored]
var _hand_polys: Array = []         ## the hand's polygons where it is drawn (item space)
var _floor := 0.0
var _handles: Array = []            ## {axis, sign, view}
var _ring := {}                     ## {centre (view), radius, axis} or {}
var _knobs: Array = []              ## {grab, view}
var _press := {}
var _dragging := false
var _changed := false
var _hover := {}
var _hover_edges := 0               ## how many edges of the part under the pointer are drawn (for the tests)
var _seen_zoom := 0.0
var _seen := Transform3D()
var _seen_size := Vector2.ZERO

static var _materials := {}


func _init() -> void:
	_scene = Node3D.new()
	add_child(_scene)
	_gizmo = MeshInstance3D.new()
	_gizmo.mesh = ImmediateMesh.new()
	add_child(_gizmo)
	for i in 10:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 18
		label.outline_size = 5
		label.render_priority = 12
		label.outline_render_priority = 11
		label.visible = false
		add_child(label)
		_letters.append(label)


## Item space (x across, y depth with the front at -y, z up, in units) to the view's, and back.
static func to_view(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.z, p.y) * FigureAxes.UNIT


static func to_item(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.z, v.y) / FigureAxes.UNIT


## The forearm and hand of a body, for `hand`.
static func hand_of(library: LowpolyLibrary, body_id: String) -> Array:
	var f := LowpolyFigure.make(library, body_id, "round", Palette.SKIN_MID)
	if f == null:
		return []
	var palm := HeldItemShape.palm(f, RegionMap.SIDE_RIGHT)
	var back := Vec64.transpose(PackedFloat64Array(HeldItemShape.RIGHT_HAND))
	var out: Array = []
	for poly in f.polygons:
		if String(poly["part"]) != "forearm_R" or bool(poly["hidden"]):
			continue
		var pts := PackedVector3Array()
		for k in poly["corners"]:
			pts.push_back(Vec64.to_vector3(Vec64.apply(back, Vec64.sub(f.point64(k), palm))))
		out.append([pts, RegionMap.key_band(String(poly["region"])) in ["hand", "wrist"]])
	return out


func show_item(p_item: GarmentItem, p_colours: Dictionary, p_selected: int, p_mode: int, p_also: Array = []) -> void:
	item = p_item
	colours = p_colours
	selected = p_selected
	also = p_also.duplicate()
	mode = p_mode
	if item == null:
		_press = {}
		_dragging = false
	redraw()


func is_dragging() -> bool:
	return _dragging


func polygon_count() -> int:
	return _polys.size()


## Every part chosen: the one with the handles first, then the others; only parts the item has.
func chosen() -> Array:
	var out: Array = []
	if item == null:
		return out
	for i in [selected] + also:
		if int(i) >= 0 and int(i) < item.parts.size() and not out.has(int(i)):
			out.append(int(i))
	return out


## The chosen part (the one with the handles), or null.
func _part() -> Variant:
	if item == null or selected < 0 or selected >= item.parts.size():
		return null
	return item.parts[selected]


static func _clean(v: float, step: float) -> float:
	var r := snappedf(v, step)
	return 0.0 if r == 0.0 else r


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A turn's axis `i` (0 x, 1 y, 2 z) in the item's space: where the part's own x, y or z points.
static func _column(m: PackedFloat64Array, i: int) -> Vector3:
	return Vector3(m[i], m[3 + i], m[6 + i])


## The turn [forward, sideways, round], in degrees, that HeldItemShape.turn makes this matrix from. There are two;
## this is the one that turns less forward and round (a part turned 120 sideways reads 0, 120, 0, not 180, 60, 180).
static func euler_of(m: PackedFloat64Array) -> Array:
	var sb := clampf(-m[6], -1.0, 1.0)
	var a := 0.0
	var b := 0.0
	var c := 0.0
	if absf(sb) > 0.9999995:
		b = 90.0 * signf(sb)
		a = rad_to_deg(atan2(-m[5], m[4]))
	else:
		b = rad_to_deg(asin(sb))
		a = rad_to_deg(atan2(m[7], m[8]))
		c = rad_to_deg(atan2(m[3], m[0]))
		var a2 := wrapf(a + 180.0, -180.0, 180.0)
		var b2 := wrapf(180.0 - b, -180.0, 180.0)
		var c2 := wrapf(c + 180.0, -180.0, 180.0)
		if absf(a2) + absf(c2) < absf(a) + absf(c) - 1e-6:
			a = a2
			b = b2
			c = c2
	return [_clean(a, 0.01), _clean(b, 0.01), _clean(c, 0.01)]


## A turn by `degrees` about the item's axis `axis`, put on top of a turn [forward, sideways, round].
static func turned(rotation: Array, axis: int, degrees: float) -> Array:
	if degrees == 0.0:
		return rotation.duplicate()
	var about := Vec64.rx(degrees) if axis == 0 else (Vec64.ry(degrees) if axis == 1 else Vec64.rz(degrees))
	return euler_of(Vec64.matmul(about, HeldItemShape.turn(rotation)))


# -------------------------------------------------------------------------------------------- drawing ---

static func _material(colour: Color, priority: int, over: bool = true) -> StandardMaterial3D:
	var key := "%s/%d/%s" % [colour.to_html(), priority, over]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colour
		m.no_depth_test = over
		m.render_priority = priority
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if colour.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materials[key] = m
	return _materials[key]


## Draw the item, the grid under it, the hand, and the handles of what is chosen.
func redraw() -> void:
	for child in _scene.get_children():
		_scene.remove_child(child)
		child.queue_free()
	_polys.clear()
	_hand_polys.clear()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var shades := PackedColorArray()
	var indices := PackedInt32Array()
	var edges := PackedVector3Array()
	for q in (HeldItemShape.polygons(item, colours) if item != null else []):
		var flat: PackedFloat64Array = q["pts"]
		var own := PackedVector3Array()
		var corners := PackedVector3Array()
		for k in flat.size() / 3:
			var p := Vector3(flat[3 * k], flat[3 * k + 1], flat[3 * k + 2])
			own.push_back(p)
			corners.push_back(to_view(p))
			lo = lo.min(p)
			hi = hi.max(p)
		_polys.append([own, int(q["part"]), bool(q["mirrored"])])
		_add_polygon(verts, normals, shades, indices, corners, q["colour"])
		if mode == Mode.PARTS and (int(q["part"]) == selected or also.has(int(q["part"]))):
			for k in corners.size():
				edges.push_back(corners[k])
				edges.push_back(corners[(k + 1) % corners.size()])
	if _polys.is_empty():
		lo = Vector3(-1, -1, 0)
		hi = Vector3(1, 1, 2)
	_add_mesh(verts, normals, shades, indices, body_material)
	_add_lines(edges, _material(Color.WHITE, 9))

	if not _dragging:
		_floor = floorf(lo.z + 1e-6)
	var grid := PackedVector3Array()
	var middle := PackedVector3Array()
	var y := _floor * FigureAxes.UNIT - 0.0005
	var reach := GRID * FigureAxes.UNIT
	for i in range(-GRID, GRID + 1):
		var at := i * FigureAxes.UNIT
		var target := middle if i == 0 else grid
		target.append_array(PackedVector3Array([Vector3(at, y, -reach), Vector3(at, y, reach), Vector3(-reach, y, at),
			Vector3(reach, y, at)]))
	_add_lines(grid, _material(Color8(70, 78, 96), 0, false))
	_add_lines(middle, _material(Color8(128, 138, 160), 0, false))
	_add_label("front", Vector3(0, y, -(GRID + 1.5) * FigureAxes.UNIT), Color8(160, 168, 184))

	if item != null:
		_draw_hand()
		if mode == Mode.GRIP:
			_draw_grip_marks()
		var g := _vec(item.grip["position"])
		lo = lo.min(g)
		hi = hi.max(g)
	var a := to_view(lo - Vector3.ONE)
	var b := to_view(hi + Vector3.ONE)
	bounds = AABB(a.min(b), (b - a).abs())
	_layout()


static func _add_polygon(verts: PackedVector3Array, normals: PackedVector3Array, shades: PackedColorArray,
		indices: PackedInt32Array, corners: PackedVector3Array, colour: Color) -> void:
	var n := Vector3.ZERO
	for k in corners.size():
		n += corners[k].cross(corners[(k + 1) % corners.size()])
	# the view's axes are a mirror image of the item's (x is turned round), so a face that is outward in the item's
	# space comes out clockwise here, which is what Godot draws as its front
	n = -n.normalized()
	var base := verts.size()
	for c in corners:
		verts.push_back(c)
		normals.push_back(n)
		shades.push_back(colour)
	for i in range(1, corners.size() - 1):
		indices.append_array(PackedInt32Array([base, base + i, base + i + 1]))


func _add_mesh(verts: PackedVector3Array, normals: PackedVector3Array, shades: PackedColorArray,
		indices: PackedInt32Array, material: Material) -> void:
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = shades
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	_scene.add_child(node)


func _add_lines(points: PackedVector3Array, material: Material) -> void:
	if points.is_empty():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = mesh
	_scene.add_child(lines)


func _add_label(text: String, at: Vector3, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 18
	label.outline_size = 6
	label.modulate = colour
	_scene.add_child(label)                              # _layout gives it its size on the screen


## The forearm and hand at the grip, see-through: what will hold the item, and how big a hand is.
func _draw_hand() -> void:
	if hand.is_empty():
		return
	var turn := HeldItemShape.turn(item.grip["rotation"])
	var g := _vec(item.grip["position"])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var shades := PackedColorArray()
	var indices := PackedInt32Array()
	var light := Vector3(-0.45, 0.6, -0.65).normalized()
	for poly in hand:
		if mode != Mode.GRIP and not bool(poly[1]):
			continue
		var own := PackedVector3Array()
		var corners := PackedVector3Array()
		for q in (poly[0] as PackedVector3Array):
			var p := g + Vec64.to_vector3(Vec64.apply(turn, Vec64.of(q)))
			own.push_back(p)
			corners.push_back(to_view(p))
		_hand_polys.append(own)
		var first := verts.size()
		_add_polygon(verts, normals, shades, indices, corners, Color.WHITE)
		var shade := 0.62 + 0.38 * maxf(0.0, normals[first].dot(light))
		for k in range(first, verts.size()):
			shades[k] = Color(Palette.SKIN_MID.r * shade, Palette.SKIN_MID.g * shade, Palette.SKIN_MID.b * shade,
				0.5 if mode == Mode.GRIP else 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_add_mesh(verts, normals, shades, indices, m)


## The grip's two arrows: the way the fist points and the way its thumb does.
func _draw_grip_marks() -> void:
	var turn := HeldItemShape.turn(item.grip["rotation"])
	var g := _vec(item.grip["position"])
	var ahead := Vec64.to_vector3(Vec64.apply(turn, Vec64.v(0, 0, 1)))
	var up := Vec64.to_vector3(Vec64.apply(turn, Vec64.v(-1, 0, 0)))
	_add_arrow(to_view(g), to_view(g + ahead * ARROW_AHEAD), Palette.UI_SKY, "ahead")
	_add_arrow(to_view(g), to_view(g + up * ARROW_UP), Palette.UI_ORANGE, "up")


## A solid arrow (a thin square shaft and a pointed head), drawn over everything, with a word at its tip.
func _add_arrow(from: Vector3, to: Vector3, colour: Color, text: String) -> void:
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
	var arrow := MeshInstance3D.new()
	arrow.mesh = st.commit()
	arrow.material_override = _material(colour, 8)
	_scene.add_child(arrow)
	_add_label(text, to + along * 0.03, colour)


# -------------------------------------------------------------------------------------------- handles ---

func _process(_delta: float) -> void:
	if camera == null or not is_visible_in_tree():
		return
	var size := _view_size()
	if not camera.global_transform.is_equal_approx(_seen) or size != _seen_size or _zoom() != _seen_zoom:
		_layout()


func _view_size() -> Vector2:
	var viewport := camera.get_viewport() if camera != null and camera.is_inside_tree() else null
	return viewport.get_visible_rect().size if viewport != null else Vector2(800, 600)


## What says how far in a flat view is zoomed (its transform does not): 0 for a view in perspective.
func _zoom() -> float:
	return camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 0.0


## How much of the view's space one pixel covers at a point.
func _per_pixel(at: Vector3) -> float:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return camera.size / maxf(_view_size().y, 1.0)
	var depth := (at - camera.global_position).dot(-camera.global_transform.basis.z)
	return 2.0 * maxf(depth, 0.01) * tan(deg_to_rad(camera.fov) * 0.5) / maxf(_view_size().y, 1.0)


## The item's axis the camera looks along most: 0 x, 1 y, 2 z.
func facing() -> int:
	if camera == null:
		return 1
	var look := to_item(-camera.global_transform.basis.z).abs()
	return look.max_axis_index()


## The handles of what is chosen, sized for the camera as it stands: squares, ring and guide lines for a part; the
## diamond and ring of the grip.
func _layout() -> void:
	var mesh := _gizmo.mesh as ImmediateMesh
	mesh.clear_surfaces()
	_handles.clear()
	_knobs.clear()
	_ring = {}
	for label in _letters:
		label.visible = false
	if camera == null or item == null or not camera.is_inside_tree():
		return
	_seen = camera.global_transform
	_seen_size = _view_size()
	_seen_zoom = _zoom()
	# words keep one size on the screen, in perspective and flat alike (Label3D's own "fixed size" is tiny in a
	# flat view): each is given the size a pixel has where it stands
	for child in _scene.get_children():
		if child is Label3D:
			(child as Label3D).pixel_size = TEXT_SCALE * _per_pixel((child as Label3D).position)
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	var dark := PackedVector3Array()
	var white := PackedVector3Array()
	var hot := PackedVector3Array()
	var orange := PackedVector3Array()
	var guides := PackedVector3Array()
	var letter := 0
	var axis := int(_press["axis"]) if _press.has("axis") else facing()
	var over := _press if not _press.is_empty() else _hover

	var part: Variant = _part()
	if mode == Mode.PARTS and part != null:
		var p: Dictionary = part
		var turn := HeldItemShape.turn(p["rotation"])
		var middle := _vec(p["position"])
		var at := to_view(middle)
		var px := _per_pixel(at)
		# two lines through its middle, along the two ways a drag goes, reaching past the part and its squares
		for j in 3:
			if j == axis:
				continue
			var way := Vector3.ZERO
			way[j] = 1.0
			var half := 0.0                          # how far the part reaches along this way
			for i in 3:
				half += absf(_column(turn, i)[j]) * 0.5 * float(p["size"][i])
			var length := maxf(GUIDE_PX * px, half * FigureAxes.UNIT + (HANDLE_OUT_PX + 2.0 * HANDLE_PX + 16.0) * px)
			var reach := (to_view(way) / FigureAxes.UNIT) * length
			guides.append_array(PackedVector3Array([at - reach, at + reach]))
			letter = _letter(letter, AXES[j], at + reach + reach.normalized() * 10.0 * px, Palette.UI_SKY)
		# a square on four of its sides: not on the two seen most end on (their squares would sit on the part, and
		# a pull along the line of sight goes nowhere). Turn the view to reach those.
		var look := -camera.global_transform.basis.z
		var end_on := 0
		var most := -1.0
		var along: Array[float] = []
		for i in 3:
			along.append(absf((to_view(_column(turn, i)) / FigureAxes.UNIT).normalized().dot(look)))
			if along[i] > most:
				most = along[i]
				end_on = i
		for i in 3:
			if i == end_on or along[i] > END_ON:
				continue
			for s: float in [1.0, -1.0]:
				var out := (to_view(_column(turn, i)) / FigureAxes.UNIT).normalized() * s
				var spot := to_view(middle + _column(turn, i) * s * 0.5 * float(p["size"][i]))
				spot += out * HANDLE_OUT_PX * _per_pixel(spot)
				var here := _is(over, Grab.SIZE) and int(over["side"]) == i and float(over["sign"]) == s
				var half := HANDLE_PX * _per_pixel(spot)
				_quad(dark, spot, half * 1.3, right, up, false)
				_quad(hot if here else white, spot, half, right, up, false)
				letter = _letter(letter, SIZES[i], spot, Color8(20, 24, 32), 16, false)
				_handles.append({"axis": i, "sign": s, "view": spot})
		# the turning ring, about the way the camera looks
		var radius := RING_PX * px
		_ring = {"centre": at, "radius": radius, "axis": axis}
		_band(dark, at, radius, 3.5 * px, axis)
		_band(hot if _is(over, Grab.TURN) else orange, at, radius, 2.0 * px, axis)
		letter = _letter(letter, "turn", at + (right - up) * 0.7071 * (radius + 22.0 * px), Palette.UI_ORANGE)
	elif mode == Mode.GRIP:
		var at := to_view(_vec(item.grip["position"]))
		var px := _per_pixel(at)
		var radius := RING_PX * px
		_ring = {"centre": at, "radius": radius, "axis": axis}
		_band(dark, at, radius, 3.5 * px, axis)
		_band(hot if _is(over, Grab.GRIP_TURN) else orange, at, radius, 2.0 * px, axis)
		letter = _letter(letter, "turn", at + (right + up) * 0.7071 * (radius + 22.0 * px), Palette.UI_ORANGE)
		_quad(dark, at, 1.3 * HANDLE_PX * px, right, up, true)
		_quad(hot if _is(over, Grab.GRIP) else white, at, HANDLE_PX * px, right, up, true)
		letter = _letter(letter, "grip", at - up * 24.0 * px, Color.WHITE)
		_knobs.append({"grab": Grab.GRIP, "view": at})

	# the part under the pointer, outlined before it is clicked (not one already chosen: it has its edges)
	var outline := PackedVector3Array()
	if mode == Mode.PARTS and _press.is_empty() and _is(_hover, Grab.PART) and not chosen().has(int(_hover["part"])):
		for entry in _polys:
			if int(entry[1]) != int(_hover["part"]):
				continue
			var c: PackedVector3Array = entry[0]
			for k in c.size():
				outline.push_back(to_view(c[k]))
				outline.push_back(to_view(c[(k + 1) % c.size()]))
	_hover_edges = outline.size() / 2
	_surface(mesh, Mesh.PRIMITIVE_LINES, outline, _material(Palette.UI_YELLOW, 9))
	_surface(mesh, Mesh.PRIMITIVE_LINES, guides, _material(Palette.UI_SKY, 9))
	_surface(mesh, Mesh.PRIMITIVE_TRIANGLES, dark, _material(Color8(16, 18, 26), 10))
	_surface(mesh, Mesh.PRIMITIVE_TRIANGLES, white, _material(Color.WHITE, 11))
	_surface(mesh, Mesh.PRIMITIVE_TRIANGLES, orange, _material(Palette.UI_ORANGE, 11))
	_surface(mesh, Mesh.PRIMITIVE_TRIANGLES, hot, _material(Palette.UI_YELLOW, 11))


static func _is(what: Dictionary, grab: int) -> bool:
	return int(what.get("grab", Grab.NONE)) == grab


static func _surface(mesh: ImmediateMesh, primitive: int, points: PackedVector3Array, material: Material) -> void:
	if points.is_empty():
		return
	mesh.surface_begin(primitive, material)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()


## A square facing the camera (or, `diamond`, one stood on its corner): two triangles.
static func _quad(into: PackedVector3Array, at: Vector3, half: float, right: Vector3, up: Vector3, diamond: bool) -> void:
	var a := (right * 1.35 if diamond else right + up) * half
	var b := (up * 1.35 if diamond else up - right) * half
	into.append_array(PackedVector3Array([at + a, at + b, at - a, at + a, at - a, at - b]))


## A ring about one of the item's axes, as a flat band.
func _band(into: PackedVector3Array, centre: Vector3, radius: float, half_width: float, axis: int) -> void:
	var u := Vector3.ZERO
	var v := Vector3.ZERO
	u[(axis + 1) % 3] = 1.0
	v[(axis + 2) % 3] = 1.0
	var uu := to_view(u) / FigureAxes.UNIT
	var vv := to_view(v) / FigureAxes.UNIT
	var steps := 64
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		var d0 := uu * cos(a0) + vv * sin(a0)
		var d1 := uu * cos(a1) + vv * sin(a1)
		var inner0 := centre + d0 * (radius - half_width)
		var outer0 := centre + d0 * (radius + half_width)
		var inner1 := centre + d1 * (radius - half_width)
		var outer1 := centre + d1 * (radius + half_width)
		into.append_array(PackedVector3Array([inner0, outer0, outer1, inner0, outer1, inner1]))


func _letter(index: int, text: String, at: Vector3, colour: Color, size: int = 18, outlined: bool = true) -> int:
	if index >= _letters.size():
		return index
	var label := _letters[index]
	label.text = text
	label.position = at
	label.pixel_size = TEXT_SCALE * _per_pixel(at)
	label.modulate = colour
	label.font_size = size
	label.outline_size = 5 if outlined else 0
	label.visible = true
	return index + 1


# ---------------------------------------------------------------------------------------------- input ---

func _ray(at: Vector2) -> Array:
	return [to_item(camera.project_ray_origin(at)), to_item(camera.project_ray_normal(at)).normalized()]


## Where the pointer's ray meets the plane across one of the item's axes, through a point; null if it runs along it.
func _on_plane(at: Vector2, through: Vector3, axis: int) -> Variant:
	var ray := _ray(at)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	if absf(d[axis]) < 1e-5:
		return null
	return o + d * ((through[axis] - o[axis]) / d[axis])


## How far along a line (from a point, a unit way) the pointer's ray comes closest; NAN if they run the same way.
func _along(at: Vector2, from: Vector3, way: Vector3) -> float:
	var ray := _ray(at)
	var w: Vector3 = from - (ray[0] as Vector3)
	var b := way.dot(ray[1])
	var denom := 1.0 - b * b
	if denom < 0.02:
		return NAN
	return (b * (ray[1] as Vector3).dot(w) - way.dot(w)) / denom


func _screen(view_point: Vector3) -> Vector2:
	return camera.unproject_position(view_point)


## The nearest polygon of `polys` (each [corners, ...] or corners) the pointer's ray meets: [index, where], or [].
func _under(at: Vector2, polys: Array) -> Array:
	var ray := _ray(at)
	var best := INF
	var hit := -1
	for i in polys.size():
		var c: PackedVector3Array = polys[i][0] if polys[i] is Array else polys[i]
		for j in range(1, c.size() - 1):
			var t := LowpolyRig._ray_triangle(ray[0], ray[1], c[0], c[j], c[j + 1])
			if t > 0.0 and t < best:
				best = t
				hit = i
	return [] if hit < 0 else [hit, (ray[0] as Vector3) + (ray[1] as Vector3) * best]


func _near_ring(at: Vector2) -> bool:
	if _ring.is_empty():
		return false
	var u := Vector3.ZERO
	var v := Vector3.ZERO
	u[(int(_ring["axis"]) + 1) % 3] = 1.0
	v[(int(_ring["axis"]) + 2) % 3] = 1.0
	var uu := to_view(u) / FigureAxes.UNIT
	var vv := to_view(v) / FigureAxes.UNIT
	var centre: Vector3 = _ring["centre"]
	var radius := float(_ring["radius"])
	var steps := 48
	var last := _screen(centre + uu * radius)
	for i in range(1, steps + 1):
		var a := TAU * i / steps
		var here := _screen(centre + (uu * cos(a) + vv * sin(a)) * radius)
		if Geometry2D.get_closest_point_to_segment(at, last, here).distance_to(at) <= RING_NEAR_PX:
			return true
		last = here
	return false


## What the pointer is on: {grab, ...}. Handles first, then the ring, then a part (or the hand).
func _hit(at: Vector2) -> Dictionary:
	if camera == null or item == null or not camera.is_inside_tree():
		return {"grab": Grab.NONE}
	for knob in _knobs:
		if _screen(knob["view"]).distance_to(at) <= NEAR_PX * 1.2:
			return {"grab": int(knob["grab"])}
	var nearest := NEAR_PX
	var handle := {}
	for h in _handles:
		var d := _screen(h["view"]).distance_to(at)
		if d <= nearest:
			nearest = d
			handle = h
	if not handle.is_empty():
		return {"grab": Grab.SIZE, "side": int(handle["axis"]), "sign": float(handle["sign"])}
	if _near_ring(at):
		return {"grab": Grab.GRIP_TURN if mode == Mode.GRIP else Grab.TURN}
	if mode == Mode.GRIP:
		var on_hand := _under(at, _hand_polys)
		return {"grab": Grab.GRIP, "at": on_hand[1]} if not on_hand.is_empty() else {"grab": Grab.NONE}
	var on := _under(at, _polys)
	if on.is_empty():
		return {"grab": Grab.NONE}
	return {"grab": Grab.PART, "part": int(_polys[on[0]][1]), "mirrored": bool(_polys[on[0]][2]), "at": on[1]}


## The view's input, before the camera takes it. Returns whether it was used here.
func handle_input(event: InputEvent) -> bool:
	if camera == null or item == null or not camera.is_inside_tree():
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			var hit := _hit(mb.position)
			if _is(hit, Grab.NONE):
				return false                               # empty space: the camera turns (with Shift, slides)
			_begin(hit, mb.position, mb.shift_pressed)
			return true
		if _press.is_empty():
			return false
		_end()
		return true
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press.is_empty():
			if mm.button_mask == 0:
				_point_at(_hit(mm.position))
			return false
		if not _dragging and mm.position.distance_to(_press["from"]) < DRAG_PX:
			return true
		_dragging = true
		_drag_to(mm.position, mm.shift_pressed)
		return true
	if event is InputEventKey:
		return _key(event as InputEventKey)
	return false


func _point_at(hit: Dictionary) -> void:
	match int(hit["grab"]):
		Grab.NONE: cursor = Control.CURSOR_ARROW
		Grab.PART: cursor = Control.CURSOR_MOVE if chosen().has(int(hit["part"])) else Control.CURSOR_POINTING_HAND
		Grab.GRIP: cursor = Control.CURSOR_MOVE
		_: cursor = Control.CURSOR_DRAG
	var slim := hit.duplicate()
	slim.erase("at")
	if slim != _hover:
		_hover = slim
		_layout()


func _begin(hit: Dictionary, from: Vector2, shift: bool = false) -> void:
	_press = hit.duplicate()
	_press["from"] = from
	_press["axis"] = facing()
	_dragging = false
	_changed = false
	match int(hit["grab"]):
		Grab.PART:
			var p := int(hit["part"])
			if shift:
				_toggle(p)
			elif not chosen().has(p):
				_choose(p, [])
			else:
				_press["alone"] = p                      # let go without a drag: this one alone stays chosen
			# a drag moves everything chosen (a part just let go with Shift is not, and does not move)
			var starts := {}
			if chosen().has(p):
				for i in chosen():
					starts[i] = (item.parts[i] as Dictionary).duplicate(true)
			_press["starts"] = starts
			_press["grabbed"] = hit["at"]
		Grab.SIZE:
			var p: Dictionary = _part()
			var way := _column(HeldItemShape.turn(p["rotation"]), int(hit["side"])) * float(hit["sign"])
			_press["start"] = p.duplicate(true)
			_press["way"] = way
			_press["base"] = _vec(p["position"]) + way * 0.5 * float(p["size"][int(hit["side"])])
			_press["t0"] = _along(from, _press["base"], way)
		Grab.TURN:
			var p2: Dictionary = _part()
			_press["start"] = p2.duplicate(true)
			_press["centre"] = _vec(p2["position"])
			_press["angle0"] = _angle(from, _press["centre"], int(_press["axis"]))
		Grab.GRIP:
			_press["start"] = item.grip.duplicate(true)
			_press["grabbed"] = hit.get("at", _vec(item.grip["position"]))
		Grab.GRIP_TURN:
			_press["start"] = item.grip.duplicate(true)
			_press["centre"] = _vec(item.grip["position"])
			_press["angle0"] = _angle(from, _press["centre"], int(_press["axis"]))
	_layout()


## Choose a part and the others with it, and say so.
func _choose(part: int, others: Array) -> void:
	var before := chosen()
	selected = part
	also = others.duplicate()
	also.erase(part)
	if chosen() != before:
		var press := _press                              # whoever listens shows the item again: the press goes on
		selection_changed.emit(selected, also.duplicate())
		_press = press
		redraw()


## Shift+click: one more part chosen (it takes the handles), or a chosen one let go.
func _toggle(part: int) -> void:
	var all := chosen()
	if not all.has(part):
		_choose(part, all)
	elif all.size() > 1:
		all.erase(part)
		_choose(all[0], all.slice(1))


## The pointer's angle about one of the item's axes, round a point, in degrees; NAN where there is none.
func _angle(at: Vector2, centre: Vector3, axis: int) -> float:
	var on: Variant = _on_plane(at, centre, axis)
	if on == null:
		return NAN
	var d: Vector3 = (on as Vector3) - centre
	return rad_to_deg(atan2(d[(axis + 2) % 3], d[(axis + 1) % 3]))


## How far the pointer has gone from where it took hold, in the plane across `axis`, in whole steps: [x, y, z] (0
## along `axis`), or null where its ray runs along the plane. Steps, not places: what is moved keeps whatever it had
## beyond the grid, so a part's sides stay on the lines they were on.
func _steps(at: Vector2, grabbed: Vector3, axis: int, flip_x: bool = false) -> Variant:
	var on: Variant = _on_plane(at, grabbed, axis)
	if on == null:
		return null
	var d: Vector3 = (on as Vector3) - grabbed
	if flip_x:
		d.x = -d.x
	var out: Array = [0.0, 0.0, 0.0]
	for j in 3:
		if j != axis:
			out[j] = _clean(d[j], SNAP)
	return out


static func _moved(place: Array, by: Array) -> Array:
	var out: Array = []
	for j in 3:
		out.append(_clean(float(place[j]) + float(by[j]), PLACES))
	return out


func _drag_to(at: Vector2, shift: bool = false) -> void:
	var axis := int(_press["axis"])
	var start: Dictionary = _press.get("start", {})
	match int(_press["grab"]):
		Grab.PART:
			var starts: Dictionary = _press["starts"]
			var by: Variant = _steps(at, _press["grabbed"], axis, bool(_press["mirrored"]))
			if by == null or starts.is_empty():
				return
			for i in starts.keys():
				_change(item.parts[i], "position", _moved(starts[i]["position"], by))
			_press.erase("alone")
			readout = _place_text((_part() as Dictionary)["position"], axis) \
				+ ("" if starts.size() == 1 else "   (%d parts)" % starts.size())
		Grab.SIZE:
			var t := _along(at, _press["base"], _press["way"])
			if is_nan(t) or is_nan(float(_press["t0"])):
				return
			var i := int(_press["side"])
			var was := float(start["size"][i])
			var grown := t - float(_press["t0"])
			var size: Array = (start["size"] as Array).duplicate()
			var place: Array = (start["position"] as Array).duplicate()
			var p: Dictionary = _part()
			if shift:
				# it keeps its shape: every size by the same amount, about its middle (the side pulled still follows
				# the pointer, so the size along it grows by twice as far)
				var factor := maxf(HeldItemShape.MIN_SIZE, _clean(was + 2.0 * grown, SNAP)) / was
				for j in 3:
					factor = maxf(factor, HeldItemShape.MIN_SIZE / float(size[j]))
				for j in 3:
					size[j] = _clean(float(size[j]) * factor, PLACES)
				readout = "%s x %s x %s   (keeping its shape)" % [_number(size[0]), _number(size[1]), _number(size[2])]
			else:
				var now := maxf(HeldItemShape.MIN_SIZE, _clean(was + grown, SNAP))
				size[i] = now
				var way: Vector3 = _press["way"]
				for j in 3:
					place[j] = _clean(float(place[j]) + way[j] * 0.5 * (now - was), PLACES)
				readout = "%s %s" % [SIZE_WORDS[i], _number(now)]
			_change(p, "size", size)
			_change(p, "position", place)
		Grab.TURN, Grab.GRIP_TURN:
			var angle := _angle(at, _press["centre"], axis)
			if is_nan(angle) or is_nan(float(_press["angle0"])):
				return
			var by := snappedf(wrapf(angle - float(_press["angle0"]), -180.0, 180.0), TURN_SNAP)
			var target: Dictionary = _part() if _is(_press, Grab.TURN) else item.grip
			_change(target, "rotation", turned(start["rotation"], axis, by))
			readout = "turned %s degrees" % _number(by)
		Grab.GRIP:
			var by2: Variant = _steps(at, _press["grabbed"], axis)
			if by2 == null:
				return
			_change(item.grip, "position", _moved(start["position"], by2))
			readout = "grip   " + _place_text(item.grip["position"], axis)
	if _changed:
		redraw()
		edited.emit()


func _change(target: Variant, field: String, value: Variant) -> void:
	var t: Dictionary = target
	if t.get(field) != value:
		t[field] = value
		_changed = true


static func _number(v: float) -> String:
	return str(snappedf(v, 0.01))


static func _place_text(place: Array, axis: int) -> String:
	var parts: Array[String] = []
	for j in 3:
		if j != axis:
			parts.append("%s %s" % [AXES[j], _number(float(place[j]))])
	return "   ".join(parts)


func _label_for(grab: int) -> String:
	match grab:
		Grab.PART: return "Move part %d" % (selected + 1) if also.is_empty() else "Move %d parts" % chosen().size()
		Grab.SIZE: return "Resize part %d" % (selected + 1)
		Grab.TURN: return "Turn part %d" % (selected + 1)
		Grab.GRIP: return "Move grip"
		Grab.GRIP_TURN: return "Turn grip"
	return "Edit"


func _end() -> void:
	var grab := int(_press["grab"])
	var changed := _changed and _differs()
	var alone := int(_press.get("alone", -1)) if not _dragging else -1
	_press = {}
	_dragging = false
	_changed = false
	readout = ""
	if alone >= 0:
		_choose(alone, [])                               # a plain click on one of several: that one alone
	redraw()
	if changed:
		edit_finished.emit(_label_for(grab), false)


## Whether what was dragged ended anywhere but where it began.
func _differs() -> bool:
	match int(_press["grab"]):
		Grab.PART:
			var starts: Dictionary = _press["starts"]
			for i in starts.keys():
				if item.parts[i] != starts[i]:
					return true
			return false
		Grab.SIZE, Grab.TURN: return _part() != _press["start"]
		Grab.GRIP, Grab.GRIP_TURN: return item.grip != _press["start"]
	return false


## Give up the drag under way: everything back where it was.
func cancel() -> void:
	if _press.is_empty():
		return
	var start: Dictionary = _press.get("start", {})
	match int(_press["grab"]):
		Grab.PART:
			var starts: Dictionary = _press["starts"]
			for i in starts.keys():
				if int(i) < item.parts.size():
					item.parts[i] = (starts[i] as Dictionary).duplicate(true)
		Grab.SIZE, Grab.TURN:
			if _part() != null:
				item.parts[selected] = start.duplicate(true)
		Grab.GRIP, Grab.GRIP_TURN:
			item.grip = start.duplicate(true)
	var was_changed := _changed
	_press = {}
	_dragging = false
	_changed = false
	readout = ""
	redraw()
	if was_changed:
		edited.emit()


func _key(key: InputEventKey) -> bool:
	if not key.pressed:
		return false
	if key.keycode == KEY_ESCAPE and not _press.is_empty():
		cancel()
		return true
	if mode != Mode.PARTS or _part() == null or not _press.is_empty():
		# an arrow key is used up all the same, or it would walk the keyboard's focus out of the view
		return key.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	match key.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			if not key.echo:
				delete_requested.emit()
			return true
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			nudge(int(key.keycode == KEY_RIGHT) - int(key.keycode == KEY_LEFT),
				int(key.keycode == KEY_UP) - int(key.keycode == KEY_DOWN))
			return true
	return false


## Move what is chosen a quarter unit the way an arrow key points on the screen, flat to the view faced.
func nudge(across: int, upward: int) -> bool:
	if _part() == null or camera == null:
		return false
	var axis := facing()
	var right := to_item(camera.global_transform.basis.x)
	var up := to_item(camera.global_transform.basis.y)
	var a := (axis + 1) % 3
	var b := (axis + 2) % 3
	var along := a if absf(right[a]) >= absf(right[b]) else b
	var rise := b if along == a else a
	var by: Array = [0.0, 0.0, 0.0]
	by[along] = across * SNAP * (1.0 if right[along] >= 0.0 else -1.0)
	by[rise] = upward * SNAP * (1.0 if up[rise] >= 0.0 else -1.0)
	for i in chosen():
		item.parts[i]["position"] = _moved(item.parts[i]["position"], by)
	redraw()
	edited.emit()
	edit_finished.emit("Nudge part %d" % (selected + 1) if also.is_empty() else "Nudge %d parts" % chosen().size(), true)
	return true
