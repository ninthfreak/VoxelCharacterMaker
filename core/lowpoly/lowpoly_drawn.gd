@tool
class_name LowpolyDrawn
extends RefCounted

## Shapes of their own, fixed at a place on the figure: the long beard, the ponytail, the bun, horns and pauldrons
## (the owner's choice, 2026-11: fixed types with a few settings each, in place of the voxel figure's drawn cells).
## lowpoly/drawn.py, which this follows step for step in full precision (Vec64), checked against it corner by corner.
##
## Every type is built the same way: its settings give a few cross-sections (each an oval: where it is, how wide, how
## thick), joined into one closed low-poly piece (a loft); a section with no width is a point. A section is placed in
## its anchor's own directions: a across (outward at a shoulder), b out from the anchor, c the third direction.
##
##   long_beard  under the chin, hanging down, clear of the chest: length, width, point, jut
##   ponytail    from the back of the head, clear of the back and the hair: height, length, thickness, tie
##   bun         on top, at the back or at the nape: position, size
##   horns       a pair, from the brow: length, curve, spread, thickness
##   pauldrons   a pair, one on each shoulder: size, drop. Each bends between the chest and its upper arm (an arm is
##               one rigid piece at the shoulder, so a pauldron following it alone turns under the armpit).

const SIDES := 8                     ## points round every section
const CLEAR := 0.35                  ## how far a beard or a tail stays off what it hangs over
const CX := 12.0
const CY := 12.0
const GREY := Color8(128, 128, 128)
const BEARD_ROWS: Array[float] = [0.15, 0.4, 0.65, 0.88, 1.0]

static var X := PackedFloat64Array([1.0, 0.0, 0.0])
static var Y := PackedFloat64Array([0.0, 1.0, 0.0])
static var Z := PackedFloat64Array([0.0, 0.0, 1.0])


static func _sec(a: float, b: float, c: float, w: float, t: float, role: String) -> Dictionary:
	return {"a": a, "b": b, "c": c, "w": maxf(0.0, w), "t": maxf(0.0, t), "role": role}


# ------------------------------------------------------------------------------------------------- types ---

## Sections, in the chin's directions (b down, c forward). Its jut is added once it stands clear of the chest.
static func long_beard(p: Dictionary) -> Array:
	var length := 2.0 + 2.0 * clampi(LowpolyShapes._whole(p["length"], 3), 1, 5)
	var width := 5.0 + 1.5 * clampi(LowpolyShapes._whole(p["width"], 3), 1, 4)
	var point := clampi(LowpolyShapes._whole(p["point"], 2), 0, 3)
	var end := 0.55 * (1.0 - point / 3.0)                # the bottom's width, against the top's
	var out: Array = [_sec(0.0, -0.6, -0.8, width, 5.6, "hair")]
	for f in BEARD_ROWS:
		var w := width * (1.0 - (1.0 - end) * pow(f, 1.2))
		var t := maxf(1.2, 4.4 * (1.0 - 0.55 * f))
		if f == 1.0 and point == 3:
			w = 0.0
			t = 0.0
		out.append(_sec(0.0, length * f, -0.8 + 0.8 * (1.0 - pow(1.0 - f, 2)), w, t, "hair"))
	return out


## Bring the beard forward by its jut, most at the bottom.
static func jut_beard(sections: Array, p: Dictionary) -> Array:
	var jut := clampi(LowpolyShapes._whole(p["jut"], 1), 0, 3)
	for i in BEARD_ROWS.size():
		var f := BEARD_ROWS[i]
		sections[i + 1]["c"] = float(sections[i + 1]["c"]) + 0.6 * jut * (1.0 - pow(1.0 - f, 2))
	return sections


## Sections, in the directions of the back of the head (b back, c up), from where the tail is tied.
static func ponytail(p: Dictionary) -> Array:
	var length := 4.0 + 2.5 * clampi(LowpolyShapes._whole(p["length"], 3), 1, 5)
	var W := 2.4 + 0.8 * clampi(LowpolyShapes._whole(p["thickness"], 2), 1, 3)
	var root := "tie" if LowpolyShapes._flag(p["tie"]) else "hair"
	var path := [[-0.6, 0.0, 0.6, 0.55, root], [0.5, -0.1, 0.65, 0.6, "hair"], [1.4, -0.55, 0.95, 0.75, "hair"],
		[1.9, -0.3 * length, 1.0, 0.75, "hair"], [1.5, -0.58 * length, 0.85, 0.65, "hair"],
		[0.6, -0.82 * length, 0.55, 0.45, "hair"], [0.0, -length, 0.0, 0.0, "hair"]]
	var out: Array = []
	for e in path:
		out.append(_sec(0.0, float(e[0]), float(e[1]), W * float(e[2]), W * float(e[3]), String(e[4])))
	return out


## Sections along the way out of the head (b), round.
static func bun(p: Dictionary) -> Array:
	var R := 1.6 + 0.5 * clampi(LowpolyShapes._whole(p["size"], 2), 1, 3)
	var c := 1.2 if LowpolyShapes._text(p["position"]) == "top" else 0.0      # on top, a little toward the back
	var out: Array = []
	for e in [[-0.5, 1.2], [0.2, 1.85], [0.9, 2.0], [1.55, 1.5], [1.95, 0.0]]:
		out.append(_sec(0.0, float(e[0]) * R, c, float(e[1]) * R, float(e[1]) * R, "hair"))
	return out


## Sections of the left horn, in the brow's directions (b forward, c up); the right one is its mirror.
static func horns(p: Dictionary) -> Array:
	var length := 2.0 + 1.5 * clampi(LowpolyShapes._whole(p["length"], 2), 1, 5)
	var curve := clampi(LowpolyShapes._whole(p["curve"], 1), 0, 3)
	var spread := clampi(LowpolyShapes._whole(p["spread"], 1), 0, 3)
	var D := 1.0 + 0.4 * clampi(LowpolyShapes._whole(p["thickness"], 2), 1, 3)
	var at := Vec64.v(3.0 + 0.5 * spread, -1.4, 0.4)
	var out: Array = []
	var steps := 5
	for i in steps + 1:
		var u := float(i) / steps
		out.append(_sec(at[0], at[1], at[2], D * pow(1.0 - u, 0.9), D * pow(1.0 - u, 0.9), "horn"))
		var back := deg_to_rad(30.0 * curve) * (u + 0.5 / steps)          # it turns back as it grows
		at = Vec64.add(at, Vec64.mul(Vec64.unit(Vec64.v(0.12 * spread, -sin(back), cos(back))), length / steps))
	return out


## Sections of the left pauldron, in the shoulder's directions (a outward, b up, c forward); its width runs front to
## back (c), its thickness square to that.
static func pauldrons(p: Dictionary) -> Array:
	var k := 0.8 + 0.15 * clampi(LowpolyShapes._whole(p["size"], 2), 1, 3)
	var drop := clampi(LowpolyShapes._whole(p["drop"], 1), 0, 3)
	var rows := [[-1.2, 0.6, 5.4, 1.2], [0.6, 1.5, 7.0, 2.2], [2.4, 1.1, 7.2, 2.2], [3.4, -0.3 - 0.5 * drop, 6.8, 1.8],
		[3.9, -1.4 - 0.9 * drop, 5.8, 1.4], [4.0, -2.0 - 1.1 * drop, 4.6, 1.0]]
	var out: Array = []
	for e in rows:
		out.append(_sec(float(e[0]) * k, float(e[1]), 0.0, float(e[2]) * k, float(e[3]), "plate"))
	return out


# ----------------------------------------------------------------------------------------------- anchors ---
# A frame: [origin, a, b, c] (directions as unit vectors).

static func _head_back(m: LowpolyHood.Measure, zh: float) -> Array:
	return [Vec64.v(CX, CY + m.head(PI, zh), zh + m.dz), X, Y, Z]


static func _chin(m: LowpolyHood.Measure) -> Array:
	var front: PackedFloat64Array = m.head_rings[m.head_z.find(26.0)][0]
	return [Vec64.add(front, Vec64.v(0.0, 1.2, 0.0)), X, Vec64.neg(Z), Vec64.neg(Y)]


static func _crown(m: LowpolyHood.Measure) -> Array:
	return [m.crown_top, X, Z, Y]


static func _brow(m: LowpolyHood.Measure) -> Array:
	return [(m.head_rings[m.head_z.find(37.0)][0] as PackedFloat64Array).duplicate(), X, Vec64.neg(Y), Z]


## The top of the arm on the dressed figure: its middle, at the arm's highest corner.
static func _shoulder(fit: LowpolyShapes.Fit, side: String) -> Array:
	var s := 1.0 if side == "L" else -1.0
	var pts := PackedFloat64Array()
	var top := -INF
	for poly in fit.figure.polygons:
		if String(poly["piece"]) != "arm_" + side or bool(poly["hidden"]):
			continue
		for k in poly["corners"]:
			pts.append_array(fit.figure.point64(k))
			top = maxf(top, fit.figure.points64[3 * k + 2])
	var sum := PackedFloat64Array([0.0, 0.0, 0.0])
	var n := 0
	for i in pts.size() / 3:
		if pts[3 * i + 2] > top - 0.6:
			sum = Vec64.add(sum, Vec64.at(pts, i))
			n += 1
	var o := Vec64.div(sum, float(maxi(n, 1)))
	o[2] = top
	return [o, Vec64.mul(X, s), Z, Vec64.neg(Y)]


# -------------------------------------------------------------------------------------------- the loft ---

static func _centre(frame: Array, s: Dictionary, sign: float = 1.0) -> PackedFloat64Array:
	var p := Vec64.add(frame[0], Vec64.mul(frame[1], sign * float(s["a"])))
	p = Vec64.add(p, Vec64.mul(frame[2], float(s["b"])))
	return Vec64.add(p, Vec64.mul(frame[3], float(s["c"])))


## Move each section from the first on out along one of the anchor's directions ("b" or "c") until it stands CLEAR of
## every corner P (flat) beside it: those within its width across (x) and a unit of its height.
static func stand_clear(sections: Array, frame: Array, P: PackedFloat64Array, along: String, first: int) -> Array:
	var D: PackedFloat64Array = frame[2] if along == "b" else frame[3]
	for i in range(first, sections.size()):
		var s: Dictionary = sections[i]
		if float(s["w"]) <= 0.0:
			continue
		var ctr := _centre(frame, s)
		var most := -INF
		for j in P.size() / 3:
			if absf(P[3 * j + 2] - ctr[2]) <= 1.0 and absf(P[3 * j] - ctr[0]) <= 0.5 * float(s["w"]):
				most = maxf(most, P[3 * j] * D[0] + P[3 * j + 1] * D[1] + P[3 * j + 2] * D[2])
		if most == -INF:
			continue
		var need := most + 0.5 * float(s["t"]) + CLEAR - Vec64.dot(ctr, D)
		if need > 0.0:
			s[along] = float(s[along]) + need
	return sections


## The closed piece through the sections. follows: for every section, the parts its corners follow. sign -1 mirrors it
## across (a). Returns [{pts (flat), colour, shares, part}].
static func loft(sections: Array, frame: Array, colours: Dictionary, follows: Array, width_axis: String = "a",
		sign: float = 1.0) -> Array:
	var across: PackedFloat64Array = Vec64.mul(frame[1], sign) if width_axis == "a" else frame[3]
	var cs: Array = []
	for s in sections:
		cs.append(_centre(frame, s, sign))
	var n := cs.size()
	var rings: Array = []
	for i in n:
		var T := Vec64.unit(Vec64.sub(cs[mini(i + 1, n - 1)], cs[maxi(i - 1, 0)]))
		var Xs := Vec64.unit(Vec64.sub(across, Vec64.mul(T, Vec64.dot(across, T))))
		var Ys := Vec64.cross(T, Xs)
		var w := 0.5 * float(sections[i]["w"])
		var t := 0.5 * float(sections[i]["t"])
		var ring: Array = []
		if w <= 1e-9 and t <= 1e-9:
			ring.append(cs[i])
		else:
			for k in SIDES:
				var f := 2.0 * PI * (k + 0.5) / SIDES
				ring.append(Vec64.add(Vec64.add(cs[i], Vec64.mul(Xs, w * cos(f))), Vec64.mul(Ys, t * sin(f))))
		rings.append(ring)
	var part := ""
	var best := -INF
	for key in (follows[0] as Dictionary).keys():
		if float(follows[0][key]) > best:
			best = float(follows[0][key])
			part = String(key)
	var polys: Array = []
	for i in n - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var colour: Color = colours.get(String(sections[i]["role"]), GREY)
		var mid := Vec64.mul(Vec64.add(cs[i], cs[i + 1]), 0.5)
		var fa: Dictionary = follows[i]
		var fb: Dictionary = follows[i + 1]
		if a.size() == 1 and b.size() == 1:
			continue
		if a.size() == 1 or b.size() == 1:
			var tip: PackedFloat64Array = a[0] if a.size() == 1 else b[0]
			var rim: Array = b if a.size() == 1 else a
			var ft := fa if a.size() == 1 else fb
			var fr := fb if a.size() == 1 else fa
			for k in SIDES:
				_put(polys, [tip, rim[k], rim[(k + 1) % SIDES]], [ft, fr, fr], colour, mid, part)
			continue
		for k in SIDES:
			_put(polys, [a[k], a[(k + 1) % SIDES], b[(k + 1) % SIDES], b[k]], [fa, fa, fb, fb], colour, mid, part)
	for end in [[0, 1], [n - 1, n - 2]]:                 # close the ends that are not points
		var r: Array = rings[int(end[0])]
		if r.size() > 1:
			var sh: Array = []
			for k in SIDES:
				sh.append(follows[int(end[0])])
			_put(polys, r.duplicate(), sh, colours.get(String(sections[int(end[0])]["role"]), GREY), cs[int(end[1])], part)
	return polys


static func _put(polys: Array, pts: Array, shares: Array, colour: Color, centre: PackedFloat64Array, part: String) -> void:
	var nrm := PackedFloat64Array([0.0, 0.0, 0.0])
	var mean := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in pts.size():
		nrm = Vec64.add(nrm, Vec64.cross(pts[i], pts[(i + 1) % pts.size()]))
		mean = Vec64.add(mean, pts[i])
	mean = Vec64.div(mean, float(pts.size()))
	if Vec64.dot(nrm, Vec64.sub(mean, centre)) < 0.0:
		pts.reverse()
		shares = shares.duplicate()
		shares.reverse()
	var flat := PackedFloat64Array()
	for p in pts:
		flat.append_array(p)
	polys.append({"pts": flat, "colour": colour, "shares": shares, "part": part})


# --------------------------------------------------------------------------------------------- building ---

## A shape of one of SpecialItem.OWN_SHAPES on the dressed figure: [polygons, notes].
static func build(fit: LowpolyShapes.Fit, kind: String, params: Dictionary, colours: Dictionary, name: String) -> Array:
	var p := LowpolyShapes.settings(kind, params)
	if kind != "pauldrons" and fit.head == null:
		return [[], ["%s: no head to put it on" % name]]
	var sections: Array = []
	match kind:
		"long_beard": sections = long_beard(p)
		"ponytail": sections = ponytail(p)
		"bun": sections = bun(p)
		"horns": sections = horns(p)
		"pauldrons": sections = pauldrons(p)
		_: return [[], ["%s: no such shape as '%s'" % [name, kind]]]
	if kind == "pauldrons":
		var polys: Array = []
		for side in ["L", "R"]:
			var follows: Array = []
			for s in sections:                   # inner end mostly with the chest, outer with the arm
				var f := clampf(0.35 + 0.12 * float(s["a"]), 0.2, 0.85)
				follows.append({"upper_arm_" + side: f, "chest": 1.0 - f})
			polys.append_array(loft(sections, _shoulder(fit, String(side)), colours, follows, "c"))
		return [polys, []]
	var m := LowpolyHood.Measure.of(fit)
	var head: Array = []
	for s in sections:
		head.append({"head": 1.0})
	match kind:
		"long_beard":
			var frame := _chin(m)
			stand_clear(sections, frame, m.corners(-INF, false), "c", 1)      # in front of the chest: the jaw is its own
			return [loft(jut_beard(sections, p), frame, colours, head), []]
		"ponytail":
			var frame := _head_back(m, 29.0 + 2.5 * clampi(LowpolyShapes._whole(p["height"], 1), 0, 3))
			stand_clear(sections, frame, m.corners(-INF, true), "b", 3)       # behind the back and the hair
			return [loft(sections, frame, colours, head), []]
		"bun":
			var where := LowpolyShapes._text(p["position"])
			var frame := _crown(m) if where == "top" else _head_back(m, 35.0 if where == "back" else 29.5)
			return [loft(sections, frame, colours, head), []]
	var brow := _brow(m)                                 # horns: the left one and its mirror
	var both := loft(sections, brow, colours, head)
	both.append_array(loft(sections, brow, colours, head, "a", -1.0))
	return [both, []]
