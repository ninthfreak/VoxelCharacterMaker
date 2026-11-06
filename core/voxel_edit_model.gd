@tool
class_name VoxelEditModel
extends RefCounted

## The editing rules shared by the body editor and the head editor.
##
## Both are a set of named parts painted voxel by voxel, under two invariants
## that live here so no editor UI can break them:
##
##   one owner per cell   painting a cell into a part removes it from whatever
##                        part held it before
##   mirror pairs         every edit is applied to the mirrored cell too, into
##                        the mirrored part (upper_arm_L <-> upper_arm_R) or,
##                        for a centred part such as the head, the same part
##
## Subclasses decide which parts can be painted, which cells may be touched at
## all, and which half of a pair a cell belongs to.

signal changed

## part name -> Dictionary of Vector3i -> true
var parts: Dictionary = {}
## Vector3i -> part name, kept in step with `parts` so a paint is O(1)
var owner_of: Dictionary = {}
var source_path: String = ""


# ------------------------------------------------------------------- hooks --

## "body" or "head", for labels and the undo menu.
func kind() -> String:
	return "shape"


func display_name() -> String:
	return kind()


## Parts the editor offers as layers to paint with.
func paintable_parts() -> Array[String]:
	var out: Array[String] = []
	for name in parts.keys():
		out.append(String(name))
	return out


func can_paint(part_name: String) -> bool:
	return part_name in paintable_parts()


## Whether a cell may be changed at all. The grid, by default.
func cell_allowed(cell: Vector3i) -> bool:
	return VoxelAxes.in_grid(cell)


## Which part a paint with `part_name` actually lands in at `cell`.
func part_here(part_name: String, _cell: Vector3i) -> String:
	return part_name


## Where a part pivots, for the pivot marker. Subclasses measure or fix it.
func pivot_of(_part_name: String) -> Vector3:
	return Vector3(VoxelAxes.MIRROR_X, VoxelAxes.DEPTH_CENTRE, 0)


## An even-width part pivots on a voxel boundary, so 90-degree turns stay on
## the grid (SPEC section 3.2, the parity rule).
func pivot_on_boundary(part_name: String) -> bool:
	var x := pivot_of(part_name).x
	return is_equal_approx(x, roundf(x))


## Subclasses also provide validate(...) -> Array of BodyEdit.Finding. It is not
## declared here because each takes a different context (the body needs the
## head it will carry; the head needs the eye sets it must fit), and GDScript
## does not allow an override to narrow a parameter's type.


# --------------------------------------------------------------- the mirror --

## The part that holds the mirror image of a cell owned by `part_name`.
## A paired part mirrors into its opposite number; a centred part into itself.
##
## No cell sits on the mirror plane: it lies BETWEEN x = 11 and x = 12, so
## every cell has a distinct partner and there is no self-mirroring column.
static func mirror_part(part_name: String) -> String:
	if part_name.ends_with("_L"):
		return part_name.substr(0, part_name.length() - 2) + "_R"
	if part_name.ends_with("_R"):
		return part_name.substr(0, part_name.length() - 2) + "_L"
	return part_name


# ------------------------------------------------------------------ editing --

## Give a cell, and its mirror, to `part_name`. Returns true if anything moved.
func paint(cell: Vector3i, part_name: String) -> bool:
	if not can_paint(part_name):
		return false
	var here := part_here(part_name, cell)
	var touched := _set_owner(cell, here)
	touched = _set_owner(VoxelAxes.mirror_voxel(cell), mirror_part(here)) or touched
	if touched:
		_invalidate()
	return touched


## Remove a cell and its mirror from whatever parts hold them.
func erase(cell: Vector3i) -> bool:
	var touched := _clear_owner(cell)
	touched = _clear_owner(VoxelAxes.mirror_voxel(cell)) or touched
	if touched:
		_invalidate()
	return touched


## Paint a run of cells in one go, as a drag does, so listeners and any
## measuring fire once.
func paint_many(cells: Array, part_name: String) -> int:
	if not can_paint(part_name):
		return 0
	var n := 0
	for cell in cells:
		var c: Vector3i = cell
		var here := part_here(part_name, c)
		if _set_owner(c, here):
			n += 1
		if _set_owner(VoxelAxes.mirror_voxel(c), mirror_part(here)):
			n += 1
	if n > 0:
		_invalidate()
	return n


func erase_many(cells: Array) -> int:
	var n := 0
	for cell in cells:
		var c: Vector3i = cell
		if _clear_owner(c):
			n += 1
		if _clear_owner(VoxelAxes.mirror_voxel(c)):
			n += 1
	if n > 0:
		_invalidate()
	return n


func _set_owner(cell: Vector3i, part_name: String) -> bool:
	if not cell_allowed(cell) or not parts.has(part_name):
		return false
	var current: Variant = owner_of.get(cell)
	if current != null and String(current) == part_name:
		return false
	if current != null:
		(parts[current] as Dictionary).erase(cell)
	(parts[part_name] as Dictionary)[cell] = true
	owner_of[cell] = part_name
	return true


func _clear_owner(cell: Vector3i) -> bool:
	if not cell_allowed(cell):
		return false
	var current: Variant = owner_of.get(cell)
	if current == null:
		return false
	(parts[current] as Dictionary).erase(cell)
	owner_of.erase(cell)
	return true


func _invalidate() -> void:
	changed.emit()


func part_cells(part_name: String) -> Dictionary:
	return parts.get(part_name, {})


func owner_at(cell: Vector3i) -> String:
	var current: Variant = owner_of.get(cell)
	return "" if current == null else String(current)


func total_voxels() -> int:
	return owner_of.size()


# ----------------------------------------------------------------- undo ----

## Snapshot for the undo stack. The cells keep their Vector3i keys because
## this never reaches the disk.
func snapshot() -> Dictionary:
	return {"cells": owner_of.duplicate()}


func restore(data: Dictionary) -> void:
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
