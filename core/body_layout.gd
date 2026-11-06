@tool
class_name BodyLayout
extends RefCounted

## The row layout every body and head shares (SPEC.md sections 3 and 4).
##
## tools/build_bodies.py builds the figures from its BANDS table; this is the
## same table for the Godot side, and every other row number in core/, the
## editor and the runtime is derived from it. A test checks it matches the band
## table each body file carries and the head files' pivot, neck socket and eye
## box, so the two cannot drift apart unnoticed.
##
## Rows are inclusive: Vector2i(z0, z1).

const BANDS := {
	"neck": Vector2i(25, 25),
	"lower_head": Vector2i(26, 30),
	"mid_head": Vector2i(31, 36),
	"crown": Vector2i(37, 41),
	"collar": Vector2i(24, 24),
	"upper_chest": Vector2i(20, 23),
	"lower_chest": Vector2i(17, 19),
	"belly": Vector2i(15, 16),
	"waist": Vector2i(14, 14),
	"hips": Vector2i(11, 13),
	"shoulder": Vector2i(21, 23),
	"upper_arm": Vector2i(18, 20),
	"elbow": Vector2i(17, 17),
	"forearm": Vector2i(13, 16),
	"wrist": Vector2i(12, 12),
	"hand": Vector2i(9, 11),
	"upper_thigh": Vector2i(9, 10),
	"lower_thigh": Vector2i(7, 8),
	"knee": Vector2i(6, 6),
	"shin": Vector2i(3, 5),
	"ankle": Vector2i(2, 2),
	"foot": Vector2i(0, 1),
}

## The head: a 4 x 4 neck socket on NECK_ROW, then HEAD_BOTTOM..TOP_ROW.
const NECK_ROW: int = BANDS["neck"].x
const HEAD_BOTTOM: int = BANDS["lower_head"].x
const TOP_ROW: int = BANDS["crown"].y
const HEAD_PIVOT := Vector3(12, 12, NECK_ROW)
const NECK_SOCKET_X := Vector2i(10, 13)
const NECK_SOCKET_Y := Vector2i(10, 13)

## Every head is HEAD_DEPTH deep, centred, so they share one front plane: the
## plane the eyes are drawn on.
const HEAD_DEPTH := 14
const FACE_PLANE_Y: int = 12 - HEAD_DEPTH / 2

## The eye box (SPEC section 5): two boxes of EYE_W x EYE_H, the screen-left
## one starting at EYE_X0, EYE_UNDER skin rows above the bottom of the head.
## The eyes are the same size on every head, always (owner's rule): every head
## gives both boxes and the brow row above them a flat face.
const EYE_W := 5
const EYE_H := 6
const EYE_X0 := 6
const EYE_UNDER := 3
const EYE_Z0: int = HEAD_BOTTOM + EYE_UNDER
const EYE_Z1: int = EYE_Z0 + EYE_H - 1
## Where the brow sits when no lid is down (eyes wide open): the row above.
const BROW_ROW: int = EYE_Z1 + 1

## Joints (corner space). The upper arm's pivot is measured over the rows of
## the arm below the deltoid; see tools/build_bodies.py:pivots().
const PELVIS_PIVOT_Z: int = BANDS["hips"].x
const CHEST_PIVOT_Z: int = BANDS["belly"].x
const UPPER_ARM_PIVOT_Z: int = BANDS["shoulder"].y + 1
const FOREARM_PIVOT_Z: int = BANDS["elbow"].x
const THIGH_PIVOT_Z: int = BANDS["hips"].x
const SHIN_PIVOT_Z: int = BANDS["knee"].x
const UPPER_ARM_ROWS := Vector2i(BANDS["elbow"].x, BANDS["upper_arm"].y - 1)
const FOREARM_ROWS := Vector2i(BANDS["wrist"].x, BANDS["forearm"].y)
const THIGH_ROWS := Vector2i(BANDS["knee"].x, BANDS["upper_thigh"].y)
const SHIN_ROWS := Vector2i(BANDS["ankle"].x, BANDS["shin"].y)


static func rows(band: String) -> Vector2i:
	return BANDS.get(band, Vector2i(-1, -1))


static func z0(band: String) -> int:
	return rows(band).x


static func z1(band: String) -> int:
	return rows(band).y


## The eye box as the head files store it.
static func eye_box_json() -> Dictionary:
	return {
		"left_x": [EYE_X0, EYE_X0 + EYE_W - 1],
		"right_x": [VoxelAxes.MIRROR_X_MAX - EYE_X0 - EYE_W + 1, VoxelAxes.MIRROR_X_MAX - EYE_X0],
		"z": [EYE_Z0, EYE_Z1],
		"plane_y": FACE_PLANE_Y,
		"brow_z": BROW_ROW,
	}
