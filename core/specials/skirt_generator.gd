@tool
class_name SkirtGenerator
extends RefCounted

## Skirt, and the base shape dresses and robes extend: a waistband on the
## pelvis plus cloth panels hanging across the legs (SPEC.md section 7.4).
##
## Panels are garment-owned rigid parts hung from a pivot on the pelvis and
## rotated by a driver rule, so the skirt swings with the stride instead of
## clipping straight through it. Legs may still clip at extreme poses; accepted.
##
## Lengths are given as region names, not rows, so "to the knee" means the same
## thing on all six bodies.

const ROLE_CLOTH := "cloth"
const ROLE_HEM := "hem"

const PANEL_FRONT := "skirt_panel_front"
const PANEL_BACK := "skirt_panel_back"
const PANEL_LEFT := "skirt_panel_L"
const PANEL_RIGHT := "skirt_panel_R"

## Length options, as the band whose floor the hem reaches.
const LENGTH_BANDS := {
	"to_knee": "knee",
	"to_shin": "shin",
	"to_ankle": "ankle",
}


static func param_spec() -> Array:
	return [
		{
			"name": "length", "label": "Length",
			"type": "enum", "default": "to_knee",
			"options": ["to_knee", "to_shin", "to_ankle"],
		},
		{
			"name": "flare", "label": "Flare",
			"type": "int", "default": 1, "min": 0, "max": 3,
			"hint": "How much wider the hem is than the waist",
		},
		{
			"name": "panels", "label": "Panels",
			"type": "enum", "default": "four",
			"options": ["two", "four"],
			"hint": "Two swing front and back; four add sides",
		},
		{
			"name": "waistband", "label": "Waistband",
			"type": "bool", "default": true,
		},
		{
			"name": "hem_trim", "label": "Hem in its own colour",
			"type": "bool", "default": true,
		},
	]


static func generate(ctx: SpecialItem.Context, params: Dictionary) -> SpecialItem.Result:
	var out := SpecialItem.Result.new()
	var pelvis := ctx.cells_of("pelvis")
	if pelvis.is_empty():
		out.warnings.append("no pelvis geometry to hang a skirt from")
		return out

	var hips := ctx.regions.band("hips")
	var top_z: int = hips.z0 if hips != null else 12
	var length_key := String(params.get("length", "to_knee"))
	var hem_band := String(LENGTH_BANDS.get(length_key, "knee"))
	var hem_z := ctx.band_floor("thigh", hem_band)
	if hem_z >= top_z:
		out.warnings.append("hem band '%s' is not below the hips" % hem_band)
		return out

	# Measure the pelvis at its lowest row: the skirt starts from that outline,
	# so it fits a slim and a heavy body without any per-body authoring.
	var ext_x := ctx.row_extent_x("pelvis", top_z)
	var ext_y := ctx.row_extent_y("pelvis", top_z)
	if ext_x.y < ext_x.x or ext_y.y < ext_y.x:
		out.warnings.append("could not measure the pelvis at row %d" % top_z)
		return out

	if bool(params.get("waistband", true)):
		_waistband(ctx, out)

	var flare: int = clampi(int(params.get("flare", 1)), 0, 3)
	var four := String(params.get("panels", "four")) == "four"
	var hem_trim := bool(params.get("hem_trim", true))

	# Front and back panels span the hip width; side panels span its depth.
	_panel(out, PANEL_FRONT, "pelvis", Vector3(VoxelAxes.MIRROR_X, VoxelAxes.DEPTH_CENTRE, top_z),
		SpecialItem.DRIVER_FORWARD_THIGH,
		ext_x, ext_y.x - 1, true, top_z, hem_z, flare, hem_trim)
	_panel(out, PANEL_BACK, "pelvis", Vector3(VoxelAxes.MIRROR_X, VoxelAxes.DEPTH_CENTRE, top_z),
		SpecialItem.DRIVER_BACKWARD_THIGH,
		ext_x, ext_y.y + 1, true, top_z, hem_z, flare, hem_trim)

	if four:
		_panel(out, PANEL_LEFT, "pelvis",
			Vector3(ext_x.y + 1, VoxelAxes.DEPTH_CENTRE, top_z),
			SpecialItem.DRIVER_THIGH_L,
			ext_y, ext_x.y + 1, false, top_z, hem_z, flare, hem_trim)
		_panel(out, PANEL_RIGHT, "pelvis",
			Vector3(ext_x.x, VoxelAxes.DEPTH_CENTRE, top_z),
			SpecialItem.DRIVER_THIGH_R,
			ext_y, ext_x.x - 1, false, top_z, hem_z, flare, hem_trim)

	return out


## A one-row band around the waist, grown from the pelvis so it follows the body.
static func _waistband(ctx: SpecialItem.Context, out: SpecialItem.Result) -> void:
	var pelvis := ctx.cells_of("pelvis")
	var source: Array = []
	for cell in pelvis.keys():
		var c: Vector3i = cell
		var band := ctx.regions.band_at("pelvis", c.z)
		if band != null and band.name == "waist":
			source.append(c)
	var grown := BulkBuilder.grow(
		pelvis, source, 1, BulkBuilder.EdgeStyle.SOFT, ctx.occupancy)
	for cell in grown.keys():
		out.claim("pelvis", cell, ROLE_CLOTH, int(grown[cell]))


## One hanging panel, one voxel thick.
##
## span       the extent the panel covers across its own width
## fixed      the coordinate it sits at on the other horizontal axis
## across_x   true when the panel's width runs along x (front/back panels)
## flare      how many voxels wider each side gets by the hem
static func _panel(out: SpecialItem.Result, name: String, parent: String, pivot: Vector3,
		driver: String, span: Vector2i, fixed: int, across_x: bool,
		top_z: int, hem_z: int, flare: int, hem_trim: bool) -> void:
	out.panel(name, parent, pivot, driver)

	var rows := top_z - hem_z
	if rows <= 0:
		return
	for z in range(hem_z, top_z):
		# Widen linearly from the waist to the hem.
		var t := float(top_z - 1 - z) / float(maxi(1, rows - 1))
		var widen := int(roundf(t * float(flare)))
		var lo := span.x - widen
		var hi := span.y + widen
		var role := ROLE_HEM if (hem_trim and z == hem_z) else ROLE_CLOTH
		for i in range(lo, hi + 1):
			var cell := Vector3i(i, fixed, z) if across_x else Vector3i(fixed, i, z)
			# Panels hang clear of the body, so reach 1: they are the outermost
			# thing in their own space and nothing layers under them.
			out.claim(name, cell, role, 1)
