@tool
class_name Poses
extends RefCounted

## Test poses for checking part splits and pivots (SPEC.md section 8).
##
## A pose is a Dictionary of part name -> Vector3 of Euler angles in DEGREES,
## in Godot space, applied to the joint at that part's pivot. No skinning: the
## parts are rigid and the pivots are the whole animation rig (SPEC section 9).
##
## Reading the axes, in Godot space (+X is the character's RIGHT, +Y up,
## -Z the way the figure faces):
##   X  swings a hanging limb forward (positive) or back (negative)
##   Y  twists it about its own length
##   Z  spreads it sideways: positive moves it to the character's right, so
##      a left limb needs a negative angle to lift away from the body
##
## Those mirrored signs are why the values below are written out per side
## instead of being generated: a sign error is obvious when you can read both.

const REST := "rest"
const ARMS_RAISED := "arms_raised"
const MID_STRIDE := "mid_stride"
const SITTING := "sitting"
const T_POSE := "t_pose"
const REACHING := "reaching"

## How much of a thigh's swing a cloth panel picks up (SPEC 7.4). Panels are
## rule-driven, not simulated; whether that stays so is an open question.
const PANEL_FOLLOW := 0.8


static func names() -> Array[String]:
	return [REST, ARMS_RAISED, T_POSE, MID_STRIDE, SITTING, REACHING]


static func display_name(pose: String) -> String:
	match pose:
		REST: return "Rest"
		ARMS_RAISED: return "Arms raised"
		T_POSE: return "T-pose"
		MID_STRIDE: return "Mid-stride"
		SITTING: return "Sitting"
		REACHING: return "Reaching"
	return pose


static func get_pose(pose: String) -> Dictionary:
	match pose:
		ARMS_RAISED:
			# Straight up: abduct 170 so the arms clear the head.
			return {
				"upper_arm_L": Vector3(0, 0, -170),
				"upper_arm_R": Vector3(0, 0, 170),
				"forearm_L": Vector3(0, 0, -5),
				"forearm_R": Vector3(0, 0, 5),
			}
		T_POSE:
			return {
				"upper_arm_L": Vector3(0, 0, -90),
				"upper_arm_R": Vector3(0, 0, 90),
			}
		MID_STRIDE:
			return {
				"thigh_L": Vector3(28, 0, 0),
				"shin_L": Vector3(-12, 0, 0),
				"thigh_R": Vector3(-22, 0, 0),
				"shin_R": Vector3(-35, 0, 0),
				"upper_arm_L": Vector3(-24, 0, -4),
				"forearm_L": Vector3(-18, 0, 0),
				"upper_arm_R": Vector3(26, 0, 4),
				"forearm_R": Vector3(-30, 0, 0),
				"chest": Vector3(0, -5, 0),
				"head": Vector3(0, 5, 0),
			}
		SITTING:
			# Thighs forward to horizontal, shins straight back down.
			return {
				"thigh_L": Vector3(90, 0, -4),
				"thigh_R": Vector3(90, 0, 4),
				"shin_L": Vector3(-88, 0, 0),
				"shin_R": Vector3(-88, 0, 0),
				"upper_arm_L": Vector3(10, 0, -8),
				"upper_arm_R": Vector3(10, 0, 8),
				"forearm_L": Vector3(-55, 0, 0),
				"forearm_R": Vector3(-55, 0, 0),
				"chest": Vector3(-6, 0, 0),
			}
		REACHING:
			return {
				"upper_arm_L": Vector3(95, 0, -12),
				"forearm_L": Vector3(10, 0, 0),
				"upper_arm_R": Vector3(8, 0, 6),
				"chest": Vector3(0, -14, 0),
				"head": Vector3(0, -10, 0),
			}
	return {}


## Rotation for a cloth panel, from the driver rule and the pose it hangs in.
##
## The front panel follows the more forward thigh, the back panel the more
## backward one, and a side panel its own thigh (SPEC 7.4).
static func panel_rotation(driver: String, pose: Dictionary) -> Vector3:
	var left: Vector3 = pose.get("thigh_L", Vector3.ZERO)
	var right: Vector3 = pose.get("thigh_R", Vector3.ZERO)
	match driver:
		SpecialItem.DRIVER_FORWARD_THIGH:
			return Vector3(maxf(left.x, right.x) * PANEL_FOLLOW, 0, 0)
		SpecialItem.DRIVER_BACKWARD_THIGH:
			return Vector3(minf(left.x, right.x) * PANEL_FOLLOW, 0, 0)
		SpecialItem.DRIVER_THIGH_L:
			return Vector3(0, 0, left.z * PANEL_FOLLOW)
		SpecialItem.DRIVER_THIGH_R:
			return Vector3(0, 0, right.z * PANEL_FOLLOW)
	return Vector3.ZERO


## Blend between two poses, for a quick look at an in-between frame.
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	var keys := {}
	for k in a.keys():
		keys[k] = true
	for k in b.keys():
		keys[k] = true
	for k in keys.keys():
		var va: Vector3 = a.get(k, Vector3.ZERO)
		var vb: Vector3 = b.get(k, Vector3.ZERO)
		out[k] = va.lerp(vb, clampf(t, 0.0, 1.0))
	return out
