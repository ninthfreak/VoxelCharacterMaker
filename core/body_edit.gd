@tool
class_name BodyEdit
extends VoxelEditModel

## An editable base body (SPEC.md section 8, "Body editing").
##
## The spec asks for parts as layers, one owner per cell, mandatory mirror
## pairs, row-band guides, pivot markers and a pose preview. The first three
## are invariants rather than UI, so they live here and the panel cannot break
## them by accident:
##
##   one owner per cell   painting a cell into a part removes it from whatever
##                        part held it before
##   mirror pairs         every edit is applied to the mirrored cell too. For a
##                        paired part the mirror lands in its opposite number
##                        (upper_arm_L <-> upper_arm_R); for a centred part it
##                        lands in the same part. A body cannot be made
##                        asymmetric through this class at all.
##
## Pivots are not stored: they are measured from the geometry whenever it
## changes, exactly the way tools/build_bodies.py measures them, so an edited
## body gets the pivots it would have had if it had been generated
## (SPEC section 3.2, "Measured from the built geometry").
##
## The head is a special case throughout. A body file carries no head voxels --
## they come from the head library so any head fits any body (SPEC section 4) --
## so the head "part" here is always empty and cannot be painted.


## Pivot measurement windows, copied from tools/build_bodies.py:pivots().
## Each paired part's x is the mid-x of its own cells over these rows.
const PIVOT_ROWS := {
	"upper_arm": Vector2i(19, 21),
	"forearm": Vector2i(13, 18),
	"thigh": Vector2i(6, 11),
	"shin": Vector2i(2, 5),
}

## The z of each joint, and the fixed pivots of the centred parts.
const PIVOT_Z := {
	"upper_arm": 26,
	"forearm": 19,
	"thigh": 12,
	"shin": 6,
}

const FIXED_PIVOTS := {
	"pelvis": Vector3(12, 12, 12),
	"chest": Vector3(12, 12, 16),
	"head": Vector3(12, 12, 27),
}

## Parts that can be painted. The head is excluded: its geometry belongs to the
## head library, not to the body.
const PAINTABLE: Array[String] = [
	"pelvis", "chest",
	"upper_arm_L", "upper_arm_R", "forearm_L", "forearm_R",
	"thigh_L", "thigh_R", "shin_L", "shin_R",
]

var sex: String = "male"
var build: String = "average"
var regions: RegionMap = null

var _pivots: Dictionary = {}
var _pivots_stale := true


static func from_body(body: BodyDef) -> BodyEdit:
	var edit := BodyEdit.new()
	edit.sex = body.sex
	edit.build = body.build
	edit.regions = body.regions
	edit.source_path = body.source_path
	for name in BodyDef.EXPECTED_PARENTS.keys():
		edit.parts[name] = {}
	for name in body.part_names():
		var part := body.part(name)
		for cell in part.cells.keys():
			edit.parts[name][cell] = true
			edit.owner_of[cell] = name
	edit._pivots_stale = true
	return edit


func duplicate_edit() -> BodyEdit:
	var copy := BodyEdit.new()
	copy.sex = sex
	copy.build = build
	copy.regions = regions
	copy.source_path = source_path
	for name in parts.keys():
		copy.parts[name] = (parts[name] as Dictionary).duplicate()
	copy.owner_of = owner_of.duplicate()
	copy._pivots_stale = true
	return copy


func id() -> String:
	return "%s_%s" % [sex, build]


func display_name() -> String:
	return "%s %s" % ["masculine" if sex == "male" else "feminine", build]


func kind() -> String:
	return "body"


func paintable_parts() -> Array[String]:
	return PAINTABLE.duplicate()


## The half of a pair that belongs on the side of `cell`. A paired part never
## crosses the mirror line -- thighs do not touch, arms hang clear of each
## other -- so the side of the cell decides which half it is. Painting
## "upper_arm_L" on the character's right therefore paints the right arm, and
## the mirror puts the left arm where it belongs, instead of swapping the two.
##
## This matters because the slice grid looks down on the figure: screen-left
## is the character's RIGHT, and choosing "_L" then painting on the left of
## the screen is the obvious mistake to make.
static func part_for_side(part_name: String, cell: Vector3i) -> String:
	var side := RegionMap.side_of_part(part_name)
	if side.is_empty():
		return part_name
	var cell_is_left := VoxelAxes.is_left(cell)
	if (side == RegionMap.SIDE_LEFT) == cell_is_left:
		return part_name
	return mirror_part(part_name)


func part_here(part_name: String, cell: Vector3i) -> String:
	return part_for_side(part_name, cell)


## Every edit can move a pivot, so they are re-measured lazily.
func _invalidate() -> void:
	_pivots_stale = true
	super._invalidate()


# ------------------------------------------------------------------ pivots --

## Pivots measured from the current geometry, the way build_bodies.py does it.
func pivots() -> Dictionary:
	if _pivots_stale:
		_measure_pivots()
	return _pivots


func pivot_of(part_name: String) -> Vector3:
	return pivots().get(part_name, Vector3.ZERO)


func _measure_pivots() -> void:
	_pivots.clear()
	for name in FIXED_PIVOTS.keys():
		_pivots[name] = FIXED_PIVOTS[name]
	for family in PIVOT_ROWS.keys():
		var rows: Vector2i = PIVOT_ROWS[family]
		var z: int = PIVOT_Z[family]
		var left := String(family) + "_L"
		var x := VoxelTopology.mid_x(part_cells(left), rows.x, rows.y)
		_pivots[left] = Vector3(x, VoxelAxes.DEPTH_CENTRE, z)
		_pivots[String(family) + "_R"] = Vector3(
			VoxelAxes.MIRROR_SUM - x, VoxelAxes.DEPTH_CENTRE, z)
	_pivots_stale = false


# -------------------------------------------------------------- validation --

class Finding extends RefCounted:
	var ok: bool
	var label: String
	var detail: String
	## Cells to highlight in the editor, when there are any.
	var cells: Array = []

	func _init(p_ok: bool, p_label: String, p_detail: String = "",
			p_cells: Array = []) -> void:
		ok = p_ok
		label = p_label
		detail = p_detail
		cells = p_cells


## Check the invariants SPEC section 12 requires of every body, so the editor
## can say whether what you have drawn is still a valid body while you draw it.
##
## The head is attached for the checks that are stated about the whole figure,
## because the spec states them that way: a body on its own is not connected to
## anything at the neck.
func validate(head: HeadDef = null) -> Array:
	var findings: Array = []
	var whole := owner_of.duplicate()
	var head_cells := {}
	if head != null:
		head_cells = head.cells
		for cell in head_cells.keys():
			whole[cell] = true

	findings.append(Finding.new(
		not whole.is_empty(), "has geometry", "%d voxels" % whole.size()))

	var asymmetric := VoxelTopology.asymmetric_cells(whole)
	findings.append(Finding.new(asymmetric.is_empty(), "mirror-symmetric",
		"" if asymmetric.is_empty() else "%d cells without a partner" % asymmetric.size(),
		asymmetric))

	var pieces := VoxelTopology.components(whole)
	findings.append(Finding.new(pieces == 1, "one connected piece",
		"" if pieces == 1 else "%d separate pieces" % pieces))

	for name in PAINTABLE:
		var cells: Dictionary = parts[name]
		if cells.is_empty():
			findings.append(Finding.new(false, "part %s is empty" % name,
				"every part needs geometry"))
			continue
		var n := VoxelTopology.components(cells)
		if n != 1:
			findings.append(Finding.new(false, "part %s is one piece" % name,
				"%d separate pieces" % n))

	var edge_only := VoxelTopology.edge_only_contacts(whole)
	findings.append(Finding.new(edge_only.is_empty(), "no edge-only contacts",
		"" if edge_only.is_empty()
			else "%d; an STL export would not be watertight" % edge_only.size(),
		edge_only))

	# Every part touches only its parent (SPEC section 3.1).
	var with_head := {}
	for name2 in PAINTABLE:
		with_head[name2] = parts[name2]
	if not head_cells.is_empty():
		with_head[BodyDef.HEAD_PART] = head_cells
	var names := with_head.keys()
	var strays: Array = []
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a := String(names[i])
			var b := String(names[j])
			if BodyDef.EXPECTED_PARENTS.get(a, "") == b \
					or BodyDef.EXPECTED_PARENTS.get(b, "") == a:
				continue
			if VoxelTopology.touches(with_head[a], with_head[b]):
				strays.append("%s touches %s" % [a, b])
	findings.append(Finding.new(strays.is_empty(), "parts touch only their parent",
		", ".join(strays)))

	# Every part must actually reach its parent, or the figure falls apart.
	var detached: Array = []
	for name3 in PAINTABLE:
		var parent := String(BodyDef.EXPECTED_PARENTS.get(name3, ""))
		if parent.is_empty():
			continue
		var parent_cells: Dictionary = head_cells if parent == BodyDef.HEAD_PART \
			else parts.get(parent, {})
		if parent_cells.is_empty():
			continue
		if not VoxelTopology.touches(parts[name3], parent_cells):
			detached.append("%s does not reach %s" % [name3, parent])
	findings.append(Finding.new(detached.is_empty(), "every part reaches its parent",
		", ".join(detached)))

	# The neck socket has to stay clear so any head still fits.
	var blocked := 0
	for x in range(10, 14):
		for y in range(10, 14):
			if owner_of.has(Vector3i(x, y, HeadDef.NECK_ROW)):
				blocked += 1
	findings.append(Finding.new(blocked == 0, "neck socket is clear",
		"" if blocked == 0 else "%d cells sit in the head's socket" % blocked))

	findings.append(Finding.new(_feet_on_floor(), "feet stand on z0",
		"lowest row is %d" % _lowest_row()))

	return findings


func _lowest_row() -> int:
	var lowest := 999
	for cell in owner_of.keys():
		lowest = mini(lowest, (cell as Vector3i).z)
	return 999 if lowest == 999 else lowest


func _feet_on_floor() -> bool:
	return _lowest_row() == 0


static func all_ok(findings: Array) -> bool:
	for finding in findings:
		if not (finding as Finding).ok:
			return false
	return true


static func failures(findings: Array) -> Array:
	var out: Array = []
	for finding in findings:
		if not (finding as Finding).ok:
			out.append(finding)
	return out


# --------------------------------------------------------------- JSON I/O ---

## Serialise in the body file schema, so an edited body loads through BodyDef
## exactly like a generated one.
func to_json() -> Dictionary:
	var measured := pivots()
	var out_parts := {}
	for name in BodyDef.EXPECTED_PARENTS.keys():
		var parent := String(BodyDef.EXPECTED_PARENTS[name])
		var cells: Dictionary = parts.get(name, {})
		out_parts[String(name)] = {
			"parent": null if parent.is_empty() else parent,
			"pivot": JsonIO.from_vec3(measured.get(name, Vector3.ZERO)),
			# The head's voxels stay empty: they come from the head library.
			"voxels": [] if name == BodyDef.HEAD_PART else JsonIO.voxel_list(cells),
		}

	var out_regions := {}
	if regions != null:
		for band_name in regions.bands.keys():
			var band: RegionMap.Band = regions.bands[band_name]
			out_regions[String(band_name)] = {
				"z0": band.z0, "z1": band.z1,
				"part": band.family, "trim": band.trim,
			}

	return {
		"grid": [VoxelAxes.GRID.x, VoxelAxes.GRID.y, VoxelAxes.GRID.z],
		"voxels_per_meter": int(VoxelAxes.VOXELS_PER_METRE),
		"facing": "-y",
		"mirror_axis_x": int(VoxelAxes.MIRROR_X),
		"sex": sex,
		"build": build,
		"head": "from the head library (head42_*.json); attaches at the neck socket, pivot (12, 12, 27)",
		"parts": out_parts,
		"regions": out_regions,
	}


## Snapshot for the undo stack. Cheaper and more exact than reserialising: no
## float formatting, no sorting, and the cells keep their Vector3i keys because
## this never reaches the disk. (An Array key would work but hashes by content
## on every lookup, which is a poor trade for thousands of cells.)
func snapshot() -> Dictionary:
	return {"sex": sex, "build": build, "cells": owner_of.duplicate()}


func restore(data: Dictionary) -> void:
	sex = String(data.get("sex", sex))
	build = String(data.get("build", build))
	for name in parts.keys():
		(parts[name] as Dictionary).clear()
	owner_of.clear()
	var cells: Dictionary = data.get("cells", {})
	for key in cells.keys():
		var cell: Vector3i = key
		var part_name := String(cells[key])
		if not parts.has(part_name):
			continue
		(parts[part_name] as Dictionary)[cell] = true
		owner_of[cell] = part_name
	_invalidate()


func save_to(path: String) -> String:
	var err := JsonIO.write_dict(path, to_json())
	if err.is_empty():
		source_path = path
	return err


## Reload through BodyDef, which is also the cheapest check that what was
## written is a valid body file.
static func load_from(path: String) -> BodyEdit:
	var body := BodyDef.load_from(path)
	if body == null:
		return null
	return BodyEdit.from_body(body)


## Build a BodyDef from the current state, for the preview to assemble.
func to_body_def() -> BodyDef:
	var def := BodyDef.new()
	def.id = id()
	def.sex = sex
	def.build = build
	def.grid = VoxelAxes.GRID
	def.regions = regions
	def.source_path = source_path
	var measured := pivots()
	for name in BodyDef.EXPECTED_PARENTS.keys():
		var parent := String(BodyDef.EXPECTED_PARENTS[name])
		var cells: Dictionary = {}
		if name != BodyDef.HEAD_PART:
			cells = (parts.get(name, {}) as Dictionary).duplicate()
		def.parts[String(name)] = BodyDef.PartDef.new(
			String(name), parent, measured.get(name, Vector3.ZERO), cells)
	def._order_hierarchy()
	return def
