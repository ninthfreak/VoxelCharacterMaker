@tool
class_name TestReport
extends RefCounted

## Minimal test reporting, so the suite needs no addon and runs headless.
##
## Every acceptance check in SPEC.md section 12 becomes a test here
## (CLAUDE.md, Conventions). Expected numbers come from tests/expected.json,
## which tools/verify_assets.py measures from the shipped assets, so nothing in
## this suite asserts a figure that was transcribed by hand.

const EXPECTED_PATH := "res://tests/expected.json"

var passed := 0
var failed := 0
var failures: Array[String] = []
var _group := ""


func group(name: String) -> void:
	_group = name
	print("\n-- %s" % name)


func check(ok: bool, label: String, detail: String = "") -> bool:
	if ok:
		passed += 1
	else:
		failed += 1
		var text := "%s / %s" % [_group, label]
		if not detail.is_empty():
			text += ": " + detail
		failures.append(text)
		print("   FAIL  %s%s" % [label, "" if detail.is_empty() else "  (%s)" % detail])
	return ok


func check_equal(actual: Variant, expected: Variant, label: String) -> bool:
	return check(actual == expected, label, "got %s, expected %s" % [actual, expected])


func check_near(actual: float, expected: float, label: String,
		tolerance: float = 0.0001) -> bool:
	return check(absf(actual - expected) <= tolerance, label,
		"got %f, expected %f" % [actual, expected])


func note(text: String) -> void:
	print("   note  %s" % text)


func summary() -> String:
	return "%d passed, %d failed" % [passed, failed]


func ok() -> bool:
	return failed == 0


## The measured facts about the shipped assets.
static func expected() -> Dictionary:
	var data := JsonIO.read_dict(EXPECTED_PATH)
	if data.is_empty():
		push_error("%s is missing. Run: python3 tools/verify_assets.py" % EXPECTED_PATH)
	return data


# ------------------------------------------------------------- voxel helpers --

## 6-connected component count of a cell set.
static func components(cells: Dictionary) -> int:
	var todo := cells.duplicate()
	var count := 0
	while not todo.is_empty():
		count += 1
		var seed: Vector3i = todo.keys()[0]
		todo.erase(seed)
		var queue: Array[Vector3i] = [seed]
		while not queue.is_empty():
			var cell: Vector3i = queue.pop_back()
			for offset in VoxelAxes.NEIGHBOURS:
				var next := cell + offset
				if todo.has(next):
					todo.erase(next)
					queue.append(next)
	return count


## Edge- or vertex-only contacts, which would make a straight voxel->STL export
## non-manifold (SPEC section 3.1).
static func edge_only_contacts(cells: Dictionary) -> Array:
	var bad: Array = []
	var probes := [
		[Vector3i(1, 1, 0), Vector3i(1, 0, 0)],
		[Vector3i(1, 0, 1), Vector3i(1, 0, 0)],
		[Vector3i(0, 1, 1), Vector3i(0, 1, 0)],
	]
	for cell in cells.keys():
		var c: Vector3i = cell
		for probe in probes:
			var diagonal: Vector3i = probe[0]
			var first: Vector3i = probe[1]
			if not cells.has(c + diagonal):
				continue
			if cells.has(c + first):
				continue
			if cells.has(c + (diagonal - first)):
				continue
			bad.append(c)
	return bad


static func mirror_of(cells: Dictionary) -> Dictionary:
	var out := {}
	for cell in cells.keys():
		out[VoxelAxes.mirror_voxel(cell)] = true
	return out


static func same_cells(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for cell in a.keys():
		if not b.has(cell):
			return false
	return true


static func face_adjacent(a: Dictionary, b: Dictionary) -> bool:
	for cell in a.keys():
		var c: Vector3i = cell
		for offset in VoxelAxes.NEIGHBOURS:
			if b.has(c + offset):
				return true
	return false


static func as_set(cells: Variant) -> Dictionary:
	var out := {}
	for cell in cells:
		out[cell] = true
	return out
