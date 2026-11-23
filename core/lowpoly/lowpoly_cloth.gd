@tool
class_name LowpolyCloth
extends RefCounted

## Hanging cloth: skirts and capes (SPEC.md section 0). The same as lowpoly/hang.py, which this is checked against
## corner by corner (tests/test_lowpoly.gd); read that file for the reasoning behind each number.
##
## Hanging cloth is not part of the bending skin. It is a few COLUMNS of cloth, each fixed at its top to the figure
## (a skirt to the waist line, a cape to the shoulder line) with a fixed length, laid standing by one rule: a taut line
## from its top, over whatever of the figure sticks out under it, then straight down for the rest of its length
## (leaning out by the garment's flare). The cloth between two neighbouring columns is a face of four-sided pieces.
##
## In a pose the cloth follows bones (the owner's choice, 2026-11): it is laid once, standing (bind), and every point
## then follows what its column's top follows and, further down, cloth bones turned by the legs (LowpolyPose cloth
## bones; cloth_shares). Laid afresh for every pose by the rule above, it jumped between poses a hair apart, so it
## would pop in any animation; following bones, nothing can jump. lay_all gives it in any pose.
##
## Points here are full precision (Vec64): a vector is a PackedFloat64Array of three; a list of points one flat
## PackedFloat64Array (x, y, z of each in turn), or (out, drop) pairs for a column's own line.

const CLEAR := 0.14            ## each corner of the figure is taken to be this much further out and up
const MARGIN := 0.75           ## a face also minds what stands this far past either of its two columns
const INNER := 5               ## rows of points a column has between its top and its trim line
const TRIM := 1.0              ## how much of a column's lower end is in the hem colour
const TIE := 1e-9              ## lengths this close are equal: the first of them is taken, whatever the rounding

# following the bones (lowpoly/hang.py)
const SKIRT_FROM := 0.5        ## skirt cloth higher than this above the hip line follows only its top
const SKIRT_OVER := 1.5        ## below that, it comes to follow the skirt bones wholly over this much further down
const KNEE_FROM := 1.0         ## and from this far above the knee it comes to follow the bones at the knee,
const KNEE_OVER := 2.0         ## wholly over this much further down
const CAPE_FROM := 3.0         ## a cape follows the chest down to this far above the hip line,
const CAPE_OVER := 5.0         ## then comes to follow its bone over this much further down
const MOST_BONES := 4          ## a point follows at most this many (what Godot's skinning takes); the slightest go

const LEG_BANDS: Array[String] = ["upper_thigh", "lower_thigh", "knee", "shin", "ankle", "foot"]
const TORSO_BANDS: Array[String] = ["upper_chest", "lower_chest", "belly", "waist", "hips"]
## what a cloth hangs over (lowpoly/specials.py _skirt_over, _cape_over)
const OVER_SKIRT := "skirt"
const OVER_CAPE := "cape"


class Column extends RefCounted:
	var top: PackedFloat64Array          ## where it is fixed, standing
	var shares: Dictionary               ## what that point follows: {part: share}
	var out: PackedFloat64Array          ## level: the way the column faces
	var side: PackedFloat64Array         ## level, across `out`: the way `spread` moves it
	var hem := 0.0                       ## the height its lower end hangs to, standing
	var trim := true                     ## its last unit of length is in the hem colour
	var angle := 0.0                     ## flare: where it hangs free it leans out by this angle
	var spread: Array = []               ## [] or [height, amount]: shifted sideways below that height
	var reach := 1.0                     ## a column with no neighbour minds what stands this far to either side
	var faces: Array = []                ## [facing, along, from, to] for each face it is an edge of
	var levels := PackedFloat64Array()   ## heights where it gets a row of points if it has rows to spare
	var length := -1.0                   ## worked out standing (settle)
	var spread_from := 0.0
	var marks := PackedFloat64Array()

	static func make(p_top: PackedFloat64Array, p_shares: Dictionary, p_out: PackedFloat64Array,
			p_side: PackedFloat64Array, p_hem: float, p_trim: bool = true, p_angle: float = 0.0,
			p_spread: Array = [], p_reach: float = 1.0, p_levels: PackedFloat64Array = PackedFloat64Array()) -> Column:
		var c := Column.new()
		c.top = p_top
		c.shares = p_shares
		c.out = Vec64.unit(p_out)
		c.side = Vec64.unit(p_side)
		c.hem = p_hem
		c.trim = p_trim
		c.angle = p_angle
		c.spread = p_spread
		c.reach = p_reach
		c.levels = p_levels
		return c


var name := ""
## The cloth laid standing and bound to its bones (bind): {points, polys: [[corner numbers, role]], shares}. Made the
## first time the cloth is posed (lay_all), and kept: the cloth is the same object in every copy of its figure.
var bound := {}
var facing := PackedFloat64Array()      ## a sheet that hangs facing one way (a cape): that way; a skirt: empty
var columns: Array = []                 ## Column
var sheets: Array = []                  ## [[column numbers side by side], closed into a ring or not]
var colours: Dictionary = {}            ## {"cloth": Color, "hem": Color}
var frame := "pelvis"                   ## the part whose turning the columns face with
var over := OVER_SKIRT                  ## which of the figure's polygons it hangs over
var inner := INNER
var by := ""                            ## the worn item it is


static func make(p_name: String, p_columns: Array, p_sheets: Array, p_colours: Dictionary, p_frame: String,
		p_over: String, p_facing: PackedFloat64Array = PackedFloat64Array()) -> LowpolyCloth:
	var cloth := LowpolyCloth.new()
	cloth.name = p_name
	cloth.facing = p_facing
	cloth.columns = p_columns
	cloth.sheets = p_sheets
	cloth.colours = p_colours
	cloth.frame = p_frame
	cloth.over = p_over
	for col in p_columns:
		(col as Column).faces = []
	for pair in cloth.pairs():
		var ca: Column = p_columns[pair[0]]
		var cb: Column = p_columns[pair[1]]
		var n := Vec64.unit(Vec64.add(ca.out, cb.out))           # the way the face between them faces
		var gap := Vec64.sub(cb.top, ca.top)
		gap[2] = 0.0
		var e := Vec64.sub(gap, Vec64.mul(n, Vec64.dot(gap, n)))
		var span := Vec64.norm(e)
		if span < 1e-6:
			continue                                               # two columns fixed at the same place
		e = Vec64.div(e, span)
		ca.faces.append([n, e, -MARGIN, span + MARGIN])
		cb.faces.append([n, Vec64.neg(e), -MARGIN, span + MARGIN])
	for col in p_columns:
		var c: Column = col
		if c.faces.is_empty():
			c.faces.append([c.out, c.side, -c.reach, c.reach])
	return cloth


## Every two columns that have cloth between them.
func pairs() -> Array:
	var out: Array = []
	for sheet in sheets:
		var order: Array = sheet[0]
		for i in order.size() - 1:
			out.append([int(order[i]), int(order[i + 1])])
		if bool(sheet[1]):
			out.append([int(order[-1]), int(order[0])])
	return out


## Whether a cloth of this kind hangs over a polygon of the figure (its piece and band).
static func hangs_over(kind: String, piece: String, band: String) -> bool:
	if kind == OVER_CAPE:
		# the torso, the legs, and any cloth already hanging (a skirt); not the arms (lowpoly/specials.py)
		return (piece == "skin" and (TORSO_BANDS.has(band) or LEG_BANDS.has(band))) or piece.begins_with("foot") \
			or piece.begins_with("cloth")
	return (piece == "skin" and (band == "hips" or LEG_BANDS.has(band))) or piece.begins_with("foot")


# ---------------------------------------------------------------------------------------- one column ---

## The taut line. points: (out, drop) of everything under the column, from its top, as flat pairs. Returns the line
## as flat (out, drop) pairs, starting at the top, `length` long.
static func taut_line(points: PackedFloat64Array, length: float, angle: float) -> PackedFloat64Array:
	var hx := sin(angle)
	var hy := cos(angle)
	var line := PackedFloat64Array([0.0, 0.0])
	var ax := 0.0
	var ay := 0.0
	var left := length
	var count := points.size() / 2
	var used := PackedByteArray()
	used.resize(count)
	var far := PackedFloat64Array()
	far.resize(count)
	var turn := PackedFloat64Array()
	turn.resize(count)
	for _step in count + 1:
		if count == 0:
			break
		var most := -INF
		var any := false
		for i in count:
			var vx := points[2 * i] - ax
			var vy := points[2 * i + 1] - ay
			far[i] = sqrt(vx * vx + vy * vy)
			turn[i] = fposmod(atan2(vx, vy) - angle + PI, TAU) - PI      # 0 along the hanging line, more is further out
			if used[i] == 0 and far[i] > 1e-6 and turn[i] > 1e-6:
				any = true
				most = maxf(most, turn[i])
		if not any:
			break
		var k := -1
		for i in count:
			if used[i] == 0 and far[i] > 1e-6 and turn[i] > 1e-6 and turn[i] >= most - 1e-7:
				if k < 0 or far[i] > far[k]:
					k = i                                              # of those in line, the furthest
		for i in count:
			if used[i] == 0 and far[i] > 1e-6 and turn[i] > 1e-6 and turn[i] >= most - 1e-7:
				used[i] = 1
		var vkx := points[2 * k] - ax
		var vky := points[2 * k + 1] - ay
		if far[k] >= left:
			line.append(ax + vkx * left / far[k])
			line.append(ay + vky * left / far[k])
			return line
		line.append(points[2 * k])
		line.append(points[2 * k + 1])
		left -= far[k]
		ax = points[2 * k]
		ay = points[2 * k + 1]
	line.append(ax + hx * left)
	line.append(ay + hy * left)
	return line


static func _lengths(line: PackedFloat64Array) -> PackedFloat64Array:
	var cum := PackedFloat64Array([0.0])
	for i in line.size() / 2 - 1:
		var dx := line[2 * i + 2] - line[2 * i]
		var dy := line[2 * i + 3] - line[2 * i + 1]
		cum.append(cum[-1] + sqrt(dx * dx + dy * dy))
	return cum


## The point that far along the line: [out, drop].
static func _at(line: PackedFloat64Array, cum: PackedFloat64Array, s: float) -> PackedFloat64Array:
	s = clampf(s, 0.0, cum[-1])
	var n := line.size() / 2
	var right := 0                         # how many lengths are at or before s (numpy searchsorted, side right)
	for c in cum:
		if c <= s:
			right += 1
	var i := clampi(right - 1, 0, n - 2)
	var span := cum[i + 1] - cum[i]
	var f := (s - cum[i]) / span if span > 1e-12 else 0.0
	return PackedFloat64Array([line[2 * i] + f * (line[2 * i + 2] - line[2 * i]), line[2 * i + 1] + f * (line[2 * i + 3] - line[2 * i + 1])])


## How far along the line it first gets `drop` below its top.
static func _length_at_drop(line: PackedFloat64Array, cum: PackedFloat64Array, drop: float) -> float:
	for i in line.size() / 2 - 1:
		var a := line[2 * i + 1]
		var b := line[2 * i + 3]
		if b >= drop:
			if a >= drop:
				return cum[i]
			return cum[i] + (drop - a) / (b - a) * (cum[i + 1] - cum[i])
	return cum[-1]


static func _keep_less(a: Array, b: Array) -> bool:
	if float(a[0]) != float(b[0]):
		return float(a[0]) < float(b[0])
	return not bool(a[1]) and bool(b[1])


## Where along its line a column's rows of points go: the top, `inner` rows on the bends of the line, the trim
## line, the lower end. Returns [lengths along the line (always inner + 3), the line's cumulative lengths].
static func rows(line: PackedFloat64Array, col: Column, p_inner: int) -> Array:
	var cum := _lengths(line)
	var total := cum[-1]
	var trim_at := maxf(total - TRIM, 0.5 * total) if col.trim else total
	var fixed := PackedFloat64Array()
	if not col.spread.is_empty() and 0.05 < col.spread_from and col.spread_from < trim_at - 0.05:
		fixed.append(col.spread_from)
	var keep: Array = []
	for s in fixed:
		keep.append([s, true])
	for ci in range(1, cum.size() - 1):
		var c := cum[ci]
		if 0.05 < c and c < trim_at - 0.05:
			var clear := true
			for s in fixed:
				clear = clear and absf(c - s) > 0.05
			if clear:
				keep.append([c, false])
	keep.sort_custom(func(x: Array, y: Array) -> bool: return _keep_less(x, y))
	while keep.size() > p_inner:                                      # too many bends: drop the slightest
		var ends := _ends(keep, trim_at)
		var offs: Array = []
		var least := INF
		for i in keep.size():
			if bool(keep[i][1]):
				continue
			var a := _at(line, cum, ends[i])
			var p := _at(line, cum, float(keep[i][0]))
			var b := _at(line, cum, ends[i + 2])
			var abx := b[0] - a[0]
			var aby := b[1] - a[1]
			var n := sqrt(abx * abx + aby * aby)
			var off := absf(abx * (p[1] - a[1]) - aby * (p[0] - a[0])) / n if n > 1e-9 \
				else sqrt((p[0] - a[0]) * (p[0] - a[0]) + (p[1] - a[1]) * (p[1] - a[1]))
			offs.append([off, i])
			least = minf(least, off)
		for e in offs:                                                # the first of the slightest: points in a
			if float(e[0]) <= least + TIE:                            # straight run tie, and rounding must not choose
				keep.remove_at(int(e[1]))
				break
	for m in col.marks:                                               # rows to spare: first at the column's levels
		if keep.size() >= p_inner:
			break
		if 0.25 < m and m < trim_at - 0.25:
			var clear := true
			for e in keep:
				clear = clear and absf(m - float(e[0])) > 0.25
			if clear:
				keep.append([m, false])
				keep.sort_custom(func(x: Array, y: Array) -> bool: return _keep_less(x, y))
	while keep.size() < p_inner:                                      # then halve the longest stretch
		var ends := _ends(keep, trim_at)
		var longest := 0.0
		for j in ends.size() - 1:
			longest = maxf(longest, ends[j + 1] - ends[j])
		var i := 0
		while ends[i + 1] - ends[i] < longest - TIE:                  # the first of the longest: a halved stretch's
			i += 1                                                    # two halves tie, and rounding must not choose
		keep.insert(i, [0.5 * (ends[i] + ends[i + 1]), false])
	var at := PackedFloat64Array([0.0])
	for e in keep:
		at.append(float(e[0]))
	at.append(trim_at)
	at.append(total)
	return [at, cum]


static func _ends(keep: Array, trim_at: float) -> PackedFloat64Array:
	var ends := PackedFloat64Array([0.0])
	for e in keep:
		ends.append(float(e[0]))
	ends.append(trim_at)
	return ends


# --------------------------------------------------------------------------------------------- a cloth ---

## For a pose (transforms from LowpolyPose): [down, per column [top, out, side, faces]].
func _place(t: Dictionary, down_part: String = "pelvis") -> Array:
	var down := Vec64.apply(t[down_part][0], Vec64.v(0.0, 0.0, -1.0))
	var a: PackedFloat64Array = t[frame][0]
	var level := func(v: PackedFloat64Array) -> PackedFloat64Array:
		var av := Vec64.apply(a, v)
		return Vec64.unit(Vec64.sub(av, Vec64.mul(down, Vec64.dot(av, down))))
	var placed: Array = []
	for col in columns:
		var c: Column = col
		var top := LowpolyPose.bend(t, c.top, c.shares)
		var o: PackedFloat64Array = level.call(c.out)
		var s := Vec64.apply(a, c.side)
		s = Vec64.sub(s, Vec64.mul(down, Vec64.dot(s, down)))
		s = Vec64.unit(Vec64.sub(s, Vec64.mul(o, Vec64.dot(s, o))))
		var faces: Array = []
		for f in c.faces:
			faces.append([level.call(f[0]), level.call(f[1]), f[2], f[3]])
		placed.append([top, o, s, faces])
	return [down, placed]


## (out, drop) of every corner of the figure under a column, as flat pairs: for each of its faces, the corners
## behind that face, each by how far out the column must stand for the face to clear it. Corners at or above the
## column's top when the figure is at rest do not count.
static func _under(col: Column, placed: Array, down: PackedFloat64Array, p: PackedFloat64Array,
		z0: PackedFloat64Array) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var count := z0.size()
	if count == 0:
		return found
	var top: PackedFloat64Array = placed[0]
	var out: PackedFloat64Array = placed[1]
	var c := CLEAR * sqrt(0.5)
	for f in placed[3]:
		var n: PackedFloat64Array = f[0]
		var e: PackedFloat64Array = f[1]
		var k := Vec64.dot(out, n)
		if k < 0.2:
			continue
		for i in count:
			if not (z0[i] < col.top[2] - 1e-6):
				continue
			var rx := p[3 * i] - top[0]
			var ry := p[3 * i + 1] - top[1]
			var rz := p[3 * i + 2] - top[2]
			var s := rx * e[0] + ry * e[1] + rz * e[2]
			if s >= float(f[2]) and s <= float(f[3]):
				found.append((rx * n[0] + ry * n[1] + rz * n[2]) / k + c)
				found.append(rx * down[0] + ry * down[1] + rz * down[2] - c)
	return found


## Standing: fix every column's length, so that it hangs to its hem.
func settle(t: Dictionary, p: PackedFloat64Array, z0: PackedFloat64Array) -> void:
	var got := _place(t)
	var down: PackedFloat64Array = got[0]
	for i in columns.size():
		var col: Column = columns[i]
		var line := taut_line(_under(col, got[1][i], down, p, z0), 1e3, col.angle)
		var cum := _lengths(line)
		col.length = _length_at_drop(line, cum, col.top[2] - col.hem)
		col.spread_from = _length_at_drop(line, cum, col.top[2] - float(col.spread[0])) if not col.spread.is_empty() else 0.0
		col.marks = PackedFloat64Array()
		for z in col.levels:
			if col.hem < z and z < col.top[2]:
				col.marks.append(_length_at_drop(line, cum, col.top[2] - z))


## Every column's points in a pose: [grid (per column, a flat list of points), placed].
func _grid(t: Dictionary, p: PackedFloat64Array, z0: PackedFloat64Array) -> Array:
	var got := _place(t)
	var down: PackedFloat64Array = got[0]
	var grid: Array = []
	for i in columns.size():
		var col: Column = columns[i]
		var place: Array = got[1][i]
		var top: PackedFloat64Array = place[0]
		var out: PackedFloat64Array = place[1]
		var side: PackedFloat64Array = place[2]
		var line := taut_line(_under(col, place, down, p, z0), col.length, col.angle)
		var r := rows(line, col, inner)
		var pts := PackedFloat64Array()
		for s in (r[0] as PackedFloat64Array):
			var q := _at(line, r[1], s)
			var shift := 0.0
			if not col.spread.is_empty() and col.length - col.spread_from > 1e-6:
				shift = float(col.spread[1]) * maxf(0.0, s - col.spread_from) / (col.length - col.spread_from)
			var at := Vec64.add(Vec64.add(Vec64.add(top, Vec64.mul(out, q[0])), Vec64.mul(down, q[1])), Vec64.mul(side, shift))
			pts.append_array(at)
		grid.append(pts)
	return [grid, got[1]]


## Where every column's lower end is, in a pose: a flat list of points.
func ends(t: Dictionary, p: PackedFloat64Array, z0: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for pts in _grid(t, p, z0)[0]:
		var flat: PackedFloat64Array = pts
		out.append_array(flat.slice(flat.size() - 3))
	return out


## The cloth in a pose. p: every corner of the dressed, posed figure it hangs over; z0: the height each of those
## corners has at rest. Returns [[polygon (flat points), role ("cloth" or "hem")], ...].
func lay(t: Dictionary, p: PackedFloat64Array, z0: PackedFloat64Array) -> Array:
	var got := _grid(t, p, z0)
	var grid: Array = got[0]
	var placed: Array = got[1]
	var polys: Array = []
	var last := inner + 1                                            # the band between the trim line and the end
	for pair in pairs():
		var a: int = pair[0]
		var b: int = pair[1]
		var facing_ab := Vec64.add(placed[a][1], placed[b][1])
		for j in inner + 2:
			var quad := [Vec64.at(grid[a], j), Vec64.at(grid[b], j), Vec64.at(grid[b], j + 1), Vec64.at(grid[a], j + 1)]
			var pts: Array = []
			for q in quad:
				var dup := false
				for r in pts:
					dup = dup or Vec64.norm(Vec64.sub(q, r)) < 1e-6
				if not dup:
					pts.append(q)
			if pts.size() < 3:
				continue
			var n := PackedFloat64Array([0.0, 0.0, 0.0])
			for i in pts.size():
				n = Vec64.add(n, Vec64.cross(pts[i], pts[(i + 1) % pts.size()]))
			if Vec64.norm(n) < 1e-9:
				continue
			if Vec64.dot(n, facing_ab) < 0.0:
				pts.reverse()
			# a four-sided piece that is not flat is drawn as two triangles, split from its first corner to its third:
			# start it where that split folds outward, as cloth over a body does (lowpoly/hang.py)
			if pts.size() == 4:
				var fold := Vec64.sub(Vec64.mul(Vec64.add(pts[1], pts[3]), 0.5), Vec64.mul(Vec64.add(pts[0], pts[2]), 0.5))
				if Vec64.dot(fold, facing_ab) > 1e-9:
					pts = [pts[1], pts[2], pts[3], pts[0]]
			var flat := PackedFloat64Array()
			for q in pts:
				flat.append_array(q)
			var role := "hem" if (j == last and (columns[a] as Column).trim and (columns[b] as Column).trim) else "cloth"
			polys.append([flat, role])
	return polys


# ---------------------------------------------------------------------------------- following the bones ---

## What a point of a column follows, standing at p: {bone or part: share}.
func cloth_shares(col: Column, p: PackedFloat64Array, hip_z: float, knee_z: float) -> Dictionary:
	var skirt := frame == "pelvis"
	var g := clampf((hip_z + (SKIRT_FROM if skirt else CAPE_FROM) - p[2]) / (SKIRT_OVER if skirt else CAPE_OVER), 0.0, 1.0)
	var out := {}
	for part in col.shares.keys():
		out[String(part)] = (1.0 - g) * float(col.shares[part])
	if skirt:
		var low := clampf((knee_z + KNEE_FROM - p[2]) / KNEE_OVER, 0.0, 1.0)
		var ox := col.out[0]
		var oy := col.out[1]
		var q := {"skirt_front": pow(maxf(0.0, -oy), 2), "skirt_back": pow(maxf(0.0, oy), 2),
			"skirt_left": pow(maxf(0.0, ox), 2), "skirt_right": pow(maxf(0.0, -ox), 2)}
		var total := 0.0
		for bone in q.keys():
			total += float(q[bone])
		for bone in ["skirt_front", "skirt_back", "skirt_left", "skirt_right"]:
			var w := float(q[bone])
			if w <= 0.0:
				continue
			var share := g * w / total
			if (1.0 - low) * share > 0.0:
				out[bone] = float(out.get(bone, 0.0)) + (1.0 - low) * share
			if low * share > 0.0:
				out[bone + "_low"] = float(out.get(bone + "_low", 0.0)) + low * share
	else:
		out["cape_back"] = float(out.get("cape_back", 0.0)) + g
	var kept: Array = []
	for bone in out.keys():
		if float(out[bone]) > 1e-12:
			kept.append([float(out[bone]), String(bone)])
	kept.sort_custom(func(x: Array, y: Array) -> bool:
		return x[0] > y[0] if x[0] != y[0] else String(x[1]) < String(y[1]))
	kept = kept.slice(0, MOST_BONES)
	var sum := 0.0
	for e in kept:
		sum += float(e[0])
	var shares := {}
	for e in kept:
		shares[String(e[1])] = float(e[0]) / sum
	return shares


## The cloth laid standing (t: the figure at rest), kept as points and the polygons between them, with what every
## point follows: {points (flat), polys: [[corner numbers, role]], shares}. The polygons are lay()'s, standing.
func bind(t: Dictionary, p: PackedFloat64Array, z0: PackedFloat64Array, hip_z: float, knee_z: float) -> Dictionary:
	var got := _grid(t, p, z0)
	var grid: Array = got[0]
	var placed: Array = got[1]
	var rows_n := inner + 3
	var points := PackedFloat64Array()
	var shares: Array = []
	for a in grid.size():
		var flat: PackedFloat64Array = grid[a]
		points.append_array(flat)
		for i in flat.size() / 3:
			shares.append(cloth_shares(columns[a], Vec64.at(flat, i), hip_z, knee_z))
	var polys: Array = []
	var last := inner + 1
	for pair in pairs():
		var a: int = pair[0]
		var b: int = pair[1]
		var facing_ab := Vec64.add(placed[a][1], placed[b][1])
		for j in inner + 2:
			var quad := [a * rows_n + j, b * rows_n + j, b * rows_n + j + 1, a * rows_n + j + 1]
			var ids: Array = []
			for k in quad:
				var dup := false
				for i in ids:
					dup = dup or Vec64.norm(Vec64.sub(Vec64.at(points, k), Vec64.at(points, i))) < 1e-6
				if not dup:
					ids.append(k)
			if ids.size() < 3:
				continue
			var n := PackedFloat64Array([0.0, 0.0, 0.0])
			for i in ids.size():
				n = Vec64.add(n, Vec64.cross(Vec64.at(points, ids[i]), Vec64.at(points, ids[(i + 1) % ids.size()])))
			if Vec64.norm(n) < 1e-9:
				continue
			if Vec64.dot(n, facing_ab) < 0.0:
				ids.reverse()
			if ids.size() == 4:
				var fold := Vec64.sub(Vec64.mul(Vec64.add(Vec64.at(points, ids[1]), Vec64.at(points, ids[3])), 0.5),
					Vec64.mul(Vec64.add(Vec64.at(points, ids[0]), Vec64.at(points, ids[2])), 0.5))
				if Vec64.dot(fold, facing_ab) > 1e-9:
					ids = [ids[1], ids[2], ids[3], ids[0]]
			var role := "hem" if (j == last and (columns[a] as Column).trim and (columns[b] as Column).trim) else "cloth"
			polys.append([PackedInt32Array(ids), role])
	return {"points": points, "polys": polys, "shares": shares}


## A bound cloth in a pose (t: LowpolyPose transforms with the cloth bones): [[polygon (flat points), role], ...].
static func posed(b: Dictionary, t: Dictionary) -> Array:
	var points: PackedFloat64Array = b["points"]
	var moved := PackedFloat64Array()
	moved.resize(points.size())
	var shares: Array = b["shares"]
	for i in points.size() / 3:
		var q := LowpolyPose.bend(t, Vec64.at(points, i), shares[i])
		moved[3 * i] = q[0]
		moved[3 * i + 1] = q[1]
		moved[3 * i + 2] = q[2]
	var out: Array = []
	for entry in b["polys"]:
		var flat := PackedFloat64Array()
		for k in (entry[0] as PackedInt32Array):
			flat.append_array(Vec64.at(moved, k))
		out.append([flat, String(entry[1])])
	return out


# ------------------------------------------------------------------------------------------ in a pose ---

## Bind every cloth of a figure that is not bound yet: each laid standing over the figure and over the cloths before
## it (lowpoly/dress.py, when it dresses the figure).
static func bind_all(figure: LowpolyFigure) -> void:
	var missing := false
	for c in figure.cloths:
		missing = missing or (c as LowpolyCloth).bound.is_empty()
	if not missing:
		return
	var rest := LowpolyPose.rest()
	var hip_z := LowpolyPose.hip_point(figure.parts)[2]
	var knee_z := LowpolyPose.knee_point(figure.parts)[2]
	var laid: Array = []                 # cloth laid so far, standing: [[polygon, role], ...]
	for c in figure.cloths:
		var cloth: LowpolyCloth = c
		if cloth.bound.is_empty():
			var p := PackedFloat64Array()
			var z0 := PackedFloat64Array()
			for poly in figure.polygons:
				if not hangs_over(cloth.over, String(poly["piece"]), RegionMap.key_band(String(poly["region"]))):
					continue
				for k in poly["corners"]:
					p.append_array(figure.point64(k))
					z0.append(figure.points64[3 * k + 2])
			if hangs_over(cloth.over, "cloth:", ""):
				for made in laid:
					var flat: PackedFloat64Array = made[0]
					p.append_array(flat)
					for i in flat.size() / 3:
						z0.append(-1.0)            # cloth already hanging always counts
			cloth.bound = cloth.bind(rest, p, z0, hip_z, knee_z)
		laid.append_array(posed(cloth.bound, rest))


## Every cloth of a figure in a pose: [[cloth, [[polygon (flat points), role], ...]], ...], following its bones
## (lowpoly/pose.py laid).
static func lay_all(figure: LowpolyFigure, pose: Dictionary) -> Array:
	var out: Array = []
	if figure.cloths.is_empty():
		return out
	bind_all(figure)
	var t := LowpolyPose.with_cloth_bones(LowpolyPose.transforms(pose, figure.parts), figure.parts)
	for c in figure.cloths:
		out.append([c, posed((c as LowpolyCloth).bound, t)])
	return out
