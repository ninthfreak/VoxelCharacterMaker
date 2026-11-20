"""Checks for the low-poly bodies:  python3 lowpoly/check.py   (needs numpy)

1. The band table in body.py is the project's own (the "regions" block every voxel body file carries, which a Godot
   test already holds equal to core/body_layout.gd): same bands, rows, part families and trim flags.
2. Every body rebuilds cleanly: no twisted polygons, no open or doubled edges, nothing standing off the clay, all 64
   regions present, every polygon inside its own band's heights apart from the documented exceptions.
3. The joints: every corner has shares that add up to one, over known parts; standing still the bending skin is the
   body as built; in a big move nothing flies off.
4. The heads: closed, on their regions, the right size, the same layout of polygons on all five, and a flat patch
   wide and tall enough for each eye box and the brow row above it.
5. The files in lowpoly/bodies/ and lowpoly/heads/ are what a rebuild gives. They are generated, not hand-edited.
6. Clothing, with the game's own starter wardrobe and test poses (written out by dump_wardrobe.gd, so this part
   needs Godot: GODOT=/path/to/godot, or the two files already in lowpoly/_work/; without either it is skipped):
   the special shapes' settings and defaults are the game's; every starter outfit dresses both bodies; hanging cloth
   hangs to its hem when standing, and in every test pose nothing of the figure comes through it; straps lie on the
   chest with nothing coming through them.
7. Faces (also from the game's tables): every polygon of the eyes and the mouth lies on its flat patch of the face;
   in every lid state the oval eyes show what the game's own cells show at the middle of each cell; the polygons of
   an eye tile it; the mouth is clear of the eyes; facial hair is found on every head, the same on both sides, in
   the colours the game works out.
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

for sex, build_name in lb.BODIES:
    print(f"== {sex} {build_name} ==")
    b = lb.build(sex, build_name)
    ok, text = lb.check(b)
    print(text)
    expect(ok, "geometry and regions")
    n = lb.counts(b)
    n = lb.counts(b, head=False)
    expect(n == lb.counts(lb.build("female"), head=False), f"same polygon count as the other bodies ({n[0]} polygons, {n[1]} triangles, without a head)")
    b = lb.build(sex, build_name)
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
    disk = json.load(open(path)); fresh = json.loads(json.dumps(lb.to_data(b)))
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
    known = lambda note: "edge style" in note or "'hood' not built" in note      # not built yet; see the README
    chest = lambda q: q["piece"] == "skin" and q["band"] in ("waist", "belly", "lower_chest", "upper_chest", "collar", "neck")
    for sex, build_name in lb.BODIES:
        b = lb.build(sex, build_name)
        for name in sorted(w.outfits):
            look = ld.dress(b, w, w.outfit(name))
            odd = [n for n in look.notes if not known(n)]
            said = f"{sex}, '{name}'"
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
        for size in (None, 1.0):                                     # as built, and as big as the game's eye box
            for eye_set in w.eye_sets:
                for state in states + [""]:
                    flat &= all(on_face(q, bend) for q in fc.eyes(tables, w, eye_set=eye_set, lids=state, bend=bend, size=size))
        for m in fc.MOUTHS:
            flat &= all(on_face(q, bend) for q in fc.mouth(tables, m, bend=bend))
    expect(flat, f"every polygon of the eyes (all {len(states)} lid states) and of the mouth (all {len(fc.MOUTHS)}) lies on its flat patch of the face")

    inside = lambda poly, x, r: all((poly[(i + 1) % len(poly)][0] - poly[i][0]) * (r - poly[i][1]) - (poly[(i + 1) % len(poly)][1] - poly[i][1]) * (x - poly[i][0]) >= -1e-9
                                    for i in range(len(poly)))
    for eye_set, es in w.eye_sets.items():
        wrong = 0; looked = 0; torn = 0; counts = []; tris = []
        for state in states:
            count = 0; tri = 0
            for i, eye in enumerate(fc.EYES):
                numbers = tables["eyes"]["states"][state][i]
                shape = fc.shape_of(fc.drawing_of(es, eye))
                pieces = fc.drawn(shape, numbers, eye, EW, EH)
                count += len(pieces); tri += sum(len(p) - 2 for p, _ in pieces)
                theirs = {(cc, r): role for cc, r, role in tables["eyes"]["applied"][eye_set][state][eye]}
                for cc in range(EW):
                    if numbers[4] and (numbers[4] * cc) % (EW - 1): continue     # a tilted lid's edge runs through these cells' centres
                    for r in range(EH + 1):
                        looked += 1
                        wrong += fc.role_at(pieces, cc + 0.5, r + 0.5) != theirs.get((cc, r))
                # the pieces tile the eye: nowhere two of them, and no hole inside its outline
                ox, oy, oa, ob = shape["outline"]
                within = fc.oval(ox, oy, 0.97 * oa, 0.97 * ob, fc.SIDES, fc.ROUND)
                for x in np.arange(0.037, EW, 0.11):
                    for r in np.arange(-0.463, EH + 1.5, 0.11):
                        n = sum(inside(p, x, r) for p, _ in pieces)
                        torn += n > 1 or (n == 0 and inside(within, x, r))
            counts.append(count); tris.append(tri)
        expect(wrong == 0, f"eye set '{eye_set}': in every lid state the oval eyes show what the game's cells show at the middle of each cell ({looked} cells looked at)")
        expect(torn == 0, f"eye set '{eye_set}': the polygons of an eye tile it, with no overlap and no hole; "
                          f"{min(counts)} to {max(counts)} polygons ({min(tris)} to {max(tris)} triangles) for a pair of eyes")

    def overlap(a, b):                                               # two convex polygons, as (x on the head, height)
        part = [tuple(v) for v in a]
        if fc._area(b) and sum(b[i][0] * b[(i + 1) % len(b)][1] - b[(i + 1) % len(b)][0] * b[i][1] for i in range(len(b))) < 0: b = b[::-1]
        for i in range(len(b)):
            part = fc._clip(part, b[i], b[(i + 1) % len(b)], True)
            if len(part) < 3: return 0.0
        return fc._area(part)

    flat2 = lambda q: [(float(v[0]), float(v[2])) for v in q["pts"]]
    clash = 0; even = True; sizes = []
    for m in fc.MOUTHS:
        made = fc.mouth(tables, m); sizes.append(len(made))
        mids = sorted((round(float(q["pts"][:, 0].mean() - lb.CX), 6), round(float(q["pts"][:, 2].mean()), 6)) for q in made)
        even &= mids == sorted((-x, z) for x, z in mids)
        for size in (None, 1.0):
            for state in states:
                for e in fc.eyes(tables, w, lids=state, size=size):
                    clash += sum(overlap(flat2(q), flat2(e)) > 1e-9 for q in made)
    expect(clash == 0 and even, f"the mouth ({', '.join(fc.MOUTHS)}): the same on both sides, and clear of the eyes and brows in every lid state, "
                                f"even with eyes as big as the game's box; {min(sizes)} to {max(sizes)} polygons")
    tones = tables["skin_order"]
    expect(sorted(tones) == sorted(tables["skin"]) and tables["default_skin"] in tones
           and all(tuple(tables["skin"][t]["lid"]) != tuple(tables["skin"][t]["mid"]) for t in tones)
           and all(set(v["stubble"]) == set(tones) for v in tables["hair"].values()),
           f"the game's {len(tones)} skin tones: each has its own lid colour, and every hair colour gives a stubble for each")
    theirs = {e["name"]: e for e in tables["specials"]["facial_hair"]}
    expect(list(sp.FACIAL_HAIR) == theirs["style"]["options"] and sp.DEFAULTS["facial_hair"]["style"] == theirs["style"]["default"],
           "facial hair: the game's styles and default")
    heads_on = {n: lb.build("male", head=n) for n in hd.NAMES}
    brown = w.palette[tables["default_brow_hair"]]                   # what "@hair" is on a bald head
    for style in sp.FACIAL_HAIR:
        ok = True; added = []
        for n in hd.NAMES:
            plain = ld.dress(heads_on[n], w, [], skin="tan", eyes={})
            look = ld.dress(heads_on[n], w, [], skin="tan", eyes={}, features=[(style, "default")])
            stubble = tuple(tables["hair"][tables["default_brow_hair"]]["stubble"]["tan"])
            on_head = [q for q in look.polys if q["piece"] == "head"]
            left = lambda q: q["pts"][:, 0].mean() > lb.CX
            recoloured = [q for q in on_head if q["rgb"] == stubble]; raised = [q for q in on_head if q["rgb"] == brown]
            even = sum(map(left, recoloured)) * 2 == len(recoloured) and sum(map(left, raised)) * 2 == len(raised)
            ok &= not look.notes and even and (len(recoloured) > 0) == (style != "chinstrap") and (len(raised) > 0) == (style != "stubble")
            ok &= all(np.isfinite(q["pts"]).all() for q in look.polys)
            ok &= all(q["pts"][:, 2].max() <= sp.SIDEBURN_TOP + 1e-6 for q in recoloured)
            added.append(len(look.polys) - len(plain.polys))
            # with hair on, beard, stubble and brows follow it
            crop = ld.dress(heads_on[n], w, [], skin="tan", eyes={}, features=[("short_crop", "black"), (style, "default")])
            want = tuple(tables["hair"]["hair_black"]["stubble"]["tan"]) if style != "chinstrap" else w.palette["hair_black"]
            ok &= any(q["rgb"] == want for q in crop.polys if q["piece"] == "head" and q["pts"][:, 2].max() <= sp.JAW_TOP + 1.5)
            ok &= any(q["rgb"] == tuple(tables["hair"]["hair_black"]["brow"]) for q in crop.polys if q["piece"] == "face")
        expect(ok, f"facial hair '{style}': on all five heads, the same on both sides, in the colours the game works out from hair and skin; "
                   f"it adds {min(added)} to {max(added)} polygons")

print("low-poly bodies, heads, clothing and faces:", "all checks passed" if not failed else f"{len(failed)} FAILED")
sys.exit(1 if failed else 0)
