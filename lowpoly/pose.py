"""Posing the figure.

The body is one skin that bends (owner's decision): each corner follows one part or shares several, as the body file
says (body.py: joints), and moves by the blend of their movements. That is plain blended skinning, which is what
Godot's Skeleton3D does.

Clothing is not settled. Two behaviours exist here:

  bend    a lifted garment follows the corners it was lifted from, so it bends with the body (posed_bend)
  rigid   every part's share of a garment is a closed piece that turns as a whole, with a rounded end on each open
          loop so that bent joints overlap instead of gaping (posed_rigid). It was compared with the bending skin for
          the body and lost (renders/joints_rigid_or_bend.png); it is kept because some clothing, such as hard
          pieces, may need to stay rigid.
"""
import numpy as np
import body as lb

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
        R = _rz(p.get("turn", 0.0)) @ _ry(side_sign * p.get("side", 0.0)) @ _rx((-1.0 if hangs else 1.0) * p.get("fwd", 0.0))
        t = piv - R @ piv
        parent = lb.PARENT[part]
        if parent is None:
            out[part] = (R, t)
        else:
            Ap, tp = out[parent]
            out[part] = (Ap @ R, Ap @ t + tp)
    return out


# ------------------------------------------------------------------------------------------------- bending ---

def posed_bend(body, polys, pose):
    """polys: dress(..., detail=True). Returns [(polygon, rgb)] with every corner moved by its shares."""
    T = transforms(pose, body["pivots"]); shares = body["shares"]
    out = []
    for q in polys:
        pts = []
        for v, s in zip(q["pts"], q["src"]):
            w = shares[lb.share_key(q["piece"], s)]
            pts.append(sum(share * (T[part][0] @ v + T[part][1]) for part, share in w.items()))
        out.append((np.array(pts), q["rgb"]))
    return out


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
