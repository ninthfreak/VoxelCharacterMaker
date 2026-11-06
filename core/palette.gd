@tool
class_name Palette
extends RefCounted

## Colours and tone derivation (SPEC.md section 6).
##
## Every colour in the figure resolves to a light/mid/dark triple, which the
## baked tone from Shading then indexes. Skin uses fixed tones; garment colours
## derive their triple from one palette colour.

## Skin: light, mid, dark.
const SKIN_LIGHT := Color8(255, 214, 172)
const SKIN_MID := Color8(236, 178, 134)
const SKIN_DARK := Color8(190, 128, 92)

## Face roles (SPEC section 5). These are flat: no tone is applied, because the
## eye is a skin-tight recolour and shading it would muddy a small pixel feature.
const EYE_BLACK := Color8(20, 20, 26)
const LID_LINE := Color8(70, 38, 24)
const EYE_WHITE := Color8(250, 250, 248)

## Garment derivation from a base palette colour c:
##   light = c + (255 - c) * 0.28      mid = c      dark = c * 0.68
const GARMENT_LIGHT_LIFT := 0.28
const GARMENT_DARK_SCALE := 0.68

## Optional extra legibility: multiply by face orientation. The prototypes used
## this and it reads well, so it is on by default; AssembledCharacter carries
## the flag so it can be turned off without touching the mesher.
const FACE_MUL_TOP := 1.0
const FACE_MUL_FRONT := 0.97
const FACE_MUL_SIDE := 0.9
const FACE_MUL_BACK := 0.84
const FACE_MUL_BOTTOM := 0.74


## Skin is a choice of tone (owner): a short named list, each a mid colour.
## "light" is the original skin exactly; every other tone takes its light and
## dark shades in the same proportions to its mid, so all tones shade alike.
const DEFAULT_SKIN := "light"
const SKIN_TONE_NAMES: Array[String] = ["pale", "light", "tan", "medium", "brown", "deep"]
const SKIN_TONE_MIDS := {
	"pale": Color8(244, 200, 164),
	"light": SKIN_MID,
	"tan": Color8(214, 156, 108),
	"medium": Color8(190, 132, 92),
	"brown": Color8(150, 98, 66),
	"deep": Color8(112, 72, 50),
}

## Brows are the hair colour one shade darker; a bald head with no brow colour
## set gets the brow of this hair colour (dark brown).
const DEFAULT_BROW_HAIR := "hair_brown"


## Light, mid and dark for a skin tone; an unknown name is the default.
static func skin_tones(tone: String = DEFAULT_SKIN) -> Array[Color]:
	if tone == DEFAULT_SKIN or not SKIN_TONE_MIDS.has(tone):
		return [SKIN_LIGHT, SKIN_MID, SKIN_DARK]
	var mid: Color = SKIN_TONE_MIDS[tone]
	return [_scaled(mid, SKIN_LIGHT, SKIN_MID), mid, _scaled(mid, SKIN_DARK, SKIN_MID)]


static func _scaled(mid: Color, shade: Color, reference: Color) -> Color:
	return Color(
		clampf(mid.r * shade.r / reference.r, 0.0, 1.0),
		clampf(mid.g * shade.g / reference.g, 0.0, 1.0),
		clampf(mid.b * shade.b / reference.b, 0.0, 1.0))


## The eyelid: the skin tone half a shade darker (halfway from mid to dark).
static func lid_colour(tone: String = DEFAULT_SKIN) -> Color:
	var t := skin_tones(tone)
	return t[1].lerp(t[2], 0.5)


## A brow from a hair colour: one shade darker (its garment "dark" tone).
static func brow_from_hair(hair: Color) -> Color:
	return garment_tones(hair)[2]


## The light/mid/dark triple for a garment colour.
static func garment_tones(base: Color) -> Array[Color]:
	var light := Color(
		base.r + (1.0 - base.r) * GARMENT_LIGHT_LIFT,
		base.g + (1.0 - base.g) * GARMENT_LIGHT_LIFT,
		base.b + (1.0 - base.b) * GARMENT_LIGHT_LIFT,
		base.a,
	)
	var dark := Color(
		base.r * GARMENT_DARK_SCALE,
		base.g * GARMENT_DARK_SCALE,
		base.b * GARMENT_DARK_SCALE,
		base.a,
	)
	return [light, base, dark]


## Pick a tone out of a triple.
static func apply_tone(tones: Array[Color], tone: int) -> Color:
	if tones.is_empty():
		return Color.MAGENTA
	return tones[clampi(tone, 0, tones.size() - 1)]


## Orientation multiplier for a face whose outward normal is an asset-space
## axis direction. Asset space: +z up, -y front, +y back, +/-x sides.
static func face_multiplier(normal: Vector3i) -> float:
	if normal.z > 0:
		return FACE_MUL_TOP
	if normal.z < 0:
		return FACE_MUL_BOTTOM
	if normal.y < 0:
		return FACE_MUL_FRONT
	if normal.y > 0:
		return FACE_MUL_BACK
	return FACE_MUL_SIDE


static func multiply_rgb(c: Color, m: float) -> Color:
	return Color(c.r * m, c.g * m, c.b * m, c.a)


# ---------------------------------------------------------------------------
# Colour-blind-safe UI palette.
#
# The owner is red/green colour blind. Nothing in the editor may encode meaning
# in red vs green alone -- every state carries a label or a shape as well. These
# are the Okabe-Ito eight, which stay distinguishable under all common forms of
# colour blindness (SPEC section 8, Accessibility).
# ---------------------------------------------------------------------------

const UI_BLACK := Color8(0, 0, 0)
const UI_ORANGE := Color8(230, 159, 0)
const UI_SKY := Color8(86, 180, 233)
const UI_GREEN := Color8(0, 158, 115)
const UI_YELLOW := Color8(240, 228, 66)
const UI_BLUE := Color8(0, 114, 178)
const UI_VERMILLION := Color8(213, 94, 0)
const UI_PURPLE := Color8(204, 121, 167)


static func ui_palette() -> Array[Color]:
	return [UI_BLUE, UI_ORANGE, UI_SKY, UI_GREEN, UI_YELLOW, UI_VERMILLION, UI_PURPLE, UI_BLACK]


## A distinct UI colour per index, for role swatches and region highlights.
static func ui_colour(index: int) -> Color:
	var p := ui_palette()
	return p[posmod(index, p.size())]


## Default wardrobe palette: eight starting garment colours, chosen so no two
## differ only in red vs green.
static func default_wardrobe_colours() -> Dictionary:
	return {
		"ink": Color8(38, 42, 58),
		"bone": Color8(226, 219, 198),
		"rust": Color8(166, 84, 48),
		"ochre": Color8(198, 150, 58),
		"moss": Color8(96, 112, 70),
		"teal": Color8(58, 116, 124),
		"slate": Color8(96, 104, 124),
		"plum": Color8(104, 66, 94),
		# Eyes: the stock colours SPEC section 6 gives, plus two iris colours.
		"eye_white": EYE_WHITE,
		"eye_dark": EYE_BLACK,
		"lid": LID_LINE,
		"eye_blue": Color8(58, 104, 170),
		"eye_amber": Color8(176, 120, 40),
		# Hair.
		"hair_black": Color8(34, 30, 34),
		"hair_brown": Color8(98, 66, 44),
		"hair_auburn": Color8(140, 70, 40),
		"hair_fair": Color8(214, 184, 120),
		"hair_grey": Color8(160, 160, 164),
	}
