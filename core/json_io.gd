@tool
class_name JsonIO
extends RefCounted

## Reading and writing the project's JSON, in one place.
##
## Two things matter here. First, asset JSON must load whether it was shipped as
## plain text or imported as a JSON resource, so reads try both. Second, the
## wardrobe file has to round-trip byte for byte (SPEC.md section 12), which
## means keys are always sorted and nothing that could drift -- notably colours
## -- is ever stored as a float. Colours go in and out as "#rrggbb".

const INDENT := "  "


## Read a JSON object from res:// or a user path. Returns {} on failure and
## pushes an error; call last_error() for the message.
static var _last_error: String = ""


static func last_error() -> String:
	return _last_error


static func read_dict(path: String) -> Dictionary:
	_last_error = ""
	var text := ""
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
			f.close()
	if text.is_empty() and ResourceLoader.exists(path):
		# Imported as a JSON resource rather than kept as text.
		var res := ResourceLoader.load(path)
		if res is JSON:
			var data: Variant = (res as JSON).data
			if data is Dictionary:
				return data as Dictionary
			_last_error = "%s: JSON resource is not an object" % path
			push_error(_last_error)
			return {}
	if text.is_empty():
		_last_error = "%s: not found or empty" % path
		push_error(_last_error)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_last_error = "%s: could not be parsed as JSON" % path
		push_error(_last_error)
		return {}
	if not (parsed is Dictionary):
		_last_error = "%s: top level is not a JSON object" % path
		push_error(_last_error)
		return {}
	return parsed as Dictionary


## Write a JSON object with sorted keys and a trailing newline. Returns "" on
## success or an error message.
static func write_dict(path: String, data: Dictionary) -> String:
	var text := JSON.stringify(data, INDENT, true, false) + "\n"
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return "could not create %s (error %d)" % [dir, err]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "could not open %s for writing (error %d)" % [path, FileAccess.get_open_error()]
	f.store_string(text)
	f.close()
	return ""


## Serialise exactly as write_dict would, without touching the disk. Used by the
## round-trip test and by the unsaved-changes check.
static func to_text(data: Dictionary) -> String:
	return JSON.stringify(data, INDENT, true, false) + "\n"


# ----------------------------------------------------------------- colours --

## Colour -> "#rrggbb". Alpha is never stored: nothing in the figure is
## translucent, and keeping it out guarantees the round-trip.
static func colour_to_hex(c: Color) -> String:
	return "#" + c.to_html(false).to_lower()


static func hex_to_colour(s: String) -> Color:
	var t := s.strip_edges()
	if t.begins_with("#"):
		t = t.substr(1)
	if not Color.html_is_valid(t):
		push_error("not a valid colour: %s" % s)
		return Color.MAGENTA
	var c := Color.html(t)
	c.a = 1.0
	return c


# ------------------------------------------------------------------ numbers --

## JSON has one number type, and Godot parses every number as a float. A value
## stored as the int 1 is written "1", reloaded as 1.0, and written "1.0" --
## so any field that is not cast back on load breaks the byte-for-byte
## round-trip. This settles it: whole-valued floats become ints, recursively,
## so the value is the same after every load and writes the same every time.
static func normalise_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and is_equal_approx(f, roundf(f)) and absf(f) < 9.0e15:
				return int(roundf(f))
			return f
		TYPE_DICTIONARY:
			var out := {}
			var d: Dictionary = value
			for key in d.keys():
				out[key] = normalise_numbers(d[key])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for item in (value as Array):
				arr.append(normalise_numbers(item))
			return arr
	return value


# ------------------------------------------------------------------ vectors --

static func to_vec3i(v: Variant) -> Vector3i:
	var a: Array = v as Array
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


static func to_vec3(v: Variant) -> Vector3:
	var a: Array = v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func from_vec3i(v: Vector3i) -> Array:
	return [v.x, v.y, v.z]


## Pivots are stored as given in the asset files: whole numbers stay whole,
## halves stay halves, so a reserialised body file matches the original.
static func from_vec3(v: Vector3) -> Array:
	return [_trim(v.x), _trim(v.y), _trim(v.z)]


static func _trim(f: float) -> Variant:
	if is_equal_approx(f, roundf(f)):
		return int(roundf(f))
	return f


## Read a voxel list -- [[x, y, z], ...] -- into a Dictionary used as a set.
static func voxel_set(list: Variant) -> Dictionary:
	var out := {}
	if list == null:
		return out
	for v in (list as Array):
		out[to_vec3i(v)] = true
	return out


## A voxel set back to a sorted list, so output order never depends on hashing.
static func voxel_list(cells: Dictionary) -> Array:
	var keys := cells.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z < b.z
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	var out: Array = []
	for k in keys:
		out.append(from_vec3i(k))
	return out
