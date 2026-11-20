"""Cutting a clay body into rings of points: the machinery every low-poly body here is made with.

Rings of a few points each are placed on the clay's surface at chosen heights and joined into four-sided polygons.
Ring points sit where the outline is widest, deepest or furthest forward, so the front and side outlines of the
clay are kept at every ring.

The torso, neck and both legs are one continuous skin (the legs branch from the hip ring). Each arm, each foot and
the head are their own closed pieces that overlap it.

This file also holds the first two cuts (LIGHT / FULL: bodies "A" and "B" of the first sheets), made for shape
alone, which the look was approved from. The bodies the clothing system uses are built in body.py, with their edges on the clothing regions.

Units are the clay's (24 to the metre). x across (mirror plane x = 12), y depth (front is -y), z up.
"""
import numpy as np
import clay

CX, CY = 12.0, 12.0
M = clay.FEM_AVERAGE
FRONT = np.array([0.0, -1.0, 0.0]); OUT = np.array([1.0, 0.0, 0.0]); UP = np.array([0.0, 0.0, 1.0])


# ---------------------------------------------------------------------------------------- the clay, by part ---

def _q(p):
    q = np.empty_like(p); q[:, 0] = np.abs(p[:, 0] - CX); q[:, 1] = p[:, 1] - CY; q[:, 2] = p[:, 2]
    return q


def _E(q, name):
    c, r = M[name]
    return clay.ellipsoid(q, np.array(c, float), np.array(r, float))


def sdf_torso(p):
    """Torso and neck."""
    a, b, ra, rb = M["neck"]
    return clay.smin(clay.body(p, M, parts="torso"), clay.cone(_q(p), a, b, ra, rb), 1.6)


def sdf_leg(p):
    q = _q(p)
    return clay.smin(_E(q, "thigh"), _E(q, "calf"), 1.3)


def sdf_skin(p):
    """Torso, neck and legs flowing into each other, as in the clay."""
    return clay.smin(sdf_torso(p), sdf_leg(p), 1.8)


def sdf_arm(p):
    q = _q(p); c, r = M["deltoid"]
    arm = clay.smin(clay.smin(_E(q, "upper_arm"), _E(q, "forearm"), 1.2), _E(q, "hand"), 0.9)
    return clay.smin(np.linalg.norm(q - np.array(c, float), axis=1) - r, arm, 1.0)


def sdf_foot(p):
    q = _q(p)
    return np.maximum(clay.smin(_E(q, "foot"), _E(q, "heel"), 1.0), -p[:, 2])


def sdf_head(p):
    c, half, r = M["head"]
    return clay.round_box(_q(p), np.array(c, float), half, r)


# ------------------------------------------------------------------------------------------ cutting a slice ---

def outline(sdf, origin, u=FRONT, v=OUT, n=360, rmax=12.0, step=0.03, half=False):
    """The outline of the clay in the plane through origin spanned by u and v: n points, in order of angle
    (angle 0 looks along u, 90 along v). origin must be inside. half: stop at the mirror plane."""
    ang = np.arange(n) * (2.0 * np.pi / n)
    dirs = np.cos(ang)[:, None] * u + np.sin(ang)[:, None] * v
    ts = np.arange(0.0, rmax, step)
    P = origin[None, None, :] + ts[None, :, None] * dirs[:, None, :]
    d = sdf(P.reshape(-1, 3)).reshape(n, ts.size)
    if half:
        d = np.maximum(d, CX - P[:, :, 0])
    out = d > 0
    first = np.where(out.any(axis=1), out.argmax(axis=1), ts.size - 1)
    i1 = np.clip(first, 1, ts.size - 1); ar = np.arange(n)
    d0 = d[ar, i1 - 1]; d1 = d[ar, i1]
    t = ts[i1 - 1] + step * np.clip(-d0 / np.maximum(d1 - d0, 1e-9), 0.0, 1.0)
    t = np.where(first == 0, 0.0, t)
    return origin[None, :] + t[:, None] * dirs


def support(pts, deg, u=FRONT, v=OUT):
    """The outline point that sticks out furthest in the direction deg."""
    a = np.radians(deg); d = np.cos(a) * u + np.sin(a) * v
    return pts[np.argmax(pts @ d)].copy()


def snap(ring, pts, axes=(0, 1)):
    """Move the ring's extreme points onto the clay's true extremes, so the outline is not shrunk."""
    ring = np.array(ring, float)
    for ax in axes:
        for fn, arg in ((np.min, np.argmin), (np.max, np.argmax)):
            ring[arg(ring[:, ax]), ax] = fn(pts[:, ax])
    return ring


def inside_centre(sdf, guess, z, reach=1.2):
    """A point inside the slice at height z near guess (x, y), or None if the slice is empty there."""
    g = np.linspace(-reach, reach, 13)
    X, Y = np.meshgrid(guess[0] + g, guess[1] + g)
    P = np.stack([X.ravel(), Y.ravel(), np.full(X.size, z)], axis=1)
    d = sdf(P)
    i = int(np.argmin(d))
    return None if d[i] >= -1e-3 else P[i]


# ------------------------------------------------------------------------------------------- building faces ---

class Faces:
    def __init__(self):
        self.polys = []

    def add(self, pts):
        pts = [np.asarray(p, float) for p in pts]
        keep = []
        for p in pts:
            if not keep or np.linalg.norm(p - keep[-1]) > 1e-6:
                keep.append(p)
        if len(keep) > 1 and np.linalg.norm(keep[0] - keep[-1]) <= 1e-6:
            keep.pop()
        if len(keep) >= 3:
            self.polys.append(np.array(keep))

    def loft(self, rings, skip=None):
        for a, b in zip(rings[:-1], rings[1:]):
            n = len(a)
            for k in range(n):
                quad = [a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]]
                if skip is not None and skip(quad): continue
                self.add(quad)

    def cap(self, ring):
        self.add(list(ring))

    def fan(self, ring, apex):
        n = len(ring)
        for k in range(n):
            self.add([ring[k], ring[(k + 1) % n], apex])

    def mirrored(self):
        out = Faces()
        for p in self.polys:
            m = p[::-1].copy(); m[:, 0] = 2.0 * CX - m[:, 0]
            out.polys.append(m)
        return out


def normal(poly):
    n = np.zeros(3)
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        n += np.cross(a, b)
    ln = np.linalg.norm(n)
    return n / ln if ln > 1e-12 else np.array([0.0, 0.0, 1.0])


def oriented(polys, sdf):
    """Wind every polygon so its normal points out of the clay."""
    out = []
    for p in polys:
        n = normal(p); c = p.mean(axis=0)
        d = sdf(np.array([c + 0.25 * n, c - 0.25 * n]))
        out.append(p if d[0] >= d[1] else p[::-1].copy())
    return out


# ------------------------------------------------------------------------------------------------ the pieces ---

def _mirror_ring(half):
    """half = points from front centre round the +x side to back centre; returns the full ring."""
    rest = [np.array([2.0 * CX - p[0], p[1], p[2]]) for p in half[-2:0:-1]]
    return np.array(list(half) + rest)


SHOULDER_CUT = 4.9      # the torso stops here at shoulder height; the arm's shoulder covers the rest


def use(model):
    """Cut from another clay body (same form as clay.FEM_AVERAGE)."""
    global M, SHOULDER_CUT
    M = model
    SHOULDER_CUT = model["deltoid"][0][0] - 0.95


def sdf_torso_cut(p):
    """The skin with the pointed end of the shoulder girdle cut off square, where the arm piece takes over."""
    d = sdf_skin(p)
    return np.where(p[:, 2] > 19.5, np.maximum(d, np.abs(p[:, 0] - CX) - SHOULDER_CUT), d)


def torso_ring(z, cols, yc=0.25):
    o = np.array([CX, CY + yc, z])
    if sdf_skin(o[None, :])[0] >= 0:
        o = inside_centre(sdf_skin, (CX, CY + yc), z, 2.0)
    pts = outline(sdf_torso_cut, o)
    side = pts[pts[:, 0] >= CX - 1e-6]
    half = [pts[0].copy()]                                        # front centre: straight ahead of the axis
    half += [support(side, a) for a in cols]
    half.append(pts[len(pts) // 2])                               # back centre
    half = snap(half, side, axes=(1,))
    half[0][0] = CX; half[-1][0] = CX
    return half


def crotch():
    """Lowest point of the body on the mirror plane: (y, z)."""
    ys = np.linspace(CY - 3.0, CY + 4.0, 71); zs = np.arange(7.0, 12.5, 0.02)
    Y, Z = np.meshgrid(ys, zs, indexing="ij")
    d = sdf_skin(np.stack([np.full(Y.size, CX), Y.ravel(), Z.ravel()], axis=1)).reshape(Y.shape)
    low = np.where((d < 0).any(axis=1), zs[(d < 0).argmax(axis=1)], np.inf)
    i = int(np.argmin(low))
    return float(ys[i]), float(low[i])


def hip_half_ring(z, cols, c_point=None):
    """Above the crotch: one side's half of the outline, closed along the mirror plane."""
    o = inside_centre(lambda p: np.maximum(sdf_skin(p), CX + 0.6 - p[:, 0]), (CX + 2.6, CY + 0.4), z, 2.0)
    pts = outline(sdf_skin, o, half=True)
    on_plane = pts[pts[:, 0] < CX + 0.03]
    f = np.array([CX, on_plane[:, 1].min(), z]); r = np.array([CX, on_plane[:, 1].max(), z])
    skin = pts[pts[:, 0] >= CX + 0.03]
    ring = [f] + [support(skin, a) for a in cols] + [r]
    ring = snap(ring, pts, axes=(1,))
    ring[0][0] = CX; ring[-1][0] = CX
    c = np.array([CX, 0.5 * (f[1] + r[1]), z]) if c_point is None else np.array(c_point, float)
    return np.array(list(ring) + [c])


def leg_ring(z, cols):
    """Below the crotch: a free ring round one leg. cols are directions (0 = front, 90 = outer side)."""
    q = M["thigh"][0] if z > 6.4 else M["calf"][0]
    o = inside_centre(sdf_leg, (CX + q[0], CY + q[1]), z, 1.5)
    pts = outline(sdf_skin, o, half=True)
    return snap([support(pts, a) for a in cols], pts)


def build_skin(spec):
    f = Faces()
    tc = spec["torso_cols"]
    rings = [torso_ring(z, tc, yc) for z, yc in spec["torso_z"]]
    full = [_mirror_ring(h) for h in rings]
    f.loft(full)
    f.cap(full[0][::-1])                                           # top of the neck (hidden inside the head)
    # legs: the lowest torso ring is the hip ring; each side of it is the top of a leg
    yc, zc = crotch()
    side = Faces()
    hip = np.array(list(rings[-1]) + [np.array([CX, 0.5 * (rings[-1][0][1] + rings[-1][-1][1]), spec["torso_z"][-1][0]])])
    leg = [hip]
    for z in spec["hip_z"]:
        leg.append(hip_half_ring(z, tc))
    leg.append(hip_half_ring(zc + spec["crotch_lift"], tc, c_point=(CX, yc, zc)))
    lc = spec["leg_cols"]
    for z in spec["leg_z"]:
        leg.append(leg_ring(z, lc))
    on_plane = lambda quad: all(abs(p[0] - CX) < 1e-6 for p in quad)
    side.loft(leg, skip=on_plane)
    side.cap(leg[-1])                                              # ankle (hidden inside the foot)
    polys = oriented(f.polys + side.polys + side.mirrored().polys, sdf_skin)
    return polys, dict(crotch=(yc, zc))


def build_arm(spec):
    f = Faces()
    keys = ("hand", "forearm", "upper_arm", "deltoid")
    kz = [M[k][0][2] for k in keys]
    cen = lambda z: (CX + np.interp(z, kz, [M[k][0][0] for k in keys]), CY + np.interp(z, kz, [M[k][0][1] for k in keys]))
    top = M["deltoid"][0][2] + M["deltoid"][1]; dz = M["deltoid"][0][2]
    hz = M["hand"][0][2]; hb = hz - M["hand"][1][2]
    stations = dict(light=[top - 0.22, dz + 0.4, 17.4, 15.0, 12.7, hz + 0.1, hb + 0.35],
                    full=[top - 0.2, top - 0.9, dz - 0.4, 19.8, 17.4, 15.2, 12.8, hz + 0.8, hz - 0.4, hb + 0.3])[spec["name"]]
    rings = []
    for z in stations:
        o = inside_centre(sdf_arm, cen(z), z, 1.0)
        pts = outline(sdf_arm, o, rmax=5.0)
        rings.append(snap([support(pts, a) for a in spec["arm_cols"]], pts))
    f.loft(rings)
    f.cap(rings[0][::-1]); f.cap(rings[-1])                        # blunt ends: a small flat polygon, not a point
    return oriented(f.polys + f.mirrored().polys, sdf_arm)


def build_foot(spec):
    f = Faces()
    rings = []
    fx = M["foot"][0][0]
    y0 = M["foot"][0][1] - M["foot"][1][1]; y1 = M["heel"][0][1] + M["heel"][1][1]      # toe tip, back of the heel
    for t in spec["foot_y"]:
        y = y0 + (t + 4.5) / 6.75 * (y1 - y0)                      # the stations were laid out on a foot from -4.5 to 2.25
        o = np.array([CX + fx, CY + y, 0.5])
        if sdf_foot(o[None, :])[0] >= 0:
            g = np.linspace(-1.2, 1.2, 25)
            P = np.stack([CX + fx + g, np.full(g.size, CY + y), np.full(g.size, 0.3)], axis=1)
            o = P[int(np.argmin(sdf_foot(P)))]
        pts = outline(sdf_foot, o, u=UP, v=OUT, rmax=5.0)
        ring = [support(pts, a, UP, OUT) for a in spec["foot_cols"]]
        rings.append(snap(ring, pts, axes=(0, 2)))
    f.loft(rings); f.cap(rings[0][::-1]); f.cap(rings[-1])
    return oriented(f.polys + f.mirrored().polys, sdf_foot)


def build_head(spec):
    c, half, r = M["head"]
    r = r * spec["head_round"]                                     # fewer points round a corner cut inside it, so cut less
    c = np.array([CX + c[0], CY + c[1], c[2]]); hx, hy, hz = half
    f = Faces(); rings = []
    arcs = spec["head_arc"]                                        # angles round each rounded corner / edge
    for sign in (1, -1):
        for a in (arcs[::-1] if sign > 0 else arcs):
            a = np.radians(a); rho = r * np.cos(a)
            z = c[2] + sign * ((hz - r) + r * np.sin(a))
            ring = []
            # walk round the head one way only: front-right corner (front side first), back-right, back-left, front-left
            for sx, sy, order in ((1, -1, -1), (1, 1, 1), (-1, 1, -1), (-1, -1, 1)):
                corner = []
                for b in arcs:
                    b = np.radians(b)
                    corner.append(np.array([c[0] + sx * ((hx - r) + rho * np.cos(b)), c[1] + sy * ((hy - r) + rho * np.sin(b)), z]))
                ring += corner if order > 0 else corner[::-1]
            rings.append(np.array(ring))
    f.loft(rings); f.cap(rings[0][::-1]); f.cap(rings[-1])
    return oriented(f.polys, sdf_head)


# ----------------------------------------------------------------------------------------------- the two sizes ---

LIGHT = dict(
    name="light",
    torso_cols=[20, 90, 155],
    torso_z=[(26.5, 0.35), (24.9, 0.5), (23.7, 0.5), (22.6, 0.4), (21.2, 0.3), (19.6, 0.25), (17.7, 0.2), (15.4, 0.0), (12.6, 0.3)],
    hip_z=[11.2], crotch_lift=0.7,
    leg_cols=[315, 20, 90, 160, 225, 270],
    leg_z=[8.3, 6.4, 2.2],
    arm_cols=[30, 90, 150, 210, 270, 330],
    arm_z=[23.78, 22.7, 17.4, 15.0, 12.7, 10.8, 9.25],
    foot_cols=[325, 35, 90, 135, 225, 270],
    foot_y=[-4.2, -2.8, -0.9, 1.0, 2.05],
    head_arc=[22.5, 67.5], head_round=1.0,
)

# The masculine first cut: the same rings and columns, with the torso rings moved to its own landmarks.
LIGHT_MASC = dict(LIGHT, torso_z=[(26.5, 0.35), (25.1, 0.5), (23.9, 0.6), (22.75, 0.45), (21.6, 0.3), (20.4, 0.3), (18.4, 0.25),
                                  (15.4, 0.05), (12.6, 0.3)])

FULL = dict(
    name="full",
    torso_cols=[15, 50, 90, 130, 160],
    torso_z=[(26.5, 0.35), (25.2, 0.5), (24.4, 0.55), (23.5, 0.5), (22.6, 0.4), (21.6, 0.3), (20.6, 0.25), (19.6, 0.25), (18.6, 0.25),
             (17.6, 0.2), (16.4, 0.1), (15.2, 0.0), (13.9, 0.15), (12.7, 0.3)],
    hip_z=[11.7, 10.7], crotch_lift=0.6,
    leg_cols=[315, 5, 50, 90, 130, 175, 225, 270],
    leg_z=[8.6, 7.5, 6.4, 5.4, 4.3, 3.2, 2.2],
    arm_cols=[0, 45, 90, 135, 180, 225, 270, 315],
    arm_z=[23.8, 23.1, 21.9, 19.8, 17.4, 15.2, 12.8, 11.5, 10.3, 9.2],
    foot_cols=[0, 45, 90, 135, 225, 270, 315],
    foot_y=[-4.3, -3.6, -2.4, -1.0, 0.4, 1.5, 2.1],
    head_arc=[15, 45, 75], head_round=1.0,
)


def build(spec):
    skin, info = build_skin(spec)
    parts = dict(skin=skin, arms=build_arm(spec), feet=build_foot(spec), head=build_head(spec))
    return parts, info


def counts(parts):
    out = {}
    for name, polys in parts.items():
        out[name] = (len(polys), sum(len(p) - 2 for p in polys))
    out["all"] = (sum(v[0] for v in out.values()), sum(v[1] for v in out.values()))
    return out
