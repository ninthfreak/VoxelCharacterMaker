"""Posing the figure.

The body is one skin that bends (owner's decision): each corner follows one part or shares several, as the body file
says (body.py: joints), and moves by the blend of their movements. That is plain blended skinning, which is what
Godot's Skeleton3D does.

Clothing moves in one of three ways:

  bend    a garment lifted off the body follows the corners it was lifted from, and a shape that lies on the body
          (straps) follows the part it lies on. Both bend with the body.
  hang    a skirt or a cape is hanging cloth: it is laid afresh for every pose (hang.py).
  rigid   every part's share of a garment is a closed piece that turns as a whole, with a rounded end on each open
          loop so that bent joints overlap instead of gaping (posed_rigid). It was compared with the bending skin for
          the body and lost (renders/joints_rigid_or_bend.png); it is kept because some clothing, such as hard
          pieces, may need to stay rigid. Nothing uses it yet.
"""
import numpy as np
import body as lb
import hang

CX, CY = lb.CX, lb.CY
ORDER = ["pelvis", "chest", "head", "upper_arm_L", "upper_arm_R", "forearm_L", "forearm_R", "thigh_L", "thigh_R", "shin_L", "shin_R"]


def _rx(deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def _ry(deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def _rz(deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def transforms(pose, pivots):
    """pose: {part: {"fwd": deg, "side": deg, "turn": deg}}. fwd swings the part's far end forward (a knee bend is a
    negative fwd on the shin), side lifts a limb out to its own side, turn twists it to the figure's left.
    Returns {part: (A, t)} with posed = A @ rest + t."""
    out = {}
    for part in ORDER:
        p = pose.get(part, {}); piv = np.array(pivots[part], float)
        hangs = part not in ("chest", "head", "pelvis")              # limbs hang below their pivot
        side_sign = -1.0 if part.endswith("_L") else 1.0
        # the game's order (Godot turns a part about its Y, then X, then Z): turn, then forward, then sideways
        R = _rz(p.get("turn", 0.0)) @ _rx((-1.0 if hangs else 1.0) * p.get("fwd", 0.0)) @ _ry(side_sign * p.get("side", 0.0))
        t = piv - R @ piv
        parent = lb.PARENT[part]
        if parent is None:
            out[part] = (R, t)
        else:
            Ap, tp = out[parent]
            out[part] = (Ap @ R, Ap @ t + tp)
    return out


def from_game(parts):
    """A pose as the game writes it (runtime/poses.gd: degrees about Godot's X, Y and Z for each part), in the terms
    used here. Godot's X swings a hanging limb forward and leans an upright part back; its Z moves a hanging limb to
    the figure's right."""
    out = {}
    for part, (x, y, z) in parts.items():
        hangs = part not in ("chest", "head", "pelvis")
        out[part] = {"fwd": x if hangs else -x, "turn": y, "side": -z if part.endswith("_L") else z}
    return out


# ------------------------------------------------------------------------------------------------- bending ---

def _bent(q, T):
    return np.array([sum(share * (T[part][0] @ v + T[part][1]) for part, share in w.items()) for v, w in zip(q["pts"], q["shares"])])


def posed_bend(body, polys, pose):
    """polys: dicts with pts and shares (a Look's polys). Returns [(polygon, rgb)] with every corner moved by its
    shares."""
    T = transforms(pose, body["pivots"])
    return [(_bent(q, T), q["rgb"]) for q in polys]


def laid(body, look, pose):
    """A dressed figure (dress.Look) in a pose, in its two kinds: the polygons that bend, each as (its record, its
    posed corners), and each hanging cloth as (the cloth, its polygons [(polygon, role)]). A cloth is laid over the
    posed figure and over the cloths before it."""
    T = transforms(pose, body["pivots"])
    bent = [(q, _bent(q, T)) for q in look.polys]
    under = [(q, pts, q["pts"][:, 2]) for q, pts in bent]
    cloths = []
    for cloth in look.cloths:
        sel = [(pts, z0) for q, pts, z0 in under if cloth.over(q)]
        P = np.concatenate([a for a, _ in sel]) if sel else np.zeros((0, 3))
        Z0 = np.concatenate([b for _, b in sel]) if sel else np.zeros(0)
        made = hang.lay(cloth, T, P, Z0)
        cloths.append((cloth, made))
        tag = dict(piece="cloth:" + cloth.name, band=None, hidden=False)
        under += [(tag, pts, np.full(len(pts), -1.0)) for pts, _ in made]
    return bent, cloths


def posed(body, look, pose):
    """A dressed figure in a pose, to draw: [(polygon, rgb)]."""
    bent, cloths = laid(body, look, pose)
    return [(pts, q["rgb"]) for q, pts in bent] + [(pts, cloth.colours[role]) for cloth, made in cloths for pts, role in made]


# --------------------------------------------------------------------------------------------------- rigid ---

def _loops(edges):
    """Chain open edges {(a, b)} (keys of corners) into closed loops of corner keys."""
    nxt = {}
    for a, b in edges:
        nxt.setdefault(a, []).append(b); nxt.setdefault(b, []).append(a)
    seen = set(); loops = []
    for start in nxt:
        if start in seen or len(nxt[start]) != 2: continue
        loop = [start]; seen.add(start); prev = None; cur = start
        while True:
            a, b = nxt[cur]
            step = a if a != prev else b
            if step == start or step in seen or len(nxt.get(step, [])) != 2: break
            loop.append(step); seen.add(step); prev, cur = cur, step
        if len(loop) >= 3: loops.append(loop)
    return loops


def rounded_ends(polys):
    """For one part: close every open loop of its surface with a rounded end, bulging away from the part.
    polys: [dict(pts, rgb)]. Returns extra [(polygon, rgb)]."""
    key = lambda v: tuple(np.round(v, 4))
    count = {}; colour = {}; pos = {}
    for q in polys:
        p = q["pts"]
        for i in range(len(p)):
            a, b = key(p[i]), key(p[(i + 1) % len(p)])
            if a == b: continue
            e = (a, b) if a < b else (b, a)
            count[e] = count.get(e, 0) + 1; colour[e] = q["rgb"]; pos[a] = p[i]; pos[b] = p[(i + 1) % len(p)]
    open_edges = [e for e, n in count.items() if n == 1]
    if not open_edges: return []
    centre = np.mean([q["pts"].mean(axis=0) for q in polys], axis=0)
    extra = []
    for loop in _loops(open_edges):
        pts = np.array([pos[k] for k in loop])
        # a loop that touches the centre line twice is two openings side by side (the pelvis's two leg openings)
        on = [i for i, p in enumerate(pts) if abs(p[0] - CX) < 1e-6]
        groups = [pts]
        if len(on) == 2 and (pts[:, 0].max() - CX) > 0.5 and (CX - pts[:, 0].min()) > 0.5:
            i, j = on
            groups = [pts[i:j + 1], np.concatenate([pts[j:], pts[:i + 1]])]
        rgb = colour[(loop[0], loop[1]) if loop[0] < loop[1] else (loop[1], loop[0])]
        for g in groups:
            c = g.mean(axis=0); u = c - centre; u /= max(np.linalg.norm(u), 1e-9)
            depth = 0.6 * np.mean(np.linalg.norm(g - c, axis=1))
            rings = [g] + [c + np.cos(np.radians(a)) * (g - c) + np.sin(np.radians(a)) * depth * u for a in (35.0, 68.0)]
            n = len(g)
            for a, b in zip(rings[:-1], rings[1:]):
                for k in range(n):
                    extra.append((np.array([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]]), rgb))
            extra.append((rings[-1].copy(), rgb))                    # a small flat tip
    return extra


def posed_rigid(body, polys, pose):
    """polys: dress(..., detail=True). Every part moves as one piece, with rounded ends on every open loop.
    Returns ([(polygon, rgb)], number of polygons the rounded ends added)."""
    T = transforms(pose, body["pivots"])
    out = []; added = 0
    for part in ORDER:
        mine = [q for q in polys if q["part"] == part]
        if not mine: continue
        A, t = T[part]
        ends = rounded_ends(mine); added += len(ends)
        for p, rgb in [(q["pts"], q["rgb"]) for q in mine] + ends:
            out.append((p @ A.T + t, rgb))
    return out, added


# ---------------------------------------------------------------------------------------------- test poses ---

REST = {}
WALK = {"thigh_L": {"fwd": 32}, "shin_L": {"fwd": -12}, "thigh_R": {"fwd": -22}, "shin_R": {"fwd": -40},
        "upper_arm_R": {"fwd": 28}, "forearm_R": {"fwd": 30}, "upper_arm_L": {"fwd": -22}, "forearm_L": {"fwd": 18},
        "chest": {"turn": -8}, "head": {"turn": 6}}
BIG = {"thigh_L": {"fwd": 78}, "shin_L": {"fwd": -85}, "upper_arm_R": {"side": 62}, "forearm_R": {"fwd": 35},
       "upper_arm_L": {"fwd": 80}, "forearm_L": {"fwd": 55}, "chest": {"fwd": 12, "turn": 14}, "head": {"turn": 30, "fwd": -8}}
