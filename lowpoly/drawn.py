"""Drawn shapes as polygons: a first pass, made so the owner can choose how drawn shapes are made on the low-poly figure.

A drawn shape is fixed at an anchor on the figure and has a form of its own: a long beard under the chin, a
ponytail's tail at the nape, a bun, horns, a pauldron. On the voxel figure the form was a small drawing in cells
(17 by 7 by 21). Here the form is a loft: a few cross-sections, each an oval (where it is, how wide, how thick), joined
into one low-poly piece and closed at both ends; a section with no width is a point (a tip).

Where a section is, is given in the anchor's own directions, as the cells were:
  a   across, toward the figure's left
  b   out from the anchor (down under the chin, back from the nape, up from the crown, ...)
  c   along: the anchor's third direction (forward under the chin, up at the nape, ...)

Two ways to get the sections, shown side by side for the owner:
  from_cells   the old drawing, read slice by slice along its longest direction: each slice's width and thickness
               become a section. "stepped" keeps every step of the drawing; "smooth" puts one section in the middle
               of each slice, so the piece tapers smoothly between them.
  by hand      a short list of sections, chosen for the look.

Mirror: a shape whose sections stand off the middle line is copied to the other side; at a side anchor (shoulder, hip,
wrist, ankle) the copy goes to the other limb. Wrap (follow the surface) is not done in this first pass.
"""
import numpy as np
import body as lb
import heads
import hood as hd

CX, CY = lb.CX, lb.CY
SIDES = 8                       # points round every section

X, Y, Z = np.eye(3)


def _unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def anchor(fit, name, side="L"):
    """Where an anchor is on the dressed figure: (origin, a, b, c directions, the part it follows)."""
    m = hd._Measure(fit); dz = m.dz
    s = 1.0 if side == "L" else -1.0

    def ring(z):                                                     # one of the dressed head's rings, by its height
        return m.head_rings[heads.RING_Z.index(z)][1]

    if name == "chin":
        front = ring(26.0)[0]
        return front + np.array([0.0, 1.2, 0.0]), X, -Z, -Y, "head"
    if name == "nape":
        return ring(29.0)[7], X, Y, Z, "head"
    if name == "crown":
        return m.crown_top, X, Z, Y, "head"
    if name == "brow":
        return ring(37.0)[0], X, -Y, Z, "head"
    if name == "face":
        return 0.5 * (ring(31.0)[0] + ring(29.0)[0]), X, -Y, Z, "head"
    torso = lambda z, i: fit.at(fit.ring(min(fit.heights(lb.BANDS), key=lambda h: abs(h - z)))[i])
    if name in ("chest", "back"):
        z = sum(fit.band("upper_chest")) / 2
        return (torso(z, 0), X, -Y, Z, "chest") if name == "chest" else (torso(z, 4), X, Y, Z, "chest")
    if name in ("waist_front", "waist_back"):
        z = sum(fit.band("waist")) / 2
        return (torso(z, 0), X, -Y, Z, "pelvis") if name == "waist_front" else (torso(z, 4), X, Y, Z, "pelvis")
    if name == "hip":
        z = sum(fit.band("hips")) / 2
        p = torso(z, 2 if side == "L" else 6)
        return p, -Y, s * X, Z, "pelvis"
    limb = {"shoulder": "arm", "wrist": "arm", "ankle": "leg"}[name]
    piece = ("arm_" + side) if limb == "arm" else "skin"
    pts = np.array([v for q in fit._polys if q["piece"] == piece and not q["hidden"] for v in q["pts"]])
    if name == "shoulder":
        top = pts[pts[:, 2] > pts[:, 2].max() - 0.6]
        o = top.mean(axis=0); o[2] = pts[:, 2].max()
        return o, s * X, Z, -Y, "upper_arm_" + side
    if name == "wrist":
        z0, z1 = fit.band("wrist")
        band = pts[(pts[:, 2] >= z0 - 1e-6) & (pts[:, 2] <= z1 + 1e-6)]
        o = band.mean(axis=0); o[0] = band[:, 0].max() if side == "L" else band[:, 0].min()
        return o, -Y, s * X, -Z, "forearm_" + side
    z0, z1 = fit.band("ankle")
    band = pts[(pts[:, 2] >= z0 - 1e-6) & (pts[:, 2] <= z1 + 1e-6) & ((pts[:, 0] > CX) == (side == "L"))]
    o = band.mean(axis=0); o[0] = band[:, 0].max() if side == "L" else band[:, 0].min()
    return o, -Y, s * X, Z, "shin_" + side


def from_cells(cells, along, smooth=False):
    """Sections from an old cell drawing ([a, b, c, role]; mirrored about a = 0 as the old drawings were).
    along: "b" or "c", the drawing's long direction. Returns [dict(a, b, c, w, t, role)]."""
    other = "c" if along == "b" else "b"
    col = {"a": 0, "b": 1, "c": 2}
    slices = {}
    for cell in cells:
        if int(cell[1]) < 0: continue                                # b = -1 recoloured the surface: nothing to build
        slices.setdefault(int(cell[col[along]]), []).append(cell)
    # moved to touch the anchor: the old drawings were placed against the voxel head, and read here as they were,
    # a tail drawn from b = 1 floats a unit off the low-poly head
    gap = min(int(c[1]) for c in cells if int(c[1]) >= 0)
    out = []
    for k in sorted(slices):
        cs = slices[k]
        amax = max(int(c[0]) for c in cs) + 1
        lo = min(int(c[col[other]]) for c in cs); hi = max(int(c[col[other]]) for c in cs) + 1
        roles = [str(c[3]) for c in cs]; role = max(set(roles), key=roles.count)
        shift = {"b": -gap, "c": 0.0}
        sec = lambda at: {"a": 0.0, along: float(at) + shift[along], other: 0.5 * (lo + hi) + shift[other], "w": 2.0 * amax,
                          "t": float(hi - lo), "role": role}
        if smooth:
            out.append(sec(k + 0.5))
        else:
            out += [sec(k), sec(k + 1)]
    if smooth and out:                                               # flat ends, at the drawing's own ends
        first = dict(out[0]); first[along] -= 0.5; last = dict(out[-1]); last[along] += 0.5
        out = [first] + out + [last]
    merged = []                                                      # stepped: drop sections that only repeat a run
    for i, s in enumerate(out):
        if 0 < i < len(out) - 1 and all(abs(out[i - 1][k] - s[k]) < 1e-9 and abs(out[i + 1][k] - s[k]) < 1e-9 for k in ("w", "t", other)):
            if s["role"] == out[i - 1]["role"] == out[i + 1]["role"]: continue
        merged.append(s)
    return merged


def loft(sections, frame, colours, mirror=False):
    """The piece through the sections. frame: (origin, a, b, c, part). Returns [polygon dicts: pts, rgb, shares, part]."""
    origin, A, B, C, part = frame
    polys = []
    copies = [1.0] + ([-1.0] if mirror and any(abs(s["a"]) > 1e-6 for s in sections) else [])
    for sign in copies:
        cs = [origin + sign * s["a"] * A + s["b"] * B + s["c"] * C for s in sections]
        n = len(cs); rings = []
        for i in range(n):
            T = _unit(cs[min(i + 1, n - 1)] - cs[max(i - 1, 0)])
            Xs = _unit(A - (A @ T) * T)
            if np.linalg.norm(Xs) < 1e-6: Xs = _unit(B - (B @ T) * T)
            Ys = np.cross(T, Xs)
            w, t = 0.5 * sections[i]["w"], 0.5 * sections[i]["t"]
            if w < 1e-6 and t < 1e-6:
                rings.append([cs[i]])
            else:
                rings.append([cs[i] + w * np.cos(f) * Xs + t * np.sin(f) * Ys for f in (2 * np.pi * (k + 0.5) / SIDES for k in range(SIDES))])
        if part.startswith("upper_arm_"):                            # at the shoulder: bend between the chest and the arm, inner
            follows = []                                             # end mostly with the chest (an arm is one rigid piece, so
            for s in sections:                                       # following it alone turns a pauldron under the armpit)
                f = float(np.clip(0.35 + 0.12 * s["a"], 0.2, 0.85))
                follows.append({part: f, "chest": 1.0 - f})
        else:
            follows = [{part: 1.0}] * n
        at = {}
        for i, r in enumerate(rings):
            for v in r: at[tuple(np.round(v, 6))] = follows[i]

        def put(pts, rgb, centre):
            pts = np.array(pts); nrm = np.zeros(3)
            for i in range(len(pts)): nrm += np.cross(pts[i], pts[(i + 1) % len(pts)])
            if nrm @ (pts.mean(axis=0) - centre) < 0: pts = pts[::-1].copy()
            polys.append(dict(pts=pts, rgb=rgb, shares=[at[tuple(np.round(v, 6))] for v in pts], part=part))

        for i in range(n - 1):
            a, b = rings[i], rings[i + 1]; rgb = colours.get(sections[i]["role"], (128, 128, 128))
            mid = 0.5 * (cs[i] + cs[i + 1])
            if len(a) == 1 and len(b) == 1: continue
            if len(a) == 1 or len(b) == 1:
                tip, rim = (a[0], b) if len(a) == 1 else (b[0], a)
                for k in range(SIDES): put([tip, rim[k], rim[(k + 1) % SIDES]], rgb, mid)
                continue
            for k in range(SIDES):
                q = [a[k], a[(k + 1) % SIDES], b[(k + 1) % SIDES], b[k]]
                if np.linalg.norm(q[0] - q[3]) + np.linalg.norm(q[1] - q[2]) < 1e-9: continue
                put(q, rgb, mid)
        for i, beyond in ((0, 1), (n - 1, n - 2)):                   # close the ends that are not points
            if len(rings[i]) > 1:
                put(rings[i], colours.get(sections[i]["role"], (128, 128, 128)), cs[beyond])
    return polys


ALONG = {"chin": "b", "nape": "c"}     # the old drawings' long direction at these anchors; elsewhere the longest one


def shape(fit, params, colours, name="shape"):
    """The drawn shape special. Its sections come from params["sections"] if it has them (a first-pass setting, not in
    the game's table yet), else from its cell drawing. Returns ([polygon dicts], notes)."""
    import specials
    p = specials.settings("shape", params)
    where = str(p["anchor"])
    try:
        frame = anchor(fit, where)
    except (KeyError, ValueError, IndexError):
        return [], [f"{name}: anchor '{where}' is not on this figure"]
    sections = (params or {}).get("sections")
    if not sections:
        cells = p["cells"] or []
        if not cells: return [], [f"{name}: the drawing is empty"]
        along = ALONG.get(where)
        if along is None:
            span = lambda i: max(int(c[i]) for c in cells) - min(int(c[i]) for c in cells)
            along = "b" if span(1) >= span(2) else "c"
        sections = from_cells(cells, along, smooth=(params or {}).get("from_cells", "smooth") == "smooth")
    side = where in ("shoulder", "hip", "wrist", "ankle")            # mirrored there: the same on the other limb
    polys = loft(sections, frame, colours, mirror=bool(p["mirror"]) and not side)
    if bool(p["mirror"]) and side:
        polys += loft(sections, anchor(fit, where, "R"), colours)
    return polys, []
