"""Review sheets for the low-poly bodies.

  python3 lowpoly/sheets.py look      the first look test: the feminine average at two polygon budgets, beside its clay
  python3 lowpoly/sheets.py male      the masculine average (budget A), beside its clay and the feminine one
  python3 lowpoly/sheets.py regions   the bodies the clothing system uses: their regions, then starter outfits
  python3 lowpoly/sheets.py all

Sheets are written to lowpoly/renders/. The clay is drawn by ray marching (about 40 s a view), so those pictures are
kept in lowpoly/_work/ and reused. "regions" needs the project's starter wardrobe as JSON
(lowpoly/_work/starter_wardrobe.json); if it is missing it is written first with dump_wardrobe.gd, which needs Godot
(GODOT=/path/to/godot, or `godot` on PATH).
"""
import os, shutil, subprocess, sys, time
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import clay, rings as ring_tools, body as lb, dress as ld, picture as mr

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


def look_test(sex, spec):
    """A look-test body (rings.py LIGHT / FULL), checked before it is drawn."""
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
    path = os.path.join(WORK, "starter_wardrobe.json")
    if not os.path.exists(path):
        godot = os.environ.get("GODOT") or shutil.which("godot")
        if not godot:
            sys.exit("needs lowpoly/_work/starter_wardrobe.json. Write it with dump_wardrobe.gd (see its first lines), or set GODOT=/path/to/godot")
        os.makedirs(WORK, exist_ok=True)
        subprocess.run([godot, "--headless", "--path", ROOT, "--script", os.path.join(HERE, "dump_wardrobe.gd"), "--", "--out", path], check=True)
    return path


# ------------------------------------------------------------------------------------------------- sheets ---

def sheet_look():
    built = {}
    for tag, spec in (("A", ring_tools.LIGHT), ("B", ring_tools.FULL)):
        parts = look_test("female", spec)
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
    fem = look_test("female", ring_tools.LIGHT); masc = look_test("male", ring_tools.LIGHT_MASC)
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
    n = lb.counts(bodies["female"])
    tl = []; lab = []
    for sex in ("female", "male"):
        groups, _ = ld.dress(bodies[sex], w, [], paint=region_paint())
        prep = mr.prepare_coloured(groups)
        front = mr.render(prep, 0, 0, scale=S, mode="lines", z_range=ZR)
        tl += [labelled(front, S, ZR) if sex == "female" else front] + [mr.render(prep, y, 0, scale=S, mode="lines", z_range=ZR) for y in (90, 180)]
        lab += [f"{sex}: front", f"{sex}: side", f"{sex}: back"]
    rows = [("1. The clothing regions, on both bodies",
             f"the same 32 regions a side as the voxel bodies, at the same heights. Bands alternate blue and orange; one-row trim bands are pale; back regions are darker. "
             f"Every polygon is in exactly one region. Each body is {n[0]} polygons.",
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
            groups, notes = ld.dress(bodies[sex], w, worn)
            prep = mr.prepare_coloured(groups)
            tl += [mr.render(prep, y, p, scale=S, z_range=ZR) for y, p in ((0, 12), (35, 15), (180, 12))]
            lab += [f"{sex}: front", f"{sex}: turned", f"{sex}: back"]
        if notes: print(" ", title, "|", "; ".join(notes))
        rows.append((title, sub, band(tl, lab, gap_after=(2,))))
    save_sheet(rows, "regions_and_outfits.png")


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    jobs = dict(look=sheet_look, male=sheet_male, regions=sheet_regions)
    if which != "all" and which not in jobs:
        sys.exit(__doc__)
    for name in (jobs if which == "all" else [which]):
        t0 = time.time(); jobs[name](); print(f"{name}: done ({time.time() - t0:.0f} s)")
