"""Held items: weapons, shields, tools, potions, built from parts and held in a hand.

An item is a list of PARTS, each a simple shape placed, turned and sized in the item's own space (x across, y depth
with its front at -y, z up, in the figure's units), coloured by one of the item's roles:

    box       a block
    wedge     a block whose top slopes from its back edge down to its front edge
    cylinder  a post of a few sides (3 a triangle, 4 a square, 8 nearly round)
    cone      a post narrowing to a point at its top
    sphere    a ball of a few faces
    outline   a flat shape drawn on a 16 x 16 grid, given thickness: blades, axe heads, shields
    spin      half a side view drawn on the grid and spun round its middle: bottles, handles, pommels

A part fills its size exactly (its width, depth and height are the box round it, whatever its number of sides), and is
turned forward about x, then sideways about y, then about z, and moved. A mirrored part is drawn twice, the second
copy across the item's middle. Every shape is closed, its faces turned outward; parts overlap, nothing is cut.

Holding: the item's GRIP is where the hand closes, and its turn is how the item sits in the hand. Unturned, an item
made standing up and facing the front is held as a sword is, in the right hand with the arm hanging: its top ahead
(out of the thumb's side of the fist), its front facing outward, its left side (+x) down. The left hand holds the
mirror image. The item is drawn at the palm, the middle of the box round the hand, and rides the forearm.

The game builds the same shapes and holds them the same way (core/held_item_shape.gd), checked against this corner by
corner (tests/test_lowpoly.gd, from tests/lowpoly_expected.json). The editor's Items tab makes items.
"""
import numpy as np

KINDS = ("box", "wedge", "cylinder", "cone", "sphere", "outline", "spin")
GRID = 16
EPS = 1e-12


def _rx(deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def _ry(deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def _rz(deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def turn(rotation):
    """Tipped forward about x, then sideways about y, then turned about z (degrees)."""
    return _rz(rotation[2]) @ _ry(rotation[1]) @ _rx(rotation[0])


def _v(x, y, z):
    return np.array([x, y, z], float)


def _box(sx, sy, sz):
    x, y, z = 0.5 * sx, 0.5 * sy, 0.5 * sz
    c = [_v(-x, -y, -z), _v(x, -y, -z), _v(x, y, -z), _v(-x, y, -z), _v(-x, -y, z), _v(x, -y, z), _v(x, y, z), _v(-x, y, z)]
    return [[c[0], c[3], c[2], c[1]], [c[4], c[5], c[6], c[7]], [c[0], c[1], c[5], c[4]],
            [c[1], c[2], c[6], c[5]], [c[2], c[3], c[7], c[6]], [c[3], c[0], c[4], c[7]]]


def _wedge(sx, sy, sz):
    x, y, z = 0.5 * sx, 0.5 * sy, 0.5 * sz
    fl, fr, bl, br = _v(-x, -y, -z), _v(x, -y, -z), _v(-x, y, -z), _v(x, y, -z)
    tl, tr = _v(-x, y, z), _v(x, y, z)
    return [[fl, bl, br, fr], [bl, tl, tr, br], [fl, fr, tr, tl], [fl, tl, bl], [fr, br, tr]]


def _distinct(corners):
    out = []
    for c in corners:
        if not any(np.linalg.norm(c - d) < 1e-9 for d in out):
            out.append(c)
    return out


def _lathe(profile, sides, sx, sy, sz):
    """A profile ([out 0..1, up 0..1] points) spun round the middle; an end off the middle is capped. The ring at 1 out
    fills the width and depth exactly, its box's middle on the middle."""
    pts = [list(p) for p in profile]
    if len(pts) < 2:
        return []
    if pts[0][0] > 1e-9:
        pts.insert(0, [0.0, pts[0][1]])
    if pts[-1][0] > 1e-9:
        pts.append([0.0, pts[-1][1]])
    ring = []
    for k in range(sides):
        a = 2 * np.pi * k / sides + np.pi / sides
        ring.append((np.sin(a), -np.cos(a)))
    xs = [u[0] for u in ring]; ys = [u[1] for u in ring]
    mid_x, mid_y = 0.5 * (min(xs) + max(xs)), 0.5 * (min(ys) + max(ys))
    scale_x, scale_y = sx / (max(xs) - min(xs)), sy / (max(ys) - min(ys))

    def at(p, k):
        u = ring[k % sides]
        return _v(p[0] * (u[0] - mid_x) * scale_x, p[0] * (u[1] - mid_y) * scale_y, (p[1] - 0.5) * sz)

    out = []
    for i in range(len(pts) - 1):
        for k in range(sides):
            kept = _distinct([at(pts[i], k), at(pts[i], k + 1), at(pts[i + 1], k + 1), at(pts[i + 1], k)])
            if len(kept) >= 3:
                out.append(kept)
    return out


def _same(a, b):
    return abs(a[0] - b[0]) < 1e-9 and abs(a[1] - b[1]) < 1e-9


def _area2(pts):
    n = len(pts)
    return sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))


def _in_triangle(p, a, b, c):
    for u, v in ((a, b), (b, c), (c, a)):
        if (v[0] - u[0]) * (p[1] - u[1]) - (v[1] - u[1]) * (p[0] - u[0]) < -EPS:
            return False
    return True


def triangles(pts):
    """An anticlockwise outline cut into triangles by ear clipping: [[i, j, k], ...]. Each time the first corner that
    bulges outward with no other point in or on its triangle is cut off; failing that, the first corner in a straight
    line with its neighbours (a triangle of no area, so the edges still meet); failing that (a drawing that crosses
    itself), what is left is not filled."""
    left = list(range(len(pts)))
    out = []
    while len(left) > 3:
        n = len(left)
        cut = -1
        for pass_ in range(2):
            for i in range(n):
                a, b, c = pts[left[(i - 1) % n]], pts[left[i]], pts[left[(i + 1) % n]]
                turn_ = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
                if pass_ == 1:
                    if abs(turn_) <= EPS:
                        cut = i
                        break
                    continue
                if turn_ <= EPS:
                    continue
                clear = True
                for j in range(n):
                    if j in (i, (i - 1) % n, (i + 1) % n):
                        continue
                    p = pts[left[j]]
                    if not (_same(p, a) or _same(p, b) or _same(p, c)) and _in_triangle(p, a, b, c):
                        clear = False
                        break
                if clear:
                    cut = i
                    break
            if cut >= 0:
                break
        if cut < 0:
            return out
        out.append([left[(cut - 1) % n], left[cut], left[(cut + 1) % n]])
        del left[cut]
    out.append(list(left))
    return out


def _extrude(outline, sx, sy, sz):
    flat = []
    for p in outline:
        if not flat or not _same(flat[-1], p):
            flat.append(list(p))
    if len(flat) > 2 and _same(flat[0], flat[-1]):
        flat.pop()
    if len(flat) < 3:
        return []
    if _area2(flat) < 0.0:
        flat.reverse()
    front = lambda p: _v((p[0] - 0.5) * sx, -0.5 * sy, (p[1] - 0.5) * sz)
    back = lambda p: _v((p[0] - 0.5) * sx, 0.5 * sy, (p[1] - 0.5) * sz)
    out = []
    for i, j, k in triangles(flat):
        out.append([front(flat[i]), front(flat[j]), front(flat[k])])
        out.append([back(flat[k]), back(flat[j]), back(flat[i])])
    n = len(flat)
    for i in range(n):
        a, b = flat[i], flat[(i + 1) % n]
        out.append([front(a), back(a), back(b), front(b)])
    return out


def _outward(polys):
    volume = sum(float(np.dot(p[0], np.cross(p[i], p[i + 1]))) for p in polys for i in range(1, len(p) - 1))
    if volume < 0.0:
        for p in polys:
            p.reverse()


def part_polygons(part):
    """A part's polygons in the item's space, turned and placed (not mirrored): a list of arrays of corners."""
    sx, sy, sz = (float(v) for v in part["size"])
    sides = int(part.get("sides", 8))
    kind = part["kind"]
    drawn = [[p[0] / GRID, p[1] / GRID] for p in part.get("points", [])]
    if kind == "box":
        local = _box(sx, sy, sz)
    elif kind == "wedge":
        local = _wedge(sx, sy, sz)
    elif kind == "cylinder":
        local = _lathe([[1.0, 0.0], [1.0, 1.0]], sides, sx, sy, sz)
    elif kind == "cone":
        local = _lathe([[1.0, 0.0], [0.0, 1.0]], sides, sx, sy, sz)
    elif kind == "sphere":
        rings = max(2, ((sides // 2 + 1) // 2) * 2)
        profile = []
        for j in range(rings + 1):
            a = -np.pi / 2 + np.pi * j / rings
            profile.append([0.0 if j in (0, rings) else np.cos(a), 0.5 + 0.5 * np.sin(a)])
        local = _lathe(profile, sides, sx, sy, sz)
    elif kind == "outline":
        local = _extrude(drawn, sx, sy, sz)
    elif kind == "spin":
        local = _lathe(drawn, sides, sx, sy, sz)
    else:
        raise ValueError(kind)
    _outward(local)
    R = turn(part["rotation"]); t = np.array(part["position"], float)
    return [np.array([R @ c + t for c in poly]) for poly in local]


def polygons(item):
    """Every polygon of an item in its own space: [(corners, part number, role)], a mirrored part's copy after it."""
    out = []
    for i, part in enumerate(item["parts"]):
        made = part_polygons(part)
        out += [(pts, i, part["role"]) for pts in made]
        if part.get("mirror", False):
            out += [(pts[::-1] * np.array([-1.0, 1.0, 1.0]), i, part["role"]) for pts in made]
    return out


def palm(figure, side):
    """The middle of the box round a figure's hand band on one side ("L" or "R"), standing."""
    pts = np.array([p for q in figure["polys"] if q["band"] == "hand" and q["side"] == side for p in q["pts"]])
    return 0.5 * (pts.min(axis=0) + pts.max(axis=0))


RIGHT_HAND = np.array([[0.0, 1.0, 0.0], [0.0, 0.0, -1.0], [-1.0, 0.0, 0.0]])    # the item's (x, y, z) -> (y, -z, -x)


def in_hand(item, at, side):
    """(A, t) taking a point of the item to the figure, standing, its grip at `at`; A is a mirror image for "L"."""
    hand = RIGHT_HAND if side == "R" else np.diag([-1.0, 1.0, 1.0]) @ RIGHT_HAND
    A = hand @ turn(item["grip"]["rotation"]).T
    return A, np.asarray(at, float) - A @ np.array(item["grip"]["position"], float)


def held(figure, item, side):
    """The item in a figure's hand: [(corners, part number, role)], each polygon facing outward (a mirror image's
    corners are taken in the other order)."""
    A, t = in_hand(item, palm(figure, side), side)
    out = []
    for pts, i, role in polygons(item):
        placed = np.array([A @ p + t for p in pts])
        out.append((placed[::-1] if side == "L" else placed, i, role))
    return out
