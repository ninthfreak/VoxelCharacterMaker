class_name TestAnimation
extends RefCounted

## Animation: the clips (runtime/animations.gd) against lowpoly/pose.py's sampling, the animator, and a character
## walking with its cloth.

const EXPECTED_PATH := "res://tests/lowpoly_expected.json"


static func run(t: TestReport, library: LowpolyLibrary) -> void:
	_samples(t)
	_clips(t)
	_animator(t, library)


static func _close(a: Dictionary, b: Dictionary, tolerance: float) -> float:
	var worst := 0.0
	var parts := {}
	for p in a.keys():
		parts[p] = true
	for p in b.keys():
		parts[p] = true
	for p in parts.keys():
		var va: Vector3 = a.get(p, Vector3.ZERO)
		var vb: Vector3 = b.get(p, Vector3.ZERO)
		worst = maxf(worst, (va - vb).abs()[(va - vb).abs().max_axis_index()])
	return worst


static func _samples(t: TestReport) -> void:
	t.group("animation: the clips sample as lowpoly/pose.py samples them")
	var expected := JsonIO.read_dict(EXPECTED_PATH)
	var all: Dictionary = expected.get("animations", {})
	if not t.check(all.size() == Animations.names().size(), "tests/lowpoly_expected.json has every clip sampled",
			"run: python3 lowpoly/expected.py"):
		return
	for name in Animations.names():
		var worst := 0.0
		for s in (all[name] as Array):
			var want := {}
			for part in (s["pose"] as Dictionary).keys():
				var v: Array = s["pose"][part]
				want[part] = Vector3(float(v[0]), float(v[1]), float(v[2]))
			worst = maxf(worst, _close(Animations.sample(name, float(s["seconds"])), want, 0.0))
		t.check(worst < 0.002, "'%s': twelve samples over one and a half lengths, to a thousandth of a degree" % name,
			"%.4f degrees off at most" % worst)


static func _clips(t: TestReport) -> void:
	t.group("animation: the clips")
	for name in Animations.names():
		var c := Animations.clip(name)
		var keys: Array = c["keys"]
		var length := float(c["length"])
		var through := 0.0
		for i in keys.size():
			through = maxf(through, _close(Animations.sample(name, length * i / keys.size()), keys[i], 0.0))
		var seam := _close(Animations.sample(name, length - 1e-4), Animations.sample(name, 0.0), 0.0)
		var largest := 0.0
		var prev := Animations.sample(name, 0.0)
		for step in range(1, 121):
			var cur := Animations.sample(name, length * step / 120.0)
			largest = maxf(largest, _close(cur, prev, 0.0))
			prev = cur
		t.check(through < 1e-4 and seam < 0.05 and largest < 3.0,
			"'%s' (%.1f s, %d keys): passes through its keys, loops with no seam, and no angle moves more than 3 degrees "
			% [name, length, keys.size()] + "in a 120th of it", "keys %.5f, seam %.3f, step %.2f" % [through, seam, largest])
	var walk := Animations.clip(Animations.WALK)
	var k: Array = walk["keys"]
	t.check(_close(k[2], Animations.mirror(k[0]), 0.0) < 1e-9 and _close(Animations.mirror(Animations.mirror(k[0])), k[0], 0.0) < 1e-9,
		"the walk's second step is its first mirrored, and mirroring twice gives the pose back")


static func _animator(t: TestReport, library: LowpolyLibrary) -> void:
	t.group("animation: playing a clip on a figure")
	var w := Wardrobe.create_default()
	var req := w.character("villager").make_request(w)
	var f := LowpolyAssembler.assemble(library, req)
	var rig := LowpolyRig.new()
	rig.build(f)
	var a := RigAnimator.make(rig)
	a.play(Animations.WALK, 0.2)
	t.check(_close(rig.current_pose(), {}, 0.0) < 1e-6, "a clip starts from the pose the figure had (the crossfade's start)")
	a.advance(0.1)
	var half := Poses.blend({}, Animations.sample(Animations.WALK, 0.1), 0.5)
	t.check(_close(rig.current_pose(), half, 0.0) < 1e-4, "half way through the crossfade, half way to the clip")
	a.advance(0.3)
	t.check(_close(rig.current_pose(), Animations.sample(Animations.WALK, 0.4), 0.0) < 1e-6,
		"after it, the clip itself")
	a.advance(1.0)
	t.check(a.playing and _close(rig.current_pose(), Animations.sample(Animations.WALK, 1.4), 0.0) < 1e-6,
		"and on round its loop")
	a.stop()
	a.advance(0.5)
	t.check(not a.playing and _close(rig.current_pose(), Animations.sample(Animations.WALK, 1.4), 0.0) < 1e-6,
		"stopped, the figure keeps its pose")
	# the skirt walking: sixty frames a step, no point of the cloth jumps, and none goes far from the last frame
	var prev := PackedFloat64Array()
	var largest := 0.0
	for frame in 121:
		var pose := Animations.sample(Animations.WALK, frame / 60.0)
		var cur := PackedFloat64Array()
		for pair in LowpolyCloth.lay_all(f, pose):
			for made in pair[1]:
				cur.append_array(made[0])
		if not prev.is_empty():
			for i in cur.size() / 3:
				largest = maxf(largest, Vec64.norm(Vec64.sub(Vec64.at(cur, i), Vec64.at(prev, i))))
		prev = cur
	# a hem point of a swinging skirt moves about 0.4 a frame at this speed, up to 0.8 at the fastest part of the swing;
	# a jump would be several units (laid afresh for every pose, cloth jumped by up to 9)
	t.check(largest < 1.0, "the villager's skirt walking, at 60 frames a second: no point moves more than 1 unit in a frame",
		"most: %.2f" % largest)
	rig.free()
	a.free()

	t.group("animation: a game character plays one")
	var who := GameCharacter.new()
	who.setup(w, "traveller")
	who.play(Animations.WALK, 0.0)
	who.animator.advance(0.35)
	t.check(_close(who.rig.current_pose(), Animations.sample(Animations.WALK, 0.35), 0.0) < 1e-6,
		"the traveller walks: its rig takes the clip's pose")
	who.set_expression("angry", "frown")
	who.animator.advance(0.1)
	t.check(who.animator.playing and _close(who.rig.current_pose(), Animations.sample(Animations.WALK, 0.45), 0.0) < 1e-6,
		"a new expression (the figure faced again) does not stop the walk")
	who.set_pose(Poses.SITTING)
	t.check(not who.animator.playing and _close(who.rig.current_pose(), Poses.get_pose(Poses.SITTING), 0.0) < 1e-6,
		"a pose stops the animation and holds")
	who.free()
