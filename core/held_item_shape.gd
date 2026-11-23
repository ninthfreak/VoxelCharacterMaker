@tool
class_name HeldItemShape
extends RefCounted

## Held items (weapons, shields, tools, potions) are built from PARTS, each a simple shape placed, turned and sized in
## the item's own space, and coloured by one of the item's roles:
##
##   box       a block
##   wedge     a block whose top slopes from its back edge down to its front edge
##   cylinder  a round or many-sided post (its sides: 3 for a triangle, 4 for a square, 8 for nearly round)
##   cone      a post narrowing to a point at its top
##   sphere    a ball of a few faces
##   outline   a flat shape drawn on a grid, given thickness: blades, axe heads, shields
##   spin      half a side view drawn on a grid and spun round its middle: bottles, handles, pommels, staff ends
##
## A part fills its size: width across (x), depth (y), height (z), in the figure's units (24 a metre). A drawing is
## made on a GRID x GRID grid and stretched to the part's size: an outline's points are (across, up); a spin's are
## (out from the middle, up), out 0 being the middle. A part can also be mirrored: drawn twice, the second copy across
## the item's middle (x -> -x).
##
## Every shape is a closed piece with its faces turned outward. Nothing is cut away from anything: parts overlap.
##
## Holding: the GRIP is where the hand closes, and its turn is how the item sits in that hand. Unturned, an item made
## standing up and facing the front is held as a sword is, in the right hand with the arm hanging: its top (+z) points
## ahead, out of the thumb's side of the fist; its front (-y) faces outward, away from the body; its left side (+x, on
## the viewer's right) faces down. So a sword or an axe made standing up needs no turn; a bottle, held upright, is
## turned 90 degrees sideways (its grip's rotation 0, 90, 0). The left hand holds the mirror image, as the body's left
## arm mirrors its right. In a figure, a held item is drawn at the palm (the middle of the hand) and rides the forearm
## (add_to_figure). lowpoly/held.py makes the same shapes and holds them the same way (tests/test_held_items.gd checks).

const KINDS: Array[String] = ["box", "wedge", "cylinder", "cone", "sphere", "outline", "spin"]
const ROUND: Array[String] = ["cylinder", "cone", "sphere", "spin"]
const DRAWN: Array[String] = ["outline", "spin"]
const GRID := 16
const MIN_SIZE := 0.1
const MIN_SIDES := 3
const MAX_SIDES := 24
const PIECE := "held"


static func kind_label(kind: String) -> String:
	match kind:
		"box": return "Box"
		"wedge": return "Wedge"
		"cylinder": return "Cylinder"
		"cone": return "Cone"
		"sphere": return "Sphere"
		"outline": return "Drawn outline, with thickness"
		"spin": return "Drawn side view, spun round"
	return kind


## A kind's name in a word or two, for a button or a list.
static func kind_name(kind: String) -> String:
	return kind_label(kind).get_slice(",", 0)


## A part of this kind at the item's middle, in a role.
static func new_part(kind: String, role: String) -> Dictionary:
	var part := {"kind": kind, "role": role, "position": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0],
		"size": [2.0, 2.0, 2.0], "sides": 8, "mirror": false, "points": []}
	match kind:
		"cylinder": part["size"] = [1.0, 1.0, 4.0]
		"cone": part["size"] = [2.0, 2.0, 3.0]
		"outline":
			part["size"] = [2.0, 0.5, 6.0]
			part["points"] = [[0, 0], [GRID, 0], [GRID, GRID], [0, GRID]]
		"spin":
			part["size"] = [2.0, 2.0, 4.0]
			part["points"] = [[GRID, 0], [GRID, GRID]]
	return part


static func _numbers(raw: Variant, fallback: Array) -> Array:
	var out: Array = []
	for i in fallback.size():
		var v: Variant = (raw as Array)[i] if raw is Array and i < (raw as Array).size() else fallback[i]
		out.append(float(v) if (v is float or v is int) else float(fallback[i]))
	return out


## A part as the file keeps it, whatever was read: every field there, of its type, within its limits.
static func clean_part(raw: Dictionary, fallback_role: String) -> Dictionary:
	var kind := String(raw.get("kind", "box"))
	if not (kind in KINDS):
		kind = "box"
	var base := new_part(kind, String(raw.get("role", fallback_role)))
	if String(base["role"]).is_empty():
		base["role"] = fallback_role
	base["position"] = _numbers(raw.get("position", []), base["position"])
	base["rotation"] = _numbers(raw.get("rotation", []), base["rotation"])
	var size := _numbers(raw.get("size", []), base["size"])
	for i in 3:
		size[i] = maxf(MIN_SIZE, float(size[i]))
	base["size"] = size
	var sides: Variant = raw.get("sides", base["sides"])
	base["sides"] = clampi(int(sides) if (sides is int or sides is float) else 8, MIN_SIDES, MAX_SIDES)
	base["mirror"] = bool(raw.get("mirror", false)) if raw.get("mirror", false) is bool else false
	if kind in DRAWN:
		var points: Array = []
		var raw_points: Variant = raw.get("points", base["points"])
		if raw_points is Array:
			for p in raw_points:
				if p is Array and (p as Array).size() >= 2:
					points.append([clampi(int(p[0]), 0, GRID), clampi(int(p[1]), 0, GRID)])
		base["points"] = points
	return base


## A grip as the file keeps it. `needed`: an item always has one (at the middle if none was read); a second grip is
## {} when there is none.
static func clean_grip(raw: Variant, needed: bool) -> Dictionary:
	if not (raw is Dictionary) or ((raw as Dictionary).is_empty() and not needed):
		return {"position": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0]} if needed else {}
	return {"position": _numbers(raw.get("position", []), [0.0, 0.0, 0.0]),
		"rotation": _numbers(raw.get("rotation", []), [0.0, 0.0, 0.0])}


## The turn a part (or a grip) has: tipped forward or back about the item's width (x), then sideways about its depth
## (y), then turned about its height (z).
static func turn(rotation: Array) -> PackedFloat64Array:
	return Vec64.matmul(Vec64.rz(float(rotation[2])), Vec64.matmul(Vec64.ry(float(rotation[1])), Vec64.rx(float(rotation[0]))))


# --------------------------------------------------------------------------------------------- shapes ---

## A part's polygons in the item's space (its turn and place applied; not mirrored): Array of flat point lists.
static func part_polygons(part: Dictionary) -> Array:
	var size: Array = part["size"]
	var sx := float(size[0])
	var sy := float(size[1])
	var sz := float(size[2])
	var sides := int(part.get("sides", 8))
	var local: Array = []
	match String(part["kind"]):
		"box": local = _box(sx, sy, sz)
		"wedge": local = _wedge(sx, sy, sz)
		"cylinder": local = _lathe([[1.0, 0.0], [1.0, 1.0]], sides, sx, sy, sz)
		"cone": local = _lathe([[1.0, 0.0], [0.0, 1.0]], sides, sx, sy, sz)
		"sphere":
			var rings := maxi(2, ((sides / 2 + 1) / 2) * 2)      # even, so that there is a ring round the middle
			var profile: Array = []
			for j in rings + 1:
				var a := -PI / 2.0 + PI * j / rings
				profile.append([0.0 if j == 0 or j == rings else cos(a), 0.5 + 0.5 * sin(a)])
			local = _lathe(profile, sides, sx, sy, sz)
		"outline":
			local = _extrude(_drawn(part), sx, sy, sz)
		"spin":
			local = _lathe(_drawn(part), sides, sx, sy, sz)
	_outward(local)
	var r := turn(part["rotation"])
	var at: Array = part["position"]
	var t := Vec64.v(float(at[0]), float(at[1]), float(at[2]))
	var out: Array = []
	for poly in local:
		var flat := PackedFloat64Array()
		for p in (poly as Array):
			flat.append_array(Vec64.add(Vec64.apply(r, p), t))
		out.append(flat)
	return out


## A drawing's points, each [across, up] from 0 to 1 (full precision: a Vector2 is not).
static func _drawn(part: Dictionary) -> Array:
	var out: Array = []
	for p in (part.get("points", []) as Array):
		out.append([float(p[0]) / GRID, float(p[1]) / GRID])
	return out


static func _v(x: float, y: float, z: float) -> PackedFloat64Array:
	return Vec64.v(x, y, z)


static func _box(sx: float, sy: float, sz: float) -> Array:
	var x := 0.5 * sx
	var y := 0.5 * sy
	var z := 0.5 * sz
	var c := [_v(-x, -y, -z), _v(x, -y, -z), _v(x, y, -z), _v(-x, y, -z),
		_v(-x, -y, z), _v(x, -y, z), _v(x, y, z), _v(-x, y, z)]
	return [[c[0], c[3], c[2], c[1]], [c[4], c[5], c[6], c[7]], [c[0], c[1], c[5], c[4]],
		[c[1], c[2], c[6], c[5]], [c[2], c[3], c[7], c[6]], [c[3], c[0], c[4], c[7]]]


## A block whose top slopes from the full height at its back (+y) to nothing at its front (-y).
static func _wedge(sx: float, sy: float, sz: float) -> Array:
	var x := 0.5 * sx
	var y := 0.5 * sy
	var z := 0.5 * sz
	var fl := _v(-x, -y, -z)
	var fr := _v(x, -y, -z)
	var bl := _v(-x, y, -z)
	var br := _v(x, y, -z)
	var tl := _v(-x, y, z)
	var tr := _v(x, y, z)
	return [[fl, bl, br, fr], [bl, tl, tr, br], [fl, fr, tr, tl], [fl, tl, bl], [fr, br, tr]]


## A profile (each point: out from the middle 0 to 1, up 0 to 1) spun round the middle with `sides` faces, the first
## face square to the front. An end of the profile off the middle is closed with a flat cap. The ring at 1 out fills
## the part's width and depth exactly, whatever its number of sides (a square post of width 2 is 2 wide, not 1.4),
## and the middle is the middle of that ring's box.
static func _lathe(profile: Array, sides: int, sx: float, sy: float, sz: float) -> Array:
	var pts: Array = profile.duplicate()
	if pts.size() < 2:
		return []
	if float(pts[0][0]) > 1e-9:
		pts.insert(0, [0.0, float(pts[0][1])])
	if float(pts[-1][0]) > 1e-9:
		pts.append([0.0, float(pts[-1][1])])
	var ring: Array = []
	var lo_x := INF
	var lo_y := INF
	var hi_x := -INF
	var hi_y := -INF
	for k in sides:
		var a := TAU * k / sides + PI / sides
		ring.append([sin(a), -cos(a)])
		lo_x = minf(lo_x, sin(a))
		hi_x = maxf(hi_x, sin(a))
		lo_y = minf(lo_y, -cos(a))
		hi_y = maxf(hi_y, -cos(a))
	var mid_x := 0.5 * (lo_x + hi_x)
	var mid_y := 0.5 * (lo_y + hi_y)
	var scale_x := sx / (hi_x - lo_x)
	var scale_y := sy / (hi_y - lo_y)
	var at := func(p: Array, k: int) -> PackedFloat64Array:
		var u: Array = ring[k % sides]
		var r := float(p[0])
		return _v(r * (float(u[0]) - mid_x) * scale_x, r * (float(u[1]) - mid_y) * scale_y, (float(p[1]) - 0.5) * sz)
	var out: Array = []
	for i in pts.size() - 1:
		for k in sides:
			var quad := [at.call(pts[i], k), at.call(pts[i], k + 1), at.call(pts[i + 1], k + 1), at.call(pts[i + 1], k)]
			var kept := _distinct(quad)
			if kept.size() >= 3:
				out.append(kept)
	return out


## A flat outline (each point: across 0 to 1, up 0 to 1) given thickness: a face in front, one behind, and a band
## round its edge. A drawing that crosses itself is left open where its faces cannot be found.
static func _extrude(outline: Array, sx: float, sy: float, sz: float) -> Array:
	var flat: Array = []
	var same := func(a: Array, b: Array) -> bool:
		return absf(float(a[0]) - float(b[0])) < 1e-9 and absf(float(a[1]) - float(b[1])) < 1e-9
	for p in outline:
		if flat.is_empty() or not same.call(flat[-1], p):
			flat.append(p)
	if flat.size() > 2 and same.call(flat[0], flat[-1]):
		flat.pop_back()
	if flat.size() < 3:
		return []
	if _area2(flat) < 0.0:
		flat.reverse()                              # anticlockwise, seen from the front
	var front := func(p: Array) -> PackedFloat64Array:
		return _v((float(p[0]) - 0.5) * sx, -0.5 * sy, (float(p[1]) - 0.5) * sz)
	var back := func(p: Array) -> PackedFloat64Array:
		return _v((float(p[0]) - 0.5) * sx, 0.5 * sy, (float(p[1]) - 0.5) * sz)
	var out: Array = []
	for tri in triangles(flat):
		out.append([front.call(flat[tri[0]]), front.call(flat[tri[1]]), front.call(flat[tri[2]])])
		out.append([back.call(flat[tri[2]]), back.call(flat[tri[1]]), back.call(flat[tri[0]])])
	var n := flat.size()
	for i in n:
		var a: Array = flat[i]
		var b: Array = flat[(i + 1) % n]
		out.append([front.call(a), back.call(a), back.call(b), front.call(b)])
	return out


## Twice the area of an outline ([x, y] points), positive if it runs anticlockwise.
static func _area2(pts: Array) -> float:
	var area := 0.0
	var n := pts.size()
	for i in n:
		area += float(pts[i][0]) * float(pts[(i + 1) % n][1]) - float(pts[(i + 1) % n][0]) * float(pts[i][1])
	return area


## An anticlockwise outline ([x, y] points) cut into triangles, by ear clipping: [[i, j, k], ...] by point number.
## Each time, the first corner that bulges outward with no other point in or on its triangle is cut off; if there is
## none, the first corner in a straight line with its neighbours (a triangle of no area, so the edges still meet).
## A drawing that crosses itself can have neither: what is left then is not filled. lowpoly/held.py does the same.
static func triangles(pts: Array) -> Array:
	var left: Array = range(pts.size())
	var out: Array = []
	while left.size() > 3:
		var n := left.size()
		var cut := -1
		for pass_ in 2:
			for i in n:
				var a: Array = pts[left[(i + n - 1) % n]]
				var b: Array = pts[left[i]]
				var c: Array = pts[left[(i + 1) % n]]
				var turn_ := (float(b[0]) - float(a[0])) * (float(c[1]) - float(b[1])) \
					- (float(b[1]) - float(a[1])) * (float(c[0]) - float(b[0]))
				if pass_ == 1:
					if absf(turn_) <= 1e-12:
						cut = i
						break
					continue
				if turn_ <= 1e-12:
					continue
				var clear := true
				for j in n:
					if j == i or j == (i + n - 1) % n or j == (i + 1) % n:
						continue
					var p: Array = pts[left[j]]
					if not (same_point(p, a) or same_point(p, b) or same_point(p, c)) and _in_triangle(p, a, b, c):
						clear = false
						break
				if clear:
					cut = i
					break
			if cut >= 0:
				break
		if cut < 0:
			return out
		out.append([left[(cut + n - 1) % n], left[cut], left[(cut + 1) % n]])
		left.remove_at(cut)
	out.append([left[0], left[1], left[2]])
	return out


static func same_point(a: Array, b: Array) -> bool:
	return absf(float(a[0]) - float(b[0])) < 1e-9 and absf(float(a[1]) - float(b[1])) < 1e-9


## Whether p is in the anticlockwise triangle a, b, c or on its edge.
static func _in_triangle(p: Array, a: Array, b: Array, c: Array) -> bool:
	for e in [[a, b], [b, c], [c, a]]:
		var u: Array = e[0]
		var v: Array = e[1]
		var side := (float(v[0]) - float(u[0])) * (float(p[1]) - float(u[1])) - (float(v[1]) - float(u[1])) * (float(p[0]) - float(u[0]))
		if side < -1e-12:
			return false
	return true


## The corners of a polygon without repeats (a corner on the middle of a spin is shared by its whole ring).
static func _distinct(corners: Array) -> Array:
	var out: Array = []
	for c in corners:
		var dup := false
		for d in out:
			dup = dup or Vec64.norm(Vec64.sub(c, d)) < 1e-9
		if not dup:
			out.append(c)
	return out


## Turn every face of a closed piece outward: if the piece's volume comes out negative its faces point in, and all are
## turned round.
static func _outward(polys: Array) -> void:
	var volume := 0.0
	for poly in polys:
		var p: Array = poly
		for i in range(1, p.size() - 1):
			volume += Vec64.dot(p[0], Vec64.cross(p[i], p[i + 1]))
	if volume < 0.0:
		for poly in polys:
			(poly as Array).reverse()


# --------------------------------------------------------------------------------------------- an item ---

## Every polygon of a held item, in its own space: [{pts (flat), colour, part (its number), mirrored}].
## colours: role -> Color (a role it lacks is grey).
static func polygons(item: GarmentItem, colours: Dictionary) -> Array:
	var out: Array = []
	for i in item.parts.size():
		var part: Dictionary = item.parts[i]
		var colour: Color = colours.get(String(part.get("role", "")), Color8(128, 128, 128))
		var made := part_polygons(part)
		for flat in made:
			out.append({"pts": flat, "colour": colour, "part": i, "mirrored": false})
		if bool(part.get("mirror", false)):
			for flat in made:
				var m := PackedFloat64Array()
				var f: PackedFloat64Array = flat
				for k in range(f.size() / 3 - 1, -1, -1):          # across the middle, and turned round to face out
					m.append_array(Vec64.v(-f[3 * k], f[3 * k + 1], f[3 * k + 2]))
				out.append({"pts": m, "colour": colour, "part": i, "mirrored": true})
	return out


## The middle of a figure's hand on one side ("L" or "R"), standing: the middle of the box round its hand band (so a
## glove, grown all round, does not move it).
static func palm(figure: LowpolyFigure, side: String) -> PackedFloat64Array:
	var lo := Vec64.v(INF, INF, INF)
	var hi := Vec64.v(-INF, -INF, -INF)
	for poly in figure.polygons:
		var region := String(poly["region"])
		if region.is_empty() or RegionMap.key_band(region) != "hand" or RegionMap.key_side(region) != side:
			continue
		for k in poly["corners"]:
			var p := figure.point64(k)
			for i in 3:
				lo[i] = minf(lo[i], p[i])
				hi[i] = maxf(hi[i], p[i])
	if lo[0] == INF:
		return Vec64.v(0.0, 0.0, 0.0)
	return Vec64.mul(Vec64.add(lo, hi), 0.5)


## The right hand's frame, unturned: the item's (x, y, z) to the figure's (y, -z, -x): its top ahead (-y), its front
## outward (-x, the figure's right), its left side (+x) down.
const RIGHT_HAND := [0.0, 1.0, 0.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0]


## How an item sits in a hand ("R" or "L"): [A, t] taking a point of the item to the figure, standing, with the grip at
## `at`. For the left hand A is a mirror image (it turns faces inside out: add_to_figure reverses them).
static func in_hand(item: GarmentItem, at: PackedFloat64Array, side: String) -> Array:
	var hand := PackedFloat64Array(RIGHT_HAND)
	if side == RegionMap.SIDE_LEFT:
		hand = Vec64.matmul(PackedFloat64Array([-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]), hand)
	var g: Array = item.grip["position"]
	var a := Vec64.matmul(hand, Vec64.transpose(turn(item.grip["rotation"])))
	var t := Vec64.sub(at, Vec64.apply(a, Vec64.v(float(g[0]), float(g[1]), float(g[2]))))
	return [a, t]


## Draw a held item in a figure's hand ("L" or "R"): every corner rides that forearm.
static func add_to_figure(figure: LowpolyFigure, item: GarmentItem, colours: Dictionary, side: String) -> void:
	var placed := in_hand(item, palm(figure, side), side)
	var mirrored := side == RegionMap.SIDE_LEFT
	var part := "forearm_" + side
	for q in polygons(item, colours):
		var flat: PackedFloat64Array = q["pts"]
		var corners := PackedInt32Array()
		for k in flat.size() / 3:
			var p := Vec64.add(Vec64.apply(placed[0], Vec64.at(flat, k)), placed[1])
			corners.push_back(figure.add_point(p, {part: 1.0}))
		if mirrored:
			corners.reverse()
		figure.polygons.append({"corners": corners, "colour": q["colour"], "region": "", "part": part, "piece": PIECE,
			"hidden": false, "by": item.id, "at": side})
