@tool
class_name FigureAxes
extends RefCounted

## The one and only conversion between the asset files' space and Godot's (SPEC.md section 2).
##
## The asset files (assets/lowpoly/) are in the old voxel's unit, 24 to the metre, with x across (the character's
## left is +x, the mirror plane at x = 12), y depth (the figure faces -y, the depth centre at y = 12) and z up from
## the floor.
##
## Godot mapping:  godot = ((12 - x) / 24, z / 24, (y - 12) / 24)
## which puts up on +Y, the character's right on +X and its face toward -Z (Node3D forward). The mapping is a proper
## rotation plus uniform scale, so winding and handedness are kept and nothing is mirrored. tests/test_axes.gd
## locks this down.
##
## If the project ever adopts the glTF/MODEL_FRONT convention (models face +Z), flip X and Z here and nowhere else.

const UNITS_PER_METRE := 24.0
const UNIT := 1.0 / UNITS_PER_METRE
## The mirror plane (x) and the depth centre (y).
const MIRROR_X := 12.0
const DEPTH_CENTRE := 12.0


## Asset point -> Godot metres.
static func point_to_godot(p: Vector3) -> Vector3:
	return Vector3((MIRROR_X - p.x) * UNIT, p.z * UNIT, (p.y - DEPTH_CENTRE) * UNIT)


## Godot metres -> asset point. The exact inverse of point_to_godot, kept beside it so that flipping the convention
## here flips picking too.
static func godot_to_point(g: Vector3) -> Vector3:
	return Vector3(MIRROR_X - g.x * UNITS_PER_METRE, g.z * UNITS_PER_METRE + DEPTH_CENTRE, g.y * UNITS_PER_METRE)


## A pivot, which is a point -> Godot metres.
static func pivot_to_godot(pivot: Vector3) -> Vector3:
	return point_to_godot(pivot)


## Asset DISPLACEMENT -> Godot displacement: the linear part of point_to_godot, so the scale is included and the
## translation is not. This is what converts an offset BETWEEN two points, such as the gap between a joint's pivot
## and its parent's. For a normal, normalise the result; the scale then makes no difference.
static func direction_to_godot(d: Vector3) -> Vector3:
	return Vector3(-d.x, d.z, d.y) * UNIT
