@tool
class_name SpecialItem
extends RefCounted

## Special wardrobe items: shapes the bulk system cannot express, and they are
## common -- hoods, skirts, dresses, robes, togas, capes, standing collars,
## pauldrons, hats, long hair (SPEC.md section 7.4).
##
## Each special type is a generator with a few parameters, built from body
## measurements so it still fits every body, using region names for lengths.
## A limited number of types, by design.
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

	func claim(part: String, cell: Vector3i, role: String, reach: int = 1) -> void:
		claims.append({"part": part, "cell": cell, "role": role, "reach": reach})

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


## Context handed to every generator.
class Context extends RefCounted:
	var body: BodyDef
	var head: HeadDef
	var regions: RegionMap
	## part name -> Dictionary of Vector3i -> true, for the body as assembled so
	## far (body plus anything already worn).
	var part_cells: Dictionary = {}
	## Every cell of the whole figure, for deciding what is an exposed surface.
	## A generator passes this to BulkBuilder.grow so a garment does not grow
	## through a joint seam. Empty means "judge by the part alone".
	var occupancy: Dictionary = {}

	func cells_of(part: String) -> Dictionary:
		return part_cells.get(part, {})

	## Inclusive x extent of a part's cells in one row, or a zero rect if empty.
	func row_extent_x(part: String, z: int) -> Vector2i:
		var lo := 9999
		var hi := -9999
		for cell in cells_of(part).keys():
			var c: Vector3i = cell
			if c.z == z:
				lo = mini(lo, c.x)
				hi = maxi(hi, c.x)
		if hi < lo:
			return Vector2i(0, -1)
		return Vector2i(lo, hi)

	func row_extent_y(part: String, z: int) -> Vector2i:
		var lo := 9999
		var hi := -9999
		for cell in cells_of(part).keys():
			var c: Vector3i = cell
			if c.z == z:
				lo = mini(lo, c.y)
				hi = maxi(hi, c.y)
		if hi < lo:
			return Vector2i(0, -1)
		return Vector2i(lo, hi)

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
	return ["hood", "skirt"]


static func display_name(type: String) -> String:
	match type:
		"hood": return "Hood"
		"skirt": return "Skirt"
	return type


## Parameter description for the editor, so a new special type does not need
## any editor changes. Each entry:
##   {"name", "label", "type": "int"|"bool"|"enum", "default",
##    "min", "max" (int), "options": Array[String] (enum)}
static func param_spec(type: String) -> Array:
	match type:
		"hood": return HoodGenerator.param_spec()
		"skirt": return SkirtGenerator.param_spec()
	return []


static func default_params(type: String) -> Dictionary:
	var out := {}
	for entry in param_spec(type):
		var e: Dictionary = entry
		out[String(e["name"])] = e["default"]
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
	var empty := Result.new()
	empty.warnings.append("unknown special type '%s'" % type)
	return empty
