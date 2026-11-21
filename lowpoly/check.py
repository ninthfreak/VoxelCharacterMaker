"""Checks for the low-poly bodies:  python3 lowpoly/check.py   (needs numpy)

1. The band table in body.py is the project's own (the "regions" block every voxel body file carries, which a Godot
   test already holds equal to core/body_layout.gd): same bands, rows, part families and trim flags.
2. Every body rebuilds cleanly: no twisted polygons, no open or doubled edges, nothing standing off the clay, all 64
   regions present, every polygon inside its own band's heights apart from the documented exceptions. All eight
   (slim, average, heavy, short, for each sex) have the same corners in the same order and the same polygons,
   regions, parts and joint shares: each is the female average with its corners moved. Each has the same bands, each
   on the one below, at the voxel rows' heights or (short) at its own; the head sits on the neck; the crotch stands
   clear above the ring at the bottom of the upper thigh; the side seam lies within half a unit of each torso ring's
   centre depth.
3. The joints: every corner has shares that add up to one, over known parts; standing still the bending skin is the
   body as built; in a big move nothing flies off.
4. The heads: closed, on their regions, the right size, the same layout of polygons on all five, and a flat patch
   wide and tall enough for each eye box and the brow row above it.
5. The files in assets/lowpoly/ (and the OBJ copies in lowpoly/bodies/ and lowpoly/heads/) are what a rebuild gives,
   and so is tests/lowpoly_expected.json, which the Godot tests hold the game's posed figures to. They are generated,
   not hand-edited.
6. Clothing, with the game's own starter wardrobe and test poses (written out by dump_wardrobe.gd, so this part
   needs Godot: GODOT=/path/to/godot, or the two files already in lowpoly/_work/; without either it is skipped):
   the special shapes' settings and defaults are the game's; every starter outfit dresses all eight bodies; hanging cloth
   hangs to its hem when standing, and in every test pose nothing of the figure comes through it; straps lie on the
   chest with nothing coming through them.
7. Faces (also from the game's tables): every polygon of the eyes and the mouth lies on its flat patch of the face;
   in every lid state the lids and the pupil of the oval eyes are where the game's own cells have them; the
   polygons of an eye and its brow tile; the lash line stays inside the eye; the mouth is clear of the eyes and
   brows.
8. Facial hair (four parts, each on or off, and one length): the game's three styles read as parts and a length;
   every way of putting the parts together leaves every head one closed surface; each part covers only its own
   area, is the same on both sides, in the colours the game works out, and under the eyes; stubble and short lie
   flush, medium and long stand out by exactly their bulk; the moustache is clear of the eyes and hangs over the mouth.
   On a short body the head, the face and the facial hair are the average's, moved down with the head.
"""
import json, os, shutil, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import body as lb, pose as ps, heads as hd, dress as ld, specials as sp, hang, game

failed = []


def expect(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok: failed.append(what)


print("== band table ==")
voxel = json.load(open(os.path.join(HERE, "..", "assets", "body42_female_average_parts.json")))["regions"]
ours = {k: {"z0": v[0], "z1": v[1] - 1, "part": v[2], "trim": v[3]} for k, v in lb.BANDS.items()}
expect(ours == voxel, f"{len(ours)} bands match the voxel bodies' region table")

import clay
layout_of = lambda data: ([(p["v"], p["region"], p["part"], p["piece"], p["hidden"]) for p in data["polygons"]], data["shares"])
averages = {}
for sex, build_name in lb.BODIES:
    print(f"== {sex} {build_name} ==")
    b = lb.build(sex, build_name)
    ok, text = lb.check(b)
    print(text)
    expect(ok, "geometry and regions")
    fresh = json.loads(json.dumps(lb.to_data(b)))
    n = lb.counts(b, head=False)
    if build_name == "average":
        averages[sex] = fresh
        if sex != "female":
            mine, theirs = averages["female"], fresh
            expect(len(theirs["vertices"]) == len(mine["vertices"]) and layout_of(theirs) == layout_of(mine),
                   f"the same corners, polygons, regions, parts and joint shares as the female average ({n[0]} polygons, {n[1]} triangles, without a head)")
    else:
        mine, theirs = averages[sex], fresh
        expect(len(theirs["vertices"]) == len(mine["vertices"]) and layout_of(theirs) == layout_of(mine),
               f"the {sex} average with its corners moved: the same {len(mine['vertices'])} corners in the same order, and the same polygons, "
               f"regions, parts and joint shares")
    bands = b["bands"]; heights = clay.HEIGHTS.get((sex, build_name))
    chain = [name for name, _, _ in clay.BAND_HEIGHTS]
    stacked = all(abs(bands[lo][1] - bands[hi][0]) < 1e-9 for lo, hi in zip(chain[:-1], chain[1:])) and all(v[0] < v[1] for v in bands.values())
    own = all(abs(bands[name][0] - z0) < 1e-9 and abs(bands[name][1] - z1) < 1e-9 for name, z0, z1 in heights) if heights else \
        all(tuple(bands[k][:2]) == tuple(v[:2]) for k, v in lb.BANDS.items())
    head_low = min(float(r["pts"][:, 2].min()) for r in b["polys"] if r["piece"] == "head")
    expect(stacked and own and abs(head_low - bands["neck"][1]) < 1e-6,
           (f"the same bands at its own heights ({bands['neck'][1]:.2f} to the top of the neck, against 26), each on the one below"
            if heights else "the bands at the voxel rows' heights") + f"; the head sits on the neck ({head_low:.2f})")
    gap = b["info"]["crotch"][1] - bands["upper_thigh"][0]
    expect(gap >= 0.25, f"the crotch is {gap:.2f} above the thigh's ring at the bottom of the upper thigh (at least 0.25)")
    seam = 0.0                                                       # each torso ring's side corner, against the ring's centre depth
    spec = lb.BODIES[(sex, build_name)]
    for z0, yc in spec["torso"][1:]:
        z = spec["heights"](z0)
        ring = np.array([v for r in b["polys"] if r["piece"] == "skin" for v in r["pts"] if abs(v[2] - z) < 1e-6 and v[0] > lb.CX])
        seam = max(seam, abs(ring[np.argmax(ring[:, 0])][1] - (lb.CY + yc)))
    expect(seam <= 0.5, f"the side seam lies within half a unit of each torso ring's centre depth (furthest: {seam:.2f})")
    bare = [dict(pts=r["pts"], rgb=(0, 0, 0), part=r["part"], piece=r["piece"],
                 shares=[b["shares"][lb.share_key(r["piece"], v)] for v in r["pts"]]) for r in b["polys"]]
    still = ps.posed_bend(b, bare, ps.REST)
    expect(all(np.allclose(p, q["pts"]) for (p, _), q in zip(still, bare)), "standing still, the bending skin is the body as built")
    moved = ps.posed_bend(b, bare, ps.BIG)
    whole = all(np.isfinite(p).all() for p, _ in moved)
    stretch = max(float(np.linalg.norm(p[i] - p[(i + 1) % len(p)])) for p, _ in moved for i in range(len(p)))
    expect(whole and stretch < 9.0, f"posed in a big move, no corner flies off (longest edge {stretch:.1f} units)")
    path = lb.body_path(sex, build_name)
    if not os.path.exists(path):
        expect(False, f"{os.path.relpath(path, HERE)} exists (run: python3 lowpoly/body.py)")
        continue
    disk = json.load(open(path))
    same_shape = np.array(disk["vertices"]).shape == np.array(fresh["vertices"]).shape
    close = same_shape and bool(np.allclose(np.array(disk["vertices"]), np.array(fresh["vertices"]), atol=2e-4))
    rest = all(disk[k] == fresh[k] for k in fresh if k != "vertices")
    expect(close and rest, f"{os.path.relpath(path, HERE)} is what a rebuild gives")

print("== heads ==")
layout = None
for name in hd.NAMES:
    polys = hd.build(name)
    ok, text = hd.check(name, polys)
    print(text)
    expect(ok, f"{name}: geometry, regions, size, and a flat patch for each eye")
    shape = [(len(r["pts"]), r["key"]) for r in polys]
    layout = layout or shape
    expect(shape == layout, f"{name}: the same layout of polygons and regions as the other heads")
    path = hd.head_path(name)
    if not os.path.exists(path):
        expect(False, f"{os.path.relpath(path, HERE)} exists (run: python3 lowpoly/heads.py)")
        continue
    disk = json.load(open(path)); fresh = json.loads(json.dumps(hd.to_data(name, polys)))
    close = np.array(disk["vertices"]).shape == np.array(fresh["vertices"]).shape and bool(np.allclose(np.array(disk["vertices"]), np.array(fresh["vertices"]), atol=2e-4))
    expect(close and all(disk[k] == fresh[k] for k in fresh if k != "vertices"), f"{os.path.relpath(path, HERE)} is what a rebuild gives")

THROUGH = 0.15      # how far a corner of the figure may come through hanging cloth: 0.15 units is 6 mm, at a hem's edge

print("== clothing ==")
if not game.available():
    print("  skipped: needs the game's wardrobe and poses (set GODOT=/path/to/godot)")
else:
    have_godot = bool(os.environ.get("GODOT") or shutil.which("godot"))
    tables = game.tables(fresh=have_godot)                           # fresh from the game whenever Godot is here
    w = ld.Wardrobe(game.wardrobe_path())
    for kind, ours in sp.DEFAULTS.items():
        theirs = {e["name"]: e["default"] for e in tables["specials"][kind]}
        expect(ours == theirs, f"{kind}: the same settings and defaults as the game's")
    options = lambda kind, name: next(e["options"] for e in tables["specials"][kind] if e["name"] == name)
    expect(list(sp.SKIRT_LENGTH) == options("skirt", "length") and list(sp.CAPE_LENGTH) == options("cape", "length")
           and list(sp.CAPE_WIDTH) == options("cape", "width"), "skirt and cape lengths and widths: the game's options")
    poses = {name: ps.from_game(v["parts"]) for name, v in tables["poses"].items()}
    import expected                                                  # what the Godot side is checked against
    on_disk = json.load(open(expected.OUT)) if os.path.exists(expected.OUT) else {}
    fresh = json.loads(json.dumps(expected.data(tables, ld.Wardrobe(game.wardrobe_path()))))
    expect(all(on_disk.get(k) == fresh[k] for k in ("cases", "dressed", "tolerance")),
           f"tests/lowpoly_expected.json ({len(fresh['cases'])} posed figures and {len(fresh['dressed'])} dressed ones, for the Godot tests) "
           f"is what a rebuild gives (run: python3 lowpoly/expected.py)")
    known = lambda note: "edge style" in note or "'hood' not built" in note      # not built yet; see the README
    chest = lambda q: q["piece"] == "skin" and q["band"] in ("waist", "belly", "lower_chest", "upper_chest", "collar", "neck")

    def dressed(which):
        """Every starter outfit on one body, in every test pose: [(ok, what)]. Run for the eight bodies side by side."""
        sex, build_name = which
        out = []; expect = lambda ok, what: out.append((bool(ok), what))
        b = lb.build(sex, build_name)
        for name in sorted(w.outfits):
            look = ld.dress(b, w, w.outfit(name))
            odd = [n for n in look.notes if not known(n)]
            said = f"{sex} {build_name}, '{name}'"
            parent = None; inward = 0; hems = 0                     # every hem faces out over its step
            for q in look.polys:
                if not q.get("hem"):
                    parent = q; continue
                n = sum(np.cross(q["pts"][i], q["pts"][(i + 1) % len(q["pts"])]) for i in range(len(q["pts"])))
                if np.linalg.norm(n) < 1e-9: continue
                hems += 1; inward += int(n @ (q["pts"].mean(axis=0) - parent["pts"].mean(axis=0)) <= 0)
            expect(inward == 0, f"{said}: all {hems} hems face out over their step, away from the garment they edge")
            hems = True; worst = 0.0; longest = 0.0; whole = True
            for pose_name, pose in poses.items():
                bent, cloths = ps.laid(b, look, pose)
                whole &= all(np.isfinite(pts).all() for _, pts in bent)
                T = ps.transforms(pose, b["pivots"])
                for cloth, made in cloths:
                    polys = [p for p, _ in made]
                    whole &= all(np.isfinite(p).all() for p in polys)
                    longest = max([longest] + [float(np.linalg.norm(p[i] - p[(i + 1) % len(p)])) for p in polys for i in range(len(p))])
                    seen = [pts for q, pts in bent if cloth.over(q) and not q["hidden"] and not (cloth.facing is not None and q["piece"].startswith("arm"))]
                    P = np.concatenate(seen) if seen else np.zeros((0, 3))
                    if cloth.facing is None: worst = max(worst, hang.through(polys, P, axis=(lb.CX, lb.CY)))
                    else: worst = max(worst, hang.through(polys, P, facing=T[cloth.frame][0] @ np.array(cloth.facing)))
                    if pose_name == "rest":
                        P0 = np.concatenate([q["pts"] for q in look.polys if cloth.over(q)])
                        hems &= all(abs(end[2] - col.hem) < 1e-6 for end, col in zip(hang.ends(cloth, T, P0, P0[:, 2]), cloth.columns))
            n_cloth = sum(len(made) for _, made in ps.laid(b, look, {})[1])
            if look.cloths:
                expect(not odd and whole and hems and worst < THROUGH and longest < 16.0,
                       f"{said}: {len(look.polys) + n_cloth} polygons, {n_cloth} of them hanging cloth; it hangs to its hem; in the {len(poses)} test poses "
                       f"nothing comes through it by {THROUGH} units or more (most: {worst:.2f})" + (f" | NOTES: {odd}" if odd else ""))
            else:
                expect(not odd and whole, f"{said}: {len(look.polys)} polygons" + (f" | NOTES: {odd}" if odd else ""))
            straps = [q for q in look.polys if q["piece"] == "shape:straps"]
            if any(e["item"] == "suspenders" for e in w.outfits[name]):
                tris = np.array([q["pts"][[0, i, i + 1]] for q in look.polys if chest(q) for i in range(1, len(q["pts"]) - 1)])
                rise = 0.0; sides = set()
                for q in straps:
                    p = q["pts"]; n = np.zeros(3)
                    for i in range(len(p)):
                        n += np.cross(p[i], p[(i + 1) % len(p)])
                    centre = p.mean(axis=0); sides.add(bool(centre[0] > lb.CX))
                    probe = np.array([centre] + [centre + 0.8 * (v - centre) for v in p])
                    rise = max(rise, float(sp._above(probe, hang.unit(n), tris).max()))
                expect(len(straps) > 0 and sides == {True, False} and rise == 0.0,
                       f"{said}: two straps ({len(straps)} polygons), with nothing of the chest coming through them")
        return out

    import multiprocessing
    with multiprocessing.Pool(4) as pool:                          # the eight bodies side by side: a quarter of the time
        for results in pool.map(dressed, list(lb.BODIES)):
            for ok, what in results: expect(ok, what)

    # ---- faces: the eyes in every lid state, against the game's own cells; and the mouth
    print("== faces ==")
    import faces as fc
    box = tables["eyes"]["box"]; EW, EH = int(box["w"]), int(box["h"])
    states = tables["eyes"]["order"]

    def on_face(q, bend):
        p = q["pts"]
        return bool(np.allclose(p[:, 1], [hd.face_y(v, bend) - fc.LIFT for v in p[:, 0]], atol=1e-9)
                    and np.abs(p[:, 0] - lb.CX).max() <= hd.FACE_HALF_WIDTH + 1e-6
                    and p[:, 2].min() >= hd.BELT[0] - 1e-6 and p[:, 2].max() <= hd.BELT[1] + 1e-6)

    flat = True
    for bend in (None, 0.0):                                         # the heads' own two patches, and one flat face
        for eye_set in w.eye_sets:
            for state in states + [""]:
                flat &= all(on_face(q, bend) for q in fc.eyes(tables, w, eye_set=eye_set, lids=state, bend=bend))
        for m in fc.MOUTHS:
            flat &= all(on_face(q, bend) for q in fc.mouth(tables, m, bend=bend))
    expect(flat, f"every polygon of the eyes and brows (all {len(states)} lid states) and of the mouth (all {len(fc.MOUTHS)}) lies on its flat patch of the face")

    inside = lambda poly, x, r: all((poly[(i + 1) % len(poly)][0] - poly[i][0]) * (r - poly[i][1]) - (poly[(i + 1) % len(poly)][1] - poly[i][1]) * (x - poly[i][0]) >= -1e-9
                                    for i in range(len(poly)))
    open_eye = ("white", "pupil")
    for eye_set, es in w.eye_sets.items():
        wrong = 0; looked = 0; torn = 0; astray = 0; hidden = 0; counts = []; tris = []
        for state in states:
            count = 0; tri = 0
            for i, eye in enumerate(fc.EYES):
                numbers = tables["eyes"]["states"][state][i]
                shape = fc.shape_of(fc.drawing_of(es, eye))
                bare = fc.drawn(shape, numbers, eye, EW, EH)
                pieces = fc.with_brow(bare, fc.brow_of(numbers, EW, EH))
                count += len(pieces); tri += sum(len(p) - 2 for p, _ in pieces)
                # the lids and the pupil are where the game has them. The game's one thick bar is not drawn here: where
                # it lies on the eye it is lid, and the lash line is the top edge of the open eye instead.
                theirs = {(cc, r): role for cc, r, role in tables["eyes"]["applied"][eye_set][state][eye]}
                for cc in range(EW):
                    if numbers[4] and (numbers[4] * cc) % (EW - 1): continue     # a tilted lid's edge runs through these cells' centres
                    for r in range(EH):
                        looked += 1
                        mine = fc.role_at(pieces, cc + 0.5, r + 0.5); game = theirs.get((cc, r))
                        if game in open_eye:
                            top_edge = theirs.get((cc, r + 1)) not in open_eye
                            wrong += not (mine == game or (mine == "line" and top_edge))
                        elif game == "lid":
                            wrong += mine not in ("lid", "brow")
                        else:                                         # the game's bar, or nothing: here lid, brow or bare face
                            wrong += mine not in (("lid", "brow", None) if game == "brow" else ("brow", None))
                # the pieces tile the face round the eye: nowhere two of them, and no hole inside the eye's outline
                ox, oy, oa, ob = shape["outline"]
                outline = fc.oval(ox, oy, oa, ob, fc.SIDES, fc.ROUND)
                within = fc.oval(ox, oy, 0.97 * oa, 0.97 * ob, fc.SIDES, fc.ROUND)
                for x in np.arange(0.037, EW, 0.11):
                    for r in np.arange(-0.463, EH + 2.0, 0.11):
                        n = sum(inside(p, x, r) for p, _ in pieces)
                        torn += n > 1 or (n == 0 and inside(within, x, r))
                # the lash line stays inside the eye, and the brow hides none of the open eye
                astray += sum(not inside(outline, x, r) for p, role in pieces if role == "line" for x, r in p)
                area = lambda made: sum(fc._area(p) for p, role in made if role in open_eye + ("line",))
                hidden += abs(area(pieces) - area(bare)) > 1e-6
            counts.append(count); tris.append(tri)
        expect(wrong == 0, f"eye set '{eye_set}': in every lid state the lids and the pupil are where the game's cells have them, at the middle of each cell ({looked} cells looked at)")
        expect(torn == 0, f"eye set '{eye_set}': the polygons of an eye and its brow tile, with no overlap and no hole; "
                          f"{min(counts)} to {max(counts)} polygons ({min(tris)} to {max(tris)} triangles) for a pair")
        expect(astray == 0 and hidden == 0, f"eye set '{eye_set}': the lash line never leaves the eye, and the brow never hides any of the open eye")

    def overlap(a, b):                                               # two convex polygons, as (x on the head, height)
        part = [tuple(v) for v in a]
        if fc._area(b) and sum(b[i][0] * b[(i + 1) % len(b)][1] - b[(i + 1) % len(b)][0] * b[i][1] for i in range(len(b))) < 0: b = b[::-1]
        for i in range(len(b)):
            part = fc._clip(part, b[i], b[(i + 1) % len(b)], True)
            if len(part) < 3: return 0.0
        return fc._area(part)

    flat2 = lambda q: [(float(v[0]), float(v[2])) for v in q["pts"]]
    clash = 0; even = True; sizes = []; low = 99.0
    for m in fc.MOUTHS:
        made = fc.mouth(tables, m); sizes.append(len(made))
        mids = sorted((round(float(q["pts"][:, 0].mean() - lb.CX), 6), round(float(q["pts"][:, 2].mean()), 6)) for q in made)
        even &= mids == sorted((-x, z) for x, z in mids)
        low = min(low, min(float(q["pts"][:, 2].min()) for q in made))
        for state in states:
            for e in fc.eyes(tables, w, lids=state):
                clash += sum(overlap(flat2(q), flat2(e)) > 1e-9 for q in made)
    room = min(float(e["pts"][:, 2].min()) for state in states for e in fc.eyes(tables, w, lids=state)) - (fc.MOUTH_Z + 0.5 * fc.MOUTH_THICK)
    expect(clash == 0 and even, f"the mouth ({', '.join(fc.MOUTHS)}): the same on both sides, and clear of the eyes and brows in every lid state; "
                                f"{min(sizes)} to {max(sizes)} polygons")
    expect(low >= hd.BELT[0] + 0.05 and room >= 0.5, f"the mouth is on the flat part of the face (its lowest point {low - hd.BELT[0]:.2f} above the jaw), "
                                                    f"with {room:.2f} between a straight mouth and the bottoms of the eyes for a moustache")
    tones = tables["skin_order"]
    expect(sorted(tones) == sorted(tables["skin"]) and tables["default_skin"] in tones
           and all(tuple(tables["skin"][t]["lid"]) != tuple(tables["skin"][t]["mid"]) for t in tones)
           and all(set(v["stubble"]) == set(tones) for v in tables["hair"].values()),
           f"the game's {len(tones)} skin tones: each has its own lid colour, and every hair colour gives a stubble for each")
    # ---- facial hair: four parts, each on or off, and one length (facial_hair.py)
    print("== facial hair ==")
    import itertools, facial_hair as fh
    theirs = {e["name"]: e for e in tables["specials"]["facial_hair"]}
    expect(sorted(fh.GAME_STYLES) == sorted(theirs["style"]["options"]) and sp.DEFAULTS["facial_hair"]["style"] == theirs["style"]["default"],
           f"the game's {len(fh.GAME_STYLES)} facial hair styles each read as parts and a length; its default is the game's")
    heads_on = {n: lb.build("male", head=n) for n in hd.NAMES}
    area3 = lambda p: 0.5 * float(np.linalg.norm(sum(np.cross(p[i], p[(i + 1) % len(p)]) for i in range(len(p)))))
    combos = [c for k in range(1, len(fh.PARTS) + 1) for c in itertools.combinations(fh.PARTS, k)]
    sound = True; added = []
    for n in hd.NAMES:
        mine = [r for r in heads_on[n]["polys"] if r["piece"] == "head"]
        before = sum(area3(r["pts"]) for r in mine)
        for hair in (False, True):
            for parts in combos:
                cut = [r for r in fh.on_head(heads_on[n]["polys"], parts, "short", dict(hair=(1, 2, 3), stubble=(4, 5, 6)), 65, n, hair) if r["piece"] == "head"]
                edges = {}
                for r in cut:
                    p = r["pts"]
                    for i in range(len(p)):
                        sound &= bool(np.linalg.norm(p[i] - p[i - 1]) > 1e-6)
                        k = frozenset((tuple(np.round(p[i], 4)), tuple(np.round(p[(i + 1) % len(p)], 4))))
                        edges[k] = edges.get(k, 0) + 1
                after = sum(area3(r["pts"]) for r in cut)                # not exact: some of the head's polygons are not flat
                sound &= all(v == 2 for v in edges.values()) and abs(after - before) < 0.001 * before
                added.append(len(cut) - len(mine))
    expect(sound, f"all {len(combos)} ways of putting the parts together, cut into all five heads, bald and with hair, leave the head one closed surface "
                  f"(every edge shared by two polygons); they add {min(added)} to {max(added)} polygons to the head")

    eye_shapes = [flat2(e) for state in states for e in fc.eyes(tables, w, lids=state)]
    eye_shapes = [(min(x for x, _ in e), max(x for x, _ in e), min(z for _, z in e), e) for e in eye_shapes]

    def meets_eyes(poly):
        x0, x1, z1 = min(x for x, _ in poly), max(x for x, _ in poly), max(z for _, z in poly)
        return any(overlap(poly, e) > 1e-9 for ex0, ex1, ez0, e in eye_shapes if z1 > ez0 and x1 > ex0 and x0 < ex1)
    where = {                                                        # where each part's polygons may be, by the head's own corners
        "moustache": lambda x, z: abs(x) <= fh.MOUSTACHE[-1][0] + 1e-6 and fh.MOUSTACHE[-1][1] - 1e-6 <= z <= fh.MOUSTACHE[0][2] + 1e-6,
        "goatee": lambda x, z: abs(x) <= fh.GOATEE_HALF[0] + 0.05 and z <= fh.MOUTH_FLOOR + 1e-6,
        "sideburns": lambda x, z: abs(x) >= hd.FACE_HALF_WIDTH and z >= fh.SIDEBURN_FOOT - 1e-6,
        "cheeks": lambda x, z: z <= fh.SIDEBURN_FOOT + 1e-6 and (abs(x) >= fh.MOUTH_ROOM - 1e-6 or z <= hd.BELT[0] + 1e-6),
    }
    placed = True; even = True; coloured = True; flush = True; grown = True; quiet = True
    for n in hd.NAMES:
        for hair in (None, "hair_black"):
            crop = [("short_crop", "black")] if hair else []
            top = hd.BELT[1] if hair else fh.EAR_TOP                    # the sideburns end at the hair, or at the top of the ear
            for parts in [(p,) for p in fh.PARTS] + [fh.PARTS]:
                for length in fh.LENGTHS:
                    item = w.facial_hair(parts, length)
                    look = ld.dress(heads_on[n], w, [], skin="tan", eyes={}, mouth="neutral", features=crop + [(item, "default")])
                    quiet &= not look.notes
                    want = tuple(tables["hair"][hair or tables["default_brow_hair"]]["stubble"]["tan"]) if length == "stubble" else w.palette[hair or tables["default_brow_hair"]]
                    beard = [q for q in look.polys if q.get("by") == item]
                    coloured &= all(q["rgb"] == want for q in beard)
                    placed &= all(q["src"][:, 2].max() <= top + 1e-6 for q in beard)
                    left = [q for q in beard if q["src"][:, 0].mean() > lb.CX]
                    even &= len(beard) > 0 and len(left) * 2 == len(beard) and abs(sum(area3(q["pts"]) for q in left) * 2 - sum(area3(q["pts"]) for q in beard)) < 1e-6
                    coloured &= any(q["rgb"] == tuple(tables["hair"][hair or tables["default_brow_hair"]]["brow"]) for q in look.polys if q["piece"] == "face")
                    if len(parts) == 1:
                        placed &= all(where[parts[0]](v[0] - lb.CX, v[2]) for q in beard for v in q["src"])
                    moved = max(float(np.linalg.norm(q["pts"] - q["src"], axis=1).max()) for q in beard)
                    if fh.LENGTHS[length] == 0: flush &= moved < 1e-9
                    else: grown &= abs(moved - fh.LENGTHS[length] * ld.BULK_UNIT) < 1e-6
                    on_flat = [q for q in beard if np.allclose(q["src"][:, 1], [hd.face_y(v) for v in q["src"][:, 0]], atol=1e-6)]
                    placed &= not any(meets_eyes([(float(v[0]), float(v[2])) for v in q["src"]]) for q in on_flat)
    expect(quiet and even and coloured, "facial hair on all five heads, bald and with hair, at every length: the same on both sides, in the colours the game works out "
                                        "from hair and skin (stubble for stubble, the hair's colour otherwise), with the brows still following the hair")
    expect(placed, "each part covers only its own area, no higher than the hair (or the top of the ear, bald), and nothing on the flat of the face reaches the eyes in any lid state")
    expect(flush and grown, f"stubble and short lie flush with the face; medium and long stand out by exactly {fh.LENGTHS['medium']:g} and {fh.LENGTHS['long']:g} steps of bulk")

    cover = [[(lb.CX + u, z) for u, z in c] for c in fh.cover()]
    mids = sorted((round(float(np.mean([x for x, _ in c])) - lb.CX, 6), round(float(np.mean([z for _, z in c])), 6)) for c in cover)
    symmetric = mids == sorted((-u, z) for u, z in mids)
    clash = sum(overlap(c, flat2(e)) > 1e-9 for state in states for e in fc.eyes(tables, w, lids=state) for c in cover)
    under = 0; whole = True
    for m in fc.MOUTHS:
        hidden = fc.lower_face(tables, m, cover=fh.cover())
        under += sum(overlap(flat2(q), c) > 1e-9 for q in hidden for c in cover)
        whole &= len(fc.lower_face(tables, m)) == len(fc.mouth_shape(m))
    expect(symmetric and clash == 0 and under == 0 and whole, "the moustache is the same on both sides and clear of the eyes in every lid state; "
                                                              "once it is more than stubble the mouth is cut where it hangs over it, and under stubble the mouth is whole")

    # ---- the short bodies: the head sits lower, and the face and facial hair go with it
    beard = w.facial_hair(fh.PARTS, "medium")
    for sex in ("female", "male"):
        made = {}
        for build_name in ("average", "short"):
            b = lb.build(sex, build_name, head="strong")
            look = ld.dress(b, w, [], skin="tan", eyes={}, mouth="smile", features=[("short_crop", "black"), (beard, "default")])
            made[build_name] = ([q for q in look.polys if q["piece"] in ("head", "face")], b["info"]["head_dz"], look.notes)
        (a, _, notes_a), (s, dz, notes_s) = made["average"], made["short"]
        same = len(a) == len(s) and all(p["rgb"] == q["rgb"] and np.allclose(p["pts"] + np.array([0.0, 0.0, dz]), q["pts"], atol=1e-9) for p, q in zip(a, s))
        expect(same and not notes_a and not notes_s and dz < 0, f"{sex} short: the head, the eyes and mouth, and a full beard are the average's, {-dz:.2f} lower ({len(s)} polygons)")

print("low-poly bodies, heads, clothing, faces and facial hair:", "all checks passed" if not failed else f"{len(failed)} FAILED")
sys.exit(1 if failed else 0)
