@tool
class_name HoodGenerator
extends RefCounted

## Hood: a shell around the head with the face left open, or bunched at the
## back of the neck when down (SPEC.md section 7.4).
##
## Built from the head's own surface rather than drawn, so it fits all five head
## shapes even though their widths differ. The face opening is sized from the
## eye box, which every head shares, so the eyes are never covered.

const ROLE_CLOTH := "cloth"
const ROLE_LINING := "lining"

## Head bands the raised hood grows from. The neck band is excluded so the hood
## does not fuse to the collar.
const RAISED_BANDS: Array[String] = ["lower_head", "mid_head", "crown"]


static func param_spec() -> Array:
	return [
		{
			"name": "raised", "label": "Up (over the head)",
			"type": "bool", "default": true,
		},
		{
			"name": "depth", "label": "Thickness",
			"type": "int", "default": 1, "min": 1, "max": 3,
		},
		{
			"name": "opening", "label": "Face opening",
			"type": "int", "default": 1, "min": 0, "max": 3,
			"hint": "How far past the eye box the opening reaches",
		},
		{
			"name": "lined", "label": "Separate lining colour",
			"type": "bool", "default": false,
		},
	]


static func generate(ctx: SpecialItem.Context, params: Dictionary) -> SpecialItem.Result:
	var out := SpecialItem.Result.new()
	if bool(params.get("raised", true)):
		_raised(ctx, params, out)
	else:
		_down(ctx, params, out)
	return out


static func _raised(ctx: SpecialItem.Context, params: Dictionary,
		out: SpecialItem.Result) -> void:
	var head_cells := ctx.cells_of("head")
	if head_cells.is_empty():
		out.warnings.append("no head geometry to build a hood on")
		return

	var depth: int = clampi(int(params.get("depth", 1)), 1, 3)
	var source: Array = []
	for cell in head_cells.keys():
		var c: Vector3i = cell
		var band := ctx.regions.band_at("head", c.z)
		if band != null and band.name in RAISED_BANDS:
			source.append(c)

	# A hood is cloth: soft edges.
	var grown := BulkBuilder.grow(
		head_cells, source, depth, BulkBuilder.EdgeStyle.SOFT, ctx.occupancy)

	var opening := _face_opening(ctx, int(params.get("opening", 1)))
	var lined := bool(params.get("lined", false))
	for cell in grown.keys():
		var c2: Vector3i = cell
		if _in_opening(c2, opening):
			continue
		# The innermost layer, where it shows through the opening, reads as
		# lining. Reach is the hood's depth everywhere, because reach is how far
		# the ITEM gets from the body, which is what layering compares.
		var role := ROLE_CLOTH
		if lined and int(grown[cell]) == 1 and c2.y < VoxelAxes.DEPTH_CENTRE:
			role = ROLE_LINING
		out.claim("head", c2, role, depth)


static func _down(ctx: SpecialItem.Context, params: Dictionary,
		out: SpecialItem.Result) -> void:
	# A hood that is down bunches behind the neck and across the upper back.
	var depth: int = clampi(int(params.get("depth", 1)), 1, 3) + 1
	var chest_cells := ctx.cells_of("chest")
	if chest_cells.is_empty():
		out.warnings.append("no chest geometry to rest a lowered hood on")
		return

	var source: Array = []
	for cell in chest_cells.keys():
		var c: Vector3i = cell
		if c.y < VoxelAxes.DEPTH_CENTRE:
			continue  # back half only
		var band := ctx.regions.band_at("chest", c.z)
		if band != null and band.name in ["collar", "upper_chest"]:
			source.append(c)

	var grown := BulkBuilder.grow(
		chest_cells, source, depth, BulkBuilder.EdgeStyle.SOFT, ctx.occupancy)
	for cell in grown.keys():
		var c2: Vector3i = cell
		if c2.y < VoxelAxes.DEPTH_CENTRE:
			continue  # never wrap round to the front
		out.claim("chest", c2, ROLE_CLOTH, int(grown[cell]))


## The face opening, sized from the eye box every head shares.
static func _face_opening(ctx: SpecialItem.Context, slack: int) -> Dictionary:
	var box_x := Vector2i(BodyLayout.EYE_X0, VoxelAxes.MIRROR_X_MAX - BodyLayout.EYE_X0)
	var box_z := Vector2i(BodyLayout.EYE_Z0, BodyLayout.EYE_Z1)
	if ctx.head != null:
		box_x = Vector2i(
			ctx.head.screen_left_eye_x().x,
			ctx.head.screen_right_eye_x().y)
		box_z = ctx.head.eye_rows()
	return {
		"x0": box_x.x - slack,
		"x1": box_x.y + slack,
		"z0": box_z.x - slack - 1,
		"z1": box_z.y + slack,
	}


## Cells in front of the figure inside the opening rectangle are cut away.
static func _in_opening(c: Vector3i, opening: Dictionary) -> bool:
	if c.y >= VoxelAxes.DEPTH_CENTRE:
		return false
	return c.x >= int(opening["x0"]) and c.x <= int(opening["x1"]) \
		and c.z >= int(opening["z0"]) and c.z <= int(opening["z1"])
