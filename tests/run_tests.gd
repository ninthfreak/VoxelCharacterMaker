extends SceneTree

## Headless test runner. Every acceptance check in SPEC.md section 12 lives in
## one of the suites below (CLAUDE.md: "Tests run headless").
##
## Run from the repository root:
##
##   tests/run.sh
##
## or directly:
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Expected asset numbers come from tests/expected.json. Regenerate it after
## changing anything in assets/:
##
##   python3 tools/verify_assets.py
##
## Exit status is 0 when everything passed, 1 otherwise, so CI can use it.
##
## The core suites run straight away. The editor suite needs the scene tree
## running -- a node added during _initialize does not get its _ready until
## the tree starts -- so it runs over the first few frames.

var _report := TestReport.new()
var _library := AssetLibrary.new()
var _started := 0
var _frame := 0
var _editor: Control = null


func _initialize() -> void:
	_started = Time.get_ticks_msec()
	print("Voxel Character Maker - acceptance checks")
	print("Godot %s" % Engine.get_version_info().get("string", "?"))

	if not _library.load_all():
		for error in _library.errors:
			print("   FAIL  asset library: %s" % error)
		_report.failed += _library.errors.size()

	# Ordered so a foundational failure is reported before what it would break.
	TestAxes.run(_report, _library)
	TestAssets.run(_report, _library)
	TestFaces.run(_report, _library)
	TestGarments.run(_report, _library)
	TestWardrobe.run(_report, _library)
	TestMesher.run(_report, _library)
	TestBodyEdit.run(_report, _library)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		TestEditor.cleanup()
		_editor = TestEditor.make()
		root.add_child(_editor)
		return false
	if _frame == 2:
		TestEditor.run(_report, _editor as CharacterEditor)
		root.remove_child(_editor)
		_editor.free()
		TestEditor.cleanup()
		# _finish() calls quit() with the right exit status; returning true here
		# would end the loop through a second route, so let quit() do it.
		_finish()
		return false
	return false


func _finish() -> void:
	var elapsed := Time.get_ticks_msec() - _started
	print("\n%s" % "".lpad(60, "-"))
	print("%s in %d ms" % [_report.summary(), elapsed])

	if not _report.ok():
		print("\nFailures:")
		for failure in _report.failures:
			print("  - %s" % failure)
		print("\nSPEC.md section 12 is the list these come from.")
		quit(1)
		return

	print("every SPEC section 12 acceptance check passed")
	quit(0)
