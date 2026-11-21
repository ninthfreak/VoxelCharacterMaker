"""Review sheets for the low-poly bodies.

  python3 lowpoly/sheets.py look      the first cut: the feminine average at two polygon budgets, beside its clay
  python3 lowpoly/sheets.py male      the masculine average (budget A), beside its clay and the feminine one
  python3 lowpoly/sheets.py builds    the eight bodies as clay: slim, average, heavy and short, each sex
  python3 lowpoly/sheets.py bodies    the eight low-poly bodies: bare, their regions, dressed, posed, as characters
  python3 lowpoly/sheets.py regions   the bodies the clothing system uses: their regions, then starter outfits
  python3 lowpoly/sheets.py joints    the comparison behind the joints decision: rigid pieces, or one bending skin
  python3 lowpoly/sheets.py heads     the five heads as rounded forms, with the face treated two ways
  python3 lowpoly/sheets.py faces     the face: eyes with lashes and lids, eyebrows, the mouth, skin tones, colours
  python3 lowpoly/sheets.py beards    facial hair: four parts, each on or off, and one length
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
import clay, rings as ring_tools, body as lb, dress as ld, picture as mr, pose as ps, heads as hd, faces as fc, facial_hair as fh, game
import drawn as dr

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


BUILDS = ["slim", "average", "heavy", "short"]
BUILD_VIEWS = [("front", 0, 0), ("turned", 35, 10), ("side", 90, 0)]


def _draw_clay(job):
    sex, build, yaw, pitch, path = job
    model = clay.BODIES[(sex, build)]
    big = clay.render(lambda p: clay.body(p, model), yaw, pitch, scale=24, width=30.0)
    im = Image.fromarray(big); im.resize((im.width // 2, im.height // 2), Image.BOX).save(path)


def build_tiles(sex, build):
    """The clay of one build in BUILD_VIEWS, drawn once and kept in lowpoly/_work/ (redrawn when the clay changes)."""
    import hashlib, multiprocessing
    os.makedirs(WORK, exist_ok=True)
    jobs = []
    for b in BUILDS:
        tag = hashlib.sha1(repr(clay.BODIES[(sex, b)]).encode()).hexdigest()[:10]
        for name, y, p in BUILD_VIEWS:
            jobs.append((sex, b, y, p, os.path.join(WORK, f"build_{sex}_{b}_{name}_{tag}.png")))
    missing = [j for j in jobs if not os.path.exists(j[4])]
    if missing:
        t0 = time.time()
        with multiprocessing.Pool(min(4, len(missing))) as pool: pool.map(_draw_clay, missing)
        print(f"  drew {len(missing)} clay views ({time.time() - t0:.0f} s)", flush=True)
    return [np.array(Image.open(j[4]).convert("RGB")) for j in jobs if j[1] == build]


def widths(model):
    """The torso's width at the chest, the waist and the hips, and the figure's height: what the eye compares."""
    sdf = lambda p: clay.body(p, model, parts="torso")
    def across(name):
        c, _ = model[name]; z = c[2]; y = 12.0 + c[1]
        lo, hi = 0.0, 15.0
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            if sdf(np.array([[12.0 + mid, y, z]]))[0] < 0: lo = mid
            else: hi = mid
        return 2 * lo
    top = model["head"][0][2] + model["head"][1][2]
    return across("ribcage"), across("abdomen"), across("pelvis"), top


def sheet_builds():
    """The eight bodies as clay: slim, average, heavy and short, for each sex. The six new ones are a first pass."""
    rows = []
    for k, (sex, title) in enumerate((("female", "Feminine"), ("male", "Masculine"))):
        tiles = {b: build_tiles(sex, b) for b in BUILDS}
        size = {b: widths(clay.BODIES[(sex, b)]) for b in BUILDS}
        notes = ["slim, heavy and short are made from the average clay; the low-poly bodies are cut from these (bodies_builds.png).",
                 "torso widths, chest / waist / hips: " + ";  ".join(f"{b} {size[b][0]:.1f} / {size[b][1]:.1f} / {size[b][2]:.1f}" for b in BUILDS),
                 "heavy is more mass everywhere, with no belly in front of the chest. Short is broader, then shorter; the head is the same."]
        for i, (name, _, _) in enumerate(BUILD_VIEWS):
            rows.append((f"{k + 1}. {title} bodies" if i == 0 else "", notes[i],
                         band([tiles[b][i] for b in BUILDS], [f"{b}, {size[b][3]:.0f} tall" if i == 0 else f"{b}: {name}" for b in BUILDS])))
    save_sheet(rows, "bodies_builds_clay.png")


def sheet_bodies():
    """The eight low-poly bodies: bare, their regions, dressed, posed, and as characters."""
    w = ld.Wardrobe(wardrobe_path()); shown = _shown(w); tables = game.tables()
    poses = {name: ps.from_game(v["parts"]) for name, v in tables["poses"].items()}
    full = dict(scale=13.0, width=26.0, z_range=(-0.5, 43.0))
    order = ["slim", "average", "heavy", "short"]
    bodies = {}
    for sex in ("female", "male"):
        for b in order:
            body = lb.build(sex, b); ok, text = lb.check(body)
            assert ok, f"{sex} {b}:\n{text}"
            bodies[(sex, b)] = body
    data = lb.to_data(bodies[("female", "average")])
    short = bodies[("female", "short")]["bands"]
    rows = []
    for k, (sex, title) in enumerate((("female", "Feminine"), ("male", "Masculine"))):
        tl = []; lab = []
        for b in order:
            prep, _ = figure(bodies[(sex, b)], w, [])
            for name, y, p in (("front", 0, 12), ("turned", 35, 15), ("side", 90, 12)):
                tl.append(mr.render(prep, y, p, **full)); lab.append(f"{b}: {name}")
        sub = (f"each is the average body with its corners moved: the same {len(data['vertices'])} corners and {len(data['polygons'])} polygons, "
               f"the same regions and joints, on all eight bodies" if k == 0 else
               f"short: the same bands, lower ({short['neck'][1]:.1f} to the top of the neck, against 26), and the same head on the shorter neck: 36 tall")
        rows.append((f"{k + 1}. {title} bodies: slim, average, heavy, short", sub, band(tl, lab, gap_after=(2, 5, 8))))

    tl = []; lab = []
    for sex in ("female", "male"):
        for b in order:
            prep = mr.prepare_coloured(ld.dress(bodies[(sex, b)], w, [], paint=region_paint()).groups())
            tl.append(mr.render(prep, 0, 0, mode="lines", **full)); lab.append(f"{sex} {b}")
    rows.append(("3. The clothing regions on every body", "the same 32 regions a side on all eight; bands alternate blue and orange, one-row trim bands are pale. "
                 "On the short bodies every band is lower.", band(tl, lab, gap_after=(3,))))

    def dressed(sex, b, worn, yaw, pitch, pose=None, frame=full, **who):
        prep, look = figure(bodies[(sex, b)], w, worn, pose, **who)
        odd = [n for n in look.notes if "edge style" not in n and "'hood' not built" not in n]      # not built yet: see the README
        assert not odd, f"{sex} {b}: {odd}"
        return mr.render(prep, yaw, pitch, **frame)

    tl = [dressed("female", b, w.outfit("dress"), 35, 15) for b in order] + [dressed("male", b, w.outfit("overalls"), 35, 15) for b in order]
    rows.append(("4. The same outfits on every body", "nothing is set per body: every clothing rule reads the body's regions and heights. "
                 "Feminine: the dress (bodice, skirt, boots). Masculine: the overalls (shirt, trousers, bib, straps).",
                 band(tl, [f"dress, {b}" for b in order] + [f"overalls, {b}" for b in order], gap_after=(3,))))

    tl = [dressed("female", b, w.outfit("dress"), 35, 15, poses["sitting"]) for b in order]
    tl += [dressed("male", b, shown["travelling"], 145, 15, poses["mid_stride"]) for b in order]
    rows.append(("5. In the game's test poses", "sitting in the dress: the skirt lies over the lap and falls at the knees. "
                 "Striding in the travelling clothes, from behind: the cloak hangs from the shoulders.",
                 band(tl, [f"sitting, {b}" for b in order] + [f"striding, {b}" for b in order], gap_after=(3,))))

    beard = w.facial_hair(fh.PARTS, "long")
    cast = [("male", w.outfit("overalls"), dict(skin="tan", features=[("short_crop", "auburn"), (beard, "default")], eyes=dict(colourway="amber"))),
            ("female", shown["robe"], dict(skin="brown", features=[("short_crop", "black")], eyes=dict(colourway="blue"), mouth="smile"))]
    tl = []; lab = []
    for sex, worn, who in cast:
        for b in ("average", "short"):
            for yaw, pitch in ((0, 8), (35, 15)):
                tl.append(dressed(sex, b, worn, yaw, pitch, **who)); lab.append(f"{sex} {b}: " + ("front" if yaw == 0 else "turned"))
    rows.append(("6. Characters on the short bodies", "the face, the hair and the beard go with the head: on a short body they are the average's, 6 units lower. "
                 "Masculine: overalls, a full long beard. Feminine: the robe (shown in green).", band(tl, lab, gap_after=(3,))))
    save_sheet(rows, "bodies_builds.png")


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


def figure(b, w, worn, pose=None, **who):
    """A dressed figure in a pose, ready to draw. who: what dress() takes beyond the clothes (skin, features, eyes,
    brow, mouth); the standard eyes and a mouth, both neutral, unless it says otherwise. Returns (prepared, the look)."""
    who.setdefault("eyes", {}); who.setdefault("mouth", "neutral")
    look = ld.dress(b, w, worn, **who)
    return mr.prepare_coloured(look.groups(pose)), look


def open_eyes(w, bend=None):
    """The standard eye wide open, with no brow, for pictures of bare heads."""
    return [(q["pts"], q["rgb"]) for q in fc.eyes(game.tables(), w, lids="", bend=bend)]


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


FACE_BENDS = [("one flat face", 0.0), ("each eye on its own flat patch, turned 15 degrees outward", 15.0)]


def sheet_heads():
    """The heads as rounded forms, with the face treated two ways, beside the first rebuild they replace."""
    w = ld.Wardrobe(wardrobe_path())
    frame = dict(scale=22.0, width=22.0, z_range=(24.5, 43.5))
    small = dict(scale=16.0, width=22.0, z_range=(24.5, 43.5))
    made = {}
    for _, bend in FACE_BENDS:
        for n in hd.NAMES:
            polys = hd.build(n, bend); ok, text = hd.check(n, polys, bend)
            assert ok, text
            made[(n, bend)] = mr.prepare_coloured({"head": [(r["pts"], ld.SKIN) for r in polys], "unlit:eyes": open_eyes(w, bend)})
    count = len(hd.build("round"))
    shot = lambda bend, yaw, pitch, fr=frame, mode="facet", names=hd.NAMES: [mr.render(made[(n, bend)], yaw, pitch, mode=mode, **fr) for n in names]
    rows = []
    before = os.path.join(RENDERS, "heads_first_rebuild.png")
    if os.path.exists(before):                                       # the "turned" row of the first rebuild's sheet
        old = Image.open(before).convert("RGB")
        tw, th, top = int(frame["scale"] * frame["width"]), int(frame["scale"] * 19.0), 3 * (78 + 418 + 30) + 78 + 30
        tl = [np.array(old.crop((PAD + i * (tw + PAD), top, PAD + i * (tw + PAD) + tw, top + th))) for i in range(5)]
        rows.append(("1. As they were", "the first low-poly rebuild: blocks with bevelled edges", band(tl, hd.NAMES)))
    (name_a, a), (name_b, b) = FACE_BENDS
    rows.append((f"2. Rounder, A: {name_a}", f"a domed crown, a round back, cheeks that turn the corner in steps, a tapering jaw. {count} polygons each. "
                 "Both eyes on one plane, as the spec has it, so the front stays flat.", band(shot(a, 35, 15), hd.NAMES)))
    rows.append((f"3. Rounder, B: {name_b}", "the same heads, with the front round too. Each eye, with its brow, still lies flat; the two patches meet down the middle of the face.",
                 band(shot(b, 35, 15), hd.NAMES)))
    rows.append(("4. A from the front", "", band(shot(a, 0, 12), hd.NAMES)))
    rows.append(("5. B from the front", "from straight ahead the two are nearly the same", band(shot(b, 0, 12), hd.NAMES)))
    pair = ["round", "heart"]
    tl = shot(a, 90, 0, small, names=pair) + shot(a, 0, 89, small, names=pair) + shot(b, 90, 0, small, names=pair) + shot(b, 0, 89, small, names=pair)
    rows.append(("6. From the side, and from above", "round and heart. A on the left, B on the right. From above, the face is toward the bottom of the picture.",
                 band(tl, ["A: round, side", "A: heart, side", "A: round, above", "A: heart, above", "B: round, side", "B: heart, side", "B: round, above", "B: heart, above"], gap_after=(3,))))
    tl = []; lab = []
    for tag, bend in (("A", a), ("B", b)):
        keep = hd.FACE_BEND; hd.FACE_BEND = bend
        try:
            for n, sex in (("round", "female"), ("strong", "male")):
                body = lb.build(sex, head=n)
                prep = mr.prepare_coloured({"all": [(r["pts"], ld.SKIN) for r in body["polys"]], "unlit:eyes": open_eyes(w, bend)})
                tl += [mr.render(prep, 0, 12, scale=13.0, width=22.0), mr.render(prep, 35, 15, scale=13.0, width=22.0)]
                lab += [f"{tag}: {n}, {sex}", "turned"]
        finally:
            hd.FACE_BEND = keep
    rows.append(("7. On the bodies", "any head goes on any body, as before", band(tl, lab, gap_after=(3,))))
    rows.append(("8. B from behind, with the polygon edges drawn", "the same layout of polygons on all five heads, with an edge on every head region",
                 band(shot(b, 145, 15, mode="lines"), hd.NAMES)))
    save_sheet(rows, "heads.png")


def called_out(tile, scale, z_top, notes, margin=380):
    """A front view with short notes beside it, each joined to its own height. notes: [(height, text)], top first."""
    h, w = tile.shape[:2]
    im = Image.new("RGB", (w + margin, h), BG); im.paste(Image.fromarray(tile), (0, 0)); d = ImageDraw.Draw(im)
    at = [(z_top - z) * scale for z, _ in notes]; ys = list(at)
    for _ in range(80):                                              # keep the notes from overlapping
        for i in range(1, len(ys)):
            if ys[i] - ys[i - 1] < 26:
                mid = 0.5 * (ys[i] + ys[i - 1]); ys[i - 1] = mid - 13; ys[i] = mid + 13
    for (z, text), y, y_text in zip(notes, at, ys):
        d.line([(w - 96, y), (w - 30, y), (w + 4, y_text)], fill=(170, 176, 190), width=2)
        d.text((w + 12, y_text - 10), text, font=font(16, True), fill=(235, 235, 235))
    return np.array(im)


def sheet_faces():
    """The face on the low-poly heads: eyes with lashes and lids, eyebrows, the mouth, facial hair."""
    w = ld.Wardrobe(wardrobe_path()); tables = game.tables()
    standard = w.eye_sets["standard"]                                # eye colour is a colourway: make two more, as the editor would
    for name in ("blue", "amber"): standard["colourways"][name] = dict(standard["colourways"]["default"], pupil="eye_" + name)
    crop = w.features["short_crop"][1]
    for name in ("fair", "grey"): crop["colourways"][name] = {"hair": "hair_" + name}
    big = dict(scale=20.0, width=22.0, z_range=(24.5, 43.5)); mid = dict(scale=18.0, width=22.0, z_range=(24.5, 43.5))
    bodies = {}; notes = set()

    def tile(yaw, pitch, head="round", sex="female", frame=big, worn=(), **who):
        if (sex, head) not in bodies: bodies[(sex, head)] = lb.build(sex, head=head)
        prep, look = figure(bodies[(sex, head)], w, list(worn), **who)
        notes.update(look.notes)
        return mr.render(prep, yaw, pitch, **frame)

    order = tables["eyes"]["order"]; label = lambda s: s.replace("_", " ")
    box = tables["eyes"]["box"]; half = 0.5 * box["h"] * fc.EYE_SIZE
    close = dict(scale=27.0, width=22.0, z_range=(24.5, 43.5)); small = dict(scale=7.0, width=22.0, z_range=(24.5, 43.5))
    said = [(fc.EYE_MIDDLE + half + 0.7 * fc.EYE_SIZE, "eyebrow: a bar of its own"), (fc.EYE_MIDDLE + half - 1.0 * fc.EYE_SIZE, "lash line: thin, on the eye's top edge"),
            (fc.EYE_MIDDLE, "eye: at the middle of the face"), (0.5 * (fc.EYE_MIDDLE - half + fc.MOUTH_Z), "room for a moustache"),
            (fc.MOUTH_Z, "mouth: a little lower"), (27.5, "jaw: room for a beard")]
    tl = [called_out(tile(0, 0, frame=close), close["scale"], close["z_range"][1], said), tile(35, 12, frame=close), tile(0, 8, frame=small)]
    rows = [("1. The face, laid out", f"eyes at size B ({box['w'] * fc.EYE_SIZE:.1f} wide, {box['h'] * fc.EYE_SIZE:.1f} tall), moved up to the middle of the flat part of the face; "
             "the mouth moved down a little. The thick bar on the eyelid is gone.", band(tl, ["from the front", "turned", "small"]))]
    pair = [fc.eyes(tables, w, lids=s) for s in order]
    most = max(sum(len(q["pts"]) - 2 for q in e) for e in pair)
    rows += [("2. The ten lid states", "the game's own ten, unchanged. The eyebrow goes up for a wide open eye, down for a lowered lid, and tilts with the lid, though less. "
              f"A pair of eyes with brows is up to {most} triangles.",
              band([tile(0, 8, eyes=dict(lids=s)) for s in order[:5]], [label(s) for s in order[:5]])),
             ("", "", band([tile(0, 8, eyes=dict(lids=s)) for s in order[5:]], [label(s) for s in order[5:]]))]
    some = ["neutral", "unimpressed", "angry", "sad", "wink"]
    rows.append(("3. Turned", "each eye, with its brow, lies flat on its own patch of the head. The mouth bends round the middle of the face.",
                 band([tile(35, 12, eyes=dict(lids=s)) for s in some], [label(s) for s in some])))
    plan = [("neutral", "neutral", "neutral"), ("neutral", "smile", "smile"), ("sad", "frown", "frown, with sad eyes"), ("wide_open", "open", "open, with wide open eyes"),
            ("blink", "smile", "smile, with a blink"), ("angry", "frown", "frown, with angry eyes")]
    rows.append(("4. The mouth", "still a first pass: a short line, straight or curved, or a small open oval. Which mouth goes with which eyes is the game's to choose.",
                 band([tile(0, 8, frame=mid, eyes=dict(lids=lids), mouth=m) for lids, m, _ in plan], [p[2] for p in plan])))
    tones = tables["skin_order"]; heads = ["round", "boxy", "oval", "strong", "heart", "round"]
    rows.append(("5. The six skin tones", "the game's six, lightest first. The lid is the skin half a shade darker (shown: unimpressed, so that the lid can be seen); the mouth follows the skin too. One head of each shape.",
                 band([tile(0, 8, head=h, frame=mid, skin=tone, eyes=dict(lids="unimpressed")) for tone, h in zip(tones, heads)],
                      [f"{tone} skin, {h} head" for tone, h in zip(tones, heads)])))
    plan = [("default", "default", "dark eyes, brown hair"), ("blue", "black", "blue eyes, black hair"), ("amber", "auburn", "amber eyes, auburn hair"),
            ("default", "fair", "dark eyes, fair hair"), ("blue", "grey", "blue eyes, grey hair"), ("default", None, "bald: brows of dark brown")]
    rows.append(("6. Eye colour, and eyebrows that follow the hair", "eye colour is a colourway of the eye set, and so is the lash line's colour. The eyebrow is the hair's colour one shade darker. "
                 "The hair is a stand-in: hair itself is not rebuilt yet.",
                 band([tile(0, 8, frame=mid, eyes=dict(colourway=eye), features=[("short_crop", hair)] if hair else []) for eye, hair, _ in plan], [p[2] for p in plan])))
    man = dict(head="strong", sex="male", frame=mid, skin="light")
    tl = []; lab = []
    for parts, length, name in ((fh.PARTS, "stubble", "full beard, stubble"), (fh.PRESETS["goatee and moustache"], "short", "goatee and moustache, short"),
                                (fh.PARTS, "medium", "full beard, medium")):
        worn = [(w.facial_hair(parts, length), "default")]
        tl += [tile(0, 8, features=[("short_crop", "default")] + worn, **man), tile(40, 10, features=[("short_crop", "default")] + worn, **man)]
        lab += [name, "turned"]
    rows.append(("7. Facial hair", "three of the ways to wear it. Facial hair has a sheet of its own: facial_hair.png.", band(tl, lab, gap_after=(1, 3))))
    full = dict(scale=13.0, width=24.0, z_range=(-0.5, 43.0)); tiny = dict(scale=5.0, width=24.0, z_range=(-0.5, 43.0))
    cast = [("female", "round", w.outfit("everyday"), dict(skin="light", features=[("short_crop", "auburn")], eyes=dict(colourway="blue"), mouth="smile"), "everyday, smiling"),
            ("male", "strong", w.outfit("overalls"), dict(skin="tan", features=[("short_crop", "black"), (w.facial_hair(fh.PARTS, "medium"), "default")], eyes=dict(lids="unimpressed")), "overalls, full beard"),
            ("female", "heart", w.outfit("dress"), dict(skin="brown", features=[("short_crop", "black")], eyes=dict(lids="sad"), mouth="frown"), "dress, sad"),
            ("male", "boxy", _shown(w)["travelling"], dict(skin="pale", features=[("short_crop", "grey"), (w.facial_hair(fh.PARTS, "stubble"), "default")], eyes=dict(lids="angry", colourway="amber"), mouth="frown"), "green cloak, stubble, angry")]
    tl = []; lab = []
    for sex, h, worn, who, name in cast:
        tl += [tile(0, 12, head=h, sex=sex, frame=full, worn=worn, **who), tile(35, 15, head=h, sex=sex, frame=full, worn=worn, **who)]
        lab += [name, "turned"]
    rows.append(("8. Whole characters", "body, head, skin tone, eyes, eyebrows, mouth, hair, facial hair and an outfit together", band(tl, lab, gap_after=(1, 3, 5))))
    tl = [tile(yaw, 12, head=h, sex=sex, frame=tiny, worn=worn, **who) for sex, h, worn, who, _ in cast for yaw in (0, 35)]
    rows.append(("9. The same four, small", "about the size a character might be on screen", band(tl, [""] * len(tl), gap_after=(1, 3, 5))))
    for n in sorted(notes): print("  note:", n)
    save_sheet(rows, "faces.png")


def sheet_beards():
    """Facial hair on the low-poly heads: four parts, each on or off, and one length."""
    w = ld.Wardrobe(wardrobe_path()); tables = game.tables()
    crop = w.features["short_crop"][1]
    for name in ("black", "auburn", "fair", "grey"): crop["colourways"].setdefault(name, {"hair": "hair_" + name})
    mid = dict(scale=18.0, width=22.0, z_range=(23.5, 43.5))
    bodies = {}; notes = set()

    def tile(yaw, pitch, parts=(), length="short", hair="default", head="strong", sex="male", frame=mid, clothes=(), **who):
        if (sex, head) not in bodies: bodies[(sex, head)] = lb.build(sex, head=head)
        features = ([("short_crop", hair)] if hair else []) + ([(w.facial_hair(parts, length), "default")] if parts else [])
        prep, look = figure(bodies[(sex, head)], w, list(clothes), features=features, **{"skin": "light", **who})
        notes.update(look.notes)
        return mr.render(prep, yaw, pitch, **frame)

    lengths = list(fh.LENGTHS)
    rows = [("1. Four parts, each on or off", "shown at the short length, so that the shapes are clear. \"Cheeks\" is the name used here for the part between the sideburns and the goatee: "
             "the jaw, the lower cheeks and the face beside the mouth.", band([tile(0, 8, (part,)) for part in fh.PARTS] + [tile(0, 8, fh.PARTS)], list(fh.PARTS) + ["all four: a full beard"], gap_after=(3,))),
            ("", "", band([tile(40, 10, (part,)) for part in fh.PARTS] + [tile(40, 10, fh.PARTS)], [f"{part}, turned" for part in fh.PARTS] + ["all four, turned"], gap_after=(3,)))]
    rows.append(("2. One length for every part, done the way clothes do bulk", "stubble: a tint, flush with the face. Short: opaque, still flush. Medium and long: grown out from the face, "
                 f"by {fh.LENGTHS['medium']:g} and {fh.LENGTHS['long']:g} steps of bulk, with edges like a sleeve's. Shown: a full beard (every part on).",
                 band([tile(0, 8, fh.PARTS, ln) for ln in lengths] + [tile(40, 10, fh.PARTS, ln) for ln in lengths[1:3]], lengths + [f"{ln}, turned" for ln in lengths[1:3]], gap_after=(3,))))
    rows.append(("", "", band([tile(90, 5, fh.PARTS, ln) for ln in lengths] + [tile(40, 10, fh.PARTS, ln, hair=None) for ln in ("short", "long")],
                              [f"{ln}, from the side" for ln in lengths] + [f"bald, {ln}" for ln in ("short", "long")], gap_after=(3,))))
    names = [n for n in fh.PRESETS if n != "full beard"]
    rows.append(("3. A named style is a set of parts", "full beard: every part. Amish: every part but the moustache. And so on. Shown at medium length.",
                 band([tile(0, 8, fh.PRESETS[n], "medium") for n in names], names)))
    plan = [(fh.PRESETS["goatee and moustache"], ln, f"goatee and moustache: {ln}") for ln in lengths] + [(fh.PRESETS["Amish"], "long", "Amish, long"), (("sideburns",), "long", "sideburns, long")]
    rows.append(("4. The length on other styles", "a moustache or sideburns on their own, grown out a whole step, stand off the face as much as a full beard does",
                 band([tile(40, 10, parts, ln) for parts, ln, _ in plan], [p[2] for p in plan], gap_after=(3,))))
    rows.append(("5. The game's three facial hair items, read as parts and a length", "stubble: every part, stubble. Chinstrap: the Amish parts, medium (a chinstrap's narrow strap is not a part). "
                 "Full beard: every part, medium.", band([tile(0, 8, *fh.GAME_STYLES[g]) for g in fh.GAME_STYLES] + [tile(40, 10, *fh.GAME_STYLES[g]) for g in fh.GAME_STYLES],
                                                           [g.replace("_", " ") for g in fh.GAME_STYLES] + ["turned"] * 3, gap_after=(2,))))
    plan = [("round", "pale"), ("boxy", "light"), ("oval", "tan"), ("strong", "medium"), ("heart", "brown"), ("round", "deep")]
    rows.append(("6. On every head, in every skin tone", "a black full beard, long. It is cut into each head's own polygons, so it follows each shape.",
                 band([tile(0, 8, fh.PARTS, "long", hair="black", head=h, skin=tone) for h, tone in plan], [f"{h} head, {tone} skin" for h, tone in plan])))
    plan = [("stubble", "pale", "black"), ("stubble", "tan", "auburn"), ("stubble", "deep", None), ("medium", "light", "auburn"), ("medium", "medium", "fair"), ("medium", "light", "grey")]
    rows.append(("7. Colours follow the hair and the skin", "stubble is the game's own stubble colour, worked out from the skin and the hair, always darker than the skin. "
                 "Every other length is the hair's colour; dark brown on a bald head.",
                 band([tile(0, 8, fh.PARTS, ln, hair=hc, skin=tone) for ln, tone, hc in plan], [f"{ln}: {tone} skin, {hc or 'bald'}" for ln, tone, hc in plan], gap_after=(2,))))
    plan = [(("moustache",), "stubble", "smile", "neutral", "stubble moustache: smile"), (("moustache",), "short", "smile", "neutral", "short moustache: smile"),
            (("moustache",), "medium", "open", "wide_open", "medium moustache: open"), (fh.PARTS, "long", "smile", "neutral", "long beard: smile"),
            (fh.PARTS, "long", "frown", "sad", "long beard: frown"), (fh.PRESETS["Amish"], "medium", "open", "wide_open", "Amish: open")]
    rows.append(("8. With a mouth", "under stubble the mouth shows whole. A moustache that is more than stubble hangs over the mouth. A beard leaves the mouth a gap.",
                 band([tile(0, 8, parts, ln, mouth=m, eyes=dict(lids=lids)) for parts, ln, m, lids, _ in plan], [p[4] for p in plan])))
    full = dict(scale=13.0, width=24.0, z_range=(-0.5, 43.0)); tiny = dict(scale=5.0, width=24.0, z_range=(-0.5, 43.0))
    cast = [(fh.PARTS, "medium", "black", "strong", w.outfit("overalls"), dict(skin="tan"), "overalls: full beard, medium"),
            (fh.PRESETS["goatee and moustache"], "short", "auburn", "round", w.outfit("everyday"), dict(skin="light", mouth="smile"), "everyday: goatee, moustache"),
            (fh.PARTS, "stubble", "grey", "boxy", _shown(w)["travelling"], dict(skin="pale", eyes=dict(lids="angry", colourway="amber"), mouth="frown"), "green cloak: stubble"),
            (fh.PRESETS["Amish"], "long", None, "oval", w.outfit("toga"), dict(skin="medium", eyes=dict(lids="unimpressed")), "toga: bald, Amish, long")]
    tl = []; lab = []
    for parts, ln, hair, h, clothes, who, name in cast:
        tl += [tile(0, 12, parts, ln, hair=hair, head=h, frame=full, clothes=clothes, **who), tile(35, 15, parts, ln, hair=hair, head=h, frame=full, clothes=clothes, **who)]
        lab += [name, "turned"]
    rows.append(("9. Whole characters", "body, outfit, hair and facial hair together", band(tl, lab, gap_after=(1, 3, 5))))
    tl = [tile(yaw, 12, parts, ln, hair=hair, head=h, frame=tiny, clothes=clothes, **who) for parts, ln, hair, h, clothes, who, _ in cast for yaw in (0, 35)]
    rows.append(("10. The same four, small", "about the size a character might be on screen", band(tl, [""] * len(tl), gap_after=(1, 3, 5))))
    for n in sorted(notes): print("  note:", n)
    save_sheet(rows, "facial_hair.png")


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


def sheet_hood():
    """The hood, raised and lowered, on every head and build, with its settings, in the game's poses."""
    w = ld.Wardrobe(wardrobe_path()); shown = _shown(w)
    poses = {name: ps.from_game(v["parts"]) for name, v in game.tables()["poses"].items()}
    base = shown["travelling"][:3]

    def cloak(cape=True, **kw):
        item = copy.deepcopy(w.items["cloak"])
        hood = next(sp for sp in item["specials"] if sp["type"] == "hood")
        hood["params"].update(kw)
        if not cape: item["specials"] = [hood]
        new = "cloak " + " ".join(f"{k}={v}" for k, v in sorted(kw.items())) + ("" if cape else " (hood alone)")
        w.items[new] = item
        return base + [(new, "shown")]

    head = dict(scale=20.0, width=22.0, z_range=(16.0, 45.0))
    notes = set()

    def tiles(worn, sex, build, head_shape, views, frame=head, pose=None, **who):
        prep, look = figure(lb.build(sex, build, head_shape), w, worn, poses.get(pose) if pose else None, **who)
        notes.update(n for n in look.notes if "edge style" not in n)
        return [mr.render(prep, y, p, **frame) for y, p in views]

    five = [(0, 8), (35, 10), (90, 8), (145, 12), (180, 8)]
    names = ["front", "turned", "side", "from behind", "back"]
    rows = []
    tl = tiles(cloak(raised=True), "female", "average", "round", five)
    rows.append(("1. Raised hood: the cloak with its hood up (female, round head)",
                 "a loose shell over the head: a brim over the brows, room at the back, the face left open, falling to a short cowl on the shoulders. Shown in green; its own colours are near-black.",
                 band(tl, names)))
    who = [("male", "average", "boxy"), ("male", "heavy", "strong"), ("female", "slim", "oval"), ("male", "short", "heart"), ("female", "heavy", "heart")]
    tl = []; lab = []
    for sex, build, shape in who:
        tl += tiles(cloak(raised=True), sex, build, shape, [(0, 8), (35, 10)]); lab += [f"{sex} {build}, {shape}: front", "turned"]
    rows.append(("2. On every build and head", "measured from each dressed head and body, so the same settings fit all of them.", band(tl, lab, gap_after=(1, 3, 5, 7))))
    tl = [tiles(cloak(raised=True, depth=d), "female", "average", "round", [(35, 10)])[0] for d in (1, 2, 3)]
    tl += [tiles(cloak(raised=True, depth=d), "female", "average", "round", [(90, 8)])[0] for d in (1, 3)]
    tl += [tiles(cloak(raised=True, opening=o), "female", "average", "round", [(0, 8)])[0] for o in (0, 1, 2, 3)]
    rows.append(("3. Settings: thickness (read here as how loose the hood is) and the face opening",
                 "thickness 1 to 3 stands the hood further off the head. The opening setting moves the edge out past the eyes, and its arch up.",
                 band(tl, ["thickness 1", "thickness 2", "thickness 3", "thickness 1: side", "thickness 3: side", "opening 0", "opening 1", "opening 2", "opening 3"], gap_after=(2, 4))))
    tl = tiles(cloak(raised=True, lined=True), "male", "average", "round", [(0, 8), (35, 10)])
    tl += tiles(cloak(raised=True), "female", "average", "round", [(145, 12)], features=[("ponytail", "default")])
    tl += tiles(cloak(raised=True), "male", "average", "round", [(0, 8)], features=[(w.facial_hair(("moustache", "goatee", "sideburns", "cheeks"), "short"), "default"), ("short_crop", "default")])
    tl += tiles(cloak(raised=True), "female", "average", "round", [(90, 8)], pose="mid_stride")
    tl += tiles(cloak(raised=True), "male", "average", "round", [(35, 10)], pose="reaching")
    tl += tiles(cloak(raised=True), "male", "average", "round", [(35, 10)], pose="arms_raised")
    rows.append(("4. Lined, over hair and a beard, and in the game's poses",
                 "lined: the inside and the edge take the lining colour. The hood stands clear of the hair under it, a ponytail's tail too (it bulges). The head part turns with the head, the cowl with the chest; a raised arm goes through the cowl.",
                 band(tl, ["lined: front", "lined: turned", "over a ponytail: behind", "over a beard", "mid-stride", "reaching", "arms raised"], gap_after=(1, 3))))
    tl = tiles(cloak(raised=False), "female", "average", "round", five)
    rows.append(("5. Lowered hood: the cloak as the wardrobe has it (hood down)",
                 "a cowl closed round the neck, and the empty hood lying on the upper back over it, its opening turned up.",
                 band(tl, names)))
    tl = tiles(cloak(raised=False, lined=True), "male", "average", "boxy", [(145, 12), (180, 8)])
    tl += tiles(cloak(raised=False, depth=3), "male", "heavy", "strong", [(145, 12)])
    tl += tiles(cloak(raised=False), "male", "short", "heart", [(145, 12)])
    tl += tiles(cloak(raised=False), "female", "average", "round", [(145, 12)], pose="mid_stride")
    tl += tiles(cloak(raised=False), "female", "average", "round", [(90, 8)], pose="mid_stride")
    rows.append(("6. Lowered: lined, loose, other builds, mid-stride",
                 "the hood lies on the chest and turns with it; the cape is laid afresh for every pose, so in a stride it swings away and the hood stays on the back.",
                 band(tl, ["lined: from behind", "lined: back", "heavy, thickness 3", "short", "mid-stride: behind", "mid-stride: side"], gap_after=(1, 3))))
    for n in sorted(notes): print("  note:", n)
    save_sheet(rows, "hood.png")


def sheet_types():
    """The shapes of their own: each type's settings, one at a time from one end to the other, on several builds and
    in the game's poses."""
    w = ld.Wardrobe(wardrobe_path())
    poses = {name: ps.from_game(v["parts"]) for name, v in game.tables()["poses"].items()}
    clothes = [("boots", "default"), ("trousers", "default"), ("tunic", "rust")]
    beard = w.facial_hair(("moustache", "sideburns", "goatee", "cheeks"), "short")
    colours = {"hair": "@hair", "tie": "rust", "horn": "bone", "plate": "slate"}

    def item(kind, **settings):
        item_id = kind + " " + " ".join(f"{k}={v}" for k, v in sorted(settings.items()))
        roles = list(dr.ROLES[kind])
        w.items[item_id] = dict(name=item_id, category="accessory", draw_order=80, edge_style="soft", mirror=True, roles=roles,
                                colourways={"default": {r: colours[r] for r in roles}}, coverage={},
                                specials=[dict(type=kind, params=dict(settings))])
        return (item_id, "default")

    notes = set()

    def tiles(kind, settings, views, frame, sex="male", build="average", shape="round", pose=None, hair=("short_crop", "default"), whiskers=False):
        features = ([hair] if hair else []) + ([(beard, "default")] if whiskers else [])
        prep, look = figure(lb.build(sex, build, shape), w, clothes + [item(kind, **settings)], poses.get(pose) if pose else None, features=features)
        notes.update(n for n in look.notes if "edge style" not in n)
        return [mr.render(prep, y, p, **frame) for y, p in views]

    tall = dict(scale=16.0, width=22.0, z_range=(8.0, 45.0))
    head = dict(scale=19.0, width=22.0, z_range=(14.0, 45.0))
    front, side, turned, behind = (0, 8), (90, 8), (35, 10), (150, 12)
    rows = []

    def row(title, sub, plan, frame, **who):
        tl = []; lab = []; gaps = []
        for label, settings, views in plan:
            tl += [t for v in views for t in tiles(kind_of[0], settings, [v], frame, **who)]
            lab += [label] + [""] * (len(views) - 1)
            gaps.append(len(tl) - 1)
        rows.append((title, sub, band(tl, lab, gap_after=tuple(gaps[:-1]))))

    kind_of = ["long_beard"]
    row("1. Long beard (under the chin), worn with a short full beard",
        "length 1 to 5, width 1 to 4, point 0 (blunt) to 3 (a point), jut 0 to 3 (how far forward). It stands clear of the chest. Defaults: length 3, width 3, point 2, jut 1.",
        [("default: front, side", {}, [front, side]), ("length 1", dict(length=1), [side]), ("length 5", dict(length=5), [side]),
         ("width 1", dict(width=1), [front]), ("width 4", dict(width=4), [front]), ("point 0", dict(point=0), [front]),
         ("point 3", dict(point=3), [front]), ("jut 0", dict(jut=0), [side]), ("jut 3", dict(jut=3), [side])], tall, whiskers=True)
    kind_of[0] = "ponytail"
    row("2. Ponytail (from the back of the head)",
        "height 0 (the nape) to 3 (the crown), length 1 to 5, thickness 1 to 3, tie on or off. It hangs clear of the back. Defaults: height 1, length 3, thickness 2, tie on.",
        [("default: side, behind", {}, [side, behind]), ("height 0", dict(height=0), [side]), ("height 3", dict(height=3), [side]),
         ("length 1", dict(length=1), [side]), ("length 5", dict(length=5), [side]), ("thickness 1", dict(thickness=1), [behind]),
         ("thickness 3", dict(thickness=3), [behind]), ("no tie", dict(tie=False), [behind])], tall, sex="female", hair=("short_crop", "black"))
    kind_of[0] = "bun"
    row("3. Bun", "position top, back or nape; size 1 to 3. Defaults: back, size 2.",
        [("top", dict(position="top"), [turned, side]), ("back", {}, [turned, side]), ("nape", dict(position="nape"), [side]),
         ("size 1", dict(size=1), [side]), ("size 3", dict(size=3), [side])], dict(scale=17.0, width=22.0, z_range=(14.0, 51.0)),
        sex="female", hair=("short_crop", "black"))
    kind_of[0] = "horns"
    row("4. Horns (a pair, from the brow)",
        "length 1 to 5, curve 0 (straight up) to 3 (swept back), spread 0 to 3, thickness 1 to 3. Defaults: length 2, curve 1, spread 1, thickness 2.",
        [("default: front, turned", {}, [front, turned]), ("length 1", dict(length=1), [front]), ("length 5", dict(length=5), [front]),
         ("curve 0", dict(curve=0), [side]), ("curve 3", dict(curve=3), [side]), ("spread 0", dict(spread=0), [front]),
         ("spread 3", dict(spread=3), [front]), ("thickness 3", dict(thickness=3), [turned])], dict(scale=17.0, width=22.0, z_range=(14.0, 50.0)), hair=None)
    kind_of[0] = "pauldrons"
    row("5. Pauldrons (a pair, on the shoulders)", "size 1 to 3, drop 0 to 3 (how far down the arm). Defaults: size 2, drop 1.",
        [("default: front, turned", {}, [front, turned]), ("size 1", dict(size=1), [front]), ("size 3", dict(size=3), [front]),
         ("drop 0", dict(drop=0), [front]), ("drop 3", dict(drop=3), [front])], tall, shape="strong", hair=None)
    tl = tiles("long_beard", {}, [turned], tall, build="heavy", shape="strong", whiskers=True)
    tl += tiles("long_beard", {}, [side], tall, sex="female", build="average", whiskers=True)
    tl += tiles("ponytail", dict(height=2, length=4), [behind], tall, sex="female", build="short", shape="heart", hair=("short_crop", "auburn"))
    tl += tiles("horns", dict(length=3, curve=2), [turned], tall, sex="female", build="slim", shape="oval", hair=None)
    tl += tiles("pauldrons", {}, [turned], tall, build="heavy", shape="boxy", hair=None)
    rows.append(("6. On other builds and heads", "every type is measured from the dressed figure it is on.",
                 band(tl, ["beard: heavy, strong head", "beard: female", "ponytail: short, heart head", "horns: slim, oval head", "pauldrons: heavy"])))
    tl = tiles("ponytail", dict(length=4), [side], tall, sex="female", pose="mid_stride", hair=("short_crop", "black"))
    tl += tiles("ponytail", dict(length=4), [behind], tall, sex="female", pose="reaching", hair=("short_crop", "black"))
    tl += tiles("long_beard", {}, [turned], tall, pose="reaching", whiskers=True)
    tl += tiles("horns", dict(length=3), [turned], tall, pose="reaching", hair=None)
    tl += tiles("pauldrons", {}, [turned], tall, shape="strong", pose="arms_raised", hair=None)
    tl += tiles("pauldrons", {}, [turned], tall, shape="strong", pose="reaching", hair=None)
    rows.append(("7. In the game's poses", "a beard, a tail, a bun and horns turn with the head. A pauldron bends between the chest and the arm: with the arm overhead it still sinks into the shoulder.",
                 band(tl, ["tail: mid-stride", "tail: reaching", "beard: reaching", "horns: reaching", "pauldrons: arms raised", "reaching"], gap_after=(1, 3))))
    for n in sorted(notes): print("  note:", n)
    save_sheet(rows, "shape_types.png")


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
    jobs = dict(look=sheet_look, male=sheet_male, builds=sheet_builds, bodies=sheet_bodies, regions=sheet_regions, joints=sheet_joints, heads=sheet_heads,
                faces=sheet_faces, beards=sheet_beards, shapes=sheet_shapes, moving=sheet_moving, hood=sheet_hood, types=sheet_types)
    if which != "all" and which not in jobs:
        sys.exit(__doc__)
    for name in (jobs if which == "all" else [which]):
        t0 = time.time(); jobs[name](); print(f"{name}: done ({time.time() - t0:.0f} s)")
