@tool
class_name Vec64
extends RefCounted

## Small vectors and 3 by 3 matrices in full precision, for the low-poly figure's dressing and cloth.
##
## Godot's Vector3 and Basis are single precision; lowpoly/ (Python) works in double precision, and the cloth rules
## make choices (which point of the figure a cloth line rests on, which bend of it keeps a row of points) that a
## hundred-thousandth can tip. So the low-poly code that must agree with lowpoly/ keeps its numbers as doubles: a
## vector is a PackedFloat64Array of three, a matrix one of nine (row by row). Each function does its sums in the
## same order numpy does, so the two agree to the last place nearly everywhere.


static func v(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func of(p: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([p.x, p.y, p.z])


static func to_vector3(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2]])


static func sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


## s * a
static func mul(a: PackedFloat64Array, s: float) -> PackedFloat64Array:
	return PackedFloat64Array([s * a[0], s * a[1], s * a[2]])


static func div(a: PackedFloat64Array, s: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] / s, a[1] / s, a[2] / s])


static func neg(a: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([-a[0], -a[1], -a[2]])


static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]])


static func norm(a: PackedFloat64Array) -> float:
	return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


## a / |a|, or a as it is when it has no length (lowpoly/hang.py unit).
static func unit(a: PackedFloat64Array) -> PackedFloat64Array:
	var n := norm(a)
	return div(a, n) if n > 1e-12 else a.duplicate()


## a + f * (b - a)
static func lerp3(a: PackedFloat64Array, b: PackedFloat64Array, f: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2])])


## The point at index i of a flat list of points (x, y, z of each in turn).
static func at(flat: PackedFloat64Array, i: int) -> PackedFloat64Array:
	return PackedFloat64Array([flat[3 * i], flat[3 * i + 1], flat[3 * i + 2]])


# ----------------------------------------------------------------------------------------------- matrices ---

static func identity() -> PackedFloat64Array:
	return PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0])


## m @ a
static func apply(m: PackedFloat64Array, a: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([m[0] * a[0] + m[1] * a[1] + m[2] * a[2], m[3] * a[0] + m[4] * a[1] + m[5] * a[2],
		m[6] * a[0] + m[7] * a[1] + m[8] * a[2]])


## m @ n
static func matmul(m: PackedFloat64Array, n: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(9)
	for r in 3:
		for c in 3:
			out[3 * r + c] = m[3 * r] * n[c] + m[3 * r + 1] * n[3 + c] + m[3 * r + 2] * n[6 + c]
	return out


## Turns by that many degrees about x, y and z (lowpoly/pose.py _rx, _ry, _rz).
static func rx(deg: float) -> PackedFloat64Array:
	var a := deg_to_rad(deg)
	var c := cos(a)
	var s := sin(a)
	return PackedFloat64Array([1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c])


static func ry(deg: float) -> PackedFloat64Array:
	var a := deg_to_rad(deg)
	var c := cos(a)
	var s := sin(a)
	return PackedFloat64Array([c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c])


static func rz(deg: float) -> PackedFloat64Array:
	var a := deg_to_rad(deg)
	var c := cos(a)
	var s := sin(a)
	return PackedFloat64Array([c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0])
