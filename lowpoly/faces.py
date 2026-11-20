"""Faces: the eyes with their lids and lashes, the eyebrows and a small mouth, as flat polygons on a head's two face
patches.

WHAT is shown comes from the game, not from here (game.py), as on the voxel faces (SPEC 5):

  an eye set     the open eye, drawn once per eye in the eye box's cells, from the wardrobe file. What is taken from
                 the drawing is how much of the box it fills and where its pupil sits.
  a colourway    which palette colour each of its roles takes (white, pupil, line): eye colour is a colourway, and
                 the lash line takes the "line" colour
  a lid state    per eye: how far the upper lid has come down, how far the lower lid has come up, where the pupil
                 looks, and the tilt of the upper lid. The ten named states are the game's.
  lid colour     from the skin tone; brow colour from the hair. Both are the game's own numbers.

HOW it is drawn is the low-poly figure's own (owner, 2026-11):

  the eye     a rounded oval filling the box the drawing fills, with an oval pupil over the drawing's pupil cells.
              A lid cuts the oval straight across (on a slope when it is tilted).
  the lashes  a thin line along the top edge of the open eye, from corner to corner, never outside the eye. (The
              voxel face has one thick bar there that is lashes and eyebrow at once, and overhangs the eye.)
  the brow    a bar of its own above the eye. It rises for a wide open eye, comes down for a lowered lid, and takes
              part of the lid's tilt, so the ten lid states still give ten faces.
  its place   the eye box goes on the head slightly smaller than the voxel one (EYE_SIZE), its middle at the middle
              of the flat part of the face. That leaves room above for the brow and below for
  the mouth   a short line, curved up or down, or a small open oval, low on the flat part of the face, with room
              between it and the eyes for a moustache. The voxel faces have no mouth; this one is new.

The polygons of a face do not overlap: they tile it, so they can all lie at one small height off the head. White,
pupil and lash line are drawn in their own colour, untouched by the light (as the voxel face has them); lid, brow and
mouth are lit like the skin they are part of.
"""
import numpy as np
import body as lb, heads as hd

CX = lb.CX
LIFT = 0.04                      # how far the face's polygons stand off the face
EYES = ("left", "right")         # SCREEN left and right, as the game names them: "left" is the figure's own right eye

EYE_SIZE = 0.9                   # the eye box on the head, against the game's (5 wide, 6 tall): slightly smaller (owner)
EYE_MIDDLE = 0.5 * (hd.BELT[0] + hd.BELT[1])     # the height of the eye's middle: half way up the flat part of the face (owner)
ROUND = 2.0                      # the eye's outline: 2 is an ellipse, more is fuller toward the corners of its box
SIDES = 20                       # corners of the eye's outline
PUPIL_GROW = (1.3, 1.15)         # the pupil's oval against the box of the drawing's pupil cells: wider, taller
PUPIL_SIDES = 12
# The numbers below are in the eye box's own cells and rows, so they shrink with the eye.
LASH = 0.34                      # the lash line's thickness at the middle of the eye
LASH_FLARE = 0.35                # it is this much thicker at the eye's outer end, and as much thinner at its inner end
BROW_REACH = (0.3, 4.9)          # the brow from end to end, counted from the eye's outer edge
BROW_GAP = 0.4                   # its lower edge above the top of the eye, at rest
BROW_THICK = (0.36, 0.62)        # at its outer end, at its inner end
BROW_MOVE = 0.3                  # it rises this far for a wide open eye, and comes down this far for a lid half way down or more
BROW_TILT = 0.55                 # how much of the upper lid's tilt it takes; it hangs from its higher end
BROW_PEAK = 0.35                 # where along it, from its outer end, its peak is
BROW_ARCH = 0.3                  # how far its outer end falls from the peak (0 for a straight bar)

MOUTH_Z = 29.4                   # the height of a straight mouth
MOUTH_WIDE = 2.0                 # a line mouth, corner to corner
MOUTH_THICK = 0.3
MOUTH_STEPS = 6                  # pieces in a curved line (an even number: the mouth is cut where the two patches meet)
MOUTH_SHADE = (0.62, 0.45, 0.48)     # the mouth's colour is the skin's, darkened and a little toward red
# name: a line with how far its corners turn up (down, if negative) against its middle; or an open oval, wide and tall
MOUTHS = {"neutral": ("line", 0.0), "smile": ("line", 0.5), "frown": ("line", -0.45), "open": ("oval", (1.1, 0.8))}


# ------------------------------------------------------------------------------------------- flat geometry ---

def _clip(poly, p, q, above=True):
    """Keep the part of a convex polygon on or above the line through p and q (p left of q); or on or below it."""
    if len(poly) < 3: return []
    p = np.asarray(p, float); q = np.asarray(q, float); d = q - p
    side = lambda v: (d[0] * (v[1] - p[1]) - d[1] * (v[0] - p[0])) * (1.0 if above else -1.0)
    out = []
    for i in range(len(poly)):
        a, b = np.asarray(poly[i], float), np.asarray(poly[(i + 1) % len(poly)], float)
        sa, sb = side(a), side(b)
        if sa >= -1e-9: out.append(a)
        if (sa > 1e-9 and sb < -1e-9) or (sa < -1e-9 and sb > 1e-9):
            out.append(a + sa / (sa - sb) * (b - a))
    return out


def _area(poly):
    return 0.5 * abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly))))


def _tidy(poly):
    """Drop repeated points and points on a straight run."""
    pts = []
    for v in poly:
        if not pts or np.linalg.norm(np.asarray(v) - pts[-1]) > 1e-7: pts.append(np.asarray(v, float))
    if len(pts) > 1 and np.linalg.norm(pts[0] - pts[-1]) <= 1e-7: pts.pop()
    changed = True
    while changed and len(pts) > 3:
        changed = False
        for i in range(len(pts)):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
            if abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) < 1e-7:
                del pts[i]; changed = True; break
    return pts


def _convex(poly):
    sign = 0
    for i in range(len(poly)):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
        z = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(z) < 1e-7: continue
        if sign and (z > 0) != (sign > 0): return False
        sign = z
    return True


def merge(pieces):
    """Join neighbouring pieces of one role into one polygon wherever the result is still convex.
    pieces: [(polygon, role)]. Fewer polygons, the same picture."""
    pieces = [(_tidy(p), role) for p, role in pieces]
    pieces = [(p, role) for p, role in pieces if len(p) >= 3 and _area(p) > 1e-6]
    key = lambda v: (round(float(v[0]), 6), round(float(v[1]), 6))
    joined = True
    while joined:
        joined = False
        for i in range(len(pieces)):
            for j in range(i + 1, len(pieces)):
                (a, ra), (b, rb) = pieces[i], pieces[j]
                if ra != rb: continue
                found = None
                for s in range(len(a)):
                    e0, e1 = key(a[s]), key(a[(s + 1) % len(a)])
                    for t in range(len(b)):
                        if key(b[t]) == e1 and key(b[(t + 1) % len(b)]) == e0:
                            found = (s, t); break
                    if found: break
                if not found: continue
                s, t = found
                both = [a[(s + 1 + k) % len(a)] for k in range(len(a))] + [b[(t + 2 + k) % len(b)] for k in range(len(b) - 2)]
                both = _tidy(both)
                if len(both) >= 3 and _convex(both) and abs(_area(both) - _area(a) - _area(b)) < 1e-6:
                    pieces[i] = (both, ra); del pieces[j]; joined = True; break
            if joined: break
    return pieces


def oval(cx, cy, a, b, sides, power=2.0):
    """A rounded oval as a polygon, anticlockwise, with a corner at its top, bottom and both sides:
    |x / a| ** power + |y / b| ** power = 1. Power 2 is an ellipse; more is fuller toward the corners of its box."""
    pts = []
    for k in range(sides):
        c, s = np.cos(2.0 * np.pi * k / sides), np.sin(2.0 * np.pi * k / sides)
        pts.append((cx + a * np.sign(c) * abs(c) ** (2.0 / power), cy + b * np.sign(s) * abs(s) ** (2.0 / power)))
    return pts


def _apart(poly, hole):
    """A convex polygon with a convex hole (anticlockwise) cut out of it: (the pieces round the hole, the part of
    the polygon inside the hole). The pieces are convex and do not overlap: one for each side of the hole that has
    some of the polygon outside it."""
    rest = list(poly); pieces = []
    for i in range(len(hole)):
        if len(rest) < 3: break
        p, q = hole[i], hole[(i + 1) % len(hole)]
        pieces.append(_clip(rest, p, q, above=False))
        rest = _clip(rest, p, q, above=True)
    return [x for x in pieces if len(x) >= 3], rest


def role_at(pieces, x, r):
    """The role drawn at a point of the eye's box, or None."""
    for poly, role in pieces:
        inside = True
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            if (b[0] - a[0]) * (r - a[1]) - (b[1] - a[1]) * (x - a[0]) < -1e-9: inside = False; break
        if inside: return role
    return None


# ------------------------------------------------------------------------------------------------- the eye ---
# An eye is worked out flat first, in the game's own eye box: x from the eye's OUTER edge (0 to the box's width), r up
# from its bottom row (0 to the box's height, and one more row for a raised brow). Lid states are in those rows.

def drawing_of(eye_set, eye):
    return {(int(c), int(r)): role for c, r, role in eye_set["eye"][eye]}


def shape_of(drawing):
    """The ovals a drawn eye stands for: dict(outline, pupil), each (centre x, centre r, half width, half height).
    The outline fills the box the drawing fills; the pupil lies over the drawing's pupil cells, a little larger."""
    def box(cells):
        cs = [c for c, _ in cells]; rs = [r for _, r in cells]
        return 0.5 * (min(cs) + max(cs) + 1), 0.5 * (min(rs) + max(rs) + 1), 0.5 * (max(cs) + 1 - min(cs)), 0.5 * (max(rs) + 1 - min(rs))

    pupil = [k for k, role in drawing.items() if role == "pupil"]
    px, pr, pa, pb = box(pupil) if pupil else (0.0, 0.0, 0.0, 0.0)
    return dict(outline=box(list(drawing)), pupil=(px, pr, pa * PUPIL_GROW[0], pb * PUPIL_GROW[1]))


def drawn(shape, state, eye, w, h):
    """One eye as flat pieces [(polygon, role)], roles white, pupil, line (the lashes), lid. shape: its ovals
    (shape_of). state: the game's five numbers for this eye: upper lid rows, lower lid rows, pupil dx in screen
    terms, pupil dy, tilt of the upper lid."""
    upper, lower, dx, dy, tilt = (float(v) for v in state)
    ox, oy, oa, ob = shape["outline"]; px, py, pa, pb = shape["pupil"]
    outline = oval(ox, oy, oa, ob, SIDES, ROUND)
    pupil = oval(px + (dx if eye != "right" else -dx), py + dy, pa, pb, PUPIL_SIDES) if pa > 0 and pb > 0 else None
    edge = lambda x: h - (upper + tilt * (x - 0.5) / (w - 1))       # the upper lid's edge: the game's steps, as one slope
    lid = ((0.0, edge(0.0)), (float(w), edge(float(w))))
    low = ((0.0, lower), (float(w), lower))
    pieces = [(_clip(outline, *lid, True), "lid")]                   # the upper lid
    under = _clip(outline, *lid, False)                              # all of the eye under the upper lid's edge
    # the lashes: the top of that, from corner to corner. Cut by sliding the shape down its own thickness of lash.
    thick = lambda x: LASH * (1.0 + LASH_FLARE * (1.0 - 2.0 * x / w))
    lashes, rest = _apart(under, [(x, r - thick(x)) for x, r in under])
    pieces += [(p, "line") for p in lashes]
    pieces.append((_clip(rest, *low, False), "lid"))                 # the lower lid
    seen = _clip(rest, *low, True)                                   # the eye between the lids
    if pupil is None:
        pieces.append((seen, "white"))
    else:
        around, inside = _apart(seen, pupil)
        pieces += [(p, "white") for p in around] + [(inside, "pupil")]
    return merge(pieces)


def brow_of(state, w, h):
    """An eyebrow as flat polygons, in the eye's box: an inner part and an outer part that falls away from its peak.
    It rides above the eye: up a little for a wide open eye, down a little for a lowered lid, and tilted as the lid
    is tilted, though less, hanging from its higher end."""
    upper, _, _, _, tilt = (float(v) for v in state)
    x0, x1 = BROW_REACH; xp = x0 + BROW_PEAK * (x1 - x0)
    base = h + BROW_GAP + BROW_MOVE * (1.0 - min(max(upper, 0.0), 2.0))
    slope = BROW_TILT * tilt / (w - 1)                              # rows down for each cell toward the nose
    drop = lambda x: slope * (x - x0) if slope > 0 else slope * (x - x1)      # nothing at the higher end
    low = lambda x: base - drop(x) - (BROW_ARCH * (xp - x) / (xp - x0) if x < xp else 0.0)
    thick = lambda x: BROW_THICK[0] + (BROW_THICK[1] - BROW_THICK[0]) * (x - x0) / (x1 - x0)
    part = lambda xa, xb: [(xa, low(xa)), (xb, low(xb)), (xb, low(xb) + thick(xb)), (xa, low(xa) + thick(xa))]
    return [part(x0, xp), part(xp, x1)] if BROW_ARCH else [part(x0, x1)]


def with_brow(pieces, brow):
    """The eye's pieces with the brow added. Where the brow lies over the eye it is cut out of what is under it."""
    for part in brow:
        out = []
        for poly, role in pieces:
            around, inside = _apart(poly, part)
            if len(inside) >= 3 and _area(inside) > 1e-9: out += [(p, role) for p in around]
            else: out.append((poly, role))
        pieces = out
    return merge(pieces) + [(part, "brow") for part in brow]


# --------------------------------------------------------------------------------------------- on the head ---

def _on_face(polys, bend, lift):
    """Flat polygons given as (x on the head, height) onto the face's patches, facing forward."""
    out = []
    for poly in polys:
        pts = np.array([[x, hd.face_y(x, bend) - lift, z] for x, z in poly])
        n = np.zeros(3)
        for i in range(len(pts)):
            n += np.cross(pts[i], pts[(i + 1) % len(pts)])
        out.append(pts[::-1].copy() if n[1] > 0 else pts)
    return out


def place(pieces, eye, box, bend=None, lift=LIFT, size=None):
    """Flat pieces of one eye onto its patch of the head: [(polygon in 3D, role)]. The eye box keeps the game's
    place across the face; its middle is at EYE_MIDDLE; size is how big it is against the game's box."""
    size = EYE_SIZE if size is None else size
    w, h = float(box["w"]), float(box["h"])
    middle = abs(float(box["x0"]) - CX) - 0.5 * w                   # the middle of the eye, from the face's centre line
    top = EYE_MIDDLE + 0.5 * h * size
    flat = []
    for poly, _ in pieces:
        off = [middle + (0.5 * w - x) * size for x, _ in poly]
        flat.append([(CX - o if eye == "left" else CX + o, top - (h - r) * size) for o, (_, r) in zip(off, poly)])
    return [(pts, role) for pts, (_, role) in zip(_on_face(flat, bend, lift), pieces)]


def eyes(tables, wardrobe, eye_set="standard", colourway="default", lids=None, skin=None, hair=None, brow=None,
         bend=None, size=None):
    """Both eyes with their brows on a head: [dict(pts, rgb, role, unlit)].
    lids: a lid state's name (the game's default if None), or "" for the eye wide open with no brow.
    skin: a skin tone's name. hair: the palette name of the hair colour the brow follows (the game's default brow
    hair if None). brow: a colour to use for the brow instead."""
    t = tables["eyes"]; box = t["box"]; w, h = int(box["w"]), int(box["h"])
    lids = t["default"] if lids is None else lids
    skin = tables["default_skin"] if skin is None else skin
    es = wardrobe.eye_sets[eye_set]
    way = es["colourways"][colourway if colourway in es["colourways"] else sorted(es["colourways"])[0]]
    colour = {role: wardrobe.palette[name] for role, name in way.items()}
    colour["lid"] = tuple(tables["skin"][skin]["lid"])
    colour["brow"] = tuple(brow) if brow is not None else tuple(tables["hair"][hair or tables["default_brow_hair"]]["brow"])
    flat = set(t["flat_roles"])
    out = []
    for i, eye in enumerate(EYES):
        state = t["states"][lids][i] if lids else [0, 0, 0, 0, 0]
        pieces = drawn(shape_of(drawing_of(es, eye)), state, eye, w, h)
        if lids != "": pieces = with_brow(pieces, brow_of(state, w, h))
        for pts, role in place(pieces, eye, box, bend, size=size):
            out.append(dict(pts=pts, rgb=colour[role], role=role, unlit=role in flat))
    return out


# ----------------------------------------------------------------------------------------------- the mouth ---

def mouth_shape(state="neutral"):
    """A mouth as flat polygons [(x from the face's centre line, height)], cut where the two patches meet. Nothing of
    it is lower than a straight mouth's lower edge, since the flat part of the face ends just under that."""
    kind, v = MOUTHS[state]
    t = 0.5 * MOUTH_THICK
    if kind == "oval":
        whole = oval(0.0, MOUTH_Z - t + 0.5 * v[1], 0.5 * v[0], 0.5 * v[1], 12)
        return [_tidy(_clip(whole, (0.0, 0.0), (0.0, 1.0), above)) for above in (True, False)]
    n = MOUTH_STEPS if v else 2
    us = [MOUTH_WIDE * (k / n - 0.5) for k in range(n + 1)]
    bend = lambda u: (2.0 * u / MOUTH_WIDE) ** 2                     # 0 at the middle of the mouth, 1 at its corners
    # a smile turns its corners up from the line; a frown stands on its corners and lifts its middle
    zs = [MOUTH_Z + (v * bend(u) if v >= 0 else -v * (1.0 - bend(u))) for u in us]
    return [[(us[k], zs[k] - t), (us[k + 1], zs[k + 1] - t), (us[k + 1], zs[k + 1] + t), (us[k], zs[k] + t)] for k in range(n)]


def mouth_colour(skin_rgb):
    return tuple(int(round(c * k)) for c, k in zip(skin_rgb, MOUTH_SHADE))


def mouth(tables, state="neutral", skin=None, bend=None):
    """The mouth on a head: [dict(pts, rgb, role, unlit)]. skin: a skin tone's name."""
    skin = tables["default_skin"] if skin is None else skin
    rgb = mouth_colour(tables["skin"][skin]["mid"])
    flat = [[(CX + u, z) for u, z in poly] for poly in mouth_shape(state)]
    return [dict(pts=pts, rgb=rgb, role="mouth", unlit=False) for pts in _on_face(flat, bend, LIFT)]
