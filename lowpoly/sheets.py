"""Review sheets for the low-poly bodies.

  python3 lowpoly/sheets.py look      the first cut: the feminine average at two polygon budgets, beside its clay
  python3 lowpoly/sheets.py male      the masculine average (budget A), beside its clay and the feminine one
  python3 lowpoly/sheets.py regions   the bodies the clothing system uses: their regions, then starter outfits
  python3 lowpoly/sheets.py joints    the comparison behind the joints decision: rigid pieces, or one bending skin
  python3 lowpoly/sheets.py heads     the five heads, beside the voxel heads they follow
  python3 lowpoly/sheets.py shapes    the special shapes built so far (skirt, cape, straps), standing, with their settings
  python3 lowpoly/sheets.py moving    the same clothes in the game's test poses
  python3 lowpoly/sheets.py all

Sheets are written to lowpoly/renders/. The clay is drawn by ray marching (about 40 s a view), so those pictures are
kept in lowpoly/_work/ and reused. Anything dressed needs the game's starter wardrobe and test poses (game.py); if
they are not in lowpoly/_work/ they are written first with dump_wardrobe.gd, which needs Godot
(GODOT=/path/to/godot, or `godot` on PATH).
"""
import copy, os, sys, time
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import json
import clay, rings as ring_tools, body as lb, dress as ld, picture as mr, pose as ps, heads as hd, game

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WORK = os.path.join(HERE, "_work")
RENDERS = os.path.join(HERE, "renders")
BG = mr.BG
PAD = 16

FULL = [("front", 0, 12), ("turned", 35, 15), ("side", 90, 12), ("turned, from behind", 145, 15), ("back", 180, 12)]
THREE = [("front", 0, 12), ("turned", 35, 15), ("turned, from behind", 145, 15)]
TWO = [("turned", 35, 15), ("turned, from behind", 145, 15)]


# ------------------------------------------------------------------------------------------------- layout ---

def font(sz, bold=False):
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else ""), sz)
    except Exception: return ImageFont.load_default()


def band(tl, labels, gap_after=()):
    """One row of pictures, each with its label above it."""
    hgt = max(t.shape[0] for t in tl); w = sum(t.shape[1] for t in tl) + PAD * (len(tl) + 1) + 24 * len(gap_after)
    im = Image.new("RGB", (w, hgt + 30), BG); d = ImageDraw.Draw(im); x = PAD
    for i, (t, l) in enumerate(zip(tl, labels)):
        im.paste(Image.fromarray(t), (x, 30)); d.text((x + 6, 4), l, font=font(16, True), fill=(255, 214, 102)); x += t.shape[1] + PAD
        if i in gap_after: x += 24
    return im


def head(title, sub, w):
    im = Image.new("RGB", (w, 78), BG); d = ImageDraw.Draw(im)
    d.text((PAD, 10), title, font=font(28, True), fill=(240, 240, 240)); d.text((PAD, 46), sub, font=font(16), fill=(180, 186, 200))
    return im


def save_sheet(rows, name):
    W = max(r.width for _, _, r in rows)
    ims = []
    for title, sub, r in rows:
        ims.append(head(title, sub, W)); ims.append(r)
    sheet = Image.new("RGB", (W, sum(i.height for i in ims) + PAD), BG); y = 0
    for i in ims:
        sheet.paste(i, (0, y)); y += i.height
    os.makedirs(RENDERS, exist_ok=True)
    out = os.path.join(RENDERS, name); sheet.save(out); print(out, sheet.size)


# -------------------------------------------------------------------------------------------- ingredients ---

def clay_tiles(sex, kind):
    """Pictures of a clay body: 'full' (the five standard views) or 'close' (torso: front, turned, from behind)."""
    os.makedirs(WORK, exist_ok=True)
    model = clay.BODIES[(sex, "average")]
    sdf = lambda p: clay.body(p, model)
    views = [(y, p) for _, y, p in FULL] if kind == "full" else [(0, 12), (35, 15), (145, 15)]
    out = []
    for i, (y, p) in enumerate(views):
        path = os.path.join(WORK, f"clay_{sex}_{kind}{i}.png")
        if not os.path.exists(path):
            t0 = time.time()
            big = clay.render(sdf, y, p, scale=30, width=26.0) if kind == "full" else clay.render(sdf, y, p, scale=52, width=17.0, z_range=(8.0, 26.5))
            im = Image.fromarray(big); im.resize((im.width // 2, im.height // 2), Image.BOX).save(path)
            print(f"  drew the {sex} clay, {kind} view {i} ({time.time() - t0:.0f} s)", flush=True)
        out.append(np.array(Image.open(path).convert("RGB")))
    return out


def first_cut(sex, spec):
    """One of the first cuts (rings.py LIGHT / FULL), checked before it is drawn."""
    ring_tools.use(clay.BODIES[(sex, "average")])
    parts, _ = ring_tools.build(spec)
    sdfs = dict(skin=ring_tools.sdf_skin, arms=ring_tools.sdf_arm, feet=ring_tools.sdf_foot, head=ring_tools.sdf_head)
    for name, polys in parts.items():
        bow = deep = far = 0; edges = {}
        for p in polys:
            if len(p) == 4:
                n1 = np.cross(p[1] - p[0], p[2] - p[0]); n2 = np.cross(p[2] - p[0], p[3] - p[0])
                m1 = np.cross(p[1] - p[0], p[3] - p[0]); m2 = np.cross(p[2] - p[1], p[3] - p[1])
                bow += bool(n1 @ n2 < 0 or m1 @ m2 < 0)
            d = sdfs[name](p.mean(axis=0)[None, :])[0]
            deep += bool(d < -0.8); far += bool(d > 0.3)
            for i in range(len(p)):
                a = tuple(np.round(p[i], 4)); b = tuple(np.round(p[(i + 1) % len(p)], 4))
                k = (a, b) if a < b else (b, a); edges[k] = edges.get(k, 0) + 1
        odd = sum(1 for v in edges.values() if v != 2)
        hidden_ends = 3 if name == "skin" else 0                    # the neck top and the two ankle caps
        assert bow == 0 and far == 0 and odd == 0 and deep <= hidden_ends, f"{sex} {spec['name']} {name}: twisted {bow}, buried {deep}, off the clay {far}, bad edges {odd}"
    return parts


BLUE = (92, 138, 200); ORANGE = (220, 152, 66); PALE = (238, 234, 222)
REGION_COLOURS = [("crown", BLUE), ("mid_head", ORANGE), ("lower_head", BLUE), ("neck", PALE),
                  ("collar", PALE), ("upper_chest", ORANGE), ("lower_chest", BLUE), ("belly", ORANGE), ("waist", PALE), ("hips", BLUE),
                  ("upper_thigh", ORANGE), ("lower_thigh", BLUE), ("knee", PALE), ("shin", ORANGE), ("ankle", PALE), ("foot", BLUE),
                  ("shoulder", BLUE), ("upper_arm", ORANGE), ("elbow", PALE), ("forearm", BLUE), ("wrist", PALE), ("hand", ORANGE)]


def region_paint():
    """Region key -> colour: bands alternate blue and orange (safe for red/green colour blindness), trim bands are
    pale, back regions are darker."""
    paint = {}
    for name, rgb in REGION_COLOURS:
        fam = lb.BANDS[name][2]
        for side in "LR":
            if fam in lb.CENTRED:
                paint[f"{name}.{side}.F"] = rgb
                paint[f"{name}.{side}.B"] = tuple(int(c * 0.66) for c in rgb)
            else:
                paint[f"{name}.{side}"] = rgb
    return paint


def wardrobe_path():
    return game.wardrobe_path()


def figure(b, w, worn, pose=None):
    """A dressed figure in a pose, ready to draw, with the stand-in eyes on its head. Returns (prepared, the look)."""
    look = ld.dress(b, w, worn)
    pose = pose or {}
    A, t = ps.transforms(pose, b["pivots"])["head"]
    eyes = [(p @ A.T + t, w.palette[c]) for p, c in hd.eye_preview()]
    return mr.prepare_coloured({"all": ps.posed(b, look, pose), "unlit:eyes": eyes}), look


def with_settings(w, item_id, **settings):
    """A copy of a wardrobe item with some of its special shape's settings changed. Returns the copy's id."""
    item = copy.deepcopy(w.items[item_id])
    item["specials"][0]["params"].update(settings)
    new = item_id + " " + " ".join(f"{k}={v}" for k, v in sorted(settings.items()))
    w.items[new] = item
    return new


# ------------------------------------------------------------------------------------------------- sheets ---

def sheet_look():
    built = {}
    for tag, spec in (("A", ring_tools.LIGHT), ("B", ring_tools.FULL)):
        parts = first_cut("female", spec)
        built[tag] = (mr.prepare(parts), ring_tools.counts(parts)["all"])
        print(f"female {tag}: {built[tag][1][0]} polygons, {built[tag][1][1]} triangles")
    rows = [("1. The clay model (the starting point)", "the smooth body this is cut from; nothing here is polygons yet",
             band(clay_tiles("female", "full"), [v[0] for v in FULL]))]
    for num, tag, sub in (("2", "A", "every polygon is one flat shade, so the polygons show. One plain colour, no face. The head is a stand-in block."),
                          ("3", "B", "the same method with more rings and more points on each ring")):
        rows.append((f"{num}. Low-poly {tag}: {built[tag][1][0]} polygons", sub,
                     band([mr.render(built[tag][0], y, p, scale=15.0) for _, y, p in FULL], [v[0] for v in FULL])))
    for num, mode, title, sub in (("4", "lines", "The polygons themselves", "edges drawn in. A on the left, B on the right."),
                                 ("5", "smooth", "Smooth shading", "the same polygons with the light blended across them, the usual way games of that era lit their models")):
        tl = []; lab = []
        for tag in ("A", "B"):
            tl += [mr.render(built[tag][0], y, p, scale=13.0, mode=mode) for _, y, p in THREE]; lab += [f"{tag}: {v[0]}" for v in THREE]
        rows.append((f"{num}. {title}", sub, band(tl, lab, gap_after=(2,))))
    close = clay_tiles("female", "close")
    tl = [np.array(Image.fromarray(close[i]).resize((340, 370), Image.LANCZOS)) for i in (1, 2)]; lab = [f"clay: {v[0]}" for v in TWO]
    for tag in ("A", "B"):
        tl += [mr.render(built[tag][0], y, p, scale=20.0, width=17.0, z_range=(8.0, 26.5)) for _, y, p in TWO]; lab += [f"{tag}: {v[0]}" for v in TWO]
    rows.append(("6. Torso, close up", "the clay, then A, then B", band(tl, lab, gap_after=(1, 3))))
    save_sheet(rows, "look_female_A_B.png")


def sheet_male():
    fem = first_cut("female", ring_tools.LIGHT); masc = first_cut("male", ring_tools.LIGHT_MASC)
    n = ring_tools.counts(masc)["all"]; print(f"male A: {n[0]} polygons, {n[1]} triangles")
    pm, pf = mr.prepare(masc), mr.prepare(fem)
    rows = [("1. The male clay model (first pass)", "same height, head and joint heights as the female clay",
             band(clay_tiles("male", "full"), [v[0] for v in FULL])),
            (f"2. Male low-poly A: {n[0]} polygons", "cut from that clay the same way as the female A. Every polygon is one flat shade. The head is a stand-in block.",
             band([mr.render(pm, y, p, scale=15.0) for _, y, p in FULL], [v[0] for v in FULL]))]
    tl = [mr.render(pm, y, p, scale=13.0, mode="lines") for _, y, p in THREE] + [mr.render(pm, y, p, scale=13.0, mode="smooth") for _, y, p in THREE]
    rows.append(("3. The polygons, and smooth shading", "edges drawn in on the left; the same polygons with the light blended across them on the right",
                 band(tl, [f"edges: {v[0]}" for v in THREE] + [f"smooth: {v[0]}" for v in THREE], gap_after=(2,))))
    tl = []; lab = []
    for name, y, p in (("front", 0, 12), ("turned", 35, 15), ("side", 90, 12)):
        tl += [mr.render(pf, y, p, scale=13.0), mr.render(pm, y, p, scale=13.0)]; lab += [f"female A: {name}", f"male A: {name}"]
    rows.append(("4. Female A and male A, side by side", "same polygon count and the same layout of polygons; only the positions differ", band(tl, lab, gap_after=(1, 3))))
    save_sheet(rows, "look_male_A.png")


def labelled(tile, scale, z_range, margin=150):
    """A front view with every band named at its own height: head, torso and legs on the left, arms on the right."""
    colour = dict(REGION_COLOURS)
    h, w = tile.shape[:2]
    im = Image.new("RGB", (w + 2 * margin, h), BG); im.paste(Image.fromarray(tile), (margin, 0)); d = ImageDraw.Draw(im)
    f = font(13, True)
    left = ["crown", "mid_head", "lower_head", "neck", "collar", "upper_chest", "lower_chest", "belly", "waist", "hips",
            "upper_thigh", "lower_thigh", "knee", "shin", "ankle", "foot"]
    right = ["shoulder", "upper_arm", "elbow", "forearm", "wrist", "hand"]
    for names, x_text, align, title in ((left, margin - 8, "right", "head, torso, legs"), (right, margin + w + 8, "left", "arms")):
        ys = [(z_range[1] - 0.5 * (lb.BANDS[n][0] + lb.BANDS[n][1])) * scale for n in names]
        for _ in range(60):                                   # keep the names from overlapping
            for i in range(1, len(ys)):
                if ys[i] - ys[i - 1] < 15:
                    mid = 0.5 * (ys[i] + ys[i - 1]); ys[i - 1] = mid - 7.5; ys[i] = mid + 7.5
        tw = d.textlength(title, font=font(12))
        d.text((x_text - tw if align == "right" else x_text, 6), title, font=font(12), fill=(180, 186, 200))
        for n, y in zip(names, ys):
            text = n.replace("_", " ") + (" (trim)" if lb.BANDS[n][3] else "")
            tw = d.textlength(text, font=f)
            if align == "right":
                d.rectangle([x_text - 10, y - 5, x_text, y + 5], fill=colour[n]); d.text((x_text - 16 - tw, y - 8), text, font=f, fill=(235, 235, 235))
            else:
                d.rectangle([x_text, y - 5, x_text + 10, y + 5], fill=colour[n]); d.text((x_text + 16, y - 8), text, font=f, fill=(235, 235, 235))
    return np.array(im)


def sheet_regions():
    S = 13.0; ZR = (-0.5, 43.0)
    w = ld.Wardrobe(wardrobe_path())
    bodies = {}
    for sex in ("female", "male"):
        b = lb.build(sex); ok, text = lb.check(b)
        assert ok, f"{sex}:\n{text}"
        bodies[sex] = b
    n = lb.counts(bodies["female"], head=False); nh = lb.counts(bodies["female"])[0] - n[0]
    tl = []; lab = []
    for sex in ("female", "male"):
        prep = mr.prepare_coloured(ld.dress(bodies[sex], w, [], paint=region_paint()).groups())
        front = mr.render(prep, 0, 0, scale=S, mode="lines", z_range=ZR)
        tl += [labelled(front, S, ZR) if sex == "female" else front] + [mr.render(prep, y, 0, scale=S, mode="lines", z_range=ZR) for y in (90, 180)]
        lab += [f"{sex}: front", f"{sex}: side", f"{sex}: back"]
    rows = [("1. The clothing regions, on both bodies",
             f"the same 32 regions a side as the voxel bodies, at the same heights. Bands alternate blue and orange; one-row trim bands are pale; back regions are darker. "
             f"Every polygon is in exactly one region. Each body is {n[0]} polygons, and its head {nh}.",
             band(tl, lab, gap_after=(2,)))]
    looks = [
        ("2. Tunic, trousers, boots (the 'everyday' outfit)", "the top stands one step off the body, with its collar and waist trims; the trousers are skin-tight with knee and ankle trims",
         [(e["item"], e["colourway"]) for e in w.outfits["everyday"]]),
        ("3. One-shoulder top, trousers, boots", "mirror off: the two sides of the top have their own regions",
         [("boots", "default"), ("trousers", "denim"), ("one_shoulder_top", "default")]),
        ("4. Shirt, bib, trousers, boots (overalls without the straps)", "all skin-tight; the bib shows over the shirt because it draws later, and only covers the front of the lower chest",
         [("boots", "default"), ("trousers", "denim"), ("shirt", "default"), ("bib", "default")]),
    ]
    for title, sub, worn in looks:
        tl = []; lab = []
        for sex in ("female", "male"):
            look = ld.dress(bodies[sex], w, worn); notes = look.notes
            prep = mr.prepare_coloured(look.groups())
            tl += [mr.render(prep, y, p, scale=S, z_range=ZR) for y, p in ((0, 12), (35, 15), (180, 12))]
            lab += [f"{sex}: front", f"{sex}: turned", f"{sex}: back"]
        if notes: print(" ", title, "|", "; ".join(notes))
        rows.append((title, sub, band(tl, lab, gap_after=(2,))))
    save_sheet(rows, "regions_and_outfits.png")


def sheet_joints(sex="female"):
    S = 13.0; frame = dict(scale=S, width=38.0, z_range=(-0.5, 45.5))
    w = ld.Wardrobe(wardrobe_path())
    b = lb.build(sex); ok, text = lb.check(b)
    assert ok, text
    # the robe top's own colours are near-black, which hides its folds on this background: show it in teal and bone
    w.items["robe_top"]["colourways"]["shown"] = {"cloth": "teal", "trim": "bone"}
    worn = [("boots", "default"), ("trousers", "default"), ("robe_top", "shown")]
    looks = {"bare": ld.dress(b, w, []).polys, "dressed": ld.dress(b, w, worn).polys}
    made = {}; added = {}
    for look, polys in looks.items():
        for pname, pose in (("walk", ps.WALK), ("big", ps.BIG)):
            rigid, extra = ps.posed_rigid(b, polys, pose)
            made[(look, pname, "rigid")] = mr.prepare_coloured({"all": rigid})
            made[(look, pname, "bend")] = mr.prepare_coloured({"all": ps.posed_bend(b, polys, pose)})
            added[look] = (len(polys), extra)
    print("polygons:", {k: f"{v[0]} as one skin, {v[0] + v[1]} as rigid pieces" for k, v in added.items()})
    names = {"rigid": "rigid pieces", "bend": "bending skin"}
    rows = []
    plan = [("1. Walking, bare", "walk", "bare", [("side", 90, 12), ("turned", 35, 15)],
             f"left: every part a rigid piece with rounded ends ({added['bare'][0] + added['bare'][1]} polygons). Right: one skin that bends ({added['bare'][0]} polygons)."),
            ("2. Walking, dressed", "walk", "dressed", [("side", 90, 12), ("turned", 35, 15)],
             "robe top (shown in teal), trousers and boots from the wardrobe file. As rigid pieces every garment piece needs its own rounded ends too."),
            ("3. A big move, bare", "big", "bare", [("front", 0, 12), ("side", 90, 12)],
             "a high step, one arm reaching forward with the elbow bent, the other out to the side, the chest leaning and turned, the head turned"),
            ("4. A big move, dressed", "big", "dressed", [("front", 0, 12), ("side", 90, 12)], "the same pose in the same clothes")]
    for title, pname, look, views, sub in plan:
        tl = []; lab = []
        for way in ("rigid", "bend"):
            tl += [mr.render(made[(look, pname, way)], y, p, **frame) for _, y, p in views]; lab += [f"{names[way]}: {v[0]}" for v in views]
        rows.append((title, sub, band(tl, lab, gap_after=(1,))))
    close = [("knee and hip, from the side", "bare", 90, 12, dict(scale=24.0, width=16.0, z_range=(2.0, 17.0))),
             ("seat and hip, from behind", "bare", 150, 15, dict(scale=24.0, width=16.0, z_range=(3.0, 18.0))),
             ("elbow in a sleeve", "dressed", 90, 12, dict(scale=24.0, width=16.0, z_range=(13.0, 28.0), centre_y=5.5))]
    tl = []; lab = []
    for name, look, y, p, kw in close:
        for way in ("rigid", "bend"):
            tl.append(mr.render(made[(look, "big", way)], y, p, **kw)); lab.append(f"{names[way]}: {name}")
    rows.append(("5. The big move, close up", "each pair: rigid pieces, then the bending skin", band(tl, lab, gap_after=(1, 3))))
    save_sheet(rows, "joints_rigid_or_bend.png")


def voxel_head(name):
    """One of the voxel heads (assets/head42_*.json) as square polygons, to draw beside its low-poly successor."""
    cells = {tuple(v) for v in json.load(open(os.path.join(ROOT, "assets", f"head42_{name}.json")))["voxels"] if v[2] >= 26}
    faces = []
    corners = {(1, 0, 0): [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], (-1, 0, 0): [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)],
               (0, 1, 0): [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)], (0, -1, 0): [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
               (0, 0, 1): [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, -1): [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]}
    for x, y, z in cells:
        for d, quad in corners.items():
            if (x + d[0], y + d[1], z + d[2]) not in cells:
                faces.append((np.array([[x + a, y + b, z + c] for a, b, c in quad], float), ld.SKIN))
    return faces


def sheet_heads():
    w = ld.Wardrobe(wardrobe_path())
    frame = dict(scale=22.0, width=22.0, z_range=(24.5, 43.5))
    heads = {n: hd.build(n) for n in hd.NAMES}
    for n in hd.NAMES:
        ok, text = hd.check(n, heads[n]); assert ok, text
    count = len(heads["round"])
    plain = {n: mr.prepare_coloured({"head": [(r["pts"], ld.SKIN) for r in heads[n]]}) for n in hd.NAMES}
    eyes = [(p, w.palette[c]) for p, c in hd.eye_preview()]
    faced = {n: mr.prepare_coloured({"head": [(r["pts"], ld.SKIN) for r in heads[n]], "unlit:eyes": eyes}) for n in hd.NAMES}
    voxel = {n: mr.prepare_coloured({"head": voxel_head(n)}) for n in hd.NAMES}
    rows = [("1. The voxel heads", "the five originals, for comparison", band([mr.render(voxel[n], 0, 12, **frame) for n in hd.NAMES], hd.NAMES)),
            ("2. The new heads, front", f"{count} polygons each, and the same layout of polygons on all five. Same height, depth and widths as the originals.",
             band([mr.render(plain[n], 0, 12, **frame) for n in hd.NAMES], hd.NAMES)),
            ("3. Side", "the face is flat where the eyes go, on every head", band([mr.render(plain[n], 90, 12, **frame) for n in hd.NAMES], hd.NAMES)),
            ("4. Turned", "", band([mr.render(plain[n], 35, 15, **frame) for n in hd.NAMES], hd.NAMES)),
            ("5. Turned, from behind, with the polygon edges drawn", "", band([mr.render(plain[n], 145, 15, mode="lines", **frame) for n in hd.NAMES], hd.NAMES)),
            ("6. With the standard open eye in place", "placement only: the eye boxes are where they were, the same size on every head. Lids, brows and colours are not rebuilt yet.",
             band([mr.render(faced[n], 0, 12, **frame) for n in hd.NAMES] , hd.NAMES))]
    tl = []; lab = []
    for i, n in enumerate(hd.NAMES):
        sex = "female" if i % 2 == 0 else "male"
        b = lb.build(sex, head=n)
        groups = {"all": [(r["pts"], ld.SKIN) for r in b["polys"]], "unlit:eyes": eyes}
        tl.append(mr.render(mr.prepare_coloured(groups), 0, 12, scale=15.0)); lab.append(f"{n}, on the {sex} body")
    rows.append(("7. On the bodies", "any head goes on any body", band(tl, lab)))
    save_sheet(rows, "heads.png")


def _shown(w):
    """Colourways for pictures: the robe and the cloak are near-black in their own colours, which hides every fold on
    this background, so they are also shown in green."""
    for item in ("robe_top", "robe_skirt"):
        if "moss" not in w.items[item]["colourways"]: w.items[item]["colourways"]["moss"] = {"cloth": "moss", "trim": "ochre", "hem": "ochre"}
    w.items["cloak"]["colourways"]["shown"] = {"cloth": "moss", "hem": "ochre", "lining": "rust"}
    return dict(robe=[("boots", "default"), ("trousers", "default"), ("robe_top", "moss"), ("robe_skirt", "moss")],
                travelling=[("boots", "default"), ("trousers", "default"), ("tunic", "rust"), ("cloak", "shown")])


def sheet_shapes():
    w = ld.Wardrobe(wardrobe_path()); shown = _shown(w)
    bodies = {sex: lb.build(sex) for sex in ("female", "male")}
    full = dict(scale=13.0, width=24.0, z_range=(-0.5, 43.0))
    legs = dict(scale=15.0, width=22.0, z_range=(-0.5, 19.0))
    notes = set()

    def tiles(worn, sex, views, frame, mode="facet"):
        prep, look = figure(bodies[sex], w, worn)
        notes.update(look.notes)
        return [mr.render(prep, y, p, mode=mode, **frame) for y, p in views]

    rows = []
    three = [(0, 12), (35, 15), (180, 12)]; names = ["front", "turned", "back"]
    tl = tiles(w.outfit("dress"), "female", three, full) + tiles(w.outfit("dress"), "male", three, full)
    rows.append(("1. Skirt: the dress outfit (bodice, skirt, boots)", "the skirt hangs from the waist line, over the hips, to its hem. The item's own regions make the waistband.",
                 band(tl, [f"female: {n}" for n in names] + [f"male: {n}" for n in names], gap_after=(2,))))

    top = [("boots", "default"), ("bodice", "default")]
    skirt = lambda **kw: top + [(with_settings(w, "skirt", **kw), "default")]
    plan = [("to knee", dict(length="to_knee")), ("to shin", dict(length="to_shin")), ("to ankle", dict(length="to_ankle")),
            ("flare 0", dict(length="to_shin", flare=0)), ("flare 1", dict(length="to_shin", flare=1)), ("flare 3", dict(length="to_shin", flare=3))]
    tl = [tiles(skirt(**kw), "female", [(0, 12)], legs)[0] for _, kw in plan]
    rows.append(("2. Skirt settings: length and flare", "the same settings as the voxel skirt, with the same names. Length is a band of the body, so it means the same on every body.",
                 band(tl, [n for n, _ in plan], gap_after=(2,))))
    plan = [("hem slant 4, high on its left", dict(length="to_shin", slant=4), (0, 12)), ("wrap, open on its left", dict(length="to_ankle", opening="wrap"), (0, 12)),
            ("wrap, open on its right", dict(length="to_ankle", opening="wrap", side="right"), (0, 12)), ("wrap with slant 4", dict(length="to_ankle", opening="wrap", slant=4), (35, 15)),
            ("open front", dict(length="to_ankle", opening="front"), (0, 12)), ("open front, turned", dict(length="to_ankle", opening="front"), (35, 15))]
    tl = [tiles(skirt(**kw), "female", [view], legs)[0] for _, kw, view in plan]
    rows.append(("3. Skirt settings: slanted hem, wrap, open front", "the hem trim follows the hem. A wrap is cut from one hip to just past the middle at the hem; an open front opens from the hips down.",
                 band(tl, [n for n, _, _ in plan], gap_after=(0, 3))))
    plan = [("four panels: front", dict(length="to_shin"), (0, 12)), ("four panels: turned", dict(length="to_shin"), (35, 15)),
            ("two panels: front", dict(length="to_shin", panels="two"), (0, 12)), ("two panels: turned", dict(length="to_shin", panels="two"), (35, 15)),
            ("two panels: side", dict(length="to_shin", panels="two"), (90, 12)), ("no waistband, no hem trim", dict(length="to_shin", waistband=False, hem_trim=False), (0, 12))]
    worn = lambda kw: ([("boots", "default"), ("shirt", "default")] if "waistband" in kw else top) + [(with_settings(w, "skirt", **kw), "default")]
    tl = [tiles(worn(kw), "female", [view], legs)[0] for _, kw, view in plan]
    rows.append(("4. Skirt settings: panels, waistband, hem trim", "four panels is one cloth all round. Two panels is a front cloth and a back cloth with the sides open. The last is worn with the shirt, which stops above the waist.",
                 band(tl, [n for n, _, _ in plan], gap_after=(1, 4))))

    two = [(0, 12), (35, 15)]
    tl = tiles(w.outfit("toga"), "female", two, full) + tiles(w.outfit("toga"), "male", two, full) + tiles(shown["robe"], "female", two, full) + tiles(shown["robe"], "male", two, full)
    rows.append(("5. The toga and robe outfits", "toga: one-shoulder top and wrap skirt. Robe: robe top and open-fronted skirt over trousers, shown in green (its own colours are near-black).",
                 band(tl, ["toga, female: front", "turned", "toga, male: front", "turned", "robe, female: front", "turned", "robe, male: front", "turned"], gap_after=(1, 3, 5))))

    chest = dict(scale=20.0, width=17.0, z_range=(12.0, 27.5))
    tl = tiles(w.outfit("shirt and suspenders"), "female", three, full) + tiles(w.outfit("overalls"), "male", three, full)
    tl += tiles(w.outfit("shirt and suspenders"), "female", [(35, 15)], chest) + tiles(w.outfit("overalls"), "male", [(145, 15)], chest)
    rows.append(("6. Straps: 'shirt and suspenders', and 'overalls'", "each strap is a flat band lying on the chest: over the shoulder beside the neck, then straight to the front of the waist. The skin at the waist is the wardrobe's: neither the shirt nor the trousers covers that row.",
                 band(tl, ["suspenders, female: front", "turned", "back", "overalls, male: front", "turned", "back", "close: turned", "close: from behind"], gap_after=(2, 5))))

    back = [(0, 12), (90, 12), (145, 15), (180, 12)]
    tl = tiles(w.outfit("travelling"), "female", [(145, 15)], full) + tiles(shown["travelling"], "female", back, full) + tiles(shown["travelling"], "male", back[1:], full)
    rows.append(("7. Cape: the travelling outfit (the cloak; its hood is not built yet)", "the cape hangs from the shoulder line, over the back. First picture: its own colours. The rest: shown in green so that it can be seen.",
                 band(tl, ["own colours: from behind", "female: front", "side", "from behind", "back", "male: side", "from behind", "back"], gap_after=(0, 4))))
    cape = lambda **kw: shown["travelling"][:3] + [(with_settings(w, "cloak", **kw), "shown")]
    upper = dict(scale=13.0, width=24.0, z_range=(-0.5, 28.0))
    plan = [("to waist", dict(length="to_waist")), ("to knee", dict(length="to_knee")), ("to ankle", dict(length="to_ankle")),
            ("narrow", dict(width="narrow")), ("wide", dict(width="wide")), ("flare 0", dict(flare=0)), ("flare 3", dict(flare=3))]
    tl = [tiles(cape(**kw), "female", [(180, 12)], upper)[0] for _, kw in plan]
    rows.append(("8. Cape settings: length, width, flare", "seen from the back. Width is against the shoulders: narrower, the same, or wider by one unit each side.",
                 band(tl, [n for n, _ in plan], gap_after=(2, 4))))
    for n in sorted(notes): print("  note:", n)
    save_sheet(rows, "special_shapes.png")


def sheet_moving():
    w = ld.Wardrobe(wardrobe_path()); shown = _shown(w)
    poses = {name: ps.from_game(v["parts"]) for name, v in game.tables()["poses"].items()}
    bodies = {sex: lb.build(sex) for sex in ("female", "male")}
    frame = dict(scale=13.0, width=30.0, z_range=(-0.5, 43.0))

    def tiles(worn, sex, pose, views):
        prep, _ = figure(bodies[sex], w, worn, poses[pose])
        return [mr.render(prep, y, p, **frame) for y, p in views]

    cast = [("dress", w.outfit("dress"), "female"), ("toga", w.outfit("toga"), "male"), ("robe", shown["robe"], "female"), ("cloak", shown["travelling"], "male")]
    rows = []
    for num, pose, title, sub in (("1", "mid_stride", "Mid-stride", "the forward knee pushes the front of the cloth out and the back heel pushes the back out; nowhere else does it move"),
                                  ("2", "sitting", "Sitting", "the cloth lies over the lap and knees, then hangs from them. There is no seat in the picture: the pose only bends the legs.")):
        tl = []; lab = []
        for name, worn, sex in cast:
            tl += tiles(worn, sex, pose, [(90, 12), (35, 15)]); lab += [f"{name}, {sex}: side", "turned"]
        rows.append((f"{num}. {title} (the game's test pose)", sub, band(tl, lab, gap_after=(1, 3, 5))))
    tl = tiles(w.outfit("overalls"), "male", "arms_raised", [(0, 12), (145, 15)]) + tiles(w.outfit("shirt and suspenders"), "female", "reaching", [(35, 15)])
    tl += tiles(shown["travelling"], "female", "arms_raised", [(145, 15)]) + tiles(shown["travelling"], "male", "reaching", [(145, 15), (90, 12)])
    tl += tiles(w.outfit("dress"), "female", "t_pose", [(0, 12)])
    rows.append(("3. Arms raised, reaching, T-pose", "straps are fixed to the chest and turn with it. A cape hangs from the shoulder line whatever the arms do. A skirt does not move for the arms.",
                 band(tl, ["overalls: arms raised", "from behind", "suspenders: reaching", "cloak: arms raised", "cloak: reaching", "side", "dress: T-pose"], gap_after=(2, 5))))
    close = dict(scale=22.0, width=22.0, z_range=(0.0, 17.0))
    tl = []; lab = []
    for name, worn, sex, pose, view in (("dress, mid-stride", w.outfit("dress"), "female", "mid_stride", (90, 8)), ("dress, mid-stride, from behind", w.outfit("dress"), "female", "mid_stride", (150, 15)),
                                        ("dress, sitting", w.outfit("dress"), "female", "sitting", (60, 15)), ("robe, sitting", shown["robe"], "female", "sitting", (20, 15)),
                                        ("toga, mid-stride", w.outfit("toga"), "male", "mid_stride", (35, 15))):
        prep, _ = figure(bodies[sex], w, worn, poses[pose])
        tl.append(mr.render(prep, view[0], view[1], mode="lines", **close)); lab.append(name)
    rows.append(("4. Close up, with the polygon edges drawn", "each cloth is a few columns of points; the rows of points slide to wherever the cloth bends",
                 band(tl, lab)))
    save_sheet(rows, "special_shapes_moving.png")


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    jobs = dict(look=sheet_look, male=sheet_male, regions=sheet_regions, joints=sheet_joints, heads=sheet_heads,
                shapes=sheet_shapes, moving=sheet_moving)
    if which != "all" and which not in jobs:
        sys.exit(__doc__)
    for name in (jobs if which == "all" else [which]):
        t0 = time.time(); jobs[name](); print(f"{name}: done ({time.time() - t0:.0f} s)")
