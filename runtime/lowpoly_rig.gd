@tool
class_name LowpolyRig
extends Node3D

## A low-poly character as Godot draws it: one skin that bends at its joints (SPEC.md section 0).
##
## A Skeleton3D has a bone for each of the eleven parts, at the part's pivot, each under its parent. The figure is one
## skinned mesh: every corner follows the parts its weights name, in those shares (plain blended skinning, which is
## what the body files were made for). Posing turns the bones; nothing is rebuilt. A pose is the same dictionary the
## voxel rig takes (runtime/poses.gd): part name -> Euler angles in degrees, in Godot space.
##
## The rig's origin is at the figure's feet on the ground, as CharacterRig's is.
##
## Hanging cloth (skirts, capes: LowpolyCloth) is not part of the skin. It is laid afresh over the posed figure every
## time the pose changes, in full precision, and drawn as a second mesh that the skeleton does not move.
##
## Shading: flat (every polygon one shade, the polygons show) or smooth (shade blended across them from corner to
## corner, the way 1990s 3D games lit their models). Which one the game uses is the owner's call (lowpoly/README.md,
## "Not decided yet"), so both are here. The light is the review sheets' even studio light, fixed to the camera, so
## the editor shows a figure as lowpoly/sheets.py draws it; it is a preview light, not the game's.

signal rebuilt

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_back;

// Vertex colours are the palette's own values, lit as the review sheets light them, and shown as they are: the
// project renders with the Compatibility renderer, which (like the voxel material, Mesher.make_material) passes
// them straight through.

// The mesh's normals already say flat or smooth (LowpolyRig._make_mesh); they bend with the skin.
void fragment() {
	vec3 n = normalize(NORMAL);
	// lowpoly/picture.py: a key light from the upper left, a soft fill from the right, a little from above
	vec3 key = normalize(vec3(-0.45, 0.55, 0.7));
	vec3 fill = normalize(vec3(0.6, 0.1, 0.75));
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float light = 0.34 + 0.52 * clamp(dot(n, key), 0.0, 1.0) + 0.16 * clamp(dot(n, fill), 0.0, 1.0)
		+ 0.06 * clamp(dot(n, up), 0.0, 1.0);
	// A vertex colour with no alpha marks a polygon drawn in its own colour, untouched by the light: the eye's
	// white, pupil and lash line, as the voxel face has them. Nothing here writes ALPHA, so all of it is opaque.
	if (COLOR.a < 0.5) {
		light = 1.0;
	}
	ALBEDO = clamp(COLOR.rgb * light, vec3(0.0), vec3(1.0));
}
"""

var figure: LowpolyFigure = null
var skeleton: Skeleton3D = null
var mesh_instance: MeshInstance3D = null
## the hanging cloth as laid in the current pose (null when the figure has none)
var cloth_instance: MeshInstance3D = null
## that cloth: [[polygon (flat points, asset units, posed), colour], ...]
var laid_cloth: Array = []
var flat_shading := true: set = set_flat_shading

var _material: ShaderMaterial = null
var _pose: Dictionary = {}
var _bone: Dictionary = {}          ## part -> bone index


func _init() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader


## Flat or smooth: the normals change, so the mesh is made again (it is under a thousand triangles).
func set_flat_shading(on: bool) -> void:
	if on == flat_shading:
		return
	flat_shading = on
	if figure != null and mesh_instance != null:
		mesh_instance.mesh = _make_mesh()
		_show_cloth()


func material() -> ShaderMaterial:
	return _material


## Replace the whole figure. The pose is kept.
func build(p_figure: LowpolyFigure) -> void:
	figure = p_figure
	_clear()
	if figure == null:
		return
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	for part in LowpolyLibrary.PARTS:
		var i := skeleton.add_bone(part)
		_bone[part] = i
		var parent := _parent(part)
		if not parent.is_empty():
			skeleton.set_bone_parent(i, _bone[parent])
		skeleton.set_bone_rest(i, _rest_local(part))
	skeleton.reset_bone_poses()

	var skin := Skin.new()
	for part in LowpolyLibrary.PARTS:
		skin.add_named_bind(part, _rest_global(part).affine_inverse())
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _make_mesh()
	mesh_instance.material_override = _material
	add_child(mesh_instance)
	mesh_instance.skin = skin
	mesh_instance.skeleton = NodePath("../Skeleton")
	apply_pose_values(_pose)
	rebuilt.emit()


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	skeleton = null
	mesh_instance = null
	cloth_instance = null
	laid_cloth = []
	_bone.clear()


# ---------------------------------------------------------------------- posing ---

## Apply a named pose from Poses.
func apply_pose(pose_name: String) -> void:
	apply_pose_values(Poses.get_pose(pose_name))


## Apply explicit Euler angles in degrees: part name -> Vector3.
func apply_pose_values(pose: Dictionary) -> void:
	_pose = pose.duplicate()
	if skeleton == null:
		return
	for part in LowpolyLibrary.PARTS:
		var i: int = _bone[part]
		skeleton.set_bone_pose_position(i, _rest_local(part).origin)
		skeleton.set_bone_pose_rotation(i, _turn(part, _pose).get_rotation_quaternion())
	_lay_cloth()


## Lay the figure's hanging cloth for the current pose and show it.
func _lay_cloth() -> void:
	laid_cloth = []
	if figure != null:
		for pair in LowpolyCloth.lay_all(figure, _pose):
			var cloth: LowpolyCloth = pair[0]
			for made in pair[1]:
				laid_cloth.append([made[0], cloth.colours.get(String(made[1]), Color.MAGENTA)])
	_show_cloth()


## The laid cloth as a plain mesh in the rig's own space: flat shading gives each piece its own normal; smooth
## shading shares a normal wherever pieces meet.
func _show_cloth() -> void:
	if laid_cloth.is_empty():
		if cloth_instance != null:
			cloth_instance.visible = false
		return
	if cloth_instance == null:
		cloth_instance = MeshInstance3D.new()
		cloth_instance.name = "Cloth"
		cloth_instance.material_override = _material
		add_child(cloth_instance)
	cloth_instance.visible = true
	var sums := {}
	var own: Array = []
	for piece in laid_cloth:
		var pts: PackedFloat64Array = piece[0]
		var n := PackedFloat64Array([0.0, 0.0, 0.0])
		for i in pts.size() / 3:
			n = Vec64.add(n, Vec64.cross(Vec64.at(pts, i), Vec64.at(pts, (i + 1) % (pts.size() / 3))))
		own.append(n)
		for i in pts.size() / 3:
			var key := Vector3i(roundi(pts[3 * i] * 1e4), roundi(pts[3 * i + 1] * 1e4), roundi(pts[3 * i + 2] * 1e4))
			sums[key] = Vec64.add(sums.get(key, PackedFloat64Array([0.0, 0.0, 0.0])), n)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for j in laid_cloth.size():
		var pts: PackedFloat64Array = laid_cloth[j][0]
		var base := verts.size()
		var count := pts.size() / 3
		for i in count:
			var key := Vector3i(roundi(pts[3 * i] * 1e4), roundi(pts[3 * i + 1] * 1e4), roundi(pts[3 * i + 2] * 1e4))
			var n: PackedFloat64Array = own[j] if flat_shading else sums[key]
			verts.push_back(VoxelAxes.point_to_godot(Vec64.to_vector3(Vec64.at(pts, i))))
			normals.push_back(VoxelAxes.direction_to_godot(Vec64.to_vector3(n)).normalized())
			colours.push_back(laid_cloth[j][1])
		for i in range(1, count - 1):                       # Godot's front faces are clockwise: each fan triangle reversed
			indices.append_array(PackedInt32Array([base, base + i + 1, base + i]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	cloth_instance.mesh = mesh


func current_pose() -> Dictionary:
	return _pose.duplicate()


## For every part: the transform that takes a point of the figure at rest to where that part carries it in the pose,
## in Godot space. The same transforms the skeleton applies, worked out here so that the figure's corners can be
## found without drawing it (picking, and the checks against lowpoly/expected.py).
func skinning(pose: Dictionary = _pose) -> Dictionary:
	var global := {}
	var out := {}
	for part in LowpolyLibrary.PARTS:
		var local := Transform3D(_turn(part, pose), _rest_local(part).origin)
		var parent := _parent(part)
		global[part] = local if parent.is_empty() else (global[parent] as Transform3D) * local
		out[part] = (global[part] as Transform3D) * _rest_global(part).affine_inverse()
	return out


## Every corner of the figure in a pose, in the asset files' units (x across, y depth, z up).
func posed_points(pose: Dictionary = _pose) -> PackedVector3Array:
	var out := PackedVector3Array()
	if figure == null:
		return out
	var m := skinning(pose)
	for k in figure.points.size():
		var rest := VoxelAxes.point_to_godot(figure.points[k])
		var at := Vector3.ZERO
		var w: Dictionary = figure.weights[k]
		for part in w.keys():
			at += float(w[part]) * ((m[part] as Transform3D) * rest)
		out.push_back(VoxelAxes.godot_to_point(at))
	return out


## The polygon a ray meets first, in its pose: its index in figure.polygons, or -1. The ray is in this rig's own
## space (Godot units and axes), as a camera gives it once taken into the rig's frame.
func pick(origin: Vector3, direction: Vector3) -> int:
	if figure == null:
		return -1
	var posed := posed_points()
	var at := PackedVector3Array()
	for v in posed:
		at.push_back(VoxelAxes.point_to_godot(v))
	var best := INF
	var hit := -1
	for i in figure.polygons.size():
		var p: Dictionary = figure.polygons[i]
		if bool(p["hidden"]) or String(p["piece"]) == LowpolyAssembler.FACE_PIECE:
			continue                         # the face lies just off the head: a click on it picks the head under it
		var corners: PackedInt32Array = p["corners"]
		for j in range(1, corners.size() - 1):
			var t := _ray_triangle(origin, direction, at[corners[0]], at[corners[j]], at[corners[j + 1]])
			if t > 0.0 and t < best:
				best = t
				hit = i
	for piece in laid_cloth:                                 # hanging cloth in front of what was hit: nothing is picked
		var pts: PackedFloat64Array = piece[0]
		var c := PackedVector3Array()
		for k in pts.size() / 3:
			c.push_back(VoxelAxes.point_to_godot(Vec64.to_vector3(Vec64.at(pts, k))))
		for j in range(1, c.size() - 1):
			var t := _ray_triangle(origin, direction, c[0], c[j], c[j + 1])
			if t > 0.0 and t < best:
				return -1
	return hit


## How far along the ray it meets the triangle (either face), or -1 (Moller and Trumbore).
static func _ray_triangle(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var h := d.cross(e2)
	var det := e1.dot(h)
	if absf(det) < 1e-12:
		return -1.0
	var inv := 1.0 / det
	var s := o - a
	var u := s.dot(h) * inv
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := s.cross(e1)
	var v := d.dot(q) * inv
	if v < 0.0 or u + v > 1.0:
		return -1.0
	return e2.dot(q) * inv


## The bounds of the figure standing, in Godot space, for framing a camera. part: just that part's.
func figure_aabb(part: String = "") -> AABB:
	if figure == null:
		return AABB()
	var b := figure.bounds(part)
	var a := VoxelAxes.point_to_godot(b.position)
	var c := VoxelAxes.point_to_godot(b.end)
	return AABB(a, c - a).abs()


# --------------------------------------------------------------------- helpers ---

func _parent(part: String) -> String:
	return String((figure.parts[part] as Dictionary)["parent"])


func _pivot(part: String) -> Vector3:
	return (figure.parts[part] as Dictionary)["pivot"]


## A bone's rest, relative to its parent's: no turn, just the step from the parent's pivot to its own. A root's
## pivot is a point and takes the whole mapping; a child's is an offset and takes only its linear part (see the
## note in CharacterRig.build).
func _rest_local(part: String) -> Transform3D:
	var parent := _parent(part)
	if parent.is_empty():
		return Transform3D(Basis(), VoxelAxes.pivot_to_godot(_pivot(part)))
	return Transform3D(Basis(), VoxelAxes.direction_to_godot(_pivot(part) - _pivot(parent)))


func _rest_global(part: String) -> Transform3D:
	return Transform3D(Basis(), VoxelAxes.pivot_to_godot(_pivot(part)))


## How a part is turned in a pose: Godot's Euler angles, in its usual order (as Node3D.rotation_degrees).
func _turn(part: String, pose: Dictionary) -> Basis:
	var v: Vector3 = pose.get(part, Vector3.ZERO)
	return Basis.from_euler(Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z)))


## One skinned surface. Each polygon has its own corners, so it keeps its own colour and, for flat shading, its own
## normal on every corner: a polygon that is not quite flat is still one shade, as on the review sheets. For smooth
## shading a corner's normal is shared: the area-weighted sum of the normals of the visible polygons that use it.
func _make_mesh() -> ArrayMesh:
	var sums := PackedVector3Array()
	sums.resize(figure.points.size())
	for p in figure.polygons:
		if bool(p["hidden"]):
			continue
		var corners: PackedInt32Array = p["corners"]
		var n := _newell(corners)
		for k in corners:
			sums[k] += n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for p in figure.polygons:
		if bool(p["hidden"]):
			continue
		var corners: PackedInt32Array = p["corners"]
		var base := verts.size()
		var own := VoxelAxes.direction_to_godot(_newell(corners)).normalized()
		var colour: Color = p["colour"]
		colour.a = 0.0 if bool(p.get("unlit", false)) else 1.0
		for k in corners:
			verts.push_back(VoxelAxes.point_to_godot(figure.points[k]))
			normals.push_back(own if flat_shading else VoxelAxes.direction_to_godot(sums[k]).normalized())
			colours.push_back(colour)
			_push_weights(bones, weights, figure.weights[k])
		# A fan from the first corner, each triangle reversed: Godot's front faces are clockwise (see Mesher).
		for i in range(1, corners.size() - 1):
			indices.append_array(PackedInt32Array([base, base + i + 1, base + i]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A polygon's normal, as long as twice its area (asset space): the sum of the cross products round it.
func _newell(corners: PackedInt32Array) -> Vector3:
	var n := Vector3.ZERO
	for i in corners.size():
		n += figure.points[corners[i]].cross(figure.points[corners[(i + 1) % corners.size()]])
	return n


## Four bones and four weights for a corner, the heaviest first; the body files give at most four.
func _push_weights(bones: PackedInt32Array, weights: PackedFloat32Array, w: Dictionary) -> void:
	var entries: Array = []
	for part in w.keys():
		entries.append([float(w[part]), String(part)])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in 4:
		if i < entries.size():
			bones.push_back(_bone[entries[i][1]])
			weights.push_back(entries[i][0])
		else:
			bones.push_back(0)
			weights.push_back(0.0)


func polygon_count() -> int:
	return figure.visible_polygons() if figure != null else 0


func triangle_count() -> int:
	return figure.triangles() if figure != null else 0
