@tool
class_name VoxelTopology
extends RefCounted

## Structural checks on a set of voxels (SPEC.md sections 3.1 and 12).
##
## These live in core/, not in the test suite, because the body editor checks
## the same invariants live while you draw and the acceptance tests check them
## on the shipped assets. Two implementations of "is this one connected piece"
## would eventually disagree, and then the editor would call a body valid that
## the tests reject.
##
## Every function takes a Dictionary used as a set: Vector3i -> anything.


## Number of 6-connected components. 1 means "one connected piece".
static func components(cells: Dictionary) -> int:
	var todo := cells.duplicate()
	var count := 0
	while not todo.is_empty():
		count += 1
		var seed: Vector3i = todo.keys()[0]
		todo.erase(seed)
		var queue: Array[Vector3i] = [seed]
		while not queue.is_empty():
			var cell: Vector3i = queue.pop_back()
			for offset in VoxelAxes.NEIGHBOURS:
				var next: Vector3i = cell + offset
				if todo.has(next):
					todo.erase(next)
					queue.append(next)
	return count


## True when every cell is reachable from every other through shared faces.
static func is_one_piece(cells: Dictionary) -> bool:
	return cells.is_empty() or components(cells) == 1


## Cells that touch the rest of the solid only along an edge or a corner.
##
## An edge of the grid is shared by four cells. When exactly two of them are
## solid and sit diagonally opposite, the solid touches itself along that edge
## alone, and a straight voxel-to-STL export of it is not manifold
## (SPEC 3.1). Checked on all three axis-aligned planes.
##
## Returns the cells where such a contact starts, so the editor can show them.
static func edge_only_contacts(cells: Dictionary) -> Array:
	var bad: Array = []
	# diagonal offset, and one of the two cells that would bridge it
	var probes := [
		[Vector3i(1, 1, 0), Vector3i(1, 0, 0)],
		[Vector3i(1, 0, 1), Vector3i(1, 0, 0)],
		[Vector3i(0, 1, 1), Vector3i(0, 1, 0)],
	]
	for cell in cells.keys():
		var c: Vector3i = cell
		for probe in probes:
			var diagonal: Vector3i = probe[0]
			var first: Vector3i = probe[1]
			if not cells.has(c + diagonal):
				continue
			if cells.has(c + first):
				continue
			if cells.has(c + (diagonal - first)):
				continue
			bad.append(c)
	return bad


## True when any cell of `a` shares a face with any cell of `b`.
static func touches(a: Dictionary, b: Dictionary) -> bool:
	# Walk the smaller set: adjacency is symmetric and this is called per pair
	# of parts, which is quadratic in the number of parts already.
	var small := a
	var large := b
	if a.size() > b.size():
		small = b
		large = a
	for cell in small.keys():
		var c: Vector3i = cell
		for offset in VoxelAxes.NEIGHBOURS:
			if large.has(c + offset):
				return true
	return false


## Cells of `a` that share a face with a cell of `b`.
static func contact_cells(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for cell in a.keys():
		var c: Vector3i = cell
		for offset in VoxelAxes.NEIGHBOURS:
			if b.has(c + offset):
				out.append(c)
				break
	return out


## The set reflected across the body's mirror plane.
static func mirrored(cells: Dictionary) -> Dictionary:
	var out := {}
	for cell in cells.keys():
		out[VoxelAxes.mirror_voxel(cell)] = true
	return out


static func is_mirror_symmetric(cells: Dictionary) -> bool:
	for cell in cells.keys():
		if not cells.has(VoxelAxes.mirror_voxel(cell)):
			return false
	return true


## Cells with no mirror partner, which is what breaks the symmetry.
static func asymmetric_cells(cells: Dictionary) -> Array:
	var out: Array = []
	for cell in cells.keys():
		if not cells.has(VoxelAxes.mirror_voxel(cell)):
			out.append(cell)
	return out


static func same_cells(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for cell in a.keys():
		if not b.has(cell):
			return false
	return true


## Cells on the surface: at least one face open to the outside.
static func surface_cells(cells: Dictionary) -> Array:
	var out: Array = []
	for cell in cells.keys():
		var c: Vector3i = cell
		for offset in VoxelAxes.NEIGHBOURS:
			if not cells.has(c + offset):
				out.append(c)
				break
	return out


## Inclusive bounding box of a cell set, or a zero AABB when empty.
static func bounds(cells: Dictionary) -> AABB:
	if cells.is_empty():
		return AABB()
	var lo := Vector3i(999, 999, 999)
	var hi := Vector3i(-999, -999, -999)
	for cell in cells.keys():
		var c: Vector3i = cell
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	return AABB(Vector3(lo), Vector3(hi - lo))


## Inclusive x extent of the cells in one row, or a reversed range when none.
static func row_extent_x(cells: Dictionary, z: int) -> Vector2i:
	var lo := 9999
	var hi := -9999
	for cell in cells.keys():
		var c: Vector3i = cell
		if c.z == z:
			lo = mini(lo, c.x)
			hi = maxi(hi, c.x)
	if hi < lo:
		return Vector2i(0, -1)
	return Vector2i(lo, hi)


## Mid-x of the cells in rows z0..z1, in corner space.
##
## This is how tools/build_bodies.py measures a joint pivot, so a body edited
## here gets the pivots it would have had if it had been generated.
static func mid_x(cells: Dictionary, z0: int, z1: int) -> float:
	var lo := 9999
	var hi := -9999
	for cell in cells.keys():
		var c: Vector3i = cell
		if c.z >= z0 and c.z <= z1:
			lo = mini(lo, c.x)
			hi = maxi(hi, c.x)
	if hi < lo:
		return VoxelAxes.MIRROR_X
	return (float(lo) + float(hi) + 1.0) / 2.0


static func cells_in_row(cells: Dictionary, z: int) -> Array:
	var out: Array = []
	for cell in cells.keys():
		if (cell as Vector3i).z == z:
			out.append(cell)
	return out


static func count_in_row(cells: Dictionary, z: int) -> int:
	var n := 0
	for cell in cells.keys():
		if (cell as Vector3i).z == z:
			n += 1
	return n
