@tool
class_name StrapGenerator
extends RefCounted

## A pair of straps over the shoulders (SPEC.md section 7.4).
##
## One voxel proud of the body, each strap runs up the front of the chest from
## the belly's bottom row, across the top of the chest beside the neck, and
## straight down the back to the same row. Worn over a shirt and trousers they
## read as suspenders; in one colour with a bib and trousers they make
## overalls -- which is why overalls are a saved outfit, not a garment.
##
## Everything is measured on the chest itself, so the straps fit every body and
## follow whatever the chest's front does (a bust included):
##
##   the column  halfway between the neck and the edge of the chest's top row,
##               so a wide chest carries its straps wider than a narrow one;
##   the front   one voxel in front of the chest's frontmost cell, row by row,
##               bridging any step so the strap stays one connected strip;
##   the top     one voxel above the chest's top cells in that column;
##   the back    one voxel behind the chest's rearmost cell, row by row.
##
## Straight down the back: a crossed back was tried and turns into a cluster of
## pixels at this size (owner chose straight).
##
## Shade: a strap one voxel wide is all edge, and the baked lighting would make
## every voxel of it the light shade -- lighter than the bib and trousers it
## is meant to match on overalls. So each run takes the shade its outward face
## has on a flat garment: mid on the front, dark on the back, light on top.

const ROLE_STRAP := "strap"


static func param_spec() -> Array:
	return [
		{"name": "width", "label": "Strap width", "type": "int", "default": 1,
			"min": 1, "max": 2},
	]


## The strap columns on the character's left (+x) side for a chest; the right
## side mirrors them. Empty when the chest has no room beside the neck.
static func strap_columns(chest: Dictionary, width: int) -> Array[int]:
	var out: Array[int] = []
	if chest.is_empty():
		return out
	var top := int(VoxelTopology.bounds(chest).end.z)   # bounds are inclusive: this IS the top row
	var edge := VoxelTopology.row_extent_x(chest, top).y
	var beside_neck := BodyLayout.NECK_SOCKET_X.y + 1
	if edge < beside_neck:
		return out
	var x := (beside_neck + edge) / 2
	out.append(x)
	if width >= 2:
		# The second column goes outward if the top row reaches that far,
		# otherwise in toward the neck.
		if x + 1 <= edge:
			out.append(x + 1)
		elif x - 1 >= beside_neck:
			out.append(x - 1)
	return out


static func generate(ctx: SpecialItem.Context, params: Dictionary) -> SpecialItem.Result:
	var out := SpecialItem.Result.new()
	var chest := ctx.cells_of("chest")
	if chest.is_empty():
		out.warnings.append("no chest to hang straps from")
		return out
	var columns := strap_columns(chest, clampi(int(params.get("width", 1)), 1, 2))
	if columns.is_empty():
		out.warnings.append("the chest has no room beside the neck for a strap")
		return out

	var done := {}
	for column in columns:
		for x in [column, VoxelAxes.MIRROR_X_MAX - column]:
			# Front and back: this column's frontmost and rearmost chest cell
			# in every row, and the cell just outside each.
			var front := {}   # z -> y
			var back := {}
			var top := -1
			for cell in chest.keys():
				var c: Vector3i = cell
				if c.x != x:
					continue
				front[c.z] = mini(int(front.get(c.z, 999)), c.y)
				back[c.z] = maxi(int(back.get(c.z, -999)), c.y)
				top = maxi(top, c.z)
			if top < 0:
				continue
			var rows: Array = front.keys()
			rows.sort()
			for i in rows.size():
				var z := int(rows[i])
				var f := int(front[z]) - 1
				var b := int(back[z]) + 1
				_add(out, done, chest, Vector3i(x, f, z), Shading.face_tone(VoxelAxes.FRONT))
				_add(out, done, chest, Vector3i(x, b, z), Shading.face_tone(VoxelAxes.BACK))
				if i + 1 >= rows.size() or int(rows[i + 1]) != z + 1:
					continue
				# Where the chest steps in or out from one row to the next (the
				# rounded collar row, a bust), the two strap cells would touch
				# only along an edge. A strap bridges the step: fill across, in
				# whichever row sits further in, so the run stays one piece.
				var f2 := int(front[z + 1]) - 1
				if f2 != f:
					var inner_row := z + 1 if f2 > f else z
					for y in range(mini(f, f2), maxi(f, f2)):
						_add(out, done, chest, Vector3i(x, y, inner_row), Shading.face_tone(VoxelAxes.FRONT))
				var b2 := int(back[z + 1]) + 1
				if b2 != b:
					var inner_row_b := z + 1 if b2 < b else z
					for y in range(mini(b, b2) + 1, maxi(b, b2) + 1):
						_add(out, done, chest, Vector3i(x, y, inner_row_b), Shading.face_tone(VoxelAxes.BACK))
			# Over the top: above the column's top cells, and one further at
			# each end so the top meets the front and back runs.
			for y in range(int(front[top]) - 1, int(back[top]) + 2):
				_add(out, done, chest, Vector3i(x, y, top + 1), Shading.face_tone(VoxelAxes.UP))
	return out


static func _add(out: SpecialItem.Result, done: Dictionary, chest: Dictionary,
		cell: Vector3i, tone: int) -> void:
	if done.has(cell) or chest.has(cell) or not VoxelAxes.in_grid(cell):
		return
	done[cell] = true
	out.claim("chest", cell, ROLE_STRAP, 1, false, tone)
