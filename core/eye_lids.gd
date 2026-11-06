@tool
class_name EyeLids
extends RefCounted

## Lids and brows over the open eye (SPEC.md section 5).
##
## The eye set draws the eye wide open; a lid state says, per eye, how far the
## upper lid has come down and the lower lid up, and where the pupil looks.
## From those few numbers:
##
##   rows the upper lid covers are LID (the skin, half a shade darker), and
##   its lowest covered row is the BROW line -- the brow leads the lid down;
##   with no upper lid the brow sits on the row above the eye (wide open,
##   brows raised), and in neutral it covers the eye's top row;
##   rows the lower lid covers are LID with no line;
##   when the two lids meet the eye is closed: lid, with the brow line where
##   the upper lid's edge is;
##   the brow is always the full width of the eye;
##   TILT slants the upper lid (and so the brow): +n puts its inner end -- the
##   end nearest the nose -- n rows lower than its outer end (angry), -n puts
##   it n rows higher (sad, worried). Each column gets its own lid depth, in
##   even steps across the eye.
##
## The one dark line therefore serves as both brow and lash line; the owner
## accepted that compromise. Each eye has its own state, which is what makes a
## wink. Lid states are not edited in the editor; the Preview tab picks them.

## No lids and no brow: the eye drawing exactly as it is.
const OFF := ""
const DEFAULT := "neutral"

const ROLE_LID := "lid"
const ROLE_BROW := "brow"

## Index names for one eye's numbers.
const UPPER := 0   ## upper lid rows (at the eye's outer end, when tilted)
const LOWER := 1   ## lower lid rows
const PUPIL_DX := 2  ## pupil shift in SCREEN terms (+ = toward screen right)
const PUPIL_DY := 3  ## pupil shift up (+) or down (-)
const TILT := 4    ## inner end of the upper lid this many rows lower (+) / higher (-)

## name -> [screen-left eye, screen-right eye], each [upper, lower, pupil dx,
## pupil dy, tilt]. Pupil dx is in screen terms so both eyes look the same way;
## tilt is mirrored, so both eyes slant toward (or away from) the nose.
const STATES := {
	"neutral": [[1, 0, 0, 0, 0], [1, 0, 0, 0, 0]],
	"wide_open": [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]],
	"unimpressed": [[2, 0, 0, 0, 0], [2, 0, 0, 0, 0]],
	"downcast": [[3, 0, 0, -1, 0], [3, 0, 0, -1, 0]],
	"tired": [[3, 1, 0, -1, 0], [3, 1, 0, -1, 0]],
	"suspicious": [[2, 2, 0, 0, 0], [2, 2, 0, 0, 0]],
	"angry": [[1, 0, 0, 0, 2], [1, 0, 0, 0, 2]],
	"sad": [[2, 0, 0, -1, -2], [2, 0, 0, -1, -2]],
	"blink": [[4, 2, 0, 0, 0], [4, 2, 0, 0, 0]],
	"wink": [[1, 0, 0, 0, 0], [4, 2, 0, 0, 0]],
}

const ORDER: Array[String] = [
	"neutral", "wide_open", "unimpressed", "downcast", "tired", "suspicious", "angry", "sad",
	"blink", "wink",
]


static func names() -> Array[String]:
	return ORDER.duplicate()


static func display_name(state: String) -> String:
	return "(eyes as drawn)" if state == OFF else state.replace("_", " ")


static func has_state(state: String) -> bool:
	return STATES.has(state)


## One eye's numbers for a named state; an unknown name is wide open.
static func eye_state(state: String, eye: String) -> Array:
	var pair: Array = STATES.get(state, STATES["wide_open"])
	return (pair[1] if eye == EyeSet.EYE_RIGHT else pair[0]) as Array


## How much deeper the upper lid is in column c (counted from the eye's outer
## edge) for a tilt: even steps from 0 at the outer edge to |tilt| at the inner.
static func tilt_offset(c: int, tilt: int, w: int = EyeSet.BOX_W) -> int:
	if tilt == 0 or w <= 1:
		return 0
	var steps := floori(float(absi(tilt) * c) / float(w - 1) + 0.5)
	return steps if tilt > 0 else -steps


## Apply a state to one eye's drawing: box cells Vector2i(c, r) -> role, only
## painted cells (an absent cell is skin). The result may include row `h`, the
## brow row above the box.
static func apply(cells: Dictionary, state: Array, eye: String,
		w: int = EyeSet.BOX_W, h: int = EyeSet.BOX_H) -> Dictionary:
	var out := cells.duplicate()
	var lower := clampi(int(state[LOWER]), 0, h)
	var tilt := int(state[TILT]) if state.size() > TILT else 0
	var dx := int(state[PUPIL_DX])
	var dy := int(state[PUPIL_DY])
	# Each column's upper lid depth: the tilt adds even steps toward the inner
	# end (high c, since c counts from the outer edge on both eyes).
	var upper_at: Array[int] = []
	for col in w:
		upper_at.append(clampi(int(state[UPPER]) + tilt_offset(col, tilt, w), 0, h))

	# The pupil moves first, so the lids then cover it where they reach.
	if dx != 0 or dy != 0:
		var dc := dx if eye != EyeSet.EYE_RIGHT else -dx  # c counts from the outer edge
		var pupils: Array = []
		for cell in out.keys():
			if String(out[cell]) == EyeSet.ROLE_PUPIL:
				pupils.append(cell)
		for cell in pupils:
			out[cell] = EyeSet.ROLE_WHITE
		for cell in pupils:
			var moved := Vector2i((cell as Vector2i).x + dc, (cell as Vector2i).y + dy)
			if out.has(moved) and String(out[moved]) == EyeSet.ROLE_WHITE:
				out[moved] = EyeSet.ROLE_PUPIL

	for cell in out.keys():
		var c: Vector2i = cell
		var upper: int = upper_at[clampi(c.x, 0, w - 1)]
		var from_top := h - 1 - c.y
		if upper + lower >= h or from_top < upper or c.y < lower:
			out[c] = ROLE_LID

	# The brow leads the lid in every column, so a tilted lid has a slanted brow.
	for col in w:
		var upper: int = upper_at[col]
		out[Vector2i(col, h if upper == 0 else h - upper)] = ROLE_BROW
	return out
