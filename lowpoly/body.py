"""The low-poly bodies the clothing system uses: cut so that their polygons follow the clothing regions.

The clothing parameters address the body by REGION: a band of height on a part family, split left/right, and for the
head and torso also front/back (SPEC 3.4; core/body_layout.gd, core/region_map.gd). So every band boundary here is an
edge loop, every polygon lies in exactly one region, and each polygon is tagged with its region key and its rigid part.

Heights are the voxel rows: the clay's unit is one voxel, so the band table is the same table.

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

# name: (bottom, top, part family, trim) -- core/body_layout.gd BANDS, rows made into heights
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
HEAD_ARC = [22.5, 67.5]

# torso rings, top to bottom: (height, depth offset of the ring's centre). Heights that are band boundaries are fixed;
# the others are shape rings inside a band (shoulder line, upper chest, under the chest, widest hip).
BODIES = {
    ("female", "average"): dict(model=clay.FEM_AVERAGE,
        torso=[(26.6, .35), (26, .35), (25, .5), (24, .5), (22.6, .4), (21.3, .3), (20, .25), (18.4, .25), (17, .2), (15, 0.0), (14, .1), (12.6, .3)]),
    ("male", "average"): dict(model=clay.MASC_AVERAGE,
        torso=[(26.6, .35), (26, .35), (25, .5), (24, .6), (22.75, .45), (21.6, .3), (20, .3), (18.4, .25), (17, .2), (15, .05), (14, .15), (12.6, .3)]),
}
HIP_SEAT_Z = 11.6                       # one extra ring through the fullest part of the seat
HOLE = dict(side=11.0, oblique=10.6, lift=0.7)   # the leg opening: its height at the side, at the front/back obliques, above the crotch
LEG_Z = [9, 7, 6, 3, 2, 1.2]            # band boundaries down the leg; the last ring is hidden inside the foot


def band_at(z, families):
    for name, (z0, z1, fam, _) in BANDS.items():
        if fam in families and z0 <= z < z1:
            return name
    lo = min((b for b in BANDS.items() if b[1][2] in families), key=lambda b: b[1][0])
    hi = max((b for b in BANDS.items() if b[1][2] in families), key=lambda b: b[1][1])
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

def build_skin(spec):
    out = []
    halves = [ring_tools.torso_ring(z, TORSO_COLS, yc) for z, yc in spec["torso"]]
    zs = [z for z, _ in spec["torso"]]
    for i in range(len(halves) - 1):
        u, l = halves[i], halves[i + 1]
        band = "neck" if zs[i] > 26 else band_at(0.5 * (zs[i] + zs[i + 1]), CENTRED)
        for k in range(4):
            out.append(rec([u[k], u[k + 1], l[k + 1], l[k]], band, "L", "F" if k < 2 else "B", "skin", hidden=zs[i] > 26))
    out.append(rec(list(halves[0][::-1]), "neck", "L", "F", "skin", hidden=True))          # top of the neck, inside the head

    yc, zc = ring_tools.crotch()
    j = halves[-1]
    ring_j = np.array(list(j) + [np.array([CX, 0.5 * (j[0][1] + j[-1][1]), zs[-1]])])
    seat = ring_tools.hip_half_ring(HIP_SEAT_Z, TORSO_COLS)
    lo = ring_tools.hip_half_ring(zc + HOLE["lift"], TORSO_COLS); ob = ring_tools.hip_half_ring(HOLE["oblique"], TORSO_COLS); sd = ring_tools.hip_half_ring(HOLE["side"], TORSO_COLS)
    hole = np.array([lo[0], ob[1], sd[2], ob[3], lo[4], np.array([CX, yc, zc])])           # F, A, S, B, R, crotch
    rings = [ring_j, seat, hole] + [ring_tools.leg_ring(z, LEG_COLS) for z in LEG_Z]
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


def build_arm():
    M = ring_tools.M
    keys = ("hand", "forearm", "upper_arm", "deltoid")
    kz = [M[k][0][2] for k in keys]
    cen = lambda z: (CX + np.interp(z, kz, [M[k][0][0] for k in keys]), CY + np.interp(z, kz, [M[k][0][1] for k in keys]))
    top = M["deltoid"][0][2] + M["deltoid"][1]; dz = M["deltoid"][0][2]
    hz = M["hand"][0][2]; hb = hz - M["hand"][1][2]
    zs = [top - 0.22, dz + 0.4, 21, 18, 17, 15, 13, 12, hz + 0.1, hb + 0.35]
    rings = []
    for z in zs:
        o = ring_tools.inside_centre(ring_tools.sdf_arm, cen(z), z, 1.0)
        pts = ring_tools.outline(ring_tools.sdf_arm, o, rmax=5.0)
        rings.append(ring_tools.snap([ring_tools.support(pts, a) for a in ARM_COLS], pts))
    fams = ("upper_arm", "forearm")
    out = [rec(list(rings[0][::-1]), "shoulder", "L", "", "arm_L")]
    for i in range(len(rings) - 1):
        band = band_at(0.5 * (zs[i] + zs[i + 1]), fams)
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


def build_head():
    """The stand-in head, with edges on its region boundaries (heights 31 and 37, the centre line, the side seam)."""
    c, half, r = ring_tools.M["head"]
    c = np.array([CX + c[0], CY + c[1], c[2]]); hx, hy, hz = half
    arcs = np.radians(HEAD_ARC)

    def ring(z, rho):
        ex, ey = (hx - r) + rho, (hy - r) + rho                      # half sizes of this ring
        pts = [np.array([c[0], c[1] - ey, z])]                       # front centre, then round by the figure's left
        for sx, sy, order in ((1, -1, -1), (1, 1, 1), (-1, 1, -1), (-1, -1, 1)):
            corner = [np.array([c[0] + sx * ((hx - r) + rho * np.cos(b)), c[1] + sy * ((hy - r) + rho * np.sin(b)), z]) for b in arcs]
            pts += corner if order > 0 else corner[::-1]
            pts.append({(1, -1): np.array([c[0] + ex, c[1], z]), (1, 1): np.array([c[0], c[1] + ey, z]),
                        (-1, 1): np.array([c[0] - ex, c[1], z]), (-1, -1): None}[(sx, sy)])
        return [p for p in pts if p is not None]                     # 12 points

    levels = [(c[2] + ((hz - r) + r * np.sin(a)), r * np.cos(a)) for a in arcs[::-1]] + [(37.0, r), (31.0, r)] + \
             [(c[2] - ((hz - r) + r * np.sin(a)), r * np.cos(a)) for a in arcs]
    rings = [ring(z, rho) for z, rho in levels]
    fams = ("head",)
    out = []

    def tag(pts):
        m = np.mean(pts, axis=0)
        return ("L" if m[0] > CX else "R"), ("F" if m[1] < CY else "B")

    for (za, _), (zb, _), a, b in zip(levels[:-1], levels[1:], rings[:-1], rings[1:]):
        band = band_at(0.5 * (za + zb), fams)
        band = "lower_head" if band == "neck" else band
        for k in range(12):
            quad = [a[k], a[(k + 1) % 12], b[(k + 1) % 12], b[k]]
            side, face = tag(quad)
            out.append(rec(quad, band, side, face, "head"))
    for rg, band in ((rings[0], "crown"), (rings[-1], "lower_head")):   # caps, cut into four so none crosses a region line
        mid = np.array([c[0], c[1], rg[0][2]])
        for q in range(4):
            quad = [mid] + [rg[(q * 3 + i) % 12] for i in range(4)]
            side, face = tag(quad[1:])
            out.append(rec(quad, band, side, face, "head"))
    return [r for r in out if r is not None]


SDF = dict(skin=lambda p: ring_tools.sdf_skin(p), arm_L=lambda p: ring_tools.sdf_arm(p), arm_R=lambda p: ring_tools.sdf_arm(p),
           foot_L=lambda p: ring_tools.sdf_foot(p), foot_R=lambda p: ring_tools.sdf_foot(p), head=lambda p: ring_tools.sdf_head(p))


def build(sex, build="average"):
    spec = BODIES[(sex, build)]
    ring_tools.use(spec["model"])
    skin, info = build_skin(spec)
    polys = skin + build_arm() + build_foot() + build_head()
    for r in polys:                                                  # wind every polygon outward
        n = ring_tools.normal(r["pts"]); c = r["pts"].mean(axis=0)
        d = SDF[r["piece"]](np.array([c + 0.25 * n, c - 0.25 * n]))
        if d[0] < d[1]:
            r["pts"] = r["pts"][::-1].copy()
    M = spec["model"]
    arm_x = CX + M["upper_arm"][0][0]; leg_x = CX + M["thigh"][0][0]
    pivots = {"pelvis": (CX, CY, 11.0), "chest": (CX, CY, 15.0), "head": (CX, CY, 25.0),
              "upper_arm_L": (arm_x, CY, 24.0), "forearm_L": (arm_x, CY, 17.0), "thigh_L": (leg_x, CY, 11.0), "shin_L": (leg_x, CY, 6.0)}
    for k in list(pivots):
        if k.endswith("_L"):
            x, y, z = pivots[k]; pivots[k[:-1] + "R"] = (2 * CX - x, y, z)
    return dict(sex=sex, build=build, polys=polys, pivots=pivots, info=info)


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
        z0, z1 = BANDS[r["band"]][:2]; lo, hi = r["pts"][:, 2].min(), r["pts"][:, 2].max()
        if lo < z0 - 1e-6 or hi > z1 + 1e-6:
            stray.append((r["key"], round(float(lo), 2), round(float(hi), 2)))
    allowed = ("hips", "upper_thigh", "shoulder", "hand", "foot", "crown", "lower_head")
    bad = [s for s in stray if s[0].split(".")[0] not in allowed]
    ok &= not bad
    lines.append(f"  polygons outside their band's heights: {len(stray)} by design (leg opening, arm and foot ends, head ends)" + (f" | UNEXPECTED: {bad}" if bad else ""))
    return ok, "\n".join(lines)


def counts(body):
    polys = body["polys"]
    return len(polys), sum(len(r["pts"]) - 2 for r in polys)


# ----------------------------------------------------------------------------------------------------- files ---

def to_data(body):
    """The body file's contents: corners (welded within each piece), polygons with their region and part, pivots, bands."""
    index = {}; verts = []

    def vid(piece, v):
        k = (piece, tuple(np.round(v, 4)))
        if k not in index:
            index[k] = len(verts); verts.append([round(float(x), 4) for x in v])
        return index[k]

    polys = [dict(v=[vid(r["piece"], v) for v in r["pts"]], region=r["key"], part=r["part"], piece=r["piece"], hidden=bool(r["hidden"]))
             for r in body["polys"]]
    return {
        "format": "lowpoly_body", "version": 1, "units_per_metre": 24, "facing": "-y", "mirror_plane_x": CX, "depth_centre_y": CY,
        "sex": body["sex"], "build": body["build"],
        "note": "Generated by lowpoly/body.py; regenerate rather than hand-edit. Heights are the old voxel rows. 'hidden' polygons are ends buried inside a neighbouring piece.",
        "parts": {k: {"parent": PARENT[k], "pivot": [float(x) for x in body["pivots"][k]]} for k in PARENT},
        "regions": {k: {"z0": v[0], "z1": v[1] - 1, "part": v[2], "trim": v[3]} for k, v in BANDS.items()},
        "vertices": verts, "polygons": polys,
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
        for key in sorted({r["key"] for r in body["polys"]}):
            fh.write(f"g {key}\n")
            for r in body["polys"]:
                if r["key"] != key: continue
                for v in r["pts"]:
                    fh.write(f"v {(v[0] - CX) / 24.0:.5f} {v[2] / 24.0:.5f} {-(v[1] - CY) / 24.0:.5f}\n")
                fh.write("f " + " ".join(str(n + i) for i in range(len(r["pts"]))) + "\n"); n += len(r["pts"])


def body_path(sex, build_name, ext="json"):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "bodies", f"body_{sex}_{build_name}.{ext}")


if __name__ == "__main__":
    # python3 lowpoly/body.py : rebuild every body file in lowpoly/bodies/
    for sex, build_name in BODIES:
        b = build(sex, build_name); ok, text = check(b)
        n = counts(b); print(f"{sex} {build_name}: {n[0]} polygons, {n[1]} triangles, check {'passed' if ok else 'FAILED'}"); print(text)
        if not ok: sys.exit(1)
        write_json(b, body_path(sex, build_name)); write_obj(b, body_path(sex, build_name, "obj"))
