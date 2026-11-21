"""The hood, as polygons. The game builds it the same way (core/lowpoly/lowpoly_hood.gd), checked against this corner by
corner (expected.py).

A raised hood is a loose shell over the head with the face left open, falling to a short cowl that lies on the
shoulders. It is measured from the dressed figure (the head with its hair, the neck, the tops of the arms), so it fits
every head and body and stands clear of whatever is under it.

  shell    rows round the head, top to bottom, each a ring of points measured outward from the middle of the head:
           how far the dressed head reaches that way (from its rings of corners), plus a gap. The gap is the hood's
           looseness: most at the back, where the hood's bag is, and over the crown; a brim over the brows.
  opening  the face opening is cut from the front of the shell: an arch over the brows, straight sides beside the
           eyes, closing under the chin. Its setting moves its edge out past the eye box.
  cowl     below the widest part of the head the shell no longer follows the head: it falls to the shoulders and lies
           on them, ending in a short hem below the shoulder line.
  clear    then every corner of the dressed figure under the hood (ears, hair, the tops of the arms) is checked against
           the hood's faces, and the hood is pushed out wherever one comes through.
  inside   a second shell just inside the first, in the lining colour when the hood is lined, so the inside shows
           through the opening; a strip joins the two round the opening and along the hem.

A lowered hood (raised off) is a cowl closed round the neck, with the empty hood lying on the upper back over it,
its opening turned up (in the lining colour when the hood is lined).

Settings, with the game's names (core/specials/special_item.gd): raised, depth (shown as "Looseness": how far the hood
stands off the head, 1 to 3), opening (how far past the eye box the opening reaches, 0 to 3), lined, and four for its
shape, each 0 to 3 (the owner's hand-tuning): brim (how far it comes forward over the brows), fullness (how much room
at the back), peak (0 a round dome over the crown, 3 a point drawn up and back) and cowl_length (how far the cowl comes
down over the shoulders; for a lowered hood, its collar).
"""
import numpy as np
import body as lb
import heads

CX, CY = lb.CX, lb.CY
SEGMENTS = 14                   # quads in each row of the shell, round from one edge of the opening to the other
THICK = 0.35                    # how far the inside is from the outside
LOOSE = {1: 1.3, 2: 1.9, 3: 2.5}  # depth setting -> the hood's looseness: the gap between the dressed head and the hood
CLEAR = 0.25                    # how far the hood stays off anything under it
FACE_EDGE = heads.FACE_HALF_WIDTH  # the eye boxes reach this far either side of the centre line
BROW_TOP = heads.FACE_Z[1]      # the brow row's top
WIDE = 31.0                     # the head's widest row: below it the hood falls loose to the shoulders
JAW = 28.6                      # where the opening's sides turn in under the chin
SHOULDER = 0.95                 # where the cowl lies on the shoulder, against the shoulder's width
POUCH_ROWS, POUCH_COLUMNS = 5, 6  # a lowered hood's pouch: rows down the back, quads across
# the shape settings, 0 to 3 (1 is the first pass's shape, but for the top: peak 0 is a round dome)
BRIM = (0.0, 1.0, 1.7, 2.4)     # how far the brim comes forward over the brows, against the first pass's
FULLNESS = (0.3, 1.0, 1.6, 2.2)  # how much room the back of the hood has, against the first pass's
COWL_DROP = (0.9, 1.6, 2.6, 3.8)  # how far the cowl's hem comes below the shoulder line
CAP = (65.0, 35.0)              # the dome over the crown: two rings, at these angles from level (top first)


def _unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def _direction(theta):
    """Level, theta from straight ahead round by the figure's left."""
    return np.array([np.sin(theta), -np.cos(theta), 0.0])


def _ray_ring(ring, theta, centre=(CX, CY)):
    """How far a closed ring of points reaches from the centre the way theta points (the farthest crossing)."""
    d = _direction(theta)[:2]; o = np.array(centre, float); best = 0.0
    for i in range(len(ring)):
        a = np.asarray(ring[i][:2], float) - o; b = np.asarray(ring[(i + 1) % len(ring)][:2], float) - o
        e = b - a; den = d[0] * (-e[1]) - d[1] * (-e[0])
        if abs(den) < 1e-12: continue
        t = (a[0] * (-e[1]) - a[1] * (-e[0])) / den                  # solve t d = a + s e
        s = (d[0] * a[1] - d[1] * a[0]) / den
        if -1e-9 <= s <= 1.0 + 1e-9 and t > best: best = t
    return best


def _opening(p):
    """The face opening: its half-width beside the eyes, the top of its arch and the arch's height (head heights)."""
    slack = float(np.clip(int(p["opening"]), 0, 3))
    half = FACE_EDGE + 0.4 + 0.75 * slack
    top = BROW_TOP + 0.6 + 0.6 * slack
    return half, top, min(half, 3.0 + 0.3 * slack)


def _edge_half(z, half, top, arch, bottom):
    """The opening's half-width at height z (head heights): 0 above it and below it."""
    if z >= top - 1e-9 or z <= bottom + 1e-9: return 0.0
    c = top - arch
    if z > c: return half * float(np.sqrt(max(0.0, 1.0 - ((z - c) / arch) ** 2)))
    if z >= JAW: return half
    return half * float(np.sqrt(max(0.0, 1.0 - ((JAW - z) / (JAW - bottom)) ** 2)))


def _inside_quad(x, quad, n):
    """Whether x, seen along n, falls inside the polygon."""
    for i in range(len(quad)):
        a, b = quad[i], quad[(i + 1) % len(quad)]
        if np.cross(b - a, x - a) @ n < -1e-9: return False
    return True


class _Measure:
    """The dressed figure round the head and shoulders, measured for a hood."""

    def __init__(self, fit):
        info = fit.body.get("info", {})
        self.fit = fit; self.dz = float(info.get("head_dz", 0.0))
        lift = np.array([0.0, 0.0, self.dz])
        self.head_rings = [(z, [fit.at(v + lift, "head") for v in ring]) for z, ring in zip(heads.RING_Z, heads.rings(info["head"]))]
        self.crown_top = fit.at(np.array([CX, CY + heads.SEAM, heads.TOP]) + lift, "head")
        neck_band = fit.band("neck"); collar = fit.band("collar")
        self.neck = 0.5 * (neck_band[0] + neck_band[1]); self.neck_top = neck_band[1]
        self.shoulder = collar[0]; self.hem = self.shoulder - 1.6
        self.body_rings = [(z, [fit.at(v) for v in fit.ring(z)]) for z in fit.heights(("neck", "collar", "upper_chest", "lower_chest"))]
        arm = np.array([v for q in fit._polys if q["piece"] == "arm_L" and not q["hidden"] for v in q["pts"]])
        self.shoulder_w = float(arm[arm[:, 2] > arm[:, 2].max() - 1.5][:, 0].max() - CX) if len(arm) else 6.0

    def head(self, theta, zh):
        """How far the dressed head reaches from the middle line at a head height."""
        rg = self.head_rings; zs = [z for z, _ in rg]
        if zh >= zs[0]: return _ray_ring(rg[0][1], theta)
        if zh <= zs[-1]: return _ray_ring(rg[-1][1], theta)
        i = next(i for i in range(len(zs) - 1) if zs[i + 1] <= zh <= zs[i])
        f = (zs[i] - zh) / (zs[i] - zs[i + 1])
        return _ray_ring([(1 - f) * a + f * b for a, b in zip(rg[i][1], rg[i + 1][1])], theta)

    def body(self, theta, zw):
        """How far the dressed torso reaches from the middle line at a height of the figure."""
        rg = self.body_rings
        below = [r for r in rg if r[0] <= zw + 1e-6]; above = [r for r in rg if r[0] >= zw - 1e-6]
        a = below[-1] if below else rg[0]; b = above[0] if above else rg[-1]
        ra, rb = _ray_ring(a[1], theta), _ray_ring(b[1], theta)
        return ra if b[0] - a[0] < 1e-6 else ra + (zw - a[0]) / (b[0] - a[0]) * (rb - ra)

    def lying(self, theta, zw, a, depth_at):
        """A ring round the shoulders: as wide as a, as deep as the body there plus depth_at, an ellipse between."""
        d = self.body(0.0 if np.cos(theta) > 0 else np.pi, zw) + depth_at
        r = 1.0 / np.sqrt((np.sin(theta) / a) ** 2 + (np.cos(theta) / d) ** 2)
        return max(r, self.body(theta, zw) + depth_at)

    def corners(self, low, head=True):
        """Every corner of the dressed figure above a height (the head's too, or not): what the hood must stay clear of."""
        return np.array([v for q in self.fit._polys if not q["hidden"] and (head or q["piece"] != "head") for v in q["pts"] if v[2] > low])


class _Shell:
    """Points and faces of a hood's outside, then pushed clear of the figure and given an inside."""

    def __init__(self):
        self.V = []; self.follows = []; self.faces = []

    def add(self, v, sh):
        self.V = list(self.V); self.V.append(np.array(v, float)); self.follows.append(sh); return len(self.V) - 1

    def ring(self, points, sh, closed):
        idx = [self.add(v, sh) for v in points]
        if closed: idx.append(idx[0])
        return idx

    def strip(self, a, b):
        self.faces += [(a[k], a[k + 1], b[k + 1], b[k]) for k in range(len(a) - 1)]

    def normals(self):
        V = np.asarray(self.V); n = np.zeros_like(V); fn = []
        for f in self.faces:
            pts = V[list(f)]; c = np.zeros(3)
            for i in range(len(pts)): c += np.cross(pts[i], pts[(i + 1) % len(pts)])
            fn.append(c)
            for i in f: n[i] += c
        return np.array([_unit(v) for v in n]), [_unit(c) for c in fn]

    def wind_out(self, middle):
        """Turn the faces to face away from a point inside. They are built in a grid, so all of them face the same
        way: turn all or none, by most of them (face by face, a face lying flat on the shoulders can look inward)."""
        V = np.asarray(self.V); _, fn = self.normals()
        out = sum(1 for f, c in zip(self.faces, fn) if c @ (V[list(f)].mean(axis=0) - middle) > 0)
        if out < len(self.faces) / 2: self.faces = [tuple(reversed(f)) for f in self.faces]

    def clear(self, P):
        """Push the shell out wherever one of the corners P comes through it, or comes within CLEAR of it."""
        V = np.asarray(self.V)
        for _ in range(4):
            self.V = V; vn, fn = self.normals(); push = np.zeros(len(V))
            for f, n in zip(self.faces, fn):
                pts = V[list(f)]; m = pts.mean(axis=0)
                lo, hi = pts.min(axis=0) - 3.0, pts.max(axis=0) + 3.0
                need = 0.0
                for x in P[np.all((P >= lo) & (P <= hi), axis=1)]:
                    d = (x - m) @ n
                    if -CLEAR < d < 3.0 and _inside_quad(x, pts, n): need = max(need, d + CLEAR)
                for i in f: push[i] = max(push[i], need)
            if push.max() < 1e-3: break
            spread = push.copy()                                     # a gentle bump, not a ledge: two rings of neighbours go
            for _ in range(2):                                       # out part way (0.65 of it, then 0.42)
                step = spread.copy()
                for f in self.faces:
                    m = max(spread[i] for i in f)
                    for i in f: step[i] = max(step[i], 0.65 * m)
                spread = step
            V = V + vn * spread[:, None]
        self.V = V

    def polygons(self, cloth, inside, edges):
        """The outside in the cloth colour, the inside THICK within it (none if inside is None), and a strip between the
        two along each edge. edges: runs of (corner, its neighbour away from the edge)."""
        V = np.asarray(self.V); vn, _ = self.normals(); V_in = V - THICK * vn
        polys = []

        def put(pts, rgb, sh):
            pts = np.array(pts, float); sh = list(sh)
            keep = [i for i in range(len(pts)) if np.linalg.norm(pts[i] - pts[i - 1]) > 1e-6]
            if len(keep) < 3: return
            polys.append(dict(pts=pts[keep], rgb=rgb, shares=[sh[i] for i in keep],
                              part="head" if all(s.get("head", 0.0) > 0.99 for s in sh) else "chest"))

        for f in self.faces:
            sh = [self.follows[i] for i in f]
            put(V[list(f)], cloth, sh)
            if inside is not None: put(V_in[list(f)][::-1], inside, sh[::-1])
        for run in edges:
            for (a, na), (b, nb) in zip(run[:-1], run[1:]):
                if a == b: continue
                q = [V[a], V[b], V_in[b], V_in[a]]; sh = [self.follows[i] for i in (a, b, b, a)]
                n = np.cross(V[b] - V[a], V_in[a] - V[a])
                if n @ ((V[a] + V[b]) - (V[na] + V[nb])) < 0: q = q[::-1]; sh = sh[::-1]   # facing away from the shell
                put(q, inside, sh)
        return polys


def _setting(p, key):
    return int(np.clip(int(p[key]), 0, 3))


def _colours(p, colours):
    cloth = colours.get("cloth", (128, 128, 128))
    return cloth, (colours.get("lining", cloth) if bool(p["lined"]) else cloth)


def raised(fit, p, colours, name="hood"):
    """Returns ([polygon dicts: pts, rgb, shares, part], notes)."""
    m = _Measure(fit); dz = m.dz
    loose = LOOSE.get(int(np.clip(int(p["depth"]), 1, 3)), LOOSE[1])
    cloth, inside = _colours(p, colours)
    half, top, arch = _opening(p)
    brim_k, full_k, peak = BRIM[_setting(p, "brim")], FULLNESS[_setting(p, "fullness")], _setting(p, "peak")
    m.hem = m.shoulder - COWL_DROP[_setting(p, "cowl_length")]

    def gap(theta, zh):
        back = 0.5 * (1.0 - np.cos(theta)); front = 1.0 - back
        crown = float(np.clip((zh - 34.0) / 5.0, 0.0, 1.0))
        bag = float(np.clip(1.0 - abs(zh - 35.0) / 7.0, 0.3, 1.0))
        brim = brim_k * (0.5 + 0.4 * loose) * front ** 2 * (0.4 + 0.6 * float(np.clip((zh - 32.0) / 4.0, 0.0, 1.0)))
        return loose * (0.45 + 0.75 * full_k * back ** 1.5 * bag + 0.45 * crown) + brim

    def on_shoulder(theta):
        return m.lying(theta, m.shoulder, SHOULDER * m.shoulder_w + 0.2, 0.5 * loose)

    def radius(theta, zh, zw):
        """How far the hood is from the middle line at this angle and height (zh: the head's height for it)."""
        if zh >= WIDE:
            return m.head(theta, zh) + gap(theta, zh)
        hung = radius(theta, WIDE, WIDE + dz)                       # falling from the head's widest row ...
        s = float(np.clip((WIDE + dz - zw) / (WIDE + dz - m.shoulder), 0.0, 1.0))
        r = (1.0 - s) * hung + s * on_shoulder(theta)               # ... to where it lies on the shoulders
        under = m.head(theta, zh) if zh >= heads.BOTTOM else m.body(theta, zw)
        return max(r, under + 0.35 * loose)

    # rows, top to bottom, at the head's heights (the opening is cut by these), then the neck and the cowl
    head_rows = [41.0, 39.3, top, top - 0.4 * arch, top - arch]
    for z in (33.0, 31.0, 29.0, 27.6, 26.4):
        if all(abs(z - h) > 0.6 for h in head_rows): head_rows.append(z)
    head_rows = sorted(set(head_rows), reverse=True)
    bottom = m.neck - dz
    rows = []                                                        # (points, open?, follows) per row of the head
    for zh in head_rows + [bottom]:
        zw = zh + dz
        w = _edge_half(zh, half, top, arch, bottom)
        t0 = 0.0
        if w > 0.0:                                                  # the edge of the opening: where the shell is w from the middle
            lo, hi = 0.0, np.radians(100.0)
            for _ in range(40):
                mid = 0.5 * (lo + hi)
                if radius(mid, zh, zw) * np.sin(mid) < w: lo = mid
                else: hi = mid
            t0 = hi
        thetas = [t0 + k * (2.0 * np.pi - 2.0 * t0) / SEGMENTS for k in range(SEGMENTS + (1 if w > 0.0 else 0))]
        rows.append(([np.array([CX, CY, zw]) + radius(t, zh, zw) * _direction(t) for t in thetas], w > 0.0,
                     {"head": 1.0} if zh > bottom else {"head": 0.5, "chest": 0.5}))
    # the top: a dome from the highest row over the crown, or, with a peak, drawn up and back to a point
    apex = m.crown_top + np.array([0.0, loose * (0.35 + 0.3 * peak), loose * (0.45 + 0.25 * peak)])
    sharp = peak / 3.0
    sh = _Shell(); grid = []; opened = []
    crown = sh.add(apex, {"head": 1.0})
    for deg in CAP:
        c = float(np.cos(np.radians(deg))); up = (1.0 - sharp) * float(np.sin(np.radians(deg))) + sharp * (1.0 - c)
        pts = [np.array([apex[0] + c * (r[0] - apex[0]), apex[1] + c * (r[1] - apex[1]), r[2] + up * (apex[2] - r[2])]) for r in rows[0][0]]
        grid.append(sh.ring(pts, {"head": 1.0}, True)); opened.append(False)
    for pts, is_open, follows in rows:
        grid.append(sh.ring(pts, follows, not is_open)); opened.append(is_open)
    for zw, ring in ((m.shoulder, on_shoulder), (m.hem, lambda t: m.lying(t, m.hem, m.shoulder_w + 0.9, 0.5 * loose + 0.4))):
        thetas = [k * 2.0 * np.pi / SEGMENTS for k in range(SEGMENTS)]
        grid.append(sh.ring([np.array([CX, CY, zw]) + ring(t) * _direction(t) for t in thetas], {"chest": 1.0}, True)); opened.append(False)
    sh.faces += [(crown, grid[0][k + 1], grid[0][k]) for k in range(SEGMENTS)]
    for a, b in zip(grid[:-1], grid[1:]): sh.strip(a, b)
    sh.wind_out(np.array([CX, CY, 30.0 + dz]))
    sh.clear(m.corners(m.hem - 1.0))
    # the edges: round the opening, and along the hem
    first = opened.index(True) - 1; last = len(opened) - 1 - opened[::-1].index(True) + 1
    loop = [(grid[i][0], grid[i][1]) for i in range(first, last + 1)]
    loop += [(grid[i][SEGMENTS], grid[i][SEGMENTS - 1]) for i in range(last, first - 1, -1)]
    hem_run = [(grid[-1][k], grid[-2][k]) for k in range(SEGMENTS + 1)]
    return sh.polygons(cloth, inside, [loop, hem_run]), []


def lowered(fit, p, colours, name="hood"):
    """A hood that is down: a cowl closed round the neck, and the empty hood lying on the upper back over it, its
    opening turned up. Returns ([polygon dicts], notes)."""
    m = _Measure(fit)
    loose = LOOSE.get(int(np.clip(int(p["depth"]), 1, 3)), LOOSE[1])
    cloth, inside = _colours(p, colours)
    m.hem = m.shoulder - COWL_DROP[_setting(p, "cowl_length")]
    full = [k * 2.0 * np.pi / SEGMENTS for k in range(SEGMENTS)]
    cowl = _Shell()
    neck = cowl.ring([np.array([CX, CY, m.neck]) + (m.body(t, m.neck) + 0.45 * loose) * _direction(t) for t in full],
                     {"head": 0.3, "chest": 0.7}, True)
    on = cowl.ring([np.array([CX, CY, m.shoulder]) + m.lying(t, m.shoulder, SHOULDER * m.shoulder_w + 0.2, 0.5 * loose) * _direction(t)
                    for t in full], {"chest": 1.0}, True)
    hem = cowl.ring([np.array([CX, CY, m.hem]) + m.lying(t, m.hem, m.shoulder_w + 0.9, 0.5 * loose + 0.4) * _direction(t) for t in full],
                    {"chest": 1.0}, True)
    cowl.strip(neck, on); cowl.strip(on, hem)
    cowl.wind_out(np.array([CX, CY, m.shoulder - 3.0]))
    body = m.corners(m.hem - 8.0, head=False)                        # the chin hangs over the collar: not the head
    cowl.clear(body)
    # the empty hood: a pouch from the back of the neck down the back, fullest at the top, to a soft point. It lies on
    # the back, so it is one layer: nothing sees its inside.
    depth = 5.4 + 0.8 * loose                                        # how far down the back it lies
    spread = np.radians(64.0)
    pouch = _Shell(); grid = []
    for i in range(POUCH_ROWS + 1):
        v = i / POUCH_ROWS; zw = m.neck + 0.3 - v * depth
        w = spread * float(np.sqrt(max(0.0, 1.0 - v ** 1.7))) if i < POUCH_ROWS else 0.0
        pts = []
        for k in range(POUCH_COLUMNS + 1):
            u = -1.0 + 2.0 * k / POUCH_COLUMNS
            t = np.pi + u * w
            full_at = 1.0 - u * u
            r = m.body(t, zw) + 0.3 + (0.5 + 0.7 * loose) * full_at * (1.0 - 0.6 * v) + (0.6 * loose if i == 0 else 0.0) * full_at
            pts.append(np.array([CX, CY, zw]) + r * _direction(t))
        grid.append(pouch.ring(pts, {"chest": 1.0}, False))
    for a, b in zip(grid[:-1], grid[1:]): pouch.strip(a, b)
    pouch.wind_out(np.array([CX, CY, m.shoulder - 3.0]))
    pouch.clear(np.concatenate([body, np.asarray(cowl.V)]))         # lying over the collar, not under it
    polys = cowl.polygons(cloth, inside, [[(neck[k], on[k]) for k in range(SEGMENTS + 1)], [(hem[k], on[k]) for k in range(SEGMENTS + 1)]])
    polys += pouch.polygons(cloth, None, [])
    # the pouch's mouth: across its top, from the outside down to the back it lies on, in the lining colour
    V = np.asarray(pouch.V); zw = m.neck + 0.3
    for k in range(POUCH_COLUMNS):
        rim = []
        for j in (k, k + 1):
            t = np.pi + (-1.0 + 2.0 * j / POUCH_COLUMNS) * spread
            rim.append(np.array([CX, CY, zw - 0.2]) + (m.body(t, zw) + 0.25) * _direction(t))
        pts = np.array([V[grid[0][k]], V[grid[0][k + 1]], rim[1], rim[0]]); n = np.zeros(3)
        for i in range(4): n += np.cross(pts[i], pts[(i + 1) % 4])
        if n[2] < 0: pts = pts[::-1]
        polys.append(dict(pts=pts, rgb=inside, shares=[{"chest": 1.0}] * 4, part="chest"))
    return polys, []


def hood(fit, params, colours, name="hood"):
    """Returns ([polygon dicts], notes)."""
    import specials
    info = fit.body.get("info", {})
    if info.get("head") is None:
        return [], [f"{name}: no head to put it on"]
    p = specials.settings("hood", params)
    return (raised if bool(p["raised"]) else lowered)(fit, p, colours, name)
