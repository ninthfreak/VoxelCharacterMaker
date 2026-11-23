@tool
class_name Animations
extends RefCounted

## Animation clips: poses over time. A pose is the game's own (runtime/poses.gd: part -> Euler angles in degrees, in
## Godot space). A clip is a few key poses, evenly spaced over its length, and whether it loops:
##
##   {"label": shown in the editor, "length": seconds, "loop": bool, "keys": [pose, ...]}
##
## Between its keys every angle moves on a smooth curve through them (uniform Catmull-Rom), so a clip has no corners
## where it passes a key. A looping clip runs from its last key back into its first. The figure does not move over the
## ground: a walk is a walk on the spot, and the game moves the node.
##
## lowpoly/pose.py samples clips the same way (sample), for the review filmstrips; tests/lowpoly_expected.json holds
## samples of every clip that the Godot tests hold this to.
##
## Hanging cloth needs nothing here: it follows cloth bones that the legs turn (LowpolyPose), so a clip moves it too.

const IDLE := "idle"
const WALK := "walk"


static func names() -> Array[String]:
	return [IDLE, WALK]


static func display_name(name: String) -> String:
	var c := clip(name)
	return String(c.get("label", name))


## A clip by name ({} if there is none).
static func clip(name: String) -> Dictionary:
	match name:
		IDLE:
			# Standing, breathing: the chest leans back a little and settles, the arms ease out and in.
			return {"label": "Idle", "length": 3.0, "loop": true, "keys": [
				{"upper_arm_L": Vector3(0, 0, -3), "upper_arm_R": Vector3(0, 0, 3),
					"forearm_L": Vector3(6, 0, 0), "forearm_R": Vector3(6, 0, 0)},
				{"chest": Vector3(1.5, 0, 0), "head": Vector3(-1.5, 0, 0),
					"upper_arm_L": Vector3(0, 0, -5), "upper_arm_R": Vector3(0, 0, 5),
					"forearm_L": Vector3(9, 0, 0), "forearm_R": Vector3(9, 0, 0)},
			]}
		WALK:
			# Two steps: the left foot reaches forward (contact), passes under (the right leg swings through, its knee
			# bent), then the same mirrored. Each arm swings with the opposite leg; the chest turns a little against
			# the hips and the head turns back to face ahead.
			var contact := {
				"thigh_L": Vector3(24, 0, 0), "shin_L": Vector3(-6, 0, 0),
				"thigh_R": Vector3(-18, 0, 0), "shin_R": Vector3(-24, 0, 0),
				"upper_arm_L": Vector3(-16, 0, -3), "forearm_L": Vector3(12, 0, 0),
				"upper_arm_R": Vector3(18, 0, 3), "forearm_R": Vector3(24, 0, 0),
				"chest": Vector3(0, -5, 0), "head": Vector3(0, 4, 0),
			}
			var passing := {
				"thigh_L": Vector3(-2, 0, 0), "shin_L": Vector3(-4, 0, 0),
				"thigh_R": Vector3(10, 0, 0), "shin_R": Vector3(-44, 0, 0),
				"upper_arm_L": Vector3(0, 0, -3), "forearm_L": Vector3(14, 0, 0),
				"upper_arm_R": Vector3(2, 0, 3), "forearm_R": Vector3(16, 0, 0),
			}
			return {"label": "Walk", "length": 1.0, "loop": true, "keys": [contact, passing, mirror(contact), mirror(passing)]}
	return {}


## The same pose for the other side: left and right swapped, and every turn about Y and Z the other way (a turn about
## X, forward or back, is the same on either side).
static func mirror(pose: Dictionary) -> Dictionary:
	var out := {}
	for part in pose.keys():
		var name := String(part)
		var other := name
		if name.ends_with("_L"):
			other = name.trim_suffix("_L") + "_R"
		elif name.ends_with("_R"):
			other = name.trim_suffix("_R") + "_L"
		var v: Vector3 = pose[part]
		out[other] = Vector3(v.x, -v.y, -v.z)
	return out


## The pose a clip (or a clip's name) gives this many seconds in. A looping clip wraps; one that does not holds its
## first key before its start and its last after its end.
static func sample(which: Variant, seconds: float) -> Dictionary:
	var c: Dictionary = clip(String(which)) if which is String else which
	if c.is_empty():
		return {}
	var keys: Array = c["keys"]
	var n := keys.size()
	if n == 1:
		return (keys[0] as Dictionary).duplicate()
	var loop := bool(c["loop"])
	var length := float(c["length"])
	var share := seconds / length
	share = fposmod(share, 1.0) if loop else clampf(share, 0.0, 1.0)
	var spans := n if loop else n - 1                # a looping clip has a span from its last key back to its first
	var at := share * spans
	var i := mini(int(floor(at)), spans - 1)
	var u := at - i
	var key := func(k: int) -> Dictionary:
		return keys[posmod(k, n)] if loop else keys[clampi(k, 0, n - 1)]
	var p0: Dictionary = key.call(i - 1)
	var p1: Dictionary = key.call(i)
	var p2: Dictionary = key.call(i + 1)
	var p3: Dictionary = key.call(i + 2)
	var parts := {}
	for p in [p0, p1, p2, p3]:
		for part in p.keys():
			parts[part] = true
	var out := {}
	for part in parts.keys():
		var a: Vector3 = p0.get(part, Vector3.ZERO)
		var b: Vector3 = p1.get(part, Vector3.ZERO)
		var d: Vector3 = p2.get(part, Vector3.ZERO)
		var e: Vector3 = p3.get(part, Vector3.ZERO)
		out[part] = 0.5 * (2.0 * b + (d - a) * u + (2.0 * a - 5.0 * b + 4.0 * d - e) * u * u
			+ (3.0 * b - a - 3.0 * d + e) * u * u * u)
	return out
