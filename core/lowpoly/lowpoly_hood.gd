@tool
class_name LowpolyHood
extends RefCounted

## The hood, raised or lowered: lowpoly/hood.py, which this follows step for step in full precision (Vec64), checked
## against it corner by corner (tests/test_lowpoly.gd, from lowpoly/expected.py).
##
## Raised: a loose shell over the head, measured from the dressed head (its hair too): rows round the head, each point
## as far out as the head reaches that way plus a gap (most at the back and over the crown, with a brim over the
## brows); the face opening cut from its front (an arch over the brows, sides beside the eyes, closing under the
## chin); below the head's widest row it falls to a cowl lying on the shoulders. Every corner of the dressed figure
## under it is then checked against its faces and the hood pushed out where one comes through. An inside shell, in the
## lining colour when lined, and a strip round the opening and along the hem.
##
## Lowered: a cowl closed round the neck, and the empty hood lying as a pouch on the upper back over it, its opening
## turned up.
##
## Settings (SpecialItem): raised, depth (how loose: 1.3, 1.9 or 2.5 units off the head), opening (how far past the eye
## box the opening reaches), lined.

const SEGMENTS := 14                 ## quads in each row of the shell, round from one edge of the opening to the other
const THICK := 0.35                  ## how far the inside is from the outside
const LOOSE := {1: 1.3, 2: 1.9, 3: 2.5}
const CLEAR := 0.25                  ## how far the hood stays off anything under it
const FACE_EDGE := 6.0               ## the eye boxes reach this far either side of the centre line
const BROW_TOP := 36.0               ## the top of the brow row
const WIDE := 31.0                   ## the head's widest row: below it the hood falls loose to the shoulders
const JAW := 28.6                    ## where the opening's sides turn in under the chin
const HEAD_BOTTOM := 26.0            ## the bottom of every head (the head library's heights)
const SHOULDER := 0.95               ## where the cowl lies on the shoulder, against the shoulder's width
const POUCH_ROWS := 5
const POUCH_COLUMNS := 6
const CX := 12.0
const CY := 12.0
const GREY := Color8(128, 128, 128)
const CELL := 3.0                    ## the grid the push-out pass sorts the figure's corners into


## Level, theta from straight ahead round by the figure's left.
static func direction(theta: float) -> PackedFloat64Array:
	return Vec64.v(sin(theta), -cos(theta), 0.0)


## How far a closed ring of points reaches from the middle line the way theta points (the farthest crossing).
static func ray_ring(ring: Array, theta: float) -> float:
	var d := direction(theta)
	var best := 0.0
	var n := ring.size()
	for i in n:
		var p: PackedFloat64Array = ring[i]
		var q: PackedFloat64Array = ring[(i + 1) % n]
		var ax := p[0] - CX
		var ay := p[1] - CY
		var ex := (q[0] - CX) - ax
		var ey := (q[1] - CY) - ay
		var den := d[0] * (-ey) - d[1] * (-ex)
		if absf(den) < 1e-12:
			continue
		var t := (ax * (-ey) - ay * (-ex)) / den          # solve t d = a + s e
		var s := (d[0] * ay - d[1] * ax) / den
		if s >= -1e-9 and s <= 1.0 + 1e-9 and t > best:
			best = t
	return best


static func _clip(x: float, lo: float, hi: float) -> float:
	return minf(maxf(x, lo), hi)


static func _loose(p: Dictionary) -> float:
	return float(LOOSE[clampi(LowpolyShapes._whole(p["depth"], 1), 1, 3)])


static func _colours(p: Dictionary, colours: Dictionary) -> Array:
	var cloth: Color = colours.get("cloth", GREY)
	return [cloth, colours.get("lining", cloth) if LowpolyShapes._flag(p["lined"]) else cloth]


## The face opening: [its half-width beside the eyes, the top of its arch, the arch's height] (head heights).
static func opening(p: Dictionary) -> PackedFloat64Array:
	var slack := float(clampi(LowpolyShapes._whole(p["opening"], 1), 0, 3))
	var half := FACE_EDGE + 0.4 + 0.75 * slack
	return PackedFloat64Array([half, BROW_TOP + 0.6 + 0.6 * slack, minf(half, 3.0 + 0.3 * slack)])


## The opening's half-width at height z (head heights): 0 above it and below it.
static func edge_half(z: float, half: float, top: float, arch: float, bottom: float) -> float:
	if z >= top - 1e-9 or z <= bottom + 1e-9:
		return 0.0
	var c := top - arch
	if z > c:
		return half * sqrt(maxf(0.0, 1.0 - pow((z - c) / arch, 2)))
	if z >= JAW:
		return half
	return half * sqrt(maxf(0.0, 1.0 - pow((JAW - z) / (JAW - bottom), 2)))


## Whether x, seen along n, falls inside the polygon (flat points).
static func _inside(x: PackedFloat64Array, pts: PackedFloat64Array, n: PackedFloat64Array) -> bool:
	var count := pts.size() / 3
	for i in count:
		var a := Vec64.at(pts, i)
		var b := Vec64.at(pts, (i + 1) % count)
		if Vec64.dot(Vec64.cross(Vec64.sub(b, a), Vec64.sub(x, a)), n) < -1e-9:
			return false
	return true


# ------------------------------------------------------------------------------------------- measuring ---

## The dressed figure round the head and shoulders, measured for a hood.
class Measure extends RefCounted:
	var fit: LowpolyShapes.Fit
	var dz := 0.0
	var head_z := PackedFloat64Array()
	var head_rings: Array = []           ## per ring of the head, top to bottom: its dressed points
	var crown_top := PackedFloat64Array()
	var neck := 0.0
	var shoulder := 0.0
	var hem := 0.0
	var body_z := PackedFloat64Array()
	var body_rings: Array = []           ## per ring of the torso, bottom to top: its dressed points
	var shoulder_w := 6.0

	static func of(p_fit: LowpolyShapes.Fit) -> Measure:
		var m := Measure.new()
		m.fit = p_fit
		m.dz = p_fit.raise
		var head := p_fit.head
		for i in head.ring_z.size():
			var flat: PackedFloat64Array = head.ring_points[i]
			var ring: Array = []
			for k in flat.size() / 3:
				ring.append(p_fit.head_at(Vec64.v(flat[3 * k], flat[3 * k + 1], flat[3 * k + 2] + m.dz)))
			m.head_z.append(head.ring_z[i])
			m.head_rings.append(ring)
		m.crown_top = p_fit.head_at(p_fit.crown())
		var neck_band := p_fit.band("neck")
		m.neck = 0.5 * (neck_band[0] + neck_band[1])
		m.shoulder = p_fit.band("collar")[0]
		m.hem = m.shoulder - 1.6
		for z in p_fit.heights(["neck", "collar", "upper_chest", "lower_chest"]):
			var ring: Array = []
			for k in p_fit.ring(z):
				ring.append(p_fit.at(k))
			m.body_z.append(z)
			m.body_rings.append(ring)
		var top := -INF
		var arm := PackedFloat64Array()
		for poly in p_fit.figure.polygons:
			if String(poly["piece"]) != "arm_L" or bool(poly["hidden"]):
				continue
			for k in poly["corners"]:
				arm.append_array(p_fit.figure.point64(k))
				top = maxf(top, p_fit.figure.points64[3 * k + 2])
		if not arm.is_empty():
			var widest := -INF
			for i in arm.size() / 3:
				if arm[3 * i + 2] > top - 1.5:
					widest = maxf(widest, arm[3 * i])
			m.shoulder_w = widest - CX
		return m

	## How far the dressed head reaches from the middle line at a head height.
	func head(theta: float, zh: float) -> float:
		var n := head_z.size()
		if zh >= head_z[0]:
			return LowpolyHood.ray_ring(head_rings[0], theta)
		if zh <= head_z[n - 1]:
			return LowpolyHood.ray_ring(head_rings[n - 1], theta)
		var i := 0
		while not (head_z[i + 1] <= zh and zh <= head_z[i]):
			i += 1
		var f := (head_z[i] - zh) / (head_z[i] - head_z[i + 1])
		var ring: Array = []
		for k in (head_rings[i] as Array).size():
			var a: PackedFloat64Array = head_rings[i][k]
			var b: PackedFloat64Array = head_rings[i + 1][k]
			ring.append(Vec64.add(Vec64.mul(a, 1.0 - f), Vec64.mul(b, f)))
		return LowpolyHood.ray_ring(ring, theta)

	## How far the dressed torso reaches from the middle line at a height of the figure.
	func body(theta: float, zw: float) -> float:
		var a := 0
		var b := body_z.size() - 1
		var below := -1
		var above := -1
		for i in body_z.size():
			if body_z[i] <= zw + 1e-6:
				below = i
			if above < 0 and body_z[i] >= zw - 1e-6:
				above = i
		a = below if below >= 0 else 0
		b = above if above >= 0 else body_z.size() - 1
		var ra := LowpolyHood.ray_ring(body_rings[a], theta)
		var rb := LowpolyHood.ray_ring(body_rings[b], theta)
		if body_z[b] - body_z[a] < 1e-6:
			return ra
		return ra + (zw - body_z[a]) / (body_z[b] - body_z[a]) * (rb - ra)

	## A ring round the shoulders: as wide as a, as deep as the body there plus depth_at, an ellipse between.
	func lying(theta: float, zw: float, a: float, depth_at: float) -> float:
		var d := body(0.0 if cos(theta) > 0.0 else PI, zw) + depth_at
		var r := 1.0 / sqrt(pow(sin(theta) / a, 2) + pow(cos(theta) / d, 2))
		return maxf(r, body(theta, zw) + depth_at)

	## Every corner of the dressed figure above a height (the head's too, or not): what a hood stays clear of.
	func corners(low: float, with_head: bool = true) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		for poly in fit.figure.polygons:
			if bool(poly["hidden"]) or (not with_head and String(poly["piece"]) == "head"):
				continue
			for k in poly["corners"]:
				if fit.figure.points64[3 * k + 2] > low:
					out.append_array(fit.figure.point64(k))
		return out


# ---------------------------------------------------------------------------------------------- the shell ---

## Points and faces of a hood's outside, pushed clear of the figure, then given an inside.
class Shell extends RefCounted:
	var V := PackedFloat64Array()
	var follows: Array = []
	var faces: Array = []                ## PackedInt32Array each

	func add(p: PackedFloat64Array, shares: Dictionary) -> int:
		V.append_array(p)
		follows.append(shares)
		return follows.size() - 1

	func ring(points: Array, shares: Dictionary, closed: bool) -> PackedInt32Array:
		var idx := PackedInt32Array()
		for p in points:
			idx.append(add(p, shares))
		if closed:
			idx.append(idx[0])
		return idx

	func strip(a: PackedInt32Array, b: PackedInt32Array) -> void:
		for k in a.size() - 1:
			faces.append(PackedInt32Array([a[k], a[k + 1], b[k + 1], b[k]]))

	func points_of(f: PackedInt32Array) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		for i in f:
			out.append_array(Vec64.at(V, i))
		return out

	## [each corner's normal (flat, unit), each face's normal (unit)]
	func normals() -> Array:
		var n := PackedFloat64Array()
		n.resize(V.size())
		n.fill(0.0)
		var fn: Array = []
		for f in faces:
			var c := PackedFloat64Array([0.0, 0.0, 0.0])
			var count: int = (f as PackedInt32Array).size()
			for i in count:
				c = Vec64.add(c, Vec64.cross(Vec64.at(V, f[i]), Vec64.at(V, f[(i + 1) % count])))
			fn.append(Vec64.unit(c))
			for i in f:
				for j in 3:
					n[3 * i + j] += c[j]
		var vn := PackedFloat64Array()
		for i in V.size() / 3:
			vn.append_array(Vec64.unit(Vec64.at(n, i)))
		return [vn, fn]

	## Turn the faces to face away from a point inside: all or none, by most of them (built in a grid, they all face
	## the same way; face by face, one lying flat on the shoulders can look inward).
	func wind_out(middle: PackedFloat64Array) -> void:
		var fn: Array = normals()[1]
		var out := 0
		for i in faces.size():
			var pts := points_of(faces[i])
			var mean := PackedFloat64Array([0.0, 0.0, 0.0])
			for k in pts.size() / 3:
				mean = Vec64.add(mean, Vec64.at(pts, k))
			mean = Vec64.div(mean, float(pts.size() / 3))
			if Vec64.dot(fn[i], Vec64.sub(mean, middle)) > 0.0:
				out += 1
		if float(out) < faces.size() / 2.0:
			for i in faces.size():
				var f: PackedInt32Array = faces[i]
				f.reverse()
				faces[i] = f

	## Push the shell out wherever one of the corners P (flat) comes through it, or comes within CLEAR of it. Each
	## face looks only at the corners within 3 of it (lowpoly/hood.py looks at the same ones, unsorted).
	func clear(P: PackedFloat64Array) -> void:
		var cells := {}
		for i in P.size() / 3:
			var key := Vector3i(floori(P[3 * i] / CELL), floori(P[3 * i + 1] / CELL), floori(P[3 * i + 2] / CELL))
			if not cells.has(key):
				cells[key] = []                  # a plain Array: a packed one taken out of the dictionary is a copy
			(cells[key] as Array).append(i)
		for _round in 4:
			var both := normals()
			var vn: PackedFloat64Array = both[0]
			var fn: Array = both[1]
			var push := PackedFloat64Array()
			push.resize(V.size() / 3)
			push.fill(0.0)
			for fi in faces.size():
				var f: PackedInt32Array = faces[fi]
				var n: PackedFloat64Array = fn[fi]
				var pts := points_of(f)
				var count := f.size()
				var m := PackedFloat64Array([0.0, 0.0, 0.0])
				var lo := Vec64.v(INF, INF, INF)
				var hi := Vec64.v(-INF, -INF, -INF)
				for k in count:
					var p := Vec64.at(pts, k)
					m = Vec64.add(m, p)
					for j in 3:
						lo[j] = minf(lo[j], p[j])
						hi[j] = maxf(hi[j], p[j])
				m = Vec64.div(m, float(count))
				for j in 3:
					lo[j] -= 3.0
					hi[j] += 3.0
				var need := 0.0
				for cx in range(floori(lo[0] / CELL), floori(hi[0] / CELL) + 1):
					for cy in range(floori(lo[1] / CELL), floori(hi[1] / CELL) + 1):
						for cz in range(floori(lo[2] / CELL), floori(hi[2] / CELL) + 1):
							var key := Vector3i(cx, cy, cz)
							if not cells.has(key):
								continue
							for i in cells[key]:
								var x := Vec64.at(P, i)
								if x[0] < lo[0] or x[1] < lo[1] or x[2] < lo[2] or x[0] > hi[0] or x[1] > hi[1] or x[2] > hi[2]:
									continue
								var d := Vec64.dot(Vec64.sub(x, m), n)
								if d > -CLEAR and d < 3.0 and LowpolyHood._inside(x, pts, n):
									need = maxf(need, d + CLEAR)
				for i in f:
					push[i] = maxf(push[i], need)
			var most := 0.0
			for v in push:
				most = maxf(most, v)
			if most < 1e-3:
				break
			var spread := push.duplicate()       # a gentle bump, not a ledge: two rings of neighbours go out part way
			for _ring in 2:
				var step := spread.duplicate()
				for f in faces:
					var top := 0.0
					for i in f:
						top = maxf(top, spread[i])
					for i in f:
						step[i] = maxf(step[i], 0.65 * top)
				spread = step
			for i in V.size() / 3:
				for j in 3:
					V[3 * i + j] += vn[3 * i + j] * spread[i]

	## The outside in the cloth colour, the inside THICK within it (none if inside is null), and a strip between the
	## two along each edge. edges: runs of [corner, its neighbour away from the edge].
	func polygons(cloth: Color, inside: Variant, edges: Array) -> Array:
		var vn: PackedFloat64Array = normals()[0]
		var V_in := PackedFloat64Array()
		for i in V.size():
			V_in.append(V[i] - THICK * vn[i])
		var polys: Array = []
		for f in faces:
			var sh: Array = []
			for i in f:
				sh.append(follows[i])
			_put(polys, points_of(f), cloth, sh)
			if inside != null:
				var inner := PackedFloat64Array()
				var back: Array = []
				for k in range(f.size() - 1, -1, -1):
					inner.append_array(Vec64.at(V_in, f[k]))
					back.append(follows[f[k]])
				_put(polys, inner, inside, back)
		for run in edges:
			for e in (run as Array).size() - 1:
				var a := int(run[e][0])
				var na := int(run[e][1])
				var b := int(run[e + 1][0])
				var nb := int(run[e + 1][1])
				if a == b:
					continue
				var pa := Vec64.at(V, a)
				var pb := Vec64.at(V, b)
				var qa := Vec64.at(V_in, a)
				var qb := Vec64.at(V_in, b)
				var q: Array = [pa, pb, qb, qa]
				var sh: Array = [follows[a], follows[b], follows[b], follows[a]]
				var n := Vec64.cross(Vec64.sub(pb, pa), Vec64.sub(qa, pa))
				var away := Vec64.sub(Vec64.add(pa, pb), Vec64.add(Vec64.at(V, na), Vec64.at(V, nb)))
				if Vec64.dot(n, away) < 0.0:          # facing away from the shell
					q.reverse()
					sh.reverse()
				var flat := PackedFloat64Array()
				for p in q:
					flat.append_array(p)
				_put(polys, flat, inside, sh)
		return polys

	static func _put(polys: Array, pts: PackedFloat64Array, colour: Color, shares: Array) -> void:
		var count := pts.size() / 3
		var keep := PackedFloat64Array()
		var kept: Array = []
		for i in count:
			if Vec64.norm(Vec64.sub(Vec64.at(pts, i), Vec64.at(pts, (i - 1 + count) % count))) > 1e-6:
				keep.append_array(Vec64.at(pts, i))
				kept.append(shares[i])
		if kept.size() < 3:
			return
		var on_head := true
		for s in shares:
			on_head = on_head and float((s as Dictionary).get("head", 0.0)) > 0.99
		polys.append({"pts": keep, "colour": colour, "shares": kept, "part": "head" if on_head else "chest"})


# ---------------------------------------------------------------------------------------------- the hood ---

## [polygons ({pts, colour, shares, part}), notes]
static func hood(fit: LowpolyShapes.Fit, params: Dictionary, colours: Dictionary, name: String) -> Array:
	if fit.head == null:
		return [[], ["%s: no head to put it on" % name]]
	var p := LowpolyShapes.settings("hood", params)
	return raised(fit, p, colours) if LowpolyShapes._flag(p["raised"]) else lowered(fit, p, colours)


static func raised(fit: LowpolyShapes.Fit, p: Dictionary, colours: Dictionary) -> Array:
	var m := Measure.of(fit)
	var dz := m.dz
	var loose := _loose(p)
	var pair := _colours(p, colours)
	var cut := opening(p)
	var half := cut[0]
	var top := cut[1]
	var arch := cut[2]

	var gap := func(theta: float, zh: float) -> float:
		var back := 0.5 * (1.0 - cos(theta))
		var front := 1.0 - back
		var crown := _clip((zh - 34.0) / 5.0, 0.0, 1.0)
		var bag := _clip(1.0 - absf(zh - 35.0) / 7.0, 0.3, 1.0)
		var brim := (0.5 + 0.4 * loose) * front * front * (0.4 + 0.6 * _clip((zh - 32.0) / 4.0, 0.0, 1.0))
		return loose * (0.45 + 0.75 * pow(back, 1.5) * bag + 0.45 * crown) + brim
	var on_shoulder := func(theta: float) -> float:
		return m.lying(theta, m.shoulder, SHOULDER * m.shoulder_w + 0.2, 0.5 * loose)
	var on_head := func(theta: float, zh: float) -> float:
		return m.head(theta, zh) + float(gap.call(theta, zh))
	var radius := func(theta: float, zh: float, zw: float) -> float:
		if zh >= WIDE:
			return float(on_head.call(theta, zh))
		var hung := float(on_head.call(theta, WIDE))        # falling from the head's widest row ...
		var s := _clip((WIDE + dz - zw) / (WIDE + dz - m.shoulder), 0.0, 1.0)
		var r := (1.0 - s) * hung + s * float(on_shoulder.call(theta))     # ... to where it lies on the shoulders
		var under := m.head(theta, zh) if zh >= HEAD_BOTTOM else m.body(theta, zw)
		return maxf(r, under + 0.35 * loose)

	# rows, top to bottom, at the head's heights (the opening is cut by these), then the neck and the cowl
	var rows: Array = [41.0, 39.3, top, top - 0.4 * arch, top - arch]
	for z in [33.0, 31.0, 29.0, 27.6, 26.4]:
		var apart := true
		for h in rows:
			apart = apart and absf(float(z) - float(h)) > 0.6
		if apart:
			rows.append(z)
	var head_rows: Array = []
	for z in rows:
		if not head_rows.has(z):
			head_rows.append(z)
	head_rows.sort()
	head_rows.reverse()
	var bottom := m.neck - dz
	var sh := Shell.new()
	var grid: Array = []
	var opened: Array = []
	var crown := sh.add(Vec64.add(m.crown_top, Vec64.v(0.0, 1.0 * loose, 0.8 * loose)), {"head": 1.0})
	for z in head_rows + [bottom]:
		var zh := float(z)
		var zw := zh + dz
		var w := edge_half(zh, half, top, arch, bottom)
		var t0 := 0.0
		if w > 0.0:                                      # the edge of the opening: where the shell is w from the middle
			var lo := 0.0
			var hi := deg_to_rad(100.0)
			for _i in 40:
				var mid := 0.5 * (lo + hi)
				if float(radius.call(mid, zh, zw)) * sin(mid) < w:
					lo = mid
				else:
					hi = mid
			t0 = hi
		var pts: Array = []
		for k in SEGMENTS + (1 if w > 0.0 else 0):
			var t := t0 + k * (2.0 * PI - 2.0 * t0) / SEGMENTS
			pts.append(Vec64.add(Vec64.v(CX, CY, zw), Vec64.mul(direction(t), float(radius.call(t, zh, zw)))))
		grid.append(sh.ring(pts, {"head": 1.0} if zh > bottom else {"head": 0.5, "chest": 0.5}, w == 0.0))
		opened.append(w > 0.0)
	for row in [[m.shoulder, SHOULDER * m.shoulder_w + 0.2, 0.5 * loose], [m.hem, m.shoulder_w + 0.9, 0.5 * loose + 0.4]]:
		var pts: Array = []
		for k in SEGMENTS:
			var t := k * 2.0 * PI / SEGMENTS
			pts.append(Vec64.add(Vec64.v(CX, CY, float(row[0])), Vec64.mul(direction(t), m.lying(t, float(row[0]), float(row[1]), float(row[2])))))
		grid.append(sh.ring(pts, {"chest": 1.0}, true))
		opened.append(false)
	for k in SEGMENTS:
		sh.faces.append(PackedInt32Array([crown, grid[0][k + 1], grid[0][k]]))
	for i in grid.size() - 1:
		sh.strip(grid[i], grid[i + 1])
	sh.wind_out(Vec64.v(CX, CY, 30.0 + dz))
	sh.clear(m.corners(m.hem - 1.0))
	# the edges: round the opening, and along the hem
	var first := opened.find(true) - 1
	var last := opened.rfind(true) + 1
	var loop: Array = []
	for i in range(first, last + 1):
		loop.append([grid[i][0], grid[i][1]])
	for i in range(last, first - 1, -1):
		loop.append([grid[i][SEGMENTS], grid[i][SEGMENTS - 1]])
	var hem_run: Array = []
	for k in SEGMENTS + 1:
		hem_run.append([grid[grid.size() - 1][k], grid[grid.size() - 2][k]])
	return [sh.polygons(pair[0], pair[1], [loop, hem_run]), []]


## A hood that is down: a cowl closed round the neck, and the empty hood lying on the upper back over it, its opening
## turned up.
static func lowered(fit: LowpolyShapes.Fit, p: Dictionary, colours: Dictionary) -> Array:
	var m := Measure.of(fit)
	var loose := _loose(p)
	var pair := _colours(p, colours)
	var cowl := Shell.new()
	var rows: Array = []
	for r in 3:
		var pts: Array = []
		for k in SEGMENTS:
			var t := k * 2.0 * PI / SEGMENTS
			var at := 0.0
			var zw := 0.0
			match r:
				0:
					zw = m.neck
					at = m.body(t, m.neck) + 0.45 * loose
				1:
					zw = m.shoulder
					at = m.lying(t, m.shoulder, SHOULDER * m.shoulder_w + 0.2, 0.5 * loose)
				2:
					zw = m.hem
					at = m.lying(t, m.hem, m.shoulder_w + 0.9, 0.5 * loose + 0.4)
			pts.append(Vec64.add(Vec64.v(CX, CY, zw), Vec64.mul(direction(t), at)))
		rows.append(cowl.ring(pts, {"head": 0.3, "chest": 0.7} if r == 0 else {"chest": 1.0}, true))
	cowl.strip(rows[0], rows[1])
	cowl.strip(rows[1], rows[2])
	cowl.wind_out(Vec64.v(CX, CY, m.shoulder - 3.0))
	var body := m.corners(m.hem - 8.0, false)            # the chin hangs over the collar: not the head
	cowl.clear(body)
	# the empty hood: a pouch from the back of the neck down the back, fullest at the top, to a soft point; one layer
	var depth := 5.4 + 0.8 * loose
	var spread := deg_to_rad(64.0)
	var pouch := Shell.new()
	var grid: Array = []
	for i in POUCH_ROWS + 1:
		var v := float(i) / POUCH_ROWS
		var zw := m.neck + 0.3 - v * depth
		var w := spread * sqrt(maxf(0.0, 1.0 - pow(v, 1.7))) if i < POUCH_ROWS else 0.0
		var pts: Array = []
		for k in POUCH_COLUMNS + 1:
			var u := -1.0 + 2.0 * k / POUCH_COLUMNS
			var t := PI + u * w
			var full_at := 1.0 - u * u
			var r := m.body(t, zw) + 0.3 + (0.5 + 0.7 * loose) * full_at * (1.0 - 0.6 * v) + (0.6 * loose if i == 0 else 0.0) * full_at
			pts.append(Vec64.add(Vec64.v(CX, CY, zw), Vec64.mul(direction(t), r)))
		grid.append(pouch.ring(pts, {"chest": 1.0}, false))
	for i in grid.size() - 1:
		pouch.strip(grid[i], grid[i + 1])
	pouch.wind_out(Vec64.v(CX, CY, m.shoulder - 3.0))
	var under := body.duplicate()
	under.append_array(cowl.V)                           # lying over the collar, not under it
	pouch.clear(under)
	var neck_run: Array = []
	var hem_run: Array = []
	for k in SEGMENTS + 1:
		neck_run.append([rows[0][k], rows[1][k]])
		hem_run.append([rows[2][k], rows[1][k]])
	var polys: Array = cowl.polygons(pair[0], pair[1], [neck_run, hem_run])
	polys.append_array(pouch.polygons(pair[0], null, []))
	# the pouch's mouth: across its top, from the outside down to the back it lies on, in the lining colour
	var zw := m.neck + 0.3
	for k in POUCH_COLUMNS:
		var rim: Array = []
		for j in [k, k + 1]:
			var t := PI + (-1.0 + 2.0 * int(j) / float(POUCH_COLUMNS)) * spread
			rim.append(Vec64.add(Vec64.v(CX, CY, zw - 0.2), Vec64.mul(direction(t), m.body(t, zw) + 0.25)))
		var q: Array = [Vec64.at(pouch.V, grid[0][k]), Vec64.at(pouch.V, grid[0][k + 1]), rim[1], rim[0]]
		var n := PackedFloat64Array([0.0, 0.0, 0.0])
		for i in 4:
			n = Vec64.add(n, Vec64.cross(q[i], q[(i + 1) % 4]))
		if n[2] < 0.0:
			q.reverse()
		var flat := PackedFloat64Array()
		for pt in q:
			flat.append_array(pt)
		polys.append({"pts": flat, "colour": pair[1], "shares": [{"chest": 1.0}, {"chest": 1.0}, {"chest": 1.0}, {"chest": 1.0}],
			"part": "chest"})
	return [polys, []]
