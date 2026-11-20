"""Faces: the eyes, with their lids and brows, as flat polygons on a head's two eye patches.

The options are the voxel faces' (SPEC 5), and WHAT is drawn comes from the game, not from here (game.py):

  an eye set     the open eye, drawn once per eye in box cells (5 wide, 6 tall), from the wardrobe file
  a colourway    which palette colour each of its roles takes (white, pupil, line): eye colour is a colourway
  a lid state    per eye: how far the upper lid has come down, how far the lower lid has come up, where the pupil
                 looks, and the tilt of the upper lid. The ten named states are the game's.
  lid colour     from the skin tone; brow colour from the hair. Both are the game's own numbers.

What is new here is HOW it is drawn on a low-poly head. Two ways:

  eased   (the default) a one-cell step in the outline of the drawing becomes a diagonal, and a tilted lid is one
          sloped edge. The brow is a bar, one unit thick, that follows that edge.
  cells   every cell a square, exactly the cells the game works out for the voxel face.

Eyes do not overlap one another's colours: the polygons of one eye tile it, so they can all lie at one small height
off the face. White, pupil and line are drawn in their own colour, untouched by the light (as the voxel face has
them); lid and brow are lit like the skin they are part of.
"""
import numpy as np
import body as lb, heads as hd

CX = lb.CX
LIFT = 0.04                      # how far the eye's polygons stand off the face
EYES = ("left", "right")         # SCREEN left and right, as the game names them: "left" is the figure's own right eye


# ------------------------------------------------------------------------------------------- flat geometry ---
# An eye is worked out flat first, in its own box: x from the eye's OUTER edge (0 to the box's width), r up from its
# bottom row (0 to the box's height, and one more row for a raised brow).

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


def _runs(drawing, w, h):
    """The painted cells of the open eye, column by column, with its one-cell steps eased into diagonals.
    Returns {column: [(bottom row, top, bottom line, top line)]}; a line is its height at the column's two sides."""
    has = lambda c, r: (c, r) in drawing
    out = {}
    for c in range(w):
        rows = sorted(r for (cc, r) in drawing if cc == c)
        runs = []
        for r in rows:
            if runs and runs[-1][1] == r: runs[-1][1] = r + 1
            else: runs.append([r, r + 1])
        made = []
        for a, b in runs:
            bottom = [float(a), float(a)]; top = [float(b), float(b)]
            # the outline steps down one cell into the next column, and this bottom edge is one cell long: a diagonal
            for side, n, far in ((0, c - 1, c + 1), (1, c + 1, c - 1)):
                if has(n, a - 1) and has(n, a) and not has(n, a - 2) and not has(far, a): bottom[side] = float(a - 1)
                if has(n, b) and has(n, b - 1) and not has(n, b + 1) and not has(far, b - 1): top[side] = float(b + 1)
            made.append((a, b, tuple(bottom), tuple(top)))
        out[c] = made
    return out


def look_at(drawing, dc, dy):
    """The open eye with its pupil moved dc columns (counted from the eye's outer edge) and dy rows: pupil cells move
    onto white cells only, as the game moves them."""
    if not dc and not dy: return dict(drawing)
    out = dict(drawing)
    pupils = [k for k, role in out.items() if role == "pupil"]
    for k in pupils: out[k] = "white"
    for c, r in pupils:
        if out.get((c + dc, r + dy)) == "white": out[(c + dc, r + dy)] = "pupil"
    return out


def eased(drawing, state, eye, w, h):
    """One eye, eased, as flat pieces [(polygon, role)]. drawing: {(c, r): role}, the open eye; state: the game's five
    numbers for this eye (upper lid rows, lower lid rows, pupil dx in screen terms, pupil dy, tilt)."""
    upper, lower, dx, dy, tilt = (float(v) for v in state)
    drawing = look_at(drawing, int(dx) if eye != "right" else -int(dx), int(dy))
    runs = _runs(drawing, w, h)
    raw = lambda x: upper + tilt * (x - 0.5) / (w - 1)              # the lid's depth: the game's steps, as one slope
    depth = lambda x: float(np.clip(raw(x), 0.0, h))
    cuts = set(float(c) for c in range(w + 1))
    if tilt:
        for level in (0.0, float(h)):                               # where the slope runs out at the top or bottom of the box
            x = 0.5 + (level - upper) * (w - 1) / tilt
            if 1e-6 < x < w - 1e-6: cuts.add(float(x))
    cuts = sorted(cuts)
    pieces = []
    for xa, xb in zip(cuts[:-1], cuts[1:]):
        c = int(np.floor(0.5 * (xa + xb)))
        box = [(xa, -1.0), (xb, -1.0), (xb, h + 2.0), (xa, h + 2.0)]
        lid_b = ((xa, h - depth(xa)), (xb, h - depth(xb)))          # the lid's edge, which is also the bottom of the brow
        lid_t = ((xa, lid_b[0][1] + 1.0), (xb, lid_b[1][1] + 1.0))
        level = lambda r: ((xa, r), (xb, r))
        at = lambda line, x: line[0] + (line[1] - line[0]) * (x - c)
        pieces.append((_clip(_clip(box, *lid_b, True), *lid_t, False), "brow"))    # the full width of the eye, painted or not
        for a, b, bottom, top in runs[c]:
            edge_b = ((xa, at(bottom, xa)), (xb, at(bottom, xb))); edge_t = ((xa, at(top, xa)), (xb, at(top, xb)))
            run = _clip(_clip(box, *edge_b, True), *edge_t, False)
            pieces.append((_clip(run, *lid_t, True), "lid"))                                            # the upper lid, above the brow
            pieces.append((_clip(_clip(run, *level(lower), False), *lid_b, False), "lid"))              # the lower lid
            seen = _clip(_clip(run, *level(lower), True), *lid_b, False)                                # the eye between the lids
            for k in range(a, b):
                part = seen
                if k > a: part = _clip(part, *level(float(k)), True)
                if k < b - 1: part = _clip(part, *level(float(k + 1)), False)
                pieces.append((part, drawing[(c, k)]))
    return merge(pieces)


def cells(applied):
    """One eye as the game's own cells, each a unit square: [(polygon, role)]. applied: [[c, r, role]]."""
    return merge([([(c, r), (c + 1, r), (c + 1, r + 1), (c, r + 1)], role) for c, r, role in applied])


def role_at(pieces, x, r):
    """The role drawn at a point of the eye's box, or None."""
    for poly, role in pieces:
        inside = True
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            if (b[0] - a[0]) * (r - a[1]) - (b[1] - a[1]) * (x - a[0]) < -1e-9: inside = False; break
        if inside: return role
    return None


# --------------------------------------------------------------------------------------------- on the head ---

def place(pieces, eye, box, bend=None, lift=LIFT):
    """Flat pieces of one eye onto its patch of the head: [(polygon in 3D, role)]."""
    x0 = float(box["x0"]); z0 = float(box["z0"])
    out = []
    for poly, role in pieces:
        pts = []
        for x, r in poly:
            X = x0 + x if eye == "left" else 2.0 * CX - x0 - x
            pts.append([X, hd.face_y(X, bend) - lift, z0 + r])
        pts = np.array(pts)
        n = np.zeros(3)
        for i in range(len(pts)):
            n += np.cross(pts[i], pts[(i + 1) % len(pts)])
        out.append((pts[::-1].copy() if n[1] > 0 else pts, role))     # facing forward
    return out


def drawing_of(eye_set, eye):
    return {(int(c), int(r)): role for c, r, role in eye_set["eye"][eye]}


def eyes(tables, wardrobe, eye_set="standard", colourway="default", lids=None, skin=None, hair=None, brow=None,
         style="eased", bend=None):
    """Both eyes on a head: [dict(pts, rgb, role, unlit)].
    lids: a lid state's name (the game's default if None), or "" for the eye as drawn, with no lids and no brow.
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
        if lids == "":
            pieces = cells([[c, r, role] for (c, r), role in drawing_of(es, eye).items()]) if style == "cells" \
                else eased(drawing_of(es, eye), [0, 0, 0, 0, 0], eye, w, h)
            pieces = [(p, role) for p, role in pieces if role != "brow"]
        elif style == "cells":
            pieces = cells(t["applied"][eye_set][lids][eye])
        else:
            pieces = eased(drawing_of(es, eye), t["states"][lids][i], eye, w, h)
        for pts, role in place(pieces, eye, box, bend):
            out.append(dict(pts=pts, rgb=colour[role], role=role, unlit=role in flat))
    return out
