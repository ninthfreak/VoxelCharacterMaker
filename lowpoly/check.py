"""Checks for the low-poly bodies:  python3 lowpoly/check.py   (needs numpy)

1. The band table in body.py is the project's own (the "regions" block every voxel body file carries, which a Godot
   test already holds equal to core/body_layout.gd): same bands, rows, part families and trim flags.
2. Every body rebuilds cleanly: no twisted polygons, no open or doubled edges, nothing standing off the clay, all 64
   regions present, every polygon inside its own band's heights apart from the documented exceptions.
3. The joints: every corner has shares that add up to one, over known parts; standing still the bending skin is the
   body as built; in a big move nothing flies off.
4. The heads: closed, on their regions, the right size, the same layout of polygons on all five, and a flat face
   wide and tall enough for both eye boxes and the brow row.
5. The files in lowpoly/bodies/ and lowpoly/heads/ are what a rebuild gives. They are generated, not hand-edited.
"""
import json, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import body as lb, pose as ps, heads as hd

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
    bare = [dict(pts=r["pts"], src=r["pts"], rgb=(0, 0, 0), part=r["part"], piece=r["piece"]) for r in b["polys"]]
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
    expect(ok, f"{name}: geometry, regions, size, and a flat face for the eyes")
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

print("low-poly bodies and heads:", "all checks passed" if not failed else f"{len(failed)} FAILED")
sys.exit(1 if failed else 0)
