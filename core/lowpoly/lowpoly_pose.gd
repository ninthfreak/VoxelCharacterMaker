@tool
class_name LowpolyPose
extends RefCounted

## Posing the low-poly figure in full precision: what lowpoly/pose.py does, for the parts of the figure that are
## worked out per pose rather than drawn by the skeleton (hanging cloth, LowpolyCloth).
##
## The skeleton (LowpolyRig) bends the figure for drawing, in single precision. Cloth is laid over the posed figure
## by rules that make choices a hundred-thousandth can tip, so it is laid over the figure as posed here, in double
## precision, the same way lowpoly/ poses it. The two agree to well under a thousandth of a unit.
##
## A pose is the game's own (runtime/poses.gd): part -> Euler angles in degrees about Godot's X, Y and Z. A transform
## is [A, t] (Vec64 matrix and vector): a point of the figure at rest goes to A @ point + t, in the asset files' units.


## For every part, in the order of LowpolyLibrary.PARTS (every part after its parent): [A, t].
## parts: part -> {"parent": String, "pivot64": PackedFloat64Array}, as LowpolyFigure.parts has it.
static func transforms(pose: Dictionary, parts: Dictionary) -> Dictionary:
	var out := {}
	for part in LowpolyLibrary.PARTS:
		var deg: Vector3 = pose.get(part, Vector3.ZERO)
		# lowpoly/pose.py from_game, then transforms: the game's order, turn, then forward, then sideways
		var hangs := not (part in ["chest", "head", "pelvis"])
		var fwd: float = deg.x if hangs else -deg.x
		var turn: float = deg.y
		var side: float = -deg.z if part.ends_with("_L") else deg.z
		var side_sign := -1.0 if part.ends_with("_L") else 1.0
		var r := Vec64.matmul(Vec64.matmul(Vec64.rz(turn), Vec64.rx((-1.0 if hangs else 1.0) * fwd)), Vec64.ry(side_sign * side))
		var entry: Dictionary = parts[part]
		var piv: PackedFloat64Array = entry["pivot64"]
		var t := Vec64.sub(piv, Vec64.apply(r, piv))
		var parent := String(entry["parent"])
		if parent.is_empty():
			out[part] = [r, t]
		else:
			var ap: PackedFloat64Array = out[parent][0]
			var tp: PackedFloat64Array = out[parent][1]
			out[part] = [Vec64.matmul(ap, r), Vec64.add(Vec64.apply(ap, t), tp)]
	return out


## Every part standing: no turn at all (the cloth bones too).
static func rest() -> Dictionary:
	var out := {}
	for part in LowpolyLibrary.PARTS:
		out[part] = [Vec64.identity(), Vec64.v(0.0, 0.0, 0.0)]
	for bone in CLOTH_BONES:
		out[bone] = [Vec64.identity(), Vec64.v(0.0, 0.0, 0.0)]
	return out


## Where a point of the figure at rest goes in a pose: the blend of its parts' movements, by its shares.
static func bend(t: Dictionary, point: PackedFloat64Array, shares: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0])
	for part in shares.keys():
		var m: Array = t[part]
		var moved := Vec64.add(Vec64.apply(m[0], point), m[1])
		var w := float(shares[part])
		out = Vec64.add(out, Vec64.mul(moved, w))
	return out


# ------------------------------------------------------------------------------------------------ cloth bones ---
# Bones that hanging cloth follows (LowpolyCloth, "following the bones"; lowpoly/pose.py, which this follows step for
# step): not parts of the body, turned by the legs. A skirt has a bone for each of its four sides at the hip line,
# under the pelvis, and under each of those another at knee height for the cloth below the knee; a cape has one bone
# at the hip line. A thigh's swing is how far its knee has gone forward of straight down (negative: back), its spread
# how far it leans out to its own side; a shin's reach how far it points forward of straight down; all seen from the
# pelvis.

const FOLLOW := 1.0                  ## how much of a thigh's swing the skirt bones at the hip take
const CAPE_FOLLOW := 0.8             ## how much of the back leg's swing a cape bone takes
const CLOTH_BONES: Array[String] = ["skirt_front", "skirt_back", "skirt_left", "skirt_right", "cape_back",
	"skirt_front_low", "skirt_back_low", "skirt_left_low", "skirt_right_low"]
## a cloth bone's parent (the others: the pelvis)
const CLOTH_PARENT := {"skirt_front_low": "skirt_front", "skirt_back_low": "skirt_back", "skirt_left_low": "skirt_left",
	"skirt_right_low": "skirt_right"}


static func _pivot(parts: Dictionary, part: String) -> PackedFloat64Array:
	return (parts[part] as Dictionary)["pivot64"]


## Where the skirt's upper bones and the cape's bone turn: between the two hip joints.
static func hip_point(parts: Dictionary) -> PackedFloat64Array:
	return Vec64.mul(Vec64.add(_pivot(parts, "thigh_L"), _pivot(parts, "thigh_R")), 0.5)


## Where the skirt's lower bones turn: at the hip point's middle and depth, at knee height.
static func knee_point(parts: Dictionary) -> PackedFloat64Array:
	var p := hip_point(parts)
	p[2] = 0.5 * (_pivot(parts, "shin_L")[2] + _pivot(parts, "shin_R")[2])
	return p


## {side: [swing, spread, reach]} in degrees, for "L" and "R": the thigh's swing and spread, and how far its shin
## points forward of straight down (negative: back), all seen from the pelvis.
static func leg_angles(t: Dictionary) -> Dictionary:
	var ap: PackedFloat64Array = t["pelvis"][0]
	var down := Vec64.v(0.0, 0.0, -1.0)
	var out := {}
	for s in ["L", "R"]:
		var d := Vec64.apply(Vec64.transpose(ap), Vec64.apply(t["thigh_" + s][0], down))
		var swing := rad_to_deg(atan2(-d[1], -d[2]))
		var spread := rad_to_deg(asin(clampf(d[0] if s == "L" else -d[0], -1.0, 1.0)))
		var k := Vec64.apply(Vec64.transpose(ap), Vec64.apply(t["shin_" + s][0], down))
		var reach := rad_to_deg(atan2(-k[1], -k[2]))
		out[s] = [swing, spread, reach]
	return out


## How each cloth bone is turned, under its parent: {bone: matrix}. At the hip, the front of a skirt follows the thigh
## furthest forward, its back the thigh furthest back (each only that way), its sides their own thigh. At the knee, the
## front follows the shin that reaches furthest forward and the back the shin that reaches furthest back (only back),
## whichever leg it is: in a walk the leg swinging through has its thigh forward and its shin back, and the cloth
## behind must clear that heel. A side follows its own shin. A cape follows the thigh furthest back.
static func cloth_turns(t: Dictionary) -> Dictionary:
	var a := leg_angles(t)
	var sl: float = a["L"][0]
	var ol: float = a["L"][1]
	var rl: float = a["L"][2]
	var sr: float = a["R"][0]
	var orr: float = a["R"][1]
	var rr: float = a["R"][2]
	var front := FOLLOW * maxf(maxf(sl, sr), 0.0)
	var back := FOLLOW * minf(minf(sl, sr), 0.0)
	return {
		"skirt_front": Vec64.rx(-front),
		"skirt_back": Vec64.rx(-back),
		"skirt_left": Vec64.matmul(Vec64.rx(-FOLLOW * sl), Vec64.ry(-FOLLOW * ol)),
		"skirt_right": Vec64.matmul(Vec64.rx(-FOLLOW * sr), Vec64.ry(FOLLOW * orr)),
		"skirt_front_low": Vec64.rx(-(maxf(rl, rr) - front)),
		"skirt_back_low": Vec64.rx(-(minf(minf(rl, rr), 0.0) - back)),
		"skirt_left_low": Vec64.rx(-(rl - FOLLOW * sl)),
		"skirt_right_low": Vec64.rx(-(rr - FOLLOW * sr)),
		"cape_back": Vec64.rx(-CAPE_FOLLOW * minf(minf(sl, sr), 0.0)),
	}


## The cloth bone's own pivot: the hip point, or the knee point for a bone at the knee.
static func cloth_pivot(parts: Dictionary, bone: String) -> PackedFloat64Array:
	return knee_point(parts) if bone.ends_with("_low") else hip_point(parts)


static func cloth_parent(bone: String) -> String:
	return String(CLOTH_PARENT.get(bone, "pelvis"))


## t with the cloth bones added: each turned at its own point, carried by its parent.
static func with_cloth_bones(t: Dictionary, parts: Dictionary) -> Dictionary:
	var turns := cloth_turns(t)
	for bone in CLOTH_BONES:
		var r: PackedFloat64Array = turns[bone]
		var piv := cloth_pivot(parts, bone)
		var ap: PackedFloat64Array = t[cloth_parent(bone)][0]
		var tp: PackedFloat64Array = t[cloth_parent(bone)][1]
		t[bone] = [Vec64.matmul(ap, r), Vec64.add(Vec64.apply(ap, Vec64.sub(piv, Vec64.apply(r, piv))), tp)]
	return t
