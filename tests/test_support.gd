@tool
class_name TestReport
extends RefCounted

## Minimal test reporting, so the suite needs no addon and runs headless.
##
## Every acceptance check becomes a test here (CLAUDE.md, Conventions). Numbers
## the low-poly checks compare against come from tests/lowpoly_expected.json,
## which lowpoly/expected.py works out, so nothing in this suite asserts a
## figure that was transcribed by hand.

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
