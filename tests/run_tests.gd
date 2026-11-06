extends SceneTree

## Headless test runner. Every acceptance check in SPEC.md section 12 lives in
## one of the suites below (CLAUDE.md: "Tests run headless").
##
## Run from the repository root:
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Expected asset numbers come from tests/expected.json. Regenerate it after
## changing anything in assets/:
##
##   python3 tools/verify_assets.py
##
## Exit status is 0 when everything passed, 1 otherwise, so CI can use it.


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var report := TestReport.new()

	print("Voxel Character Maker - acceptance checks")
	print("Godot %s" % Engine.get_version_info().get("string", "?"))

	var library := AssetLibrary.new()
	if not library.load_all():
		for error in library.errors:
			print("   FAIL  asset library: %s" % error)
		report.failed += library.errors.size()

	# Ordered so a foundational failure is reported before what it would break.
	TestAxes.run(report, library)
	TestAssets.run(report, library)
	TestFaces.run(report, library)
	TestGarments.run(report, library)
	TestWardrobe.run(report, library)
	TestMesher.run(report, library)
	TestBodyEdit.run(report, library)

	var elapsed := Time.get_ticks_msec() - started
	print("\n%s" % "".lpad(60, "-"))
	print("%s in %d ms" % [report.summary(), elapsed])

	if not report.ok():
		print("\nFailures:")
		for failure in report.failures:
			print("  - %s" % failure)
		print("\nSPEC.md section 12 is the list these come from.")
		quit(1)
		return

	print("every SPEC section 12 acceptance check passed")
	quit(0)
