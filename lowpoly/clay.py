"""Smooth "clay" bodies: the shapes the low-poly bodies are cut from.

A clay body is a handful of rounded volumes (ellipsoids, a tapered tube for the neck, a rounded block for the head)
blended so that one flows into the next. Nothing here is polygons: it is the smooth form that rings of points are
later placed on (rings.py).

Units are the old voxel (24 to the metre): x across (the mirror plane is x = 12), y depth (front is -y, the depth
centre is y = 12), z up from the floor. The figure keeps the project's cartoon proportions: 42 tall, head 16 x 14 x 16.

Usage: python3 lowpoly/clay.py OUT_PNG [female|male] [--torso]
"""
import sys, time
import numpy as np

# ------------------------------------------------------------------ distance functions (smooth shapes) ---

def ellipsoid(p, c, r):
    q = (p - c) / r
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / r, axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def cone(p, a, b, ra, rb):
    """A limb: a rounded tube from a to b whose radius runs from ra to rb."""
    a = np.asarray(a, float); b = np.asarray(b, float)
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1) - (ra + (rb - ra) * t)


def round_box(p, c, half, r):
    q = np.abs(p - c) - (np.asarray(half, float) - r)
    return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - r


def smin(a, b, k):
    """Blend two shapes so one flows into the other; k is how wide the blend is."""
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * h * k / 6.0


# ------------------------------------------------------------------ the body ---

FEM_AVERAGE = dict(
    # torso, top to bottom (centres are (x offset from the mirror line, y offset from the depth centre, z))
    ribcage=((0, 0.25, 19.6), (4.7, 3.2, 5.5)),
    shoulders=((0, 0.4, 22.6), (5.7, 2.5, 1.75)),               # the shoulder girdle: collarbones out to the arms
    trapezius=((0, 0.6, 23.9), (3.3, 2.0, 1.5)),                # the slope from the neck down to the shoulders
    abdomen=((0, 0.0, 15.6), (3.8, 2.7, 3.5)),
    pelvis=((0, 0.3, 12.3), (4.95, 3.1, 2.7)),
    glute=((2.3, 1.75, 11.6), (2.3, 1.95, 2.35)),
    breast=((2.3, -2.2, 19.6), (2.15, 2.0, 2.2)),
    breast_slope=((2.1, -1.55, 21.0), (2.05, 1.55, 2.4)),       # the gentle slope down from the collarbone
    neck=((0, 0.5, 23.8), (0, 0.3, 26.8), 1.85, 1.85),
    head=((0, 0.0, 34.0), (8.0, 7.0, 8.0), 3.9),
    # arm: shoulder, then upper arm, forearm, hand (each a soft elongated form)
    deltoid=((5.85, 0.4, 22.3), 1.7),
    upper_arm=((6.4, 0.4, 19.6), (1.4, 1.45, 4.0)),
    forearm=((7.0, 0.2, 15.0), (1.2, 1.25, 3.9)),
    hand=((7.4, -0.35, 10.7), (0.95, 1.3, 1.8)),
    # leg: thigh, calf, heel and foot
    thigh=((2.78, 0.2, 8.9), (2.25, 2.35, 4.0)),
    calf=((2.92, 0.5, 4.4), (1.7, 1.75, 3.4)),
    heel=((2.95, 0.75, 1.1), (1.4, 1.5, 1.4)),
    foot=((3.05, -1.2, 1.1), (1.75, 3.3, 1.5)),
)


# First pass, judged "decent" by the owner. It starts from the old masculine average body (chest 12 x 8, belly 10,
# hips 10 x 8, arms 4 wide, against the feminine 10 x 6, 8, 10 x 6, 3) and real proportions: broader, squarer shoulders,
# a wider and deeper ribcage, less waist, hips no wider than the ribs, a flatter seat, a flat chest with a slight chest
# muscle, a thicker neck and thicker arms. Same height, same head, same joint heights.
MASC_AVERAGE = dict(
    ribcage=((0, 0.3, 19.7), (5.5, 3.8, 5.6)),
    shoulders=((0, 0.45, 22.75), (6.9, 2.9, 1.9)),
    trapezius=((0, 0.7, 24.0), (3.9, 2.4, 1.6)),
    abdomen=((0, 0.05, 15.6), (4.7, 3.25, 3.6)),
    pelvis=((0, 0.3, 12.3), (4.9, 3.5, 2.7)),
    glute=((2.2, 2.2, 11.7), (2.25, 1.8, 2.3)),
    breast=((2.6, -2.3, 20.5), (2.7, 1.0, 2.1)),                # the chest muscle: broad, flat, about a quarter of a unit proud
    breast_slope=((2.4, -1.9, 21.6), (2.4, 1.2, 1.8)),          # upper chest up to the collarbone
    neck=((0, 0.5, 23.8), (0, 0.3, 26.8), 2.25, 2.25),
    head=((0, 0.0, 34.0), (8.0, 7.0, 8.0), 3.9),
    deltoid=((7.05, 0.45, 22.4), 2.05),
    upper_arm=((7.55, 0.45, 19.6), (1.75, 1.8, 4.0)),
    forearm=((8.0, 0.2, 15.0), (1.5, 1.5, 3.9)),
    hand=((8.3, -0.35, 10.6), (1.15, 1.5, 2.0)),
    thigh=((2.7, 0.25, 8.9), (2.2, 2.35, 4.0)),
    calf=((2.85, 0.5, 4.4), (1.8, 1.85, 3.4)),
    heel=((2.9, 0.8, 1.1), (1.5, 1.6, 1.4)),
    foot=((3.0, -1.35, 1.1), (1.9, 3.6, 1.5)),
)

# ------------------------------------------------------------------ the other builds ---
# Slim, heavy and short are made from each sex's average clay, so that a change to the average carries over. First
# pass, for the owner to judge (2026-11). The low-poly bodies are cut from them (body.py).
#
#   slim, heavy   the same heights; widths and girths change (factors against the average). Heavy is more mass
#                 everywhere, not obesity: the belly never comes forward of the chest, and the seat grows little
#                 (SPEC 3.3: a protruding belly or rear was tried and rejected twice).
#   short         for dwarfs: broader than average, then shorter. Every band of height keeps its place in the order,
#                 but the shins and lower thighs lose the most, the torso less, and the feet and the upper thighs
#                 nothing. The head is the same head, set on the shorter neck. 42 tall becomes 36.

import copy

BUILD_FACTORS = {
    ("female", "slim"): dict(chest=0.86, waist=0.85, hips=0.86, depth=0.92, arm=0.85, leg=0.85, bust=0.8, neck=0.92, feet=0.95, seat=0.85),
    ("female", "heavy"): dict(chest=1.18, waist=1.25, hips=1.18, depth=1.2, arm=1.25, leg=1.25, bust=1.25, neck=1.12, feet=1.08, seat=1.1),
    ("female", "short"): dict(chest=1.1, waist=1.15, hips=1.1, depth=1.12, arm=1.2, leg=1.2, bust=1.1, neck=1.12, feet=1.12, seat=1.05),
    ("male", "slim"): dict(chest=0.85, waist=0.9, hips=0.92, depth=0.85, arm=0.82, leg=0.85, neck=0.9, feet=0.95),
    ("male", "heavy"): dict(chest=1.17, waist=1.3, hips=1.25, depth=1.2, arm=1.3, leg=1.3, neck=1.15, feet=1.08),
    ("male", "short"): dict(chest=1.12, waist=1.2, hips=1.15, depth=1.15, arm=1.25, leg=1.25, neck=1.2, feet=1.12),
}
# the bands of height from the floor to the top of the neck, and how much of its height each keeps on a short body
BAND_HEIGHTS = [("foot", 0, 2), ("ankle", 2, 3), ("shin", 3, 6), ("knee", 6, 7), ("lower_thigh", 7, 9), ("upper_thigh", 9, 11),
                ("hips", 11, 14), ("waist", 14, 15), ("belly", 15, 17), ("lower_chest", 17, 20), ("upper_chest", 20, 24),
                ("collar", 24, 25), ("neck", 25, 26)]
# The upper thigh keeps its height: it holds the leg opening, and the broad pelvis keeps most of its depth, so the
# crotch is as far below the hips as on the average. The shins and the lower thighs give it up instead, which also
# puts the knee where it is on the average: 57% of the way from the ankle up to the crotch. (First pass 2026-11 had
# shin 0.6, lower thigh 0.6, upper thigh 0.65: the crotch fell below the thigh's ring, and the knee sat high.)
SHORT_KEEPS = dict(foot=1.0, ankle=0.8, shin=0.47, knee=0.8, lower_thigh=0.45, upper_thigh=1.0, hips=0.8, waist=0.9, belly=0.75,
                   lower_chest=0.75, upper_chest=0.8, collar=0.9, neck=0.9)
SQUASH_SHAPE = 0.5          # how much of the squash a rounded volume takes in its own height; less keeps it longer, so that it blends


def derive(base, chest=1.0, waist=1.0, hips=1.0, depth=1.0, arm=1.0, leg=1.0, bust=1.0, neck=1.0, feet=1.0, seat=1.0):
    """Another build from an average clay: widths and girths changed by these factors, heights kept."""
    m = copy.deepcopy(base)

    def put(name, c=None, r=None):
        oc, orr = m[name]
        m[name] = (tuple(c) if c is not None else oc, tuple(r) if r is not None else orr)

    c, r = m["ribcage"]; front0 = c[1] - r[1]
    put("ribcage", r=(r[0] * chest, r[1] * depth, r[2]))
    rc, rr = m["ribcage"]; front = rc[1] - rr[1]                    # the chest's front, where it is now
    c, r = m["shoulders"]; wider = r[0] * (chest - 1.0)             # how much further out the shoulders reach
    put("shoulders", r=(r[0] * chest, r[1] * depth, r[2]))
    c, r = m["trapezius"]; put("trapezius", r=(r[0] * (1.0 + 0.6 * (chest - 1.0)), r[1] * depth, r[2]))
    c, r = m["abdomen"]; belly = (r[0] * waist, r[1] * depth, r[2])
    cy = max(c[1], front + 0.35 + belly[1])                         # the belly never comes forward of the chest
    put("abdomen", c=(c[0], cy, c[2]), r=belly)
    c, r = m["pelvis"]; hip = r[0] * (hips - 1.0)
    put("pelvis", r=(r[0] * hips, r[1] * depth, r[2]))
    c, r = m["glute"]; put("glute", c=(c[0] * hips, c[1] * (1.0 + 0.6 * (depth - 1.0)), c[2]), r=(r[0] * hips, r[1] * seat, r[2]))
    for name in ("breast", "breast_slope"):
        c, r = m[name]; put(name, c=(c[0] * chest, c[1] + front - front0, c[2]), r=(r[0] * bust, r[1] * bust, r[2] * (1.0 + 0.5 * (bust - 1.0))))
    a, b, ra, rb = m["neck"]; m["neck"] = (a, b, ra * neck, rb * neck)
    c, r = m["deltoid"]; m["deltoid"] = ((c[0] + wider, c[1], c[2]), r * arm)
    for name in ("upper_arm", "forearm", "hand"):                   # the arms hang from the wider shoulders
        c, r = m[name]; put(name, c=(c[0] + wider, c[1], c[2]), r=(r[0] * arm, r[1] * arm, r[2]))
    for name in ("thigh", "calf"):                                  # the legs stand a little wider with the hips
        c, r = m[name]; put(name, c=(c[0] + 0.55 * hip, c[1], c[2]), r=(r[0] * leg, r[1] * leg, r[2]))
    for name in ("heel", "foot"):
        c, r = m[name]; put(name, c=(c[0] + 0.55 * hip, c[1], c[2]), r=(r[0] * feet, r[1] * feet, r[2]))
    return m


def short_heights(keeps=SHORT_KEEPS):
    """[(band, bottom, top)] for a short body: each band of BAND_HEIGHTS keeps that much of its height."""
    out = []; z = 0.0
    for name, z0, z1 in BAND_HEIGHTS:
        out.append((name, z, z + (z1 - z0) * keeps[name])); z += (z1 - z0) * keeps[name]
    return out


class Heights:
    """Where a height on the average body is on another body: the same band, the same share of the way up it. On a
    short body (heights from short_heights) every band is lower; straight in between; above the neck the distances
    stay as they are, because the head keeps its size. With no heights, every height stays exactly where it is."""

    def __init__(self, heights=None):
        self.moved = heights is not None
        self.old = [0.0] + [z1 for _, _, z1 in BAND_HEIGHTS]
        self.new = [0.0] + [z1 for _, _, z1 in heights] if self.moved else list(self.old)

    def __call__(self, z):
        if not self.moved: return z
        return float(np.interp(z, self.old, self.new)) if z <= self.old[-1] else self.new[-1] + (z - self.old[-1])

    def back(self, z):
        """The other way: where a height on this body is on the average."""
        if not self.moved: return z
        return float(np.interp(z, self.new, self.old)) if z <= self.new[-1] else self.old[-1] + (z - self.new[-1])


def squash(base, heights):
    """The same body with its bands of height moved to heights (as short_heights gives), straight in between. The
    head keeps its size and sits on the neck."""
    old = [0.0] + [z1 for _, _, z1 in BAND_HEIGHTS]; new = [0.0] + [z1 for _, _, z1 in heights]
    f = Heights(heights)
    slope = lambda z: (f(z + 0.25) - f(z - 0.25)) / 0.5
    m = copy.deepcopy(base)
    for name, v in m.items():
        if name == "neck":
            a, b, ra, rb = v; m[name] = ((a[0], a[1], f(a[2])), (b[0], b[1], f(b[2])), ra, rb)
        elif name == "head":
            c, half, r = v; m[name] = ((c[0], c[1], c[2] - old[-1] + new[-1]), half, r)
        elif name == "deltoid":
            c, r = v; m[name] = ((c[0], c[1], f(c[2])), r)
        else:
            c, r = v; m[name] = ((c[0], c[1], f(c[2])), (r[0], r[1], r[2] * slope(c[2]) ** SQUASH_SHAPE))
    return m


BODIES = {("female", "average"): FEM_AVERAGE, ("male", "average"): MASC_AVERAGE}
HEIGHTS = {}                # the builds whose bands are not at the average's heights: (sex, build) -> short_heights()
for (_sex, _build), _f in BUILD_FACTORS.items():
    _m = derive(BODIES[(_sex, "average")], **_f)
    if _build == "short": HEIGHTS[(_sex, _build)] = short_heights()
    BODIES[(_sex, _build)] = squash(_m, HEIGHTS[(_sex, _build)]) if _build == "short" else _m


def body(p, m=FEM_AVERAGE, parts=None):
    """Distance to the body's surface for points p (N x 3, voxel units). Negative inside.
    parts = "torso" gives the torso alone (no head, arms or legs), for measuring."""
    q = np.empty_like(p)
    q[:, 0] = np.abs(p[:, 0] - 12.0)          # mirror: everything is modelled on one side
    q[:, 1] = p[:, 1] - 12.0
    q[:, 2] = p[:, 2]
    E = lambda name: ellipsoid(q, np.array(m[name][0], float), np.array(m[name][1], float))

    torso = smin(E("ribcage"), E("shoulders"), 2.2)
    torso = smin(torso, E("trapezius"), 1.8)
    torso = smin(torso, E("abdomen"), 2.8)
    torso = smin(torso, E("pelvis"), 2.6)
    torso = smin(torso, E("glute"), 1.8)
    bust = smin(E("breast"), E("breast_slope"), 1.5)
    torso = smin(torso, bust, 1.4)

    if parts == "torso":
        return torso
    a, b, ra, rb = m["neck"]
    neck = cone(q, a, b, ra, rb)
    c, half, r = m["head"]
    head = round_box(q, np.array(c, float), half, r)
    d = smin(torso, smin(neck, head, 0.9), 1.6)

    # The shoulder flows into the torso; below it the arm is its own smooth limb lying against the body.
    c, r = m["deltoid"]
    d = smin(d, np.linalg.norm(q - np.array(c, float), axis=1) - r, 1.6)
    arm = smin(E("upper_arm"), E("forearm"), 1.2)
    arm = smin(arm, E("hand"), 0.9)
    d = smin(d, arm, 0.6)

    leg = smin(E("thigh"), E("calf"), 1.3)
    leg = smin(leg, smin(E("foot"), E("heel"), 1.0), 0.9)
    d = smin(d, leg, 1.8)
    return np.maximum(d, -p[:, 2])            # flat on the floor


# ------------------------------------------------------------------ a plain clay picture ---

def render(sdf, yaw_deg=0.0, pitch_deg=0.0, scale=14, width=24.0 + 6.0, z_range=(-0.5, 43.0), centre_x=12.0, centre_y=12.0,
           colour=(206, 190, 172), bg=(28, 31, 40)):
    """Parallel-ray picture: yaw 0 = from the front, 90 = from the figure's left, 180 = from behind."""
    yaw, pitch = np.radians(yaw_deg), np.radians(pitch_deg)
    # camera axes in body coordinates
    fwd = np.array([-np.sin(yaw) * np.cos(pitch), np.cos(yaw) * np.cos(pitch), -np.sin(pitch)])
    right = np.array([np.cos(yaw), np.sin(yaw), 0.0])
    up = np.cross(right, fwd); up /= np.linalg.norm(up)
    if up[2] < 0: up = -up
    W = int(width * scale); H = int((z_range[1] - z_range[0]) * scale)
    us = (np.arange(W) + 0.5) / scale - width / 2.0
    vs = (z_range[1] - z_range[0]) / 2.0 - (np.arange(H) + 0.5) / scale
    U, V = np.meshgrid(us, vs)
    centre = np.array([centre_x, centre_y, (z_range[0] + z_range[1]) / 2.0])
    origin = centre + U.reshape(-1, 1) * right + V.reshape(-1, 1) * up - 40.0 * fwd
    t = np.zeros(origin.shape[0]); alive = np.ones(origin.shape[0], bool); hit = np.zeros(origin.shape[0], bool)
    for _ in range(260):
        idx = np.nonzero(alive)[0]
        if idx.size == 0: break
        d = sdf(origin[idx] + t[idx, None] * fwd)
        t[idx] += np.maximum(d * 0.55, 0.0)
        done = d < 0.008
        hit[idx[done]] = True
        alive[idx[done]] = False
        alive[idx[t[idx] > 90.0]] = False
    img = np.zeros((H * W, 3)); img[:] = bg
    idx = np.nonzero(hit)[0]
    if idx.size:
        P = origin[idx] + t[idx, None] * fwd
        e = 0.06
        n = np.stack([sdf(P + np.array([e, 0, 0])) - sdf(P - np.array([e, 0, 0])),
                      sdf(P + np.array([0, e, 0])) - sdf(P - np.array([0, e, 0])),
                      sdf(P + np.array([0, 0, e])) - sdf(P - np.array([0, 0, e]))], axis=1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        # an even studio light fixed to the camera: a key from upper left, a soft fill, a little from above
        key = (-0.45 * right + 0.55 * up - 0.7 * fwd); key /= np.linalg.norm(key)
        fill = (0.6 * right + 0.1 * up - 0.75 * fwd); fill /= np.linalg.norm(fill)
        light = 0.34 + 0.52 * np.clip(n @ key, 0, 1) + 0.16 * np.clip(n @ fill, 0, 1) + 0.06 * np.clip(n[:, 2], 0, 1)
        img[idx] = np.clip(light[:, None] * np.array(colour, float), 0, 255)
    return img.reshape(H, W, 3).astype(np.uint8)


def silhouette(sdf, yaw_deg, scale=14, width=30.0, z_range=(-0.5, 43.0)):
    im = render(sdf, yaw_deg, 0.0, scale, width, z_range, colour=(232, 236, 244))
    mask = (im != np.array((28, 31, 40), np.uint8)).any(axis=2)
    out = np.zeros_like(im); out[:] = (28, 31, 40); out[mask] = (232, 236, 244)
    return out


if __name__ == "__main__":
    from PIL import Image, ImageDraw, ImageFont
    out = sys.argv[1]
    model = MASC_AVERAGE if "male" in sys.argv[2:] else FEM_AVERAGE
    torso_only = "--torso" in sys.argv
    t0 = time.time()
    def font(sz, bold=False):
        try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else ""), sz)
        except Exception: return ImageFont.load_default()
    sdf = lambda p: body(p, model)
    views = [("front", 0, 0), ("turned", 35, 10), ("side", 90, 0), ("turned back", 145, 10), ("back", 180, 0)]
    if torso_only:
        tiles = [render(sdf, y, p, scale=30, width=20.0, z_range=(8.5, 27.0)) for _, y, p in views]
    else:
        tiles = [render(sdf, y, p, scale=15, width=27.0) for _, y, p in views]
    h = tiles[0].shape[0]; w = sum(t.shape[1] for t in tiles)
    sheet = Image.new("RGB", (w, h + 40), (28, 31, 40)); d = ImageDraw.Draw(sheet); x = 0
    for (name, _, _), t in zip(views, tiles):
        sheet.paste(Image.fromarray(t), (x, 40)); d.text((x + 10, 8), name, font=font(20, True), fill=(255, 214, 102)); x += t.shape[1]
    sheet.save(out); print(out, sheet.size, "%.0f s" % (time.time() - t0))
