"""Facial hair on the low-poly head: beards and moustaches.

A beard and a moustache are chosen separately, so that any beard goes with any moustache (owner, 2026-11).

  beards       stubble, chinstrap and full beard are the game's three (SPEC 5.1; check.py holds GAME_BEARDS equal to
               the game's list). A goatee is new here.
  moustaches   new here. The voxel face had three rows under the eyes and no mouth, so no room for one.

Facial hair is made of three kinds of piece:

  the head's own polygons, recoloured   stubble everywhere, and the cheeks and sideburns of a full beard. Where the
                                        beard's upper edge crosses a polygon, the polygon is cut along it.
  the head's own polygons, lifted       the body of a beard: the jaw of a full beard, a goatee, a chinstrap. They
                                        stand up to BULK steps of bulk off the head, and the ordinary garment rules
                                        of dress.py give them their edges, as they give a sleeve its hem. A full
                                        beard and a goatee grow out of the face: nothing at the top of the jaw, their
                                        whole thickness lower down.
  flat shapes on the face               a moustache. faces.py lays it with the mouth, which it hangs over.

The upper edge of a beard (CHEEK_LINE) starts beside the mouth, runs out under the eye, and climbs across the cheek
to the sideburn in front of the ear. With hair on, the sideburn runs up into the hair; on a bald head it stops at the
top of the ear. A full beard leaves the mouth a window of skin, so that the mouth can still be read on dark hair.
"""
import numpy as np
import body as lb, heads as hd

CX = lb.CX
GAME_BEARDS = ("stubble", "chinstrap", "full_beard")
BEARDS = GAME_BEARDS + ("goatee",)

BULK = 0.5                       # how far the body of a beard stands off the head at its thickest, in steps of bulk
FADE = (hd.BELT[0], hd.RING_Z[-2])           # a beard has no thickness at the top of the jaw, and all of it from the next ring down
CHEEK_LINE = (29.95, 30.15, 31.0, 32.5)      # a beard's upper edge: beside the mouth, at the edge of the flat face, and at the next two corners round the cheek
MOUTH_ROOM = 1.2                 # a full beard keeps this far from the middle of the face, where the mouth is
MOUTH_FLOOR = 29.12              # and comes up this high under the mouth
LIP_TOP = 30.2                   # stubble on the upper lip reaches this high
EAR_TOP = 34.4                   # where a sideburn stops on a bald head
GOATEE_HALF = (2.0, 1.5)         # half the width of a goatee: at the top of the jaw, and under the chin

# A moustache, from the middle of the face outward: (how far out, lower edge, upper edge). "leg": a bar down beside
# the mouth, hanging from the wing: (inner edge, outer edge, how low it goes).
MOUSTACHES = {
    "moustache": dict(wing=[(0.0, 29.66, 30.42), (1.0, 29.62, 30.28), (2.1, 29.50, 29.86)]),
    "handlebar": dict(wing=[(0.0, 29.68, 30.36), (1.0, 29.64, 30.20), (1.8, 29.70, 30.10), (2.5, 30.05, 30.38)]),
    "horseshoe": dict(wing=[(0.0, 29.66, 30.40), (1.25, 29.64, 30.30), (1.75, 29.64, 30.12)], leg=(1.25, 1.75, hd.BELT[0])),
    "pencil": dict(wing=[(0.0, 29.70, 30.02), (1.5, 29.64, 29.86)]),
}


# ---------------------------------------------------------------------------------------------- mesh tools ---

def _split(r, point, normal):
    """A polygon record cut by a plane: (the part on the side the normal points to, the part on the other side).
    Either is None where the polygon has nothing."""
    p = r["pts"]; d = (p - point) @ normal
    if d.min() >= -1e-9: return r, None
    if d.max() <= 1e-9: return None, r
    halves = []
    for sign in (1.0, -1.0):
        out = []
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]; da, db = sign * d[i], sign * d[(i + 1) % len(p)]
            if da >= -1e-9: out.append(a)
            if (da > 1e-9 and db < -1e-9) or (da < -1e-9 and db > 1e-9): out.append(a + da / (da - db) * (b - a))
        q = dict(r); q["pts"] = np.array(out)
        halves.append(q if len(out) >= 3 else None)
    return halves[0], halves[1]


def _cut(polys, pick, point, normal, claim=None):
    """polys, with every picked polygon cut by the plane. The part on the normal's side is given the claim, if any.
    A claim is (bulk, draw order, colour), as dress.py reads them."""
    out = []
    for r in polys:
        if not pick(r):
            out.append(r); continue
        yes, no = _split(r, point, normal)
        if yes is not None:
            if claim is not None:
                yes = dict(yes); yes["claims"] = list(yes.get("claims", [])) + [claim]
            out.append(yes)
        if no is not None: out.append(no)
    return out


def _claim(polys, pick, claim):
    out = []
    for r in polys:
        if pick(r):
            r = dict(r); r["claims"] = list(r.get("claims", [])) + [claim]
        out.append(r)
    return out


def conform(polys, piece="head"):
    """After cutting: give every polygon of the piece the corners that other polygons have on its edges, so that
    neighbours share whole edges again. dress.py looks across an edge to find the neighbour a hem steps down to."""
    mine = [r for r in polys if r["piece"] == piece]
    seen = {}
    for r in mine:
        for v in r["pts"]: seen.setdefault(tuple(np.round(v, 5)), v)
    pts = np.array(list(seen.values()))
    out = []
    for r in polys:
        if r["piece"] != piece:
            out.append(r); continue
        p = r["pts"]; ring = []
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]; ab = b - a; ll = float(ab @ ab)
            ring.append(a)
            if ll < 1e-12: continue
            t = (pts - a) @ ab / ll
            on = (t > 1e-6) & (t < 1.0 - 1e-6) & (np.linalg.norm(pts - a - np.outer(t, ab), axis=1) < 1e-6)
            for k in np.argsort(t[on]): ring.append(pts[on][k])
        if len(ring) != len(p):
            r = dict(r); r["pts"] = np.array(ring)
        out.append(r)
    return out


# ---------------------------------------------------------------------------------------------- on the head ---

def on_head(polys, style, colours, order, head, hair):
    """The figure's polygons with a beard marked on the head: a new list in which the polygons the beard takes carry
    claims, cut where its edge crosses them. A claim is (bulk, draw order, colour) or (bulk, draw order, colour,
    fade), as dress.py reads them. Returns (polys, notes).
    head: the name of the head's shape. hair: whether hair is worn (the sideburns run up into it)."""
    if style not in BEARDS: return polys, [f"unknown facial hair style '{style}'"]
    rg = hd.rings(head); n = len(rg[0]); ring_z = hd.RING_Z; e = 1e-6
    top = hd.BELT[1] if hair else EAR_TOP                           # where the sideburn ends

    def column(j, side, z):
        """The point at height z on the j-th corner round the head from the front (side 1: by the figure's left)."""
        i = max(k for k in range(len(ring_z) - 1) if ring_z[k] >= z - 1e-9)
        a, b = rg[i][j if side > 0 else (n - j) % n], rg[i + 1][j if side > 0 else (n - j) % n]
        return a + (ring_z[i] - z) / (ring_z[i] - ring_z[i + 1]) * (b - a)

    flat = lambda u, side, z: np.array([CX + side * u, hd.face_y(CX + side * u), z])    # a point on the flat of the face
    on = lambda r, kind: r["piece"] == "head" and r.get("at", ("",))[0] == kind
    lo = lambda r: float(r["pts"][:, 2].min()); hi = lambda r: float(r["pts"][:, 2].max())
    out_by = lambda r: float(np.abs(r["pts"][:, 0] - CX).mean())
    front = lambda r: r["face"] == "F"
    jaw = lambda r: on(r, "ring") and front(r) and hi(r) <= hd.BELT[0] + e              # the front of the head under the flat face
    chin = lambda r: on(r, "base") and front(r)                                         # its underside
    facet = lambda j, side: (j if side > 0 else n - 1 - j)                              # the polygons between corners j and j + 1
    between = lambda j, side, band: (lambda r: on(r, "ring") and r["at"][1:] == (band, facet(j, side)))
    level = lambda z: (np.array([0.0, 0.0, z]), np.array([0.0, 0.0, -1.0]))             # a plane, its normal pointing down

    def under(polys, pick, a, b, claim):
        """Cut the picked polygons along the line from a to b, and claim what is under it."""
        mine = [r for r in polys if pick(r)]
        if not mine: return polys
        across = np.cross(b - a, lb.ring_tools.normal(mine[0]["pts"]))                  # in the polygon, square to the line
        return _cut(polys, pick, a, -across if across[2] > 0 else across, claim)

    def cheeks(polys, claim):
        """Everything of the cheek under the beard's upper edge, from the flat of the face round to the ear."""
        heights = list(CHEEK_LINE[1:]) + [top]
        for side in (1, -1):
            for j in (1, 2, 3):
                for band in (2, 3):                                                     # the two bands the flat face is as tall as
                    polys = under(polys, between(j, side, band), column(j, side, heights[j - 1]), column(j + 1, side, heights[j]), claim)
        return polys

    if style == "stubble":
        shade = (0, order, colours["stubble"])
        polys = cheeks(_claim(polys, lambda r: jaw(r) or chin(r), shade), shade)
        for side in (1, -1):                                                            # and across the flat of the face, upper lip and all
            polys = under(polys, between(0, side, 3), flat(0.0, side, LIP_TOP), flat(hd.FACE_HALF_WIDTH, side, CHEEK_LINE[1]), shade)
    elif style == "full_beard":
        thin = (0, order, colours["hair"])
        polys = _claim(polys, lambda r: jaw(r) or chin(r), (BULK, order, colours["hair"], FADE))
        polys = cheeks(polys, thin)
        for side in (1, -1):                                                            # on the flat of the face: beside the mouth, and under it
            patch = between(0, side, 3)
            polys = _cut(polys, patch, flat(MOUTH_ROOM, side, 0.0), np.array([float(side), 0.0, 0.0]))
            polys = under(polys, lambda r: patch(r) and out_by(r) > MOUTH_ROOM, flat(MOUTH_ROOM, side, CHEEK_LINE[0]),
                          flat(hd.FACE_HALF_WIDTH, side, CHEEK_LINE[1]), thin)
            polys = _cut(polys, lambda r: patch(r) and out_by(r) < MOUTH_ROOM, *level(MOUTH_FLOOR), thin)
    elif style == "chinstrap":
        strap = (BULK, order, colours["hair"])
        if top < hd.BELT[1] - e:                                                        # so that the sideburn has an edge to stop at
            polys = _cut(polys, lambda r: on(r, "ring") and lo(r) < top - e and hi(r) > top + e, *level(top))
        beside_ear = lambda r: on(r, "ring") and r["at"][2] in (facet(3, 1), facet(3, -1))
        low = ring_z[-2]                                                                # the strap runs along the lowest band of the jaw
        polys = _claim(polys, lambda r: (jaw(r) and hi(r) <= low + e) or (beside_ear(r) and lo(r) >= low - e and hi(r) <= top + e), strap)
    elif style == "goatee":
        g0, g1 = GOATEE_HALF; drop = hd.BELT[0] - hd.BOTTOM
        sides = [(np.array([CX + s * g0, 0.0, hd.BELT[0]]), np.array([s, 0.0, (g1 - g0) / drop])) for s in (1.0, -1.0)]
        for point, outward in sides:                                                    # cut the chin free of the jaw on both sides
            polys = _cut(polys, lambda r: jaw(r) or chin(r), point, outward)
        middle = lambda r: (jaw(r) or chin(r)) and all(float(((r["pts"] - point) @ outward).max()) <= e for point, outward in sides)
        polys = _claim(polys, middle, (BULK, order, colours["hair"], FADE))
    return conform(polys), []


# ---------------------------------------------------------------------------------------------- on the face ---

def moustache(style):
    """A moustache as flat polygons [(x from the face's centre line, height)]. Each lies on one side of the centre
    line, because the face is two flat patches that meet there. faces.py lays them, with the mouth."""
    m = MOUSTACHES[style]; out = []
    for s in (1.0, -1.0):
        w = m["wing"]
        for (ua, la, ha), (ub, lb_, hb) in zip(w[:-1], w[1:]):
            out.append([(s * ua, la), (s * ub, lb_), (s * ub, hb), (s * ua, ha)])
        if "leg" in m:
            inner, outer, low = m["leg"]
            at = lambda u: float(np.interp(u, [p[0] for p in w], [p[1] for p in w]))    # the wing's lower edge, where the leg hangs from
            out.append([(s * inner, low), (s * outer, low), (s * outer, at(outer)), (s * inner, at(inner))])
    return out
