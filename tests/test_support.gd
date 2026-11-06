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
#
# These delegate to VoxelTopology in core/. The body editor validates a body
# live while you draw it, using the same code these tests judge the shipped
# assets with -- otherwise the editor could call a body valid that the suite
# rejects. The wrappers stay so the tests read the way they always did.

static func components(cells: Dictionary) -> int:
	return VoxelTopology.components(cells)


static func edge_only_contacts(cells: Dictionary) -> Array:
	return VoxelTopology.edge_only_contacts(cells)


static func mirror_of(cells: Dictionary) -> Dictionary:
	return VoxelTopology.mirrored(cells)


static func same_cells(a: Dictionary, b: Dictionary) -> bool:
	return VoxelTopology.same_cells(a, b)


static func face_adjacent(a: Dictionary, b: Dictionary) -> bool:
	return VoxelTopology.touches(a, b)


static func as_set(cells: Variant) -> Dictionary:
	var out := {}
	for cell in cells:
		out[cell] = true
	return out
