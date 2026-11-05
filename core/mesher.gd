@tool
class_name Mesher
extends RefCounted

## Exposed-face culling into an ArrayMesh with vertex colours (SPEC.md section 9).
##
## Enough at these sizes: a body is roughly 4-6k voxels, so a dressed figure is
## a few thousand quads. Greedy meshing later if it ever matters.
##
## Culling is PER PART, deliberately. Culling against the whole figure would
## look tidier in the rest pose but would punch holes the moment a limb rotates
## away from its neighbour, and SPEC 3.1 accepts gaps and overlaps at bent
## joints precisely because there are no joint caps. Shading, by contrast, is
## computed over the whole figure (see CharacterAssembler), which is what gives
## the baked Voxel Doom look.
##
## Winding: Godot treats CLOCKWISE triangles as front-facing. The quads below
## are listed counter-clockwise seen from outside, which is the usual
## OpenGL-style order, and then emitted reversed. VoxelAxes' mapping is a proper
## rotation, so that order survives the conversion to Godot space unchanged.

## The six faces of a voxel: outward normal in asset space, then the four corner
## offsets in counter-clockwise order seen from outside.
const FACES := [
	{
		"normal": Vector3i(1, 0, 0),
		"corners": [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	},
	{
		"normal": Vector3i(-1, 0, 0),
		"corners": [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	},
	{
		"normal": Vector3i(0, 1, 0),
		"corners": [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	},
	{
		"normal": Vector3i(0, -1, 0),
		"corners": [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	},
	{
		"normal": Vector3i(0, 0, 1),
		"corners": [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	},
	{
		"normal": Vector3i(0, 0, -1),
		"corners": [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
	},
]


## Build a mesh for one assembled part.
##
## Vertices are placed relative to `origin` in corner space -- normally the
## part's own pivot -- so the mesh can hang under a Node3D sitting at that pivot
## and rotate about it.
static func build_part(part: CharacterAssembler.Part, origin: Vector3,
		use_face_multiplier: bool = true) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()

	var origin_godot := VoxelAxes.point_to_godot(origin)

	for cell in part.cells.keys():
		var c: Vector3i = cell
		var base_colour: Color = part.colours.get(c, Color.MAGENTA)
		for face in FACES:
			var f: Dictionary = face
			var normal_asset: Vector3i = f["normal"]
			if part.cells.has(c + normal_asset):
				continue  # hidden by this part's own geometry

			var colour := base_colour
			if use_face_multiplier:
				colour = Palette.multiply_rgb(
					base_colour, Palette.face_multiplier(normal_asset))

			var normal_godot := VoxelAxes.direction_to_godot(Vector3(normal_asset)).normalized()
			var corners: Array = f["corners"]
			var p: Array[Vector3] = []
			for corner in corners:
				var offset: Vector3 = corner
				var asset_point := Vector3(c.x + offset.x, c.y + offset.y, c.z + offset.z)
				p.append(VoxelAxes.point_to_godot(asset_point) - origin_godot)

			# Reversed, because Godot's front faces are clockwise.
			_tri(vertices, normals, colours, p[0], p[2], p[1], normal_godot, colour)
			_tri(vertices, normals, colours, p[0], p[3], p[2], normal_godot, colour)

	if vertices.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _tri(vertices: PackedVector3Array, normals: PackedVector3Array,
		colours: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		normal: Vector3, colour: Color) -> void:
	vertices.push_back(a)
	vertices.push_back(b)
	vertices.push_back(c)
	for _i in 3:
		normals.push_back(normal)
		colours.push_back(colour)


## The material the baked look needs: unshaded, vertex colours straight through,
## so what Shading computed is exactly what appears (SPEC 6).
static func make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Count of quads a part would emit, without building anything. Used by tests
## and by the editor's statistics line.
static func count_faces(part: CharacterAssembler.Part) -> int:
	var n := 0
	for cell in part.cells.keys():
		var c: Vector3i = cell
		for offset in VoxelAxes.NEIGHBOURS:
			if not part.cells.has(c + offset):
				n += 1
	return n
