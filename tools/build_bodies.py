"""Base bodies at 24 voxels per meter: 42 voxels tall, 24 x 24 x 48 grid, 11 rigid parts.

Axes: x = width (character's left is +x, mirror line between x11|x12),
      y = depth (front faces -y, depth centre between y11|y12), z = up (feet on z0).
Both bodies share every row boundary; only widths and depths differ.
Outputs per body: <name>.vox, <name>_parts.json, previews.
"""
import json, os, struct
import numpy as np

W, D, H = 24, 24, 48
PARTS = ["head", "chest", "pelvis", "upper_arm_L", "upper_arm_R", "forearm_L", "forearm_R",
         "thigh_L", "thigh_R", "shin_L", "shin_R"]
PID = {p: i + 1 for i, p in enumerate(PARTS)}
# Pivots in grid-corner coordinates (voxel x spans [x, x+1]); each part rotates about its joint with the parent.
# Parent chain: pelvis (root) -> chest -> head; chest -> upper_arm -> forearm; pelvis -> thigh -> shin.
def pivots(sex, build="average"):
    """Joint pivots in corner coordinates, measured from the built body so every build is correct."""
    part, _ = build_fn(sex, build, face=None)
    def cx(name, z0, z1):
        xs = np.nonzero(part[:, :, z0:z1 + 1] == PID[name])[0]; return (xs.min() + xs.max() + 1) / 2
    pv = {"pelvis": (12, 12, 12), "chest": (12, 12, 16), "head": (12, 12, 27),
          "upper_arm_L": (cx("upper_arm_L", 19, 21), 12, 26), "forearm_L": (cx("forearm_L", 13, 18), 12, 19),
          "thigh_L": (cx("thigh_L", 6, 11), 12, 12), "shin_L": (cx("shin_L", 2, 5), 12, 6)}
    for k in list(pv):
        if k.endswith("_L"): x, y, z = pv[k]; pv[k.replace("_L", "_R")] = (W - x, y, z)
    return pv
PARENT = {"pelvis": None, "chest": "pelvis", "head": "chest", "upper_arm_L": "chest", "upper_arm_R": "chest",
          "forearm_L": "upper_arm_L", "forearm_R": "upper_arm_R", "thigh_L": "pelvis", "thigh_R": "pelvis", "shin_L": "thigh_L", "shin_R": "thigh_R"}
EYE, SHINE, WHITE, LINE = 8, 9, 10, 11


# ---- builds: six bodies from one set of rules. Widths/depths are even where pivot parity matters. ----
BUILDS = {
    # chest (w,d) = ribcage; belly w; hips (w,d); arm (w,d); leg (w,d); shoulder: square top row or sloped (inset 1/side);
    # bust: two forms w x h starting at row z0, a 2-voxel gap between, one voxel proud; layer2 (w, h, offset from the
    # inner edge) adds a second, smaller layer in front of the lower rows. Each pair fills the chest minus 1 per side; shin (w,d) defaults to (leg w, leg d - 2);
    # soft: heavy builds round every vertical edge of torso and legs. Heavy = more mass everywhere, no bulges.
    ("male", "slim"):      dict(chest=(10, 6),  belly=10, hips=(10, 6),  arm=(3, 4), leg=(4, 4), shoulder="square", bust=None),
    ("male", "average"):   dict(chest=(12, 8),  belly=10, hips=(10, 8),  arm=(4, 4), leg=(4, 6), shoulder="square", bust=None),
    ("male", "heavy"):     dict(chest=(14, 10), belly=14, hips=(14, 10), arm=(4, 6), leg=(6, 8), shin=(6, 6), shoulder="square", bust=None, soft=True),
    ("female", "slim"):    dict(chest=(8, 6),   belly=6,  hips=(8, 6),   arm=(3, 3), leg=(4, 4), shoulder="sloped", bust=dict(w=2, h=2, z0=20)),
    ("female", "average"): dict(chest=(10, 6),  belly=8,  hips=(10, 6),  arm=(3, 4), leg=(4, 6), shoulder="sloped", bust=dict(w=3, h=3, z0=20, layer2=(2, 2, 1))),
    ("female", "heavy"):   dict(chest=(12, 8),  belly=10, hips=(12, 8),  arm=(4, 4), leg=(5, 6), shin=(5, 6), shoulder="sloped", bust=dict(w=4, h=3, z0=20, layer2=(2, 2, 1)), soft=True),
}


def span(w, centre=12):              # inclusive x (or y) range of width w centred on the mirror line
    return centre - w // 2, centre - 1 + (w + 1) // 2


def build(sex, build="average", head="round", face="neutral"):
    return build_fn(sex, build, head, face)


def build_fn(sex, build="average", head="round", face="neutral"):
    p = BUILDS[(sex, build)]
    part = np.zeros((W, D, H), np.int8); mat = np.zeros((W, D, H), np.int8)

    def box(name, x0, x1, y0, y1, z0, z1):
        part[x0:x1 + 1, y0:y1 + 1, z0:z1 + 1] = PID[name]; mat[x0:x1 + 1, y0:y1 + 1, z0:z1 + 1] = 1

    def cut(x, y, z): part[x, y, z] = 0; mat[x, y, z] = 0

    def both(name, x0, x1, *rest):
        box(name + "_L", x0, x1, *rest); box(name + "_R", W - 1 - x1, W - 1 - x0, *rest)

    def cut_both(x, y, z): cut(x, y, z); cut(W - 1 - x, y, z)

    # ---- legs: thigh z6-11, shin z2-5, foot z0-1; two columns either side of a 2-voxel gap ----
    lw, ld = p["leg"]; sw, sd = p.get("shin", (lw, max(4, ld - 2)))
    lx0, lx1 = 13, 12 + lw; sx0 = lx0 + (lw - sw) // 2; sx1 = sx0 + sw - 1
    ty0, ty1 = span(ld); sy0, sy1 = span(sd)
    both("thigh", lx0, lx1, ty0, ty1, 6, 11)
    both("shin", sx0, sx1, sy0, sy1, 2, 5)
    both("shin", sx0, sx1, sy0 - 2, sy1, 0, 1)                      # foot, toes 2 forward
    cut_both(sx1, sy0 - 2, 1)                                      # round the outer toe
    if p.get("soft"):                                              # heavy: round the legs' vertical edges
        for (x0, x1, y0, y1, z0, z1) in ((lx0, lx1, ty0, ty1, 6, 11), (sx0, sx1, sy0, sy1, 2, 5)):
            for x in (x0, x1):
                for y in (y0, y1):
                    for z in range(z0, z1 + 1): cut_both(x, y, z)
        for x in (sx0, sx1):
            for z in (0, 1): cut_both(x, sy1, z)                    # round the heel to match the shin above it
    # ---- pelvis z12-15 ----
    hw, hd = p["hips"]; hx0, hx1 = span(hw); hy0, hy1 = span(hd)
    box("pelvis", hx0, hx1, hy0, hy1, 13, 15)
    if hd >= 8: box("pelvis", hx0, hx1, hy0 + 1, hy1 - 1, 12, 12)   # crotch row rounded front/back to thigh depth
    else: box("pelvis", hx0, hx1, hy0, hy1, 12, 12)
    if p["belly"] < hw:                                            # waist row narrows to the belly width
        part[:, :, 15] = 0; mat[:, :, 15] = 0; bx0, bx1 = span(p["belly"]); box("pelvis", bx0, bx1, hy0, hy1, 15, 15)
    # ---- chest z16-26 ----
    cw, cd = p["chest"]; cx0, cx1 = span(cw); cy0, cy1 = span(cd)
    bx0, bx1 = span(p["belly"])
    box("chest", bx0, bx1, cy0, cy1, 16, 18)                       # belly
    box("chest", cx0, cx1, cy0, cy1, 19, 25)                       # ribcage
    if p["shoulder"] == "square": box("chest", cx0, cx1, cy0 + 1, cy1 - 1, 26, 26)   # top row: full width, front/back rounded
    else: box("chest", cx0 + 1, cx1 - 1, cy0, cy1, 26, 26)         # top row: one narrower each side, shoulders slope from here
    if p.get("soft"):                                              # heavy: round every torso row's four vertical edges
        for z in range(13, 26):
            xs, ys = np.nonzero((part[:, :, z] == PID["chest"]) | (part[:, :, z] == PID["pelvis"]))
            for x in (xs.min(), xs.max()):
                for y in (ys.min(), ys.max()): cut(x, y, z)
    elif cd >= 8:
        for x in (cx0, cx1):
            for y in (cy0, cy1): part[x, y, 19:26] = 0; mat[x, y, 19:26] = 0   # soften the ribcage's vertical edges
    if p["bust"]:
        bs = p["bust"]; fy = min(np.nonzero(part[:, :, 24] == PID["chest"])[1])   # chest front plane above the bust
        for x in range(13, 13 + bs["w"]):
            for z in range(bs["z0"], bs["z0"] + bs["h"]):
                box("chest", x, x, fy - 1, fy - 1, z, z); box("chest", W - 1 - x, W - 1 - x, fy - 1, fy - 1, z, z)
        if bs.get("layer2"):
            w2, h2, off = bs["layer2"]
            for x in range(13 + off, 13 + off + w2):
                for z in range(bs["z0"], bs["z0"] + h2):
                    box("chest", x, x, fy - 2, fy - 2, z, z); box("chest", W - 1 - x, W - 1 - x, fy - 2, fy - 2, z, z)
    # ---- arms: hang one voxel clear of the widest torso row beside them; deltoid flush against the chest ----
    torso = (part == PID["chest"]) | (part == PID["pelvis"])
    def torso_edge(z0, z1): return max(np.nonzero(torso[:, :, z0:z1 + 1])[0])
    aw, ad = p["arm"]; faw, fad = p.get("forearm", p["arm"])
    ax0 = torso_edge(10, 21) + 1 + p.get("arm_gap", 1); ax1 = ax0 + aw - 1; ay0, ay1 = span(ad); fy0, fy1 = span(fad)
    both("upper_arm", ax0, ax1, ay0, ay1, 19, 21)
    for z, inset in ((22, 0), (23, 0), (24, 1), (25, 2)):           # deltoid: from the chest's edge out to the arm, sloping in
        e = torso_edge(z, z) + 1
        both("upper_arm", e, ax1 - inset, ay0, ay1, z, z)
        if ad >= 6 and inset == 0:                                  # thick arms: round the deltoid's outer front/back corners
            cut_both(ax1, ay0, z); cut_both(ax1, ay1, z)
    both("forearm", ax0 + (aw - faw), ax1, fy0, fy1, 13, 18)
    both("forearm", ax0 + (aw - faw) + 1, ax1, fy0, fy1, 10, 12)    # hand: one narrower on the inner side
    for y in (fy0, fy1): cut_both(ax0 + (aw - faw) + 1, y, 10); cut_both(ax1, y, 10)   # round the fingertip corners
    build_head(part, mat, head)
    if face: apply_face(part, mat, FACES[face]())
    return part, mat


# ---- heads: unisex, interchangeable. Same neck socket (4x4 at z27), pivot (12,12,27), height (z28-41),
#      eye box (x7-10 and x13-16, z30-34) and ear rows, so faces, hair and hats line up on every shape. ----
HEADS = {   # w = width, d = depth, rounding 1 = edges only, 2 = edges plus corner step; jaw/crown shaping; eye offset from the side
    "round":  dict(w=14, d=12, rounding=2, jaw=None,     crown=None,   eye_off=2),
    "boxy":   dict(w=14, d=12, rounding=0, jaw=None,     crown=None,   eye_off=2),   # square plan, only top/bottom edges softened
    "oval":   dict(w=12, d=12, rounding=2, jaw="taper",  crown="taper", eye_off=1),
    "strong": dict(w=14, d=12, rounding=2, jaw="square", crown=None,   eye_off=2),
    "heart":  dict(w=14, d=12, rounding=2, jaw="narrow", crown=None,   eye_off=2),
}


def build_head(part, mat, shape="round"):
    h = HEADS[shape]; pid = PID["head"]
    x0, x1 = 12 - h["w"] // 2, 11 + h["w"] // 2
    y0, y1 = 12 - h["d"] // 2, 11 + h["d"] // 2
    z0, z1 = 28, 41

    def put(x, y, z): part[x, y, z] = pid; mat[x, y, z] = 1
    def cut(x, y, z): part[x, y, z] = 0; mat[x, y, z] = 0

    part[10:14, 10:14, 27] = pid; mat[10:14, 10:14, 27] = 1              # neck 4 x 4
    part[x0:x1 + 1, y0:y1 + 1, z0:z1 + 1] = pid; mat[x0:x1 + 1, y0:y1 + 1, z0:z1 + 1] = 1
    # rounding: the 12 edge lines
    bottom_edges = h["jaw"] != "square"
    for x in (x0, x1):
        if h["rounding"] >= 1:
            for y in (y0, y1):
                for z in range(z0, z1 + 1): cut(x, y, z)                  # 4 vertical edges
        for z in ((z0, z1) if bottom_edges else (z1,)):
            for y in range(y0, y1 + 1): cut(x, y, z)                      # edges along y at top/bottom
    for y in (y0, y1):
        for z in ((z0, z1) if bottom_edges else (z1,)):
            for x in range(x0, x1 + 1): cut(x, y, z)                      # edges along x at top/bottom
    if h["rounding"] >= 2:                                                # second step on the corners
        for x in (x0 + 1, x1 - 1):
            for y in (y0 + 1, y1 - 1):
                for z in ((z0, z1) if bottom_edges else (z1,)): cut(x, y, z)
    def narrow(z, n):                                                     # remove n columns from each side, outside in
        for y in range(y0, y1 + 1):
            for i in range(n): cut(x0 + i, y, z); cut(x1 - i, y, z)
    if h["jaw"] == "taper":   narrow(z0, 2); narrow(z0 + 1, 1)             # chin: 8, 10, then full width
    if h["jaw"] == "narrow":  narrow(z0, 3); narrow(z0 + 1, 3); narrow(z0 + 2, 2)   # chin: 8, 8, 10, full at the ear line
    if h["crown"] == "taper": narrow(z1, 2); narrow(z1 - 1, 1)            # crown: full, 10, 8
    # ears: 1 wide x 3 deep x 4 tall, level with the eyes
    for z in range(31, 35):
        for y in (11, 12, 13): put(x0 - 1, y, z); put(x1 + 1, y, z)
    # no eyes: the face is a skin-tight overlay (see FACES), so expressions can be swapped


# ---- faces: eyes only, skin-tight overlays (bulk 0) on the face plane y6, inside a fixed EYE BOX shared by every head.
#      Expressions are defined once per eye in box cells (c, r): c counts from the eye's OUTER edge, r from its bottom row,
#      and are mirrored onto the other eye, so the two eyes always match. Roles: white, pupil (eye colour), line (lids),
#      skin (the overlay hides the eye there). ----
FACE_Y = 6
EYE_BOX = dict(w=4, h=5, z0=30, x0=7, drop=((0, 4), (3, 4)), pupil_cols=(1, 2), pupil_rows=(1, 4))   # 4 wide x 5 tall, top corners rounded
# screen-left eye occupies x7-10, screen-right eye x13-16, rows z30-34


def _expressions(bx=EYE_BOX):
    w, h, pc, pr = bx["w"], bx["h"], bx["pupil_cols"], bx["pupil_rows"]; top = h - 1; drop = set(map(tuple, bx["drop"]))
    def base(): return {(c, r): "white" for c in range(w) for r in range(h) if (c, r) not in drop}
    def skin(): return {(c, r): "skin" for c in range(w) for r in range(h)}
    def pupil(e, cols, rows):
        for c in cols:
            for r in range(rows[0], rows[1] + 1):
                if e.get((c, r)) == "white": e[(c, r)] = "pupil"
        return e
    def neutral(): return pupil(base(), pc, pr)
    def blink(): e = skin(); [e.__setitem__((c, 2), "line") for c in range(w)]; return e
    def happy(): e = skin(); e[(0, 2)] = e[(w - 1, 2)] = "line"; [e.__setitem__((c, 3), "line") for c in range(1, w - 1)]; return e
    def angry():                                               # upper lid slants down toward the nose
        e = pupil(base(), pc, (1, 2))
        for c in range(w): e[(c, top)] = "skin"
        e[(1, top)] = "line"
        for c in range(2, w): e[(c, top - 1)] = "line"
        return e
    def sad():                                                 # upper lid slants down toward the outside, pupils low
        e = pupil(base(), pc, (0, 2))
        for c in range(w): e[(c, top)] = "skin"
        e[(w - 2, top)] = "line"
        for c in range(0, w - 2): e[(c, top - 1)] = "line"
        return e
    def surprised(): return pupil(base(), (1, 2), (2, 3))
    def bored():
        e = pupil(base(), pc, (1, 2))
        for c in range(w): e[(c, top)] = "skin"; e[(c, top - 1)] = "line"
        return e
    def look_down(): return pupil(base(), pc, (pr[0] - 1, pr[1] - 1))
    def look(screen_cols):                                     # both pupils toward the same side of the screen
        return pupil(base(), screen_cols, pr), pupil(base(), tuple(w - 1 - s for s in screen_cols), pr)
    same = lambda f: (lambda: (f(), f()))
    return {"neutral": same(neutral), "blink": same(blink), "happy": same(happy), "angry": same(angry), "sad": same(sad),
            "surprised": same(surprised), "bored": same(bored), "wink": lambda: (neutral(), blink()),
            "look_left": lambda: look((0, 1)), "look_right": lambda: look((w - 2, w - 1)), "look_down": same(look_down)}


EXPRESSIONS = _expressions()


def face_cells(name, bx=EYE_BOX):
    """Absolute (x, y, z) -> role for an expression."""
    left, right = EXPRESSIONS[name](); out = {}
    for e, mirror in ((left, False), (right, True)):
        for (c, r), role in e.items():
            x = (W - 1 - bx["x0"]) - c if mirror else bx["x0"] + c
            out[(x, FACE_Y, bx["z0"] + r)] = role
    return out


FACES = {n: (lambda n=n: face_cells(n)) for n in EXPRESSIONS}
FACE_MAT = {"white": WHITE, "pupil": EYE, "line": LINE, "skin": 1}


def apply_face(part, mat, face):
    """Skin-tight: only recolours cells that are head voxels (the overlay never adds volume)."""
    for (x, y, z), role in face.items():
        if part[x, y, z] == PID["head"]: mat[x, y, z] = FACE_MAT[role]


# ---- regions (left side; the right mirrors by x) ----
BANDS = {   # name: (z0, z1, part family)
    "neck": (27, 27, "head"), "lower_head": (28, 31, "head"), "mid_head": (32, 36, "head"), "crown": (37, 41, "head"),
    "collar": (26, 26, "chest"), "upper_chest": (22, 25, "chest"), "lower_chest": (19, 21, "chest"), "belly": (16, 18, "chest"),
    "waist": (15, 15, "pelvis"), "hips": (12, 14, "pelvis"),
    "shoulder": (23, 25, "upper_arm"), "upper_arm": (20, 22, "upper_arm"), "elbow": (19, 19, "upper_arm"),
    "forearm": (14, 18, "forearm"), "wrist": (13, 13, "forearm"), "hand": (10, 12, "forearm"),
    "upper_thigh": (9, 11, "thigh"), "lower_thigh": (7, 8, "thigh"), "knee": (6, 6, "thigh"),
    "shin": (3, 5, "shin"), "ankle": (2, 2, "shin"), "foot": (0, 1, "shin"),
}
TRIM = {"neck", "collar", "waist", "elbow", "wrist", "knee", "ankle"}


def region_of(partname, z):
    fam = partname.replace("_L", "").replace("_R", "")
    for name, (z0, z1, f) in BANDS.items():
        if f == fam and z0 <= z <= z1: return name
    return None


# ---- shading & output ----
SKIN = [(255, 214, 172), (236, 178, 134), (190, 128, 92)]
EYE_C, SHINE_C, LINE_C = (20, 20, 26), (255, 255, 255), (70, 38, 24)


def shade(solid):
    """Baked tone per voxel: 0 light (top, or left+front edge), 1 mid (front/left faces), 2 dark (under, right, back)."""
    def e(dx, dy, dz):
        t = np.zeros_like(solid)
        xs, xd = (slice(0, W - dx), slice(dx, W)) if dx >= 0 else (slice(-dx, W), slice(0, W + dx))
        ys, yd = (slice(0, D - dy), slice(dy, D)) if dy >= 0 else (slice(-dy, D), slice(0, D + dy))
        zs, zd = (slice(0, H - dz), slice(dz, H)) if dz >= 0 else (slice(-dz, H), slice(0, H + dz))
        t[xs, ys, zs] = solid[xd, yd, zd]; return ~t
    up, left, front, down, right, back = e(0, 0, 1), e(-1, 0, 0), e(0, -1, 0), e(0, 0, -1), e(1, 0, 0), e(0, 1, 0)
    return np.where(up | (left & front), 0, np.where(front, 1, np.where(down | right | back, 2, 1)))


def colors(part, mat):
    tone = shade(part > 0); out = np.zeros((W, D, H, 3), np.uint8)
    for t in range(3): out[(mat == 1) & (tone == t)] = SKIN[t]
    out[mat == EYE] = EYE_C; out[mat == SHINE] = SHINE_C; out[mat == WHITE] = (250, 250, 248); out[mat == LINE] = LINE_C
    return out


def write_vox(path, part, col):
    pal, idx, xyzi = [], {}, bytearray(); n = 0
    for z in range(H):
        for y in range(D):
            for x in range(W):
                if not part[x, y, z]: continue
                c = tuple(int(v) for v in col[x, y, z])
                if c not in idx: pal.append(c); idx[c] = len(pal)
                xyzi += struct.pack("<BBBB", x, D - 1 - y, z, idx[c]); n += 1
    chunk = lambda cid, b: cid + struct.pack("<ii", len(b), 0) + b
    rgba = b"".join(struct.pack("<BBBB", *c, 255) for c in pal) + b"\0\0\0\xff" * (256 - len(pal))
    main = chunk(b"SIZE", struct.pack("<iii", W, D, H)) + chunk(b"XYZI", struct.pack("<i", n) + bytes(xyzi)) + chunk(b"RGBA", rgba)
    open(path, "wb").write(b"VOX " + struct.pack("<i", 150) + b"MAIN" + struct.pack("<ii", 0, len(main)) + main)
    return n


if __name__ == "__main__":
    for shape in HEADS:
        part = np.zeros((W, D, H), np.int8); mat = np.zeros((W, D, H), np.int8); build_head(part, mat, shape)
        n = write_vox(f"head42_{shape}.vox", part, colors(part, mat))
        json.dump({"shape": shape, "part": "head", "parent": "chest", "pivot": [12, 12, 27], "neck_socket": [[10, 13], [10, 13], 27],
                   "eye_box": {"left_x": [7, 10], "right_x": [13, 16], "z": [30, 34], "plane_y": 6},
                   "voxels": [[int(x), int(y), int(z)] for x, y, z in zip(*np.nonzero(part))]}, open(f"head42_{shape}.json", "w"))
        print("head", shape, n, "voxels")
    for old in __import__("glob").glob("face42_*.json"): os.remove(old)
    for name in EXPRESSIONS:
        L, R = EXPRESSIONS[name]()
        json.dump({"name": name, "plane_y": FACE_Y, "bulk": 0, "roles": ["white", "pupil", "line", "skin"],
                   "eye_box": {k: (list(map(list, v)) if k == "drop" else v) for k, v in EYE_BOX.items()},
                   "cells_note": "c from the eye's outer edge, r from its bottom row; 'right' is mirrored onto the screen-right eye",
                   "left": [[c, r, role] for (c, r), role in sorted(L.items())], "right": [[c, r, role] for (c, r), role in sorted(R.items())],
                   "voxels": [[x, y, z, r] for (x, y, z), r in sorted(face_cells(name).items())]}, open(f"face42_{name}.json", "w"))
    print("faces:", ", ".join(FACES))
    for (sex, bld) in BUILDS:
        part, mat = build(sex, bld, face=None)
        col = colors(part, mat); name = f"body42_{sex}_{bld}"
        n = write_vox(f"{name}.vox", part, col)
        cells = {q: [] for q in PARTS}
        for x, y, z in zip(*np.nonzero(part)): cells[PARTS[part[x, y, z] - 1]].append([int(x), int(y), int(z)])
        json.dump({"grid": [W, D, H], "voxels_per_meter": 24, "facing": "-y", "mirror_axis_x": 12, "sex": sex, "build": bld,
                   "head": "from the head library (head42_*.json); attaches at the neck socket, pivot (12, 12, 27)",
                   "parts": {q: {"parent": PARENT[q], "pivot": [float(v) for v in pivots(sex, bld)[q]],
                                 "voxels": [] if q == "head" else cells[q]} for q in PARTS},
                   "regions": {k: {"z0": v[0], "z1": v[1], "part": v[2], "trim": k in TRIM} for k, v in BANDS.items()}},
                  open(f"{name}_parts.json", "w"))
        np.savez(f"{name}.npz", part=part, mat=mat)
        print(name, n, "voxels")
