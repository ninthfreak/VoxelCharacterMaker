"""A prototype: put garments from the project's wardrobe file onto a region-tagged low-poly body.

It reads the project's own wardrobe JSON (palette, items with coverage = {region key: {role, bulk}}, mirror flag, draw
order, colourways, outfits) and applies the parametric rules of SPEC 7.3 to polygons instead of voxels:

  1  bulk 0 recolours the body's own polygons; bulk N lifts them N units off the body
  2  growth is sideways, so a covered band next to a bare one makes a level hem step
  3  surfaces that face up or down also grow up or down; nothing goes below the floor
  4  arms, feet and head are separate pieces, so their bulk may overlap the torso's
  6  where worn items claim the same region, the larger bulk wins, then the higher draw order
  8  nothing on a leg or foot grows toward the other leg
Not done here: rule 7 (soft or hard edge style) and every special shape (skirt, cape, hood, straps...).

This is a second copy of rules whose home is core/ (the project keeps garment logic in exactly one place). It exists
to prove the regions and parameters carry over to polygons; once the Godot side builds polygons, the rules belong
there and this file should go, or shrink to a cross-check.
"""
import json
import numpy as np
import body as lb

SKIN = (236, 178, 134)        # the project's default skin tone ("light", mid shade)
BULK_UNIT = 1.0               # how far one step of bulk stands off the body, in voxels


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Wardrobe:
    def __init__(self, path):
        d = json.load(open(path))
        assert d["format"] == "voxel_wardrobe"
        self.palette = {k: hex_rgb(v) for k, v in d["palette"].items()}
        self.items = d["items"]; self.outfits = d["outfits"]


def resolve(item):
    """Region key -> (role, bulk) for both sides. With mirror on, the right side follows the left."""
    cov = {}
    for key, e in item["coverage"].items():
        parts = key.split(".")
        if item["mirror"]:
            if parts[1] != "L": continue
            cov[key] = (e["role"], int(e["bulk"]))
            parts[1] = "R"; cov[".".join(parts)] = (e["role"], int(e["bulk"]))
        else:
            cov[key] = (e["role"], int(e["bulk"]))
    return cov


def _normal(p):
    n = np.zeros(3)
    for i in range(len(p)):
        n += np.cross(p[i], p[(i + 1) % len(p)])
    return n


def dress(body, wardrobe, worn, skin=SKIN, paint=None):
    """worn: [(item id, colourway)]. paint: optional {region key: rgb} to colour bare regions (for the region map).
    Returns ({group: [(polygon, rgb)]}, [notes])."""
    polys = body["polys"]; notes = []
    layers = []
    for item_id, cw in worn:
        it = wardrobe.items[item_id]
        layers.append(dict(cov=resolve(it), order=int(it["draw_order"]),
                           colours={role: wardrobe.palette[name] for role, name in it["colourways"][cw].items()}))
        for sp in it.get("specials", []):
            notes.append(f"{item_id}: special shape '{sp['type']}' not built")
        if it.get("edge_style", "soft") != "soft":
            notes.append(f"{item_id}: edge style '{it['edge_style']}' ignored")
        unknown = [k for k in it["coverage"] if k not in set(lb.all_region_keys())]
        if unknown: notes.append(f"{item_id}: regions not on this body: {unknown}")
    win = []
    for r in polys:
        best = None
        if not r["hidden"]:
            for L in layers:
                if r["key"] in L["cov"]:
                    role, bulk = L["cov"][r["key"]]
                    if best is None or (bulk, L["order"]) > (best[0], best[1]):
                        best = (bulk, L["order"], L["colours"][role])
        win.append(best)

    # per piece: weld corners, corner normals from the visible polygons, and who is across each edge
    key = lambda piece, v: (piece, tuple(np.round(v, 4)))
    acc = {}; across = {}
    for i, r in enumerate(polys):
        p = r["pts"]
        if not r["hidden"]:
            n = _normal(p)
            for v in p:
                acc[key(r["piece"], v)] = acc.get(key(r["piece"], v), np.zeros(3)) + n
        for a in range(len(p)):
            e = frozenset((key(r["piece"], p[a]), key(r["piece"], p[(a + 1) % len(p)])))
            across.setdefault(e, []).append(i)

    def moved(r, v, bulk):
        if bulk == 0: return v
        n = acc.get(key(r["piece"], v), np.zeros(3)); ln = np.linalg.norm(n)
        if ln < 1e-9: return v
        n = n / ln; step = bulk * BULK_UNIT
        flat = np.array([n[0], n[1], 0.0]); fl = np.linalg.norm(flat)
        d = flat / fl * step if (abs(n[2]) < 0.7 and fl > 1e-9) else n * step            # rule 2, rule 3
        if v[2] + d[2] < 0 and fl > 1e-9:                                                 # rule 3: not below the floor
            d = flat / fl * step; d[2] = -v[2]
        if lb.BANDS[r["band"]][2] in ("thigh", "shin"):                                   # rule 8: the gap between the legs
            d[0] = max(d[0], 0.0) if r["side"] == "L" else min(d[0], 0.0)
        return v + d

    groups = {}
    for i, r in enumerate(polys):
        g = groups.setdefault(r["piece"], [])
        w = win[i]
        if w is None:
            g.append((r["pts"], paint.get(r["key"], skin) if (paint and not r["hidden"]) else skin)); continue
        bulk, _, rgb = w
        if bulk == 0:
            g.append((r["pts"], rgb)); continue
        p = r["pts"]
        g.append((np.array([moved(r, v, bulk) for v in p]), rgb))
        for a in range(len(p)):                                                           # hems: a step down to a lower neighbour
            va, vb = p[a], p[(a + 1) % len(p)]
            others = [j for j in across[frozenset((key(r["piece"], va), key(r["piece"], vb)))] if j != i]
            if not others: continue
            q = polys[others[0]]
            if q["hidden"]: continue
            m = win[others[0]][0] if win[others[0]] is not None else 0
            if m >= bulk: continue
            hem = [moved(r, va, bulk), moved(r, vb, bulk), moved(q, vb, m), moved(q, va, m)]
            if max(np.linalg.norm(hem[0] - hem[3]), np.linalg.norm(hem[1] - hem[2])) > 1e-6:
                g.append((np.array(hem), rgb))
    return groups, notes
