"""The heads: round, boxy, oval, strong and heart, as low-poly forms.

They follow the ideas and proportions of the five voxel heads without tracing them. What every head shares, so that
faces, hair and hats fit any of them:

  - the same size: 16 tall (heights 26 to 42), 14 deep, 16 wide (the oval 14), attached at the neck;
  - a flat face: the two eye boxes and the brow row above them (6 either side of the centre line, heights 29 to 36)
    lie on one plane, the face plane, on every head;
  - the ears, level with the eyes;
  - the same layout of polygons, with an edge on every head region (heights 31 and 37, the centre line, the side seam).

A head is seven sections, top to bottom. Each section is a rounded rectangle: half-width, depth in front of and behind
the centre, and how round the front and back corners are. Those numbers are the whole shape; they play the part the
clay plays for the bodies.

  python3 lowpoly/heads.py     rebuild lowpoly/heads/*.json and *.obj
"""
import json, os, sys
import numpy as np
import body as lb

CX, CY = lb.CX, lb.CY
TOP, BOTTOM = 42.0, 26.0
SECTION_Z = [41.7, 40.3, 37.0, 31.0, 29.0, 27.3, 26.25]
FACE_HALF_WIDTH = 6.0           # the eye boxes reach this far either side of the centre line
FACE_Z = (29.0, 36.0)           # eye boxes (29 to 35) and the brow row above them
FACE_Y = CY - 7.0               # the face plane
EYE_BOX = dict(z=(29.0, 35.0), inner=1.0, outer=6.0, pupil_x=(3.0, 4.0), pupil_z=(31.0, 33.0))

# Per section: (half-width, depth to the front, depth to the back, front corner radius, back corner radius)
HEADS = {
    # a soft block: every edge well rounded, the face a little flatter than the back of the head
    "round": [(5.4, 4.6, 4.8, 2.4, 2.6), (7.7, 6.75, 6.8, 2.0, 3.2), (8.0, 7.0, 7.0, 2.0, 3.4), (8.0, 7.0, 7.0, 2.0, 3.4),
              (8.0, 7.0, 7.0, 2.0, 3.4), (7.6, 6.75, 6.75, 2.0, 3.2), (5.8, 5.2, 5.2, 2.2, 2.6)],
    # square everywhere, with only a small bevel
    "boxy": [(7.1, 6.2, 6.2, 0.8, 0.8), (7.9, 6.95, 6.95, 0.8, 0.8), (8.0, 7.0, 7.0, 0.8, 0.8), (8.0, 7.0, 7.0, 0.8, 0.8),
             (8.0, 7.0, 7.0, 0.8, 0.8), (7.95, 6.95, 6.95, 0.8, 0.8), (7.2, 6.3, 6.3, 0.8, 0.8)],
    # narrower, and tapering toward both the crown and the chin
    "oval": [(3.6, 4.4, 4.6, 1.6, 2.0), (5.6, 6.3, 6.5, 1.2, 2.6), (7.0, 7.0, 7.0, 1.0, 3.0), (7.0, 7.0, 7.0, 1.0, 3.0),
             (7.0, 7.0, 7.0, 1.0, 3.0), (5.6, 6.6, 6.4, 1.2, 2.6), (3.8, 5.2, 4.6, 1.5, 2.0)],
    # a rounded crown over a square jaw that keeps its full width to the bottom
    "strong": [(5.6, 4.8, 5.0, 2.2, 2.4), (7.7, 6.75, 6.8, 1.2, 2.6), (8.0, 7.0, 7.0, 1.2, 2.4), (8.0, 7.0, 7.0, 1.2, 2.4),
               (8.0, 7.0, 7.0, 1.2, 2.4), (8.0, 7.0, 7.0, 1.2, 2.2), (7.7, 6.7, 6.8, 1.0, 1.8)],
    # wide at the brow, narrowing from the cheeks to a pointed chin
    "heart": [(5.4, 4.6, 4.8, 2.4, 2.6), (7.7, 6.75, 6.8, 2.0, 3.2), (8.0, 7.0, 7.0, 2.0, 3.4), (8.0, 7.0, 7.0, 2.0, 3.4),
              (7.0, 7.0, 7.0, 1.0, 3.0), (4.9, 6.6, 6.2, 1.3, 2.4), (2.9, 5.3, 4.2, 1.1, 1.5)],
}
NAMES = list(HEADS)
C45 = float(np.cos(np.radians(45.0)))


def ring(section, z):
    """Sixteen points round one section, from the front centre round the figure's left."""
    w, f, b, rf, rb = section
    half = [(0.0, -f), (w - rf, -f), (w - rf + rf * C45, -f + rf - rf * C45), (w, -f + rf), (w, 0.0),
            (w, b - rb), (w - rb + rb * C45, b - rb + rb * C45), (w - rb, b), (0.0, b)]
    pts = half + [(-x, y) for x, y in half[-2:0:-1]]
    return [np.array([CX + x, CY + y, z]) for x, y in pts]


def width_at(sections, z):
    return float(np.interp(z, SECTION_Z[::-1], [s[0] for s in sections][::-1]))


def build(name):
    """One head as tagged polygons (the same records body.py makes): piece "head", part "head"."""
    sections = HEADS[name]
    rings = [ring(s, z) for s, z in zip(sections, SECTION_Z)]
    out = []

    def tag(pts):
        m = np.mean(pts, axis=0)
        return ("L" if m[0] > CX else "R"), ("F" if m[1] < CY else "B")

    for (za, a), (zb, b) in zip(zip(SECTION_Z[:-1], rings[:-1]), zip(SECTION_Z[1:], rings[1:])):
        band = lb.band_at(0.5 * (za + zb), ("head",))
        band = "lower_head" if band == "neck" else band
        for k in range(16):
            quad = [a[k], a[(k + 1) % 16], b[(k + 1) % 16], b[k]]
            side, face = tag(quad)
            out.append(lb.rec(quad, band, side, face, "head"))
    for rg, band, z in ((rings[0], "crown", TOP), (rings[-1], "lower_head", BOTTOM)):   # ends, cut in four
        mid = np.array([CX, 0.5 * (rg[8][1] + rg[0][1]), z])
        for q in range(4):
            fan = [mid] + [rg[(q * 4 + i) % 16] for i in range(5)]
            side, face = tag(fan[1:])
            out.append(lb.rec(fan, band, side, face, "head"))
    out = [r for r in out if r is not None]
    _wind(out, np.array([CX, CY, 0.5 * (TOP + BOTTOM)]))
    # ears: a small wedge on each side, level with the eyes, flaring toward the back
    for sign, side in ((1.0, "L"), (-1.0, "R")):
        w = width_at(sections, 32.8)
        inner = [(w - 0.3, 0.3, 31.2), (w - 0.3, 2.9, 31.2), (w - 0.3, 2.9, 34.4), (w - 0.3, 0.3, 34.4)]
        outer = [(w + 1.0, 1.2, 31.6), (w + 1.0, 2.9, 31.6), (w + 1.0, 2.9, 34.0), (w + 1.0, 1.2, 34.0)]
        P = lambda p: np.array([CX + sign * p[0], CY + p[1], p[2]])
        i4 = [P(p) for p in inner]; o4 = [P(p) for p in outer]
        faces = [o4, i4[::-1]] + [[i4[k], i4[(k + 1) % 4], o4[(k + 1) % 4], o4[k]] for k in range(4)]
        ear = [lb.rec(fc, "mid_head", side, "B", "head") for fc in faces]
        _wind(ear, np.mean(i4 + o4, axis=0))
        out += ear
    return out


def _wind(polys, middle):
    """Wind every polygon so that it faces away from middle (the shapes here bulge outward everywhere)."""
    for r in polys:
        if lb.ring_tools.normal(r["pts"]) @ (r["pts"].mean(axis=0) - middle) < 0:
            r["pts"] = r["pts"][::-1].copy()


def eye_preview(skin_front=0.04):
    """The standard open eye as flat polygons just in front of the face plane: [(polygon, colour name)].
    Placement only: the eye system itself (lids, brows, colourways) is not rebuilt yet."""
    y = FACE_Y - skin_front; z0, z1 = EYE_BOX["z"]
    out = []
    for sign in (1.0, -1.0):
        x0, x1 = CX + sign * EYE_BOX["inner"], CX + sign * EYE_BOX["outer"]
        xa, xb = min(x0, x1), max(x0, x1)
        white = [(xa + 1, z0), (xb - 1, z0), (xb, z0 + 1), (xb, z1 - 1), (xb - 1, z1), (xa + 1, z1), (xa, z1 - 1), (xa, z0 + 1)]
        out.append((np.array([[x, y, z] for x, z in white]), "eye_white"))
        p0, p1 = CX + sign * EYE_BOX["pupil_x"][0], CX + sign * EYE_BOX["pupil_x"][1]
        pa, pb = min(p0, p1), max(p0, p1); q0, q1 = EYE_BOX["pupil_z"]
        out.append((np.array([[pa, y - 0.02, q0], [pb, y - 0.02, q0], [pb, y - 0.02, q1], [pa, y - 0.02, q1]]), "eye_dark"))
    return out


# ---------------------------------------------------------------------------------------------------- checks ---

def check(name, polys=None):
    polys = polys or build(name)
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
    # the face: between the face heights every section's front is the face plane, flat out past the eye boxes
    face = [s for s, z in zip(HEADS[name], SECTION_Z) if FACE_Z[0] - 1e-6 <= z <= 37.0 + 1e-6]
    reach = min(s[0] - s[3] for s in face)
    flat = all(abs(s[1] - 7.0) < 1e-9 for s in face)
    zone = P[(P[:, 2] >= FACE_Z[0] - 1e-6) & (P[:, 2] <= FACE_Z[1] + 1e-6) & (np.abs(P[:, 0] - CX) <= FACE_HALF_WIDTH + 1e-6) & (P[:, 1] < CY - 6.0)]
    flat &= bool(np.allclose(zone[:, 1], FACE_Y, atol=1e-6))
    ok &= bow == 0 and odd == 0 and keys == want and not stray and flat and reach >= FACE_HALF_WIDTH - 1e-9
    ok &= abs(size[2] - 16.0) < 1e-6 and abs(size[1] - 14.0) < 1e-6
    lines.append(f"  {name:6s}: {len(polys)} polygons | twisted: {bow} | open or doubled edges: {odd} | regions: {len(keys)} of {len(want)}"
                 f" | outside their band: {len(stray)} | size {size[0]:.0f} wide with ears, {size[1]:.0f} deep, {size[2]:.0f} tall"
                 f" | flat face out to {reach:.1f} either side: {'yes' if flat and reach >= FACE_HALF_WIDTH - 1e-9 else 'NO'}")
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

    return {
        "format": "lowpoly_head", "version": 1, "units_per_metre": 24, "facing": "-y", "mirror_plane_x": CX, "depth_centre_y": CY,
        "shape": name, "part": "head", "parent": "chest",
        "note": "Generated by lowpoly/heads.py; regenerate rather than hand-edit. Every corner follows the head part alone.",
        "eye_box": {"plane_y": FACE_Y, "z": list(EYE_BOX["z"]), "brow_z": [35.0, 36.0],
                    "left_x": [CX + EYE_BOX["inner"], CX + EYE_BOX["outer"]], "right_x": [CX - EYE_BOX["outer"], CX - EYE_BOX["inner"]]},
        "sections": [dict(z=z, half_width=s[0], front=s[1], back=s[2], front_corner=s[3], back_corner=s[4]) for s, z in zip(HEADS[name], SECTION_Z)],
        "vertices": verts,
        "polygons": [dict(v=[vid(v) for v in r["pts"]], region=r["key"]) for r in polys],
    }


def head_path(name, ext="json"):
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
    os.makedirs(os.path.dirname(head_path("x")), exist_ok=True)
    for name in NAMES:
        polys = build(name); ok, text = check(name, polys); print(text)
        if not ok: sys.exit(f"{name}: check FAILED")
        with open(head_path(name), "w") as fh:
            json.dump(to_data(name, polys), fh)
        write_obj(name, head_path(name, "obj"), polys)
    print("heads written:", ", ".join(NAMES))
