@tool
class_name BodyDef
extends RefCounted

## One base body: 11 rigid parts, their parents, pivots and voxels, plus the
## shared region band table (SPEC.md section 3).
##
## The head part is always present but its voxel list is empty in the body file:
## head geometry comes from the head library so any head fits any body. The
## assembler fills it in.

## Parent chain (SPEC section 3.1). Held here as well as in the files so a
## malformed asset is caught rather than silently believed.
const EXPECTED_PARENTS := {
	"pelvis": "",
	"chest": "pelvis",
	"head": "chest",
	"upper_arm_L": "chest", "upper_arm_R": "chest",
	"forearm_L": "upper_arm_L", "forearm_R": "upper_arm_R",
	"thigh_L": "pelvis", "thigh_R": "pelvis",
	"shin_L": "thigh_L", "shin_R": "thigh_R",
}

const ROOT_PART := "pelvis"
const HEAD_PART := "head"


class PartDef extends RefCounted:
	var name: String
	var parent: String          ## "" for the root
	var pivot: Vector3          ## corner space; the joint with the parent
	var cells: Dictionary = {}  ## Vector3i -> true

	func _init(p_name: String, p_parent: String, p_pivot: Vector3, p_cells: Dictionary) -> void:
		name = p_name
		parent = p_parent
		pivot = p_pivot
		cells = p_cells

	func family() -> String:
		return RegionMap.family_of(name)

	func side() -> String:
		return RegionMap.side_of_part(name)

	func count() -> int:
		return cells.size()


var id: String = ""             ## e.g. "male_average"
var sex: String = ""
var build: String = ""
var grid: Vector3i = VoxelAxes.GRID
var parts: Dictionary = {}      ## part name -> PartDef
var regions: RegionMap = null
var source_path: String = ""

## Parts in parent-before-child order, so a rig can be built in one pass.
var hierarchy_order: Array[String] = []


static func load_from(path: String) -> BodyDef:
	var data := JsonIO.read_dict(path)
	if data.is_empty():
		return null
	var def := BodyDef.new()
	def.source_path = path
	def.sex = String(data.get("sex", ""))
	def.build = String(data.get("build", ""))
	def.id = "%s_%s" % [def.sex, def.build]
	if data.has("grid"):
		def.grid = JsonIO.to_vec3i(data["grid"])

	var facing := String(data.get("facing", "-y"))
	if facing != "-y":
		push_error("%s: facing is %s, but the project assumes -y (SPEC section 2)" % [path, facing])
		return null
	var mirror := int(data.get("mirror_axis_x", 12))
	if mirror != int(VoxelAxes.MIRROR_X):
		push_error("%s: mirror axis is %d, expected %d" % [path, mirror, int(VoxelAxes.MIRROR_X)])
		return null

	var raw_parts: Dictionary = data.get("parts", {})
	for name in raw_parts.keys():
		var p: Dictionary = raw_parts[name]
		var parent_value: Variant = p.get("parent", null)
		var parent := "" if parent_value == null else String(parent_value)
		def.parts[String(name)] = PartDef.new(
			String(name), parent,
			JsonIO.to_vec3(p["pivot"]),
			JsonIO.voxel_set(p.get("voxels", []))
		)

	def.regions = RegionMap.from_json(data.get("regions", {}))
	var problem := def._validate()
	if not problem.is_empty():
		push_error("%s: %s" % [path, problem])
		return null
	def._order_hierarchy()
	return def


func _validate() -> String:
	for name in EXPECTED_PARENTS.keys():
		if not parts.has(name):
			return "missing part %s" % name
	for name in parts.keys():
		if not EXPECTED_PARENTS.has(name):
			return "unexpected part %s" % name
		var want := String(EXPECTED_PARENTS[name])
		var got: String = (parts[name] as PartDef).parent
		if got != want:
			return "part %s has parent '%s', expected '%s'" % [name, got, want]
	if regions == null or regions.bands.is_empty():
		return "no region bands"
	if not (parts[HEAD_PART] as PartDef).cells.is_empty():
		return "head voxels should be empty in a body file (they come from the head library)"
	return ""


func _order_hierarchy() -> void:
	hierarchy_order.clear()
	var remaining := parts.keys()
	remaining.sort()
	var placed := {}
	while not remaining.is_empty():
		var progressed := false
		var still: Array = []
		for name in remaining:
			var p: PartDef = parts[name]
			if p.parent.is_empty() or placed.has(p.parent):
				hierarchy_order.append(String(name))
				placed[name] = true
				progressed = true
			else:
				still.append(name)
		remaining = still
		if not progressed:
			push_error("%s: part hierarchy has a cycle" % source_path)
			break


func part(name: String) -> PartDef:
	return parts.get(name, null) as PartDef


func part_names() -> Array[String]:
	var out: Array[String] = []
	for n in hierarchy_order:
		out.append(n)
	return out


func children_of(name: String) -> Array[String]:
	var out: Array[String] = []
	for other in hierarchy_order:
		if (parts[other] as PartDef).parent == name:
			out.append(other)
	return out


## Every body voxel, head excluded (the head comes from the head library).
func all_cells() -> Dictionary:
	var out := {}
	for name in parts.keys():
		for cell in (parts[name] as PartDef).cells.keys():
			out[cell] = name
	return out


func total_voxels() -> int:
	var n := 0
	for name in parts.keys():
		n += (parts[name] as PartDef).count()
	return n


## Human-readable name for UI lists: "masculine average", not "male_average".
func display_name() -> String:
	var sex_word := "masculine" if sex == "male" else "feminine"
	return "%s %s" % [sex_word, build]
