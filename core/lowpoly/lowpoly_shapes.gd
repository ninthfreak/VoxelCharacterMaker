@tool
class_name LowpolyShapes
extends RefCounted

## Special shapes on the low-poly figure: straps, skirt, cape (SPEC.md section 0); the hood is LowpolyHood and the
## shapes of their own LowpolyDrawn, both measured from the Fit below. The same as lowpoly/specials.py, which this is
## checked against corner by corner (tests/test_lowpoly.gd); read that file for the reasoning.
##
## Each takes the settings its item has (SpecialItem.param_spec: the same names, options and defaults) and is
## measured from the dressed figure (Fit), so it fits any body and stands clear of whatever is worn under it.
##
##   straps   two bands lying on the chest: up the front from the bottom of the belly, over the top beside the
##            neck, straight down the back. Fixed to the chest; they bend with it.
##   skirt    hanging cloth (LowpolyCloth), fixed at the waist line. Its settings choose its columns: how long each
##            is, where the cloth is cut open, how much it flares. With a waistband it also covers the waist as an
##            ordinary garment would (coverage()).
##   cape     hanging cloth, fixed along the shoulder line at the back.
##
## Full precision throughout (Vec64), as for the face and the cloth.

const BUILT: Array[String] = ["skirt", "cape", "straps", "hood", "long_beard", "ponytail", "bun", "horns", "pauldrons"]
const HANGS: Array[String] = ["skirt", "cape"]       ## placed after everything else worn, in draw order among themselves

const SKIRT_LENGTH := {"to_knee": "knee", "to_shin": "shin", "to_ankle": "ankle"}     ## the band whose floor the hem reaches
const CAPE_LENGTH := {"to_waist": "waist", "to_knee": "knee", "to_ankle": "ankle"}
const CAPE_WIDTH := {"narrow": -1.0, "shoulders": 0.0, "wide": 1.0}
const MAX_SLANT := 6.0
const MIN_ROWS := 2.0               ## however steep the slant, the high side keeps this much cloth below the hips
const OPEN_AT_HEM := 2.0            ## a front opening: how far each flap's edge stands from the middle at the hem
const WRAP_PAST_MIDDLE := 1.0       ## a wrap: how far past the middle its cut edge ends, at the hem
const STRAP_PROUD := 0.12           ## how far a strap stands off what it lies on: a flat band, no thickness
const STRAP_STRAIGHT := 0.12        ## a strap takes no extra points where it runs this straight
const STRAP_AT_WAIST := 0.6         ## where a strap meets the waist, as a share of the waist's half width


## The dressed figure, as a special shape measures it (lowpoly/dress.py Fit).
class Fit extends RefCounted:
	var body: LowpolyLibrary.Body       ## the bare body: its bands, rings and shares
	var figure: LowpolyFigure           ## dressed so far, in full precision (points64)
	var surface: Dictionary = {}        ## a bare body corner -> where it is once dressed (only those that moved)
	var laid: Array = []                ## cloth laid standing so far: [[polygon (flat points), role], ...]
	var cx := 12.0
	var head: LowpolyLibrary.Head       ## the head (its rings), for a hood and the shapes on the head; null if none
	var raise := 0.0                    ## how far the head is moved from the head library's heights onto this neck
	var head_corners := {}              ## a head corner's bare place (to a ten-thousandth) -> its number
	var crown_k := -1                   ## the head's top corner

	## The head, and its corners in the figure: numbers first to first + count - 1, before anything was dressed.
	func use_head(p_head: LowpolyLibrary.Head, p_raise: float, first: int, count: int) -> void:
		head = p_head
		raise = p_raise
		for k in range(first, first + count):
			var key := Vector3i(roundi(figure.points64[3 * k] * 1e4), roundi(figure.points64[3 * k + 1] * 1e4),
				roundi(figure.points64[3 * k + 2] * 1e4))
			if not head_corners.has(key):
				head_corners[key] = k
			if crown_k < 0 or figure.points64[3 * k + 2] > figure.points64[3 * crown_k + 2]:
				crown_k = k

	## Where a head corner (by its bare place) is once the figure is dressed; the place itself if no corner is there.
	func head_at(p: PackedFloat64Array) -> PackedFloat64Array:
		var key := Vector3i(roundi(p[0] * 1e4), roundi(p[1] * 1e4), roundi(p[2] * 1e4))
		return at(int(head_corners[key])) if head_corners.has(key) else p.duplicate()

	## The head's top corner, bare.
	func crown() -> PackedFloat64Array:
		return figure.point64(crown_k)

	## A band's bottom and top on this body.
	func band(name: String) -> PackedFloat64Array:
		return body.heights64[name]

	## The heights of the bare body's rings in those bands, bottom to top (to a ten-thousandth).
	func heights(bands: Array) -> PackedFloat64Array:
		var seen := {}
		for p in body.polygons:
			if String(p["piece"]) != "skin" or bool(p["hidden"]) or not bands.has(RegionMap.key_band(String(p["region"]))):
				continue
			for k in p["corners"]:
				seen[roundi(body.points64[3 * k + 2] * 1e4)] = true
		var keys: Array = seen.keys()
		keys.sort()
		var out := PackedFloat64Array()
		for key in keys:
			out.append(int(key) / 1e4)
		return out

	## The bare body's own corners at a ring height, in order: the front centre, then round by the figure's left.
	## Corner numbers (into the body, and the figure).
	func ring(z: float) -> PackedInt32Array:
		var seen := {}
		var order_seen: Array = []
		for p in body.polygons:
			if String(p["piece"]) != "skin" or bool(p["hidden"]):
				continue
			for k in p["corners"]:
				if absf(body.points64[3 * k + 2] - z) < 1e-6:
					var key := Vector3i(roundi(body.points64[3 * k] * 1e4), roundi(body.points64[3 * k + 1] * 1e4),
						roundi(body.points64[3 * k + 2] * 1e4))
					if not seen.has(key):
						order_seen.append(key)
					seen[key] = int(k)
		var ks := PackedInt32Array()
		for key in order_seen:
			ks.append(int(seen[key]))
		var n := ks.size()
		if n == 0:
			return ks
		var c := PackedFloat64Array([0.0, 0.0, 0.0])
		for k in ks:
			c = Vec64.add(c, Vec64.at(body.points64, k))
		c = Vec64.div(c, float(n))
		var angle: Array = []
		for i in n:
			var p := Vec64.at(body.points64, ks[i])
			angle.append([fposmod(atan2(p[0] - c[0], -(p[1] - c[1])), TAU), i])
		angle.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
		var order: Array = []
		for e in angle:
			order.append(int(e[1]))
		var front := -1
		for i in order:
			if absf(body.points64[3 * ks[i]] - cx) < 1e-6 and (front < 0 or body.points64[3 * ks[i] + 1] < body.points64[3 * ks[front] + 1]):
				front = i
		if front < 0:
			front = order[0]
		var at := order.find(front)
		var out := PackedInt32Array()
		for j in n:
			out.append(ks[order[(at + j) % n]])
		return out

	## Where one of the bare figure's corners (the body's, or the head's) is once the figure is dressed. The dressed
	## figure keeps every bare corner at its own number, so one that did not move is read from there.
	func at(k: int) -> PackedFloat64Array:
		return surface[k] if surface.has(k) else Vec64.at(figure.points64, k)

	func bare(k: int) -> PackedFloat64Array:
		return Vec64.at(body.points64, k)

	func shares(k: int) -> Dictionary:
		return figure.weights[k]

	## Every corner of the dressed figure (and of cloth laid so far) that a cloth of this kind hangs over, and its
	## height standing: [points (flat), heights].
	func points(kind: String) -> Array:
		var p := PackedFloat64Array()
		var z0 := PackedFloat64Array()
		for poly in figure.polygons:
			if not LowpolyCloth.hangs_over(kind, String(poly["piece"]), RegionMap.key_band(String(poly["region"]))):
				continue
			for k in poly["corners"]:
				p.append_array(Vec64.at(figure.points64, k))
				z0.append(figure.points64[3 * k + 2])
		if LowpolyCloth.hangs_over(kind, "cloth:", ""):
			for made in laid:
				var flat: PackedFloat64Array = made[0]
				p.append_array(flat)
				for i in flat.size() / 3:
					z0.append(flat[3 * i + 2])
		return [p, z0]

	## The dressed skin in those bands, as triangles (nine numbers each).
	func triangles(bands: Array) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		for poly in figure.polygons:
			if String(poly["piece"]) != "skin" or not bands.has(RegionMap.key_band(String(poly["region"]))):
				continue
			var c: PackedInt32Array = poly["corners"]
			for i in range(1, c.size() - 1):
				out.append_array(Vec64.at(figure.points64, c[0]))
				out.append_array(Vec64.at(figure.points64, c[i]))
				out.append_array(Vec64.at(figure.points64, c[i + 1]))
		return out


## A shape's settings: its defaults, with what the item sets.
static func settings(kind: String, params: Dictionary) -> Dictionary:
	var out := SpecialItem.default_params(kind)
	for key in params.keys():
		if out.has(key):
			out[key] = params[key]
	return out


## Settings read as lowpoly/specials.py reads them, so that a hand-edited file of the wrong type still builds: a word
## from anything (a number that is not one of the options falls back to the default), Python's truth for a flag (any
## non-empty text is on), and a whole number from a number or a numeric text (anything else: the default).
static func _text(v: Variant) -> String:
	return str(v)


static func _flag(v: Variant) -> bool:
	if v is String:
		return not (v as String).is_empty()
	if v is bool or v is int or v is float:
		return bool(v)
	return v != null


static func _whole(v: Variant, fallback: int) -> int:
	if v is int or v is float or v is bool:
		return int(v)
	if v is String and (v as String).is_valid_float():
		return int(float(v))
	return fallback


## Regions a shape covers as an ordinary garment would: {region: {role, bulk}}.
static func coverage(kind: String, params: Dictionary) -> Dictionary:
	var out := {}
	if kind == "skirt" and _flag(settings(kind, params)["waistband"]):
		for s in ["L", "R"]:
			for f in ["F", "B"]:
				out["waist.%s.%s" % [s, f]] = {"role": "cloth", "bulk": 1}     # a one-row band, in the cloth colour
	return out


## Level directions pointing out of a closed ring of points, one per point.
static func outward(ring: Array) -> Array:
	var n := ring.size()
	var c := PackedFloat64Array([0.0, 0.0, 0.0])
	for p in ring:
		c = Vec64.add(c, p)
	c = Vec64.div(c, float(n))
	var out: Array = []
	for i in n:
		var t := Vec64.sub(ring[(i + 1) % n], ring[(i - 1 + n) % n])
		var d := Vec64.v(t[1], -t[0], 0.0)
		if Vec64.dot(d, Vec64.sub(ring[i], c)) < 0.0:
			d = Vec64.neg(d)
		out.append(Vec64.unit(d))
	return out


static func _mix(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := {}
	for part in a.keys():
		out[part] = float(out.get(part, 0.0)) + (1.0 - f) * float(a[part])
	for part in b.keys():
		out[part] = float(out.get(part, 0.0)) + f * float(b[part])
	var kept := {}
	for part in out.keys():
		if float(out[part]) > 1e-9:
			kept[part] = out[part]
	return kept


static func _argmax(xs: PackedFloat64Array) -> int:
	var best := 0
	for i in xs.size():
		if xs[i] > xs[best]:
			best = i
	return best


static func _argmin(xs: PackedFloat64Array) -> int:
	var best := 0
	for i in xs.size():
		if xs[i] < xs[best]:
			best = i
	return best


# --------------------------------------------------------------------------------------------- skirt ---

## Returns [LowpolyCloth or null, notes].
static func skirt(fit: Fit, params: Dictionary, colours: Dictionary, name: String) -> Array:
	var p := settings("skirt", params)
	var notes: Array[String] = []
	var cx := fit.cx
	var z_top := fit.band("hips")[1]                       # the waist line: the cloth is fixed along it
	var z_hip := fit.band("hips")[0]                       # below here an opening is open
	var ring := fit.ring(z_top)
	var n := ring.size()
	var xs := PackedFloat64Array()
	for k in ring:
		xs.append(fit.bare(k)[0] - cx)
	if n != 8 or absf(xs[0]) > 1e-6 or absf(xs[4]) > 1e-6 or _argmax(xs) != 2 or _argmin(xs) != 6:
		return [null, ["%s: the waist is not the ring of eight points this expects" % name]]
	const F := 0
	const AL := 1
	const SL := 2
	const BL := 3
	const R := 4
	const BR := 5
	const SR := 6
	const AR := 7
	var w: Array = []
	var sh: Array = []
	for k in ring:
		w.append(fit.at(k))
		sh.append(fit.shares(k))
	var d := outward(w)
	var hem_z: float = fit.band(String(SKIRT_LENGTH.get(_text(p["length"]), "knee")))[0]
	# flare: the hem is that much wider than the hips, all round, widening evenly below them
	var flare := atan2(float(clampi(_whole(p["flare"], 1), 0, 3)), z_hip - hem_z)
	var four := _text(p["panels"]) == "four"
	var opening := _text(p["opening"])
	if not (opening in ["none", "wrap", "front"]):
		notes.append("%s: unknown opening '%s'" % [name, opening])
		opening = "none"
	var left := _text(p["side"]) != "right"               # the side the hem rises toward and a wrap opens on
	var slant := clampf(float(_whole(p["slant"], 0)), 0.0, minf(MAX_SLANT, maxf(0.0, z_hip - hem_z - MIN_ROWS)))
	var trim := _flag(p["hem_trim"])
	var got := fit.points(LowpolyCloth.OVER_SKIRT)
	var pp: PackedFloat64Array = got[0]
	var z0: PackedFloat64Array = got[1]
	var rest := LowpolyPose.rest()
	var levels := PackedFloat64Array()
	for z in fit.heights(["hips"]):
		if z_hip < z and z < z_top - 1e-6:
			levels.append(z)

	# Where each of the eight columns hangs at the hem: the width the slant runs across, and what an opening is
	# measured along.
	var base: Array = []
	for k in n:
		var dk: PackedFloat64Array = d[k]
		base.append(LowpolyCloth.Column.make(w[k], sh[k], dk, Vec64.v(dk[1], -dk[0], 0.0), hem_z, trim, flare, [], 1.0, levels))
	var all := PackedInt32Array()
	for k in n:
		all.append(k)
	var first := LowpolyCloth.make(name, base, [[all, true]], colours, "pelvis", LowpolyCloth.OVER_SKIRT)
	first.settle(rest, pp, z0)
	var at_hem := first.ends(rest, pp, z0)
	var xh := PackedFloat64Array()
	for k in n:
		xh.append(at_hem[3 * k] - cx)
	var lo: float = xh[_argmin(xh)]
	var hi: float = xh[_argmax(xh)]

	var hem_at := func(x: float) -> float:
		var t := clampf((x - lo) / maxf(hi - lo, 1e-9), 0.0, 1.0)
		return hem_z + (t if left else 1.0 - t) * slant

	var cols: Array = []
	## A column at ring point a, or part of the way from a to b. Returns its number.
	## opts: hem, trim_on, spread, side (each optional)
	var add := func(a: int, b: int = -1, f: float = 0.0, opts: Dictionary = {}) -> int:
		if b < 0:
			b = a
		var top := Vec64.lerp3(w[a], w[b], f)
		var out := Vec64.unit(Vec64.lerp3(d[a], d[b], f))
		var x := xh[a] + f * (xh[b] - xh[a])
		var side: PackedFloat64Array = opts.get("side", Vec64.v(out[1], -out[0], 0.0))
		var hem: float = opts["hem"] if opts.has("hem") else float(hem_at.call(x))
		cols.append(LowpolyCloth.Column.make(top, _mix(sh[a], sh[b], f), out, side, hem,
			bool(opts.get("trim_on", trim)), flare, opts.get("spread", []), 1.0, levels))
		return cols.size() - 1

	var near := func(k: int) -> int:                       # ring points named from the open (or high) side
		return k if left else (n - k) % n
	var sign := 1.0 if left else -1.0
	var u := func(k: int) -> float:                        # how far toward that side a column hangs
		return sign * xh[near.call(k)]

	## A wrap's front on its open side, from the middle out to its edge (ring point edge_a, or part of the way from
	## edge_a to edge_b). The cloth is cut on a line from that edge at the hips to just past the middle at the level
	## hem. Returns the columns, from the middle outward.
	var open_front := func(edge_a: int, edge_b: int, edge_f: float) -> Array:
		var u_front: float = u.call(1)
		var u_edge: float = float(u.call(edge_a)) + edge_f * (float(u.call(edge_b)) - float(u.call(edge_a)))
		var slope := (z_hip - hem_z) / maxf(u_edge - WRAP_PAST_MIDDLE, 1e-6)
		var cut := func(uu: float) -> float:
			return hem_z + (uu - WRAP_PAST_MIDDLE) * slope
		var hem_u := func(uu: float) -> float:
			return hem_at.call(sign * uu)
		var u_meet := WRAP_PAST_MIDDLE                     # where the cut meets the hem
		for _i in 60:
			u_meet = WRAP_PAST_MIDDLE + (float(hem_u.call(u_meet)) - hem_z) / slope
		var made: Array = []
		if u_meet < u_front - 0.3:                         # the cut meets the hem before the front corner
			made.append(add.call(F, near.call(1), u_meet / u_front, {"hem": hem_u.call(u_meet)}))
			made.append(add.call(near.call(1), -1, 0.0, {"hem": cut.call(u_front), "trim_on": false}))
		elif u_meet > u_front + 0.3 and u_meet < u_edge - 0.3:      # or beyond it
			made.append(add.call(near.call(1)))
			made.append(add.call(near.call(1), near.call(2), (u_meet - u_front) / (float(u.call(2)) - u_front),
				{"hem": hem_u.call(u_meet)}))
		else:
			made.append(add.call(near.call(1), -1, 0.0, {"hem": maxf(hem_u.call(u_front), cut.call(u_front))}))
		# the edge itself: cloth to the hips only
		made.append(add.call(near.call(edge_a), near.call(edge_b), edge_f, {"hem": z_hip, "trim_on": false}))
		return made

	var half := 0.5
	var back_two := func() -> Array:
		return [add.call(SL, BL, half), add.call(BL), add.call(R), add.call(BR), add.call(BR, SR, half)]
	var sheets: Array = []
	if opening == "none":
		if four:
			var ring_cols: Array = []
			for k in n:
				ring_cols.append(add.call(k))
			sheets = [[ring_cols, true]]
		else:                                              # front and back cloths, the sides open
			var front_cols: Array = [add.call(SR, AR, half), add.call(AR), add.call(F), add.call(AL), add.call(AL, SL, half)]
			sheets = [[front_cols, false], [back_two.call(), false]]
	elif opening == "wrap":
		if four:
			var run: Array = [add.call(near.call(SL)), add.call(near.call(BL)), add.call(R), add.call(near.call(BR)),
				add.call(near.call(SR)), add.call(near.call(AR)), add.call(F)]
			run.append_array(open_front.call(2, 2, 0.0))
			sheets = [[run, false]]
		else:
			var run: Array = [add.call(near.call(SR), near.call(AR), half), add.call(near.call(AR)), add.call(F)]
			run.append_array(open_front.call(1, 2, half))
			sheets = [[run, false], [back_two.call(), false]]
	else:                                                  # open down the front: two flaps
		var flap := func(s: float) -> int:
			return add.call(F, -1, 0.0, {"hem": hem_at.call(s * OPEN_AT_HEM), "spread": [z_hip, OPEN_AT_HEM],
				"side": Vec64.v(s, 0.0, 0.0)})
		if four:
			var run: Array = [flap.call(1.0), add.call(AL), add.call(SL), add.call(BL), add.call(R), add.call(BR),
				add.call(SR), add.call(AR), flap.call(-1.0)]
			sheets = [[run, false]]
		else:
			var one: Array = [flap.call(1.0), add.call(AL), add.call(AL, SL, half)]
			var two: Array = [add.call(SR, AR, half), add.call(AR), flap.call(-1.0)]
			sheets = [[one, false], [two, false], [back_two.call(), false]]
	var cloth := LowpolyCloth.make(name, cols, sheets, colours, "pelvis", LowpolyCloth.OVER_SKIRT)
	cloth.settle(rest, pp, z0)
	return [cloth, notes]


# ---------------------------------------------------------------------------------------------- cape ---

## Returns [LowpolyCloth or null, notes].
static func cape(fit: Fit, params: Dictionary, colours: Dictionary, name: String) -> Array:
	var p := settings("cape", params)
	var cx := fit.cx
	var z_top := fit.band("collar")[0]                     # the shoulder line, under the collar
	var hem_z: float = fit.band(String(CAPE_LENGTH.get(_text(p["length"]), "knee")))[0]
	if hem_z >= z_top:
		return [null, ["%s: its hem is not below its shoulders" % name]]
	var ring := fit.ring(z_top)
	var xs := PackedFloat64Array()
	for k in ring:
		xs.append(fit.bare(k)[0] - cx)
	if ring.size() != 8 or _argmax(xs) != 2 or _argmin(xs) != 6:
		return [null, ["%s: the shoulder line is not the ring of eight points this expects" % name]]
	var tops: Array = []
	var sh: Array = []
	for i in [2, 3, 4, 5, 6]:                              # shoulder, round the back, shoulder
		tops.append(fit.at(ring[i]))
		sh.append(fit.shares(ring[i]))
	var extra: float = CAPE_WIDTH.get(_text(p["width"]), 0.0)
	for pair in [[0, 1], [4, 3]]:                          # narrower or wider than the shoulders, by a unit
		var e: int = pair[0]
		var inner: int = pair[1]
		var s := signf(tops[e][0] - cx)
		if extra > 0.0:
			tops[e] = Vec64.add(tops[e], Vec64.v(s * extra, 0.0, 0.0))
		elif extra < 0.0:
			var f := minf(0.9, -extra / maxf(absf(tops[e][0] - tops[inner][0]), 1e-6))
			tops[e] = Vec64.lerp3(tops[e], tops[inner], f)
			sh[e] = _mix(sh[e], sh[inner], f)
	var flare := float(clampi(_whole(p["flare"], 1), 0, 3))
	var half := 0.0
	for t in tops:
		half = maxf(half, absf(t[0] - cx))
	var cols: Array = []
	var order := PackedInt32Array()
	for i in tops.size():
		var ux: float = (tops[i][0] - cx) / half          # the hem is wider than the shoulders by the flare
		cols.append(LowpolyCloth.Column.make(tops[i], sh[i], Vec64.v(0.0, 1.0, 0.0), Vec64.v(1.0, 0.0, 0.0), hem_z,
			_flag(p["hem_trim"]), 0.0, [z_top, flare * ux]))
		order.append(i)
	var cloth := LowpolyCloth.make(name, cols, [[order, false]], colours, "chest", LowpolyCloth.OVER_CAPE,
		Vec64.v(0.0, 1.0, 0.0))
	var got := fit.points(LowpolyCloth.OVER_CAPE)
	cloth.settle(LowpolyPose.rest(), got[0], got[1])
	return [cloth, []]


# -------------------------------------------------------------------------------------------- straps ---

## Where a closed ring of points crosses the upright plane at x: at the front, or at the back. Empty if nowhere.
static func _cross(loop: Array, x: float, back: bool) -> PackedFloat64Array:
	var best := PackedFloat64Array()
	var n := loop.size()
	for i in n:
		var a: PackedFloat64Array = loop[i]
		var b: PackedFloat64Array = loop[(i + 1) % n]
		if (a[0] - x) * (b[0] - x) > 0.0 or absf(a[0] - b[0]) < 1e-9:
			continue
		var p := Vec64.add(a, Vec64.mul(Vec64.sub(b, a), (x - a[0]) / (b[0] - a[0])))
		if best.is_empty() or (p[1] > best[1] if back else p[1] < best[1]):
			best = p
	return best


## How far along `direction` the surface (triangles) still is, at the furthest of these points; 0 where it is not in
## the way. Only triangles near the points are looked at: a hit is never further than 3 along.
static func _above(points: Array, direction: PackedFloat64Array, tris: PackedFloat64Array) -> float:
	var lo := PackedFloat64Array([INF, INF, INF])
	var hi := PackedFloat64Array([-INF, -INF, -INF])
	for p in points:
		var q: PackedFloat64Array = p
		for c in 3:
			lo[c] = minf(lo[c], minf(q[c], q[c] + 3.0 * direction[c]))
			hi[c] = maxf(hi[c], maxf(q[c], q[c] + 3.0 * direction[c]))
	var near := PackedInt32Array()
	for t in tris.size() / 9:
		var inside := true
		for c in 3:
			var a := minf(tris[9 * t + c], minf(tris[9 * t + 3 + c], tris[9 * t + 6 + c]))
			var b := maxf(tris[9 * t + c], maxf(tris[9 * t + 3 + c], tris[9 * t + 6 + c]))
			inside = inside and b >= lo[c] - 0.01 and a <= hi[c] + 0.01
		if inside:
			near.append(t)
	var best := 0.0
	for t in near:
		var a := Vec64.at(tris, 3 * t)
		var e1 := Vec64.sub(Vec64.at(tris, 3 * t + 1), a)
		var e2 := Vec64.sub(Vec64.at(tris, 3 * t + 2), a)
		var h := Vec64.cross(direction, e2)
		var det := Vec64.dot(e1, h)
		if not absf(det) > 1e-12:
			continue
		var inv := 1.0 / det
		for p in points:
			var s := Vec64.sub(p, a)
			var u := Vec64.dot(s, h) * inv
			var q := Vec64.cross(s, e1)
			var v := Vec64.dot(q, direction) * inv
			var far := Vec64.dot(e2, q) * inv
			if u >= -1e-9 and v >= -1e-9 and u + v <= 1.0 + 1e-9 and far > 1e-6 and far < 3.0:
				best = maxf(best, far)
	return best


## Returns [[{pts (flat), colour, shares (one per corner)}, ...], notes].
static func straps(fit: Fit, params: Dictionary, colours: Dictionary, name: String) -> Array:
	var p := settings("straps", params)
	var cx := fit.cx
	var cy := 12.0
	var width := float(clampi(_whole(p["width"], 1), 1, 2))
	var half := 0.5 * width
	var z0 := fit.band("belly")[0]
	var z1 := fit.band("collar")[0]
	var z2 := fit.band("collar")[1]
	var zs := PackedFloat64Array()                          # up the chest
	for z in fit.heights(["belly", "lower_chest", "upper_chest"]):
		if z0 - 1e-6 <= z and z <= z1 + 1e-6:
			zs.append(z)
	var bare := {}
	var worn := {}
	var all_z := zs.duplicate()
	all_z.append(z2)
	for z in all_z:
		var ring := fit.ring(z)
		var b: Array = []
		var wv: Array = []
		for k in ring:
			b.append(k)
			wv.append(fit.at(k))
		bare[roundi(z * 1e4)] = b                           # by height to a ten-thousandth: the rings' own heights
		worn[roundi(z * 1e4)] = wv
	var max_x := func(ks: Array) -> float:
		var m := -INF
		for k in ks:
			m = maxf(m, fit.bare(k)[0])
		return m
	var at_z := func(table: Dictionary, z: float) -> Array:
		return table.get(roundi(z * 1e4), [])
	if not bare.has(roundi(z1 * 1e4)) or not bare.has(roundi(z0 * 1e4)) or zs.is_empty():
		return [[], ["%s: the chest's rings are not where the bands say" % name]]
	var edge: float = float(max_x.call(at_z.call(bare, z1))) - cx
	var beside_neck: float = float(max_x.call(at_z.call(bare, z2))) - cx
	if edge < beside_neck + 1.0:
		return [[], ["%s: the chest has no room beside the neck for a strap" % name]]
	# Over the shoulder a strap sits halfway between the neck and the edge of the chest's top row; a second unit of
	# width goes outward if the top row reaches that far, otherwise in toward the neck. From there it runs straight
	# to the front of the waist (lowpoly/specials.py).
	var at_top := 0.5 * (beside_neck + edge)
	if width >= 2.0:
		at_top += 0.5 if at_top + 1.5 <= edge + 0.25 else -0.5
	var at_waist := minf(at_top, STRAP_AT_WAIST * (float(max_x.call(at_z.call(bare, z0))) - cx) + (0.5 if width >= 2.0 else 0.0))
	var where := func(z: float) -> float:
		return at_waist + (at_top - at_waist) * (z - z0) / (z1 - z0)
	var tris := fit.triangles(["waist", "belly", "lower_chest", "upper_chest", "collar", "neck"])
	var bottom_share := fit.shares(at_z.call(bare, zs[0])[0])         # the belly's bottom row bends a little with the waist
	var inside := Vec64.v(cx, cy + 0.2, 0.5 * (z0 + z1))
	var polys: Array = []
	for sign in [1.0, -1.0]:
		var stations: Array = []                             # [inner edge, fold, outer edge, folded]: up the front, over, down the back
		var top_at := -1
		for back in [false, true]:
			var run: Array = []
			for z in zs:
				var loop: Array = at_z.call(worn, z)
				var room := -INF
				for q in loop:
					room = maxf(room, sign * (q[0] - cx))
				var c := minf(float(where.call(z)), room - half - 0.2)        # a waist too narrow for it: move in
				var lo: float = cx + sign * (c - half)
				var hi: float = cx + sign * (c + half)
				var inner := _cross(loop, lo, back)
				var outer := _cross(loop, hi, back)
				if inner.is_empty() or outer.is_empty():
					return [[], ["%s: the chest is too narrow for them" % name]]
				# a corner of the ring under the strap: the strap folds over it
				var front_y := 0.5 * (inner[1] + outer[1])
				var fold := PackedFloat64Array()
				var fold_off := INF
				for q in loop:
					if minf(lo, hi) + 0.08 < q[0] and q[0] < maxf(lo, hi) - 0.08 and absf(q[1] - front_y) < 2.5 \
							and ((q[1] > cy + 0.3) == back):
						var off := absf(q[0] - cx - sign * c)
						if fold.is_empty() or off < fold_off:
							fold = q
							fold_off = off
				run.append([inner, fold if not fold.is_empty() else _cross(loop, cx + sign * c, back), outer, not fold.is_empty()])
			if not back:
				stations.append_array(run)
				var a: PackedFloat64Array = _furthest(at_z.call(worn, z1), sign, cx)
				var b: PackedFloat64Array = _furthest(at_z.call(worn, z2), sign, cx)
				var up := Vec64.sub(b, a)                    # the slope from the shoulder up to the neck
				if absf(up[0]) < 1e-6:
					return [[], ["%s: no shoulder slope to cross" % name]]
				var on := func(x: float) -> PackedFloat64Array:
					return Vec64.add(a, Vec64.mul(up, clampf((x - a[0]) / up[0], 0.0, 1.0)))
				stations.append([on.call(cx + sign * (at_top - half)), on.call(cx + sign * at_top),
					on.call(cx + sign * (at_top + half)), false])
				top_at = stations.size() - 1
			else:
				run.reverse()
				stations.append_array(run)
		var count := stations.size()
		var keep := PackedInt32Array([0])                    # drop the stations where the strap runs straight
		for i in range(1, count - 1):
			var bend := 0.0
			for e in 3:
				var a: PackedFloat64Array = stations[keep[-1]][e]
				var q: PackedFloat64Array = stations[i][e]
				var b: PackedFloat64Array = stations[i + 1][e]
				var ab := Vec64.sub(b, a)
				bend = maxf(bend, Vec64.norm(Vec64.cross(ab, Vec64.sub(q, a))) / maxf(Vec64.norm(ab), 1e-9))
			if bend > STRAP_STRAIGHT or i == top_at or bool(stations[i][3]) != bool(stations[keep[-1]][3]):
				keep.append(i)
		keep.append(count - 1)
		var ups: Array = []
		for j in keep.size():
			var i := keep[j]
			var along := Vec64.sub(stations[keep[mini(j + 1, keep.size() - 1)]][1], stations[keep[maxi(j - 1, 0)]][1])
			var up := Vec64.cross(along, Vec64.sub(stations[i][2], stations[i][0]))
			if Vec64.dot(up, Vec64.sub(stations[i][1], inside)) < 0.0:
				up = Vec64.neg(up)
			ups.append(Vec64.unit(up))                       # square to the strap, away from the chest
		# how far the strap must stand off so that nothing under it comes through
		var need := PackedFloat64Array()
		need.resize(keep.size())
		need.fill(0.0)
		for j in keep.size() - 1:
			var sa: Array = stations[keep[j]]
			var sb: Array = stations[keep[j + 1]]
			var grid: Array = []
			for e in [0, 1]:
				for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
					for v in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
						var ga := Vec64.add(Vec64.mul(sa[e], 1.0 - u), Vec64.mul(sa[e + 1], u))
						var gb := Vec64.add(Vec64.mul(sb[e], 1.0 - u), Vec64.mul(sb[e + 1], u))
						grid.append(Vec64.add(Vec64.mul(ga, 1.0 - v), Vec64.mul(gb, v)))
			var rise := _above(grid, Vec64.unit(Vec64.add(ups[j], ups[j + 1])), tris)
			need[j] = maxf(need[j], rise)
			need[j + 1] = maxf(need[j + 1], rise)
		var rows: Array = []
		var follow: Array = []
		for j in keep.size():
			var i := keep[j]
			var row: Array = []
			for e in 3:
				row.append(Vec64.add(stations[i][e], Vec64.mul(ups[j], STRAP_PROUD + need[j])))
			rows.append(row)
			follow.append(bottom_share if (i == 0 or i == count - 1) else {"chest": 1.0})
		for j in rows.size() - 1:
			var corner_shares: Array = [follow[j], follow[j], follow[j + 1], follow[j + 1]]
			var facing := Vec64.add(ups[j], ups[j + 1])
			if bool(stations[keep[j]][3]) or bool(stations[keep[j + 1]][3]):       # folded over a corner here: two faces
				for e in [0, 1]:
					_put(polys, [rows[j][e], rows[j][e + 1], rows[j + 1][e + 1], rows[j + 1][e]], corner_shares.duplicate(),
						facing, colours)
			else:
				_put(polys, [rows[j][0], rows[j][2], rows[j + 1][2], rows[j + 1][0]], corner_shares.duplicate(), facing, colours)
	return [polys, []]


## Of a ring's points, the one furthest out to that side (the first, of equals).
static func _furthest(loop: Array, sign: float, cx: float) -> PackedFloat64Array:
	var best: PackedFloat64Array = loop[0]
	for q in loop:
		if sign * (q[0] - cx) > sign * (best[0] - cx):
			best = q
	return best


static func _put(polys: Array, pts: Array, corner_shares: Array, facing: PackedFloat64Array, colours: Dictionary) -> void:
	var n := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in pts.size():
		n = Vec64.add(n, Vec64.cross(pts[i], pts[(i + 1) % pts.size()]))
	if Vec64.dot(n, facing) < 0.0:
		pts.reverse()
		corner_shares.reverse()
	var flat := PackedFloat64Array()
	for q in pts:
		flat.append_array(q)
	polys.append({"pts": flat, "colour": colours.get("strap", Color.MAGENTA), "shares": corner_shares})
