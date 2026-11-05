#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["PySide6>=6.4", "numpy>=1.22"]
# ///
"""Voxel Wardrobe Studio - desktop editor for hair and clothing on the JRPG voxel base bodies.

Run with uv (no setup):   uv run voxel_wardrobe_studio.py [wardrobe.json]
Or in a venv:             python3 -m venv voxenv && voxenv/bin/python -m pip install PySide6 numpy
                          voxenv/bin/python voxel_wardrobe_studio.py [wardrobe.json]

One wardrobe .json holds every item (with color roles, colorways and male/female tailoring),
the palette and the saved outfits. Exports .vox (MagicaVoxel), .stl (printing) and .obj.
"""
import json, os, re, struct, sys, time, uuid

try:
    import numpy as np
    from PySide6 import QtCore, QtGui, QtWidgets
    from PySide6.QtCore import Qt
except ImportError as e:  # pragma: no cover
    print("Missing package:", e.name, "\nInstall with:  python3 -m pip install PySide6 numpy")
    sys.exit(1)

W, D, H = 24, 15, 36
N_CELLS = W * D * H
DIRS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
VARIANTS = ("both", "male", "female")
CATS = {"hair": 70, "hat": 80, "top": 30, "bottom": 10, "feet": 20, "hands": 40, "belt": 50, "back": 60, "accessory": 55, "other": 45}
SKIN = ((255, 214, 172), (236, 178, 134), (190, 128, 92))
EYE, SHINE = (28, 28, 52), (255, 255, 255)
DEFAULT_PALETTE = [
    ("Navy", "#2d4a9e"), ("Sky", "#5aa0e6"), ("Teal", "#2a9d8f"), ("Mustard", "#e9b949"),
    ("Orange", "#e07a2d"), ("Rust", "#a84a2a"), ("Brown", "#6b4a2e"), ("Tan", "#c8a070"),
    ("Cream", "#f1e6c8"), ("Charcoal", "#3a3a44"), ("Slate", "#6f7a8a"), ("Plum", "#7a4e9e"),
    ("Pink", "#e08ab0"), ("White", "#f6f6f6"), ("Black", "#1a1a20"), ("Olive", "#7d8a3c"),
]
BODY_RLE = {"male": "80a3b2a3b15a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b231a3b2a3b15a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b255a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b12a3b1a3b2a3b1a3b8a3b1a3b2a3b1a3b8a3b1a3b2a3b1a3b12a3b2a3b233a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b16a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b16a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b17a6b185a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b205a14b10a14b10a14b10a14b10a14b10a14b229a8b16a8b16a8b16a8b16a8b16a8b258a4b20a4b20a4b20a4b233a10b14a10b14a10b14a10b14a10b14a10b14a10b14a10b158a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1b1d1c4b1c1d1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b159a8b15a10b14a10b14a10b14a10b14a10b14a10b15a8b824a", "female": "81a2b2a2b17a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b233a2b2a2b17a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b13a2b1a3b2a3b1a2b10a2b1a3b2a3b1a2b10a2b1a3b2a3b1a2b13a3b2a3b233a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b13a8b17a6b210a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b13a8b17a6b210a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b14a6b210a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b14a6b210a6b18a6b14a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b14a6b210a6b18a6b14a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b14a6b210a6b18a6b14a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b14a6b186a2b2a2b18a6b17a8b13a14b10a14b10a14b10a14b14a6b186a2b2a2b18a6b17a8b13a14b10a14b10a14b10a14b14a6b210a6b17a8b13a14b10a14b10a14b10a14b14a6b231a12b12a12b12a12b12a12b12a12b255a6b18a6b18a6b18a6b18a6b283a4b20a4b20a4b257a10b14a10b14a10b14a10b14a10b14a10b14a10b14a10b158a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1c1d1c4b1c1d1c13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b159a8b15a10b14a10b14a10b14a10b14a10b14a10b15a8b824a"}


# ---------------------------------------------------------------- grid helpers
def K(x, y, z): return (z * D + y) * W + x
def unK(k): return k % W, (k // W) % D, k // (W * D)
def inb(x, y, z): return 0 <= x < W and 0 <= y < D and 0 <= z < H


def decode_body(rle):
    g = np.zeros(N_CELLS, dtype=np.int16); p = 0; m = {"a": 0, "b": 1, "c": 8, "d": 9}
    for n, ch in re.findall(r"(\d+)([a-d])", rle):
        n = int(n); v = m[ch]
        if v: g[p:p + n] = v
        p += n
    return g


BODIES = {s: decode_body(r) for s, r in BODY_RLE.items()}


def part_of(x, y, z):
    if z >= 21: return "head"
    if z == 20: return "neck"
    if z == 19 and 10 <= x <= 13: return "neck"
    if x <= 6 or x >= 17: return "hand" if z <= 9 else "arm"
    if z <= 1: return "foot"
    if z <= 7: return "leg"
    return "torso"


PART_ID = {"head": 1, "neck": 2, "arm": 3, "hand": 4, "foot": 5, "leg": 6, "torso": 7}
PARTS = np.array([PART_ID[part_of(*unK(k))] for k in range(N_CELLS)], dtype=np.int8)


def hex_rgb(h): h = h.lstrip("#"); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
def rgb_hex(c): return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in c)
def tones(h):
    c = hex_rgb(h)
    return [tuple(v + (255 - v) * 0.28 for v in c), c, tuple(v * 0.68 for v in c)]


# ---------------------------------------------------------------- model
class Item:
    def __init__(self, name, category, roles=None, colorways=None):
        self.id = "it_" + uuid.uuid4().hex[:8]
        self.name, self.category = name, category
        self.order = CATS.get(category, 45); self.worn = True
        self.roles = list(roles or ["Base"])
        self.colorways = [dict(c) for c in (colorways or [{"name": "Default", "colors": [0]}])]
        self.cw = 0
        self.vox = {v: {} for v in VARIANTS}

    def n_vox(self): return sum(len(m) for m in self.vox.values())
    def color_idx(self, role, npal):
        cols = self.colorways[min(self.cw, len(self.colorways) - 1)]["colors"]
        c = cols[role] if role < len(cols) else 0
        return c if 0 <= c < npal else 0

    def to_json(self):
        return {"id": self.id, "name": self.name, "category": self.category, "order": self.order, "worn": self.worn,
                "roles": list(self.roles), "colorways": [{"name": c["name"], "colors": list(c["colors"])} for c in self.colorways],
                "cw": self.cw, "vox": {v: [n for k, r in self.vox[v].items() for n in (int(k), int(r))] for v in VARIANTS}}

    @staticmethod
    def from_json(o):
        it = Item(str(o.get("name", "Item")), o.get("category") if o.get("category") in CATS else "other")
        it.id = str(o.get("id") or it.id)
        it.order = int(o.get("order", it.order)); it.worn = o.get("worn", True) is not False
        it.roles = [str(r) for r in o.get("roles") or ["Base"]]
        it.colorways = [{"name": str(c.get("name", "Default")), "colors": [int(v) for v in c.get("colors", [])]} for c in o.get("colorways") or []] or [{"name": "Default", "colors": [0]}]
        it.cw = min(int(o.get("cw", 0)), len(it.colorways) - 1)
        for v in VARIANTS:
            a = (o.get("vox") or {}).get(v) or []
            for i in range(0, len(a) - 1, 2):
                k, r = int(a[i]), int(a[i + 1])
                if 0 <= k < N_CELLS: it.vox[v][k] = min(r, len(it.roles) - 1)
        return it


class Wardrobe:
    def __init__(self):
        self.palette = [{"name": n, "hex": h} for n, h in DEFAULT_PALETTE]
        self.items = []; self.outfits = []

    def to_json(self):
        return {"app": "voxel-wardrobe-studio", "version": 2, "grid": [W, D, H], "palette": self.palette,
                "items": [it.to_json() for it in self.items], "outfits": self.outfits}

    @staticmethod
    def from_json(o):
        if not isinstance(o, dict) or o.get("app") != "voxel-wardrobe-studio" or not isinstance(o.get("items"), list):
            raise ValueError("Not a Voxel Wardrobe Studio file.")
        wd = Wardrobe()
        pal = [{"name": str(p.get("name", "?")), "hex": p["hex"] if re.fullmatch(r"#[0-9a-fA-F]{6}", str(p.get("hex", ""))) else "#888888"} for p in o.get("palette") or []]
        if pal: wd.palette = pal
        wd.items = [Item.from_json(x) for x in o["items"]]
        wd.outfits = [{"name": str(x.get("name", "Outfit")), "worn": [{"id": str(w.get("id")), "colorway": int(w.get("colorway", 0))} for w in x.get("worn", [])]} for x in o.get("outfits") or []]
        return wd

    def item_by_id(self, iid): return next((i for i in self.items if i.id == iid), None)
    def palette_index(self, hexcol, name=None):
        hexcol = hexcol.lower()
        for i, p in enumerate(self.palette):
            if p["hex"].lower() == hexcol: return i
        self.palette.append({"name": name or hexcol, "hex": hexcol}); return len(self.palette) - 1


# ---------------------------------------------------------------- composition & shading
def sorted_items(items):
    return [it for _, it in sorted(enumerate(items), key=lambda p: (p[1].order, p[0]))]


def compose(wd, sex, items, body=True, only=None):
    cells = BODIES[sex].copy() if body else np.zeros(N_CELLS, dtype=np.int16)
    npal = len(wd.palette)
    for it in sorted_items(items):
        if only is not None and it is not only: continue
        cols = [100 + it.color_idx(r, npal) for r in range(len(it.roles))]
        for v in ("both", sex):
            m = it.vox[v]
            if m:
                ks = np.fromiter(m.keys(), dtype=np.int64, count=len(m))
                rs = np.fromiter((cols[min(r, len(cols) - 1)] for r in m.values()), dtype=np.int16, count=len(m))
                cells[ks] = rs
    return cells


def _nb(solid, dx, dy, dz):
    """neighbor-solid mask for offset (dx,dy,dz); solid shaped [z,y,x]"""
    out = np.zeros_like(solid)
    zs = slice(max(0, -dz), H - max(0, dz)); ys = slice(max(0, -dy), D - max(0, dy)); xs = slice(max(0, -dx), W - max(0, dx))
    zs2 = slice(max(0, dz), H - max(0, -dz)); ys2 = slice(max(0, dy), D - max(0, -dy)); xs2 = slice(max(0, dx), W - max(0, -dx))
    out[zs, ys, xs] = solid[zs2, ys2, xs2]
    return out


def shade(cells):
    solid = (cells != 0).reshape(H, D, W)
    e = {d: ~_nb(solid, *d) for d in DIRS}
    tone = np.where(e[(0, 0, 1)] | (e[(-1, 0, 0)] & e[(0, -1, 0)]), 0,
                    np.where(e[(0, -1, 0)], 1, np.where(e[(0, 0, -1)] | e[(1, 0, 0)] | e[(0, 1, 0)], 2, 1)))
    return tone.reshape(-1).astype(np.int8)


def color_lut(wd):
    lut = np.zeros((100 + len(wd.palette), 3, 3), dtype=np.float32)
    lut[1] = SKIN; lut[8] = [EYE] * 3; lut[9] = [SHINE] * 3
    for i, p in enumerate(wd.palette): lut[100 + i] = tones(p["hex"])
    return lut


FACE_CORNERS = {
    (1, 0, 0): [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], (-1, 0, 0): [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)],
    (0, 1, 0): [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)], (0, -1, 0): [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
    (0, 0, 1): [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, -1): [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)],
}
FACE_FACTOR = {(1, 0, 0): 0.9, (-1, 0, 0): 0.9, (0, 1, 0): 0.84, (0, -1, 0): 0.97, (0, 0, 1): 1.0, (0, 0, -1): 0.74}


def build_faces(wd, cells):
    """Exposed faces -> corners (N,4,3) world coords, normals (N,3), colors (N,3) uint8, cell keys (N,)"""
    solid = (cells != 0).reshape(H, D, W)
    tone = shade(cells); lut = color_lut(wd)
    base = lut[np.clip(cells, 0, lut.shape[0] - 1), tone]       # (N_CELLS, 3)
    corners, normals, colors, keys = [], [], [], []
    for d in DIRS:
        exposed = solid & ~_nb(solid, *d)
        z, y, x = np.nonzero(exposed)
        if not len(x): continue
        k = (z * D + y) * W + x
        c = np.array(FACE_CORNERS[d], dtype=np.float32)          # (4,3)
        pts = np.stack([x, y, z], axis=1).astype(np.float32)[:, None, :] + c[None, :, :]
        corners.append(pts); normals.append(np.tile(np.array(d, dtype=np.float32), (len(x), 1)))
        colors.append(np.clip(base[k] * FACE_FACTOR[d], 0, 255).astype(np.uint8)); keys.append(k)
    if not corners: return np.zeros((0, 4, 3), np.float32), np.zeros((0, 3), np.float32), np.zeros((0, 3), np.uint8), np.zeros(0, np.int64)
    return np.concatenate(corners), np.concatenate(normals), np.concatenate(colors), np.concatenate(keys)


# ---------------------------------------------------------------- exporters
def baked_palette(wd, cells, tone):
    lut = color_lut(wd); pal, idx, col = [], {}, np.zeros(N_CELLS, dtype=np.int16)
    for k in np.nonzero(cells)[0]:
        rgb = tuple(int(round(v)) for v in lut[cells[k], tone[k]])
        if rgb not in idx:
            if len(pal) < 255: pal.append(rgb); idx[rgb] = len(pal)
            else: idx[rgb] = 1
        col[k] = idx[rgb]
    return pal, col


def write_vox(path, wd, cells, mask=None):
    tone = shade(cells); pal, col = baked_palette(wd, cells, tone)
    ks = np.nonzero(cells if mask is None else (cells != 0) & (mask != 0))[0]
    xyzi = bytearray()
    for k in ks:
        x, y, z = unK(int(k)); xyzi += struct.pack("<BBBB", x, D - 1 - y, z, int(col[k]))
    def chunk(cid, content): return cid + struct.pack("<ii", len(content), 0) + content
    rgba = b"".join(struct.pack("<BBBB", *c, 255) for c in pal) + b"\x00\x00\x00\xff" * (256 - len(pal))
    main = chunk(b"SIZE", struct.pack("<iii", W, D, H)) + chunk(b"XYZI", struct.pack("<i", len(ks)) + bytes(xyzi)) + chunk(b"RGBA", rgba)
    with open(path, "wb") as f: f.write(b"VOX " + struct.pack("<i", 150) + b"MAIN" + struct.pack("<ii", 0, len(main)) + main)
    return len(ks)


def exposed_quads(cells):
    solid = (cells != 0).reshape(H, D, W); out = []
    for d in DIRS:
        z, y, x = np.nonzero(solid & ~_nb(solid, *d))
        for xi, yi, zi in zip(x.tolist(), y.tolist(), z.tolist()):
            out.append((d, [(xi + a, yi + b, zi + c) for a, b, c in FACE_CORNERS[d]], (zi * D + yi) * W + xi))
    return out


def fix_edge_contacts(cells):
    """Fill one voxel of every edge-only contact so the STL is manifold. Returns voxels added."""
    g = cells.reshape(H, D, W); added = 0; changed = True
    while changed:
        changed = False
        for (a, b) in (((0, 0, 1), (0, 1, 0)), ((0, 0, 1), (1, 0, 0)), ((0, 1, 0), (1, 0, 0))):  # axis pairs in (z,y,x) index order
            s = g != 0
            s00 = s[:H - a[0] - b[0], :D - a[1] - b[1], :W - a[2] - b[2]]
            s10 = s[a[0]:H - b[0], a[1]:D - b[1], a[2]:W - b[2]]
            s01 = s[b[0]:H - a[0], b[1]:D - a[1], b[2]:W - a[2]]
            s11 = s[a[0] + b[0]:, a[1] + b[1]:, a[2] + b[2]:]
            m1 = s00 & s11 & ~s10 & ~s01; m2 = s10 & s01 & ~s00 & ~s11
            if m1.any():
                z, y, x = np.nonzero(m1)
                g[z + a[0], y + a[1], x + a[2]] = g[z, y, x]; added += len(x); changed = True
            if m2.any():
                z, y, x = np.nonzero(m2)
                g[z, y, x] = g[z + a[0], y + a[1], x + a[2]]; added += len(x); changed = True
    return added


def count_pieces(cells):
    solid = cells != 0; seen = np.zeros(N_CELLS, dtype=bool); n = 0
    for k0 in np.nonzero(solid)[0]:
        if seen[k0]: continue
        n += 1; seen[k0] = True; st = [int(k0)]
        while st:
            x, y, z = unK(st.pop())
            for dx, dy, dz in DIRS:
                nx, ny, nz = x + dx, y + dy, z + dz
                if inb(nx, ny, nz):
                    nk = K(nx, ny, nz)
                    if solid[nk] and not seen[nk]: seen[nk] = True; st.append(nk)
    return n


def write_stl(path, cells, scale):
    qs = exposed_quads(cells)
    with open(path, "wb") as f:
        f.write(b"voxel wardrobe studio".ljust(80, b" ")); f.write(struct.pack("<I", len(qs) * 2))
        for n, q, _ in qs:
            p = [(vx * scale, (D - vy) * scale, vz * scale) for vx, vy, vz in q]; nn = (n[0], -n[1], n[2])
            for tri in ((p[0], p[1], p[2]), (p[0], p[2], p[3])):
                t = (tri[0], tri[2], tri[1]); f.write(struct.pack("<3f", *nn))
                for v in t: f.write(struct.pack("<3f", *v))
                f.write(b"\x00\x00")


def write_obj(path_base, wd, cells):
    tone = shade(cells); pal, col = baked_palette(wd, cells, tone); name = os.path.basename(path_base)
    verts, vmap, by_mat = [], {}, {}
    def vid(v):
        if v not in vmap: verts.append(v); vmap[v] = len(verts)
        return vmap[v]
    for n, q, k in exposed_quads(cells): by_mat.setdefault(int(col[k]), []).append([vid(v) for v in q])
    with open(path_base + ".mtl", "w") as f:
        for i, c in enumerate(pal, 1): f.write(f"newmtl c{i}\nKd {c[0]/255:.4f} {c[1]/255:.4f} {c[2]/255:.4f}\nKa 0 0 0\nKs 0 0 0\nillum 1\n\n")
    with open(path_base + ".obj", "w") as f:
        f.write(f"mtllib {name}.mtl\no {name}\n")
        for x, y, z in verts: f.write(f"v {x - W/2:.1f} {z:.1f} {-(y - D/2):.1f}\n")
        for c, fl in by_mat.items():
            f.write(f"usemtl c{c}\n")
            for q in fl: f.write("f " + " ".join(map(str, q)) + "\n")


def safe_name(s): return re.sub(r"[^\w\-]+", "_", s).strip("_")[:40] or "x"


# ---------------------------------------------------------------- shell/tight helpers & samples
def shell_cells(base, base_pred, cell_pred=None):
    out = set()
    for k in np.nonzero(base)[0]:
        x, y, z = unK(int(k))
        if not base_pred(x, y, z): continue
        for dx, dy, dz in DIRS:
            nx, ny, nz = x + dx, y + dy, z + dz
            if not inb(nx, ny, nz) or base[K(nx, ny, nz)]: continue
            if cell_pred and not cell_pred(nx, ny, nz): continue
            out.add(K(nx, ny, nz))
    return out


def tight_cells(base, pred):
    return {int(k) for k in np.nonzero(base)[0] if pred(*unK(int(k)))}


def fill(m, r, x0, x1, y0, y1, z0, z1):
    for z in range(z0, z1 + 1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if inb(x, y, z): m[K(x, y, z)] = r


def soft_box(m, r, x0, x1, y0, y1, z0, z1):
    fill(m, r, x0, x1, y0, y1, z0, z1)
    for x in (x0, x1):
        for y in (y0, y1):
            for z in range(z0, z1 + 1): m.pop(K(x, y, z), None)


def make_samples(wd):
    PI = lambda n: next((i for i, p in enumerate(wd.palette) if p["name"] == n), 0)
    cw = lambda name, *names: {"name": name, "colors": [PI(n) for n in names]}
    body = BODIES["male"]; S = {}

    def crop():
        it = Item("Crop hair", "hair", ["Hair"], [cw("Brown", "Brown"), cw("Black", "Black"), cw("Blond", "Mustard"), cw("Red", "Rust"), cw("Grey", "Slate")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: z >= 27): m[k] = 0
        for x in range(7, 17):
            if x % 3 != 1: m[K(x, 1, 26)] = 0
        return it
    def bob():
        it = Item("Bob", "hair", ["Hair"], [cw("Black", "Black"), cw("Brown", "Brown"), cw("Blond", "Mustard"), cw("Pink", "Pink")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: z >= 21, lambda x, y, z: z >= 21 and (y >= 2 or z >= 27)): m[k] = 0
        for x in range(7, 17):
            if x % 3 != 1: m[K(x, 1, 26)] = 0
        for z in range(19, 22):
            for y in range(3, 12):
                for x in (5, 6, 17, 18): m[K(x, y, z)] = 0
            for x in range(5, 19): m[K(x, 11, z)] = 0; m[K(x, 12, z)] = 0
        return it
    def spikes():
        it = Item("Spikes", "hair", ["Hair", "Tips"], [cw("Blond", "Mustard", "Cream"), cw("Black", "Black", "Slate"), cw("Teal", "Teal", "Sky")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: z >= 27): m[k] = 0
        for x in range(7, 17):
            if x % 2 == 1: m[K(x, 1, 26)] = 0
        for x, y, h in ((7, 4, 2), (10, 3, 3), (13, 5, 2), (15, 8, 2), (8, 8, 2), (11, 9, 3), (12, 6, 2)):
            fill(m, 0, x, x + 1, y, y + 1, 32, 32)
            for z in range(33, 33 + h): m[K(x, y, z)] = 1 if z == 32 + h else 0
        return it
    def ponytail():
        it = Item("Ponytail", "hair", ["Hair", "Tie"], [cw("Red", "Rust", "Mustard"), cw("Brown", "Brown", "Cream"), cw("Black", "Black", "Pink")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: z >= 27): m[k] = 0
        for x in range(7, 17):
            if x % 3 != 1: m[K(x, 1, 26)] = 0
        fill(m, 0, 7, 16, 12, 12, 23, 26); fill(m, 0, 11, 12, 11, 11, 9, 22); fill(m, 0, 10, 13, 11, 11, 20, 21); fill(m, 1, 10, 13, 11, 12, 20, 20)
        return it
    def tunic():
        it = Item("Tunic", "top", ["Cloth", "Belt", "Buckle"], [cw("Navy", "Navy", "Brown", "Mustard"), cw("Rust", "Rust", "Charcoal", "Mustard"), cw("Teal", "Teal", "Brown", "Cream"), cw("Plum", "Plum", "Black", "Mustard")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: 9 <= z <= 18 and part_of(x, y, z) in ("torso", "arm"), lambda x, y, z: 9 <= z <= 19): m[k] = 0
        soft_box(m, 0, 6, 17, 1, 12, 6, 8)
        for k in list(m):
            if unK(k)[2] == 12: m[k] = 1
        m[K(11, 2, 12)] = 2; m[K(12, 2, 12)] = 2
        return it
    def tee():
        it = Item("Tee", "top", ["Cloth", "Collar"], [cw("Sky", "Sky", "White"), cw("Orange", "Orange", "Cream"), cw("Charcoal", "Charcoal", "Slate")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: (part_of(x, y, z) == "torso" and 9 <= z <= 18) or (part_of(x, y, z) == "arm" and 15 <= z <= 18), lambda x, y, z: 9 <= z <= 19): m[k] = 0
        for k in shell_cells(body, lambda x, y, z: part_of(x, y, z) == "neck" and z == 20, lambda x, y, z: z == 20): m[k] = 1
        return it
    def cloak():
        it = Item("Cloak", "back", ["Cloth", "Clasp"], [cw("Plum", "Plum", "Mustard"), cw("Olive", "Olive", "Tan"), cw("Black", "Black", "Slate")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: 18 <= z <= 19 and part_of(x, y, z) != "neck", lambda x, y, z: 18 <= z <= 20): m[k] = 0
        fill(m, 0, 6, 17, 11, 11, 4, 17); fill(m, 0, 5, 18, 10, 11, 18, 18); fill(m, 0, 6, 17, 10, 11, 19, 19); m[K(11, 3, 19)] = 1; m[K(12, 3, 19)] = 1
        return it
    def pants():
        it = Item("Pants", "bottom", ["Cloth"], [cw("Charcoal", "Charcoal"), cw("Tan", "Tan"), cw("Navy", "Navy"), cw("Brown", "Brown")]); m = it.vox["both"]
        for k in tight_cells(body, lambda x, y, z: part_of(x, y, z) == "leg"): m[k] = 0
        for k in shell_cells(body, lambda x, y, z: 8 <= z <= 11 and part_of(x, y, z) == "torso", lambda x, y, z: 8 <= z <= 11): m[k] = 0
        return it
    def skirt():
        it = Item("Skirt", "bottom", ["Cloth", "Hem"], [cw("Teal", "Teal", "Cream"), cw("Rust", "Rust", "Mustard"), cw("Black", "Black", "Slate")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: 8 <= z <= 11 and part_of(x, y, z) == "torso", lambda x, y, z: 8 <= z <= 11): m[k] = 0
        soft_box(m, 0, 6, 17, 1, 12, 4, 7)
        for k in list(m):
            if unK(k)[2] == 4: m[k] = 1
        return it
    def boots():
        it = Item("Boots", "feet", ["Leather", "Cuff"], [cw("Brown", "Brown", "Tan"), cw("Black", "Black", "Slate"), cw("Rust", "Rust", "Cream")]); m = it.vox["both"]
        for k in tight_cells(body, lambda x, y, z: z <= 3 and part_of(x, y, z) in ("foot", "leg")): m[k] = 1 if unK(k)[2] == 3 else 0
        return it
    def belt():
        it = Item("Belt", "belt", ["Strap", "Buckle"], [cw("Brown", "Brown", "Mustard"), cw("Black", "Black", "Slate")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: z == 12 and part_of(x, y, z) == "torso", lambda x, y, z: z == 12): m[k] = 0
        m[K(11, 2, 12)] = 1; m[K(12, 2, 12)] = 1
        return it
    def gloves():
        it = Item("Gloves", "hands", ["Leather"], [cw("Tan", "Tan"), cw("Black", "Black"), cw("White", "White")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: part_of(x, y, z) == "hand", lambda x, y, z: z <= 10): m[k] = 0
        return it
    def cap():
        it = Item("Cap", "hat", ["Cloth", "Brim"], [cw("Navy", "Navy", "Sky"), cw("Olive", "Olive", "Tan"), cw("Rust", "Rust", "Cream")]); m = it.vox["both"]
        for k in shell_cells(body, lambda x, y, z: z >= 28, lambda x, y, z: z >= 28): m[k] = 0
        for k in shell_cells(body, lambda x, y, z: z >= 28):
            x, y, z = unK(k)
            if z == 28: m[K(x, y, 27)] = 0
        fill(m, 1, 7, 16, 0, 0, 27, 27); fill(m, 1, 8, 15, 0, 0, 26, 26)
        return it
    for f in (crop, bob, spikes, ponytail, tunic, tee, cloak, pants, skirt, boots, belt, gloves, cap): S[f.__name__] = f
    return S


def starter_wardrobe():
    wd = Wardrobe(); S = make_samples(wd)
    for f in S.values():
        it = f(); it.worn = False; wd.items.append(it)
    byname = {it.name: it for it in wd.items}
    def wear(names, cws=None): return [{"id": byname[n].id, "colorway": (cws[i] if cws else 0)} for i, n in enumerate(names)]
    wd.outfits = [
        {"name": "Adventurer", "worn": wear(["Crop hair", "Tunic", "Pants", "Boots"])},
        {"name": "Traveller", "worn": wear(["Ponytail", "Tee", "Pants", "Boots", "Cloak", "Belt"], [1, 1, 1, 1, 1, 0])},
        {"name": "Villager", "worn": wear(["Bob", "Tee", "Skirt", "Boots", "Cap"], [2, 1, 0, 2, 1])},
    ]
    return wd


# ---------------------------------------------------------------- 3D view
class VoxelView(QtWidgets.QWidget):
    clicked = QtCore.Signal(object, object, int)      # cell, adjacent cell, button
    hovered = QtCore.Signal(object, object)           # cell or None, adjacent

    def __init__(self, app):
        super().__init__(); self.app = app
        self.setMouseTracking(True); self.setFocusPolicy(Qt.StrongFocus); self.setMinimumSize(320, 300)
        self.target = np.array([W / 2, D / 2, 17.0]); self.r = 84.0; self.theta = 0.55; self.phi = 1.25; self.fov = 38.0
        self.corners = np.zeros((0, 4, 3), np.float32); self.normals = np.zeros((0, 3), np.float32); self.colors = np.zeros((0, 3), np.uint8)
        self.occ = np.zeros(N_CELLS, dtype=bool); self.hover_cell = None; self.hover_adj = None
        self._press = None; self._last = None; self._moved = False; self.show_edges = False

    def set_model(self, wd, cells):
        self.corners, self.normals, self.colors, _ = build_faces(wd, cells); self.occ = cells != 0; self.update()

    # camera
    def cam_basis(self):
        sp, cp, st, ct = np.sin(self.phi), np.cos(self.phi), np.sin(self.theta), np.cos(self.theta)
        pos = self.target + self.r * np.array([sp * st, -sp * ct, cp])
        fwd = self.target - pos; fwd /= np.linalg.norm(fwd)
        right = np.cross(fwd, np.array([0, 0, 1.0])); right /= np.linalg.norm(right)
        up = np.cross(right, fwd)
        return pos, right, up, fwd

    def focal(self): return (self.height() / 2) / np.tan(np.radians(self.fov) / 2)

    def view_front(self): self.theta, self.phi = 0.0, 1.35; self.update()
    def view_back(self): self.theta, self.phi = np.pi, 1.35; self.update()
    def zoom(self, f): self.r = float(max(15, min(160, self.r * f))); self.update()

    def ray(self, px, py):
        pos, right, up, fwd = self.cam_basis(); f = self.focal(); cx, cy = self.width() / 2, self.height() / 2
        d = fwd + right * ((px - cx) / f) + up * (-(py - cy) / f); return pos, d / np.linalg.norm(d)

    def pick(self, px, py):
        """3D DDA through the grid; returns (cell, adjacent) or None"""
        o, d = self.ray(px, py)
        # enter the grid bounding box
        tmin, tmax = 0.0, 1e9
        for i, size in enumerate((W, D, H)):
            if abs(d[i]) < 1e-9:
                if o[i] < 0 or o[i] > size: return None
            else:
                t1, t2 = (0 - o[i]) / d[i], (size - o[i]) / d[i]
                tmin, tmax = max(tmin, min(t1, t2)), min(tmax, max(t1, t2))
        if tmax < tmin: return None
        p = o + d * (tmin + 1e-4)
        cell = [int(np.floor(v)) for v in p]
        step = [1 if d[i] > 0 else -1 for i in range(3)]
        tdelta = [abs(1 / d[i]) if abs(d[i]) > 1e-9 else 1e18 for i in range(3)]
        tnext = [((cell[i] + (1 if step[i] > 0 else 0)) - p[i]) / d[i] if abs(d[i]) > 1e-9 else 1e18 for i in range(3)]
        prev = None
        for _ in range(W + D + H + 3):
            x, y, z = cell
            if not inb(x, y, z): return None
            if self.occ[K(x, y, z)]: return (x, y, z), prev
            prev = (x, y, z)
            a = int(np.argmin(tnext)); cell[a] += step[a]; tnext[a] += tdelta[a]
        return None

    def project(self, pts, pos, right, up, fwd):
        rel = pts - pos; zc = rel @ fwd; xc = rel @ right; yc = rel @ up
        f = self.focal(); return xc * f / np.maximum(zc, 1e-3) + self.width() / 2, -yc * f / np.maximum(zc, 1e-3) + self.height() / 2, zc

    def paintEvent(self, ev):
        p = QtGui.QPainter(self); p.fillRect(self.rect(), QtGui.QColor(38, 41, 50))
        pos, right, up, fwd = self.cam_basis()
        # floor grid
        p.setRenderHint(QtGui.QPainter.Antialiasing, True); p.setPen(QtGui.QPen(QtGui.QColor(70, 74, 86), 1))
        g = []
        for i in range(-8, W + 9, 2): g.append(((i, -8, 0), (i, D + 8, 0)))
        for j in range(-8, D + 9, 2): g.append(((-8, j, 0), (W + 8, j, 0)))
        pts = np.array(g, dtype=np.float32).reshape(-1, 3); sx, sy, zc = self.project(pts, pos, right, up, fwd)
        for i in range(0, len(sx), 2):
            if zc[i] > 0.5 and zc[i + 1] > 0.5: p.drawLine(QtCore.QPointF(sx[i], sy[i]), QtCore.QPointF(sx[i + 1], sy[i + 1]))
        p.setRenderHint(QtGui.QPainter.Antialiasing, False)
        if len(self.corners):
            centers = self.corners.mean(axis=1)
            vis = np.einsum("ij,ij->i", self.normals, pos - centers) > 0
            c = self.corners[vis]; cols = self.colors[vis]
            flat = c.reshape(-1, 3); sx, sy, zc = self.project(flat, pos, right, up, fwd)
            sx = sx.reshape(-1, 4); sy = sy.reshape(-1, 4); zc = zc.reshape(-1, 4)
            ok = (zc > 0.3).all(axis=1); depth = zc.mean(axis=1)
            order = np.argsort(-depth[ok]); idx = np.nonzero(ok)[0][order]
            pen = QtGui.QPen(QtGui.QColor(0, 0, 0, 60), 1) if self.show_edges else Qt.NoPen
            p.setPen(pen); PF, PolyF = QtCore.QPointF, QtGui.QPolygonF
            for i in idx.tolist():
                p.setBrush(QtGui.QColor(int(cols[i, 0]), int(cols[i, 1]), int(cols[i, 2])))
                p.drawPolygon(PolyF([PF(sx[i, 0], sy[i, 0]), PF(sx[i, 1], sy[i, 1]), PF(sx[i, 2], sy[i, 2]), PF(sx[i, 3], sy[i, 3])]))
        # slice plane
        if self.app.show_plane:
            a, lv = self.app.axis, self.app.level
            if a == "z": quad = [(0, 0, lv + .5), (W, 0, lv + .5), (W, D, lv + .5), (0, D, lv + .5)]
            elif a == "y": quad = [(0, lv + .5, 0), (W, lv + .5, 0), (W, lv + .5, H), (0, lv + .5, H)]
            else: quad = [(lv + .5, 0, 0), (lv + .5, D, 0), (lv + .5, D, H), (lv + .5, 0, H)]
            sx, sy, zc = self.project(np.array(quad, np.float32), pos, right, up, fwd)
            if (zc > 0.3).all():
                p.setRenderHint(QtGui.QPainter.Antialiasing, True); p.setPen(QtGui.QPen(QtGui.QColor(242, 181, 68, 160), 1)); p.setBrush(QtGui.QColor(242, 181, 68, 40))
                p.drawPolygon(QtGui.QPolygonF([QtCore.QPointF(sx[i], sy[i]) for i in range(4)]))
        # hover box
        hc = self.hover_adj if self.app.tool == "add" else self.hover_cell
        if hc and inb(*hc):
            x, y, z = hc; cube = np.array([(x + a, y + b, z + c) for a in (0, 1) for b in (0, 1) for c in (0, 1)], np.float32)
            sx, sy, zc = self.project(cube, pos, right, up, fwd)
            if (zc > 0.3).all():
                p.setRenderHint(QtGui.QPainter.Antialiasing, True); p.setPen(QtGui.QPen(QtGui.QColor(255, 255, 255), 2)); p.setBrush(Qt.NoBrush)
                for i, j in ((0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3), (2, 6), (3, 7), (4, 5), (4, 6), (5, 7), (6, 7)):
                    p.drawLine(QtCore.QPointF(sx[i], sy[i]), QtCore.QPointF(sx[j], sy[j]))
        p.setPen(QtGui.QColor(169, 173, 184)); p.setFont(QtGui.QFont("monospace", 9))
        p.drawText(10, self.height() - 10, self.app.hud_text)
        p.end()

    # mouse
    def mousePressEvent(self, e):
        self.setFocus(); self._press = (e.position().x(), e.position().y(), e.button(), bool(e.modifiers() & Qt.ShiftModifier)); self._last = self._press[:2]; self._moved = False

    def mouseMoveEvent(self, e):
        x, y = e.position().x(), e.position().y()
        if self._press and (e.buttons() & (Qt.LeftButton | Qt.RightButton | Qt.MiddleButton)):
            if not self._moved and abs(x - self._press[0]) + abs(y - self._press[1]) > 4: self._moved = True
            if self._moved:
                dx, dy = x - self._last[0], y - self._last[1]
                if self._press[3] or self._press[2] == Qt.MiddleButton:
                    pos, right, up, fwd = self.cam_basis(); k = self.r * 0.0016
                    self.target = self.target - right * dx * k + up * dy * k
                else:
                    self.theta -= dx * 0.008; self.phi = float(max(0.15, min(np.pi - 0.15, self.phi - dy * 0.008)))
                self.update()
        else:
            hit = self.pick(x, y)
            self.hover_cell, self.hover_adj = (hit[0], hit[1]) if hit else (None, None)
            self.hovered.emit(self.hover_cell, self.hover_adj); self.update()
        self._last = (x, y)

    def mouseReleaseEvent(self, e):
        if self._press and not self._moved:
            hit = self.pick(e.position().x(), e.position().y())
            if hit: self.clicked.emit(hit[0], hit[1], 2 if self._press[2] == Qt.RightButton else 0)
        self._press = None

    def wheelEvent(self, e): self.zoom(1.1 if e.angleDelta().y() < 0 else 0.9)
    def leaveEvent(self, e): self.hover_cell = None; self.hover_adj = None; self.update()


# ---------------------------------------------------------------- slice view
class SliceView(QtWidgets.QWidget):
    painted = QtCore.Signal(object, int, bool)   # cell, button, stroke_start
    boxed = QtCore.Signal(object, object, int)   # cell a, cell b, button
    stroke_end = QtCore.Signal()

    def __init__(self, app):
        super().__init__(); self.app = app; self.setMouseTracking(True); self.setMinimumHeight(260)
        self.hover = None; self.stroke = None; self.box_start = None; self.seen = set()

    def dims(self):
        a, lv = self.app.axis, self.app.level
        if a == "z": return W, D, (lambda c, r: (c, D - 1 - r, lv))
        if a == "y": return W, H, (lambda c, r: (c, lv, H - 1 - r))
        return D, H, (lambda c, r: (lv, c, H - 1 - r))

    def cell_px(self):
        cols, rows, _ = self.dims(); return max(5, min((self.width() - 2) // cols, (self.height() - 2) // rows))

    def cell_at(self, px, py):
        cols, rows, f = self.dims(); s = self.cell_px(); c, r = int(px // s), int(py // s)
        return (c, r, f(c, r)) if 0 <= c < cols and 0 <= r < rows else None

    def paintEvent(self, ev):
        p = QtGui.QPainter(self); p.fillRect(self.rect(), QtGui.QColor(29, 31, 38))
        cols, rows, f = self.dims(); s = self.cell_px(); app = self.app; wd = app.wd; A = app.active_item()
        bg = (29, 31, 38); mix = lambda a, t: QtGui.QColor(*[int(a[i] + (bg[i] - a[i]) * t) for i in range(3)])
        body = BODIES[app.preview]
        for r in range(rows):
            for c in range(cols):
                x, y, z = f(c, r); k = K(x, y, z); o = app.owner_at(k); col = None
                if o:
                    it, role, var = o; rgb = hex_rgb(wd.palette[it.color_idx(role, len(wd.palette))]["hex"])
                    col = QtGui.QColor(*rgb) if it is A else mix(rgb, 0.55)
                elif body[k] and app.show_body:
                    code = body[k]; col = mix(SKIN[1] if code == 1 else EYE if code == 8 else SHINE, 0.45)
                if col: p.fillRect(c * s + 1, r * s + 1, s - 1, s - 1, col)
                if o and o[0] is A:
                    p.setPen(QtGui.QPen(QtGui.QColor(232, 230, 223), 1)); p.drawRect(c * s + 1, r * s + 1, s - 2, s - 2)
                    if o[2] != "both": p.fillRect(c * s + 1, r * s + 1, 3, 3, QtGui.QColor(232, 230, 223))
        p.setPen(QtGui.QPen(QtGui.QColor(61, 66, 80), 1))
        for c in range(cols + 1): p.drawLine(c * s, 0, c * s, rows * s)
        for r in range(rows + 1): p.drawLine(0, r * s, cols * s, r * s)
        if app.axis != "x":
            pen = QtGui.QPen(QtGui.QColor(242, 181, 68), 1, Qt.DashLine); p.setPen(pen); p.drawLine(W // 2 * s, 0, W // 2 * s, rows * s)
        if self.box_start and self.hover:
            c0, c1 = sorted((self.box_start[0], self.hover[0])); r0, r1 = sorted((self.box_start[1], self.hover[1]))
            p.setPen(QtGui.QPen(QtGui.QColor(242, 181, 68), 2)); p.setBrush(Qt.NoBrush); p.drawRect(c0 * s + 1, r0 * s + 1, (c1 - c0 + 1) * s - 1, (r1 - r0 + 1) * s - 1)
        elif self.hover:
            p.setPen(QtGui.QPen(QtGui.QColor(242, 181, 68), 2)); p.setBrush(Qt.NoBrush); p.drawRect(self.hover[0] * s + 1, self.hover[1] * s + 1, s - 1, s - 1)
        p.end()

    def mousePressEvent(self, e):
        h = self.cell_at(e.position().x(), e.position().y())
        if not h: return
        btn = 2 if e.button() == Qt.RightButton else 0
        if self.app.tool == "box": self.box_start = (h[0], h[1]); self.stroke = ("box", btn); self.update(); return
        self.stroke = ("paint", btn); self.seen = {(h[0], h[1])}; self.painted.emit(h[2], btn, True)

    def mouseMoveEvent(self, e):
        h = self.cell_at(e.position().x(), e.position().y()); self.hover = (h[0], h[1]) if h else None
        if self.stroke and self.stroke[0] == "paint" and h and (h[0], h[1]) not in self.seen:
            self.seen.add((h[0], h[1])); self.painted.emit(h[2], self.stroke[1], False)
        self.update()

    def mouseReleaseEvent(self, e):
        if not self.stroke: return
        if self.stroke[0] == "box" and self.box_start:
            h = self.cell_at(e.position().x(), e.position().y())
            _, _, f = self.dims(); b = h if h else (self.hover[0], self.hover[1], f(*self.hover)) if self.hover else None
            if b: self.boxed.emit(f(*self.box_start), b[2], self.stroke[1])
            self.box_start = None
        self.stroke = None; self.stroke_end.emit(); self.update()

    def leaveEvent(self, e): self.hover = None; self.update()


# ---------------------------------------------------------------- dialogs
class ColorPickDialog(QtWidgets.QDialog):
    def __init__(self, parent, wd, current):
        super().__init__(parent); self.setWindowTitle("Pick a color"); self.wd = wd; self.result_idx = None
        lay = QtWidgets.QVBoxLayout(self); grid = QtWidgets.QGridLayout(); lay.addLayout(grid)
        for i, p in enumerate(wd.palette):
            b = QtWidgets.QPushButton(); b.setFixedSize(34, 30); b.setToolTip(f'{p["name"]} {p["hex"]}')
            b.setStyleSheet(f'background:{p["hex"]}; border: {"3px solid white" if i == current else "1px solid #555"}; border-radius:4px;')
            b.clicked.connect(lambda _=False, i=i: self.choose(i)); grid.addWidget(b, i // 8, i % 8)
        row = QtWidgets.QHBoxLayout(); lay.addLayout(row)
        custom = QtWidgets.QPushButton("Custom color…"); custom.clicked.connect(self.custom); row.addWidget(custom)
        edit = QtWidgets.QPushButton("Edit this palette color…"); edit.clicked.connect(lambda: self.edit(current)); row.addWidget(edit)
        row.addStretch(); cancel = QtWidgets.QPushButton("Cancel"); cancel.clicked.connect(self.reject); row.addWidget(cancel)

    def choose(self, i): self.result_idx = i; self.accept()
    def custom(self):
        c = QtWidgets.QColorDialog.getColor(QtGui.QColor("#888888"), self, "Custom color")
        if c.isValid(): self.result_idx = self.wd.palette_index(c.name()); self.accept()
    def edit(self, i):
        p = self.wd.palette[i]; c = QtWidgets.QColorDialog.getColor(QtGui.QColor(p["hex"]), self, f'Edit "{p["name"]}" (changes every voxel using it)')
        if c.isValid(): p["hex"] = c.name(); self.result_idx = i; self.accept()


class ExportDialog(QtWidgets.QDialog):
    def __init__(self, parent, n_outfits):
        super().__init__(parent); self.setWindowTitle("Export"); lay = QtWidgets.QFormLayout(self)
        self.what = QtWidgets.QComboBox(); self.what.addItems(["Items worn now", f"Every saved outfit ({n_outfits})"]); lay.addRow("Export", self.what)
        self.body = QtWidgets.QComboBox(); self.body.addItems(["Both bodies", "Male body", "Female body"]); lay.addRow("Body", self.body)
        fm = QtWidgets.QHBoxLayout(); self.f_vox = QtWidgets.QCheckBox(".vox"); self.f_stl = QtWidgets.QCheckBox(".stl"); self.f_obj = QtWidgets.QCheckBox(".obj")
        for c in (self.f_vox, self.f_stl, self.f_obj): c.setChecked(True); fm.addWidget(c)
        lay.addRow("Formats", fm)
        self.mm = QtWidgets.QDoubleSpinBox(); self.mm.setRange(0.2, 20); self.mm.setSingleStep(0.5); self.mm.setValue(2.0); self.mm.setSuffix(" mm per voxel"); lay.addRow("STL scale", self.mm)
        self.clothes_only = QtWidgets.QCheckBox("Clothes only (no body)"); lay.addRow("", self.clothes_only)
        self.per_item = QtWidgets.QCheckBox("Also one .vox per worn item"); lay.addRow("", self.per_item)
        bb = QtWidgets.QDialogButtonBox(QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel); bb.accepted.connect(self.accept); bb.rejected.connect(self.reject); lay.addRow(bb)


# ---------------------------------------------------------------- main window
class MainWindow(QtWidgets.QMainWindow):
    TOOLS = [("add", "Add", "Add a voxel on the clicked face (1)"), ("paint", "Paint", "Recolor the clicked voxel, or place one in a body cell (2)"),
             ("erase", "Erase", "Remove a voxel from the active item (3)"), ("pick", "Pick", "Pick the role and item from a voxel (4)"),
             ("box", "Box", "Drag a rectangle in the slice editor (5)"), ("fill", "Fill", "Bucket: recolor a connected region, or fill an enclosed empty area in the slice (6)")]

    def __init__(self, path=None):
        super().__init__(); self.setWindowTitle("Voxel Wardrobe Studio"); self.resize(1500, 940)
        self.settings = QtCore.QSettings("VoxelWardrobe", "Studio")
        self.wd = Wardrobe(); self.path = None; self.dirty = False
        self.active = 0; self.tool = "add"; self.mirror = True; self.preview = "male"; self.target = "both"; self.role = 0
        self.show_body = True; self.show_plane = True; self.solo = False; self.axis = "z"; self.level = 12
        self.undo_stack, self.redo_stack = [], []; self.hud_text = "drag: orbit · shift-drag: pan · wheel: zoom · click: tool"; self._cells = None
        self.build_ui(); self.build_menus()
        opened = False
        p = path or self.settings.value("lastFile", "")
        if p and os.path.exists(p):
            try: self.open_path(p); opened = True
            except Exception as e: self.status(f"Could not open {p}: {e}")
        if not opened: self.wd = starter_wardrobe(); self.wear_outfit(self.wd.outfits[0]); self.active = next(i for i, it in enumerate(self.wd.items) if it.name == "Tunic")
        self.refresh(); self.dirty = False; self.update_title()

    # ---- helpers
    def active_item(self): return self.wd.items[self.active] if 0 <= self.active < len(self.wd.items) else None
    def worn_items(self, no_solo=False):
        items = [it for it in self.wd.items if it.worn]
        if self.solo and not no_solo: a = self.active_item(); items = [a] if a else []
        return items
    def owner_at(self, k):
        for it in reversed(sorted_items(self.worn_items())):
            for v in (self.preview, "both"):
                if k in it.vox[v]: return it, it.vox[v][k], v
        return None
    def status(self, msg, ms=6000): self.statusBar().showMessage(msg, ms)
    def update_title(self):
        name = os.path.basename(self.path) if self.path else "untitled wardrobe"
        self.setWindowTitle(f'{"*" if self.dirty else ""}{name} - Voxel Wardrobe Studio')

    # ---- undo
    def snapshot(self): return json.dumps({"wd": self.wd.to_json(), "active": self.active})
    def restore(self, s):
        o = json.loads(s); self.wd = Wardrobe.from_json(o["wd"]); self.active = min(o["active"], max(0, len(self.wd.items) - 1)); self.clamp_role()
    def push_undo(self): self.undo_stack.append(self.snapshot()); self.undo_stack = self.undo_stack[-60:]; self.redo_stack.clear()
    def undo(self):
        if not self.undo_stack: return
        self.redo_stack.append(self.snapshot()); self.restore(self.undo_stack.pop()); self.changed("Undone")
    def redo(self):
        if not self.redo_stack: return
        self.undo_stack.append(self.snapshot()); self.restore(self.redo_stack.pop()); self.changed("Redone")
    def clamp_role(self):
        it = self.active_item()
        if it: self.role = min(self.role, len(it.roles) - 1)
    def changed(self, msg=None):
        self.dirty = True; self.refresh()
        if msg: self.status(msg)

    # ---- UI construction
    def build_ui(self):
        split = QtWidgets.QSplitter(); self.setCentralWidget(split); hl = split
        # left panel
        left = QtWidgets.QScrollArea(); left.setWidgetResizable(True); left.setMinimumWidth(240); lw = QtWidgets.QWidget(); left.setWidget(lw); L = QtWidgets.QVBoxLayout(lw); L.setSpacing(10)
        # tools
        gb = QtWidgets.QGroupBox("Tool"); g = QtWidgets.QGridLayout(gb); self.tool_btns = {}
        for i, (key, label, tip) in enumerate(self.TOOLS):
            b = QtWidgets.QToolButton(); b.setText(label); b.setToolTip(tip); b.setCheckable(True); b.setChecked(key == "add"); b.setMinimumWidth(80)
            b.clicked.connect(lambda _=False, k=key: self.set_tool(k)); self.tool_btns[key] = b; g.addWidget(b, i // 3, i % 3)
        self.mirror_cb = QtWidgets.QCheckBox("Mirror left/right  (M)"); self.mirror_cb.setChecked(True); self.mirror_cb.toggled.connect(lambda v: setattr(self, "mirror", v)); g.addWidget(self.mirror_cb, 2, 0, 1, 3)
        hint = QtWidgets.QLabel("Right-click erases. The body is never edited; items sit on top of it."); hint.setWordWrap(True); hint.setStyleSheet("color:#999"); g.addWidget(hint, 3, 0, 1, 3)
        L.addWidget(gb)
        # draw into
        gb = QtWidgets.QGroupBox("Draw into"); g = QtWidgets.QHBoxLayout(gb); self.target_btns = {}
        for key, label in (("both", "Shared"), ("male", "Male only"), ("female", "Female only")):
            b = QtWidgets.QRadioButton(label); b.setChecked(key == "both"); b.toggled.connect(lambda v, k=key: v and self.set_target(k)); self.target_btns[key] = b; g.addWidget(b)
        L.addWidget(gb)
        # roles / colorways
        self.roles_box = QtWidgets.QGroupBox("Item colors"); g = QtWidgets.QVBoxLayout(self.roles_box)
        self.roles_list = QtWidgets.QListWidget(); self.roles_list.setMaximumHeight(150); self.roles_list.currentRowChanged.connect(self.on_role_row); self.roles_list.itemDoubleClicked.connect(lambda _: self.role_color()); g.addWidget(self.roles_list)
        r = QtWidgets.QGridLayout(); g.addLayout(r)
        for i, (label, fn) in enumerate((("Color…", self.role_color), ("Add role", self.add_role), ("Rename role", self.rename_role), ("Remove role", self.remove_role))):
            b = QtWidgets.QPushButton(label); b.clicked.connect(fn); r.addWidget(b, i // 2, i % 2)
        hint = QtWidgets.QLabel("A role is a part of the design (Cloth, Trim…). Select one to paint with it; double-click to recolor."); hint.setWordWrap(True); hint.setStyleSheet("color:#999"); g.addWidget(hint)
        r = QtWidgets.QHBoxLayout(); g.addLayout(r); r.addWidget(QtWidgets.QLabel("Colorway")); self.cw_combo = QtWidgets.QComboBox(); self.cw_combo.currentIndexChanged.connect(self.on_cw); r.addWidget(self.cw_combo, 1)
        r = QtWidgets.QHBoxLayout(); g.addLayout(r)
        for label, fn in (("Save as new", self.cw_save), ("Rename", self.cw_rename), ("Delete", self.cw_delete)):
            b = QtWidgets.QPushButton(label); b.clicked.connect(fn); r.addWidget(b)
        L.addWidget(self.roles_box)
        # modify
        gb = QtWidgets.QGroupBox("Modify item"); g = QtWidgets.QGridLayout(gb)
        for i, (label, d) in enumerate((("◀ x", (-1, 0, 0)), ("▲ z", (0, 0, 1)), ("x ▶", (1, 0, 0)), ("front y−", (0, -1, 0)), ("▼ z", (0, 0, -1)), ("back y+", (0, 1, 0)))):
            b = QtWidgets.QPushButton(label); b.clicked.connect(lambda _=False, d=d: self.shift(d)); g.addWidget(b, i // 3, i % 3)
        for i, (label, fn, tip) in enumerate((("Flip left/right", self.flip_x, ""), ("Flip front/back", self.flip_y, ""), ("Grow +1", self.grow, "Add one voxel outward"), ("Shrink −1", self.shrink, "Remove the outer layer"),
                                               ("Hollow", self.hollow, "Remove fully enclosed voxels"), ("Clear voxels", self.clear_item, "Clear the set chosen under Draw into"),
                                               ("Copy slice →", lambda: self.copy_slice(1), "Copy this slice onto the next"), ("Copy slice ←", lambda: self.copy_slice(-1), "Copy this slice onto the previous"),
                                               ("Clear slice", self.clear_slice, ""), ("All → role", self.all_to_role, "Set every voxel of the item to the selected role"))):
            b = QtWidgets.QPushButton(label); b.setToolTip(tip); b.clicked.connect(fn); g.addWidget(b, 2 + i // 2, 0 if i % 2 == 0 else 1, 1, 1 if i % 2 == 0 else 2)
        L.addWidget(gb)
        # wrap
        gb = QtWidgets.QGroupBox("Wrap the body"); g = QtWidgets.QGridLayout(gb)
        g.addWidget(QtWidgets.QLabel("Rows z"), 0, 0); self.wrap_z0 = QtWidgets.QSpinBox(); self.wrap_z0.setRange(0, H - 1); self.wrap_z0.setValue(9); self.wrap_z1 = QtWidgets.QSpinBox(); self.wrap_z1.setRange(0, H - 1); self.wrap_z1.setValue(19)
        r = QtWidgets.QHBoxLayout(); r.addWidget(self.wrap_z0); r.addWidget(QtWidgets.QLabel("to")); r.addWidget(self.wrap_z1); g.addLayout(r, 0, 1)
        self.part_cbs = {}; pg = QtWidgets.QGridLayout()
        for i, (key, label) in enumerate((("torso", "Torso"), ("arm", "Arms"), ("hand", "Hands"), ("leg", "Legs"), ("foot", "Feet"), ("head", "Head"), ("neck", "Neck"))):
            c = QtWidgets.QCheckBox(label); c.setChecked(key in ("torso", "arm")); self.part_cbs[key] = c; pg.addWidget(c, i // 2, i % 2)
        g.addWidget(QtWidgets.QLabel("Parts"), 1, 0); g.addLayout(pg, 1, 1)
        g.addWidget(QtWidgets.QLabel("Fit"), 2, 0); self.wrap_mode = QtWidgets.QComboBox(); self.wrap_mode.addItems(["Shell, 1 voxel outside the body", "Tight, on the body cells"]); g.addWidget(self.wrap_mode, 2, 1)
        self.wrap_over = QtWidgets.QCheckBox("Over worn items too"); self.wrap_over.setChecked(True); g.addWidget(self.wrap_over, 3, 1)
        b = QtWidgets.QPushButton("Wrap"); b.clicked.connect(self.wrap); g.addWidget(b, 3, 0)
        hint = QtWidgets.QLabel("Wraps the male body for Shared and Male-only, the female body for Female-only."); hint.setWordWrap(True); hint.setStyleSheet("color:#999"); g.addWidget(hint, 4, 0, 1, 2)
        L.addWidget(gb); L.addStretch()
        hl.addWidget(left)
        # center
        cw = QtWidgets.QWidget(); cl = QtWidgets.QVBoxLayout(cw); cl.setContentsMargins(0, 0, 0, 0)
        top = QtWidgets.QHBoxLayout(); cl.addLayout(top)
        self.body_combo = QtWidgets.QComboBox(); self.body_combo.addItems(["Male body", "Female body"]); self.body_combo.currentIndexChanged.connect(lambda i: self.set_preview("male" if i == 0 else "female")); top.addWidget(self.body_combo)
        self.show_body_cb = QtWidgets.QCheckBox("Show body"); self.show_body_cb.setChecked(True); self.show_body_cb.toggled.connect(lambda v: (setattr(self, "show_body", v), self.refresh())); top.addWidget(self.show_body_cb)
        self.plane_cb = QtWidgets.QCheckBox("Slice plane"); self.plane_cb.setChecked(True); self.plane_cb.toggled.connect(lambda v: (setattr(self, "show_plane", v), self.view.update())); top.addWidget(self.plane_cb)
        self.solo_cb = QtWidgets.QCheckBox("Solo active item"); self.solo_cb.toggled.connect(lambda v: (setattr(self, "solo", v), self.refresh())); top.addWidget(self.solo_cb)
        self.edges_cb = QtWidgets.QCheckBox("Edges"); self.edges_cb.toggled.connect(lambda v: (setattr(self.view, "show_edges", v), self.view.update())); top.addWidget(self.edges_cb)
        top.addStretch()
        for label, fn in (("Front", lambda: self.view.view_front()), ("Back", lambda: self.view.view_back()), ("+", lambda: self.view.zoom(0.85)), ("−", lambda: self.view.zoom(1.18))):
            b = QtWidgets.QPushButton(label); b.setFixedWidth(50); b.clicked.connect(fn); top.addWidget(b)
        self.view = VoxelView(self); self.view.clicked.connect(self.on_view_click); self.view.hovered.connect(self.on_hover); cl.addWidget(self.view, 1)
        hl.addWidget(cw)
        # right panel
        right = QtWidgets.QScrollArea(); right.setWidgetResizable(True); right.setMinimumWidth(260); rw = QtWidgets.QWidget(); right.setWidget(rw); R = QtWidgets.QVBoxLayout(rw); R.setSpacing(10)
        gb = QtWidgets.QGroupBox("Slice editor"); g = QtWidgets.QVBoxLayout(gb)
        r = QtWidgets.QHBoxLayout(); g.addLayout(r)
        self.axis_combo = QtWidgets.QComboBox(); self.axis_combo.addItems(["Top-down (z rows)", "Front view (y depth)", "Side view (x columns)"]); self.axis_combo.currentIndexChanged.connect(self.on_axis); r.addWidget(self.axis_combo, 1)
        self.level_spin = QtWidgets.QSpinBox(); self.level_spin.setRange(0, H - 1); self.level_spin.setValue(12); self.level_spin.valueChanged.connect(self.set_level); r.addWidget(self.level_spin)
        self.slice = SliceView(self); self.slice.setMinimumHeight(300); self.slice.painted.connect(self.on_slice_paint); self.slice.boxed.connect(self.on_slice_box); self.slice.stroke_end.connect(self.on_slice_end); g.addWidget(self.slice)
        self.slice_info = QtWidgets.QLabel(""); self.slice_info.setStyleSheet("color:#999"); g.addWidget(self.slice_info)
        hint = QtWidgets.QLabel("Click or drag to place; right-click to erase. Box: drag a rectangle. [ and ] change the slice; J jumps to the cell under the 3D cursor."); hint.setWordWrap(True); hint.setStyleSheet("color:#999"); g.addWidget(hint)
        R.addWidget(gb)
        gb = QtWidgets.QGroupBox("Wardrobe"); g = QtWidgets.QVBoxLayout(gb)
        self.items_list = QtWidgets.QListWidget(); self.items_list.setMinimumHeight(200); self.items_list.currentRowChanged.connect(self.on_item_row); self.items_list.itemChanged.connect(self.on_item_check); g.addWidget(self.items_list)
        r = QtWidgets.QGridLayout(); g.addLayout(r)
        for i, (label, fn) in enumerate((("New item…", self.new_item), ("Add sample ▾", self.sample_menu), ("Rename…", self.rename_item), ("Duplicate", self.dup_item), ("Delete", self.delete_item))):
            b = QtWidgets.QPushButton(label); b.clicked.connect(fn); r.addWidget(b, i // 3, i % 3)
        r = QtWidgets.QHBoxLayout(); g.addLayout(r); r.addWidget(QtWidgets.QLabel("Category")); self.cat_combo = QtWidgets.QComboBox(); self.cat_combo.addItems(list(CATS)); self.cat_combo.activated.connect(self.on_cat); r.addWidget(self.cat_combo)
        r.addWidget(QtWidgets.QLabel("Draw order")); self.order_spin = QtWidgets.QSpinBox(); self.order_spin.setRange(0, 200); self.order_spin.editingFinished.connect(self.on_order); r.addWidget(self.order_spin)
        hint = QtWidgets.QLabel("Tick an item to wear it. Higher draw order is drawn on top (hat 80 > hair 70 > cape 60 > top 30 > pants 10)."); hint.setWordWrap(True); hint.setStyleSheet("color:#999"); g.addWidget(hint)
        R.addWidget(gb)
        gb = QtWidgets.QGroupBox("Outfits"); g = QtWidgets.QVBoxLayout(gb)
        self.outfits_list = QtWidgets.QListWidget(); self.outfits_list.setMaximumHeight(140); self.outfits_list.itemDoubleClicked.connect(lambda _: self.wear_selected()); g.addWidget(self.outfits_list)
        r = QtWidgets.QGridLayout(); g.addLayout(r)
        for i, (label, fn) in enumerate((("Wear", self.wear_selected), ("Save worn set…", self.save_outfit), ("Update", self.update_outfit), ("Rename…", self.rename_outfit), ("Delete", self.delete_outfit))):
            b = QtWidgets.QPushButton(label); b.clicked.connect(fn); r.addWidget(b, i // 3, i % 3)
        R.addWidget(gb)
        gb = QtWidgets.QGroupBox("Grid"); g = QtWidgets.QVBoxLayout(gb)
        hint = QtWidgets.QLabel("24 wide × 15 deep × 36 tall. Body stands on z0, faces y0. Head z21–30 (eyes z23–25), shoulders z18, hips z8–12, legs z2–7. Male and female share the head and legs; shells around the male body fit both."); hint.setWordWrap(True); hint.setStyleSheet("color:#999"); g.addWidget(hint)
        R.addWidget(gb); R.addStretch()
        hl.addWidget(right)
        split.setSizes([360, 720, 420]); split.setStretchFactor(1, 1)
        self.statusBar()

    def build_menus(self):
        mb = self.menuBar(); fm = mb.addMenu("&File")
        def act(menu, text, fn, key=None):
            a = QtGui.QAction(text, self); a.triggered.connect(fn)
            if key: a.setShortcut(QtGui.QKeySequence(key))
            menu.addAction(a); return a
        act(fm, "&New empty wardrobe", self.new_empty, "Ctrl+N"); act(fm, "New wardrobe with &samples", self.new_samples)
        act(fm, "&Open…", self.open_dialog, "Ctrl+O"); fm.addSeparator()
        act(fm, "&Save", self.save, "Ctrl+S"); act(fm, "Save &As…", self.save_as, "Ctrl+Shift+S"); fm.addSeparator()
        act(fm, "&Export…", self.export_dialog, "Ctrl+E"); fm.addSeparator(); act(fm, "&Quit", self.close, "Ctrl+Q")
        em = mb.addMenu("&Edit"); act(em, "&Undo", self.undo, "Ctrl+Z"); act(em, "&Redo", self.redo, "Ctrl+Y")
        em.addSeparator()
        for i, (key, label, _) in enumerate(self.TOOLS): act(em, f"Tool: {label}", lambda _=False, k=key: self.set_tool(k), str(i + 1))
        act(em, "Toggle mirror", lambda: self.mirror_cb.setChecked(not self.mirror_cb.isChecked()), "M")
        vm = mb.addMenu("&View")
        act(vm, "Front", self.view.view_front, "F"); act(vm, "Back", self.view.view_back, "B")
        act(vm, "Previous slice", lambda: self.set_level(self.level - 1), "["); act(vm, "Next slice", lambda: self.set_level(self.level + 1), "]")
        act(vm, "Jump slice to hovered cell", self.jump_slice, "J")
        act(vm, "Male body", lambda: self.body_combo.setCurrentIndex(0)); act(vm, "Female body", lambda: self.body_combo.setCurrentIndex(1))

    # ---- refresh
    def refresh(self):
        self._cells = compose(self.wd, self.preview, self.worn_items(), body=self.show_body)
        self.view.set_model(self.wd, self._cells)
        self.refresh_items(); self.refresh_roles(); self.refresh_outfits(); self.slice.update()
        n = sum(1 for it in self.wd.items if it.worn)
        self.slice_info.setText(f"{self.axis} = {self.level}   ·   {len(self.wd.items)} items, {n} worn")
        self.update_title()

    def refresh_items(self):
        lst = self.items_list; lst.blockSignals(True); lst.clear()
        self._item_rows = [i for i, _ in sorted(enumerate(self.wd.items), key=lambda p: (-p[1].order, -p[0]))]
        for i in self._item_rows:
            it = self.wd.items[i]; q = QtWidgets.QListWidgetItem(f"{it.name}   ·  {it.category}, order {it.order}, {it.n_vox()} vox, {len(it.colorways)} colorway{'s' if len(it.colorways) != 1 else ''}")
            q.setFlags(q.flags() | Qt.ItemIsUserCheckable); q.setCheckState(Qt.Checked if it.worn else Qt.Unchecked)
            lst.addItem(q)
        if self.active in self._item_rows: lst.setCurrentRow(self._item_rows.index(self.active))
        it = self.active_item()
        if it: self.cat_combo.setCurrentText(it.category); self.order_spin.setValue(it.order)
        lst.blockSignals(False)

    def refresh_roles(self):
        it = self.active_item(); self.roles_list.blockSignals(True); self.roles_list.clear(); self.cw_combo.blockSignals(True); self.cw_combo.clear()
        self.roles_box.setTitle(f"Item colors - {it.name}" if it else "Item colors")
        if it:
            self.clamp_role()
            for i, name in enumerate(it.roles):
                p = self.wd.palette[it.color_idx(i, len(self.wd.palette))]
                pix = QtGui.QPixmap(18, 18); pix.fill(QtGui.QColor(p["hex"])); q = QtWidgets.QListWidgetItem(QtGui.QIcon(pix), f'{name}  ·  {p["name"]}'); self.roles_list.addItem(q)
            self.roles_list.setCurrentRow(self.role)
            for c in it.colorways: self.cw_combo.addItem(c["name"])
            self.cw_combo.setCurrentIndex(it.cw)
        self.roles_list.blockSignals(False); self.cw_combo.blockSignals(False)

    def refresh_outfits(self):
        lst = self.outfits_list; cur = lst.currentRow(); lst.clear()
        for o in self.wd.outfits:
            names = [self.wd.item_by_id(w["id"]).name for w in o["worn"] if self.wd.item_by_id(w["id"])]
            lst.addItem(f'{o["name"]}   ·  {", ".join(names) or "no items"}')
        if 0 <= cur < lst.count(): lst.setCurrentRow(cur)

    # ---- tool / state setters
    def set_tool(self, t):
        self.tool = t
        for k, b in self.tool_btns.items(): b.setChecked(k == t)
        self.view.update()
    def set_target(self, t):
        self.target = t
        if t != "both" and self.preview != t: self.body_combo.setCurrentIndex(1 if t == "female" else 0); self.status(f"Previewing the {t} body so your edits are visible.")
    def set_preview(self, s):
        self.preview = s; self.refresh()
    def on_axis(self, i): self.axis = "zyx"[i]; self.level_spin.setMaximum({"z": H - 1, "y": D - 1, "x": W - 1}[self.axis]); self.set_level(min(self.level, self.level_spin.maximum()))
    def set_level(self, v):
        self.level = max(0, min(self.level_spin.maximum(), v)); self.level_spin.blockSignals(True); self.level_spin.setValue(self.level); self.level_spin.blockSignals(False)
        self.slice.update(); self.view.update(); self.slice_info.setText(f"{self.axis} = {self.level}")
    def jump_slice(self):
        c = self.view.hover_adj if self.tool == "add" else self.view.hover_cell
        if c: self.set_level(c["zyx".index(self.axis)])
    def on_hover(self, cell, adj):
        if cell is None: self.hud_text = "drag: orbit · shift-drag: pan · wheel: zoom · click: tool"
        else:
            o = self.owner_at(K(*cell)); x, y, z = cell
            self.hud_text = f"x{x} y{y} z{z} · {(o[0].name + ' / ' + o[0].roles[o[1]] + ('' if o[2] == 'both' else ' (' + o[2] + ' only)')) if o else 'body'} · {part_of(x, y, z)}"

    # ---- editing
    def target_map(self, it): return it.vox[self.target]
    def set_vox(self, it, x, y, z, role):
        if not inb(x, y, z): return
        m = self.target_map(it); m[K(x, y, z)] = role
        if self.mirror: m[K(W - 1 - x, y, z)] = role
    def del_vox(self, it, x, y, z):
        for v in VARIANTS:
            it.vox[v].pop(K(x, y, z), None)
            if self.mirror: it.vox[v].pop(K(W - 1 - x, y, z), None)
    def has_vox(self, it, k): return any(k in it.vox[v] for v in VARIANTS)

    def apply_tool(self, tool, cell, adj, stroke_started):
        it = self.active_item(); x, y, z = cell; k = K(x, y, z)
        if tool == "pick":
            o = self.owner_at(k)
            if not o: self.status("That cell is body or empty; nothing to pick."); return False
            self.active = self.wd.items.index(o[0]); self.role = o[1]; self.refresh_items(); self.refresh_roles(); self.status(f'Picked role "{o[0].roles[o[1]]}" of "{o[0].name}"'); return False
        if not it: self.status("Add an item first (Wardrobe panel)."); return False
        if tool == "erase":
            if not self.has_vox(it, k):
                o = self.owner_at(k); self.status(f'That voxel belongs to "{o[0].name}". Select that item to erase it.' if o else "Nothing of the active item here."); return False
            if not stroke_started: self.push_undo()
            self.del_vox(it, x, y, z); return True
        if tool == "add":
            t = adj or cell
            if not t or not inb(*t): self.status("Outside the grid."); return False
            if not stroke_started: self.push_undo()
            self.set_vox(it, *t, self.role); return True
        if tool in ("paint", "box"):
            if not stroke_started: self.push_undo()
            self.set_vox(it, x, y, z, self.role); return True
        if tool == "fill":
            o = self.owner_at(k)
            if o and o[0] is it:
                frm = o[1]
                if frm == self.role: return False
                if not stroke_started: self.push_undo()
                seen = {k}; st = [k]
                while st:
                    c = st.pop()
                    for v in VARIANTS:
                        if it.vox[v].get(c) == frm: it.vox[v][c] = self.role
                    cx, cy, cz = unK(c)
                    for dx, dy, dz in DIRS:
                        nx, ny, nz = cx + dx, cy + dy, cz + dz
                        if not inb(nx, ny, nz): continue
                        nk = K(nx, ny, nz)
                        if nk not in seen and any(it.vox[v].get(nk) == frm for v in VARIANTS): seen.add(nk); st.append(nk)
                return True
            if not o and self._cells is not None and not self._cells[k]:
                fixed = {"z": z, "y": y, "x": x}[self.axis]
                in_slice = lambda cx, cy, cz: {"z": cz, "y": cy, "x": cx}[self.axis] == fixed
                seen = {k}; st = [k]; leak = False
                while st and len(seen) < 2000:
                    cx, cy, cz = unK(st.pop())
                    for dx, dy, dz in DIRS:
                        nx, ny, nz = cx + dx, cy + dy, cz + dz
                        if not in_slice(nx, ny, nz): continue
                        if not inb(nx, ny, nz): leak = True; continue
                        nk = K(nx, ny, nz)
                        if nk in seen or self._cells[nk]: continue
                        seen.add(nk); st.append(nk)
                if leak or len(seen) >= 2000: self.status("That empty area is not enclosed in this slice, so Fill stopped."); return False
                if not stroke_started: self.push_undo()
                m = self.target_map(it)
                for c in seen: m[c] = self.role
                return True
            self.status("Fill works on a voxel of the active item, or on an enclosed empty area in the slice editor."); return False
        return False

    def on_view_click(self, cell, adj, button):
        tool = "erase" if button == 2 else self.tool
        if self.apply_tool(tool, cell, adj, False): self.changed()
    def on_slice_paint(self, cell, button, start):
        if start: self._stroke_started = False
        tool = "erase" if button == 2 else ("paint" if self.tool == "add" else self.tool)
        if tool in ("fill", "pick") and not start: return
        if self.apply_tool(tool, cell, None, self._stroke_started):
            self._stroke_started = True
            self._cells = compose(self.wd, self.preview, self.worn_items(), body=self.show_body); self.slice.update()
    _stroke_started = False
    def on_slice_end(self):
        if self._stroke_started: self._stroke_started = False; self.changed()
        else: self.slice.update()
    def on_slice_box(self, a, b, button):
        it = self.active_item()
        if not it: self.status("Add an item first."); return
        self.push_undo()
        for z in range(min(a[2], b[2]), max(a[2], b[2]) + 1):
            for y in range(min(a[1], b[1]), max(a[1], b[1]) + 1):
                for x in range(min(a[0], b[0]), max(a[0], b[0]) + 1):
                    if button == 2: self.del_vox(it, x, y, z)
                    else: self.set_vox(it, x, y, z, self.role)
        self.changed()

    # ---- roles & colorways
    def on_role_row(self, r):
        if r >= 0: self.role = r
    def role_color(self):
        it = self.active_item()
        if not it: return
        dlg = ColorPickDialog(self, self.wd, it.color_idx(self.role, len(self.wd.palette)))
        if dlg.exec() and dlg.result_idx is not None:
            self.push_undo(); it.colorways[it.cw]["colors"][self.role] = dlg.result_idx; self.changed()
    def add_role(self):
        it = self.active_item()
        if not it: return
        if len(it.roles) >= 8: self.status("Up to 8 roles per item."); return
        name, ok = QtWidgets.QInputDialog.getText(self, "Add role", "Role name:", text=f"Role {len(it.roles) + 1}")
        if not ok: return
        self.push_undo(); it.roles.append(name.strip() or f"Role {len(it.roles) + 1}")
        for c in it.colorways: c["colors"].append(c["colors"][0] if c["colors"] else 0)
        self.role = len(it.roles) - 1; self.changed()
    def rename_role(self):
        it = self.active_item()
        if not it: return
        name, ok = QtWidgets.QInputDialog.getText(self, "Rename role", "Role name:", text=it.roles[self.role])
        if ok and name.strip(): self.push_undo(); it.roles[self.role] = name.strip(); self.changed()
    def remove_role(self):
        it = self.active_item()
        if not it or len(it.roles) <= 1: return
        self.push_undo(); i = self.role; it.roles.pop(i)
        for c in it.colorways: c["colors"].pop(i) if i < len(c["colors"]) else None
        for v in VARIANTS:
            for k, r in list(it.vox[v].items()): it.vox[v][k] = 0 if r == i else (r - 1 if r > i else r)
        self.role = 0; self.changed("Role removed; its voxels moved to the first role.")
    def on_cw(self, i):
        it = self.active_item()
        if it and i >= 0 and i != it.cw: it.cw = i; self.changed()
    def cw_save(self):
        it = self.active_item()
        if not it: return
        name, ok = QtWidgets.QInputDialog.getText(self, "New colorway", "Name:", text=it.colorways[it.cw]["name"] + " copy")
        if not ok: return
        self.push_undo(); it.colorways.append({"name": name.strip() or "Colorway", "colors": list(it.colorways[it.cw]["colors"])}); it.cw = len(it.colorways) - 1; self.changed("New colorway saved; recolor its roles.")
    def cw_rename(self):
        it = self.active_item()
        if not it: return
        name, ok = QtWidgets.QInputDialog.getText(self, "Rename colorway", "Name:", text=it.colorways[it.cw]["name"])
        if ok and name.strip(): self.push_undo(); it.colorways[it.cw]["name"] = name.strip(); self.changed()
    def cw_delete(self):
        it = self.active_item()
        if not it or len(it.colorways) <= 1: return
        self.push_undo(); it.colorways.pop(it.cw); it.cw = max(0, it.cw - 1); self.changed()

    # ---- modify
    def modify(self, fn, msg=None):
        it = self.active_item()
        if not it: self.status("Select an item first."); return
        self.push_undo(); fn(it); self.changed(msg)
    def shift(self, d):
        def f(it):
            for v in VARIANTS:
                m = {}
                for k, r in it.vox[v].items():
                    x, y, z = unK(k)
                    if inb(x + d[0], y + d[1], z + d[2]): m[K(x + d[0], y + d[1], z + d[2])] = r
                it.vox[v] = m
        self.modify(f)
    def flip_x(self): self.modify(lambda it: [it.vox.__setitem__(v, {K(W - 1 - unK(k)[0], unK(k)[1], unK(k)[2]): r for k, r in it.vox[v].items()}) for v in VARIANTS])
    def flip_y(self): self.modify(lambda it: [it.vox.__setitem__(v, {K(unK(k)[0], D - 1 - unK(k)[1], unK(k)[2]): r for k, r in it.vox[v].items()}) for v in VARIANTS])
    def fit_body(self): return BODIES["female" if self.target == "female" else "male"]
    def grow(self):
        def f(it):
            m = self.target_map(it); body = self.fit_body(); add = {}
            for k, r in m.items():
                x, y, z = unK(k)
                for dx, dy, dz in DIRS:
                    nx, ny, nz = x + dx, y + dy, z + dz
                    if inb(nx, ny, nz):
                        nk = K(nx, ny, nz)
                        if nk not in m and not body[nk]: add[nk] = r
            m.update(add)
        self.modify(f, "Grown by one voxel (body cells skipped).")
    def shrink(self):
        def f(it):
            m = self.target_map(it); body = self.fit_body(); rm = []
            for k in m:
                x, y, z = unK(k)
                for dx, dy, dz in DIRS:
                    nx, ny, nz = x + dx, y + dy, z + dz
                    if not inb(nx, ny, nz) or (K(nx, ny, nz) not in m and not body[K(nx, ny, nz)]): rm.append(k); break
            for k in rm: m.pop(k, None)
        self.modify(f, "Outer layer removed.")
    def hollow(self):
        def f(it):
            m = self.target_map(it); body = self.fit_body(); rm = []
            for k in m:
                x, y, z = unK(k)
                if all(inb(x + dx, y + dy, z + dz) and (K(x + dx, y + dy, z + dz) in m or body[K(x + dx, y + dy, z + dz)]) for dx, dy, dz in DIRS): rm.append(k)
            for k in rm: m.pop(k, None)
        self.modify(f, "Enclosed voxels removed.")
    def clear_item(self): self.modify(lambda it: self.target_map(it).clear(), f"Cleared the {self.target} set.")
    def all_to_role(self): self.modify(lambda it: [self.target_map(it).__setitem__(k, self.role) for k in list(self.target_map(it))])
    def slice_pairs(self, lv):
        if self.axis == "z": return [(K(x, y, lv), K(x, y, self.level)) for y in range(D) for x in range(W)]
        if self.axis == "y": return [(K(x, lv, z), K(x, self.level, z)) for z in range(H) for x in range(W)]
        return [(K(lv, y, z), K(self.level, y, z)) for z in range(H) for y in range(D)]
    def copy_slice(self, delta):
        lv = self.level + delta
        if lv < 0 or lv > self.level_spin.maximum(): self.status("No slice there."); return
        def f(it):
            m = self.target_map(it)
            for dst, src in self.slice_pairs(lv):
                if src in m: m[dst] = m[src]
                else: m.pop(dst, None)
        self.modify(f, f"Slice copied to {self.axis}={lv}."); self.set_level(lv)
    def clear_slice(self): self.modify(lambda it: [self.target_map(it).pop(dst, None) for dst, _ in self.slice_pairs(self.level)], "Slice cleared.")
    def wrap(self):
        it = self.active_item()
        if not it: self.status("Add or select an item first."); return
        z0, z1 = sorted((self.wrap_z0.value(), self.wrap_z1.value())); parts = {k for k, c in self.part_cbs.items() if c.isChecked()}
        if not parts: self.status("Pick at least one body part."); return
        sex = "female" if self.target == "female" else "male"
        base = compose(self.wd, sex, [x for x in self.worn_items(no_solo=True) if x is not it]) if self.wrap_over.isChecked() else BODIES[sex]
        pred = lambda x, y, z: z0 <= z <= z1 and part_of(x, y, z) in parts
        cells = tight_cells(base, pred) if self.wrap_mode.currentIndex() == 1 else shell_cells(base, pred, lambda x, y, z: z0 <= z <= z1)
        self.push_undo(); m = self.target_map(it)
        for k in cells: m[k] = self.role
        self.changed(f'Wrapped {len(cells)} voxels into "{it.name}" ({self.target}).')

    # ---- items
    def on_item_row(self, r):
        if 0 <= r < len(self._item_rows):
            self.active = self._item_rows[r]; self.clamp_role(); self.refresh_roles(); self.slice.update()
            it = self.active_item(); self.cat_combo.setCurrentText(it.category); self.order_spin.setValue(it.order)
            if self.solo: self.refresh()
    def on_item_check(self, q):
        r = self.items_list.row(q)
        if 0 <= r < len(self._item_rows): it = self.wd.items[self._item_rows[r]]; it.worn = q.checkState() == Qt.Checked; self.changed()
    def on_cat(self, i):
        it = self.active_item()
        if it and it.category != self.cat_combo.currentText(): self.push_undo(); it.category = self.cat_combo.currentText(); it.order = CATS[it.category]; self.changed()
    def on_order(self):
        it = self.active_item()
        if it and it.order != self.order_spin.value(): self.push_undo(); it.order = self.order_spin.value(); self.changed()
    def new_item(self):
        name, ok = QtWidgets.QInputDialog.getText(self, "New item", "Name:", text=f"Item {len(self.wd.items) + 1}")
        if not ok: return
        cat, ok2 = QtWidgets.QInputDialog.getItem(self, "New item", "Category:", list(CATS), 2, False)
        if not ok2: return
        self.push_undo(); self.wd.items.append(Item(name.strip() or "Item", cat)); self.active = len(self.wd.items) - 1; self.role = 0
        self.changed(f'Added "{name}". Paint, or use Wrap for a quick base.')
    def sample_menu(self):
        menu = QtWidgets.QMenu(self); S = make_samples(self.wd)
        for key, f in S.items():
            menu.addAction(key.capitalize(), lambda _=False, f=f: self.add_sample(f))
        menu.exec(QtGui.QCursor.pos())
    def add_sample(self, f):
        self.push_undo(); it = f(); self.wd.items.append(it); self.active = len(self.wd.items) - 1; self.role = 0; self.changed(f'Added "{it.name}" with {len(it.colorways)} colorways.')
    def rename_item(self):
        it = self.active_item()
        if not it: return
        name, ok = QtWidgets.QInputDialog.getText(self, "Rename item", "Name:", text=it.name)
        if ok and name.strip(): self.push_undo(); it.name = name.strip(); self.changed()
    def dup_item(self):
        it = self.active_item()
        if not it: return
        self.push_undo(); c = Item.from_json(it.to_json()); c.id = "it_" + uuid.uuid4().hex[:8]; c.name = it.name + " copy"; self.wd.items.insert(self.active + 1, c); self.active += 1; self.changed()
    def delete_item(self):
        it = self.active_item()
        if not it: return
        if QtWidgets.QMessageBox.question(self, "Delete item", f'Delete "{it.name}"?') != QtWidgets.QMessageBox.Yes: return
        self.push_undo(); self.wd.items.pop(self.active); self.active = min(self.active, max(0, len(self.wd.items) - 1)); self.changed(f'Deleted "{it.name}".')

    # ---- outfits
    def wear_outfit(self, o):
        for it in self.wd.items: it.worn = False
        for w in o["worn"]:
            it = self.wd.item_by_id(w["id"])
            if it: it.worn = True; it.cw = min(int(w.get("colorway", 0)), len(it.colorways) - 1)
    def sel_outfit(self):
        r = self.outfits_list.currentRow(); return self.wd.outfits[r] if 0 <= r < len(self.wd.outfits) else None
    def wear_selected(self):
        o = self.sel_outfit()
        if o: self.push_undo(); self.wear_outfit(o); self.changed(f'Wearing "{o["name"]}".')
    def save_outfit(self):
        name, ok = QtWidgets.QInputDialog.getText(self, "Save outfit", "Outfit name:", text=f"Outfit {len(self.wd.outfits) + 1}")
        if not ok: return
        self.push_undo(); self.wd.outfits.append({"name": name.strip() or "Outfit", "worn": [{"id": it.id, "colorway": it.cw} for it in self.wd.items if it.worn]}); self.changed(f'Saved outfit "{name}".')
    def update_outfit(self):
        o = self.sel_outfit()
        if o: self.push_undo(); o["worn"] = [{"id": it.id, "colorway": it.cw} for it in self.wd.items if it.worn]; self.changed(f'Outfit "{o["name"]}" updated.')
    def rename_outfit(self):
        o = self.sel_outfit()
        if not o: return
        name, ok = QtWidgets.QInputDialog.getText(self, "Rename outfit", "Name:", text=o["name"])
        if ok and name.strip(): self.push_undo(); o["name"] = name.strip(); self.changed()
    def delete_outfit(self):
        o = self.sel_outfit()
        if o: self.push_undo(); self.wd.outfits.remove(o); self.changed()

    # ---- files
    def maybe_discard(self):
        if not self.dirty: return True
        r = QtWidgets.QMessageBox.question(self, "Unsaved changes", "Save the wardrobe before continuing?", QtWidgets.QMessageBox.Save | QtWidgets.QMessageBox.Discard | QtWidgets.QMessageBox.Cancel)
        if r == QtWidgets.QMessageBox.Save: return self.save()
        return r == QtWidgets.QMessageBox.Discard
    def new_empty(self):
        if not self.maybe_discard(): return
        self.wd = Wardrobe(); self.path = None; self.active = 0; self.undo_stack.clear(); self.redo_stack.clear(); self.refresh(); self.dirty = False; self.update_title()
    def new_samples(self):
        if not self.maybe_discard(): return
        self.wd = starter_wardrobe(); self.wear_outfit(self.wd.outfits[0]); self.path = None; self.active = next(i for i, it in enumerate(self.wd.items) if it.name == "Tunic")
        self.undo_stack.clear(); self.redo_stack.clear(); self.refresh(); self.dirty = False; self.update_title()
    def open_path(self, p):
        with open(p, encoding="utf-8") as f: wd = Wardrobe.from_json(json.load(f))
        self.wd = wd; self.path = p; self.active = 0; self.role = 0; self.undo_stack.clear(); self.redo_stack.clear()
        self.settings.setValue("lastFile", p); self.refresh(); self.dirty = False; self.update_title(); self.status(f"Opened {p}")
    def open_dialog(self):
        if not self.maybe_discard(): return
        start = os.path.dirname(self.path) if self.path else self.settings.value("lastDir", os.path.expanduser("~"))
        p, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Open wardrobe", start, "Wardrobe (*.json);;All files (*)")
        if not p: return
        try: self.open_path(p); self.settings.setValue("lastDir", os.path.dirname(p))
        except Exception as e: QtWidgets.QMessageBox.warning(self, "Open failed", str(e))
    def save(self):
        if not self.path: return self.save_as()
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump(self.wd.to_json(), f, separators=(",", ":"))
        os.replace(tmp, self.path); self.dirty = False; self.update_title(); self.settings.setValue("lastFile", self.path); self.status(f"Saved {self.path}"); return True
    def save_as(self):
        start = self.path or os.path.join(self.settings.value("lastDir", os.path.expanduser("~")), "wardrobe.json")
        p, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Save wardrobe", start, "Wardrobe (*.json)")
        if not p: return False
        if not p.lower().endswith(".json"): p += ".json"
        self.path = p; self.settings.setValue("lastDir", os.path.dirname(p)); return self.save()
    def closeEvent(self, ev):
        if self.maybe_discard(): ev.accept()
        else: ev.ignore()

    # ---- export
    def export_dialog(self):
        dlg = ExportDialog(self, len(self.wd.outfits))
        if not dlg.exec(): return
        folder = QtWidgets.QFileDialog.getExistingDirectory(self, "Export into folder", self.settings.value("exportDir", os.path.expanduser("~")))
        if not folder: return
        self.settings.setValue("exportDir", folder)
        bodies = ["male", "female"] if dlg.body.currentIndex() == 0 else [["male", "female"][dlg.body.currentIndex() - 1]]
        formats = {f for f, c in (("vox", dlg.f_vox), ("stl", dlg.f_stl), ("obj", dlg.f_obj)) if c.isChecked()}
        sets = []
        if dlg.what.currentIndex() == 1:
            for o in self.wd.outfits:
                worn = []
                for w in o["worn"]:
                    it = self.wd.item_by_id(w["id"])
                    if it: worn.append((it, min(int(w.get("colorway", 0)), len(it.colorways) - 1)))
                sets.append((o["name"], worn))
        else:
            sets.append(("outfit", [(it, it.cw) for it in self.worn_items(no_solo=True)]))
        notes, written = [], 0
        QtWidgets.QApplication.setOverrideCursor(Qt.WaitCursor)
        try:
            for label, worn in sets:
                items = []
                for it, cw in worn: it.cw, it._cw_saved = cw, it.cw; items.append(it)
                try:
                    for sex in bodies:
                        cells = compose(self.wd, sex, items, body=not dlg.clothes_only.isChecked()); base = os.path.join(folder, f"{safe_name(label)}_{sex}")
                        if "vox" in formats: write_vox(base + ".vox", self.wd, cells); written += 1
                        if "stl" in formats:
                            pc = cells.copy(); added = fix_edge_contacts(pc); pieces = count_pieces(pc); write_stl(f"{base}_{dlg.mm.value():g}mm.stl", pc, dlg.mm.value()); written += 1
                            if pieces > 1: notes.append(f"{label} {sex}: STL has {pieces} separate pieces (floating voxels will not print)")
                        if "obj" in formats: write_obj(base, self.wd, cells); written += 1
                        if dlg.per_item.isChecked() and "vox" in formats:
                            os.makedirs(os.path.join(folder, "items"), exist_ok=True)
                            for it in items:
                                one = compose(self.wd, sex, items, body=True, only=it); mask = compose(self.wd, sex, items, body=False, only=it)
                                write_vox(os.path.join(folder, "items", f"{safe_name(it.name)}_{safe_name(it.colorways[it.cw]['name'])}_{sex}.vox"), self.wd, one, mask); written += 1
                finally:
                    for it in items: it.cw = it._cw_saved
        finally:
            QtWidgets.QApplication.restoreOverrideCursor()
        self.refresh()
        msg = f"Wrote {written} files to {folder}" + ("\n\n" + "\n".join(notes) if notes else "")
        QtWidgets.QMessageBox.information(self, "Export done", msg); self.status(msg.splitlines()[0])


def main():
    app = QtWidgets.QApplication(sys.argv); app.setStyle("Fusion")
    pal = QtGui.QPalette()
    for role, col in ((QtGui.QPalette.Window, "#262932"), (QtGui.QPalette.WindowText, "#e8e6df"), (QtGui.QPalette.Base, "#1d1f26"), (QtGui.QPalette.AlternateBase, "#262932"),
                      (QtGui.QPalette.Text, "#e8e6df"), (QtGui.QPalette.Button, "#30343f"), (QtGui.QPalette.ButtonText, "#e8e6df"), (QtGui.QPalette.Highlight, "#f2b544"), (QtGui.QPalette.HighlightedText, "#1d1f26"),
                      (QtGui.QPalette.ToolTipBase, "#30343f"), (QtGui.QPalette.ToolTipText, "#e8e6df"), (QtGui.QPalette.PlaceholderText, "#888")):
        pal.setColor(role, QtGui.QColor(col))
    app.setPalette(pal)
    win = MainWindow(sys.argv[1] if len(sys.argv) > 1 else None); win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
