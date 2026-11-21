@tool
class_name LowpolyFace
extends RefCounted

## The low-poly face: the eyes with their lids and lashes, the eyebrows and a small mouth, as flat polygons on a
## head's two face patches (owner, 2026-11). The same drawing as lowpoly/faces.py, which this is checked against
## corner by corner (tests/test_lowpoly.gd); read that file for why each part is drawn as it is.
##
## WHAT is shown is the game's: an eye set's open-eye drawing (how much of the eye box it fills, where its pupil
## sits), its colourway (white, pupil, line), a lid state per eye (EyeLids), the lid colour from the skin tone, the
## brow colour from the hair, and a mouth (Mouths).
##
## HOW it is drawn is the low-poly figure's own: the eye a rounded oval filling the box the drawing fills, with an
## oval pupil; a lid cuts it straight across (on a slope when tilted); a thin lash line along the top of the open
## eye; a brow bar of its own above the eye that moves with the lid; a mouth low on the flat of the face.
##
## The polygons tile the face without overlapping, a small height off it. White, pupil and lash line are drawn in
## their own colour, untouched by the light; lid, brow and mouth are lit like the skin.
##
## Everything is worked out in full precision (flat PackedFloat64Arrays: x, y of each corner in turn, or x, y, z),
## because Godot's vectors are single precision and the cuts must land where the Python's do.

const LIFT := 0.04                  ## how far the face's polygons stand off the face
const EYE_SIZE := 0.9               ## the eye box on the head, against the game's: slightly smaller (owner)
const ROUND := 2.0                  ## the eye's outline: 2 is an ellipse, more is fuller toward its box's corners
const SIDES := 20                   ## corners of the eye's outline
const PUPIL_GROW := [1.3, 1.15]     ## the pupil's oval against the box of the drawing's pupil cells: wider, taller
const PUPIL_SIDES := 12
# In the eye box's own cells and rows, so they shrink with the eye:
const LASH := 0.34                  ## the lash line's thickness at the middle of the eye
const LASH_FLARE := 0.35            ## this much thicker at the eye's outer end, and as much thinner at its inner end
const BROW_REACH := [0.3, 4.9]      ## the brow from end to end, counted from the eye's outer edge
const BROW_GAP := 0.4               ## its lower edge above the top of the eye, at rest
const BROW_THICK := [0.36, 0.62]    ## at its outer end, at its inner end
const BROW_MOVE := 0.3              ## up this far for a wide open eye, down this far for a lid half way down or more
const BROW_TILT := 0.55             ## how much of the upper lid's tilt it takes; it hangs from its higher end
const BROW_PEAK := 0.35             ## where along it, from its outer end, its peak is
const BROW_ARCH := 0.3              ## how far its outer end falls from the peak

const MOUTH_Z := 29.4               ## the height of a straight mouth (the head library's heights)
const MOUTH_WIDE := 2.0             ## a line mouth, corner to corner
const MOUTH_THICK := 0.3
const MOUTH_STEPS := 6              ## pieces in a curved line (even: the mouth is cut where the two patches meet)
const MOUTH_SHADE := [0.62, 0.45, 0.48]     ## the mouth is the skin, darkened and a little toward red

const ROLE_WHITE := "white"
const ROLE_PUPIL := "pupil"
const ROLE_LINE := "line"
const ROLE_LID := "lid"
const ROLE_BROW := "brow"
const ROLE_MOUTH := "mouth"
## drawn in their own colour, untouched by the light
const UNLIT_ROLES: Array[String] = ["white", "pupil", "line"]


# ------------------------------------------------------------------------------------- the whole face ---

## Both eyes with their brows: [{pts (x, y, z of each corner), colour, role, unlit}], in the head library's heights.
## eyes: the eye set; colours: its colourway's colour for each of its roles; lids: a lid state (EyeLids), or
## EyeLids.OFF for the eye as drawn with no brow.
static func eyes(head: LowpolyLibrary.Head, eye_set: EyeSet, colours: Dictionary, lids: String, lid: Color,
		brow: Color) -> Array:
	var w := float(EyeSet.BOX_W)
	var h := float(EyeSet.BOX_H)
	var role_colour := colours.duplicate()
	role_colour[ROLE_LID] = lid
	role_colour[ROLE_BROW] = brow
	var out: Array = []
	for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
		if eye_set.eye_cells(eye).is_empty():
			continue                         # nothing drawn for this eye: nothing to show (an eye erased in the grid)
		var state: Array = [0, 0, 0, 0, 0] if lids == EyeLids.OFF else EyeLids.eye_state(lids, eye)
		var pieces := drawn(shape_of(eye_set.eye_cells(eye)), state, eye, w, h)
		if lids != EyeLids.OFF:
			pieces = with_brow(pieces, brow_of(state, w, h))
		for placed in place(head, pieces, eye, w, h):
			var role := String(placed[1])
			out.append({"pts": placed[0], "colour": role_colour.get(role, Color.MAGENTA), "role": role,
				"unlit": UNLIT_ROLES.has(role)})
	return out


## The mouth: [{pts, colour, role, unlit}], with the shapes in `cover` cut out of it (what hangs over it, such as a
## moustache: flat polygons as x from the face's centre line and height, LowpolyFacialHair.cover()).
static func mouth(head: LowpolyLibrary.Head, state: String, skin: Color, cover: Array = []) -> Array:
	var colour := mouth_colour(skin)
	var pieces: Array = []
	for p in mouth_shape(state):
		pieces.append([p, ROLE_MOUTH])
	var flat: Array = []
	for piece in _without(pieces, cover):
		var p: PackedFloat64Array = piece[0]
		var moved := PackedFloat64Array()
		for i in p.size() / 2:
			moved.append(head.mirror_x + p[2 * i])
			moved.append(p[2 * i + 1])
		flat.append(moved)
	var out: Array = []
	for pts in _on_face(head, flat, LIFT):
		out.append({"pts": pts, "colour": colour, "role": ROLE_MOUTH, "unlit": false})
	return out


## The skin darkened toward red, rounded as Python rounds (half to even).
static func mouth_colour(skin: Color) -> Color:
	return Color8(_round_even(skin.r8 * MOUTH_SHADE[0]), _round_even(skin.g8 * MOUTH_SHADE[1]),
		_round_even(skin.b8 * MOUTH_SHADE[2]))


static func _round_even(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if d > 0.5 or (d == 0.5 and int(f) % 2 == 1):
		return int(f) + 1
	return int(f)


# ------------------------------------------------------------------------------------------- the eye ---
# An eye is worked out flat first, in the game's own eye box: x from the eye's OUTER edge (0 to the box's width), r
# up from its bottom row (0 to the box's height, and one more row for a raised brow). Lid states are in those rows.

## The ovals a drawn eye stands for: {outline, pupil}, each [centre x, centre r, half width, half height]. The
## outline fills the box the drawing fills; the pupil lies over the drawing's pupil cells, a little larger.
static func shape_of(drawing: Dictionary) -> Dictionary:
	var all: Array = drawing.keys()
	var pupil: Array = []
	for cell in all:
		if String(drawing[cell]) == ROLE_PUPIL:
			pupil.append(cell)
	var p := _box(pupil) if not pupil.is_empty() else [0.0, 0.0, 0.0, 0.0]
	return {"outline": _box(all), "pupil": [p[0], p[1], p[2] * PUPIL_GROW[0], p[3] * PUPIL_GROW[1]]}


static func _box(cells: Array) -> Array:
	var c0 := 1 << 30
	var c1 := -(1 << 30)
	var r0 := 1 << 30
	var r1 := -(1 << 30)
	for cell in cells:
		var v: Vector2i = cell
		c0 = mini(c0, v.x)
		c1 = maxi(c1, v.x)
		r0 = mini(r0, v.y)
		r1 = maxi(r1, v.y)
	return [0.5 * (c0 + c1 + 1), 0.5 * (r0 + r1 + 1), 0.5 * (c1 + 1 - c0), 0.5 * (r1 + 1 - r0)]


## One eye as flat pieces [[polygon, role]], roles white, pupil, line (the lashes), lid. state: the game's five
## numbers for this eye: upper lid rows, lower lid rows, pupil dx in screen terms, pupil dy, upper lid tilt.
static func drawn(shape: Dictionary, state: Array, eye: String, w: float, h: float) -> Array:
	var upper := float(state[0])
	var lower := float(state[1])
	var dx := float(state[2])
	var dy := float(state[3])
	var tilt := float(state[4])
	var o: Array = shape["outline"]
	var pp: Array = shape["pupil"]
	var outline := oval(o[0], o[1], o[2], o[3], SIDES, ROUND)
	var has_pupil := float(pp[2]) > 0.0 and float(pp[3]) > 0.0
	var pupil := PackedFloat64Array()
	if has_pupil:
		pupil = oval(float(pp[0]) + (dx if eye != EyeSet.EYE_RIGHT else -dx), float(pp[1]) + dy, pp[2], pp[3], PUPIL_SIDES)
	# the upper lid's edge: the game's steps, as one slope
	var e0 := h - (upper + tilt * (0.0 - 0.5) / (w - 1.0))
	var e1 := h - (upper + tilt * (w - 0.5) / (w - 1.0))
	var pieces: Array = [[_clip(outline, 0.0, e0, w, e1, true), ROLE_LID]]          # the upper lid
	var under := _clip(outline, 0.0, e0, w, e1, false)                              # all of the eye under it
	# the lashes: the top of that, from corner to corner, cut by sliding the shape down its own thickness of lash
	var hole := PackedFloat64Array()
	for i in under.size() / 2:
		var x := under[2 * i]
		hole.append(x)
		hole.append(under[2 * i + 1] - LASH * (1.0 + LASH_FLARE * (1.0 - 2.0 * x / w)))
	var apart := _apart(under, hole)
	for p in apart[0]:
		pieces.append([p, ROLE_LINE])
	var rest: PackedFloat64Array = apart[1]
	pieces.append([_clip(rest, 0.0, lower, w, lower, false), ROLE_LID])            # the lower lid
	var seen := _clip(rest, 0.0, lower, w, lower, true)                             # the eye between the lids
	if not has_pupil:
		pieces.append([seen, ROLE_WHITE])
	else:
		var cut := _apart(seen, pupil)
		for p in cut[0]:
			pieces.append([p, ROLE_WHITE])
		pieces.append([cut[1], ROLE_PUPIL])
	return merge(pieces)


## An eyebrow as flat polygons in the eye's box: an inner part and an outer part that falls away from its peak. It
## rides up a little for a wide open eye, down a little for a lowered lid, and tilts as the lid does, though less,
## hanging from its higher end.
static func brow_of(state: Array, w: float, h: float) -> Array:
	var upper := float(state[0])
	var tilt := float(state[4])
	var x0: float = BROW_REACH[0]
	var x1: float = BROW_REACH[1]
	var xp := x0 + BROW_PEAK * (x1 - x0)
	var base := h + BROW_GAP + BROW_MOVE * (1.0 - minf(maxf(upper, 0.0), 2.0))
	var slope := BROW_TILT * tilt / (w - 1.0)               # rows down for each cell toward the nose
	var low := func(x: float) -> float:
		var drop := slope * (x - x0) if slope > 0.0 else slope * (x - x1)          # nothing at the higher end
		return base - drop - (BROW_ARCH * (xp - x) / (xp - x0) if x < xp else 0.0)
	var thick := func(x: float) -> float:
		return BROW_THICK[0] + (BROW_THICK[1] - BROW_THICK[0]) * (x - x0) / (x1 - x0)
	var part := func(xa: float, xb: float) -> PackedFloat64Array:
		var la: float = low.call(xa)
		var lb: float = low.call(xb)
		return PackedFloat64Array([xa, la, xb, lb, xb, lb + float(thick.call(xb)), xa, la + float(thick.call(xa))])
	return [part.call(x0, xp), part.call(xp, x1)]


## The eye's pieces with the brow added: where the brow lies over the eye it is cut out of what is under it.
static func with_brow(pieces: Array, brow: Array) -> Array:
	for part in brow:
		var out: Array = []
		for piece in pieces:
			var cut := _apart(piece[0], part)
			var inside: PackedFloat64Array = cut[1]
			if inside.size() >= 6 and _area(inside) > 1e-9:
				for p in cut[0]:
					out.append([p, piece[1]])
			else:
				out.append(piece)
		pieces = out
	var merged := merge(pieces)
	for part in brow:
		merged.append([part, ROLE_BROW])
	return merged


# ----------------------------------------------------------------------------------------- the mouth ---

## A mouth as flat polygons (x from the face's centre line, height), cut where the two patches meet. Nothing of it is
## lower than a straight mouth's lower edge, since the flat part of the face ends just under that.
static func mouth_shape(state: String) -> Array:
	var entry: Array = Mouths.STATES[state]
	var t := 0.5 * MOUTH_THICK
	if String(entry[0]) == Mouths.OVAL:
		var size: Array = entry[1]
		var whole := oval(0.0, MOUTH_Z - t + 0.5 * float(size[1]), 0.5 * float(size[0]), 0.5 * float(size[1]), 12)
		return [_tidy(_clip(whole, 0.0, 0.0, 0.0, 1.0, true)), _tidy(_clip(whole, 0.0, 0.0, 0.0, 1.0, false))]
	var v := float(entry[1])
	var n := MOUTH_STEPS if v != 0.0 else 2
	var us := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for k in n + 1:
		var u := MOUTH_WIDE * (float(k) / n - 0.5)
		var b := 2.0 * u / MOUTH_WIDE
		b = b * b                                   # 0 at the middle of the mouth, 1 at its corners
		us.append(u)
		# a smile turns its corners up from the line; a frown stands on its corners and lifts its middle
		zs.append(MOUTH_Z + (v * b if v >= 0.0 else -v * (1.0 - b)))
	var out: Array = []
	for k in n:
		out.append(PackedFloat64Array([us[k], zs[k] - t, us[k + 1], zs[k + 1] - t, us[k + 1], zs[k + 1] + t, us[k], zs[k] + t]))
	return out


## Flat pieces [[polygon, tag]] with convex shapes cut out of them.
static func _without(pieces: Array, shapes: Array) -> Array:
	var out: Array = []
	for piece in pieces:
		out.append([_anticlockwise(piece[0]), piece[1]])
	for shape in shapes:
		var hole := _anticlockwise(shape)
		var next: Array = []
		for piece in out:
			var cut := _apart(piece[0], hole)
			var inside: PackedFloat64Array = cut[1]
			if inside.size() >= 6 and _area(inside) > 1e-9:
				for p in cut[0]:
					var q: PackedFloat64Array = p
					if q.size() >= 6 and _area(q) > 1e-9:
						next.append([q, piece[1]])
			else:
				next.append(piece)
		out = next
	return out


static func _anticlockwise(poly: PackedFloat64Array) -> PackedFloat64Array:
	var n := poly.size() / 2
	var turn := 0.0
	for i in n:
		var j := (i + 1) % n
		turn += poly[2 * i] * poly[2 * j + 1] - poly[2 * j] * poly[2 * i + 1]
	return poly if turn >= 0.0 else _reversed2(poly)


# --------------------------------------------------------------------------------------- on the head ---

## Flat pieces of one eye onto its patch of the head: [[polygon (x, y, z), role]]. The eye box keeps the game's place
## across the face; its middle is half way up the flat part of the face; it is EYE_SIZE of the game's box.
static func place(head: LowpolyLibrary.Head, pieces: Array, eye: String, w: float, h: float) -> Array:
	var cx := head.mirror_x
	var middle := absf(float(EyeSet.BOX_X0) - cx) - 0.5 * w        # the middle of the eye, from the centre line
	var top := 0.5 * (head.face_flat[0] + head.face_flat[1]) + 0.5 * h * EYE_SIZE
	var flat: Array = []
	for piece in pieces:
		var poly: PackedFloat64Array = piece[0]
		var out := PackedFloat64Array()
		for i in poly.size() / 2:
			var o := middle + (0.5 * w - poly[2 * i]) * EYE_SIZE
			out.append(cx - o if eye == EyeSet.EYE_LEFT else cx + o)
			out.append(top - (h - poly[2 * i + 1]) * EYE_SIZE)
		flat.append(out)
	var placed := _on_face(head, flat, LIFT)
	var result: Array = []
	for i in pieces.size():
		result.append([placed[i], pieces[i][1]])
	return result


## Flat polygons given as (x on the head, height) onto the face's patches, facing forward: x, y, z of each corner.
static func _on_face(head: LowpolyLibrary.Head, polys: Array, lift: float) -> Array:
	var out: Array = []
	for poly in polys:
		var p: PackedFloat64Array = poly
		var pts := PackedFloat64Array()
		for i in p.size() / 2:
			pts.append_array(PackedFloat64Array([p[2 * i], head.face_y(p[2 * i]) - lift, p[2 * i + 1]]))
		var ny := 0.0
		var n := pts.size() / 3
		for i in n:
			var j := (i + 1) % n
			ny += pts[3 * i + 2] * pts[3 * j] - pts[3 * i] * pts[3 * j + 2]
		if ny > 0.0:
			var back := PackedFloat64Array()
			for i in range(n - 1, -1, -1):
				back.append_array(PackedFloat64Array([pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]]))
			pts = back
		out.append(pts)
	return out


# ------------------------------------------------------------------------------------- flat geometry ---

## A rounded oval as a polygon, anticlockwise, with a corner at its top, bottom and both sides:
## |x / a| ** power + |y / b| ** power = 1. Power 2 is an ellipse; more is fuller toward its box's corners.
static func oval(cx: float, cy: float, a: float, b: float, sides: int, power: float = 2.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in sides:
		var c := cos(2.0 * PI * k / sides)
		var s := sin(2.0 * PI * k / sides)
		out.append(cx + a * signf(c) * pow(absf(c), 2.0 / power))
		out.append(cy + b * signf(s) * pow(absf(s), 2.0 / power))
	return out


## The part of a convex polygon on or above the line through p and q (p left of q); or on or below it.
static func _clip(poly: PackedFloat64Array, px: float, py: float, qx: float, qy: float, above: bool) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var n := poly.size() / 2
	if n < 3:
		return out
	var dx := qx - px
	var dy := qy - py
	var sign := 1.0 if above else -1.0
	for i in n:
		var j := (i + 1) % n
		var ax := poly[2 * i]
		var ay := poly[2 * i + 1]
		var bx := poly[2 * j]
		var by := poly[2 * j + 1]
		var sa := (dx * (ay - py) - dy * (ax - px)) * sign
		var sb := (dx * (by - py) - dy * (bx - px)) * sign
		if sa >= -1e-9:
			out.append(ax)
			out.append(ay)
		if (sa > 1e-9 and sb < -1e-9) or (sa < -1e-9 and sb > 1e-9):
			var t := sa / (sa - sb)
			out.append(ax + t * (bx - ax))
			out.append(ay + t * (by - ay))
	return out


static func _area(poly: PackedFloat64Array) -> float:
	var n := poly.size() / 2
	var s := 0.0
	for i in n:
		var j := (i + 1) % n
		s += poly[2 * i] * poly[2 * j + 1] - poly[2 * j] * poly[2 * i + 1]
	return 0.5 * absf(s)


## Without repeated points and points on a straight run.
static func _tidy(poly: PackedFloat64Array) -> PackedFloat64Array:
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	for i in poly.size() / 2:
		var x := poly[2 * i]
		var y := poly[2 * i + 1]
		if xs.is_empty() or sqrt((x - xs[-1]) * (x - xs[-1]) + (y - ys[-1]) * (y - ys[-1])) > 1e-7:
			xs.append(x)
			ys.append(y)
	if xs.size() > 1 and sqrt((xs[0] - xs[-1]) * (xs[0] - xs[-1]) + (ys[0] - ys[-1]) * (ys[0] - ys[-1])) <= 1e-7:
		xs.remove_at(xs.size() - 1)
		ys.remove_at(ys.size() - 1)
	var changed := true
	while changed and xs.size() > 3:
		changed = false
		var n := xs.size()
		for i in n:
			var a := (i - 1 + n) % n
			var c := (i + 1) % n
			if absf((xs[i] - xs[a]) * (ys[c] - ys[i]) - (ys[i] - ys[a]) * (xs[c] - xs[i])) < 1e-7:
				xs.remove_at(i)
				ys.remove_at(i)
				changed = true
				break
	var out := PackedFloat64Array()
	for i in xs.size():
		out.append(xs[i])
		out.append(ys[i])
	return out


static func _convex(poly: PackedFloat64Array) -> bool:
	var n := poly.size() / 2
	var sign := 0.0
	for i in n:
		var a := (i - 1 + n) % n
		var c := (i + 1) % n
		var z := (poly[2 * i] - poly[2 * a]) * (poly[2 * c + 1] - poly[2 * i + 1]) \
			- (poly[2 * i + 1] - poly[2 * a + 1]) * (poly[2 * c] - poly[2 * i])
		if absf(z) < 1e-7:
			continue
		if sign != 0.0 and (z > 0.0) != (sign > 0.0):
			return false
		sign = z
	return true


static func _key(x: float, y: float) -> Vector2i:
	return Vector2i(roundi(x * 1e6), roundi(y * 1e6))


## Join neighbouring pieces of one role into one polygon wherever the result is still convex. pieces: [[polygon,
## role]]. Fewer polygons, the same picture.
static func merge(pieces: Array) -> Array:
	var kept: Array = []
	for piece in pieces:
		var p := _tidy(piece[0])
		if p.size() >= 6 and _area(p) > 1e-6:
			kept.append([p, piece[1]])
	var joined := true
	while joined:
		joined = false
		for i in kept.size():
			for j in range(i + 1, kept.size()):
				if String(kept[i][1]) != String(kept[j][1]):
					continue
				var a: PackedFloat64Array = kept[i][0]
				var b: PackedFloat64Array = kept[j][0]
				var na := a.size() / 2
				var nb := b.size() / 2
				var fs := -1
				var ft := -1
				for s in na:
					var e0 := _key(a[2 * s], a[2 * s + 1])
					var s1 := (s + 1) % na
					var e1 := _key(a[2 * s1], a[2 * s1 + 1])
					for t in nb:
						var t1 := (t + 1) % nb
						if _key(b[2 * t], b[2 * t + 1]) == e1 and _key(b[2 * t1], b[2 * t1 + 1]) == e0:
							fs = s
							ft = t
							break
					if fs >= 0:
						break
				if fs < 0:
					continue
				var both := PackedFloat64Array()
				for k in na:
					var m := (fs + 1 + k) % na
					both.append(a[2 * m])
					both.append(a[2 * m + 1])
				for k in nb - 2:
					var m := (ft + 2 + k) % nb
					both.append(b[2 * m])
					both.append(b[2 * m + 1])
				both = _tidy(both)
				if both.size() >= 6 and _convex(both) and absf(_area(both) - _area(a) - _area(b)) < 1e-6:
					kept[i] = [both, kept[i][1]]
					kept.remove_at(j)
					joined = true
					break
			if joined:
				break
	return kept


## A convex polygon with a convex hole (anticlockwise) cut out of it: [the pieces round the hole, the part of the
## polygon inside the hole]. One piece for each side of the hole that has some of the polygon outside it.
static func _apart(poly: PackedFloat64Array, hole: PackedFloat64Array) -> Array:
	var rest := poly
	var pieces: Array = []
	var n := hole.size() / 2
	for i in n:
		if rest.size() < 6:
			break
		var j := (i + 1) % n
		var piece := _clip(rest, hole[2 * i], hole[2 * i + 1], hole[2 * j], hole[2 * j + 1], false)
		if piece.size() >= 6:
			pieces.append(piece)
		rest = _clip(rest, hole[2 * i], hole[2 * i + 1], hole[2 * j], hole[2 * j + 1], true)
	return [pieces, rest]


static func _reversed2(poly: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(poly.size() / 2 - 1, -1, -1):
		out.append(poly[2 * i])
		out.append(poly[2 * i + 1])
	return out
