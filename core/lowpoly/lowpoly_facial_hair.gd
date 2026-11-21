@tool
class_name LowpolyFacialHair
extends RefCounted

## Facial hair on the low-poly head (owner, 2026-11): four parts, each on or off, and one length for all of them
## (FacialHairSettings.param_spec). The same as lowpoly/facial_hair.py, which this is checked against corner by
## corner (tests/test_lowpoly.gd); read that file for where each part's edge runs and why.
##
##   moustache  above the mouth
##   sideburns  in front of each ear, from about the bottom of the ear up to the hair (on a bald head, to the top of
##              the ear)
##   goatee     the chin: from under the mouth, down the front of the jaw and under it
##   cheeks     the rest of a beard, between the sideburns and the goatee
##
##   stubble    a tint flush with the face, in the game's stubble colour (from the skin and the hair)
##   short      the hair's colour, opaque, still flush with the face
##   medium     grown out from the face by half a step of bulk
##   long       grown out by a whole step
##
## Every part is made of the head's own polygons. The polygons a part covers are cut along its edge and given a
## claim (bulk, draw order, colour, the item); the ordinary garment rules (LowpolyAssembler) then recolour them, or
## lift them and give them their edges, as they do a sleeve. So facial hair follows every head's own shape.
##
## A head polygon here is a record: {pts: PackedFloat64Array (x, y, z of each corner in turn, full precision),
## region, at_key, claims: [[bulk, draw order, colour, item], ...]}. Full precision because Godot's vectors are single
## precision and the cuts must land where the Python's do.

## how far each length stands out, in steps of bulk
const STEPS := {"stubble": 0.0, "short": 0.0, "medium": 0.5, "long": 1.0}

const EAR_TOP := 34.4               ## on a bald head a sideburn stops at the top of the ear
## the top of the cheeks: beside the mouth, then at the next two corners round the head (then the foot of the
## sideburn, the head's fourth ring)
const CHEEK_LINE := [29.95, 30.15, 30.55]
const MOUTH_ROOM := 1.2             ## beside the mouth the cheeks keep this far from the middle of the face
const MOUTH_FLOOR := 29.12          ## under the mouth the goatee comes up to here
const GOATEE_HALF := [2.0, 1.5]     ## half the goatee's width: at the top of the jaw, and under the chin
## from the middle of the face outward: [how far out, lower edge, upper edge]
const MOUSTACHE := [[0.0, 29.66, 30.42], [1.0, 29.62, 30.28], [2.1, 29.50, 29.86]]


## An item's facial hair settings: [parts (Array[String]), length, notes]. Settings it does not have are their
## defaults (SpecialItem.param_spec), as the editor shows them; one saved with the old "style" is read as parts and a
## length, and a style that is not known gives no facial hair, and a note.
static func read(params: Dictionary) -> Array:
	var p := FacialHairSettings.migrate(params)
	if p.has("style"):
		return [[] as Array[String], "stubble", ["unknown facial hair style '%s'" % String(p["style"])]]
	p = SpecialItem.with_defaults("facial_hair", p)
	var parts: Array[String] = []
	for part in FacialHairSettings.PARTS:
		if bool(p[part]):
			parts.append(part)
	var length := String(p["length"])
	if not STEPS.has(length):
		return [[] as Array[String], "stubble", ["unknown facial hair length '%s'" % length]]
	return [parts, length, []]


## The head's polygons with facial hair marked on them: a new list in which the polygons it covers carry the claim,
## cut along its edge. parts: which parts are on; hair: whether hair is worn (the sideburns then run up into it);
## dz: how far the head stands from the head library's heights (a short body's head sits lower).
static func on_head(polys: Array, head: LowpolyLibrary.Head, parts: Array[String], claim: Array, hair: bool,
		dz: float) -> Array:
	if parts.is_empty():
		return polys
	for area in areas(head, hair):
		if not parts.has(String(area[0])):
			continue
		var planes: Array = []
		for plane in area[2]:
			var point: PackedFloat64Array = (plane[0] as PackedFloat64Array).duplicate()
			if dz != 0.0:
				point[2] = point[2] + dz
			planes.append([point, plane[1]])
		polys = _carve(polys, String(area[1]), planes, claim)
	return conform(_merge(polys))


## The moustache as flat polygons on the face (x from the face's centre line, height), each on one side of the
## centre line: what it hides of the mouth, once it is more than stubble.
static func cover() -> Array:
	var out: Array = []
	for s in [1.0, -1.0]:
		for k in MOUSTACHE.size() - 1:
			var a: Array = MOUSTACHE[k]
			var b: Array = MOUSTACHE[k + 1]
			out.append(PackedFloat64Array([s * a[0], a[1], s * b[0], b[1], s * b[0], b[2], s * a[0], a[2]]))
	return out


## Where each part is on a head: [[part, the at_key of the head polygon it may cover, planes]]; each plane is
## [a point on it, its normal pointing in], and the part's edge is cut through the polygon along them.
static func areas(head: LowpolyLibrary.Head, hair: bool) -> Array:
	var rg := head.ring_points
	var n := rg[0].size() / 3
	var zs := head.ring_z
	var cx := head.mirror_x
	var cy := head.depth_centre_y
	var belt := head.face_flat
	var bottom := zs[zs.size() - 1]
	var foot := zs[3]                   # a sideburn comes down to about the bottom of the ear
	var cheek_line := PackedFloat64Array([CHEEK_LINE[0], CHEEK_LINE[1], CHEEK_LINE[2], foot])
	var tilt := tan(deg_to_rad(head.bend_degrees))
	var out: Array = []

	var corner := func(i: int, k: int) -> PackedFloat64Array:
		return PackedFloat64Array([rg[i][3 * k], rg[i][3 * k + 1], rg[i][3 * k + 2]])
	# the point at height z down the j-th corner round the head from the front, on side s (1: the figure's left)
	var column := func(j: int, s: float, z: float) -> PackedFloat64Array:
		var i := 0
		for k in zs.size() - 1:
			if zs[k] >= z - 1e-9:
				i = k
		var at := j if s > 0.0 else (n - j) % n
		var a: PackedFloat64Array = corner.call(i, at)
		var b: PackedFloat64Array = corner.call(i + 1, at)
		return _add(a, _mul(_sub(b, a), (zs[i] - z) / (zs[i] - zs[i + 1])))
	var facet_normal := func(band: int, j: int, s: float) -> PackedFloat64Array:
		var k := j if s > 0.0 else (n - j) % n
		var k1 := (j + 1) if s > 0.0 else (n - j - 1) % n
		var a: PackedFloat64Array = corner.call(band, k)
		var b: PackedFloat64Array = corner.call(band, k1)
		var c: PackedFloat64Array = corner.call(band + 1, k1)
		var d: PackedFloat64Array = corner.call(band + 1, k)
		var m := _cross(_sub(c, a), _sub(d, b))
		m = _div(m, _norm(m))
		var mid := _sub(_mul(_add(a, c), 0.5), PackedFloat64Array([cx, cy, 0.5 * (a[2] + c[2])]))
		return m if _dot(m, mid) > 0.0 else _mul(m, -1.0)
	var ring := func(band: int, j: int, s: float) -> String:
		return "ring|%d|%d" % [band, j if s > 0.0 else n - 1 - j]
	var down := func(z: float) -> Array:
		return [PackedFloat64Array([0.0, 0.0, z]), PackedFloat64Array([0.0, 0.0, -1.0])]

	var g0: float = GOATEE_HALF[0]
	var g1: float = GOATEE_HALF[1]
	var slope := (g1 - g0) / (belt[0] - bottom)
	for s in [1.0, -1.0]:
		# a point on this side's flat of the face, and its outward normal
		var flat := func(u: float, z: float) -> PackedFloat64Array:
			return PackedFloat64Array([cx + s * u, head.face_y(cx + s * u), z])
		var face := _div(PackedFloat64Array([s * tilt, -1.0, 0.0]), sqrt(tilt * tilt + 1.0))
		var goatee_in := [PackedFloat64Array([cx + s * g0, 0.0, belt[0]]), PackedFloat64Array([-s, 0.0, -slope])]
		var goatee_out := [goatee_in[0], _mul(goatee_in[1], -1.0)]
		var base_key := "base|%d" % (0 if s > 0.0 else 3)
		# the moustache: each piece a convex quad on the flat of the face, above the mouth
		for k in MOUSTACHE.size() - 1:
			var a: Array = MOUSTACHE[k]
			var b: Array = MOUSTACHE[k + 1]
			var corners := [flat.call(a[0], a[1]), flat.call(b[0], b[1]), flat.call(b[0], b[2]), flat.call(a[0], a[2])]
			var middle := _mul(_add(_add(_add(corners[0], corners[1]), corners[2]), corners[3]), 0.25)
			var planes: Array = []
			for c in 4:
				planes.append(_line(corners[c], corners[(c + 1) % 4], face, middle))
			out.append(["moustache", ring.call(3, 0, s), planes])
		# the sideburn: the column in front of the ear, from its foot up to the hair or the top of the ear
		out.append(["sideburns", ring.call(2, 3, s), [] if hair else [down.call(EAR_TOP)]])
		# the goatee: under the mouth, then a strip down the front of the jaw and under the chin
		out.append(["goatee", ring.call(3, 0, s), [goatee_in, down.call(MOUTH_FLOOR)]])
		for band in [4, 5]:
			out.append(["goatee", ring.call(band, 0, s), [goatee_in]])
		out.append(["goatee", base_key, [goatee_in]])
		# the cheeks: beside the mouth, the lower cheeks up to the cheek line, the jaw and under it, round to the
		# sideburn
		var beside := _line(flat.call(MOUTH_ROOM, belt[0]), flat.call(MOUTH_ROOM, belt[1]), face,
			flat.call(head.face_half_width, belt[0]))
		var top := _line(flat.call(MOUTH_ROOM, cheek_line[0]), flat.call(head.face_half_width, cheek_line[1]), face,
			flat.call(MOUTH_ROOM, belt[0]))
		out.append(["cheeks", ring.call(3, 0, s), [beside, top]])
		for j in [1, 2]:
			var p: PackedFloat64Array = column.call(j, s, cheek_line[j])
			var q: PackedFloat64Array = column.call(j + 1, s, cheek_line[j + 1])
			out.append(["cheeks", ring.call(3, j, s), [_line(p, q, facet_normal.call(3, j, s), column.call(j, s, belt[0]))]])
		out.append(["cheeks", ring.call(3, 3, s), []])
		for band in [4, 5]:
			out.append(["cheeks", ring.call(band, 0, s), [goatee_out]])
			for j in [1, 2, 3]:
				out.append(["cheeks", ring.call(band, j, s), []])
		out.append(["cheeks", base_key, [goatee_out]])
	return out


## The plane through the line from p to q, square to a surface of this normal, pointing toward a point.
static func _line(p: PackedFloat64Array, q: PackedFloat64Array, normal: PackedFloat64Array,
		toward: PackedFloat64Array) -> Array:
	var m := _cross(_sub(q, p), normal)
	return [p, m if _dot(m, _sub(toward, p)) > 0.0 else _mul(m, -1.0)]


# ------------------------------------------------------------------------------------------ mesh tools ---

## A polygon cut by a plane: [the part on the side the normal points to, the part on the other side]; either is
## empty where the polygon has nothing.
static func _split(p: PackedFloat64Array, point: PackedFloat64Array, normal: PackedFloat64Array) -> Array:
	var n := p.size() / 3
	var d := PackedFloat64Array()
	var lo := INF
	var hi := -INF
	for i in n:
		var v := (p[3 * i] - point[0]) * normal[0] + (p[3 * i + 1] - point[1]) * normal[1] \
			+ (p[3 * i + 2] - point[2]) * normal[2]
		d.append(v)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if lo >= -1e-9:
		return [p, PackedFloat64Array()]
	if hi <= 1e-9:
		return [PackedFloat64Array(), p]
	var halves: Array = []
	for sign in [1.0, -1.0]:
		var out := PackedFloat64Array()
		for i in n:
			var j := (i + 1) % n
			var da: float = sign * d[i]
			var db: float = sign * d[j]
			if da >= -1e-9:
				out.append_array(PackedFloat64Array([p[3 * i], p[3 * i + 1], p[3 * i + 2]]))
			if (da > 1e-9 and db < -1e-9) or (da < -1e-9 and db > 1e-9):
				var t := da / (da - db)
				out.append_array(PackedFloat64Array([p[3 * i] + t * (p[3 * j] - p[3 * i]),
					p[3 * i + 1] + t * (p[3 * j + 1] - p[3 * i + 1]), p[3 * i + 2] + t * (p[3 * j + 2] - p[3 * i + 2])]))
		halves.append(out if out.size() >= 9 else PackedFloat64Array())
	return halves


## Cut every polygon at `pick` down to the part inside all the planes, and give that part the claim. What is cut away
## stays as it was.
static func _carve(polys: Array, pick: String, planes: Array, claim: Array) -> Array:
	var out: Array = []
	for r in polys:
		var rec: Dictionary = r
		if String(rec["at_key"]) != pick:
			out.append(rec)
			continue
		var rest: PackedFloat64Array = rec["pts"]
		for plane in planes:
			var halves := _split(rest, plane[0], plane[1])
			rest = halves[0]
			var away: PackedFloat64Array = halves[1]
			if not away.is_empty():
				var q := rec.duplicate()
				q["pts"] = away
				out.append(q)
			if rest.is_empty():
				break
		if not rest.is_empty():
			var q := rec.duplicate()
			q["pts"] = rest
			var claims: Array = (rec.get("claims", []) as Array).duplicate()
			claims.append(claim)
			q["claims"] = claims
			out.append(q)
	return out


## A polygon's corners without repeats and without corners on a straight run.
static func _tidy(p: PackedFloat64Array) -> PackedFloat64Array:
	var pts := p.duplicate()
	var changed := true
	while changed and pts.size() >= 9:
		changed = false
		var n := pts.size() / 3
		for i in n:
			var a := (i - 1 + n) % n
			var c := (i + 1) % n
			var ab := PackedFloat64Array([pts[3 * i] - pts[3 * a], pts[3 * i + 1] - pts[3 * a + 1], pts[3 * i + 2] - pts[3 * a + 2]])
			var bc := PackedFloat64Array([pts[3 * c] - pts[3 * i], pts[3 * c + 1] - pts[3 * i + 1], pts[3 * c + 2] - pts[3 * i + 2]])
			var lab := _norm(ab)
			var lbc := _norm(bc)
			if lab < 1e-9 or _norm(_cross(ab, bc)) <= 1e-9 * maxf(lab * lbc, 1e-12):
				for k in 3:
					pts.remove_at(3 * i)
				changed = true
				break
	return pts


static func _newell(p: PackedFloat64Array) -> PackedFloat64Array:
	var n := p.size() / 3
	var s := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in n:
		var j := (i + 1) % n
		s[0] += p[3 * i + 1] * p[3 * j + 2] - p[3 * i + 2] * p[3 * j + 1]
		s[1] += p[3 * i + 2] * p[3 * j] - p[3 * i] * p[3 * j + 2]
		s[2] += p[3 * i] * p[3 * j + 1] - p[3 * i + 1] * p[3 * j]
	return s


static func _area(p: PackedFloat64Array) -> float:
	return 0.5 * _norm(_newell(p))


static func _convex(p: PackedFloat64Array) -> bool:
	var n := p.size() / 3
	var m := _newell(p)
	var ln := _norm(m)
	if n < 3 or ln < 1e-12:
		return false
	m = _div(m, ln)
	for i in n:
		var a := (i - 1 + n) % n
		var c := (i + 1) % n
		var e0 := PackedFloat64Array([p[3 * i] - p[3 * a], p[3 * i + 1] - p[3 * a + 1], p[3 * i + 2] - p[3 * a + 2]])
		var e1 := PackedFloat64Array([p[3 * c] - p[3 * i], p[3 * c + 1] - p[3 * i + 1], p[3 * c + 2] - p[3 * i + 2]])
		if not _dot(_cross(e0, e1), m) > 0.0:
			return false
	return true


static func _key5(p: PackedFloat64Array, i: int) -> Vector3i:
	return Vector3i(roundi(p[3 * i] * 1e5), roundi(p[3 * i + 1] * 1e5), roundi(p[3 * i + 2] * 1e5))


static func _claims_key(claims: Array) -> String:
	var words: Array[String] = []
	for c in claims:
		var w := "%s|%d|%s|%s" % [str(float(c[0])), int(c[1]), (c[2] as Color).to_html(), String(c[3])]
		if not words.has(w):
			words.append(w)
	words.sort()
	return "/".join(words)


## Join neighbouring pieces cut from the same polygon of the head that carry the same claims, wherever the two
## together are still convex: a cut only needs to stay where the claims on its two sides differ. Corners on a
## straight run are dropped; conform() puts back those that a neighbour needs.
static func _merge(polys: Array) -> Array:
	var groups := {}
	var out: Array = []
	for r in polys:
		var rec: Dictionary = r
		var at := String(rec["at_key"])
		if not (at.begins_with("ring|") or at.begins_with("base|")):
			out.append([rec])
			continue
		var k := at + "#" + _claims_key(rec.get("claims", []))
		if not groups.has(k):
			groups[k] = []
			out.append(groups[k])
		var pts := _tidy(rec["pts"])
		if pts.size() >= 9 and _area(pts) > 1e-9:
			var q := rec.duplicate()
			q["pts"] = pts
			(groups[k] as Array).append(q)
	for g in groups.values():
		var pieces: Array = g
		var joined := true
		while joined:
			joined = false
			for i in pieces.size():
				for j in range(i + 1, pieces.size()):
					var a: PackedFloat64Array = pieces[i]["pts"]
					var b: PackedFloat64Array = pieces[j]["pts"]
					var na := a.size() / 3
					var nb := b.size() / 3
					var found := 0
					var fs := -1
					var ft := -1
					for s in na:
						var ka := _key5(a, s)
						var ka1 := _key5(a, (s + 1) % na)
						for t in nb:
							if _key5(b, t) == ka1 and _key5(b, (t + 1) % nb) == ka:
								found += 1
								fs = s
								ft = t
					if found != 1:
						continue
					var both := PackedFloat64Array()
					for k in na:
						var m := (fs + 1 + k) % na
						both.append_array(PackedFloat64Array([a[3 * m], a[3 * m + 1], a[3 * m + 2]]))
					for k in nb - 2:
						var m := (ft + 2 + k) % nb
						both.append_array(PackedFloat64Array([b[3 * m], b[3 * m + 1], b[3 * m + 2]]))
					both = _tidy(both)
					if _convex(both) and absf(_area(both) - _area(a) - _area(b)) <= 1e-3 * (_area(a) + _area(b)):
						var q: Dictionary = (pieces[i] as Dictionary).duplicate()
						q["pts"] = both
						pieces[i] = q
						pieces.remove_at(j)
						joined = true
						break
				if joined:
					break
	var flat: Array = []
	for group in out:
		flat.append_array(group)
	return flat


## After cutting: give every polygon the corners that other polygons have on its edges, so that neighbours share
## whole edges again. The garment rules look across an edge to find the neighbour a hem steps down to.
static func conform(polys: Array) -> Array:
	var seen := {}
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for r in polys:
		var p: PackedFloat64Array = r["pts"]
		for i in p.size() / 3:
			var k := _key5(p, i)
			if not seen.has(k):
				seen[k] = true
				xs.append(p[3 * i])
				ys.append(p[3 * i + 1])
				zs.append(p[3 * i + 2])
	var out: Array = []
	for r in polys:
		var rec: Dictionary = r
		var p: PackedFloat64Array = rec["pts"]
		var n := p.size() / 3
		var ring := PackedFloat64Array()
		for i in n:
			var j := (i + 1) % n
			var ax := p[3 * i]
			var ay := p[3 * i + 1]
			var az := p[3 * i + 2]
			var abx := p[3 * j] - ax
			var aby := p[3 * j + 1] - ay
			var abz := p[3 * j + 2] - az
			var ll := abx * abx + aby * aby + abz * abz
			ring.append_array(PackedFloat64Array([ax, ay, az]))
			if ll < 1e-12:
				continue
			var x0 := minf(ax, p[3 * j]) - 1e-5
			var x1 := maxf(ax, p[3 * j]) + 1e-5
			var y0 := minf(ay, p[3 * j + 1]) - 1e-5
			var y1 := maxf(ay, p[3 * j + 1]) + 1e-5
			var z0 := minf(az, p[3 * j + 2]) - 1e-5
			var z1 := maxf(az, p[3 * j + 2]) + 1e-5
			var on: Array = []
			for k in xs.size():
				# a cheap test first: a point on the edge is inside its box
				if xs[k] < x0 or xs[k] > x1 or ys[k] < y0 or ys[k] > y1 or zs[k] < z0 or zs[k] > z1:
					continue
				var t := ((xs[k] - ax) * abx + (ys[k] - ay) * aby + (zs[k] - az) * abz) / ll
				if not (t > 1e-6 and t < 1.0 - 1e-6):
					continue
				var dx := (xs[k] - ax) - t * abx
				var dy := (ys[k] - ay) - t * aby
				var dz := (zs[k] - az) - t * abz
				if sqrt(dx * dx + dy * dy + dz * dz) < 1e-6:
					on.append([t, k])
			on.sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
			for e in on:
				ring.append_array(PackedFloat64Array([xs[e[1]], ys[e[1]], zs[e[1]]]))
		if ring.size() != p.size():
			rec = rec.duplicate()
			rec["pts"] = ring
		out.append(rec)
	return out


# -------------------------------------------------------------------------------------- small vectors ---

static func _add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2]])


static func _sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


static func _mul(a: PackedFloat64Array, s: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] * s, a[1] * s, a[2] * s])


static func _div(a: PackedFloat64Array, s: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] / s, a[1] / s, a[2] / s])


static func _dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func _cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]])


static func _norm(a: PackedFloat64Array) -> float:
	return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
