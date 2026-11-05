@tool
class_name BulkBuilder
extends RefCounted

## Parametric garment growth: the bulk rules of SPEC.md section 7.3.
##
## A garment lists the regions it covers, each with a colour role and a bulk.
## This turns one region's body cells into the garment cells that region adds.
## It exists exactly once and both the game and the editor call it, because two
## implementations of bulk generation would drift (SPEC section 8).
##
## The rules, and where each is enforced:
##
## 1. Bulk is 0 or more. 0 only recolours the body's own voxels; N adds N
##    voxels.                            -> grow() returns {} for bulk 0
## 2. Growth is sideways only, within the band's own rows, so adjacent bands
##    with different bulk make a hem step.
##                                       -> the flat stencil has dz == 0
## 3. Surfaces facing up or down also grow vertically. Nothing grows below z0.
##                                       -> the up/down stencils, gated on an
##                                          open neighbour; targets with z < 0
##                                          are dropped
## 4. Each body part grows independently, so arm and torso bulk may overlap in
##    the rest pose and still separate when the figure moves.
##                                       -> only the OWNING part's cells are
##                                          subtracted, never the whole body
## 5. Grown voxels belong to the region and part they grew from.
##                                       -> the caller keeps that association;
##                                          grow() works on one region at a time
## 6. Layering is resolved by reach, then draw order.
##                                       -> CharacterAssembler, using the
##                                          distances returned here
## 7. Edge style per garment: soft (rounded corners, cloth) or hard (squared,
##    plate).                            -> the stencil metric
##
## The returned distance is the Chebyshev layer index, 1..bulk: how far out from
## the body surface a cell sits. "Bulk is measured from the body, not from the
## layer underneath", so this is the number layering compares.

enum EdgeStyle { SOFT, HARD }

## Normal range is 0-3; more is allowed (SPEC 7.3). This only caps the stencil
## cache and guards against a typo turning into a multi-second rebuild.
const MAX_BULK := 12

static var _stencil_cache: Dictionary = {}


static func edge_style_name(style: int) -> String:
	return "hard" if style == EdgeStyle.HARD else "soft"


static func edge_style_from_name(name: String) -> int:
	return EdgeStyle.HARD if name.to_lower() == "hard" else EdgeStyle.SOFT


## Offsets a cell grows into, split by direction so the up/down groups can be
## gated on whether that face is actually open.
##
## Each entry is a Vector4i: (dx, dy, dz, layer). Returns
## {"flat": Array, "up": Array, "down": Array}.
static func stencil(bulk: int, edge_style: int) -> Dictionary:
	var key := "%d:%d" % [bulk, edge_style]
	if _stencil_cache.has(key):
		return _stencil_cache[key]

	var flat: Array = []
	var up: Array = []
	var down: Array = []
	var n := clampi(bulk, 0, MAX_BULK)
	for dx in range(-n, n + 1):
		for dy in range(-n, n + 1):
			for dz in range(-n, n + 1):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var layer := maxi(maxi(absi(dx), absi(dy)), absi(dz))
				if layer > n:
					continue
				if edge_style == EdgeStyle.SOFT:
					# Rounded: a ball, so a 1-bulk shell has no diagonal corner
					# cell and a thicker one steps back as it goes out.
					if dx * dx + dy * dy + dz * dz > n * n:
						continue
				var entry := Vector4i(dx, dy, dz, layer)
				if dz == 0:
					flat.append(entry)
				elif dz > 0:
					up.append(entry)
				else:
					down.append(entry)

	var out := {"flat": flat, "up": up, "down": down}
	_stencil_cache[key] = out
	return out


## Cells of the part that have at least one open face, i.e. the part's surface.
##
## Growth only ever needs to start from the surface: under both metrics the
## nearest source cell to any exterior cell is a surface cell, so seeding from
## interior cells cannot change the result, only cost time.
static func surface_of(part_cells: Dictionary, candidates: Variant = null) -> Array:
	var source: Variant = candidates if candidates != null else part_cells.keys()
	var out: Array = []
	for cell in source:
		var c: Vector3i = cell
		for offset in VoxelAxes.NEIGHBOURS:
			if not part_cells.has(c + offset):
				out.append(c)
				break
	return out


## Grow one region of one part.
##
## part_cells   every cell of the owning part (body plus anything already worn
##              on it, when the caller wants layers to stack outward)
## region_cells the cells of that part inside the region being grown
## Returns Dictionary of Vector3i -> layer (1..bulk), excluding part_cells.
static func grow(part_cells: Dictionary, region_cells: Variant, bulk: int,
		edge_style: int = EdgeStyle.SOFT) -> Dictionary:
	var out := {}
	if bulk <= 0:
		return out  # rule 1: bulk 0 only recolours, it adds nothing

	var sten := stencil(bulk, edge_style)
	var flat: Array = sten["flat"]
	var up: Array = sten["up"]
	var down: Array = sten["down"]

	for cell in surface_of(part_cells, region_cells):
		var c: Vector3i = cell
		_apply(out, part_cells, c, flat)
		# rule 3: only a surface that actually faces up or down grows that way
		if not part_cells.has(c + VoxelAxes.UP):
			_apply(out, part_cells, c, up)
		if not part_cells.has(c + VoxelAxes.DOWN):
			_apply(out, part_cells, c, down)
	return out


static func _apply(out: Dictionary, part_cells: Dictionary, c: Vector3i, offsets: Array) -> void:
	for entry in offsets:
		var o: Vector4i = entry
		var z := c.z + o.z
		if z < 0:
			continue  # rule 3: nothing grows below z0
		var target := Vector3i(c.x + o.x, c.y + o.y, z)
		if part_cells.has(target):
			continue  # rule 1: bulk adds outside the body, it never replaces it
		var layer := o.w
		var seen: Variant = out.get(target)
		if seen == null or int(seen) > layer:
			out[target] = layer


## Cells of a part that fall inside a set of region keys.
## Returns Dictionary of region key -> Array of Vector3i.
static func cells_by_region(part_name: String, part_cells: Dictionary,
		regions: RegionMap, wanted: Dictionary) -> Dictionary:
	var out := {}
	for cell in part_cells.keys():
		var c: Vector3i = cell
		var key := regions.key_for_cell(part_name, c)
		if key.is_empty() or not wanted.has(key):
			continue
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(c)
	return out
