@tool
class_name Mouths
extends RefCounted

## Mouths for the low-poly face (owner, 2026-11): a small table next to the lid states (EyeLids), and chosen the same
## way, by name, in the Preview tab. The voxel faces have no mouth; the low-poly face draws one (LowpolyFace).
##
## A mouth is a short line low on the flat part of the face, curved up or down, or a small open oval. Which mouth
## goes with which lid state is not decided: the two are chosen apart.
##
## lowpoly/faces.py draws the same mouths from the same numbers (lowpoly/check.py holds the two tables equal).

## No mouth.
const OFF := ""
const DEFAULT := "neutral"

const LINE := "line"
const OVAL := "oval"

## name -> [LINE, how far the corners turn up against the middle (down if negative)], or
##         [OVAL, [width, height]]; in the files' units
const STATES := {
	"neutral": [LINE, 0.0],
	"smile": [LINE, 0.5],
	"frown": [LINE, -0.45],
	"open": [OVAL, [1.1, 0.8]],
}

const ORDER: Array[String] = ["neutral", "smile", "frown", "open"]


static func names() -> Array[String]:
	return ORDER.duplicate()


static func display_name(state: String) -> String:
	return "(no mouth)" if state == OFF else state.replace("_", " ")


static func has_state(state: String) -> bool:
	return STATES.has(state)
