@tool
class_name VoxelAxes
extends RefCounted

## The one and only conversion between asset voxel space and Godot space.
##
## SPEC.md section 2. Asset axes: x = width, y = depth, z = up. Feet stand on
## z = 0, the figure faces -y, the character's left is +x. The mirror line lies
## between x = 11 and x = 12; the depth centre between y = 11 and y = 12.
## A voxel (x, y, z) occupies [x, x+1) x [y, y+1) x [z, z+1), so pivots are in
## corner space and (12, 12, 12) sits on a voxel boundary.
##
## Godot mapping:  godot = ((12 - x) / 24, z / 24, (y - 12) / 24)
## which puts up on +Y, the character's right on +X and its face toward -Z
## (Node3D forward). The mapping is a proper rotation plus uniform scale -- its
## Jacobian determinant is +1 / 24^3 -- so winding and handedness are preserved
## and nothing is mirrored. tests/test_axes.gd locks all of this down.
##
## If the project ever adopts the glTF/MODEL_FRONT convention (models face +Z),
## flip X and Z here and nowhere else.

const VOXELS_PER_METRE := 24.0
const VOXEL_SIZE := 1.0 / VOXELS_PER_METRE

## Grid of a character's reference box: 24 wide x 24 deep x 48 tall.
const GRID := Vector3i(24, 24, 48)

## The figure is 42 voxels tall (1.75 m).
const FIGURE_HEIGHT := 42

## Mirror plane in corner space: mirror of x is MIRROR_SUM - x for corner
## coordinates, and MIRROR_X_MAX - x for voxel indices.
const MIRROR_X := 12.0
const MIRROR_SUM := 24.0
const MIRROR_X_MAX := 23

## Depth centre in corner space. Cells with y < DEPTH_CENTRE are on the front.
const DEPTH_CENTRE := 12

## Face plane for the skin-tight face overlay (SPEC section 5).
const FACE_PLANE_Y := 6


## Corner-space point (asset) -> Godot metres.
static func point_to_godot(p: Vector3) -> Vector3:
	return Vector3(
		(MIRROR_X - p.x) * VOXEL_SIZE,
		p.z * VOXEL_SIZE,
		(p.y - DEPTH_CENTRE) * VOXEL_SIZE,
	)


## Voxel index -> Godot position of that voxel's centre.
static func voxel_centre_to_godot(v: Vector3i) -> Vector3:
	return point_to_godot(Vector3(v.x + 0.5, v.y + 0.5, v.z + 0.5))


## A pivot, which is already in corner space, -> Godot metres.
static func pivot_to_godot(pivot: Vector3) -> Vector3:
	return point_to_godot(pivot)


## Asset direction -> Godot direction (no translation).
static func direction_to_godot(d: Vector3) -> Vector3:
	return Vector3(-d.x, d.z, d.y)


## Mirror a voxel index across the body's mirror plane.
static func mirror_voxel(v: Vector3i) -> Vector3i:
	return Vector3i(MIRROR_X_MAX - v.x, v.y, v.z)


## Mirror a corner-space point across the body's mirror plane.
static func mirror_point(p: Vector3) -> Vector3:
	return Vector3(MIRROR_SUM - p.x, p.y, p.z)


## True when the cell is on the character's left (+x) half.
static func is_left(v: Vector3i) -> bool:
	return float(v.x) >= MIRROR_X


## True when the cell is on the figure's front half (the figure faces -y).
static func is_front(v: Vector3i) -> bool:
	return v.y < DEPTH_CENTRE


static func in_grid(v: Vector3i) -> bool:
	return v.x >= 0 and v.y >= 0 and v.z >= 0 \
		and v.x < GRID.x and v.y < GRID.y and v.z < GRID.z


## The six face-neighbour offsets, in asset space.
const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Named directions in asset space, as the shading rule uses them. "left" and
## "right" are the VIEWER's left and right: the figure faces -y, so the viewer's
## left is -x even though the character's own left is +x (SPEC section 6).
const UP := Vector3i(0, 0, 1)
const DOWN := Vector3i(0, 0, -1)
const FRONT := Vector3i(0, -1, 0)
const BACK := Vector3i(0, 1, 0)
const VIEWER_LEFT := Vector3i(-1, 0, 0)
const VIEWER_RIGHT := Vector3i(1, 0, 0)
