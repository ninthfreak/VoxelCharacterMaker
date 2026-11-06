@tool
class_name FaceDef
extends RefCounted

## The shipped open eye, as a skin-tight overlay (SPEC.md section 5).
##
## The owner wants eyes only -- no brows, no mouths. A face recolours head
## voxels on the face plane and never adds volume, so bulk is always 0 and
## blinking is an overlay swap.
##
## Eye box: 5 wide x 6 tall, all corners rounded (BodyLayout). The same on
## every head. Stored once per eye in BOX CELLS: c counts from that eye's OUTER
## edge (away from the nose) and r from its bottom row.
##
## Roles: white, pupil (the eye colour, which is a colourway), line, skin (the
## overlay leaves the skin there). The face draws UNDER hair and hats. Lids and
## brow are added over it by EyeLids.

const ROLE_WHITE := "white"
const ROLE_PUPIL := "pupil"
const ROLE_LINE := "line"
const ROLE_SKIN := "skin"
const ROLES: Array[String] = [ROLE_WHITE, ROLE_PUPIL, ROLE_LINE, ROLE_SKIN]

var name: String = ""
var plane_y: int = VoxelAxes.FACE_PLANE_Y
var bulk: int = 0
var eye_box: Dictionary = {}       ## w, h, z0, x0, drop, pupil_cols (list), pupil_rows (range)
var screen_left: Dictionary = {}   ## Vector2i(c, r) -> role
var screen_right: Dictionary = {}  ## Vector2i(c, r) -> role
var source_path: String = ""


static func load_from(path: String) -> FaceDef:
	var data := JsonIO.read_dict(path)
	if data.is_empty():
		return null
	var def := FaceDef.new()
	def.source_path = path
	def.name = String(data.get("name", ""))
	def.plane_y = int(data.get("plane_y", VoxelAxes.FACE_PLANE_Y))
	def.bulk = int(data.get("bulk", 0))

	var box: Dictionary = data.get("eye_box", {})
	var drop: Array = []
	for d in (box.get("drop", []) as Array):
		drop.append(Vector2i(int(d[0]), int(d[1])))
	def.eye_box = {
		"w": int(box.get("w", BodyLayout.EYE_W)),
		"h": int(box.get("h", BodyLayout.EYE_H)),
		"z0": int(box.get("z0", BodyLayout.EYE_Z0)),
		"x0": int(box.get("x0", BodyLayout.EYE_X0)),
		"drop": drop,
		# A LIST of columns (build_bodies.py's convention), not a range: the
		# neutral pupil is one column wide.
		"pupil_cols": (box.get("pupil_cols", []) as Array).map(func(v: Variant) -> int: return int(v)),
		"pupil_rows": Vector2i(int(box["pupil_rows"][0]), int(box["pupil_rows"][1])),
	}

	def.screen_left = _read_cells(data.get("left", []))
	def.screen_right = _read_cells(data.get("right", []))

	var problem := def._validate(data)
	if not problem.is_empty():
		push_error("%s: %s" % [path, problem])
		return null
	return def


static func _read_cells(list: Variant) -> Dictionary:
	var out := {}
	for entry in (list as Array):
		var e: Array = entry
		out[Vector2i(int(e[0]), int(e[1]))] = String(e[2])
	return out


func _validate(data: Dictionary) -> String:
	if bulk != 0:
		return "bulk is %d; a face is a skin-tight overlay and must be 0" % bulk
	if plane_y != VoxelAxes.FACE_PLANE_Y:
		return "plane_y is %d, expected %d" % [plane_y, VoxelAxes.FACE_PLANE_Y]
	if screen_left.is_empty() or screen_right.is_empty():
		return "both eyes must be stored"
	for cells in [screen_left, screen_right]:
		for role in (cells as Dictionary).values():
			if not (String(role) in ROLES):
				return "unknown role '%s'" % role
	# The stored absolute voxels must agree with what the box cells generate.
	# They are generated from the same source, so a mismatch means a hand edit.
	if data.has("voxels"):
		var stored := {}
		for v in (data["voxels"] as Array):
			stored[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = String(v[3])
		var built := to_absolute()
		if stored != built:
			return "the stored voxels do not match the box cells (%d vs %d cells)" % [
				stored.size(), built.size()]
	return ""


## Box cell -> absolute voxel, for one eye. c counts from the eye's outer edge.
func cell_to_voxel(c: int, r: int, mirrored: bool) -> Vector3i:
	var x0 := int(eye_box["x0"])
	var x := (VoxelAxes.MIRROR_X_MAX - x0) - c if mirrored else x0 + c
	return Vector3i(x, plane_y, int(eye_box["z0"]) + r)


## The whole face as absolute voxels: Vector3i -> role.
func to_absolute() -> Dictionary:
	var out := {}
	for cell in screen_left.keys():
		var c: Vector2i = cell
		out[cell_to_voxel(c.x, c.y, false)] = screen_left[cell]
	for cell in screen_right.keys():
		var c2: Vector2i = cell
		out[cell_to_voxel(c2.x, c2.y, true)] = screen_right[cell]
	return out


## Cells that actually draw something. A "skin" cell is where the overlay hides
## the eye, so it must still land on the head but it paints plain skin.
func ink_cells() -> Dictionary:
	var out := {}
	var absolute := to_absolute()
	for cell in absolute.keys():
		var role := String(absolute[cell])
		if role != ROLE_SKIN:
			out[cell] = role
	return out


## True when every cell of this face lands on the given head's face plane
## (SPEC section 12: "no eye cell falls off the face plane").
func fits_head(head: HeadDef) -> bool:
	return missing_on_head(head).is_empty()


func missing_on_head(head: HeadDef) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var absolute := to_absolute()
	for cell in absolute.keys():
		var c: Vector3i = cell
		if String(absolute[cell]) == ROLE_SKIN:
			continue
		if not head.cells.has(c):
			out.append(c)
	return out


func is_symmetric() -> bool:
	return screen_left == screen_right


## Role -> colour. The pupil takes the eye colour, which comes from a colourway;
## "skin" resolves to the body's own skin, so the caller passes that in.
static func colour_for_role(role: String, eye_colour: Color) -> Color:
	match role:
		ROLE_WHITE: return Palette.EYE_WHITE
		ROLE_PUPIL: return eye_colour
		ROLE_LINE: return Palette.LID_LINE
	return Color(0, 0, 0, 0)  # skin: the caller keeps the body's own colour


func display_name() -> String:
	return name.replace("_", " ")
