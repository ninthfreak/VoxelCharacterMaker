"""Pictures of a polygon mesh, drawn with parallel rays. Same camera and the same even light as the clay pictures
(clay.render), so the two can be compared.

mode "facet":   every polygon one flat shade (the polygons show)
mode "smooth":  shade blended across the polygons from corner to corner, the way 1990s 3D games lit their models
mode "lines":   flat shade with every polygon's edges drawn
"""
import numpy as np
from PIL import Image

BG = (28, 31, 40)


def _normal(poly):
    n = np.zeros(3)
    for i in range(len(poly)):
        n += np.cross(poly[i], poly[(i + 1) % len(poly)])
    ln = np.linalg.norm(n)
    return n / ln if ln > 1e-12 else np.array([0.0, 0.0, 1.0])


def prepare(parts):
    """parts: {name: [polygon arrays]} -> triangles with flat and smooth normals, and the polygon edges."""
    tris = []; flat = []; smooth = []; edges = []
    for polys in parts.values():
        key = lambda v: tuple(np.round(v, 4))
        acc = {}
        ns = [_normal(p) for p in polys]
        for p, n in zip(polys, ns):
            area = 0.0
            for i in range(1, len(p) - 1):
                area += 0.5 * np.linalg.norm(np.cross(p[i] - p[0], p[i + 1] - p[0]))
            for v in p:
                acc[key(v)] = acc.get(key(v), np.zeros(3)) + n * area
        for p, n in zip(polys, ns):
            vn = []
            for v in p:
                s = acc[key(v)]; ln = np.linalg.norm(s)
                vn.append(s / ln if ln > 1e-9 else n)
            vn = np.array(vn)
            k = len(p)
            if k == 4:                                             # split a four-sided polygon along its shorter diagonal
                order = [(0, 1, 2), (0, 2, 3)] if np.linalg.norm(p[0] - p[2]) <= np.linalg.norm(p[1] - p[3]) else [(0, 1, 3), (1, 2, 3)]
            else:
                order = [(0, i, i + 1) for i in range(1, k - 1)]
            for a, b, c in order:
                tris.append(p[[a, b, c]]); flat.append(n); smooth.append(vn[[a, b, c]])
            for i in range(k):
                edges.append((p[i], p[(i + 1) % k]))
    return dict(tris=np.array(tris), flat=np.array(flat), smooth=np.array(smooth), edges=edges)


def prepare_coloured(groups):
    """groups: {name: [(polygon array, (r, g, b))]} -> as prepare(), plus one colour per triangle."""
    prep = prepare({k: [p for p, _ in v] for k, v in groups.items()})
    cols = []
    for v in groups.values():
        for p, c in v:
            cols += [c] * (len(p) - 2)
    prep["colour"] = np.array(cols, float)
    return prep


def render(prep, yaw_deg=0.0, pitch_deg=0.0, scale=15.0, width=26.0, z_range=(-0.5, 43.0), colour=(206, 190, 172),
           mode="facet", ss=3, centre_x=12.0, line=(58, 50, 46)):
    px = scale * ss
    yaw, pitch = np.radians(yaw_deg), np.radians(pitch_deg)
    fwd = np.array([-np.sin(yaw) * np.cos(pitch), np.cos(yaw) * np.cos(pitch), -np.sin(pitch)])
    right = np.array([np.cos(yaw), np.sin(yaw), 0.0])
    up = np.cross(right, fwd); up /= np.linalg.norm(up)
    if up[2] < 0: up = -up
    W = int(width * px); H = int((z_range[1] - z_range[0]) * px)
    centre = np.array([centre_x, 12.0, (z_range[0] + z_range[1]) / 2.0])
    key = (-0.45 * right + 0.55 * up - 0.7 * fwd); key /= np.linalg.norm(key)
    fill = (0.6 * right + 0.1 * up - 0.75 * fwd); fill /= np.linalg.norm(fill)

    def lit(n):
        return 0.34 + 0.52 * np.clip(n @ key, 0, 1) + 0.16 * np.clip(n @ fill, 0, 1) + 0.06 * np.clip(n[..., 2], 0, 1)

    def screen(P):
        rel = P - centre
        return (rel @ right + width / 2.0) * px, ((z_range[1] - z_range[0]) / 2.0 - rel @ up) * px, rel @ fwd

    zbuf = np.full((H, W), np.inf); shade = np.zeros((H, W)); hit = np.zeros((H, W), bool); tid = np.zeros((H, W), np.int64)
    T = prep["tris"]
    sx, sy, sz = screen(T.reshape(-1, 3)); sx = sx.reshape(-1, 3); sy = sy.reshape(-1, 3); sz = sz.reshape(-1, 3)
    flat_i = lit(prep["flat"]); smooth_i = lit(prep["smooth"].reshape(-1, 3)).reshape(-1, 3)
    for t in range(T.shape[0]):
        x, y, z = sx[t], sy[t], sz[t]
        x0 = max(int(np.floor(x.min())), 0); x1 = min(int(np.ceil(x.max())) + 1, W)
        y0 = max(int(np.floor(y.min())), 0); y1 = min(int(np.ceil(y.max())) + 1, H)
        if x0 >= x1 or y0 >= y1: continue
        area = (x[1] - x[0]) * (y[2] - y[0]) - (x[2] - x[0]) * (y[1] - y[0])
        if abs(area) < 1e-9: continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        w0 = ((x[1] - gx) * (y[2] - gy) - (x[2] - gx) * (y[1] - gy)) / area
        w1 = ((x[2] - gx) * (y[0] - gy) - (x[0] - gx) * (y[2] - gy)) / area
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any(): continue
        depth = w0 * z[0] + w1 * z[1] + w2 * z[2]
        zb = zbuf[y0:y1, x0:x1]
        win = inside & (depth < zb)
        if not win.any(): continue
        zb[win] = depth[win]
        val = (w0 * smooth_i[t, 0] + w1 * smooth_i[t, 1] + w2 * smooth_i[t, 2]) if mode == "smooth" else np.full(depth.shape, flat_i[t])
        shade[y0:y1, x0:x1][win] = val[win]; hit[y0:y1, x0:x1][win] = True; tid[y0:y1, x0:x1][win] = t

    img = np.zeros((H, W, 3)); img[:] = BG
    base = prep["colour"][tid[hit]] if "colour" in prep else np.array(colour, float)[None, :]
    img[hit] = np.clip(shade[hit][:, None] * base, 0, 255)
    if mode == "lines":
        lw = max(1, int(round(ss * 0.6)))
        for a, b in prep["edges"]:
            ax, ay, az = screen(a[None, :]); bx, by, bz = screen(b[None, :])
            n = int(np.ceil(np.hypot(bx[0] - ax[0], by[0] - ay[0]))) + 2
            s = np.linspace(0.0, 1.0, n)
            xs = ax[0] + (bx[0] - ax[0]) * s; ys = ay[0] + (by[0] - ay[0]) * s; zs = az[0] + (bz[0] - az[0]) * s
            ix = np.round(xs).astype(int); iy = np.round(ys).astype(int)
            ok = (ix >= 0) & (ix < W - lw) & (iy >= 0) & (iy < H - lw)
            ix, iy, zs = ix[ok], iy[ok], zs[ok]
            vis = zs <= zbuf[iy, ix] + 0.12
            for dx in range(lw):
                for dy in range(lw):
                    img[iy[vis] + dy, ix[vis] + dx] = line
    im = Image.fromarray(img.astype(np.uint8))
    if ss > 1:
        im = im.resize((W // ss, H // ss), Image.BOX)
    return np.array(im)
