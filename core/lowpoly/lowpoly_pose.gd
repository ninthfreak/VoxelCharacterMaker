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


## Every part standing: no turn at all.
static func rest() -> Dictionary:
	var out := {}
	for part in LowpolyLibrary.PARTS:
		out[part] = [Vec64.identity(), Vec64.v(0.0, 0.0, 0.0)]
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
