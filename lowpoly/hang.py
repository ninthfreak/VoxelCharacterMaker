"""Hanging cloth: skirts and capes.

Hanging cloth is not part of the bending skin, and it is not turned by a rule either (the voxel panels were: each
swung by 0.8 of a thigh's swing). It is a few COLUMNS of cloth. Each column is fixed at its top to the figure (a skirt
to the waist line, a cape to the shoulder line) and has a fixed length. For any pose, every column is laid by one rule:

    a taut line from its top, over whatever of the figure sticks out under it, then straight down for the rest of
    its length (leaning out by the garment's flare).

Nothing is simulated and nothing is remembered from one pose to the next: the shape is worked out from the pose alone,
so standing still is just one more pose. That one rule gives the fit over the hips and seat when standing, the lap when
sitting, the knee pushing the front out in a stride, and the heel pushing the back out, with nothing set per pose.

"Down" is the figure's own down (the pelvis's), so cloth hangs the same way however the whole figure is turned.

A column's line lives in the upright plane it faces: `out` is how far out from its top, `drop` how far below.
The cloth between two neighbouring columns is a flat-ish FACE. A corner of the dressed figure counts as "under" a
column when it stands behind one of the column's faces, and it counts by how far the column must stand out for that
face to clear it. (Measuring every corner along the column's own facing instead leaves knees and toes poking through
the faces between columns: tried first, and they did.)
"""
import numpy as np

CLEAR = 0.14            # each corner of the figure is taken to be this much further out and up, so cloth clears it
MARGIN = 0.75           # a face also minds what stands this far past either of its two columns
INNER = 5               # rows of points a column has between its top and its trim line; they sit on its bends. Three
                        # were too few for the heavy and short bodies sitting: a column lying over the lap put its rows
                        # on the lap's edge while its neighbour hanging at the side spread its rows down its fall, and
                        # the cloth between them cut across the thick thigh
TRIM = 1.0              # how much of a column's lower end is in the hem colour


def unit(v):
    v = np.asarray(v, float); n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


class Column:
    def __init__(self, top, shares, out, side, hem, trim=True, angle=0.0, spread=None, reach=1.0, levels=()):
        self.top = np.asarray(top, float)     # where it is fixed, standing
        self.shares = shares                  # what that point follows: {part: share}
        self.out = unit(out)                  # level: the way the column faces
        self.side = unit(side)                # level, across `out`: the way `spread` moves it
        self.hem = float(hem)                 # the height its lower end hangs to, standing
        self.trim = bool(trim)                # its last unit of length is in the hem colour
        self.angle = float(angle)             # flare: where it hangs free it leans out by this angle, not straight down
        self.spread = spread                  # None, or (height, amount): shifted sideways below that height, by
                                              # that much at the hem
        self.reach = float(reach)             # a column with no neighbour minds what stands this far to either side
        self.faces = []                       # set by Cloth: (facing, along, from, to) for each face it is an edge of
        self.levels = tuple(levels)           # heights where it gets a row of points if it has rows to spare: the
                                              # same heights on every column keep the rows level where the cloth
                                              # hangs straight
        self.length = None; self.spread_from = 0.0; self.marks = []     # worked out standing, by settle()


class Cloth:
    def __init__(self, name, columns, sheets, colours, frame, over, inner=INNER, facing=None):
        self.name = name
        self.facing = facing                  # a sheet that hangs facing one way (a cape): that way. A skirt: None
        self.columns = columns
        self.sheets = sheets                  # [(column numbers side by side, closed into a ring or not)]
        self.colours = colours                # {"cloth": rgb, "hem": rgb}
        self.frame = frame                    # the part whose turning the columns face with
        self.over = over                      # which of the figure's polygons it hangs over: f(polygon) -> bool
        self.inner = inner
        for col in columns: col.faces = []
        for a, b in self.pairs():
            ca, cb = columns[a], columns[b]
            n = unit(ca.out + cb.out)                               # the way the face between them faces
            gap = cb.top - ca.top; gap[2] = 0.0
            e = gap - (gap @ n) * n; span = np.linalg.norm(e)
            if span < 1e-6: continue                                # two columns fixed at the same place
            e = e / span
            ca.faces.append((n, e, -MARGIN, span + MARGIN)); cb.faces.append((n, -e, -MARGIN, span + MARGIN))
        for col in columns:
            if not col.faces: col.faces.append((col.out, col.side, -col.reach, col.reach))

    def pairs(self):
        """Every two columns that have cloth between them."""
        out = []
        for order, closed in self.sheets:
            out += list(zip(order[:-1], order[1:])) + ([(order[-1], order[0])] if closed else [])
        return out


# ------------------------------------------------------------------------------------------------ one column ---

def wrap(points, length, angle):
    """The taut line. points: (out, drop) of everything under the column, from its top. Returns the line as a
    list of (out, drop), starting at the top, `length` long."""
    hang = np.array([np.sin(angle), np.cos(angle)])
    line = [np.zeros(2)]; at = np.zeros(2); left = float(length)
    used = np.zeros(len(points), bool)
    for _ in range(len(points) + 1):
        if len(points) == 0: break
        v = points - at
        far = np.hypot(v[:, 0], v[:, 1])
        turn = np.arctan2(v[:, 0], v[:, 1]) - angle                 # 0 along the hanging line, more is further out
        turn = (turn + np.pi) % (2.0 * np.pi) - np.pi
        ok = (~used) & (far > 1e-6) & (turn > 1e-6)
        if not ok.any(): break
        most = turn[ok].max()
        cand = np.where(ok & (turn >= most - 1e-7))[0]
        k = cand[int(np.argmax(far[cand]))]                         # of those in line, the furthest
        used |= ok & (turn >= most - 1e-7)
        if far[k] >= left:
            line.append(at + v[k] * left / far[k]); return line
        line.append(points[k].copy()); left -= far[k]; at = points[k].copy()
    line.append(at + hang * left)
    return line


def _lengths(line):
    return np.concatenate([[0.0], np.cumsum([np.linalg.norm(b - a) for a, b in zip(line[:-1], line[1:])])])


def _at(line, cum, s):
    s = float(np.clip(s, 0.0, cum[-1]))
    i = int(np.clip(np.searchsorted(cum, s, side="right") - 1, 0, len(line) - 2))
    span = cum[i + 1] - cum[i]
    f = (s - cum[i]) / span if span > 1e-12 else 0.0
    return line[i] + f * (line[i + 1] - line[i])


def _length_at_drop(line, cum, drop):
    """How far along the line it first gets `drop` below its top."""
    for i in range(len(line) - 1):
        a, b = line[i][1], line[i + 1][1]
        if b >= drop:
            if a >= drop: return float(cum[i])
            return float(cum[i] + (drop - a) / (b - a) * (cum[i + 1] - cum[i]))
    return float(cum[-1])


def rows(line, col, inner):
    """Where along its line a column's rows of points go: the top, `inner` rows on the bends of the line, the trim
    line, the lower end. Returns lengths along the line (always inner + 3 of them)."""
    cum = _lengths(line); total = cum[-1]
    trim_at = max(total - TRIM, 0.5 * total) if col.trim else total
    fixed = [col.spread_from] if (col.spread and 0.05 < col.spread_from < trim_at - 0.05) else []
    keep = [(s, True) for s in fixed]
    keep += [(float(c), False) for c in cum[1:-1] if 0.05 < c < trim_at - 0.05 and all(abs(c - s) > 0.05 for s in fixed)]
    keep.sort()
    while len(keep) > inner:                                        # too many bends: drop the slightest
        ends = [0.0] + [s for s, _ in keep] + [trim_at]
        worst = None
        for i, (s, is_fixed) in enumerate(keep):
            if is_fixed: continue
            a, p, b = _at(line, cum, ends[i]), _at(line, cum, s), _at(line, cum, ends[i + 2])
            ab = b - a; n = np.linalg.norm(ab)
            off = abs(ab[0] * (p - a)[1] - ab[1] * (p - a)[0]) / n if n > 1e-9 else np.linalg.norm(p - a)
            if worst is None or off < worst[0]: worst = (off, i)
        del keep[worst[1]]
    for m in col.marks:                                             # rows to spare: first at the column's levels
        if len(keep) >= inner: break
        if 0.25 < m < trim_at - 0.25 and all(abs(m - s) > 0.25 for s, _ in keep):
            keep.append((m, False)); keep.sort()
    while len(keep) < inner:                                        # then halve the longest stretch
        ends = [0.0] + [s for s, _ in keep] + [trim_at]
        i = int(np.argmax(np.diff(ends)))
        keep.insert(i, (0.5 * (ends[i] + ends[i + 1]), False))
    return [0.0] + [s for s, _ in keep] + [trim_at, total], cum


# ------------------------------------------------------------------------------------------------- a cloth ---

def _place(cloth, T, down_part="pelvis"):
    """For a pose: down, and every column's top, facing, side and faces."""
    down = T[down_part][0] @ np.array([0.0, 0.0, -1.0])
    A = T[cloth.frame][0]
    level = lambda v: unit(A @ v - ((A @ v) @ down) * down)
    out = []
    for col in cloth.columns:
        top = sum(w * (T[p][0] @ col.top + T[p][1]) for p, w in col.shares.items())
        o = level(col.out)
        s = A @ col.side; s = s - (s @ down) * down; s = unit(s - (s @ o) * o)
        out.append((top, o, s, [(level(n), level(e), s0, s1) for n, e, s0, s1 in col.faces]))
    return down, out


def _under(col, placed, down, P, Z0):
    """(out, drop) of every corner of the figure under a column: for each of its faces, the corners behind that
    face, each by how far out the column must stand for the face to clear it. Corners that stand at or above the
    column's top when the figure is at rest (its own fixing line, and what is above it) do not count."""
    top, out, _, faces = placed
    if len(P) == 0: return np.zeros((0, 2))
    rel = P - top
    low = Z0 < col.top[2] - 1e-6
    c = CLEAR * np.sqrt(0.5)
    found = [np.zeros((0, 2))]
    for n, e, s0, s1 in faces:
        k = out @ n
        if k < 0.2: continue
        s = rel @ e
        use = low & (s >= s0) & (s <= s1)
        found.append(np.stack([(rel[use] @ n) / k + c, rel[use] @ down - c], axis=1))
    return np.concatenate(found)


def settle(cloth, T, P, Z0):
    """Standing: fix every column's length, so that it hangs to its hem."""
    down, placed = _place(cloth, T)
    for col, place in zip(cloth.columns, placed):
        line = wrap(_under(col, place, down, P, Z0), 1e3, col.angle); cum = _lengths(line)
        col.length = _length_at_drop(line, cum, col.top[2] - col.hem)
        col.spread_from = _length_at_drop(line, cum, col.top[2] - col.spread[0]) if col.spread else 0.0
        col.marks = [_length_at_drop(line, cum, col.top[2] - z) for z in col.levels if col.hem < z < col.top[2]]


def _grid(cloth, T, P, Z0):
    down, placed = _place(cloth, T)
    grid = []
    for col, place in zip(cloth.columns, placed):
        top, out, side, _ = place
        line = wrap(_under(col, place, down, P, Z0), col.length, col.angle)
        at, cum = rows(line, col, cloth.inner)
        pts = []
        for s in at:
            p = _at(line, cum, s)
            shift = 0.0
            if col.spread and col.length - col.spread_from > 1e-6:
                shift = col.spread[1] * max(0.0, s - col.spread_from) / (col.length - col.spread_from)
            pts.append(top + p[0] * out + p[1] * down + shift * side)
        grid.append(pts)
    return grid, placed


def ends(cloth, T, P, Z0):
    """Where every column's lower end is, in a pose."""
    return [pts[-1] for pts in _grid(cloth, T, P, Z0)[0]]


def lay(cloth, T, P, Z0):
    """The cloth in a pose. P: every corner of the dressed, posed figure it hangs over; Z0: the height each of
    those corners has at rest. Returns [(polygon, role)]."""
    grid, placed = _grid(cloth, T, P, Z0)
    polys = []
    last = cloth.inner + 1                                          # the band between the trim line and the end
    for a, b in cloth.pairs():
        facing = placed[a][1] + placed[b][1]
        for j in range(cloth.inner + 2):
            quad = [grid[a][j], grid[b][j], grid[b][j + 1], grid[a][j + 1]]
            pts = []
            for p in quad:
                if not any(np.linalg.norm(p - q) < 1e-6 for q in pts): pts.append(p)
            if len(pts) < 3: continue
            pts = np.array(pts)
            n = np.zeros(3)
            for i in range(len(pts)):
                n += np.cross(pts[i], pts[(i + 1) % len(pts)])
            if np.linalg.norm(n) < 1e-9: continue
            if n @ facing < 0: pts = pts[::-1].copy()
            # A four-sided piece that is not flat is drawn as two triangles, split from its first corner to its third.
            # Start it where that split folds outward, as cloth over a body does: folded inward, a piece lying over
            # the lap on one side and hanging straight down on the other cuts across the outer side of the thigh.
            if len(pts) == 4 and (0.5 * (pts[1] + pts[3]) - 0.5 * (pts[0] + pts[2])) @ facing > 1e-9:
                pts = pts[[1, 2, 3, 0]]
            role = "hem" if (j == last and cloth.columns[a].trim and cloth.columns[b].trim) else "cloth"
            polys.append((pts, role))
    return polys


def through(polys, P, axis=None, facing=None):
    """How far the figure comes through cloth. polys: the cloth's polygons; P: corners of the figure.
    Round a skirt, give axis: the (x, y) of the upright line the figure stands round. For each corner, look along the
    level line from that axis out through the corner: if cloth crosses that line nearer the axis than the corner is,
    the corner has come through, by the difference.
    Behind a sheet, give facing: the way the sheet faces. A corner has come through if, looking from it back against
    that direction, there is cloth.
    Returns the largest such distance (0 if nothing comes through)."""
    tris = []
    for p in polys:
        tris += [p[[0, i, i + 1]] for i in range(1, len(p) - 1)]
    if not tris or len(P) == 0: return 0.0
    tris = np.array(tris); a = tris[:, 0]; e1 = tris[:, 1] - a; e2 = tris[:, 2] - a
    worst = 0.0
    for p in P:
        if facing is None:
            origin = np.array([axis[0], axis[1], p[2]]); d = p - origin; far = np.linalg.norm(d)
            if far < 1e-6: continue
            d = d / far
        else:
            origin = p; d = -unit(facing); far = 0.0
        h = np.cross(d, e2); det = np.einsum("ij,ij->i", e1, h)
        ok = np.abs(det) > 1e-12; inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = origin - a; u = np.einsum("ij,ij->i", s, h) * inv
        q = np.cross(s, e1); v = (q @ d) * inv
        t = np.einsum("ij,ij->i", e2, q) * inv
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1.0) & (t > 1e-6)
        if hit.any(): worst = max(worst, (far - float(t[hit].min())) if facing is None else float(t[hit].min()))
    return worst
