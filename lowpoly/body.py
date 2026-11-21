"""The low-poly bodies the clothing system uses: cut so that their polygons follow the clothing regions.

The clothing parameters address the body by REGION: a band of height on a part family, split left/right, and for the
head and torso also front/back (SPEC 3.4; the game reads this band table from assets/lowpoly/regions.json, written
below, into core/region_map.gd). So every band boundary here is an
edge loop, every polygon lies in exactly one region, and each polygon is tagged with its region key and its rigid part.

Heights are the voxel rows: the clay's unit is one voxel, so the band table is the same table.

Eight bodies: slim, average, heavy and short, for each sex. Every one is cut from its own clay (clay.py, made from
the sex's average clay) by the same cutter, so all eight have the same polygons, made of the same corners in the
same order, with the same regions and joints: each is the feminine average with its corners moved, and every
clothing rule works on it as it does on the average. A short body has the same bands at its own, lower heights
(clay.short_heights); everything here reads a body's heights from its own band table, body["bands"].

The body is one skin that bends at its joints (see "joints" below); each corner's shares are in the body file.

Three places where a region follows the body rather than a level line:
  - hips / upper thigh: the boundary is the leg opening, level 11 at the outside of the hip and dropping to the crotch,
    so "hips" covers the whole pelvis (on the voxel body the pelvis simply ended at row 11);
  - front / back: split along the side seam (the widest point of each ring), which lies within half a unit of the
    depth centre;
  - the arm's top cap and the foot's top stand a little past their bands' levels and are tagged with those bands.
"""
import json, os, sys
import numpy as np
import clay, rings as ring_tools

CX, CY = ring_tools.CX, ring_tools.CY

# name: (bottom, top, part family, trim) -- the region table's bands (SPEC 3.4), rows made into heights
BANDS = {
    "neck": (25, 26, "head", True), "lower_head": (26, 31, "head", False), "mid_head": (31, 37, "head", False), "crown": (37, 42, "head", False),
    "collar": (24, 25, "chest", True), "upper_chest": (20, 24, "chest", False), "lower_chest": (17, 20, "chest", False), "belly": (15, 17, "chest", False),
    "waist": (14, 15, "pelvis", True), "hips": (11, 14, "pelvis", False),
    "shoulder": (21, 24, "upper_arm", False), "upper_arm": (18, 21, "upper_arm", False), "elbow": (17, 18, "upper_arm", True),
    "forearm": (13, 17, "forearm", False), "wrist": (12, 13, "forearm", True), "hand": (9, 12, "forearm", False),
    "upper_thigh": (9, 11, "thigh", False), "lower_thigh": (7, 9, "thigh", False), "knee": (6, 7, "thigh", True),
    "shin": (3, 6, "shin", False), "ankle": (2, 3, "shin", True), "foot": (0, 2, "shin", False),
}
CENTRED = ("head", "chest", "pelvis")
PARENT = {"pelvis": None, "chest": "pelvis", "head": "chest", "upper_arm_L": "chest", "upper_arm_R": "chest",
          "forearm_L": "upper_arm_L", "forearm_R": "upper_arm_R", "thigh_L": "pelvis", "thigh_R": "pelvis", "shin_L": "thigh_L", "shin_R": "thigh_R"}

TORSO_COLS = [20, 90, 155]
LEG_COLS = [315, 20, 90, 160, 225, 270]
ARM_COLS = [30, 90, 150, 210, 270, 330]
FOOT_COLS = [325, 35, 90, 135, 225, 270]
FOOT_Y = [-4.2, -2.8, -0.9, 1.0, 2.05]

# torso rings, top to bottom: (height, depth offset of the ring's centre). Heights that are band boundaries are fixed;
# the others are shape rings inside a band (shoulder line, upper chest, under the chest, widest hip). Every height
# here is the average body's; a short body's are moved to its own bands (clay.Heights).
TORSO = {
    "female": [(26.6, .35), (26, .35), (25, .5), (24, .5), (22.6, .4), (21.3, .3), (20, .25), (18.4, .25), (17, .2), (15, 0.0), (14, .1), (12.6, .3)],
    "male": [(26.6, .35), (26, .35), (25, .5), (24, .6), (22.75, .45), (21.6, .3), (20, .3), (18.4, .25), (17, .2), (15, .05), (14, .15), (12.6, .3)],
}
BUILDS = ("average", "slim", "heavy", "short")
BODIES = {(sex, b): dict(model=clay.BODIES[(sex, b)], torso=TORSO[sex], heights=clay.Heights(clay.HEIGHTS.get((sex, b))))
          for sex in ("female", "male") for b in BUILDS}
HIP_SEAT_Z = 11.6                       # one extra ring through the fullest part of the seat
HOLE = dict(side=11.0, oblique=10.6, lift=0.7)   # the leg opening: its height at the side, at the front/back obliques, above the crotch
LEG_Z = [9, 7, 6, 3, 2, 1.2]            # band boundaries down the leg; the last ring is hidden inside the foot
ARM_Z = [21, 18, 17, 15, 13, 12]        # band boundaries down the arm, between the shoulder's rings and the hand's
FLAT = 1e-6                             # where the shoulder is cut off flat, a ring's side corner is the middle of the flat


def bands_of(at):
    """The band table at a body's heights (at: clay.Heights)."""
    return {name: (at(z0), at(z1), fam, trim) for name, (z0, z1, fam, trim) in BANDS.items()}


def band_at(z, families, bands=BANDS):
    for name, (z0, z1, fam, _) in bands.items():
        if fam in families and z0 <= z < z1:
            return name
    lo = min((b for b in bands.items() if b[1][2] in families), key=lambda b: b[1][0])
    hi = max((b for b in bands.items() if b[1][2] in families), key=lambda b: b[1][1])
    return lo[0] if z < lo[1][0] else hi[0]


def _clean(pts):
    keep = []
    for p in pts:
        p = np.asarray(p, float)
        if not keep or np.linalg.norm(p - keep[-1]) > 1e-6:
            keep.append(p)
    if len(keep) > 1 and np.linalg.norm(keep[0] - keep[-1]) <= 1e-6:
        keep.pop()
    return keep


def rec(pts, band, side, face, piece, hidden=False):
    pts = _clean(pts)
    if len(pts) < 3:
        return None
    fam = BANDS[band][2]
    centred = fam in CENTRED
    return dict(pts=np.array(pts), band=band, side=side, face=face if centred else "", piece=piece, hidden=hidden,
                part=fam if centred else f"{fam}_{side}",
                key=f"{band}.{side}" + (f".{face}" if centred else ""))


def mirrored(r):
    m = dict(r); p = r["pts"][::-1].copy(); p[:, 0] = 2.0 * CX - p[:, 0]
    side = "R" if r["side"] == "L" else "L"
    fam = BANDS[r["band"]][2]; centred = fam in CENTRED
    piece = r["piece"][:-1] + side if r["piece"].endswith(("_L", "_R")) else r["piece"]
    m.update(pts=p, side=side, piece=piece, part=fam if centred else f"{fam}_{side}",
             key=f"{r['band']}.{side}" + (f".{r['face']}" if centred else ""))
    return m


# ------------------------------------------------------------------------------------------------- the pieces ---

def build_skin(spec, bands):
    out = []
    at = spec["heights"]
    zs = [at(z) for z, _ in spec["torso"]]
    halves = [ring_tools.torso_ring(z, TORSO_COLS, yc, flat=FLAT) for z, (_, yc) in zip(zs, spec["torso"])]
    neck_top = bands["neck"][1]
    for i in range(len(halves) - 1):
        u, l = halves[i], halves[i + 1]
        band = "neck" if zs[i] > neck_top else band_at(0.5 * (zs[i] + zs[i + 1]), CENTRED, bands)
        for k in range(4):
            out.append(rec([u[k], u[k + 1], l[k + 1], l[k]], band, "L", "F" if k < 2 else "B", "skin", hidden=zs[i] > neck_top))
    out.append(rec(list(halves[0][::-1]), "neck", "L", "F", "skin", hidden=True))          # top of the neck, inside the head

    yc, zc = ring_tools.crotch()
    j = halves[-1]
    ring_j = np.array(list(j) + [np.array([CX, 0.5 * (j[0][1] + j[-1][1]), zs[-1]])])
    seat = ring_tools.hip_half_ring(at(HIP_SEAT_Z), TORSO_COLS)
    lo = ring_tools.hip_half_ring(at(at.back(zc) + HOLE["lift"]), TORSO_COLS)
    ob = ring_tools.hip_half_ring(at(HOLE["oblique"]), TORSO_COLS); sd = ring_tools.hip_half_ring(at(HOLE["side"]), TORSO_COLS)
    hole = np.array([lo[0], ob[1], sd[2], ob[3], lo[4], np.array([CX, yc, zc])])           # F, A, S, B, R, crotch
    rings = [ring_j, seat, hole] + [ring_tools.leg_ring(at(z), LEG_COLS) for z in LEG_Z]
    bands = ["hips", "hips", "upper_thigh", "lower_thigh", "knee", "shin", "ankle", "foot"]
    for (u, l), band in zip(zip(rings[:-1], rings[1:]), bands):
        for k in range(6):
            quad = [u[k], u[(k + 1) % 6], l[(k + 1) % 6], l[k]]
            if all(abs(p[0] - CX) < 1e-6 for p in quad):
                continue                                                                    # the seam between the two legs, inside the body
            out.append(rec(quad, band, "L", "F" if k < 2 else "B", "skin", hidden=(band == "foot")))
    out.append(rec(list(rings[-1]), "foot", "L", "", "skin", hidden=True))                # end of the leg, inside the foot
    out = [r for r in out if r is not None]
    return out + [mirrored(r) for r in out], dict(crotch=(yc, zc))


def build_arm(spec, bands):
    M = ring_tools.M
    keys = ("hand", "forearm", "upper_arm", "deltoid")
    kz = [M[k][0][2] for k in keys]
    cen = lambda z: (CX + np.interp(z, kz, [M[k][0][0] for k in keys]), CY + np.interp(z, kz, [M[k][0][1] for k in keys]))
    top = M["deltoid"][0][2] + M["deltoid"][1]; dz = M["deltoid"][0][2]
    hz = M["hand"][0][2]; hb = hz - M["hand"][1][2]
    zs = [top - 0.22, dz + 0.4] + [spec["heights"](z) for z in ARM_Z] + [hz + 0.1, hb + 0.35]
    rings = []
    for z in zs:
        o = ring_tools.inside_centre(ring_tools.sdf_arm, cen(z), z, 1.0)
        pts = ring_tools.outline(ring_tools.sdf_arm, o, rmax=5.0)
        rings.append(ring_tools.snap([ring_tools.support(pts, a) for a in ARM_COLS], pts))
    fams = ("upper_arm", "forearm")
    out = [rec(list(rings[0][::-1]), "shoulder", "L", "", "arm_L")]
    for i in range(len(rings) - 1):
        band = band_at(0.5 * (zs[i] + zs[i + 1]), fams, bands)
        for k in range(6):
            out.append(rec([rings[i][k], rings[i][(k + 1) % 6], rings[i + 1][(k + 1) % 6], rings[i + 1][k]], band, "L", "", "arm_L"))
    out.append(rec(list(rings[-1]), "hand", "L", "", "arm_L"))
    out = [r for r in out if r is not None]
    return out + [mirrored(r) for r in out]


def build_foot():
    M = ring_tools.M
    fx = M["foot"][0][0]
    y0 = M["foot"][0][1] - M["foot"][1][1]; y1 = M["heel"][0][1] + M["heel"][1][1]
    rings = []
    for t in FOOT_Y:
        y = y0 + (t + 4.5) / 6.75 * (y1 - y0)
        o = np.array([CX + fx, CY + y, 0.5])
        if ring_tools.sdf_foot(o[None, :])[0] >= 0:
            g = np.linspace(-1.2, 1.2, 25)
            P = np.stack([CX + fx + g, np.full(g.size, CY + y), np.full(g.size, 0.3)], axis=1)
            o = P[int(np.argmin(ring_tools.sdf_foot(P)))]
        pts = ring_tools.outline(ring_tools.sdf_foot, o, u=ring_tools.UP, v=ring_tools.OUT, rmax=5.0)
        rings.append(ring_tools.snap([ring_tools.support(pts, a, ring_tools.UP, ring_tools.OUT) for a in FOOT_COLS], pts, axes=(0, 2)))
    out = [rec(list(rings[0][::-1]), "foot", "L", "", "foot_L")]
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(6):
            out.append(rec([a[k], a[(k + 1) % 6], b[(k + 1) % 6], b[k]], "foot", "L", "", "foot_L"))
    out.append(rec(list(rings[-1]), "foot", "L", "", "foot_L"))
    out = [r for r in out if r is not None]
    return out + [mirrored(r) for r in out]


# ------------------------------------------------------------------------------------------------- joints ---
# The body is one skin that bends (owner's decision). Each corner follows one part, or more than one in a fixed
# share, and moves by the blend of their movements: plain blended skinning, which Godot's Skeleton3D does.
#
# Every joint except the hip and the shoulder sits in a one-row trim band. The band's upper edge loop follows the part
# above it 75/25, its lower loop 25/75, and the pivot is at the middle of the band. The hip bends on the leg-opening
# loop, half and half, and the line between the legs follows mostly the pelvis. The shoulder is a ball: the arm is a
# separate piece that turns as a whole about the centre of its shoulder.
JOINT_BANDS = {"neck": ("head", "chest"), "waist": ("chest", "pelvis"), "elbow": ("upper_arm", "forearm"), "knee": ("thigh", "shin")}


def joint_pivots(model, bands=BANDS):
    def on_line(a, b, z):
        (ca, _), (cb, _) = model[a], model[b]
        t = (z - ca[2]) / (cb[2] - ca[2])
        return (CX + ca[0] + t * (cb[0] - ca[0]), CY + ca[1] + t * (cb[1] - ca[1]), z)
    mid = lambda band: 0.5 * (bands[band][0] + bands[band][1])
    d = model["deltoid"][0]; th = model["thigh"][0]
    p = {"pelvis": (CX, CY, float(bands["hips"][0])), "chest": (CX, CY + 0.1, mid("waist")), "head": (CX, CY + 0.4, mid("neck")),
         "upper_arm_L": (CX + d[0], CY + d[1], d[2]), "forearm_L": on_line("upper_arm", "forearm", mid("elbow")),
         "thigh_L": (CX + th[0], CY + th[1], float(bands["hips"][0])), "shin_L": on_line("thigh", "calf", mid("knee"))}
    for k in list(p):
        if k.endswith("_L"):
            x, y, z = p[k]; p[k[:-1] + "R"] = (2 * CX - x, y, z)
    return {k: tuple(float(v) for v in p[k]) for k in PARENT}


def share_key(piece, v):
    return (piece, tuple(float(x) for x in np.round(v, 4)))


def corner_shares(polys, bands=BANDS):
    """For every corner: the parts it follows and in what share. Keyed by share_key(piece, position)."""
    at = {}
    for r in polys:
        for v in r["pts"]:
            at.setdefault(share_key(r["piece"], v), set()).add(r["part"])
    edge = lambda band: (float(bands[band][1]), float(bands[band][0]))     # upper loop, lower loop
    shares = {}
    for (piece, pos), parts in at.items():
        x, _, z = pos
        side = "L" if x > CX else "R"
        on_centre = abs(x - CX) < 1e-6
        at_height = lambda h: abs(z - h) < 1e-6

        def band_share(band, s=""):
            up, low = edge(band); above, below = (f"{f}{s}" for f in JOINT_BANDS[band])
            if at_height(up): return {above: 0.75, below: 0.25}
            if at_height(low): return {above: 0.25, below: 0.75}
            return None

        w = None
        if piece.startswith("arm"):
            w = band_share("elbow", "_" + piece[-1])
        elif piece == "skin" and any(p.startswith(("thigh", "shin")) for p in parts):
            if on_centre: w = {"pelvis": 0.6, "thigh_L": 0.2, "thigh_R": 0.2}      # the line between the legs
            elif "pelvis" in parts: w = {"pelvis": 0.5, f"thigh_{side}": 0.5}       # the leg opening
            else: w = band_share("knee", "_" + side)
        elif piece == "skin":
            w = band_share("waist") or band_share("neck")
        shares[(piece, pos)] = w or {sorted(parts)[0]: 1.0}
    return shares


SDF = dict(skin=lambda p: ring_tools.sdf_skin(p), arm_L=lambda p: ring_tools.sdf_arm(p), arm_R=lambda p: ring_tools.sdf_arm(p),
           foot_L=lambda p: ring_tools.sdf_foot(p), foot_R=lambda p: ring_tools.sdf_foot(p))


def build(sex, build="average", head="round"):
    """The body with one of the heads on it (heads.py). The body's own file leaves the head out.
    bands: the band table at this body's heights. info: the crotch; the head's name; head_dz, how far the head is
    moved from the head library's heights to sit on this body's neck (0 but on a short body)."""
    import heads as head_library
    spec = BODIES[(sex, build)]
    bands = bands_of(spec["heights"])
    ring_tools.use(spec["model"], spec["heights"])
    skin, info = build_skin(spec, bands)
    polys = skin + build_arm(spec, bands) + build_foot()
    for r in polys:                                                  # wind every polygon outward
        n = ring_tools.normal(r["pts"]); c = r["pts"].mean(axis=0)
        d = SDF[r["piece"]](np.array([c + 0.25 * n, c - 0.25 * n]))
        if d[0] < d[1]:
            r["pts"] = r["pts"][::-1].copy()
    dz = float(bands["neck"][1] - BANDS["neck"][1])
    for r in head_library.build(head):
        if dz: r["pts"] = r["pts"] + np.array([0.0, 0.0, dz])
        polys.append(r)
    info = dict(info, head=head, head_dz=dz)
    return dict(sex=sex, build=build, polys=polys, bands=bands, pivots=joint_pivots(spec["model"], bands),
                shares=corner_shares(polys, bands), info=info)


# ---------------------------------------------------------------------------------------------------- checks ---

def all_region_keys():
    keys = []
    for band, (_, _, fam, _) in BANDS.items():
        for side in "LR":
            keys += [f"{band}.{side}.{f}" for f in "FB"] if fam in CENTRED else [f"{band}.{side}"]
    return keys


def check(body):
    """Geometry (as before) and regions. Returns (ok, report)."""
    polys = body["polys"]; ok = True; lines = []
    for piece in sorted({r["piece"] for r in polys}):
        mine = [r for r in polys if r["piece"] == piece]
        bow = deep = far = 0; edges = {}
        for r in mine:
            p = r["pts"]
            if len(p) == 4:
                n1 = np.cross(p[1] - p[0], p[2] - p[0]); n2 = np.cross(p[2] - p[0], p[3] - p[0])
                m1 = np.cross(p[1] - p[0], p[3] - p[0]); m2 = np.cross(p[2] - p[1], p[3] - p[1])
                bow += bool(n1 @ n2 < 0 or m1 @ m2 < 0)
            if piece in SDF:                                         # the head is checked by heads.check
                d = SDF[piece](p.mean(axis=0)[None, :])[0]
                deep += bool(d < -0.8 and not r["hidden"]); far += bool(d > 0.3)
            for i in range(len(p)):
                a = tuple(np.round(p[i], 4)); b = tuple(np.round(p[(i + 1) % len(p)], 4))
                k = (a, b) if a < b else (b, a); edges[k] = edges.get(k, 0) + 1
        odd = sum(1 for v in edges.values() if v != 2)
        ok &= bow == 0 and deep == 0 and far == 0 and odd == 0
        lines.append(f"  {piece:7s}: {len(mine):3d} polygons | twisted: {bow} | buried (not counting the hidden ends): {deep} | off the clay: {far} | open or doubled edges: {odd}")
    have = {}
    for r in polys:
        if not r["hidden"]:
            have[r["key"]] = have.get(r["key"], 0) + 1
    missing = [k for k in all_region_keys() if k not in have]
    ok &= not missing
    lines.append(f"  regions: {len(have)} of {len(all_region_keys())} present" + (f" | MISSING: {missing}" if missing else ""))
    stray = []
    for r in polys:                                                  # every polygon inside its own band's heights
        if r["hidden"]: continue
        z0, z1 = body["bands"][r["band"]][:2]; lo, hi = r["pts"][:, 2].min(), r["pts"][:, 2].max()
        if lo < z0 - 1e-6 or hi > z1 + 1e-6:
            stray.append((r["key"], round(float(lo), 2), round(float(hi), 2)))
    allowed = ("hips", "upper_thigh", "shoulder", "hand", "foot", "crown", "lower_head")
    bad = [s for s in stray if s[0].split(".")[0] not in allowed]
    ok &= not bad
    lines.append(f"  polygons outside their band's heights: {len(stray)} by design (leg opening, arm and foot ends)" + (f" | UNEXPECTED: {bad}" if bad else ""))
    bad = [k for k, w in body["shares"].items() if abs(sum(w.values()) - 1.0) > 1e-9 or not set(w) <= set(PARENT) or len(w) > 4]
    blended = sum(1 for w in body["shares"].values() if len(w) > 1)
    ok &= not bad and set(body["pivots"]) == set(PARENT)
    lines.append(f"  joints: {len(body['shares'])} corners, {blended} of them shared between parts" + (f" | BAD SHARES: {bad[:5]}" if bad else ""))
    return ok, "\n".join(lines)


def counts(body, head=True):
    polys = [r for r in body["polys"] if head or r["piece"] != "head"]
    return len(polys), sum(len(r["pts"]) - 2 for r in polys)


# ----------------------------------------------------------------------------------------------------- files ---

def to_data(body):
    """The body file's contents: corners (welded within each piece), polygons with their region and part, pivots, bands."""
    index = {}; verts = []; shares = []

    def vid(piece, v):
        k = share_key(piece, v)
        if k not in index:
            index[k] = len(verts); verts.append([round(float(x), 4) for x in v]); shares.append(body["shares"][k])
        return index[k]

    polys = [dict(v=[vid(r["piece"], v) for v in r["pts"]], region=r["key"], part=r["part"], piece=r["piece"], hidden=bool(r["hidden"]))
             for r in body["polys"] if r["piece"] != "head"]
    return {
        "format": "lowpoly_body", "version": 4, "units_per_metre": 24, "facing": "-y", "mirror_plane_x": CX, "depth_centre_y": CY,
        "sex": body["sex"], "build": body["build"],
        "head": "from the head library (head_*.json beside this file); it sits on the neck, raised by head_raise, and follows the head part",
        "head_raise": body["info"]["head_dz"],
        "note": "Generated by lowpoly/body.py; regenerate rather than hand-edit. 'regions' is the game's region table (its rows are the voxel bodies'); 'heights' is where each band is on this body: the old voxel rows on every build but short. 'hidden' polygons are ends buried inside a neighbouring piece. 'shares' has one entry per corner: the parts that corner follows when the figure moves, and in what share. All eight bodies have the same vertices in the same order and the same polygons.",
        "parts": {k: {"parent": PARENT[k], "pivot": [float(x) for x in body["pivots"][k]]} for k in PARENT},
        "regions": {k: {"z0": v[0], "z1": v[1] - 1, "part": v[2], "trim": v[3]} for k, v in BANDS.items()},
        "heights": {k: [round(float(v[0]), 4), round(float(v[1]), 4)] for k, v in body["bands"].items()},
        "vertices": verts, "shares": shares, "polygons": polys,
    }


def write_json(body, path):
    data = to_data(body)
    with open(path, "w") as fh:
        json.dump(data, fh)
    return len(data["vertices"]), len(data["polygons"])


def write_obj(body, path):
    """Y up, front toward +Z, metres; one group per region so a viewer can show or hide them."""
    with open(path, "w") as fh:
        fh.write("# low-poly body, polygons grouped by clothing region. Metres. Y up, the figure faces +Z.\n")
        n = 1
        mine = [r for r in body["polys"] if r["piece"] != "head"]
        for key in sorted({r["key"] for r in mine}):
            fh.write(f"g {key}\n")
            for r in mine:
                if r["key"] != key: continue
                for v in r["pts"]:
                    fh.write(f"v {(v[0] - CX) / 24.0:.5f} {v[2] / 24.0:.5f} {-(v[1] - CY) / 24.0:.5f}\n")
                fh.write("f " + " ".join(str(n + i) for i in range(len(r["pts"]))) + "\n"); n += len(r["pts"])


ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "lowpoly")


def body_path(sex, build_name, ext="json"):
    """The game reads the JSON from assets/lowpoly/ (Godot ignores this folder); the OBJ, for looking at in any 3D
    viewer, stays in lowpoly/bodies/."""
    if ext == "json":
        return os.path.join(ASSETS, f"body_{sex}_{build_name}.json")
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "bodies", f"body_{sex}_{build_name}.{ext}")


REGIONS_PATH = os.path.join(ASSETS, "regions.json")


def regions_data():
    """The band table as the game reads it (assets/lowpoly/regions.json; core/region_map.gd): each band's bottom and top
    row (heights, in the files' units, the top one inclusive), the part family it belongs to, and whether it is a
    one-row trim band. The short bodies have the same bands at their own heights (each body file's "heights")."""
    return {"format": "lowpoly_regions", "version": 1,
            "note": "Generated by lowpoly/body.py from its band table (BANDS); regenerate rather than hand-edit.",
            "regions": {k: {"z0": v[0], "z1": v[1] - 1, "part": v[2], "trim": v[3]} for k, v in BANDS.items()}}


if __name__ == "__main__":
    # python3 lowpoly/body.py : rebuild every body file (assets/lowpoly/*.json, lowpoly/bodies/*.obj) and the region table
    os.makedirs(ASSETS, exist_ok=True)
    with open(REGIONS_PATH, "w") as fh:
        json.dump(regions_data(), fh, indent=1)
    for sex, build_name in BODIES:
        b = build(sex, build_name); ok, text = check(b)
        n = counts(b, head=False); print(f"{sex} {build_name}: {n[0]} polygons, {n[1]} triangles without a head, check {'passed' if ok else 'FAILED'}"); print(text)
        if not ok: sys.exit(1)
        write_json(b, body_path(sex, build_name)); write_obj(b, body_path(sex, build_name, "obj"))
