"""Special shapes as polygons: straps, skirt, cape. (Facial hair is in facial_hair.py; the hood is in hood.py, and the
shapes of their own (long beard, ponytail, bun, horns, pauldrons) in drawn.py.)

Each takes the game's own settings for it (core/specials/special_item.gd), with the same names, options and defaults;
check.py holds DEFAULTS below equal to the game's table. The game builds them the same way
(core/lowpoly/lowpoly_shapes.gd), checked against this corner by corner. Each is measured from the dressed figure, so it fits any
body and stands clear of whatever is worn under it.

  straps   two bands lying on the chest: up the front from the bottom of the belly, over the top beside the neck,
           straight down the back. They are fixed to the chest and bend with it.
  skirt    hanging cloth (hang.py), fixed at the waist line. Its settings choose its columns: how long each is,
           where the cloth is cut open, how much it flares.
  cape     hanging cloth, fixed along the shoulder line at the back.
"""
import numpy as np
import body as lb
import hang

CX, CY = lb.CX, lb.CY

DEFAULTS = {
    "facial_hair": {"moustache": True, "sideburns": True, "goatee": True, "cheeks": True, "length": "stubble"},
    "straps": {"width": 1},
    "skirt": {"length": "to_knee", "flare": 1, "panels": "four", "slant": 0, "opening": "none", "side": "left",
              "waistband": True, "hem_trim": True},
    "cape": {"length": "to_knee", "width": "shoulders", "flare": 1, "hem_trim": True},
    "hood": {"raised": True, "depth": 1, "opening": 1, "lined": False, "brim": 1, "fullness": 1, "peak": 0, "cowl_length": 1},
    "long_beard": {"length": 3, "width": 3, "point": 2, "jut": 0},
    "ponytail": {"height": 1, "length": 3, "thickness": 2, "tie": True},
    "bun": {"position": "back", "size": 2},
    "horns": {"length": 2, "curve": 1, "spread": 1, "thickness": 2},
    "pauldrons": {"size": 2, "drop": 1},
}
BUN_POSITIONS = ("top", "back", "nape")
SKIRT_LENGTH = {"to_knee": "knee", "to_shin": "shin", "to_ankle": "ankle"}       # the band whose floor the hem reaches
CAPE_LENGTH = {"to_waist": "waist", "to_knee": "knee", "to_ankle": "ankle"}
CAPE_WIDTH = {"narrow": -1.0, "shoulders": 0.0, "wide": 1.0}
MAX_SLANT = 6; MIN_ROWS = 2              # however steep the slant, the high side keeps this much cloth below the hips
OPEN_AT_HEM = 2.0                        # a front opening: how far each flap's edge stands from the middle at the hem
WRAP_PAST_MIDDLE = 1.0                   # a wrap: how far past the middle its cut edge ends, at the hem
STRAP_PROUD = 0.12                       # how far a strap stands off what it lies on: a flat band, no thickness
STRAP_STRAIGHT = 0.12                    # a strap takes no extra points where it runs this straight
STRAP_AT_WAIST = 0.6                     # where a strap meets the waist, as a share of the waist's half width

LEG_BANDS = ("upper_thigh", "lower_thigh", "knee", "shin", "ankle", "foot")
TORSO_BANDS = ("upper_chest", "lower_chest", "belly", "waist", "hips")


def settings(kind, params):
    out = dict(DEFAULTS[kind])
    out.update({k: v for k, v in (params or {}).items() if k in out})
    return out


def coverage(kind, params):
    """Regions a special shape covers as an ordinary garment would: {region key: (role, bulk)}."""
    if kind == "skirt" and settings(kind, params)["waistband"]:
        return {f"waist.{s}.{f}": ("cloth", 1) for s in "LR" for f in "FB"}     # a one-row band, in the cloth colour
    return {}


def outward(ring):
    """Level directions pointing out of a closed ring of points, one per point."""
    n = len(ring); c = np.mean(ring, axis=0); out = []
    for i in range(n):
        t = ring[(i + 1) % n] - ring[i - 1]
        d = np.array([t[1], -t[0], 0.0])
        if d @ (ring[i] - c) < 0: d = -d
        out.append(hang.unit(d))
    return out


def _mix(a, b, f):
    out = {}
    for part, w in a.items(): out[part] = out.get(part, 0.0) + (1.0 - f) * w
    for part, w in b.items(): out[part] = out.get(part, 0.0) + f * w
    return {k: v for k, v in out.items() if v > 1e-9}


# ------------------------------------------------------------------------------------------------------ skirt ---

def _skirt_over(q):
    return (q["piece"] == "skin" and q["band"] in ("hips",) + LEG_BANDS) or q["piece"].startswith("foot")


def skirt(fit, params, colours, name="skirt"):
    """Returns (hang.Cloth or None, notes)."""
    p = settings("skirt", params); notes = []
    z_top = fit.band("hips")[1]                                      # the waist line: the cloth is fixed along it
    z_hip = fit.band("hips")[0]                                      # below here an opening is open
    ring = fit.ring(z_top); n = len(ring)
    xs = [v[0] - CX for v in ring]
    if n != 8 or abs(xs[0]) > 1e-6 or abs(xs[4]) > 1e-6 or int(np.argmax(xs)) != 2 or int(np.argmin(xs)) != 6:
        return None, [f"{name}: the waist is not the ring of eight points this expects"]
    F, AL, SL, BL, R, BR, SR, AR = range(8)                          # front, round by the figure's left, to the back and on
    W = [fit.at(v) for v in ring]; shares = [fit.shares(v) for v in ring]; d = outward(W)
    hem_z = fit.band(SKIRT_LENGTH.get(str(p["length"]), "knee"))[0]
    # flare: the hem is that much wider than the hips, all round, widening evenly below them
    flare = float(np.arctan2(float(np.clip(int(p["flare"]), 0, 3)), z_hip - hem_z))
    four = str(p["panels"]) == "four"
    opening = str(p["opening"])
    if opening not in ("none", "wrap", "front"):
        notes.append(f"{name}: unknown opening '{opening}'"); opening = "none"
    left = str(p["side"]) != "right"                                 # the side the hem rises toward and a wrap opens on
    slant = float(np.clip(int(p["slant"]), 0, min(MAX_SLANT, max(0.0, z_hip - hem_z - MIN_ROWS))))
    trim = bool(p["hem_trim"])
    P, Z0 = fit.points(_skirt_over)
    rest = fit.rest()
    levels = [z for z in fit.heights(("hips",)) if z_hip < z < z_top - 1e-6]      # the hip rings the cloth lies on

    def base(k, hem=hem_z):
        return hang.Column(W[k], shares[k], d[k], [d[k][1], -d[k][0], 0.0], hem, trim, flare, levels=levels)

    # Where each of the eight columns hangs at the hem: that is the width the slant runs across, and what an opening
    # is measured along.
    first = hang.Cloth(name, [base(k) for k in range(n)], [(list(range(n)), True)], colours, "pelvis", _skirt_over)
    hang.settle(first, rest, P, Z0)
    at_hem = hang.ends(first, rest, P, Z0)
    xh = [float(q[0] - CX) for q in at_hem]
    lo, hi = min(xh), max(xh)

    def hem_at(x):
        t = float(np.clip((x - lo) / max(hi - lo, 1e-9), 0.0, 1.0))
        return hem_z + (t if left else 1.0 - t) * slant

    cols = []

    def add(a, b=None, f=0.0, hem=None, trim_on=None, spread=None, side=None):
        """A column at ring point a, or part of the way from a to b. Returns its number."""
        b = a if b is None else b
        top = W[a] + f * (W[b] - W[a]); out = hang.unit(d[a] + f * (d[b] - d[a])); x = xh[a] + f * (xh[b] - xh[a])
        cols.append(hang.Column(top, _mix(shares[a], shares[b], f), out, side if side is not None else [out[1], -out[0], 0.0],
                                hem_at(x) if hem is None else hem, trim if trim_on is None else trim_on, flare, spread, levels=levels))
        return len(cols) - 1

    near = (lambda k: k) if left else (lambda k: (n - k) % n)        # ring points named from the open (or high) side
    sign = 1.0 if left else -1.0
    u = lambda k: sign * xh[near(k)]                                 # how far toward that side a column hangs

    def open_front(edge_a, edge_b, edge_f):
        """A wrap's front on its open side, from the middle out to its edge (ring point edge_a, or part of the way
        from edge_a to edge_b). The cloth is cut on a line from that edge at the hips to just past the middle at the
        level hem. Returns the columns, from the middle outward."""
        u_front = u(1); u_edge = u(edge_a) + edge_f * (u(edge_b) - u(edge_a))
        slope = (z_hip - hem_z) / max(u_edge - WRAP_PAST_MIDDLE, 1e-6)
        cut = lambda uu: hem_z + (uu - WRAP_PAST_MIDDLE) * slope      # the height of the cut edge, that far out
        hem_u = lambda uu: hem_at(sign * uu)
        u_meet = WRAP_PAST_MIDDLE                                     # where the cut meets the hem
        for _ in range(60):
            u_meet = WRAP_PAST_MIDDLE + (hem_u(u_meet) - hem_z) / slope
        made = []
        if u_meet < u_front - 0.3:                                    # the cut meets the hem before the front corner
            made.append(add(F, near(1), u_meet / u_front, hem=hem_u(u_meet)))
            made.append(add(near(1), hem=cut(u_front), trim_on=False))
        elif u_meet > u_front + 0.3 and u_meet < u_edge - 0.3:        # or beyond it
            made.append(add(near(1)))
            made.append(add(near(1), near(2), (u_meet - u_front) / (u(2) - u_front), hem=hem_u(u_meet)))
        else:
            made.append(add(near(1), hem=max(hem_u(u_front), cut(u_front))))
        made.append(add(near(edge_a), near(edge_b), edge_f, hem=z_hip, trim_on=False))      # the edge itself: cloth to the hips only
        return made

    half = 0.5
    back_two = lambda: [add(SL, BL, half), add(BL), add(R), add(BR), add(BR, SR, half)]
    if opening == "none":
        if four:
            sheets = [([add(k) for k in range(n)], True)]
        else:                                                        # front and back cloths, the sides open
            sheets = [([add(SR, AR, half), add(AR), add(F), add(AL), add(AL, SL, half)], False), (back_two(), False)]
    elif opening == "wrap":
        if four:
            run = [add(near(SL)), add(near(BL)), add(R), add(near(BR)), add(near(SR)), add(near(AR)), add(F)] + open_front(2, 2, 0.0)
            sheets = [(run, False)]
        else:
            run = [add(near(SR), near(AR), half), add(near(AR)), add(F)] + open_front(1, 2, half)
            sheets = [(run, False), (back_two(), False)]
    else:                                                            # open down the front: two flaps
        flap = lambda s: add(F, hem=hem_at(s * OPEN_AT_HEM), spread=(z_hip, OPEN_AT_HEM), side=[s, 0.0, 0.0])
        if four:
            sheets = [([flap(1.0), add(AL), add(SL), add(BL), add(R), add(BR), add(SR), add(AR), flap(-1.0)], False)]
        else:
            sheets = [([flap(1.0), add(AL), add(AL, SL, half)], False), ([add(SR, AR, half), add(AR), flap(-1.0)], False), (back_two(), False)]
    cloth = hang.Cloth(name, cols, sheets, colours, "pelvis", _skirt_over)
    hang.settle(cloth, rest, P, Z0)
    return cloth, notes


# ------------------------------------------------------------------------------------------------------- cape ---

def _cape_over(q):
    # The torso, the legs, and any cloth already hanging (a skirt). Not the arms: a raised arm would carry the cape's
    # edge up with it (tried: the cape turns into a funnel), so an arm swung far back goes through the edge instead.
    return (q["piece"] == "skin" and q["band"] in TORSO_BANDS + LEG_BANDS) or q["piece"].startswith(("foot", "cloth"))


def cape(fit, params, colours, name="cape"):
    """Returns (hang.Cloth or None, notes)."""
    p = settings("cape", params); notes = []
    z_top = fit.band("collar")[0]                                    # the shoulder line, under the collar
    hem_z = fit.band(CAPE_LENGTH.get(str(p["length"]), "knee"))[0]
    if hem_z >= z_top:
        return None, [f"{name}: its hem is not below its shoulders"]
    ring = fit.ring(z_top); xs = [v[0] - CX for v in ring]
    if len(ring) != 8 or int(np.argmax(xs)) != 2 or int(np.argmin(xs)) != 6:
        return None, [f"{name}: the shoulder line is not the ring of eight points this expects"]
    W = [fit.at(v) for v in ring]; shares = [fit.shares(v) for v in ring]
    tops = [W[k].copy() for k in (2, 3, 4, 5, 6)]; sh = [shares[k] for k in (2, 3, 4, 5, 6)]      # shoulder, round the back, shoulder
    extra = CAPE_WIDTH.get(str(p["width"]), 0.0)
    for e, inner in ((0, 1), (4, 3)):                                # narrower or wider than the shoulders, by a unit
        s = np.sign(tops[e][0] - CX)
        if extra > 0:
            tops[e] = tops[e] + np.array([s * extra, 0.0, 0.0])
        elif extra < 0:
            f = min(0.9, -extra / max(abs(tops[e][0] - tops[inner][0]), 1e-6))
            tops[e] = tops[e] + f * (tops[inner] - tops[e]); sh[e] = _mix(sh[e], sh[inner], f)
    flare = float(np.clip(int(p["flare"]), 0, 3))
    half = max(abs(t[0] - CX) for t in tops)
    cols = []
    for i, top in enumerate(tops):
        ux = (top[0] - CX) / half                                    # the hem is wider than the shoulders by the flare
        cols.append(hang.Column(top, sh[i], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0], hem_z, bool(p["hem_trim"]), 0.0, (z_top, flare * ux)))
    cloth = hang.Cloth(name, cols, [(list(range(len(cols))), False)], colours, "chest", _cape_over, facing=[0.0, 1.0, 0.0])
    P, Z0 = fit.points(_cape_over)
    hang.settle(cloth, fit.rest(), P, Z0)
    return cloth, notes


# ----------------------------------------------------------------------------------------------------- straps ---

def _cross(loop, x, back):
    """Where a closed ring of points crosses the upright plane at x: at the front, or at the back."""
    best = None; n = len(loop)
    for i in range(n):
        a, b = loop[i], loop[(i + 1) % n]
        if (a[0] - x) * (b[0] - x) > 0 or abs(a[0] - b[0]) < 1e-9: continue
        p = a + (x - a[0]) / (b[0] - a[0]) * (b - a)
        if best is None or (p[1] > best[1] if back else p[1] < best[1]): best = p
    return best


def _above(points, direction, tris):
    """For each point: how far along `direction` the surface (triangles) still is. 0 where it is not in the way."""
    out = np.zeros(len(points))
    if len(tris) == 0: return out
    a = tris[:, 0]; e1 = tris[:, 1] - a; e2 = tris[:, 2] - a
    h = np.cross(direction, e2); det = np.einsum("ij,ij->i", e1, h)
    ok = np.abs(det) > 1e-12; inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    for i, p in enumerate(points):
        s = p - a; u = np.einsum("ij,ij->i", s, h) * inv
        q = np.cross(s, e1); v = (q @ direction) * inv
        far = np.einsum("ij,ij->i", e2, q) * inv
        hit = ok & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1.0 + 1e-9) & (far > 1e-6) & (far < 3.0)
        if hit.any(): out[i] = far[hit].max()
    return out


def straps(fit, params, colours, name="straps"):
    """Returns ([polygon dicts: pts, rgb, shares], notes)."""
    p = settings("straps", params)
    width = float(np.clip(int(p["width"]), 1, 2)); half = 0.5 * width
    z0 = fit.band("belly")[0]; z1, z2 = fit.band("collar")
    zs = [z for z in fit.heights(("belly", "lower_chest", "upper_chest")) if z0 - 1e-6 <= z <= z1 + 1e-6]      # up the chest
    bare = {z: fit.ring(z) for z in zs + [z2]}
    worn = {z: [fit.at(v) for v in bare[z]] for z in bare}
    edge = max(v[0] for v in bare[z1]) - CX; beside_neck = max(v[0] for v in bare[z2]) - CX
    if edge < beside_neck + 1.0:
        return [], [f"{name}: the chest has no room beside the neck for a strap"]
    # Over the shoulder a strap sits halfway between the neck and the edge of the chest's top row (the voxel rule);
    # a second unit of width goes outward if the top row reaches that far, otherwise in toward the neck. From there it
    # runs straight to the front of the waist, as a real strap does: on these bodies a plumb line from the shoulder
    # would end on the flank.
    at_top = 0.5 * (beside_neck + edge)
    if width >= 2: at_top += 0.5 if at_top + 1.5 <= edge + 0.25 else -0.5
    at_waist = min(at_top, STRAP_AT_WAIST * (max(v[0] for v in bare[z0]) - CX) + (0.5 if width >= 2 else 0.0))
    where = lambda z: at_waist + (at_top - at_waist) * (z - z0) / (z1 - z0)
    tris = fit.triangles(lambda q: q["piece"] == "skin" and q["band"] in ("waist", "belly", "lower_chest", "upper_chest", "collar", "neck"))
    bottom_share = fit.shares(bare[zs[0]][0])                        # the belly's bottom row bends a little with the waist
    inside = np.array([CX, CY + 0.2, 0.5 * (z0 + z1)])
    polys = []
    for sign in (1.0, -1.0):
        stations = []                                                # (inner edge, fold, outer edge): up the front, over, down the back
        for back in (False, True):
            run = []
            for z in zs:
                loop = worn[z]
                room = max(sign * (q[0] - CX) for q in loop)
                c = min(where(z), room - half - 0.2)                 # a waist too narrow for it: move in
                lo, hi = CX + sign * (c - half), CX + sign * (c + half)
                inner, outer = _cross(loop, lo, back), _cross(loop, hi, back)
                if inner is None or outer is None: return [], [f"{name}: the chest is too narrow for them"]
                # a corner of the ring under the strap: the strap folds over it
                front_y = 0.5 * (inner[1] + outer[1])
                under = [q for q in loop if min(lo, hi) + 0.08 < q[0] < max(lo, hi) - 0.08 and abs(q[1] - front_y) < 2.5 and ((q[1] > CY + 0.3) == back)]
                fold = min(under, key=lambda q: abs(q[0] - CX - sign * c)) if under else None
                run.append((inner, fold if fold is not None else _cross(loop, CX + sign * c, back), outer, fold is not None))
            if not back:
                stations += run
                a = max(worn[z1], key=lambda q: sign * (q[0] - CX)); b = max(worn[z2], key=lambda q: sign * (q[0] - CX))
                up = b - a                                           # the slope from the shoulder up to the neck
                if abs(up[0]) < 1e-6: return [], [f"{name}: no shoulder slope to cross"]
                on = lambda x: a + float(np.clip((x - a[0]) / up[0], 0.0, 1.0)) * up
                stations.append((on(CX + sign * (at_top - half)), on(CX + sign * at_top), on(CX + sign * (at_top + half)), False))
                top_at = len(stations) - 1
            else:
                stations += run[::-1]
        count = len(stations)
        keep = [0]                                                   # drop the stations where the strap runs straight
        for i in range(1, count - 1):
            bend = 0.0
            for e in range(3):
                a, q, b = stations[keep[-1]][e], stations[i][e], stations[i + 1][e]
                ab = b - a; bend = max(bend, np.linalg.norm(np.cross(ab, q - a)) / max(np.linalg.norm(ab), 1e-9))
            if bend > STRAP_STRAIGHT or i == top_at or stations[i][3] != stations[keep[-1]][3]: keep.append(i)
        keep.append(count - 1)
        ups = []
        for j, i in enumerate(keep):
            along = stations[keep[min(j + 1, len(keep) - 1)]][1] - stations[keep[max(j - 1, 0)]][1]
            up = np.cross(along, stations[i][2] - stations[i][0])
            if up @ (stations[i][1] - inside) < 0: up = -up
            ups.append(hang.unit(up))                                # square to the strap, away from the chest
        # how far the strap must stand off so that nothing under it comes through: look, across every stretch of it,
        # for how far the dressed chest rises above the flat faces between its points
        need = np.zeros(len(keep))
        for j in range(len(keep) - 1):
            A, B = stations[keep[j]], stations[keep[j + 1]]
            grid = [(1 - v) * ((1 - u) * A[e] + u * A[e + 1]) + v * ((1 - u) * B[e] + u * B[e + 1])
                    for e in (0, 1) for u in (0.0, 0.25, 0.5, 0.75, 1.0) for v in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)]
            rise = _above(np.array(grid), hang.unit(ups[j] + ups[j + 1]), tris).max()
            need[j] = max(need[j], rise); need[j + 1] = max(need[j + 1], rise)
        rows = [tuple(stations[i][e] + ups[j] * (STRAP_PROUD + need[j]) for e in range(3)) for j, i in enumerate(keep)]
        follow = [bottom_share if i in (0, count - 1) else {"chest": 1.0} for i in keep]

        def put(pts, sh, facing):
            pts = np.array(pts); n = np.zeros(3)
            for i in range(len(pts)):
                n += np.cross(pts[i], pts[(i + 1) % len(pts)])
            if n @ facing < 0: pts = pts[::-1].copy(); sh = sh[::-1]
            polys.append(dict(pts=pts, rgb=colours["strap"], shares=sh))

        for j in range(len(rows) - 1):
            sh = [follow[j], follow[j], follow[j + 1], follow[j + 1]]; facing = ups[j] + ups[j + 1]
            if stations[keep[j]][3] or stations[keep[j + 1]][3]:     # folded over a corner here: two faces
                for e in (0, 1):
                    put([rows[j][e], rows[j][e + 1], rows[j + 1][e + 1], rows[j + 1][e]], list(sh), facing)
            else:
                put([rows[j][0], rows[j][2], rows[j + 1][2], rows[j + 1][0]], list(sh), facing)
    return polys, []


def hood(fit, params, colours, name="hood"):
    import hood as hd
    return hd.hood(fit, params, colours, name)


def _shape_type(kind):
    def build(fit, params, colours, name=kind):
        import drawn
        return drawn.build(fit, kind, params, colours, name)
    return build


BUILT = {"skirt": skirt, "cape": cape, "straps": straps, "hood": hood}
BUILT.update({kind: _shape_type(kind) for kind in ("long_beard", "ponytail", "bun", "horns", "pauldrons")})
HANGS = ("skirt", "cape")                # placed after everything else that is worn, in draw order among themselves
