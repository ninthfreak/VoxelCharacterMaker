"""The heads: round, boxy, oval, strong and heart, as low-poly forms.

They follow the ideas of the five voxel heads (a round one, a square one, a narrow one, one with a strong jaw, one that
tapers to the chin) as rounded forms, like the bodies: a domed crown, a round back, cheeks that turn the corner in
steps, a jaw that tapers. What every head shares, so that faces, hair and hats fit any of them:

  - the same size: 16 tall (heights 26 to 42), 14 deep, 16 wide (the oval 14), attached at the neck;
  - the face: each eye box, with the brow row above it, lies on one flat patch of the head (5 wide from 1 to 6 either
    side of the centre line, heights 29 to 36). FACE_BEND says how the two patches stand to each other: each is
    turned outward by that many degrees, so that the front of the head is round as well (the owner chose 15; 0 would
    put both on one plane, the face plane, as the voxel heads have it). faces.py draws the eyes on them;
  - the ears, level with the eyes;
  - the same layout of polygons, with an edge on every head region (heights 31 and 37, the centre line, the side seam).

A head is seven rings of points, top to bottom, closed by a point at the crown and a flat base. Each ring is given by
three numbers: its half-width, and its depth in front of and behind the centre. Those numbers, and how square the back
is, are the whole shape; they play the part the clay plays for the bodies.

  python3 lowpoly/heads.py     rebuild assets/lowpoly/head_*.json and lowpoly/heads/*.obj
"""
import json, os, sys
import numpy as np
import body as lb

CX, CY = lb.CX, lb.CY
TOP, BOTTOM = 42.0, 26.0
RING_Z = [41.2, 39.4, 37.0, 31.0, 29.0, 27.5, 26.0]
FACE_HALF_WIDTH = 6.0           # the eye boxes reach this far either side of the centre line
FACE_Z = (29.0, 36.0)           # eye boxes (29 to 35) and the brow row above them
BELT = (29.0, 37.0)             # the rings between these heights carry the face; its patches are flat between them
FACE_Y = CY - 7.0               # the face plane: where the face is on the centre line
FACE_BEND = 15.0                # degrees each eye's patch is turned outward from the face plane (owner: 15, not 0)
EYE_BOX = dict(z=(29.0, 35.0), inner=1.0, outer=6.0, pupil_x=(3.0, 4.0), pupil_z=(31.0, 33.0))
ROUND_OFF = [1.0, 0.5, 0.0, 0.0, 0.0, 0.5, 1.0]     # per ring: how far its front has left the face's flatness for a round outline
SEAM = 0.3                      # the side seam (the widest point of a ring) is this far behind the depth centre

# Per head, for the seven rings top to bottom: w half-width, f depth to the front, b depth to the back.
# back: how square the back of the head is from above (2 is an ellipse, more is squarer).
HEADS = {
    # round from every side
    "round": dict(w=[4.2, 6.7, 7.7, 8.0, 7.8, 6.5, 4.4], f=[3.8, 5.8, 7.0, 7.0, 7.0, 6.3, 4.5], b=[3.9, 5.9, 6.8, 7.0, 6.4, 5.3, 3.6], back=2.0),
    # a rounded square: flatter on top, straight sides, a square jaw
    "boxy": dict(w=[5.8, 7.4, 7.9, 8.0, 8.0, 7.6, 6.4], f=[5.0, 6.5, 7.0, 7.0, 7.0, 6.7, 5.6], b=[5.0, 6.5, 6.9, 7.0, 6.8, 6.3, 5.2], back=3.0),
    # narrower, and tapering toward both the crown and the chin: an egg
    "oval": dict(w=[3.3, 5.3, 6.6, 7.0, 6.8, 5.2, 3.0], f=[3.9, 5.9, 7.0, 7.0, 7.0, 6.2, 4.2], b=[4.0, 6.0, 6.8, 7.0, 6.3, 5.2, 3.4], back=2.0),
    # a rounded crown over a jaw that keeps its width to the bottom
    "strong": dict(w=[4.4, 6.8, 7.7, 8.0, 8.0, 7.8, 6.8], f=[3.9, 5.9, 7.0, 7.0, 7.0, 6.9, 6.0], b=[4.0, 6.0, 6.8, 7.0, 6.6, 6.0, 4.8], back=2.4),
    # wide at the brow, narrowing from the cheeks to a pointed chin
    "heart": dict(w=[4.4, 6.8, 7.8, 8.0, 7.5, 5.1, 2.6], f=[3.8, 5.8, 7.0, 7.0, 7.0, 6.2, 4.0], b=[3.9, 5.9, 6.8, 7.0, 6.0, 4.8, 3.2], back=2.0),
}
NAMES = list(HEADS)
HALF = 8                        # points in half a ring: front centre, eye edge, two on the cheek, side seam, two round the back, back centre


def _on_belt(z):
    return BELT[0] - 1e-6 <= z <= BELT[1] + 1e-6


def half_ring(shape, i, bend):
    """Half of ring i of a head: eight points from the front centre round the figure's left to the back centre,
    as (x from the centre line, y from the depth centre)."""
    w, f, b = shape["w"][i], shape["f"][i], shape["b"][i]; z = RING_Z[i]
    tan = float(np.tan(np.radians(bend)))
    if _on_belt(z):
        e = FACE_HALF_WIDTH; drop = e * tan                          # the face: flat from the centre line to the eye's edge
    else:                                                            # crown and jaw: the front rounds off, as the back does
        near = min((j for j in range(len(RING_Z)) if _on_belt(RING_Z[j])), key=lambda j: abs(RING_Z[j] - z))
        e = FACE_HALF_WIDTH * w / shape["w"][near]
        oval = f * (1.0 - float(np.sqrt(max(0.0, 1.0 - (e / w) ** 2))))
        drop = (1.0 - ROUND_OFF[i]) * e * tan + ROUND_OFF[i] * max(oval, e * tan)
    front = np.array([0.0, -f]); edge = np.array([e, -f + drop]); seam = np.array([w, SEAM])
    run = (edge - front) / np.linalg.norm(edge - front)              # the way the face runs where it ends
    dx, dy = seam - edge
    c1 = edge + run * (0.75 * dx / max(run[0], 1e-6)); c2 = seam - np.array([0.0, 0.55 * dy])
    cheek = lambda t: (1 - t) ** 3 * edge + 3 * (1 - t) ** 2 * t * c1 + 3 * (1 - t) * t ** 2 * c2 + t ** 3 * seam
    n = 2.0 / shape["back"]
    back = lambda deg: np.array([w * np.cos(np.radians(deg)) ** n, SEAM + (b - SEAM) * np.sin(np.radians(deg)) ** n])
    return [front, edge, cheek(0.38), cheek(0.72), seam, back(32.0), back(62.0), np.array([0.0, b])]


def rings(name, bend=None):
    """The seven rings of a head, each fourteen points from the front centre round the figure's left."""
    bend = FACE_BEND if bend is None else bend
    out = []
    for i, z in enumerate(RING_Z):
        half = half_ring(HEADS[name], i, bend)
        pts = half + [np.array([-p[0], p[1]]) for p in half[-2:0:-1]]
        out.append([np.array([CX + p[0], CY + p[1], z]) for p in pts])
    return out


def build(name, bend=None):
    """One head as tagged polygons (the same records body.py makes): piece "head", part "head"."""
    rg = rings(name, bend); n = len(rg[0])
    out = []

    def tag(pts):
        m = np.mean(pts, axis=0)
        return ("L" if m[0] > CX else "R"), ("F" if m[1] < CY + SEAM else "B")

    def add(pts, band, at):
        """at: where on the head this polygon is: ("ring", band of rings from the top, place round the ring from the
        front centre by the figure's left), ("crown", place), ("base", quarter) or ("ear", side)."""
        side, face = tag(pts)
        r = lb.rec(pts, band, side, face, "head")
        if r is not None: r["at"] = at; out.append(r)

    for i, ((za, a), (zb, b)) in enumerate(zip(zip(RING_Z[:-1], rg[:-1]), zip(RING_Z[1:], rg[1:]))):
        band = lb.band_at(0.5 * (za + zb), ("head",))
        band = "lower_head" if band == "neck" else band
        for k in range(n):
            add([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]], band, ("ring", i, k))
    crown = np.array([CX, CY + SEAM, TOP])
    for k in range(n):                                               # the crown: a point, joined to the top ring
        add([crown, rg[0][k], rg[0][(k + 1) % n]], "crown", ("crown", k))
    base = np.array([CX, CY + SEAM, BOTTOM]); low = rg[-1]; s = HALF // 2
    for q, run in enumerate((range(0, s + 1), range(s, HALF), range(HALF - 1, n - s + 1), list(range(n - s, n)) + [0])):   # the base: flat, cut in four
        add([base] + [low[k] for k in run], "lower_head", ("base", q))
    _wind(out, np.array([CX, CY, 0.5 * (TOP + BOTTOM)]))
    # ears: a small wedge on each side, level with the eyes, set on the side seam and flaring toward the back
    a, b = rg[RING_Z.index(37.0)], rg[RING_Z.index(31.0)]
    at = lambda k, z: a[k] + (37.0 - z) / 6.0 * (b[k] - a[k])
    for side, k_seam, k_back, sign in (("L", s, s + 1, 1.0), ("R", n - s, n - s - 1, -1.0)):
        root = []
        for z in (31.2, 34.4):
            p, q = at(k_seam, z), at(k_back, z)
            root += [p + 0.1 * (q - p), p + 0.6 * (q - p)]
        lo_f, lo_b, hi_f, hi_b = root
        inner = [v + np.array([-0.35 * sign, 0.0, 0.0]) for v in (lo_f, lo_b, hi_b, hi_f)]           # buried in the head
        tip = lambda v, dy, dz: np.array([CX + sign * (abs(lo_f[0] - CX) + 1.0), v[1] + dy, v[2] + dz])
        outer = [tip(lo_f, 1.0, 0.5), tip(lo_b, 0.4, 0.5), tip(hi_b, 0.4, -0.5), tip(hi_f, 1.0, -0.5)]
        faces = [outer, inner[::-1]] + [[inner[k], inner[(k + 1) % 4], outer[(k + 1) % 4], outer[k]] for k in range(4)]
        ear = [lb.rec(fc, "mid_head", side, "B", "head") for fc in faces]
        for r in ear: r["at"] = ("ear", side)
        _wind(ear, np.mean(inner + outer, axis=0))
        out += ear
    return out


def _wind(polys, middle):
    """Wind every polygon so that it faces away from middle (the shapes here bulge outward everywhere)."""
    for r in polys:
        if lb.ring_tools.normal(r["pts"]) @ (r["pts"].mean(axis=0) - middle) < 0:
            r["pts"] = r["pts"][::-1].copy()


def face_y(x, bend=None):
    """Where the face is, that far from the mirror plane: the face plane, or its two patches."""
    bend = FACE_BEND if bend is None else bend
    return FACE_Y + abs(x - CX) * float(np.tan(np.radians(bend)))


# ---------------------------------------------------------------------------------------------------- checks ---

def check(name, polys=None, bend=None):
    bend = FACE_BEND if bend is None else bend
    polys = polys or build(name, bend)
    ok = True; lines = []
    bow = 0; edges = {}
    for r in polys:
        p = r["pts"]
        if len(p) == 4:
            n1 = np.cross(p[1] - p[0], p[2] - p[0]); n2 = np.cross(p[2] - p[0], p[3] - p[0])
            m1 = np.cross(p[1] - p[0], p[3] - p[0]); m2 = np.cross(p[2] - p[1], p[3] - p[1])
            bow += bool(n1 @ n2 < 0 or m1 @ m2 < 0)
        for i in range(len(p)):
            a = tuple(np.round(p[i], 4)); b = tuple(np.round(p[(i + 1) % len(p)], 4))
            k = (a, b) if a < b else (b, a); edges[k] = edges.get(k, 0) + 1
    odd = sum(1 for v in edges.values() if v != 2)
    P = np.concatenate([r["pts"] for r in polys])
    size = (P[:, 0].max() - P[:, 0].min(), P[:, 1].max() - P[:, 1].min(), P[:, 2].max() - P[:, 2].min())
    keys = {r["key"] for r in polys}
    want = {f"{b}.{s}.{f}" for b in ("crown", "mid_head", "lower_head") for s in "LR" for f in "FB"}
    stray = [r["key"] for r in polys if r["pts"][:, 2].min() < lb.BANDS[r["band"]][0] - 1e-6 or r["pts"][:, 2].max() > lb.BANDS[r["band"]][1] + 1e-6]
    # the face: on every ring that carries it, the front is flat from the centre line out to the eye boxes' edge, and
    # stands where the face stands; and the head is wider than the eye boxes there
    flat = True; room = 99.0
    for i, z in enumerate(RING_Z):
        if not _on_belt(z): continue
        front, edge = half_ring(HEADS[name], i, bend)[:2]
        flat &= abs(CY + front[1] - FACE_Y) < 1e-9 and abs(edge[0] - FACE_HALF_WIDTH) < 1e-9 and abs(CY + edge[1] - face_y(CX + edge[0], bend)) < 1e-9
        room = min(room, HEADS[name]["w"][i] - FACE_HALF_WIDTH)
    covers = min(z for z in RING_Z if _on_belt(z)) <= FACE_Z[0] and max(z for z in RING_Z if _on_belt(z)) >= FACE_Z[1]
    face_ok = flat and covers and room >= 0.5
    tall = abs(size[2] - 16.0) < 1e-6; deep = abs(size[1] - 14.0) < 1e-6
    ok &= bow == 0 and odd == 0 and keys == want and not stray and face_ok and tall and deep
    lines.append(f"  {name:6s}: {len(polys)} polygons | twisted: {bow} | open or doubled edges: {odd} | regions: {len(keys)} of {len(want)}"
                 f" | outside their band: {len(stray)} | size {size[0]:.0f} wide with ears, {size[1]:.0f} deep, {size[2]:.0f} tall"
                 f" | a flat patch for each eye box and its brow: {'yes' if face_ok else 'NO'} ({room:.1f} to spare at the side)")
    return ok, "\n".join(lines)


# ----------------------------------------------------------------------------------------------------- files ---

def to_data(name, polys=None):
    polys = polys or build(name)
    index = {}; verts = []

    def vid(v):
        k = tuple(float(x) for x in np.round(v, 4))
        if k not in index:
            index[k] = len(verts); verts.append([round(float(x), 4) for x in v])
        return index[k]

    shape = HEADS[name]
    return {
        "format": "lowpoly_head", "version": 2, "units_per_metre": 24, "facing": "-y", "mirror_plane_x": CX, "depth_centre_y": CY,
        "shape": name, "part": "head", "parent": "chest",
        "note": "Generated by lowpoly/heads.py; regenerate rather than hand-edit. Every corner follows the head part alone.",
        "eye_box": {"plane_y": FACE_Y, "bend_degrees": FACE_BEND,
                    "where": "y = plane_y + |x - mirror_plane_x| * tan(bend_degrees): each eye box and its brow row lie on one flat patch",
                    "z": list(EYE_BOX["z"]), "brow_z": [35.0, 36.0],
                    "left_x": [CX + EYE_BOX["inner"], CX + EYE_BOX["outer"]], "right_x": [CX - EYE_BOX["outer"], CX - EYE_BOX["inner"]]},
        "rings": [dict(z=z, half_width=shape["w"][i], front=shape["f"][i], back=shape["b"][i]) for i, z in enumerate(RING_Z)],
        "back_squareness": shape["back"],
        "vertices": verts,
        "polygons": [dict(v=[vid(v) for v in r["pts"]], region=r["key"]) for r in polys],
    }


def head_path(name, ext="json"):
    """The game reads the JSON from assets/lowpoly/; the OBJ stays in lowpoly/heads/ (see body.body_path)."""
    if ext == "json":
        return os.path.join(lb.ASSETS, f"head_{name}.json")
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "heads", f"head_{name}.{ext}")


def write_obj(name, path, polys=None):
    polys = polys or build(name)
    with open(path, "w") as fh:
        fh.write(f"# low-poly head '{name}', polygons grouped by region. Metres. Y up, the face toward +Z.\n")
        n = 1
        for key in sorted({r["key"] for r in polys}):
            fh.write(f"g {key}\n")
            for r in polys:
                if r["key"] != key: continue
                for v in r["pts"]:
                    fh.write(f"v {(v[0] - CX) / 24.0:.5f} {v[2] / 24.0:.5f} {-(v[1] - CY) / 24.0:.5f}\n")
                fh.write("f " + " ".join(str(n + i) for i in range(len(r["pts"]))) + "\n"); n += len(r["pts"])


if __name__ == "__main__":
    os.makedirs(os.path.dirname(head_path("x")), exist_ok=True); os.makedirs(os.path.dirname(head_path("x", "obj")), exist_ok=True)
    for name in NAMES:
        polys = build(name); ok, text = check(name, polys); print(text)
        if not ok: sys.exit(f"{name}: check FAILED")
        with open(head_path(name), "w") as fh:
            json.dump(to_data(name, polys), fh)
        write_obj(name, head_path(name, "obj"), polys)
    print("heads written:", ", ".join(NAMES))
