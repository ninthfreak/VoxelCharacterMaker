"""Garments from the project's wardrobe file onto a region-tagged low-poly body.

It reads the project's own wardrobe JSON (palette, items with coverage = {region key: {role, bulk}}, mirror flag, draw
order, colourways, special shapes, outfits) and applies the parametric rules of SPEC 7.3 to polygons instead of voxels:

  1  bulk 0 recolours the body's own polygons; bulk N lifts them N units off the body
  2  growth is sideways, so a covered band next to a bare one makes a level hem step
  3  surfaces that face up or down also grow up or down; nothing goes below the floor
  4  arms, feet and head are separate pieces, so their bulk may overlap the torso's
  6  where worn items claim the same region, the larger bulk wins, then the higher draw order
  8  nothing on a leg or foot grows toward the other leg
Special shapes (specials.py): straps, skirt and cape are built; a skirt or a cape is hanging cloth (hang.py) and is
placed after everything else that is worn. A skin tone, a face (faces.py), hair, a beard and a moustache
(facial_hair.py) make the figure a character. Not done here: rule 7 (soft or hard edge style), and the other special
shapes (hood, drawn shapes).

The project keeps garment logic in exactly one place, and that place is core/ (GDScript), which today only knows
voxels. When the Godot side builds polygons these rules move there, and this file goes or shrinks to a cross-check.
"""
import json
import numpy as np
import body as lb
import specials, facial_hair

SKIN = (236, 178, 134)        # the project's default skin tone ("light", mid shade)
BULK_UNIT = 1.0               # how far one step of bulk stands off the body, in voxels
# Features the low-poly figures have and the game's wardrobe does not yet: id -> (slot, special shape, its style).
# A moustache is a slot of its own, so that any beard goes with any moustache.
NEW_FEATURES = {"goatee": ("facial_hair", "facial_hair", "goatee"), "moustache": ("moustache", "moustache", "moustache"),
                "handlebar": ("moustache", "moustache", "handlebar"), "horseshoe": ("moustache", "moustache", "horseshoe"),
                "pencil": ("moustache", "moustache", "pencil")}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Wardrobe:
    def __init__(self, path):
        d = json.load(open(path))
        assert d["format"] == "voxel_wardrobe"
        self.palette = {k: hex_rgb(v) for k, v in d["palette"].items()}
        self.items = d["items"]; self.outfits = d["outfits"]
        self.eye_sets = d.get("eye_sets", {})
        self.features = {}                    # hair, facial hair, face accessories: feature id -> (slot, item)
        for slot, items in d.get("features", {}).items():
            for item_id, item in items.items(): self.features[item_id] = (slot, item)
        for item_id, (slot, kind, style) in NEW_FEATURES.items():
            self.features.setdefault(item_id, (slot, dict(
                category=slot, name=item_id.capitalize(), colourways={"default": {"hair": "@hair"}}, coverage={}, draw_order=65,
                edge_style="soft", mirror=True, roles=["hair"], specials=[dict(type=kind, params=dict(style=style))])))

    def outfit(self, name):
        return [(e["item"], e["colourway"]) for e in self.outfits[name]]


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


class Fit:
    """The figure as dressed, for a special shape to measure."""

    def __init__(self, body, polys, surface):
        self.body = body; self._polys = polys; self._surface = surface

    def heights(self, bands):
        """The heights of the body's rings in those bands, bottom to top."""
        return sorted({round(float(v[2]), 4) for r in self.body["polys"] if r["piece"] == "skin" and not r["hidden"] and r["band"] in bands for v in r["pts"]})

    def ring(self, z):
        """The body's own corners at a ring height, in order: the front centre, then round by the figure's left."""
        seen = {}
        for r in self.body["polys"]:
            if r["piece"] != "skin" or r["hidden"]: continue
            for v in r["pts"]:
                if abs(v[2] - z) < 1e-6: seen[tuple(np.round(v, 4))] = v
        pts = list(seen.values())
        c = np.mean(pts, axis=0)
        order = list(np.argsort([np.arctan2(p[0] - c[0], -(p[1] - c[1])) % (2 * np.pi) for p in pts]))
        front = min((i for i in order if abs(pts[i][0] - lb.CX) < 1e-6), key=lambda i: pts[i][1], default=order[0])
        at = order.index(front)
        return [pts[i] for i in order[at:] + order[:at]]

    def at(self, v, piece="skin"):
        """Where one of the body's corners is once the figure is dressed."""
        return self._surface(piece, v)

    def shares(self, v, piece="skin"):
        return self.body["shares"][lb.share_key(piece, v)]

    def points(self, over):
        """Every corner of the dressed figure that a hanging cloth hangs over, and its height (standing)."""
        sel = [q["pts"] for q in self._polys if over(q)]
        P = np.concatenate(sel) if sel else np.zeros((0, 3))
        return P, P[:, 2].copy()

    def triangles(self, over):
        """The dressed surface of the polygons that `over` picks, as triangles."""
        tris = []
        for q in self._polys:
            if not over(q): continue
            p = q["pts"]
            tris += [p[[0, i, i + 1]] for i in range(1, len(p) - 1)]
        return np.array(tris) if tris else np.zeros((0, 3, 3))

    def rest(self):
        return {part: (np.eye(3), np.zeros(3)) for part in lb.PARENT}


class Look:
    """A dressed figure: what dress() returns.
    polys   the body and everything that bends with it: dicts with pts, rgb, shares (for every corner, the parts it
            follows), part, piece, band, hidden
    cloths  hanging cloth (hang.Cloth), laid afresh for every pose
    notes   what was asked for and could not be built"""

    def __init__(self, body, polys, cloths, notes):
        self.body = body; self.polys = polys; self.cloths = cloths; self.notes = notes

    def standing(self):
        import pose
        return pose.posed(self.body, self, {})

    def groups(self, pose_=None):
        """The figure in a pose (standing if none), ready for picture.prepare_coloured."""
        import pose
        return pose.posed_groups(self.body, self, pose_ or {})


def dress(body, wardrobe, worn, skin=SKIN, paint=None, features=(), eyes=None, brow=None, mouth=None):
    """A figure, dressed. Returns a Look.
    worn      [(item id, colourway)] from the wardrobe's items
    features  [(feature id, colourway)] from its features: hair, a beard, a moustache
    skin      a colour, or the name of one of the game's skin tones (lids, stubble and the mouth need the name)
    eyes      None for a blank face, or what faces.eyes takes: eye_set, colourway, lids, size ({} for the standard
              eye, neutral)
    brow      a brow colour, instead of the one the hair gives
    mouth     None for no mouth, or the name of one of faces.MOUTHS
    paint     optional {region key: rgb} to colour bare regions (for the region map)"""
    notes = []
    tables = []

    def game_tables():                                               # only fetched when a face or a skin tone needs them
        if not tables:
            import game
            tables.append(game.tables())
        return tables[0]

    tone = None
    if isinstance(skin, str):
        tone = skin; skin = tuple(game_tables()["skin"][tone]["mid"])
    hair = None                                                      # the palette name of the hair colour, if hair is worn
    for feature_id, cw in features:
        slot, it = wardrobe.features[feature_id]
        name = it["colourways"][cw].get("hair", "")
        if slot == "hair" and name and not name.startswith("@"): hair = name

    def colour_of(name):
        """A palette colour, or one of the game's two references: "@hair" follows the hair (dark brown when bald),
        "@stubble" is worked out from the skin tone and the hair."""
        if name == "@hair": return wardrobe.palette[hair or game_tables()["default_brow_hair"]]
        if name == "@stubble":
            t = game_tables()
            return tuple(t["hair"][hair or t["default_brow_hair"]]["stubble"][tone or t["default_skin"]])
        return wardrobe.palette[name]

    polys = list(body["polys"])
    layers = []; shapes = []; whiskers = []
    known = set(lb.all_region_keys())
    wearing = [(wardrobe.items[i], i, cw) for i, cw in worn] + [(wardrobe.features[i][1], i, cw) for i, cw in features]
    for it, item_id, cw in wearing:
        colours = {role: colour_of(name) for role, name in it["colourways"][cw].items() if name.startswith("@") or name in wardrobe.palette}
        cov = resolve(it)
        for sp in it.get("specials", []):
            kind = sp["type"]
            if kind in ("facial_hair", "moustache"):                 # on the head and the face themselves: see below
                style = str(specials.settings(kind, sp.get("params", {}))["style"]) if kind in specials.DEFAULTS else str(sp["params"]["style"])
                whiskers.append((kind, style, colours, int(it["draw_order"]), item_id)); continue
            if kind not in specials.BUILT:
                notes.append(f"{item_id}: special shape '{kind}' not built"); continue
            cov = {**specials.coverage(kind, sp.get("params", {})), **cov}       # the item's own regions come first
            shapes.append((kind in specials.HANGS, int(it["draw_order"]), len(shapes), item_id, kind, sp.get("params", {}), colours))
        layers.append(dict(cov=cov, order=int(it["draw_order"]), colours=colours))
        if it.get("edge_style", "soft") != "soft":
            notes.append(f"{item_id}: edge style '{it['edge_style']}' ignored")
        unknown = [k for k in it["coverage"] if k not in known]
        if unknown: notes.append(f"{item_id}: regions not on this body: {unknown}")
    head = body.get("info", {}).get("head")
    for kind, style, colours, order, item_id in whiskers:           # a beard claims the head's own polygons, before anything is lifted
        if kind != "facial_hair": continue
        if head is None:
            notes.append(f"{item_id}: no head to grow it on"); continue
        polys, more = facial_hair.on_head(polys, style, colours, order, head, hair is not None)
        notes += [f"{item_id}: {m}" for m in more]
    win = []
    for r in polys:
        best = None
        if not r["hidden"] and r.get("at", ("",))[0] != "ear":       # ears stay skin: nothing made of regions covers them
            for L in layers:
                if r["key"] in L["cov"]:
                    role, bulk = L["cov"][r["key"]]
                    if best is None or (bulk, L["order"]) > (best[0], best[1]):
                        best = (bulk, L["order"], L["colours"][role], None)
            for claim in r.get("claims", ()):                        # (bulk, draw order, colour) and, for some, a fade
                if best is None or (claim[0], claim[1]) > (best[0], best[1]): best = tuple(claim) + (None,) * (4 - len(claim))
        win.append(best)

    # per piece: weld corners, corner normals from the visible polygons, who is across each edge, and the most
    # bulk worn at each corner
    key = lambda piece, v: (piece, tuple(np.round(v, 4)))
    acc = {}; across = {}; most = {}
    for i, r in enumerate(polys):
        p = r["pts"]
        if not r["hidden"]:
            n = _normal(p)
            for v in p:
                k = key(r["piece"], v)
                acc[k] = acc.get(k, np.zeros(3)) + n
                b = win[i][0] if win[i] is not None else 0
                if k not in most or b > most[k][0]: most[k] = (b, i)
        for a in range(len(p)):
            e = frozenset((key(r["piece"], p[a]), key(r["piece"], p[(a + 1) % len(p)])))
            across.setdefault(e, []).append(i)

    def moved(r, v, bulk, fade=None):
        """Where a corner goes when its polygon is lifted. fade (z0, z1): nothing at z0, all of it from z1 on."""
        if fade is not None: bulk = bulk * float(np.clip((fade[0] - v[2]) / (fade[0] - fade[1]), 0.0, 1.0))
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

    def lifted(i, v):
        return moved(polys[i], v, win[i][0], win[i][3]) if win[i] is not None else v

    def surface(piece, v):
        _, i = most.get(key(piece, v), (0, None))
        return np.array(v, float) if i is None else lifted(i, v)

    out = []

    def shares_of(r, src):
        if r["piece"] == "head": return [{"head": 1.0}] * len(src)   # every corner of a head follows the head alone
        return [body["shares"][lb.share_key(r["piece"], s)] for s in src]

    def put(r, pts, rgb, src):
        out.append(dict(pts=np.asarray(pts, float), rgb=rgb, src=src, shares=shares_of(r, src), part=r["part"], piece=r["piece"],
                        band=r["band"], hidden=r["hidden"]))

    for i, r in enumerate(polys):
        w = win[i]
        if w is None:
            put(r, r["pts"], paint.get(r["key"], skin) if (paint and not r["hidden"]) else skin, r["pts"]); continue
        bulk, _, rgb, _ = w
        if bulk == 0:
            put(r, r["pts"], rgb, r["pts"]); continue
        p = r["pts"]
        put(r, np.array([lifted(i, v) for v in p]), rgb, p)
        for a in range(len(p)):                                                           # hems: a step down to a lower neighbour
            va, vb = p[a], p[(a + 1) % len(p)]
            others = [j for j in across[frozenset((key(r["piece"], va), key(r["piece"], vb)))] if j != i]
            if not others: continue
            q = polys[others[0]]
            if q["hidden"]: continue
            m = win[others[0]][0] if win[others[0]] is not None else 0
            if m >= bulk: continue
            hem = [lifted(i, va), lifted(i, vb), lifted(others[0], vb), lifted(others[0], va)]
            if max(np.linalg.norm(hem[0] - hem[3]), np.linalg.norm(hem[1] - hem[2])) > 1e-6:
                put(r, np.array(hem), rgb, np.array([va, vb, vb, va]))

    # special shapes: those that lie on the figure first, then hanging cloth in draw order, each hanging over
    # everything before it
    fit = Fit(body, out, surface)
    cloths = []
    import hang
    for hangs, _, _, item_id, kind, params, colours in sorted(shapes, key=lambda s: s[:3]):
        if not hangs:
            made, more = specials.BUILT[kind](fit, params, colours, name=item_id)
            for q in made:
                out.append(dict(pts=q["pts"], rgb=q["rgb"], src=None, shares=q["shares"], part="chest", piece="shape:" + kind,
                                band=None, hidden=False))
        else:
            cloth, more = specials.BUILT[kind](fit, params, colours, name=item_id)
            if cloth is not None:
                cloths.append(cloth)
                P, Z0 = fit.points(cloth.over)                        # laid standing, so the next cloth hangs over it
                for pts, _ in hang.lay(cloth, fit.rest(), P, Z0):
                    fit._polys = fit._polys + [dict(pts=pts, piece="cloth:" + cloth.name, band=None, hidden=False)]
        notes += more
    moustache = [(p, colours["hair"]) for kind, style, colours, _, _ in whiskers if kind == "moustache" for p in facial_hair.moustache(style)]
    if eyes is not None or mouth is not None or moustache:           # the face: under hair and hats, which stand in front of it
        import faces
        face = faces.eyes(game_tables(), wardrobe, skin=tone, hair=hair, brow=brow, **eyes) if eyes is not None else []
        face += faces.lower_face(game_tables() if mouth is not None else None, mouth, skin=tone, moustache=moustache)
        for q in face:
            out.append(dict(pts=q["pts"], rgb=q["rgb"], src=None, shares=[{"head": 1.0}] * len(q["pts"]), part="head", piece="face",
                            band=None, hidden=False, unlit=q["unlit"], role=q["role"]))
    return Look(body, out, cloths, notes)
