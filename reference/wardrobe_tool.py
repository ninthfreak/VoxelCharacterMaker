#!/usr/bin/env python3
"""Command-line companion to Voxel Wardrobe Studio.

Reads a wardrobe .json saved by the studio and exports outfits on either base body,
with the same baked shading and the same file formats as the app (vox, stl, obj).
No third-party packages needed.

  python3 wardrobe_tool.py list   wardrobe.json
  python3 wardrobe_tool.py export wardrobe.json --outfit Adventurer --body both --out exports
  python3 wardrobe_tool.py export wardrobe.json --items "Tunic:Rust,Pants,Boots" --body female --mm 2.5
  python3 wardrobe_tool.py export wardrobe.json --all-outfits --out exports

--items takes item names, optionally with ":colorway" (name or index). --outfit uses a saved outfit.
Add --no-body to export the clothes alone, --formats vox,stl,obj to choose formats.
"""
import argparse, json, os, re, struct, sys

W, D, H = 24, 15, 36
DIRS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
SKIN = [(255, 214, 172), (236, 178, 134), (190, 128, 92)]
EYE, SHINE = (28, 28, 52), (255, 255, 255)

BODY_RLE = {
    "male": "80a3b2a3b15a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b231a3b2a3b15a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b14a4b2a4b255a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b12a3b1a3b2a3b1a3b8a3b1a3b2a3b1a3b8a3b1a3b2a3b1a3b12a3b2a3b233a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b16a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b16a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b17a6b186a6b17a8b12a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b8a3b1a8b1a3b12a8b17a6b185a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b184a8b15a10b11a16b8a16b8a16b8a16b11a10b15a8b205a14b10a14b10a14b10a14b10a14b10a14b229a8b16a8b16a8b16a8b16a8b16a8b258a4b20a4b20a4b20a4b233a10b14a10b14a10b14a10b14a10b14a10b14a10b14a10b158a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1b1d1c4b1c1d1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b159a8b15a10b14a10b14a10b14a10b14a10b14a10b15a8b824a",
    "female": "81a2b2a2b17a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b233a2b2a2b17a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b16a3b2a3b256a3b2a3b13a2b1a3b2a3b1a2b10a2b1a3b2a3b1a2b10a2b1a3b2a3b1a2b13a3b2a3b233a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b13a8b17a6b210a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b13a8b17a6b210a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b14a6b210a6b17a8b13a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b10a2b1a8b1a2b14a6b210a6b18a6b14a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b14a6b210a6b18a6b14a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b14a6b210a6b18a6b14a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b10a2b2a6b2a2b14a6b186a2b2a2b18a6b17a8b13a14b10a14b10a14b10a14b14a6b186a2b2a2b18a6b17a8b13a14b10a14b10a14b10a14b14a6b210a6b17a8b13a14b10a14b10a14b10a14b14a6b231a12b12a12b12a12b12a12b12a12b255a6b18a6b18a6b18a6b18a6b283a4b20a4b20a4b257a10b14a10b14a10b14a10b14a10b14a10b14a10b14a10b158a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1b2c4b2c1b13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a1c1d1c4b1c1d1c13a12b12a12b12a12b11a14b10a14b11a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b134a10b13a12b12a12b12a12b12a12b12a12b12a12b12a12b12a12b13a10b159a8b15a10b14a10b14a10b14a10b14a10b14a10b15a8b824a",
}


def K(x, y, z): return (z * D + y) * W + x
def unK(k): return k % W, (k // W) % D, k // (W * D)
def inb(x, y, z): return 0 <= x < W and 0 <= y < D and 0 <= z < H


def decode_body(rle):
    g = [0] * (W * D * H); p = 0; m = {"a": 0, "b": 1, "c": 8, "d": 9}
    for n, ch in re.findall(r"(\d+)([a-d])", rle):
        n = int(n); v = m[ch]
        if v:
            for i in range(p, p + n): g[i] = v
        p += n
    return g


BODIES = {s: decode_body(r) for s, r in BODY_RLE.items()}


def hex_rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def tones(h):
    c = hex_rgb(h)
    return [tuple(v + (255 - v) * 0.28 for v in c), c, tuple(v * 0.68 for v in c)]


class Wardrobe:
    def __init__(self, data):
        if data.get("app") != "voxel-wardrobe-studio":
            raise SystemExit("Not a Voxel Wardrobe Studio file (open and re-save it in the studio).")
        self.palette = data["palette"]
        self.items = data["items"]
        self.outfits = data.get("outfits", [])
        self.tc = [tones(p["hex"]) for p in self.palette]

    def item(self, name):
        for it in self.items:
            if it["name"].lower() == name.lower() or it["id"] == name: return it
        raise SystemExit(f'No item named "{name}". Use "list" to see items.')

    def colorway_index(self, it, cw):
        if cw is None: return it.get("cw", 0)
        if isinstance(cw, int) or str(cw).isdigit(): return min(int(cw), len(it["colorways"]) - 1)
        for i, c in enumerate(it["colorways"]):
            if c["name"].lower() == str(cw).lower(): return i
        raise SystemExit(f'Item "{it["name"]}" has no colorway "{cw}".')

    def compose(self, sex, worn, body=True, only=None):
        """worn: list of (item, colorway index). Returns cells (0 empty, 1 skin, 8 eye, 9 shine, 100+palette idx)."""
        cells = list(BODIES[sex]) if body else [0] * (W * D * H)
        order = sorted(enumerate(worn), key=lambda p: (p[1][0].get("order", 45), p[0]))
        for _, (it, cw) in order:
            if only is not None and it is not only: continue
            colors = it["colorways"][cw]["colors"]
            for variant in ("both", sex):
                v = it["vox"].get(variant, [])
                for i in range(0, len(v) - 1, 2):
                    role = v[i + 1]
                    pi = colors[role] if role < len(colors) else 0
                    if pi >= len(self.palette): pi = 0
                    cells[v[i]] = 100 + pi
        return cells

    def color_of(self, code, t):
        if code == 1: return SKIN[t]
        if code == 8: return EYE
        if code == 9: return SHINE
        return self.tc[code - 100][t]


def shade(cells):
    tone = [1] * (W * D * H)
    def empty(x, y, z): return not inb(x, y, z) or cells[K(x, y, z)] == 0
    for z in range(H):
        for y in range(D):
            for x in range(W):
                k = K(x, y, z)
                if not cells[k]: continue
                if empty(x, y, z + 1) or (empty(x - 1, y, z) and empty(x, y - 1, z)): tone[k] = 0
                elif empty(x, y - 1, z): tone[k] = 1
                elif empty(x, y, z - 1) or empty(x + 1, y, z) or empty(x, y + 1, z): tone[k] = 2
    return tone


def baked_palette(wd, cells, tone):
    pal, idx, col = [], {}, [0] * len(cells)
    for k, c in enumerate(cells):
        if not c: continue
        rgb = tuple(int(round(v)) for v in wd.color_of(c, tone[k]))
        if rgb not in idx:
            if len(pal) < 255: pal.append(rgb); idx[rgb] = len(pal)
            else: idx[rgb] = 1
        col[k] = idx[rgb]
    return pal, col


def write_vox(path, wd, cells, tone, mask=None):
    pal, col = baked_palette(wd, cells, tone)
    xyzi = bytearray(); n = 0
    for z in range(H):
        for y in range(D):
            for x in range(W):
                k = K(x, y, z)
                if not cells[k] or (mask is not None and not mask[k]): continue
                xyzi += struct.pack("<BBBB", x, D - 1 - y, z, col[k]); n += 1
    def chunk(cid, content): return cid + struct.pack("<ii", len(content), 0) + content
    rgba = b"".join(struct.pack("<BBBB", *c, 255) for c in pal) + b"\x00\x00\x00\xff" * (256 - len(pal))
    main = chunk(b"SIZE", struct.pack("<iii", W, D, H)) + chunk(b"XYZI", struct.pack("<i", n) + bytes(xyzi)) + chunk(b"RGBA", rgba)
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", 150) + b"MAIN" + struct.pack("<ii", 0, len(main)) + main)
    return n


FACES = {
    (1, 0, 0): [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], (-1, 0, 0): [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)],
    (0, 1, 0): [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)], (0, -1, 0): [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
    (0, 0, 1): [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, -1): [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)],
}


def quads(cells):
    def empty(x, y, z): return not inb(x, y, z) or cells[K(x, y, z)] == 0
    out = []
    for z in range(H):
        for y in range(D):
            for x in range(W):
                k = K(x, y, z)
                if not cells[k]: continue
                for n in DIRS:
                    if empty(x + n[0], y + n[1], z + n[2]):
                        out.append((n, [(x + a, y + b, z + c) for a, b, c in FACES[n]], k))
    return out


def fix_edge_contacts(cells):
    """Fill one voxel of every edge-only contact so the STL is manifold. Returns voxels added."""
    E = [(1, 0, 0), (0, 1, 0), (0, 0, 1)]; added = 0; changed = True
    while changed:
        changed = False
        for ai in range(3):
            for bi in range(ai + 1, 3):
                ea, eb = E[ai], E[bi]
                for z in range(H):
                    for y in range(D):
                        for x in range(W):
                            x1, y1, z1 = x + ea[0] + eb[0], y + ea[1] + eb[1], z + ea[2] + eb[2]
                            if not inb(x1, y1, z1): continue
                            k00, k10 = K(x, y, z), K(x + ea[0], y + ea[1], z + ea[2])
                            k01, k11 = K(x + eb[0], y + eb[1], z + eb[2]), K(x1, y1, z1)
                            s = (bool(cells[k00]), bool(cells[k10]), bool(cells[k01]), bool(cells[k11]))
                            if s == (True, False, False, True): cells[k10] = cells[k00]; changed = True; added += 1
                            elif s == (False, True, True, False): cells[k00] = cells[k10]; changed = True; added += 1
    return added


def count_pieces(cells):
    seen = [False] * len(cells); n = 0
    for k0 in range(len(cells)):
        if not cells[k0] or seen[k0]: continue
        n += 1; seen[k0] = True; st = [k0]
        while st:
            x, y, z = unK(st.pop())
            for dx, dy, dz in DIRS:
                nx, ny, nz = x + dx, y + dy, z + dz
                if inb(nx, ny, nz):
                    nk = K(nx, ny, nz)
                    if cells[nk] and not seen[nk]: seen[nk] = True; st.append(nk)
    return n


def write_stl(path, cells, scale):
    qs = quads(cells)
    with open(path, "wb") as f:
        f.write(b"voxel wardrobe studio".ljust(80, b" ")); f.write(struct.pack("<I", len(qs) * 2))
        for n, q, _ in qs:
            p = [(vx * scale, (D - vy) * scale, vz * scale) for vx, vy, vz in q]
            nn = (n[0], -n[1], n[2])
            for tri in ((p[0], p[1], p[2]), (p[0], p[2], p[3])):
                t = (tri[0], tri[2], tri[1])
                f.write(struct.pack("<3f", *nn))
                for v in t: f.write(struct.pack("<3f", *v))
                f.write(b"\x00\x00")
    return len(qs) * 2


def write_obj(path_base, wd, cells, tone):
    pal, col = baked_palette(wd, cells, tone)
    name = os.path.basename(path_base)
    verts, vmap, by_mat = [], {}, {}
    def vid(v):
        if v not in vmap: verts.append(v); vmap[v] = len(verts)
        return vmap[v]
    for n, q, k in quads(cells):
        by_mat.setdefault(col[k], []).append([vid(v) for v in q])
    with open(path_base + ".mtl", "w") as f:
        for i, c in enumerate(pal, 1):
            f.write(f"newmtl c{i}\nKd {c[0]/255:.4f} {c[1]/255:.4f} {c[2]/255:.4f}\nKa 0 0 0\nKs 0 0 0\nillum 1\n\n")
    with open(path_base + ".obj", "w") as f:
        f.write(f"mtllib {name}.mtl\no {name}\n")
        for x, y, z in verts: f.write(f"v {x - W/2:.1f} {z:.1f} {-(y - D/2):.1f}\n")
        for c, fl in by_mat.items():
            f.write(f"usemtl c{c}\n")
            for q in fl: f.write("f " + " ".join(map(str, q)) + "\n")


def safe(s): return re.sub(r"[^\w\-]+", "_", s).strip("_")[:40] or "x"


def export_set(wd, worn, label, bodies, out, mm, formats, with_body, per_item):
    os.makedirs(out, exist_ok=True)
    for sex in bodies:
        cells = wd.compose(sex, worn, body=with_body)
        tone = shade(cells)
        base = os.path.join(out, f"{safe(label)}_{sex}")
        if "vox" in formats:
            n = write_vox(base + ".vox", wd, cells, tone); print(f"  {base}.vox  ({n} voxels)")
        if "stl" in formats:
            pc = list(cells); added = fix_edge_contacts(pc); pieces = count_pieces(pc)
            write_stl(f"{base}_{mm:g}mm.stl", pc, mm)
            note = []
            if added: note.append(f"{added} corner voxels added")
            if pieces > 1: note.append(f"WARNING {pieces} separate pieces")
            print(f"  {base}_{mm:g}mm.stl  {'(' + ', '.join(note) + ')' if note else ''}")
        if "obj" in formats:
            write_obj(base, wd, cells, tone); print(f"  {base}.obj + .mtl")
        if per_item and "vox" in formats:
            for it, cw in worn:
                one = wd.compose(sex, worn, body=True, only=it); mask = wd.compose(sex, worn, body=False, only=it)
                p = os.path.join(out, "items", f"{safe(it['name'])}_{safe(it['colorways'][cw]['name'])}_{sex}.vox")
                os.makedirs(os.path.dirname(p), exist_ok=True); write_vox(p, wd, one, shade(one), mask); print(f"  {p}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    l = sub.add_parser("list", help="list items, colorways and outfits"); l.add_argument("file")
    e = sub.add_parser("export", help="export an outfit"); e.add_argument("file")
    e.add_argument("--outfit", help="name of a saved outfit")
    e.add_argument("--items", help='comma list of item names, each optionally "Name:colorway"')
    e.add_argument("--all-outfits", action="store_true", help="export every saved outfit")
    e.add_argument("--body", default="both", choices=["male", "female", "both"])
    e.add_argument("--out", default="exports"); e.add_argument("--mm", type=float, default=2.0, help="mm per voxel for STL")
    e.add_argument("--formats", default="vox,stl,obj"); e.add_argument("--no-body", action="store_true", help="clothes only, no body")
    e.add_argument("--per-item", action="store_true", help="also write one .vox per worn item")
    a = ap.parse_args()
    with open(a.file, encoding="utf-8") as f: wd = Wardrobe(json.load(f))
    if a.cmd == "list":
        print(f"{len(wd.items)} items:")
        for it in wd.items:
            n = sum(len(it["vox"].get(v, [])) // 2 for v in ("both", "male", "female"))
            cws = ", ".join(c["name"] for c in it["colorways"])
            print(f"  {it['name']:<18} {it['category']:<10} order {it.get('order', 45):<3} {n:>5} vox  roles: {', '.join(it['roles'])}  colorways: {cws}")
        print(f"{len(wd.outfits)} outfits:")
        for o in wd.outfits:
            names = []
            for w in o["worn"]:
                it = next((i for i in wd.items if i["id"] == w["id"]), None)
                if it: names.append(f"{it['name']}:{it['colorways'][min(w.get('colorway', 0), len(it['colorways'])-1)]['name']}")
            print(f"  {o['name']}: {', '.join(names)}")
        return
    bodies = ["male", "female"] if a.body == "both" else [a.body]
    formats = set(a.formats.split(","))
    sets = []
    if a.all_outfits:
        for o in wd.outfits: sets.append((o["name"], o))
    elif a.outfit:
        o = next((o for o in wd.outfits if o["name"].lower() == a.outfit.lower()), None)
        if not o: raise SystemExit(f'No outfit "{a.outfit}". Use "list" to see outfits.')
        sets.append((o["name"], o))
    elif a.items:
        worn = []
        for spec in a.items.split(","):
            name, _, cw = spec.strip().partition(":"); it = wd.item(name.strip()); worn.append((it, wd.colorway_index(it, cw.strip() or None)))
        sets.append(("custom", worn))
    else:
        raise SystemExit("Give --outfit NAME, --items LIST or --all-outfits.")
    for label, s in sets:
        worn = s if isinstance(s, list) else [(it, min(w.get("colorway", 0), len(it["colorways"]) - 1)) for w in s["worn"] for it in [next((i for i in wd.items if i["id"] == w["id"]), None)] if it]
        print(f"{label}:")
        export_set(wd, worn, label, bodies, a.out, a.mm, formats, not a.no_body, a.per_item)


if __name__ == "__main__":
    main()
