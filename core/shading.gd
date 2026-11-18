@tool
class_name Shading
extends RefCounted

## Baked per-voxel tone, Voxel Doom style (SPEC.md section 6).
##
## Lit from the viewer's upper-left-front. Per voxel, from its six neighbours:
##   light  if the top is exposed, or both left (-x, the VIEWER's left) and
##          front (-y) are exposed
##   mid    else if the front is exposed
##   dark   else if bottom, right or back is exposed
##   mid    otherwise (fully enclosed)
##
## The same rule runs on all six bodies, and it is evaluated against the whole
## assembled figure in its rest pose -- body plus head plus garments -- not per
## part, so a sleeve shades as if it were part of the silhouette. Rotating a
## part at runtime does not re-shade it; that is the point of a baked look.
##
## This mirrors tools/build_bodies.py:shade() exactly, so the .vox previews and
## the in-engine render agree.

enum Tone { LIGHT = 0, MID = 1, DARK = 2 }

const TONE_COUNT := 3


## Tone for one cell, given the set of occupied cells (Dictionary used as a set).
static func tone_for(cell: Vector3i, solid: Dictionary) -> int:
	var up_exposed := not solid.has(cell + VoxelAxes.UP)
	var left_exposed := not solid.has(cell + VoxelAxes.VIEWER_LEFT)
	var front_exposed := not solid.has(cell + VoxelAxes.FRONT)
	if up_exposed or (left_exposed and front_exposed):
		return Tone.LIGHT
	if front_exposed:
		return Tone.MID
	var down_exposed := not solid.has(cell + VoxelAxes.DOWN)
	var right_exposed := not solid.has(cell + VoxelAxes.VIEWER_RIGHT)
	var back_exposed := not solid.has(cell + VoxelAxes.BACK)
	if down_exposed or right_exposed or back_exposed:
		return Tone.DARK
	return Tone.MID


## The tone a flat face of a solid gets from the rule above, by the way the
## face looks: what a surface voxel comes out as when only that face is open.
##
## Thin cloth cannot use the per-voxel rule. A hanging panel is a sheet one
## voxel thick, and its inside face looks at the legs: where a leg touches it
## and where there is air behind it are different answers to "is the front
## neighbour empty?", so the rule prints the legs onto the back of a skirt as
## a pattern (and makes a one-voxel strap all edge, so all light). Such shapes
## say which way each piece faces and take this shade instead.
static func face_tone(outward: Vector3i) -> int:
	if outward == VoxelAxes.UP:
		return Tone.LIGHT
	if outward == VoxelAxes.FRONT or outward == VoxelAxes.VIEWER_LEFT:
		return Tone.MID
	return Tone.DARK


## Tone for every occupied cell: Dictionary of Vector3i -> Tone.
static func tone_map(solid: Dictionary) -> Dictionary:
	var out := {}
	for cell in solid.keys():
		out[cell] = tone_for(cell, solid)
	return out


static func tone_name(tone: int) -> String:
	match tone:
		Tone.LIGHT: return "light"
		Tone.MID: return "mid"
		Tone.DARK: return "dark"
	return "?"
