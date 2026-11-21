"""Facial hair on the low-poly head (owner, 2026-11).

Facial hair is four parts, each on or off, and one length for all of them:

  parts     moustache   above the mouth
            sideburns   in front of each ear, from about the bottom of the ear up to the hair (on a bald head, up to
                        the top of the ear)
            goatee      the chin: from under the mouth, down the front of the jaw and under it
            cheeks      the rest of a beard, between the sideburns and the goatee: the jaw, the lower cheeks, and the
                        face beside the mouth, up to a line from beside the mouth to the foot of the sideburn
  length    thickness done the way clothes do bulk:
            stubble     a tint over the skin, as if seen through, flush with the face: the game's stubble colour,
                        which it works out from the skin and the hair
            short       the hair's colour, opaque, still flush with the face
            medium      grown out from the face by half a step of bulk
            long        grown out by a whole step

A full beard has every part on, an Amish beard every part but the moustache, and so on (PRESETS).

Every part is made of the head's own polygons. The polygons a part covers are cut along its edge, and the ordinary
garment rules of dress.py recolour them, or lift them and give them their edges, as they do a sleeve. So facial hair
follows every head's own shape. The game's three facial hair items (setting "style": stubble, chinstrap, full beard)
are read as parts and a length (GAME_STYLES).
"""
import numpy as np
import body as lb, heads as hd

CX = lb.CX
PARTS = ("moustache", "sideburns", "goatee", "cheeks")
LENGTHS = {"stubble": 0.0, "short": 0.0, "medium": 0.5, "long": 1.0}    # how far each length stands out, in steps of bulk
PRESETS = {
    "full beard": PARTS,
    "Amish": ("sideburns", "goatee", "cheeks"),
    "mutton chops": ("sideburns", "cheeks"),
    "goatee and moustache": ("moustache", "goatee"),
    "goatee": ("goatee",),
    "moustache": ("moustache",),
    "sideburns": ("sideburns",),
}
GAME_STYLES = {"stubble": (PARTS, "stubble"), "chinstrap": (PRESETS["Amish"], "medium"), "full_beard": (PARTS, "medium")}

SIDEBURN_FOOT = hd.RING_Z[3]     # 31: a sideburn comes down to about the bottom of the ear
EAR_TOP = 34.4                   # on a bald head a sideburn stops at the top of the ear
CHEEK_LINE = (29.95, 30.15, 30.55, SIDEBURN_FOOT)   # the top of the cheeks: beside the mouth, then at the next three corners round the head
MOUTH_ROOM = 1.2                 # beside the mouth the cheeks keep this far from the middle of the face
MOUTH_FLOOR = 29.12              # under the mouth the goatee comes up to here
GOATEE_HALF = (2.0, 1.5)         # half the goatee's width: at the top of the jaw, and under the chin
MOUSTACHE = [(0.0, 29.66, 30.42), (1.0, 29.62, 30.28), (2.1, 29.50, 29.86)]   # from the middle of the face outward: (how far out, lower edge, upper edge)


def read(params):
    """An item's facial hair settings, as (parts, length, notes). Settings it does not have are their defaults (the
    game's, specials.DEFAULTS), as the game's editor shows them; the game's old "style" setting is read as parts and a
    length, and a style that is not known gives no facial hair, and a note."""
    import specials
    params = dict(params or {})
    if "style" in params:
        style = str(params.pop("style"))
        if style not in GAME_STYLES: return (), "stubble", [f"unknown facial hair style '{style}'"]
        parts, length = GAME_STYLES[style]
        params.update({p: p in parts for p in PARTS}, length=length)
    params = specials.settings("facial_hair", params)
    parts = tuple(p for p in PARTS if params[p]); length = str(params["length"])
    if length not in LENGTHS: return (), "stubble", [f"unknown facial hair length '{length}'"]
    return parts, length, []


def item(parts, length):
    """A facial hair item for the wardrobe with these parts on and this length: (its id, the item)."""
    on = [p for p in PARTS if p in parts]
    params = {p: p in on for p in PARTS}; params["length"] = length
    item_id = "facial hair: " + (", ".join(on) or "none") + ", " + length
    return item_id, dict(category="facial_hair", name=item_id, colourways={"default": {"hair": "@hair", "stubble": "@stubble"}}, coverage={},
                         draw_order=65, edge_style="soft", mirror=True, roles=["hair", "stubble"], specials=[dict(type="facial_hair", params=params)])


# ---------------------------------------------------------------------------------------------- mesh tools ---

def _split(r, point, normal):
    """A polygon record cut by a plane: (the part on the side the normal points to, the part on the other side).
    Either is None where the polygon has nothing."""
    p = r["pts"]; d = (p - point) @ normal
    if d.min() >= -1e-9: return r, None
    if d.max() <= 1e-9: return None, r
    halves = []
    for sign in (1.0, -1.0):
        out = []
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]; da, db = sign * d[i], sign * d[(i + 1) % len(p)]
            if da >= -1e-9: out.append(a)
            if (da > 1e-9 and db < -1e-9) or (da < -1e-9 and db > 1e-9): out.append(a + da / (da - db) * (b - a))
        q = dict(r); q["pts"] = np.array(out)
        halves.append(q if len(out) >= 3 else None)
    return halves[0], halves[1]


def _carve(polys, pick, planes, claim):
    """Cut every picked polygon down to the part inside all the planes, and give that part the claim. A plane is (a
    point on it, its normal pointing in). What is cut away stays as it was. A claim is (bulk, draw order, colour), as
    dress.py reads them."""
    out = []
    for r in polys:
        if not pick(r):
            out.append(r); continue
        rest = r
        for point, normal in planes:
            rest, away = _split(rest, point, normal)
            if away is not None: out.append(away)
            if rest is None: break
        if rest is not None:
            rest = dict(rest); rest["claims"] = list(rest.get("claims", [])) + [claim]
            out.append(rest)
    return out


def _tidy(p):
    """A polygon's corners without repeats and without corners on a straight run."""
    p = [np.asarray(v, float) for v in p]
    changed = True
    while changed and len(p) >= 3:
        changed = False
        for i in range(len(p)):
            a, b, c = p[i - 1], p[i], p[(i + 1) % len(p)]
            ab, bc = np.linalg.norm(b - a), np.linalg.norm(c - b)
            if ab < 1e-9 or np.linalg.norm(np.cross(b - a, c - b)) <= 1e-9 * max(ab * bc, 1e-12):
                del p[i]; changed = True; break
    return p


def _merge(polys):
    """Join neighbouring pieces cut from the same polygon of the head that carry the same claims, wherever the two
    together are still convex: a cut only needs to stay where the claims on its two sides differ. Corners on a straight
    run are dropped; conform() puts back those that a neighbour needs."""
    key = lambda v: tuple(np.round(v, 5))
    newell = lambda p: sum(np.cross(p[i], p[(i + 1) % len(p)]) for i in range(len(p)))
    area = lambda p: 0.5 * float(np.linalg.norm(newell(p)))

    def convex(p):
        n = newell(p); ln = np.linalg.norm(n)
        if len(p) < 3 or ln < 1e-12: return False
        n = n / ln
        return all(np.cross(p[i] - p[i - 1], p[(i + 1) % len(p)] - p[i]) @ n > 0 for i in range(len(p)))

    groups = {}; out = []
    for r in polys:
        at = r.get("at")
        if r["piece"] != "head" or at is None or at[0] not in ("ring", "base"):
            out.append([r]); continue
        k = (at, frozenset(tuple(c) for c in r.get("claims", ())))
        if k not in groups:
            groups[k] = []; out.append(groups[k])
        pts = _tidy(r["pts"])
        if len(pts) >= 3 and area(pts) > 1e-9:
            r = dict(r); r["pts"] = np.array(pts); groups[k].append(r)
    for pieces in groups.values():
        joined = True
        while joined:
            joined = False
            for i in range(len(pieces)):
                for j in range(i + 1, len(pieces)):
                    a, b = pieces[i]["pts"], pieces[j]["pts"]
                    shared = [(s, t) for s in range(len(a)) for t in range(len(b))
                              if key(b[t]) == key(a[(s + 1) % len(a)]) and key(b[(t + 1) % len(b)]) == key(a[s])]
                    if len(shared) != 1: continue
                    s, t = shared[0]
                    ring = _tidy([a[(s + 1 + k) % len(a)] for k in range(len(a))] + [b[(t + 2 + k) % len(b)] for k in range(len(b) - 2)])
                    if convex(ring) and abs(area(ring) - area(a) - area(b)) <= 1e-3 * (area(a) + area(b)):
                        r = dict(pieces[i]); r["pts"] = np.array(ring); pieces[i] = r; del pieces[j]; joined = True; break
                if joined: break
    return [r for group in out for r in group]


def conform(polys, piece="head"):
    """After cutting: give every polygon of the piece the corners that other polygons have on its edges, so that
    neighbours share whole edges again. dress.py looks across an edge to find the neighbour a hem steps down to."""
    seen = {}
    for r in polys:
        if r["piece"] == piece:
            for v in r["pts"]: seen.setdefault(tuple(np.round(v, 5)), v)
    pts = np.array(list(seen.values()))
    out = []
    for r in polys:
        if r["piece"] != piece:
            out.append(r); continue
        p = r["pts"]; ring = []
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]; ab = b - a; ll = float(ab @ ab)
            ring.append(a)
            if ll < 1e-12: continue
            t = (pts - a) @ ab / ll
            on = (t > 1e-6) & (t < 1.0 - 1e-6) & (np.linalg.norm(pts - a - np.outer(t, ab), axis=1) < 1e-6)
            for k in np.argsort(t[on]): ring.append(pts[on][k])
        if len(ring) != len(p):
            r = dict(r); r["pts"] = np.array(ring)
        out.append(r)
    return out


# ---------------------------------------------------------------------------------------------- the parts ---

def areas(head, hair):
    """Where each part is on a head: [(part, pick, planes)]. pick chooses the head's polygons the part may cover;
    planes (a point, a normal pointing in) cut its edge through them. hair: whether hair is worn (the sideburns then
    run up into it)."""
    rg = hd.rings(head); n = len(rg[0]); zs = hd.RING_Z
    tilt = float(np.tan(np.radians(hd.FACE_BEND)))
    out = []

    def column(j, s, z):
        """The point at height z down the j-th corner round the head from the front, on side s (1: the figure's left)."""
        i = max(k for k in range(len(zs) - 1) if zs[k] >= z - 1e-9)
        a, b = rg[i][j if s > 0 else (n - j) % n], rg[i + 1][j if s > 0 else (n - j) % n]
        return a + (zs[i] - z) / (zs[i] - zs[i + 1]) * (b - a)

    def facet_normal(band, j, s):
        k = j if s > 0 else (n - j) % n; k1 = (j + 1) if s > 0 else (n - j - 1) % n
        a, b, c, d = rg[band][k], rg[band][k1], rg[band + 1][k1], rg[band + 1][k]
        m = np.cross(c - a, d - b); m = m / np.linalg.norm(m)
        return m if m @ (0.5 * (a + c) - np.array([CX, lb.CY, 0.5 * (a[2] + c[2])])) > 0 else -m

    def line(p, q, normal, toward):
        """The plane through the line from p to q, square to a surface of this normal, pointing toward a point."""
        m = np.cross(q - p, normal)
        return p, (m if m @ (toward - p) > 0 else -m)

    ring = lambda band, j, s: (lambda r: r["piece"] == "head" and r.get("at") == ("ring", band, j if s > 0 else n - 1 - j))
    base = lambda s: (lambda r: r["piece"] == "head" and r.get("at") == ("base", 0 if s > 0 else 3))
    down = lambda z: (np.array([0.0, 0.0, z]), np.array([0.0, 0.0, -1.0]))
    g0, g1 = GOATEE_HALF; slope = (g1 - g0) / (hd.BELT[0] - hd.BOTTOM)
    for s in (1.0, -1.0):
        flat = lambda u, z, s=s: np.array([CX + s * u, hd.face_y(CX + s * u), z])           # a point on this side's flat of the face
        face = np.array([s * tilt, -1.0, 0.0]) / np.hypot(tilt, 1.0)                        # its outward normal
        goatee_in = (np.array([CX + s * g0, 0.0, hd.BELT[0]]), np.array([-s, 0.0, -slope]))   # the goatee's edge, pointing in
        goatee_out = (goatee_in[0], -goatee_in[1])
        # the moustache: each piece a convex quad on the flat of the face, above the mouth
        for (ua, la, ha), (ub, lb_, hb) in zip(MOUSTACHE[:-1], MOUSTACHE[1:]):
            corners = [flat(ua, la), flat(ub, lb_), flat(ub, hb), flat(ua, ha)]
            middle = np.mean(corners, axis=0)
            planes = [line(corners[k], corners[(k + 1) % 4], face, middle) for k in range(4)]
            out.append(("moustache", ring(3, 0, s), planes))
        # the sideburn: the column in front of the ear, from its foot up to the hair or the top of the ear
        out.append(("sideburns", ring(2, 3, s), [] if hair else [down(EAR_TOP)]))
        # the goatee: under the mouth, then a strip down the front of the jaw and under the chin
        out.append(("goatee", ring(3, 0, s), [goatee_in, down(MOUTH_FLOOR)]))
        for band in (4, 5):
            out.append(("goatee", ring(band, 0, s), [goatee_in]))
        out.append(("goatee", base(s), [goatee_in]))
        # the cheeks: beside the mouth, the lower cheeks up to the cheek line, the jaw and under it, round to the sideburn
        beside = line(flat(MOUTH_ROOM, hd.BELT[0]), flat(MOUTH_ROOM, hd.BELT[1]), face, flat(hd.FACE_HALF_WIDTH, hd.BELT[0]))
        top = line(flat(MOUTH_ROOM, CHEEK_LINE[0]), flat(hd.FACE_HALF_WIDTH, CHEEK_LINE[1]), face, flat(MOUTH_ROOM, hd.BELT[0]))
        out.append(("cheeks", ring(3, 0, s), [beside, top]))
        for j in (1, 2):
            p, q = column(j, s, CHEEK_LINE[j]), column(j + 1, s, CHEEK_LINE[j + 1])
            out.append(("cheeks", ring(3, j, s), [line(p, q, facet_normal(3, j, s), column(j, s, hd.BELT[0]))]))
        out.append(("cheeks", ring(3, 3, s), []))
        for band in (4, 5):
            out.append(("cheeks", ring(band, 0, s), [goatee_out]))
            for j in (1, 2, 3):
                out.append(("cheeks", ring(band, j, s), []))
        out.append(("cheeks", base(s), [goatee_out]))
    return out


def on_head(polys, parts, length, colours, order, head, hair, who=None, dz=0.0):
    """The figure's polygons with facial hair marked on the head: a new list in which the polygons it covers carry a
    claim (bulk, draw order, colour, who), cut along its edge. parts: which of PARTS are on. colours: "hair" and
    "stubble". head: the name of the head's shape. hair: whether hair is worn. who: the item, for dress.py to name.
    dz: how far the head stands from the head library's heights (a short body's head sits lower)."""
    if not parts: return polys
    claim = (LENGTHS[length], order, colours["stubble" if length == "stubble" else "hair"], who)
    up = np.array([0.0, 0.0, dz])
    for part, pick, planes in areas(head, hair):
        if part in parts: polys = _carve(polys, pick, [(p + up, n) for p, n in planes] if dz else planes, claim)
    return conform(_merge(polys))


def cover():
    """The moustache as flat polygons on the face [(x from the face's centre line, height)], each on one side of the
    centre line: what it hides of the mouth, once it is more than stubble."""
    out = []
    for s in (1.0, -1.0):
        for (ua, la, ha), (ub, lb_, hb) in zip(MOUSTACHE[:-1], MOUSTACHE[1:]):
            out.append([(s * ua, la), (s * ub, lb_), (s * ub, hb), (s * ua, ha)])
    return out
