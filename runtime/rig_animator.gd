@tool
class_name RigAnimator
extends Node

## Plays animation clips (Animations) on a LowpolyRig: every frame it samples the clip and turns the rig's bones,
## cloth bones too (LowpolyRig.apply_pose_values). Nothing is rebuilt, so playing costs the same with cloth as without.
##
## Changing clips blends from the pose the figure had to the new clip over `crossfade` seconds, so a walk starts from
## wherever an idle was. A clip that does not loop holds its last pose and says so (finished).
##
## Keep it outside the rig: a rig's children are replaced whenever its figure is rebuilt.

signal finished(clip_name: String)

var rig: LowpolyRig = null
var clip_name := ""
## seconds into the clip
var time := 0.0
var speed := 1.0
var playing := false

var _from: Dictionary = {}
var _fade_left := 0.0
var _fade := 0.0


static func make(p_rig: LowpolyRig) -> RigAnimator:
	var a := RigAnimator.new()
	a.name = "Animator"
	a.rig = p_rig
	return a


## Play a clip from its start, blending in from the pose the figure has now.
func play(p_clip: String, crossfade: float = 0.2) -> void:
	if Animations.clip(p_clip).is_empty():
		push_error("no animation '%s'" % p_clip)
		return
	_from = rig.current_pose() if rig != null else {}
	clip_name = p_clip
	time = 0.0
	playing = true
	_fade = maxf(crossfade, 0.0)
	_fade_left = _fade
	_apply()


## Stop where it is: the figure keeps the pose it has.
func stop() -> void:
	playing = false


## Move the clip on by `delta` seconds and pose the figure.
func advance(delta: float) -> void:
	if not playing:
		return
	time += delta * speed
	_fade_left = maxf(0.0, _fade_left - delta)
	var c := Animations.clip(clip_name)
	if not bool(c["loop"]) and time >= float(c["length"]):
		time = float(c["length"])
		playing = false
		_apply()
		finished.emit(clip_name)
		return
	_apply()


## The pose being shown: the clip's, blended from where the figure was while the crossfade lasts.
func pose_now() -> Dictionary:
	var pose := Animations.sample(clip_name, time)
	if _fade_left > 0.0 and _fade > 0.0:
		var w := 1.0 - _fade_left / _fade
		pose = Poses.blend(_from, pose, w * w * (3.0 - 2.0 * w))
	return pose


func _apply() -> void:
	if rig != null and rig.figure != null:
		rig.apply_pose_values(pose_now())


func _process(delta: float) -> void:
	if playing and not Engine.is_editor_hint():
		advance(delta)
