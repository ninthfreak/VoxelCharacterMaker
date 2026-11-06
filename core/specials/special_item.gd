@tool
class_name SpecialItem
extends RefCounted

## Special shapes: pieces the region-and-bulk system cannot express -- hoods,
## skirts, capes, beards, buns, bows (SPEC.md section 7.4).
##
## A special shape is ANCHORED to the body at a specific point and otherwise
## has its own form. Only the anchor is measured from the body, which is what
## lets one definition fit all six bodies and all five heads. Each type is a
## generator with a few parameters; lengths are named by body bands ("to the
## knee"), not rows. An item can carry several, alongside its regions.
##
## Long garments that hang across the legs use CLOTH PANELS: garment-owned
## rigid parts hung from a pivot on a body part, rotated by a simple driver
## rule. Legs may clip at extreme poses; that is accepted.

## What a generator returns.
class Result extends RefCounted:
	## Claims on cells: Array of
	## {"part": String, "cell": Vector3i, "role": String, "reach": int}
	var claims: Array = []

	## Garment-owned rigid parts: Array of
	## {"name": String, "parent": String, "pivot": Vector3, "driver": String}
	var panels: Array = []

	var warnings: Array[String] = []

	## `recolour` lets the claim land on a body voxel and repaint it, instead
	## of being refused there as an ordinary special-shape claim is.
	func claim(part: String, cell: Vector3i, role: String, reach: int = 1,
			recolour: bool = false) -> void:
		claims.append({"part": part, "cell": cell, "role": role, "reach": reach,
			"recolour": recolour})

	func panel(name: String, parent: String, pivot: Vector3, driver: String) -> void:
		panels.append({"name": name, "parent": parent, "pivot": pivot, "driver": driver})

	func cell_count() -> int:
		return claims.size()


## Driver rules for cloth panels (SPEC 7.4). The front panel follows the more
## forward thigh, the back panel the more backward one, side panels their own
## thigh.
const DRIVER_FORWARD_THIGH := "forward_thigh"
const DRIVER_BACKWARD_THIGH := "backward_thigh"
const DRIVER_THIGH_L := "thigh_L"
const DRIVER_THIGH_R := "thigh_R"
const DRIVER_STATIC := "static"
## Swing back with whichever thigh is furthest back, and never forward: a cape
## following a leg forward would go through the body when sitting.
const DRIVER_TRAIL := "trail"


## Context handed to every generator.
class Context extends RefCounted:
	var body: BodyDef
	var head: HeadDef
	var regions: RegionMap
	## part name -> Dictionary of Vector3i -> true: the BARE body. Every item
	## grows from this, not from what is already worn (SPEC 7.3 rule 6).
	var part_cells: Dictionary = {}
	## part or panel name -> Dictionary of Vector3i -> true: the figure as worn
	## so far -- the body plus everything claimed before this shape. A shape
	## that hangs clear of the figure (a cape, a skirt's panels) measures from
	## this, so it clears the clothes underneath and not just the skin.
	var worn_cells: Dictionary = {}
	## Every cell of the whole figure, for deciding what is an exposed surface.
	## A generator passes this to BulkBuilder.grow so a garment does not grow
	## through a joint seam. Empty means "judge by the part alone".
	var occupancy: Dictionary = {}

	func cells_of(part: String) -> Dictionary:
		return part_cells.get(part, {})

	## One part as worn so far; falls back to the bare part.
	func worn_of(part: String) -> Dictionary:
		return worn_cells.get(part, cells_of(part))

	## Inclusive x extent of a part's cells in one row, or a reversed range
	## when the row is empty. The measuring is VoxelTopology's.
	func row_extent_x(part: String, z: int) -> Vector2i:
		return VoxelTopology.row_extent_x(cells_of(part), z)

	func row_extent_y(part: String, z: int) -> Vector2i:
		return VoxelTopology.row_extent_y(cells_of(part), z)

	## The first row at or below `from_z` that has any cells of the part.
	func highest_row(part: String, from_z: int) -> int:
		var best := -1
		for cell in cells_of(part).keys():
			var c: Vector3i = cell
			if c.z <= from_z:
				best = maxi(best, c.z)
		return best

	## The z of a band's floor, so a generator can say "to the knee" rather
	## than hard-coding a row.
	func band_floor(family: String, band_name: String) -> int:
		var b := regions.band(band_name)
		if b == null:
			return 0
		return b.z0

	func band_top(band_name: String) -> int:
		var b := regions.band(band_name)
		if b == null:
			return 0
		return b.z1


# --------------------------------------------------------------- registry ---

## Generator type -> script. Kept as a plain lookup so adding a type is one
## line here and one new file; the editor builds its controls from param_spec.
static func types() -> Array[String]:
	return ["skirt", "cape", "hood", "shape"]


## Types that hang cloth panels clear of the figure. They measure the figure as
## worn, so within one item they are placed after its other shapes: a hooded
## cloak's cape then hangs behind its own hood's collar, not through it.
static func hangs_clear(type: String) -> bool:
	return type in ["skirt", "cape"]


static func display_name(type: String) -> String:
	match type:
		"hood": return "Hood"
		"skirt": return "Skirt"
		"cape": return "Cape"
		"shape": return "Drawn shape"
	return type


## Where a type attaches, in words, for the editor. A drawn shape's anchor is
## a parameter, so the caller passes the params to get its actual anchor.
static func anchor_description(type: String, params: Dictionary = {}) -> String:
	match type:
		"hood": return "Anchored to the head; grows from its surface and leaves the face open."
		"skirt": return "Anchored at the hips; hangs as cloth panels that swing with the legs."
		"cape": return "Anchored behind the shoulders; hangs as a panel that trails the legs."
		"shape":
			var anchor := String(params.get("anchor", "chest"))
			return "Anchored at: %s." % Anchors.label(anchor)
	return ""


## Parameter description for the editor, so a new special type does not need
## any editor changes. Each entry:
##   {"name", "label", "type": "int"|"bool"|"enum", "default",
##    "min", "max" (int), "options": Array[String] (enum)}
static func param_spec(type: String) -> Array:
	match type:
		"hood": return HoodGenerator.param_spec()
		"skirt": return SkirtGenerator.param_spec()
		"cape": return CapeGenerator.param_spec()
		"shape": return ShapeGenerator.param_spec()
	return []


static func default_params(type: String) -> Dictionary:
	var out := {}
	for entry in param_spec(type):
		var e: Dictionary = entry
		var value: Variant = e["default"]
		# A fresh copy: a shared default array would be one shape's cells drawn
		# into every new shape.
		if value is Array:
			value = (value as Array).duplicate(true)
		out[String(e["name"])] = value
	return out


## Fill in anything the stored params are missing, so an item authored before a
## parameter existed still generates.
static func with_defaults(type: String, params: Dictionary) -> Dictionary:
	var out := default_params(type)
	for key in params.keys():
		if out.has(key):
			out[key] = params[key]
	return out


static func generate(type: String, ctx: Context, params: Dictionary) -> Result:
	var p := with_defaults(type, params)
	match type:
		"hood": return HoodGenerator.generate(ctx, p)
		"skirt": return SkirtGenerator.generate(ctx, p)
		"cape": return CapeGenerator.generate(ctx, p)
		"shape": return ShapeGenerator.generate(ctx, p)
	var empty := Result.new()
	empty.warnings.append("unknown special type '%s'" % type)
	return empty
