"""Shapes of their own, fixed at a place on the figure: the long beard, the ponytail, the bun, horns and pauldrons.

The owner's choice (2026-11): fixed types, each with a few settings, rather than a drawing. The voxel figure drew these
as cells in a 17 by 7 by 21 box; that drawing has no low-poly form, and the comparison the owner chose from is
renders/drawn_shapes.png.

Every type is built the same way underneath: its settings give a few cross-sections (each an oval: where it is, how
wide, how thick), and the sections are joined into one closed low-poly piece (a loft); a section with no width is a
point, a tip. Where a section is, is given in its anchor's own directions:
  a   across, toward the figure's left (outward, at a shoulder)
  b   out from the anchor (down under the chin, back from the back of the head, up from the crown, forward from the brow,
      up from a shoulder)
  c   the anchor's third direction (forward under the chin, up at the back of the head and the brow, back at the crown,
      forward at a shoulder)

  long_beard  under the chin, hanging down: length, width, point (blunt to pointed), jut (how far forward it comes)
  ponytail    from the back of the head: height (from the nape up to the crown), length, thickness, and a tie in its own
              colour
  bun         on the head: position (top, back or nape), size
  horns       a pair, from the brow: length, curve (straight up to swept back), spread, thickness
  pauldrons   a pair, on the shoulders: size, drop (how far down the arm)

A beard and a ponytail's tail stand clear of what they hang over (the chest, the back, the hair). A beard, a tail and
a bun follow the head; horns the head; a pauldron bends between the chest and its upper arm (an arm is one rigid piece
at the shoulder, so a pauldron following it alone turns under the armpit when the arm goes overhead).

The game builds the same types (core/lowpoly/lowpoly_drawn.gd), checked against this corner by corner (expected.py).
"""
import numpy as np
import body as lb
import heads
import hood as hd

CX, CY = lb.CX, lb.CY
SIDES = 8                       # points round every section
CLEAR = 0.35                    # how far a beard or a tail stays off what it hangs over

X, Y, Z = np.eye(3)
TYPES = ("long_beard", "ponytail", "bun", "horns", "pauldrons")
ROLES = {"long_beard": ("hair",), "ponytail": ("hair", "tie"), "bun": ("hair",), "horns": ("horn",), "pauldrons": ("plate",)}


def _unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


# ----------------------------------------------------------------------------------------------- anchors ---

def _head_back(m, zh):
    """The back of the dressed head on the middle line, at a head height: the point, and the head's directions there."""
    return np.array([CX, CY + m.head(np.pi, zh), zh + m.dz]), X, Y, Z


def _chin(m):
    front = m.head_rings[heads.RING_Z.index(26.0)][1][0]
    return front + np.array([0.0, 1.2, 0.0]), X, -Z, -Y


def _crown(m):
    return m.crown_top, X, Z, Y


def _brow(m):
    return m.head_rings[heads.RING_Z.index(37.0)][1][0], X, -Y, Z


def _shoulder(fit, side):
    """The top of the arm, on the dressed figure: its middle, at the arm's highest corner."""
    s = 1.0 if side == "L" else -1.0
    pts = np.array([v for q in fit._polys if q["piece"] == "arm_" + side and not q["hidden"] for v in q["pts"]])
    top = pts[pts[:, 2] > pts[:, 2].max() - 0.6]
    o = top.mean(axis=0); o[2] = pts[:, 2].max()
    return o, s * X, Z, -Y


# ------------------------------------------------------------------------------------------------- types ---

def _sec(a, b, c, w, t, role):
    return dict(a=float(a), b=float(b), c=float(c), w=max(0.0, float(w)), t=max(0.0, float(t)), role=role)


BEARD_ROWS = (0.15, 0.4, 0.65, 0.88, 1.0)  # where the beard's sections are, as shares of its length


def long_beard(p):
    """Sections, in the chin's directions (b down, c forward). Its jut is added once it stands clear of the chest
    (jut_beard), so that it shows on every chest."""
    length = 2.0 + 2.0 * int(np.clip(int(p["length"]), 1, 5))
    width = 5.0 + 1.5 * int(np.clip(int(p["width"]), 1, 4))
    point = int(np.clip(int(p["point"]), 0, 3))
    end = 0.55 * (1.0 - point / 3.0)                                 # the bottom's width, against the top's
    out = [_sec(0, -0.6, -0.8, width, 5.6, "hair")]
    for f in BEARD_ROWS:
        w = width * (1.0 - (1.0 - end) * f ** 1.2); t = max(1.2, 4.4 * (1.0 - 0.55 * f))
        if f == 1.0 and point == 3: w = t = 0.0
        out.append(_sec(0, length * f, -0.8 + 0.8 * (1.0 - (1.0 - f) ** 2), w, t, "hair"))
    return out


def jut_beard(sections, p):
    """Bring the beard forward by its jut, most at the bottom."""
    jut = int(np.clip(int(p["jut"]), 0, 3))
    for s, f in zip(sections[1:], BEARD_ROWS):
        s["c"] += 0.6 * jut * (1.0 - (1.0 - f) ** 2)
    return sections


def ponytail(p):
    """Sections, in the directions of the back of the head (b back, c up), from where the tail is tied."""
    length = 4.0 + 2.5 * int(np.clip(int(p["length"]), 1, 5))
    W = 2.4 + 0.8 * int(np.clip(int(p["thickness"]), 1, 3))
    root = "tie" if bool(p["tie"]) else "hair"
    path = [(-0.6, 0.0, 0.6, 0.55, root), (0.5, -0.1, 0.65, 0.6, "hair"), (1.4, -0.55, 0.95, 0.75, "hair"),
            (1.9, -0.3 * length, 1.0, 0.75, "hair"), (1.5, -0.58 * length, 0.85, 0.65, "hair"),
            (0.6, -0.82 * length, 0.55, 0.45, "hair"), (0.0, -length, 0.0, 0.0, "hair")]
    return [_sec(0, b, c, W * w, W * t, role) for b, c, w, t, role in path]


def bun(p):
    """Sections along the way out of the head (b), round."""
    R = 1.6 + 0.5 * int(np.clip(int(p["size"]), 1, 3))
    c = 1.2 if str(p["position"]) == "top" else 0.0                  # on top, a little toward the back
    return [_sec(0, b * R, c, w * R, w * R, "hair") for b, w in ((-0.5, 1.2), (0.2, 1.85), (0.9, 2.0), (1.55, 1.5), (1.95, 0.0))]


def horns(p):
    """Sections of the left horn, in the brow's directions (b forward, c up); the right one is its mirror."""
    length = 2.0 + 1.5 * int(np.clip(int(p["length"]), 1, 5))
    curve = int(np.clip(int(p["curve"]), 0, 3)); spread = int(np.clip(int(p["spread"]), 0, 3))
    D = 1.0 + 0.4 * int(np.clip(int(p["thickness"]), 1, 3))
    at = np.array([3.0 + 0.5 * spread, -1.4, 0.4])
    out = []; steps = 5
    for i in range(steps + 1):
        u = i / steps
        out.append(_sec(at[0], at[1], at[2], D * (1.0 - u) ** 0.9, D * (1.0 - u) ** 0.9, "horn"))
        back = np.radians(30.0 * curve) * (u + 0.5 / steps)          # it turns back as it grows
        at = at + (length / steps) * _unit(np.array([0.12 * spread, -np.sin(back), np.cos(back)]))
    return out


def pauldrons(p):
    """Sections of the left pauldron, in the shoulder's directions (a outward, b up, c forward); its width runs
    front to back (c), its thickness is square to that."""
    k = 0.8 + 0.15 * int(np.clip(int(p["size"]), 1, 3)); drop = int(np.clip(int(p["drop"]), 0, 3))
    rows = [(-1.2, 0.6, 5.4, 1.2), (0.6, 1.5, 7.0, 2.2), (2.4, 1.1, 7.2, 2.2), (3.4, -0.3 - 0.5 * drop, 6.8, 1.8),
            (3.9, -1.4 - 0.9 * drop, 5.8, 1.4), (4.0, -2.0 - 1.1 * drop, 4.6, 1.0)]
    return [_sec(a * k, b, 0, w * k, t, "plate") for a, b, w, t in rows]


SECTIONS = {"long_beard": long_beard, "ponytail": ponytail, "bun": bun, "horns": horns, "pauldrons": pauldrons}
WIDTH_AXIS = {"pauldrons": "c"}          # which of the anchor's directions a section's width follows (else a)


# -------------------------------------------------------------------------------------------- the loft ---

def _centre(frame, s, sign=1.0):
    origin, A, B, C = frame
    return origin + sign * s["a"] * A + s["b"] * B + s["c"] * C


def stand_clear(sections, frame, P, along, first):
    """Move each section from the first on out along one of the anchor's directions ("b" or "c") until it stands CLEAR
    of every corner P beside it: those within its width across (x) and a unit of its height."""
    origin, A, B, C = frame
    D = {"b": B, "c": C}[along]
    for s in sections[first:]:
        if s["w"] <= 0.0: continue
        ctr = _centre(frame, s)
        near = P[(np.abs(P[:, 2] - ctr[2]) <= 1.0) & (np.abs(P[:, 0] - ctr[0]) <= 0.5 * s["w"])]
        if len(near) == 0: continue
        need = float((near @ D).max()) + 0.5 * s["t"] + CLEAR - float(ctr @ D)
        if need > 0.0: s[along] += need
    return sections


def loft(sections, frame, colours, follows, width_axis="a", sign=1.0):
    """The closed piece through the sections. frame: (origin, a, b, c). follows: for every section, the parts its
    corners follow and how much. sign -1 mirrors it across (a). Returns [polygon dicts: pts, rgb, shares, part]."""
    origin, A, B, C = frame
    across = {"a": sign * A, "c": C}[width_axis]
    cs = [_centre(frame, s, sign) for s in sections]
    n = len(cs); rings = []
    for i in range(n):
        T = _unit(cs[min(i + 1, n - 1)] - cs[max(i - 1, 0)])
        Xs = _unit(across - (across @ T) * T); Ys = np.cross(T, Xs)
        w, t = 0.5 * sections[i]["w"], 0.5 * sections[i]["t"]
        if w <= 1e-9 and t <= 1e-9:
            rings.append([cs[i]])
        else:
            rings.append([cs[i] + w * np.cos(f) * Xs + t * np.sin(f) * Ys for f in (2.0 * np.pi * (k + 0.5) / SIDES for k in range(SIDES))])
    part = max(follows[0], key=follows[0].get)
    polys = []

    def put(pts, shares, rgb, centre):
        pts = np.array(pts); nrm = np.zeros(3)
        for i in range(len(pts)): nrm += np.cross(pts[i], pts[(i + 1) % len(pts)])
        if nrm @ (pts.mean(axis=0) - centre) < 0: pts = pts[::-1].copy(); shares = shares[::-1]
        polys.append(dict(pts=pts, rgb=rgb, shares=list(shares), part=part))

    grey = (128, 128, 128)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]; rgb = colours.get(sections[i]["role"], grey)
        mid = 0.5 * (cs[i] + cs[i + 1]); fa, fb = follows[i], follows[i + 1]
        if len(a) == 1 and len(b) == 1: continue
        if len(a) == 1 or len(b) == 1:
            tip, rim, ft, fr = (a[0], b, fa, fb) if len(a) == 1 else (b[0], a, fb, fa)
            for k in range(SIDES): put([tip, rim[k], rim[(k + 1) % SIDES]], [ft, fr, fr], rgb, mid)
            continue
        for k in range(SIDES):
            put([a[k], a[(k + 1) % SIDES], b[(k + 1) % SIDES], b[k]], [fa, fa, fb, fb], rgb, mid)
    for i, beyond in ((0, 1), (n - 1, n - 2)):                       # close the ends that are not points
        if len(rings[i]) > 1:
            put(rings[i], [follows[i]] * SIDES, colours.get(sections[i]["role"], grey), cs[beyond])
    return polys


def build(fit, kind, params, colours, name=None):
    """A shape of one of the TYPES on the dressed figure. Returns ([polygon dicts], notes)."""
    import specials
    p = specials.settings(kind, params)
    name = name or kind
    info = fit.body.get("info", {})
    if kind != "pauldrons" and info.get("head") is None:
        return [], [f"{name}: no head to put it on"]
    sections = SECTIONS[kind](p)
    corners = lambda head: np.array([v for q in fit._polys if not q["hidden"] and (head or q["piece"] != "head") for v in q["pts"]])
    if kind == "pauldrons":
        polys = []
        for side in ("L", "R"):
            frame = _shoulder(fit, side)
            follows = []
            for s in sections:                                       # inner end mostly with the chest, outer with the arm
                f = float(np.clip(0.35 + 0.12 * s["a"], 0.2, 0.85))
                follows.append({"upper_arm_" + side: f, "chest": 1.0 - f})
            polys += loft(sections, frame, colours, follows, "c")
        return polys, []
    m = hd._Measure(fit)
    head = [{"head": 1.0}] * len(sections)
    if kind == "long_beard":
        frame = _chin(m)
        stand_clear(sections, frame, corners(False), "c", 1)        # in front of the chest: the jaw is its own
        return loft(jut_beard(sections, p), frame, colours, head), []
    if kind == "ponytail":
        frame = _head_back(m, 29.0 + 2.5 * int(np.clip(int(p["height"]), 0, 3)))
        stand_clear(sections, frame, corners(True), "b", 3)         # behind the back and the hair: the tie is in the hair
        return loft(sections, frame, colours, head), []
    if kind == "bun":
        where = str(p["position"])
        frame = _crown(m) if where == "top" else _head_back(m, 35.0 if where == "back" else 29.5)
        return loft(sections, frame, colours, head), []
    frame = _brow(m)                                                 # horns: the left one and its mirror
    return loft(sections, frame, colours, head) + loft(sections, frame, colours, head, sign=-1.0), []
