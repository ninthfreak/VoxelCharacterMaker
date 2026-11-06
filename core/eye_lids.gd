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
##   the brow is always the full width of the eye.
##
## The one dark line therefore serves as both brow and lash line; the owner
## accepted that compromise. Each eye has its own state, which is what makes a
## wink. Lid states are not edited in the editor; the Preview tab picks them.

## No lids and no brow: the eye drawing exactly as it is.
const OFF := ""
const DEFAULT := "neutral"

const ROLE_LID := "lid"
const ROLE_BROW := "brow"

## name -> [screen-left eye, screen-right eye], each
## Vector4i(upper lid rows, lower lid rows, pupil dx, pupil dy). Pupil dx is in
## SCREEN terms (+ = toward screen right) so both eyes look the same way.
const STATES := {
	"neutral": [Vector4i(1, 0, 0, 0), Vector4i(1, 0, 0, 0)],
	"wide_open": [Vector4i(0, 0, 0, 0), Vector4i(0, 0, 0, 0)],
	"unimpressed": [Vector4i(2, 0, 0, 0), Vector4i(2, 0, 0, 0)],
	"downcast": [Vector4i(3, 0, 0, -1), Vector4i(3, 0, 0, -1)],
	"tired": [Vector4i(3, 1, 0, -1), Vector4i(3, 1, 0, -1)],
	"suspicious": [Vector4i(2, 2, 0, 0), Vector4i(2, 2, 0, 0)],
	"blink": [Vector4i(4, 2, 0, 0), Vector4i(4, 2, 0, 0)],
	"wink": [Vector4i(1, 0, 0, 0), Vector4i(4, 2, 0, 0)],
}

const ORDER: Array[String] = [
	"neutral", "wide_open", "unimpressed", "downcast", "tired", "suspicious", "blink", "wink",
]


static func names() -> Array[String]:
	return ORDER.duplicate()


static func display_name(state: String) -> String:
	return "(eyes as drawn)" if state == OFF else state.replace("_", " ")


static func has_state(state: String) -> bool:
	return STATES.has(state)


## One eye's numbers for a named state; an unknown name is wide open.
static func eye_state(state: String, eye: String) -> Vector4i:
	var pair: Array = STATES.get(state, STATES["wide_open"])
	return pair[1] if eye == EyeSet.EYE_RIGHT else pair[0]


## Apply a state to one eye's drawing: box cells Vector2i(c, r) -> role, only
## painted cells (an absent cell is skin). The result may include row `h`, the
## brow row above the box.
static func apply(cells: Dictionary, state: Vector4i, eye: String,
		w: int = EyeSet.BOX_W, h: int = EyeSet.BOX_H) -> Dictionary:
	var out := cells.duplicate()
	var upper := clampi(state.x, 0, h)
	var lower := clampi(state.y, 0, h)

	# The pupil moves first, so the lids then cover it where they reach.
	if state.z != 0 or state.w != 0:
		var dc := state.z if eye != EyeSet.EYE_RIGHT else -state.z  # c counts from the outer edge
		var pupils: Array = []
		for cell in out.keys():
			if String(out[cell]) == EyeSet.ROLE_PUPIL:
				pupils.append(cell)
		for cell in pupils:
			out[cell] = EyeSet.ROLE_WHITE
		for cell in pupils:
			var moved := Vector2i((cell as Vector2i).x + dc, (cell as Vector2i).y + state.w)
			if out.has(moved) and String(out[moved]) == EyeSet.ROLE_WHITE:
				out[moved] = EyeSet.ROLE_PUPIL

	var closed := upper + lower >= h
	for cell in out.keys():
		var c: Vector2i = cell
		var from_top := h - 1 - c.y
		if closed or from_top < upper or c.y < lower:
			out[c] = ROLE_LID

	var brow_row := h if upper == 0 else h - upper
	for col in w:
		out[Vector2i(col, brow_row)] = ROLE_BROW
	return out
