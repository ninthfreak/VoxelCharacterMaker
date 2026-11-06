@tool
class_name CapeGenerator
extends RefCounted

## Cape: a cloth panel hung behind the shoulders, anchored to the back of the
## chest and swinging as a rigid part.
##
## Only the anchor is measured from the body -- the shoulder line and how far
## back the body reaches -- and the cape is otherwise its own shape: a flat sheet
## that flares toward a hem whose height is named by a body band, so "to the
## knee" means the same on every body.
##
## It swings back when a leg strides back and stays put otherwise (the "trail"
## driver). Following a thigh forward, as a skirt's front panel does, would send
## it through the body when sitting.

const ROLE_CLOTH := "cloth"
const ROLE_HEM := "hem"
const PANEL := "cape"

const LENGTH_BANDS := {
	"to_waist": "waist",
	"to_knee": "knee",
	"to_ankle": "ankle",
}

const WIDTHS := {
	"narrow": -1,
	"shoulders": 0,
	"wide": 1,
}


static func param_spec() -> Array:
	return [
		{
			"name": "length", "label": "Length",
			"type": "enum", "default": "to_knee",
			"options": ["to_waist", "to_knee", "to_ankle"],
		},
		{
			"name": "width", "label": "Width",
			"type": "enum", "default": "shoulders",
			"options": ["narrow", "shoulders", "wide"],
		},
		{
			"name": "flare", "label": "Flare",
			"type": "int", "default": 1, "min": 0, "max": 3,
		},
		{
			"name": "hem_trim", "label": "Hem in its own colour",
			"type": "bool", "default": true,
		},
	]


static func generate(ctx: SpecialItem.Context, params: Dictionary) -> SpecialItem.Result:
	var out := SpecialItem.Result.new()
	var chest := ctx.cells_of("chest")
	if chest.is_empty():
		out.warnings.append("no chest to hang a cape from")
		return out

	# The anchor: the shoulder line, and a plane just behind the deepest point
	# of the back anywhere it will hang, so it clears the body when still.
	var collar := ctx.regions.band("collar")
	var top_z: int = collar.z0 if collar != null else 26
	var hem_band := String(LENGTH_BANDS.get(String(params.get("length", "to_knee")), "knee"))
	var hem_z := ctx.band_floor("", hem_band)
	if hem_z >= top_z:
		out.warnings.append("the cape's hem is not below its shoulders")
		return out

	var back_y := -999
	for part_name in ["chest", "pelvis", "thigh_L", "thigh_R", "shin_L", "shin_R"]:
		for cell in ctx.cells_of(part_name).keys():
			var c: Vector3i = cell
			if c.z >= hem_z and c.z <= top_z:
				back_y = maxi(back_y, c.y)
	if back_y < 0:
		out.warnings.append("could not measure the back")
		return out
	var plane_y := back_y + 1

	var shoulder := VoxelTopology.row_extent_x(chest, top_z - 1)
	if shoulder.y < shoulder.x:
		out.warnings.append("could not measure the shoulders")
		return out
	var extra: int = WIDTHS.get(String(params.get("width", "shoulders")), 0)
	var span := Vector2i(shoulder.x - extra, shoulder.y + extra)
	var flare: int = clampi(int(params.get("flare", 1)), 0, 3)
	var hem_trim := bool(params.get("hem_trim", true))

	out.panel(PANEL, "chest", Vector3(VoxelAxes.MIRROR_X, plane_y, top_z + 1),
		SpecialItem.DRIVER_TRAIL)

	var rows := top_z - hem_z
	for z in range(hem_z, top_z + 1):
		var t := float(top_z - z) / float(maxi(1, rows))
		var widen := int(roundf(t * float(flare)))
		var role := ROLE_HEM if (hem_trim and z == hem_z) else ROLE_CLOTH
		for x in range(span.x - widen, span.y + widen + 1):
			out.claim(PANEL, Vector3i(x, plane_y, z), role, 1)
	return out
