@tool
class_name ShapeGenerator
extends RefCounted

## A hand-drawn shape hung at an anchor: the most literal form of "anchored to
## the body at specific points, with a shape not otherwise based on the body".
##
## Long beards, buns, ponytails, bows, buckles, pauldrons, brooches.
##
## Two ways to place it, because they answer different needs:
##
##   wrap    every column of the shape is laid onto the surface where it lands,
##           so the shape follows the curve of whatever it sits on. A beard
##           drawn once fits the round head's full jaw and the heart head's
##           narrow one, and a column that would hang in the air beyond a narrow
##           jaw is simply left out.
##   rigid   the shape keeps its own form and sits at a fixed offset from the
##           anchor. A ponytail or a pauldron should not bend round the body.
##
## Depth b = -1 is the surface voxel itself, which RECOLOURS it rather than
## adding volume -- stubble, a tattoo, war paint. That only means anything when
## wrapping, since a rigid shape has no particular surface to recolour.
##
## Cells are stored in the item as [a, b, c, role]; roles are the item's own.

const KIND := "shape"

## The drawing area, in local cells. Big enough for a beard or a bow, small
## enough that a mistake cannot grow into something two metres wide.
const A_MIN := -8
const A_MAX := 8
const B_MIN := -1
const B_MAX := 5
const C_MIN := -10
const C_MAX := 10


static func param_spec() -> Array:
	return [
		{
			"name": "anchor", "label": "Anchored at",
			"type": "enum", "default": "chest",
			"options": Anchors.names(),
		},
		{
			"name": "wrap", "label": "Wrap onto the surface",
			"type": "bool", "default": true,
			"hint": "On: follows the body's curve. Off: keeps its own shape.",
		},
		{
			"name": "mirror", "label": "Mirror onto the other side",
			"type": "bool", "default": true,
		},
		# Drawn in the shape grid, not with a control.
		{"name": "cells", "label": "Shape", "type": "cells", "default": []},
	]


static func generate(ctx: SpecialItem.Context, params: Dictionary) -> SpecialItem.Result:
	var out := SpecialItem.Result.new()
	var anchor_name := String(params.get("anchor", "chest"))
	var anchor := Anchors.find(ctx.part_cells, anchor_name)
	if anchor == null:
		out.warnings.append("anchor '%s' could not be found on this figure" % anchor_name)
		return out

	var wrap := bool(params.get("wrap", true))
	var mirror := bool(params.get("mirror", true))
	var part_cells: Dictionary = ctx.cells_of(anchor.part)

	for entry in (params.get("cells", []) as Array):
		var e: Array = entry
		if e.size() < 4:
			continue
		var a := clampi(int(e[0]), A_MIN, A_MAX)
		var b := clampi(int(e[1]), B_MIN, B_MAX)
		var c := clampi(int(e[2]), C_MIN, C_MAX)
		var role := String(e[3])

		var target: Variant = null
		if wrap:
			var surface: Variant = Anchors.surface_along(
				part_cells, anchor.column(a, c), anchor.out)
			if surface == null:
				continue  # nothing to lie on here: leave the column out
			target = (surface as Vector3i) + anchor.out * (b + 1)
		else:
			if b < 0:
				continue  # rigid shapes have no surface to recolour
			target = anchor.place(a, b, c)

		var cell: Vector3i = target
		var recolour := b < 0
		out.claim(anchor.part, cell, role, maxi(0, b + 1), recolour)
		if mirror:
			out.claim(BodyEdit.mirror_part(anchor.part), VoxelAxes.mirror_voxel(cell),
				role, maxi(0, b + 1), recolour)
	return out


## The cells of a shape as a Dictionary keyed by Vector3i(a, b, c), for the
## editor grid.
static func cells_to_dict(cells: Array) -> Dictionary:
	var out := {}
	for entry in cells:
		var e: Array = entry
		if e.size() >= 4:
			out[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = String(e[3])
	return out


## Back to the stored form, in a stable order.
static func dict_to_cells(cells: Dictionary) -> Array:
	var keys := cells.keys()
	keys.sort_custom(func(p: Vector3i, q: Vector3i) -> bool:
		if p.y != q.y:
			return p.y < q.y
		if p.z != q.z:
			return p.z > q.z
		return p.x < q.x)
	var out: Array = []
	for k in keys:
		var v: Vector3i = k
		out.append([v.x, v.y, v.z, String(cells[k])])
	return out
