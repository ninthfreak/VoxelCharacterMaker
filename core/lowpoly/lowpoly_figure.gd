@tool
class_name LowpolyFigure
extends RefCounted

## A low-poly character put together: its corners, the parts each corner follows, and its polygons.
##
## This is what the game and the editor draw and pose (runtime/lowpoly_rig.gd). It is built once per change of
## body, head or clothing; posing never rebuilds it. make() puts a bare body and head together in a skin colour;
## LowpolyAssembler dresses it and draws its face, by the rules lowpoly/dress.py and its neighbours hold in Python.
##
## Units and axes are the asset files' (LowpolyLibrary): x across, y depth (the figure faces -y), z up.

var body_id := ""
var head_shape := ""
## every corner, in the asset files' units
var points := PackedVector3Array()
## the same corners in full precision (x, y, z of each in turn): what dressing, special shapes and cloth work from,
## so that they agree with lowpoly/ (Vec64). `points` is these rounded to single precision, for drawing.
var points64 := PackedFloat64Array()
## per corner: {part: share}
var weights: Array = []
## {corners: PackedInt32Array (into points), colour: Color, region: String, part: String, piece: String,
##  hidden: bool, by: String (the worn item that made it, "" for bare skin), at: String (on a head: "ring",
##  "crown", "base" or "ear"; "" elsewhere)}; a hem also has hem: true. The face's polygons are piece "face",
##  with role (white, pupil, line, lid, brow or mouth) and unlit: true for those drawn in their own colour.
var polygons: Array = []
## part -> {"parent": String, "pivot": Vector3, "pivot64": PackedFloat64Array}, every part after its parent
## (LowpolyLibrary.PARTS)
var parts: Dictionary = {}
## hanging cloth (skirts, capes): laid afresh for every pose (LowpolyCloth.lay_all), in draw order
var cloths: Array = []
var warnings: Array[String] = []


## A bare body with a head on it, in one colour. Returns null if the body or the head is not in the library.
static func make(library: LowpolyLibrary, p_body_id: String, p_head_shape: String, skin: Color) -> LowpolyFigure:
	var body := library.body(p_body_id)
	var head := library.head(p_head_shape)
	if body == null or head == null:
		return null
	var f := LowpolyFigure.new()
	f.body_id = p_body_id
	f.head_shape = p_head_shape
	f.parts = body.parts.duplicate(true)
	f.points.append_array(body.points)
	f.points64.append_array(body.points64)
	for w in body.shares:
		f.weights.append((w as Dictionary).duplicate())
	for p in body.polygons:
		var poly: Dictionary = p
		f.polygons.append({"corners": poly["corners"], "colour": skin, "region": poly["region"],
			"part": poly["part"], "piece": poly["piece"], "hidden": poly["hidden"], "by": "", "at": ""})
	# The head library's heads stand at the average body's heights; a short body's neck is lower.
	var first := f.points.size()
	for k in head.points.size():
		f.add_point(Vec64.v(head.points64[3 * k], head.points64[3 * k + 1], head.points64[3 * k + 2] + body.head_raise),
			{"head": 1.0})
	for p in head.polygons:
		var poly: Dictionary = p
		var corners := PackedInt32Array()
		for k in poly["corners"]:
			corners.push_back(first + int(k))
		var at: Array = poly.get("at", [])
		f.polygons.append({"corners": corners, "colour": skin, "region": poly["region"], "part": "head",
			"piece": "head", "hidden": false, "by": "", "at": String(at[0]) if not at.is_empty() else ""})
	return f


## Add a corner (full precision) that follows these parts. Returns its number.
func add_point(p: PackedFloat64Array, shares: Dictionary) -> int:
	points.push_back(Vector3(p[0], p[1], p[2]))
	points64.append_array(p)
	weights.append(shares)
	return points.size() - 1


## A corner in full precision.
func point64(k: int) -> PackedFloat64Array:
	return Vec64.at(points64, k)


func visible_polygons() -> int:
	var n := 0
	for p in polygons:
		if not bool(p["hidden"]):
			n += 1
	return n


func triangles() -> int:
	var n := 0
	for p in polygons:
		if not bool(p["hidden"]):
			n += (p["corners"] as PackedInt32Array).size() - 2
	return n


## Bounds of the corners that a part's visible polygons use, at rest, in the asset files' units. "" for the whole
## figure.
func bounds(part: String = "") -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in polygons:
		if bool(p["hidden"]) or (not part.is_empty() and String(p["part"]) != part):
			continue
		for k in p["corners"]:
			lo = lo.min(points[k])
			hi = hi.max(points[k])
	if lo.x > hi.x:
		return AABB()
	return AABB(lo, hi - lo)
