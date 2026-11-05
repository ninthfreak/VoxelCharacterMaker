@tool
class_name HeadDef
extends RefCounted

## One head shape from the library (SPEC.md section 4).
##
## Every head shares the neck socket (4x4 at z27, x10-13, y10-13), the pivot
## (12, 12, 27), the height z28-41, the ear rows and the eye box, so hair, hats
## and faces fit all five. Heads are exported blank: no eyes.
##
## Head widths differ (12-14), so a pre-drawn hair or hat needs slack or a
## per-head fit. Parametric wardrobe items grow from the surface and fit
## automatically.

const EXPECTED_PIVOT := Vector3(12, 12, 27)
const NECK_ROW := 27
const TOP_ROW := 41

var shape: String = ""
var pivot: Vector3 = EXPECTED_PIVOT
var cells: Dictionary = {}       ## Vector3i -> true
var neck_socket: Dictionary = {} ## {"x": Vector2i, "y": Vector2i, "z": int}
var eye_box: Dictionary = {}     ## {"left_x", "right_x", "z": Vector2i, "plane_y": int}
var source_path: String = ""


static func load_from(path: String) -> HeadDef:
	var data := JsonIO.read_dict(path)
	if data.is_empty():
		return null
	var def := HeadDef.new()
	def.source_path = path
	def.shape = String(data.get("shape", ""))
	def.pivot = JsonIO.to_vec3(data.get("pivot", [12, 12, 27]))
	def.cells = JsonIO.voxel_set(data.get("voxels", []))

	var socket: Array = data.get("neck_socket", [[10, 13], [10, 13], 27])
	def.neck_socket = {
		"x": Vector2i(int(socket[0][0]), int(socket[0][1])),
		"y": Vector2i(int(socket[1][0]), int(socket[1][1])),
		"z": int(socket[2]),
	}

	var box: Dictionary = data.get("eye_box", {})
	def.eye_box = {
		"left_x": Vector2i(int(box["left_x"][0]), int(box["left_x"][1])),
		"right_x": Vector2i(int(box["right_x"][0]), int(box["right_x"][1])),
		"z": Vector2i(int(box["z"][0]), int(box["z"][1])),
		"plane_y": int(box.get("plane_y", VoxelAxes.FACE_PLANE_Y)),
	}

	var problem := def._validate()
	if not problem.is_empty():
		push_error("%s: %s" % [path, problem])
		return null
	return def


func _validate() -> String:
	if cells.is_empty():
		return "no voxels"
	if not pivot.is_equal_approx(EXPECTED_PIVOT):
		return "pivot is %s, expected %s (every head must share it)" % [pivot, EXPECTED_PIVOT]
	for x in range(10, 14):
		for y in range(10, 14):
			if not cells.has(Vector3i(x, y, NECK_ROW)):
				return "neck socket is incomplete at (%d, %d, %d)" % [x, y, NECK_ROW]
	return ""


## The character's own left eye region of the box is on +x; "left_x" in the file
## is the SCREEN-left eye, which is the character's right. Named plainly here to
## keep the two apart.
func screen_left_eye_x() -> Vector2i:
	return eye_box["left_x"]


func screen_right_eye_x() -> Vector2i:
	return eye_box["right_x"]


func eye_rows() -> Vector2i:
	return eye_box["z"]


func face_plane_y() -> int:
	return int(eye_box["plane_y"])


func count() -> int:
	return cells.size()


func width() -> int:
	var lo := 999
	var hi := -999
	for cell in cells.keys():
		var c: Vector3i = cell
		if c.z == NECK_ROW:
			continue
		lo = mini(lo, c.x)
		hi = maxi(hi, c.x)
	return hi - lo + 1


func display_name() -> String:
	return shape
