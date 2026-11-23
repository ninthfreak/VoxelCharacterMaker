extends SceneTree

## Times what the editor does for common actions, and counts how many times each one rebuilds a figure.
##
##   godot --headless --path . --script res://tools/bench_editor.gd
##
## Headless, so it measures the work (assembling, meshing, laying cloth, refreshing panels), not drawing. Each timing
## is the median of several runs. A "rebuild" is one figure made and shown in a preview (LowpolyRig.rebuilt).

const RUNS := 5

var _frame := 0
var _editor: CharacterEditor = null
var _rebuilds := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var started := Time.get_ticks_usec()
		var packed: PackedScene = load("res://editor/editor_main.tscn")
		_editor = packed.instantiate() as CharacterEditor
		_editor.set("state_path", "user://bench_editor_state.cfg")
		root.add_child(_editor)
		print("start: editor made and in the tree in %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
		return false
	if _frame == 2:
		_run()
		root.remove_child(_editor)
		_editor.free()
		if FileAccess.file_exists("user://bench_editor_state.cfg"):
			DirAccess.remove_absolute("user://bench_editor_state.cfg")
		quit()
	return false


func _count(_x: Variant = null) -> void:
	_rebuilds += 1


## Median time of `action` over RUNS runs (ms), and the rebuilds it made on its last run.
func _time(label: String, action: Callable, setup: Callable = Callable()) -> float:
	var times: Array = []
	var made := 0
	for i in RUNS:
		if setup.is_valid():
			setup.call()
		_rebuilds = 0
		var t0 := Time.get_ticks_usec()
		action.call()
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		made = _rebuilds
	times.sort()
	var median: float = times[times.size() / 2]
	print("  %-62s %8.1f ms   %d rebuild%s" % [label, median, made, "" if made == 1 else "s"])
	return median


func _run() -> void:
	var ed := _editor
	for ws in ed.workspaces:
		(ws as Workspace).view.lowpoly_rig.rebuilt.connect(_count)
	var library := ed.library
	var w := ed.wardrobe

	print("\nbuilding a figure (LowpolyAssembler.assemble), no editor:")
	var cases := {
		"bare": [],
		"everyday outfit": w.outfit("everyday"),
		"travelling (cape, lowered hood)": w.outfit("travelling"),
		"dress (skirt)": w.outfit("dress"),
	}
	for label in cases.keys():
		var req := CharacterRequest.make("female_average", "round", w)
		req.worn = cases[label]
		_time(String(label), func() -> void: LowpolyAssembler.assemble(library, req))
	var up := GarmentItem.create("bench_hood", "bench hood", "accessory")
	up.roles = ["cloth", "lining"]
	up.colourways = {"default": {"cloth": "moss", "lining": "rust"}}
	up.add_special("hood")
	w.add_item(up)
	var hooded := CharacterRequest.make("female_average", "round", w)
	hooded.worn = [{"item": "tunic", "colourway": "default"}, {"item": "bench_hood", "colourway": "default"}]
	_time("tunic and a raised hood", func() -> void: LowpolyAssembler.assemble(library, hooded))
	var shapes := CharacterRequest.make("male_average", "round", w)
	shapes.worn = [{"item": "tunic", "colourway": "default"}]
	shapes.features = [{"item": "ponytail", "colourway": "default"}, {"item": "full_beard", "colourway": "default"},
		{"item": "long_beard", "colourway": "default"}]
	_time("ponytail, full beard and long beard", func() -> void: LowpolyAssembler.assemble(library, shapes))

	print("\nshowing a figure (LowpolyRig), no editor:")
	var rig := LowpolyRig.new()
	root.add_child(rig)
	var travelling := CharacterRequest.make("female_average", "round", w)
	travelling.worn = w.outfit("travelling")
	var tf := LowpolyAssembler.assemble(library, travelling)
	var bare := LowpolyAssembler.assemble(library, CharacterRequest.make("female_average", "round", w))
	_time("build, bare (mesh only)", func() -> void: rig.build(bare, {}))
	_time("build, travelling (mesh, and its cape bound once)", func() -> void: rig.build(tf, {}))
	_time("a new pose for travelling (bones turned, the cape with them)", func() -> void: rig.apply_pose("mid_stride"))
	var animator := RigAnimator.make(rig)
	root.add_child(animator)
	animator.play(Animations.WALK, 0.0)
	_time("one frame of the walk, travelling (bones turned, the cape with them)", func() -> void:
		animator.advance(1.0 / 60.0))
	animator.stop()
	root.remove_child(animator)
	animator.free()
	_time("flat to smooth shading and back (mesh made twice)", func() -> void:
		rig.set_flat_shading(false)
		rig.set_flat_shading(true))
	_time("a click on the figure (picking)", func() -> void: rig.pick(Vector3(0, 1.5, -3), Vector3(0, 0, 1)))
	root.remove_child(rig)
	rig.free()

	print("\nan edit's bookkeeping:")
	_time("the wardrobe as JSON (taken on every edit, for undo)", func() -> void: w.to_json())
	_time("the undo history's commit (JSON taken and kept)", func() -> void: ed.history.commit("bench", w.to_json()))

	print("\nthe editor:")
	_time("Clothes tab brought forward", func() -> void: ed.show_tab("Clothes"),
		func() -> void:
			ed.show_tab("Preview")
			ed.clothes.mark_stale())
	ed.show_tab("Clothes")
	var cl := ed.clothes
	_time("Clothes: select an item (the cloak)", func() -> void: cl.clothes.select("cloak"),
		func() -> void: cl.clothes.select("tunic"))
	cl.clothes.select("cloak")
	var garment: GarmentPanel = cl._garment
	var flip := [0]
	_time("Clothes: change one setting of the cloak's cape (its flare)", func() -> void:
		flip[0] = 1 - flip[0]
		garment._special_index = 0
		garment._set_param(0, "flare", 1 + flip[0], "Flare"))
	_time("  of which: the figure made and shown (rebuild)", func() -> void: cl.rebuild())
	_time("  of which: the item's panel refreshed", func() -> void: garment.refresh())
	_time("  of which: the commit (undo entry)", func() -> void: ed.history.commit("bench", w.to_json()))
	_time("Clothes: wear the travelling outfit", func() -> void: cl.set_worn_list(w.outfit("travelling")))
	var item := w.item("bench_hood")
	cl.clothes.select("bench_hood")
	_time("Clothes: change one setting of a raised hood (its brim)", func() -> void:
		flip[0] = 1 - flip[0]
		garment._special_index = 0
		garment._set_param(0, "brim", 1 + flip[0], "Brim"))

	ed.show_tab("Preview")
	var pv := ed.preview
	var bodies := ["female_average", "male_heavy"]
	var which := [0]
	pv.worn = w.outfit("travelling")
	_time("Preview: another body (travelling outfit)", func() -> void:
		which[0] = 1 - which[0]
		pv._choose("body_id", bodies[which[0]]))
	_time("Preview: another pose (as its menu does it: bones turned)", func() -> void:
		which[0] = 1 - which[0]
		pv.pose = ["rest", "mid_stride"][which[0]]
		pv.view.set_pose(pv.pose))
	_time("Preview: another mouth", func() -> void:
		which[0] = 1 - which[0]
		pv._choose("mouth", ["neutral", "smile"][which[0]]))
	_time("Preview: another lid state", func() -> void:
		which[0] = 1 - which[0]
		pv._choose("lids", ["neutral", "angry"][which[0]]))
	_time("Preview: refresh() alone", func() -> void: pv.refresh())
	pv.worn = [{"item": "tunic", "colourway": "default"}, {"item": "bench_hood", "colourway": "default"}]
	pv.rebuild()
	_time("Preview, wearing a raised hood: another body", func() -> void:
		which[0] = 1 - which[0]
		pv._choose("body_id", bodies[which[0]]))
	_time("Preview, wearing a raised hood: another lid state", func() -> void:
		which[0] = 1 - which[0]
		pv._choose("lids", ["neutral", "angry"][which[0]]))

	ed.show_tab("Face & Hair")
	var fh := ed.face_hair
	_time("Face & Hair: draw eyes (one stroke ends)", func() -> void: fh._eyes_panel._on_drawn())
	_time("Face & Hair: refresh() alone", func() -> void: fh.refresh())
	_time("tab switch to Preview after a change (it catches up)", func() -> void: ed.show_tab("Preview"),
		func() -> void:
			ed.show_tab("Face & Hair")
			ed.preview.mark_stale())
