@tool
class_name SkirtGenerator
extends RefCounted

## Skirt: cloth panels hanging across the legs from the hips, with an optional
## waistband (SPEC.md section 7.4). The lower half of a dress, a robe, a toga,
## a kilt -- a "dress" is an outfit of a matching top and a skirt, not an item.
##
## Panels are garment-owned rigid parts hung from a pivot on the pelvis and
## rotated by a driver rule, so the skirt swings with the stride instead of
## clipping straight through it. Legs may still clip at extreme poses; accepted.
##
## Lengths are given as region names, not rows, so "to the knee" means the same
## thing on all six bodies.
##
## Two settings make it asymmetric, both aimed at one SIDE (the character's own
## left or right):
##
##   slant    the hem rises that many rows from the other side to this one,
##            and the hem trim follows it;
##   opening  "wrap": the front is cut on a line from this side's hip down to
##                    the middle at the hem, so this leg shows -- a wrap skirt,
##                    the lower half of a toga;
##            "front": the front is open down the middle and becomes two flaps,
##                    each following its own leg -- a robe, coat tails.
##
## A narrow slit was tried and dropped: at this size it reads as a stripe.
##
## Every panel is shaded by the way it faces (Shading.face_tone): the front mid,
## the back dark, the sides by which side they are on. Left to the per-voxel
## rule the legs print onto the back of the skirt -- dark where a leg touches
## the cloth, lighter where there is air behind it.

const ROLE_CLOTH := "cloth"
const ROLE_HEM := "hem"

const PANEL_FRONT := "skirt_panel_front"
const PANEL_BACK := "skirt_panel_back"
const PANEL_LEFT := "skirt_panel_L"
const PANEL_RIGHT := "skirt_panel_R"
## The two front flaps of an open-fronted skirt.
const PANEL_FRONT_LEFT := "skirt_panel_front_L"
const PANEL_FRONT_RIGHT := "skirt_panel_front_R"

## Length options, as the band whose floor the hem reaches.
const LENGTH_BANDS := {
	"to_knee": "knee",
	"to_shin": "shin",
	"to_ankle": "ankle",
}

const OPENINGS: Array[String] = ["none", "wrap", "front"]
const SIDES: Array[String] = ["left", "right"]
const MAX_SLANT := 6
## However steep the slant, the high side keeps this many rows of cloth.
const MIN_ROWS := 2


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
			"name": "slant", "label": "Hem slant",
			"type": "int", "default": 0, "min": 0, "max": MAX_SLANT,
			"hint": "Rows the hem rises across the skirt. 0 is level",
		},
		{
			"name": "opening", "label": "Opening",
			"type": "enum", "default": "none",
			"options": OPENINGS,
			"hint": "Wrap shows one leg. Front opens down the middle, like a robe",
		},
		{
			"name": "side", "label": "Side",
			"type": "enum", "default": "left",
			"options": SIDES,
			"hint": "The character's own left or right: where the hem rises and the wrap opens",
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
	var top_z: int = hips.z0 if hips != null else BodyLayout.z0("hips")
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
	# Below the hips the panels must also clear whatever is already worn on
	# the legs (trousers, boots): two parts in one cell would z-fight.
	for part_name in ["pelvis", "thigh_L", "thigh_R", "shin_L", "shin_R"]:
		for cell in ctx.worn_of(part_name).keys():
			var c: Vector3i = cell
			if c.z < top_z and c.z >= hem_z:
				ext_x = Vector2i(mini(ext_x.x, c.x), maxi(ext_x.y, c.x))
				ext_y = Vector2i(mini(ext_y.x, c.y), maxi(ext_y.y, c.y))

	if bool(params.get("waistband", true)):
		_waistband(ctx, out)

	var flare: int = clampi(int(params.get("flare", 1)), 0, 3)
	var four := String(params.get("panels", "four")) == "four"
	var opening := String(params.get("opening", "none"))
	if not (opening in OPENINGS):
		out.warnings.append("unknown skirt opening '%s'" % opening)
		opening = "none"

	# The shape every panel is cut to: where the hem is in each column, and
	# which cells of the front are left open.
	var cut := {
		"top_z": top_z,
		"hem_z": hem_z,
		"flare": flare,
		"hem_trim": bool(params.get("hem_trim", true)),
		"slant": clampi(int(params.get("slant", 0)), 0,
			mini(MAX_SLANT, maxi(0, top_z - hem_z - MIN_ROWS))),
		"high_left": String(params.get("side", "left")) != "right",
		# The slant runs across the skirt at its widest: the hem row.
		"lo": ext_x.x - flare,
		"hi": ext_x.y + flare,
		"opening": opening,
	}

	# Front and back panels span the hip width; side panels span its depth.
	# Once the flare widens a row, a front panel's end and a side panel's end
	# reach the same corner cell. Two rigid parts in one cell z-fight at rest
	# and tear apart when they swing differently, so the first panel to claim
	# a cell keeps it: front and back first, which own the corners.
	var taken := {}
	# Anything already worn keeps its cells too. On a slim body the hand hangs
	# one voxel clear of the hips, so a skirt over trousers meets it: the panel
	# leaves those few cells out rather than share them.
	for part_name in ctx.worn_cells.keys():
		for cell in (ctx.worn_cells[part_name] as Dictionary).keys():
			taken[cell] = true

	var front_pivot := Vector3(VoxelAxes.MIRROR_X, VoxelAxes.DEPTH_CENTRE, top_z)
	if opening == "front":
		# Open down the middle: two flaps, each following its own leg forward.
		_panel(out, taken, PANEL_FRONT_LEFT, front_pivot, SpecialItem.DRIVER_FLAP_L,
			VoxelAxes.FRONT, ext_x, ext_y.x - 1, true, cut, 1)
		_panel(out, taken, PANEL_FRONT_RIGHT, front_pivot, SpecialItem.DRIVER_FLAP_R,
			VoxelAxes.FRONT, ext_x, ext_y.x - 1, true, cut, -1)
	else:
		_panel(out, taken, PANEL_FRONT, front_pivot, SpecialItem.DRIVER_FORWARD_THIGH,
			VoxelAxes.FRONT, ext_x, ext_y.x - 1, true, cut, 0)
	cut["opening"] = "none"   # only the front opens
	_panel(out, taken, PANEL_BACK, front_pivot, SpecialItem.DRIVER_BACKWARD_THIGH,
		VoxelAxes.BACK, ext_x, ext_y.y + 1, true, cut, 0)

	if four:
		_panel(out, taken, PANEL_LEFT,
			Vector3(ext_x.y + 1, VoxelAxes.DEPTH_CENTRE, top_z),
			SpecialItem.DRIVER_THIGH_L, VoxelAxes.VIEWER_RIGHT,
			ext_y, ext_x.y + 1, false, cut, 0)
		_panel(out, taken, PANEL_RIGHT,
			Vector3(ext_x.x, VoxelAxes.DEPTH_CENTRE, top_z),
			SpecialItem.DRIVER_THIGH_R, VoxelAxes.VIEWER_LEFT,
			ext_y, ext_x.x - 1, false, cut, 0)

	return out


## The row the hem sits at in column x: level, or rising toward the high side.
static func hem_row(x: int, cut: Dictionary) -> int:
	var slant := int(cut["slant"])
	if slant <= 0:
		return int(cut["hem_z"])
	var lo := int(cut["lo"])
	var hi := int(cut["hi"])
	var t := clampf(float(x - lo) / float(maxi(1, hi - lo)), 0.0, 1.0)
	if not bool(cut["high_left"]):
		t = 1.0 - t
	return int(cut["hem_z"]) + int(roundf(t * float(slant)))


## Whether the front is open at this cell.
##
## wrap    the open edge runs from the outer hip of the open side at the top
##         row to just past the middle at the level hem; everything on the
##         open side of it is left out.
## front   a gap down the middle, two columns wide at the hips and four at the
##         hem: an upside-down V.
static func front_is_open(x: int, z: int, cut: Dictionary) -> bool:
	var opening := String(cut["opening"])
	if opening == "none":
		return false
	var top_row := int(cut["top_z"]) - 1
	var t := clampf(float(top_row - z) / float(maxi(1, top_row - int(cut["hem_z"]))), 0.0, 1.0)
	# Twice the distance from the mirror line, so the two sides stay symmetric
	# on an even grid: 1 and -1 are the two middle columns.
	var off := 2 * x - VoxelAxes.MIRROR_X_MAX
	if opening == "front":
		return absi(off) <= 1 + 2 * int(roundf(t))
	var side_off := off if bool(cut["high_left"]) else -off
	var outer := 2 * int(cut["hi"]) - VoxelAxes.MIRROR_X_MAX + 2
	return float(side_off) >= lerpf(float(outer), 3.0, t)


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
## outward    the way the panel faces: it fixes the shade of the whole panel
## span       the extent the panel covers across its own width
## fixed      the coordinate it sits at on the other horizontal axis
## across_x   true when the panel's width runs along x (front/back panels)
## cut        the skirt's shape: rows, flare, slant, opening
## half       +1 keeps only the character's left half (x past the mirror
##            line), -1 only the right half, 0 the whole width
static func _panel(out: SpecialItem.Result, taken: Dictionary, name: String,
		pivot: Vector3, driver: String, outward: Vector3i,
		span: Vector2i, fixed: int, across_x: bool, cut: Dictionary, half: int) -> void:
	out.panel(name, "pelvis", pivot, driver)
	var tone := Shading.face_tone(outward)

	var top_z := int(cut["top_z"])
	var hem_z := int(cut["hem_z"])
	var flare := int(cut["flare"])
	var rows := top_z - hem_z
	if rows <= 0:
		return
	for z in range(hem_z, top_z):
		# Widen linearly from the waist to the hem.
		var t := float(top_z - 1 - z) / float(maxi(1, rows - 1))
		var widen := int(roundf(t * float(flare)))
		for i in range(span.x - widen, span.y + widen + 1):
			var cell := Vector3i(i, fixed, z) if across_x else Vector3i(fixed, i, z)
			var hem := hem_row(cell.x, cut)
			if z < hem:
				continue
			if across_x:
				if half != 0 and signi(2 * cell.x - VoxelAxes.MIRROR_X_MAX) != half:
					continue
				if front_is_open(cell.x, z, cut):
					continue
			if taken.has(cell):
				continue
			taken[cell] = true
			# The lowest cell of each column carries the hem colour, so the
			# trim follows a slanted hem.
			var role := ROLE_HEM if (bool(cut["hem_trim"]) and z == hem) else ROLE_CLOTH
			# Panels hang clear of the body, so reach 1: they are the outermost
			# thing in their own space and nothing layers under them.
			out.claim(name, cell, role, 1, false, tone)
