"""What the game's low-poly characters must come out as, worked out here so that Godot can be checked against it.

    python3 lowpoly/expected.py      writes tests/lowpoly_expected.json (needs the game's poses: see game.py)

The Godot side (core/lowpoly/, runtime/lowpoly_rig.gd) builds characters from the same files in assets/lowpoly/.
tests/test_lowpoly.gd builds each case below and holds every corner to the place given here, to LOWPOLY_TOLERANCE.
Godot's vectors are single precision, so the two agree to about a hundred-thousandth of a unit, not exactly.

Posed: every body standing, with the round head; and every test pose on two bodies, the feminine average and the
masculine short (the short one has its own heights and its head set lower). Each case lists the body file's
corners, then the head file's, as they stand in that pose: x across, y depth, z up, in the files' units.

Dressed (phase 2: ordinary clothing, no special shapes yet): five starter outfits on the feminine average with a
short crop (between them every kind of item the starter wardrobe has, the one-shouldered top among them), the
everyday outfit on the masculine short, and the overalls on the masculine heavy, bald. Corners to a thousandth. Each case
lists every polygon dress.py makes, in its order: its corners, its colour, and the worn item that made it ("" for
bare skin).

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
           for outfit in ("dress", "everyday", "overalls", "robe", "toga")] + \
          [("male_short", "strong", "everyday", [("short_crop", "auburn")]), ("male_heavy", "boxy", "overalls", [])]


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


def dressed(wardrobe):
    out = []
    for body_id, head_name, outfit, features in DRESSED:
        look = ld.dress(figure_from_files(body_id, head_name), wardrobe, wardrobe.outfit(outfit), features=features, special_shapes=False)
        polys = [{"points": [[round(float(x), 3) for x in v] for v in q["pts"]],
                  "colour": "#%02x%02x%02x" % tuple(int(c) for c in q["rgb"]), "by": q["by"] or ""} for q in look.polys]
        out.append({"body": body_id, "head": head_name, "outfit": outfit, "hair": features[0][0] if features else "",
                    "hair_colourway": features[0][1] if features else "", "polygons": polys})
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
    d = {"format": "lowpoly_expected", "version": 2, "tolerance": TOLERANCE,
            "note": "Generated by lowpoly/expected.py from assets/lowpoly/ and the game's test poses; regenerate rather "
                    "than hand-edit. Each case: the body file's corners, then the head file's (raised onto the neck), "
                    "posed; x across, y depth, z up.",
            "cases": cases(tables)}
    if wardrobe is not None:
        d["dressed"] = dressed(wardrobe)
        d["faces"] = faces(tables, wardrobe)
    return d


if __name__ == "__main__":
    d = data(game.tables(), ld.Wardrobe(game.wardrobe_path()))
    with open(OUT, "w") as fh:
        json.dump(d, fh, separators=(",", ":"))
    print(f"{os.path.relpath(OUT)}: {len(d['cases'])} posed figures, {len(d['dressed'])} dressed, {len(d['faces'])} faces")
