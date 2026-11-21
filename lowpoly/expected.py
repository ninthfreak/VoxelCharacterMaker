"""What the game's low-poly characters must come out as, worked out here so that Godot can be checked against it.

    python3 lowpoly/expected.py      writes tests/lowpoly_expected.json (needs the game's poses: see game.py)

The Godot side (core/lowpoly/, runtime/lowpoly_rig.gd) builds characters from the same files in assets/lowpoly/.
tests/test_lowpoly.gd builds each case below and holds every corner to the place given here, to LOWPOLY_TOLERANCE.
Godot's vectors are single precision, so the two agree to about a hundred-thousandth of a unit, not exactly.

Posed: every body standing, with the round head; and every test pose on two bodies, the feminine average and the
masculine short (the short one has its own heights and its head set lower). Each case lists the body file's
corners, then the head file's, as they stand in that pose: x across, y depth, z up, in the files' units.

Dressed (phases 2 and 4: ordinary clothing, straps, skirts and capes): the starter outfits on the feminine average
with a short crop (between them every kind of item the starter wardrobe has), the everyday outfit and the dress on
the masculine short, the overalls on the masculine heavy, bald; and test items for the settings the starter ones do not
use (two panels, every opening on either side, slant, flare, knee length, no waistband or hem trim, narrow and wide
capes, wide straps) on the other builds. Corners to a thousandth. Each case lists every polygon dress.py makes, in its
order: its corners, its colour, and the worn item that made it ("" for bare skin); then, for each test pose it is
looked at in, its hanging cloth as hang.py lays it: corners, colour, role (cloth or hem) and item. Two cases wear two
hanging items (a cape over a skirt, two skirts at once), and every case with cloth is also looked at in a pose that is
not the game's, every part turned about all three axes (TWIST, listed with the case). A test item is listed in full
with its case, so that Godot can make the same item.

Faces (phase 3: eyes, lids, brows, mouths, facial hair): six characters across the bodies, heads, lid states, mouths,
skin tones and hair, with five kinds of facial hair (none, a full beard, an Amish beard grown long, a moustache and
goatee, stubble, sideburns into the hair). Each lists the head's polygons and the face's, in dress.py's order: corners,
colour, the item that made it, and whether it is drawn in its own colour, unlit (the eye's white, pupil and lashes).
"""
import json, os, sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import body as lb, heads as hd, pose as ps, dress as ld, facial_hair as fh, game

OUT = os.path.join(os.path.dirname(HERE), "tests", "lowpoly_expected.json")
TOLERANCE = 0.001           # units: a twenty-fourth of a millimetre
POSED_BODIES = ("female_average", "male_short")


def load(path):
    with open(path) as fh:
        return json.load(fh)


def posed(body_data, head_data, parts):
    """Every corner of the body file and then of the head file, in a pose as the game writes it."""
    pivots = {k: tuple(v["pivot"]) for k, v in body_data["parts"].items()}
    T = ps.transforms(ps.from_game(parts), pivots)
    out = []
    for v, w in zip(body_data["vertices"], body_data["shares"]):
        v = np.array(v, float)
        out.append(sum(share * (T[part][0] @ v + T[part][1]) for part, share in w.items()))
    A, t = T["head"]
    for v in head_data["vertices"]:
        out.append(A @ (np.array(v, float) + np.array([0.0, 0.0, body_data["head_raise"]])) + t)
    return [[round(float(x), 4) for x in p] for p in out]


def cases(tables):
    poses = {name: v["parts"] for name, v in tables["poses"].items()}
    head = load(hd.head_path("round"))
    out = []
    for sex, build in lb.BODIES:
        body_id = f"{sex}_{build}"
        data = load(lb.body_path(sex, build))
        for pose_name in (sorted(poses) if body_id in POSED_BODIES else ["rest"]):
            out.append({"body": body_id, "head": "round", "pose": pose_name, "points": posed(data, head, poses[pose_name])})
    return out


DRESSED = [("female_average", "round", outfit, [("short_crop", "black")])
           for outfit in ("dress", "everyday", "overalls", "robe", "toga", "travelling")] + \
          [("male_short", "strong", "everyday", [("short_crop", "auburn")]), ("male_short", "strong", "dress", []),
           ("male_heavy", "boxy", "overalls", []),
           ("female_heavy", "oval", [("test_skirt_two", "default"), ("test_straps_wide", "default")], []),
           ("male_slim", "heart", [("test_wrap_two", "default"), ("test_cape_wide", "default")], [("short_crop", "black")]),
           ("female_short", "round", [("test_front_two", "default"), ("test_cape_narrow", "default")], []),
           # two hanging items: a cape over a skirt; two skirts at once (each over the one before), with straps
           ("female_slim", "oval", [("boots", "default"), ("bodice", "default"), ("skirt", "default"), ("cloak", "default")],
            [("short_crop", "auburn")]),
           ("male_average", "boxy", [("shirt", "default"), ("skirt", "default"), ("wrap_skirt", "default"), ("suspenders", "default")], [])]
CLOTH_POSES_ALL = ("female_average",)        # every test pose; the others: standing, sitting and mid stride
CLOTH_POSES = ("rest", "sitting", "mid_stride")
# Not a game pose: every part turned about all three axes, the pelvis too, so that cloth is laid over a figure turned
# every way (Godot degrees about X, Y, Z, as the game writes poses). Every case with cloth is looked at in it.
TWIST = {"pelvis": [4, 18, -5], "chest": [-12, 20, 6], "head": [5, -15, 4], "upper_arm_L": [25, 30, -35],
         "forearm_L": [40, 0, 0], "upper_arm_R": [-20, -25, 30], "forearm_R": [30, 10, 0], "thigh_L": [35, 12, 10],
         "shin_L": [-45, 0, 0], "thigh_R": [-20, -10, -8], "shin_R": [-25, 6, 0]}


def test_items(wardrobe):
    """Items for the settings the starter wardrobe does not use, made from its own skirt, cloak and suspenders."""
    import copy

    def like(item_id, kind, **params):
        it = copy.deepcopy(wardrobe.items[item_id])
        it["specials"] = [dict(type=kind, params={**next(sp for sp in it["specials"] if sp["type"] == kind)["params"], **params})]
        it["name"] = "test: " + ", ".join(f"{k} {v}" for k, v in params.items())
        return it
    return {
        "test_skirt_two": like("skirt", "skirt", panels="two", opening="none", length="to_knee", flare=3, slant=3, side="right",
                               waistband=False, hem_trim=False),
        "test_wrap_two": like("skirt", "skirt", panels="two", opening="wrap", side="right", slant=2, length="to_shin"),
        "test_front_two": like("skirt", "skirt", panels="two", opening="front", flare=0, length="to_knee"),
        "test_cape_wide": like("cloak", "cape", width="wide", length="to_waist", flare=3, hem_trim=False),
        "test_cape_narrow": like("cloak", "cape", width="narrow", length="to_ankle", flare=0),
        "test_straps_wide": like("suspenders", "straps", width=2),
    }


def figure_from_files(body_id, head_name):
    """A body dict as body.build makes it, but from the files the game reads (assets/lowpoly/), so that Python and
    Godot dress exactly the same corners."""
    sex, build = body_id.split("_")
    data = load(lb.body_path(sex, build)); head = load(hd.head_path(head_name))
    V = np.array(data["vertices"], float)
    polys = []; shares = {}

    def rec(pts, key, part, piece, hidden, at=None):
        band, side = key.split(".")[:2]
        r = dict(pts=pts, key=key, band=band, side=side, face=key.split(".")[2] if key.count(".") == 2 else "",
                 part=part, piece=piece, hidden=hidden)
        if at is not None: r["at"] = tuple(at)
        polys.append(r)

    for p in data["polygons"]:
        rec(V[p["v"]].copy(), p["region"], p["part"], p["piece"], p["hidden"])
        for k in p["v"]:
            shares[lb.share_key(p["piece"], V[k])] = data["shares"][k]
    H = np.array(head["vertices"], float) + np.array([0.0, 0.0, data["head_raise"]])
    for p in head["polygons"]:
        rec(H[p["v"]].copy(), p["region"], "head", "head", False, p["at"])
    bands = {k: (v[0], v[1], lb.BANDS[k][2], lb.BANDS[k][3]) for k, v in data["heights"].items()}
    return dict(sex=sex, build=build, polys=polys, bands=bands, shares=shares,
                pivots={k: tuple(v["pivot"]) for k, v in data["parts"].items()},
                info=dict(head=head_name, head_dz=data["head_raise"]))


def dressed(tables, wardrobe):
    import pose as ps
    poses = {name: v["parts"] for name, v in tables["poses"].items()}
    poses["twist"] = TWIST
    extra = test_items(wardrobe)
    wardrobe.items.update(extra)
    rgb = lambda c: "#%02x%02x%02x" % tuple(int(x) for x in c)
    out = []
    for body_id, head_name, outfit, features in DRESSED:
        worn = wardrobe.outfit(outfit) if isinstance(outfit, str) else outfit
        body = figure_from_files(body_id, head_name)
        look = ld.dress(body, wardrobe, worn, features=features)
        polys = [{"points": [[round(float(x), 3) for x in v] for v in q["pts"]], "colour": rgb(q["rgb"]), "by": q["by"] or ""}
                 for q in look.polys]
        cloths = {}
        game_poses = sorted(p for p in poses if p != "twist")
        for pose_name in (game_poses if body_id in CLOTH_POSES_ALL else list(CLOTH_POSES)) + ["twist"]:
            if not look.cloths:
                break
            _, laid = ps.laid(body, look, ps.from_game(poses[pose_name]))
            cloths[pose_name] = [{"points": [[round(float(x), 3) for x in v] for v in pts], "colour": rgb(cloth.colours[role]),
                                  "role": role, "by": cloth.name} for cloth, made in laid for pts, role in made]
        out.append({"body": body_id, "head": head_name, "outfit": outfit if isinstance(outfit, str) else "",
                    "worn": [[i, cw] for i, cw in worn], "items": {i: extra[i] for i, _ in worn if i in extra},
                    "hair": features[0][0] if features else "", "hair_colourway": features[0][1] if features else "",
                    "notes": look.notes, "polygons": polys, "cloths": cloths,
                    "custom_poses": {"twist": TWIST} if cloths else {}})
    return out


# (body, head, skin, eye colourway, lid state, mouth, hair, hair colourway, facial hair parts, facial hair length)
FACES = [("female_average", "round", "light", "default", "neutral", "neutral", "short_crop", "black", None, None),
         ("male_average", "strong", "tan", "default", "angry", "smile", "short_crop", "auburn", fh.PARTS, "medium"),
         ("male_short", "boxy", "brown", "default", "wink", "open", None, None, fh.PRESETS["Amish"], "long"),
         ("male_heavy", "oval", "pale", "default", "sad", "frown", "short_crop", "default", fh.PRESETS["goatee and moustache"], "short"),
         ("female_slim", "heart", "deep", "default", "blink", "neutral", None, None, fh.PARTS, "stubble"),
         ("male_slim", "round", "medium", "default", "wide_open", "smile", "short_crop", "black", ("sideburns",), "medium")]


def faces(tables, wardrobe):
    out = []
    for body_id, head_name, skin, way, lids, mouth, hair, hair_way, parts, length in FACES:
        features = [(hair, hair_way)] if hair else []
        beard = None
        if parts is not None:
            beard_id = wardrobe.facial_hair(parts, length)
            features.append((beard_id, "default"))
            beard = {"id": beard_id, "parts": list(parts), "length": length, "draw_order": wardrobe.features[beard_id][1]["draw_order"]}
        look = ld.dress(figure_from_files(body_id, head_name), wardrobe, [], skin=skin, features=features,
                        eyes=dict(eye_set="standard", colourway=way, lids=lids), mouth=mouth, special_shapes=("facial_hair",))
        polys = [{"points": [[round(float(x), 4) for x in v] for v in q["pts"]], "colour": "#%02x%02x%02x" % tuple(int(c) for c in q["rgb"]),
                  "by": q["by"] or "", "unlit": bool(q.get("unlit", False)), "piece": q["piece"]}
                 for q in look.polys if q["piece"] in ("head", "face")]
        out.append({"body": body_id, "head": head_name, "skin": skin, "eye_set": "standard", "eye_colourway": way, "lids": lids,
                    "mouth": mouth, "hair": hair or "", "hair_colourway": hair_way or "", "facial_hair": beard, "polygons": polys})
    return out


def data(tables, wardrobe=None):
    d = {"format": "lowpoly_expected", "version": 3, "tolerance": TOLERANCE,
            "note": "Generated by lowpoly/expected.py from assets/lowpoly/ and the game's test poses; regenerate rather "
                    "than hand-edit. Each case: the body file's corners, then the head file's (raised onto the neck), "
                    "posed; x across, y depth, z up.",
            "cases": cases(tables)}
    if wardrobe is not None:
        d["dressed"] = dressed(tables, wardrobe)
        d["faces"] = faces(tables, wardrobe)
    return d


if __name__ == "__main__":
    d = data(game.tables(), ld.Wardrobe(game.wardrobe_path()))
    with open(OUT, "w") as fh:
        json.dump(d, fh, separators=(",", ":"))
    print(f"{os.path.relpath(OUT)}: {len(d['cases'])} posed figures, {len(d['dressed'])} dressed, {len(d['faces'])} faces")
