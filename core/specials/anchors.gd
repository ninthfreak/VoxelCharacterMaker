@tool
class_name Anchors
extends RefCounted

## Named points on the figure that special shapes attach to.
##
## A special shape is "anchored to the body at specific points but has a shape
## that isn't otherwise based on the body". So the anchor is the only thing
## measured from the body, and it is measured afresh for every body and head:
## "the front of the face at the bottom of the eyes" is a different voxel on
## the oval head than on the boxy one, and "the front of the chest" is further
## forward on a heavy body than a slim one. The shape hung there is the same.
##
## Each anchor has a local frame, so a shape is drawn the same way wherever it
## lands:
##   u    across the shape (local a)
##   v    up the shape, or toward the front for a top-facing anchor (local c)
##   out  away from the body (local b); b = 0 is the first voxel OUTSIDE the
##        surface, b = -1 is the surface voxel itself
##
## Side anchors (hip, shoulder, wrist, ankle) are defined on the character's
## LEFT; a mirrored shape is repeated on the right.

class Anchor extends RefCounted:
	var name: String
	var part: String
	## First voxel outside the surface, at the anchor's own column.
	var origin: Vector3i
	var u: Vector3i
	var v: Vector3i
	var out: Vector3i

	## Rigid placement: the shape keeps its own form.
	func place(a: int, b: int, c: int) -> Vector3i:
		return origin + u * a + v * c + out * b

	## The column a local (a, c) sits in, ignoring depth.
	func column(a: int, c: int) -> Vector3i:
		return origin + u * a + v * c


const FRONT := Vector3i(0, -1, 0)
const BACK := Vector3i(0, 1, 0)
const UP := Vector3i(0, 0, 1)
const SIDE := Vector3i(1, 0, 0)   ## the character's left, outward
const ACROSS := Vector3i(1, 0, 0)
const RISE := Vector3i(0, 0, 1)
const FORWARD := Vector3i(0, -1, 0)

## name -> [part, measure-at (x, y, z; -1 = "find it"), out, u, v, label]
## A -1 coordinate is filled in from the part's own geometry (the centre of a
## limb, its top row); the coordinate along `out` is always found.
const DEFINITIONS := {
	"face": ["head", Vector3i(12, -1, 30), FRONT, ACROSS, RISE,
		"Face, at the bottom row of the eyes"],
	"brow": ["head", Vector3i(12, -1, 35), FRONT, ACROSS, RISE,
		"Forehead, just above the eyes"],
	"crown": ["head", Vector3i(12, 11, -1), UP, ACROSS, FORWARD,
		"Top of the head"],
	"nape": ["head", Vector3i(12, -1, 30), BACK, ACROSS, RISE,
		"Back of the head, level with the eyes"],
	"chest": ["chest", Vector3i(12, -1, 22), FRONT, ACROSS, RISE,
		"Front of the chest"],
	"back": ["chest", Vector3i(12, -1, 22), BACK, ACROSS, RISE,
		"Middle of the back"],
	"waist_front": ["pelvis", Vector3i(12, -1, 15), FRONT, ACROSS, RISE,
		"Front of the waist"],
	"waist_back": ["pelvis", Vector3i(12, -1, 15), BACK, ACROSS, RISE,
		"Back of the waist"],
	"hip": ["pelvis", Vector3i(-1, 11, 13), SIDE, FORWARD, RISE,
		"Side of the hip (both sides when mirrored)"],
	"shoulder": ["upper_arm_L", Vector3i(-1, 11, -1), UP, ACROSS, FORWARD,
		"Top of the shoulder (both sides when mirrored)"],
	"wrist": ["forearm_L", Vector3i(-1, 11, 13), SIDE, FORWARD, RISE,
		"Outside of the wrist (both sides when mirrored)"],
	"ankle": ["shin_L", Vector3i(-1, 11, 2), SIDE, FORWARD, RISE,
		"Outside of the ankle (both sides when mirrored)"],
}

const ORDER: Array[String] = [
	"crown", "brow", "face", "nape", "shoulder", "chest", "back",
	"waist_front", "waist_back", "hip", "wrist", "ankle",
]


static func names() -> Array[String]:
	return ORDER.duplicate()


static func label(anchor_name: String) -> String:
	var d: Array = DEFINITIONS.get(anchor_name, [])
	return String(d[5]) if d.size() > 5 else anchor_name


static func part_of(anchor_name: String) -> String:
	var d: Array = DEFINITIONS.get(anchor_name, [])
	return String(d[0]) if not d.is_empty() else ""


## Measure an anchor on one assembled figure. part_cells: part name -> cells.
## Returns null when the part is missing or empty.
static func find(part_cells: Dictionary, anchor_name: String) -> Anchor:
	if not DEFINITIONS.has(anchor_name):
		return null
	var d: Array = DEFINITIONS[anchor_name]
	var part := String(d[0])
	var cells: Dictionary = part_cells.get(part, {})
	if cells.is_empty():
		return null
	var at: Vector3i = d[1]
	var out: Vector3i = d[2]

	# Fill in "find it" coordinates from the part's geometry: centre of its
	# extent in x, its top row in z. (y is only ever given.)
	var bounds := VoxelTopology.bounds(cells)
	var lo := Vector3i(bounds.position)
	var hi := Vector3i(bounds.position + bounds.size)
	if at.x < 0 and out.x == 0:
		at.x = (lo.x + hi.x + 1) / 2
	if at.z < 0 and out.z == 0:
		at.z = hi.z

	var probe := at
	# The coordinate along `out` is found, not given.
	if out.x != 0:
		probe.x = 0
	if out.y != 0:
		probe.y = 0
	if out.z != 0:
		probe.z = 0
	var surface: Variant = surface_along(cells, probe, out)
	if surface == null:
		return null

	var anchor := Anchor.new()
	anchor.name = anchor_name
	anchor.part = part
	anchor.origin = (surface as Vector3i) + out
	anchor.out = out
	anchor.u = d[3]
	anchor.v = d[4]
	return anchor


## The outermost cell along `out` in the column through `point` -- the column
## being every cell that matches `point` on the two axes `out` does not use.
## Null when the column is empty.
static func surface_along(cells: Dictionary, point: Vector3i, out: Vector3i) -> Variant:
	var best: Variant = null
	var best_depth := -999999
	for cell in cells.keys():
		var c: Vector3i = cell
		if out.x == 0 and c.x != point.x:
			continue
		if out.y == 0 and c.y != point.y:
			continue
		if out.z == 0 and c.z != point.z:
			continue
		var depth := c.x * out.x + c.y * out.y + c.z * out.z
		if depth > best_depth:
			best_depth = depth
			best = c
	return best
