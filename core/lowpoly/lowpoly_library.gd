@tool
class_name LowpolyLibrary
extends RefCounted

## The low-poly bodies and heads (SPEC.md section 0, lowpoly/README.md), read from assets/lowpoly/.
##
## lowpoly/body.py and lowpoly/heads.py write these files; regenerate them rather than hand-edit. Units are the old
## voxel's, 24 to the metre, in the same axes as every asset here: x across (the figure's left is +x, mirror plane
## x = 12), y depth (the figure faces -y, depth centre y = 12), z up from the floor. So VoxelAxes converts them too.
##
## Eight bodies (slim, average, heavy and short, for each sex) and five heads. All eight bodies have the same corners
## in the same order and the same polygons; each is the feminine average with its corners moved. A short body has
## the same bands at its own, lower heights, and its head is set lower by head_raise.
##
## This class is the only place that knows the low-poly file names.

const DIR := "res://assets/lowpoly"
const SEXES: Array[String] = ["female", "male"]
const BUILDS: Array[String] = ["slim", "average", "heavy", "short"]
const HEAD_SHAPES: Array[String] = ["round", "boxy", "oval", "strong", "heart"]

## The eleven parts, each after its parent. The same as the voxel bodies' (SPEC 3.1).
const PARTS: Array[String] = ["pelvis", "chest", "head", "upper_arm_L", "upper_arm_R", "forearm_L", "forearm_R",
	"thigh_L", "thigh_R", "shin_L", "shin_R"]

var bodies: Dictionary = {}       ## "female_average" -> LowpolyLibrary.Body
var heads: Dictionary = {}        ## "round" -> LowpolyLibrary.Head
var errors: Array[String] = []


## One body as its file has it. The head is not part of it: any head goes on any body.
class Body extends RefCounted:
	var id := ""
	var sex := ""
	var build := ""
	## every corner, in the file's order
	var points := PackedVector3Array()
	## per corner: {part: share}, the parts it follows when the figure moves (at most four, adding up to one)
	var shares: Array = []
	## {corners: PackedInt32Array, region: String, part: String, piece: String, hidden: bool}; hidden polygons
	## are ends buried inside a neighbouring piece and are never drawn
	var polygons: Array = []
	## part -> {"parent": String ("" for the pelvis), "pivot": Vector3}
	var parts: Dictionary = {}
	## band -> Vector2(bottom, top): where each band of the region table is on this body
	var heights: Dictionary = {}
	## how far the head from the head library is moved to sit on this body's neck (0 but on a short body)
	var head_raise := 0.0

	func display_name() -> String:
		return "%s %s" % ["feminine" if sex == "female" else "masculine", build]


## One head as its file has it: every corner follows the head part alone.
class Head extends RefCounted:
	var shape := ""
	var points := PackedVector3Array()
	## {corners: PackedInt32Array, region: String, at: Array}; `at` says where on the head the polygon is:
	## ["ring", ring band, place round it], ["crown", place], ["base", quarter] or ["ear", side]
	var polygons: Array = []


static func body_path(sex: String, build: String) -> String:
	return "%s/body_%s_%s.json" % [DIR, sex, build]


static func head_path(shape: String) -> String:
	return "%s/head_%s.json" % [DIR, shape]


static func body_id(sex: String, build: String) -> String:
	return "%s_%s" % [sex, build]


## Read every body and head. Returns false, with `errors` filled in, if any is missing or malformed.
func load_all() -> bool:
	errors.clear()
	bodies.clear()
	heads.clear()
	for sex in SEXES:
		for build in BUILDS:
			var path := body_path(sex, build)
			var body := _read_body(JsonIO.read_dict(path), sex, build)
			if body == null:
				errors.append("%s: not a low-poly body file" % path)
			else:
				bodies[body.id] = body
	for shape in HEAD_SHAPES:
		var path := head_path(shape)
		var head := _read_head(JsonIO.read_dict(path), shape)
		if head == null:
			errors.append("%s: not a low-poly head file" % path)
		else:
			heads[shape] = head
	return errors.is_empty()


## Body ids in a fixed order: each sex's slim, average, heavy, short.
func body_ids() -> Array[String]:
	var out: Array[String] = []
	for sex in SEXES:
		for build in BUILDS:
			if bodies.has(body_id(sex, build)):
				out.append(body_id(sex, build))
	return out


func head_shapes() -> Array[String]:
	var out: Array[String] = []
	for shape in HEAD_SHAPES:
		if heads.has(shape):
			out.append(shape)
	return out


func body(id: String) -> Body:
	return bodies.get(id, null) as Body


func head(shape: String) -> Head:
	return heads.get(shape, null) as Head


# ------------------------------------------------------------------- reading ---

static func _vec(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _points(list: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in list:
		out.push_back(_vec(v))
	return out


static func _corners(list: Variant, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in list:
		var k := int(i)
		if k < 0 or k >= count:
			return PackedInt32Array()
		out.push_back(k)
	return out


static func _read_body(data: Dictionary, sex: String, build: String) -> Body:
	if String(data.get("format", "")) != "lowpoly_body" or not data.has("vertices"):
		return null
	var b := Body.new()
	b.sex = sex
	b.build = build
	b.id = body_id(sex, build)
	b.points = _points(data["vertices"])
	for w in data.get("shares", []):
		var shares := {}
		for part in (w as Dictionary).keys():
			shares[String(part)] = float(w[part])
		b.shares.append(shares)
	if b.shares.size() != b.points.size():
		return null
	for p in data.get("polygons", []):
		var poly: Dictionary = p
		var corners := _corners(poly.get("v", []), b.points.size())
		if corners.size() < 3:
			return null
		b.polygons.append({"corners": corners, "region": String(poly.get("region", "")),
			"part": String(poly.get("part", "")), "piece": String(poly.get("piece", "")),
			"hidden": bool(poly.get("hidden", false))})
	var parts: Dictionary = data.get("parts", {})
	for part in PARTS:
		if not parts.has(part):
			return null
		var entry: Dictionary = parts[part]
		var parent: Variant = entry.get("parent", null)
		b.parts[part] = {"parent": "" if parent == null else String(parent), "pivot": _vec(entry["pivot"])}
	var heights: Dictionary = data.get("heights", {})
	for band in heights.keys():
		var h: Array = heights[band]
		b.heights[String(band)] = Vector2(float(h[0]), float(h[1]))
	b.head_raise = float(data.get("head_raise", 0.0))
	return b


static func _read_head(data: Dictionary, shape: String) -> Head:
	if String(data.get("format", "")) != "lowpoly_head" or not data.has("vertices"):
		return null
	var h := Head.new()
	h.shape = shape
	h.points = _points(data["vertices"])
	for p in data.get("polygons", []):
		var poly: Dictionary = p
		var corners := _corners(poly.get("v", []), h.points.size())
		if corners.size() < 3:
			return null
		h.polygons.append({"corners": corners, "region": String(poly.get("region", "")), "at": poly.get("at", [])})
	return h
