@tool
class_name HeadEdit
extends VoxelEditModel

## One head shape, editable (SPEC.md section 4).
##
## Every head shares the neck socket (4x4 on the neck row, x10-13, y10-13),
## the pivot, the height and the eye box on the face plane (BodyLayout). Those
## are what let any hair, hat and face fit any head, so:
##
##   the neck row cannot be painted at all -- it is the socket, and a head with
##   a different socket would not sit on any body
##   the rest is reported by validate() rather than enforced, because a head
##   mid-edit is allowed to be wrong for a while
##
## The head is one centred part, so every edit mirrors within it.

const PART := "head"

var shape: String = "round"


static func from_head(head: HeadDef) -> HeadEdit:
	var edit := HeadEdit.new()
	edit.shape = head.shape
	edit.source_path = head.source_path
	edit.parts[PART] = {}
	for cell in head.cells.keys():
		(edit.parts[PART] as Dictionary)[cell] = true
		edit.owner_of[cell] = PART
	return edit


func kind() -> String:
	return "head"


func display_name() -> String:
	return "%s head" % shape


func paintable_parts() -> Array[String]:
	return [PART]


## Anything above the neck row. The socket row is locked.
func cell_allowed(cell: Vector3i) -> bool:
	return VoxelAxes.in_grid(cell) and cell.z > HeadDef.NECK_ROW


func pivot_of(_part_name: String) -> Vector3:
	return HeadDef.EXPECTED_PIVOT


## Check the head against what every head must share.
##
## eye_cells: every absolute cell some expression paints, from the shipped
## faces and the wardrobe's eye sets. Each must be a head voxel with nothing in
## front of it, or that expression would vanish (or be buried) on this head.
func validate(eye_cells: Dictionary = {}) -> Array:
	var findings: Array = []
	var cells: Dictionary = part_cells(PART)

	findings.append(BodyEdit.Finding.new(not cells.is_empty(), "has geometry",
		"%d voxels" % cells.size()))

	var asymmetric := VoxelTopology.asymmetric_cells(cells)
	findings.append(BodyEdit.Finding.new(asymmetric.is_empty(), "mirror-symmetric",
		"" if asymmetric.is_empty() else "%d cells without a partner" % asymmetric.size(),
		asymmetric))

	var pieces := VoxelTopology.components(cells)
	findings.append(BodyEdit.Finding.new(pieces == 1, "one connected piece",
		"" if pieces == 1 else "%d separate pieces" % pieces))

	var edge_only := VoxelTopology.edge_only_contacts(cells)
	findings.append(BodyEdit.Finding.new(edge_only.is_empty(), "no edge-only contacts",
		"" if edge_only.is_empty()
			else "%d; an STL export would not be watertight" % edge_only.size(),
		edge_only))

	# The socket: exactly the 4x4, nothing else on that row.
	var socket_ok := true
	var row := VoxelTopology.cells_in_row(cells, HeadDef.NECK_ROW)
	if row.size() != 16:
		socket_ok = false
	for cell in row:
		var c: Vector3i = cell
		if c.x < 10 or c.x > 13 or c.y < 10 or c.y > 13:
			socket_ok = false
	findings.append(BodyEdit.Finding.new(socket_ok, "neck socket is the shared 4x4",
		"%d cells on the neck row" % row.size()))

	# The shared height: hair and hats are drawn to sit on row 41.
	var top := -1
	var bottom := 999
	for cell2 in cells.keys():
		var z := (cell2 as Vector3i).z
		if z == HeadDef.NECK_ROW:
			continue
		top = maxi(top, z)
		bottom = mini(bottom, z)
	findings.append(BodyEdit.Finding.new(top == HeadDef.TOP_ROW, "top of the head is row %d" % HeadDef.TOP_ROW,
		"top row is %d; hair and hats are drawn to sit on %d" % [top, HeadDef.TOP_ROW]))
	findings.append(BodyEdit.Finding.new(bottom == HeadDef.NECK_ROW + 1,
		"head starts straight above the neck", "lowest row is %d" % bottom))

	# The eyes: every cell some expression paints must be on the face plane.
	var off_face: Array = []
	var buried: Array = []
	for cell3 in eye_cells.keys():
		var e: Vector3i = cell3
		if not cells.has(e):
			off_face.append(e)
			continue
		for y in range(0, e.y):
			if cells.has(Vector3i(e.x, y, e.z)):
				buried.append(e)
				break
	findings.append(BodyEdit.Finding.new(off_face.is_empty(), "every eye fits",
		"" if off_face.is_empty()
			else "%d eye cells fall off the face plane" % off_face.size(), off_face))
	findings.append(BodyEdit.Finding.new(buried.is_empty(), "nothing in front of the eyes",
		"" if buried.is_empty() else "%d eye cells are covered from the front" % buried.size(),
		buried))
	return findings


# --------------------------------------------------------------- JSON I/O ---

## In the head file schema, so it loads through HeadDef like a generated one.
func to_json() -> Dictionary:
	return {
		"shape": shape,
		"part": PART,
		"parent": "chest",
		"pivot": JsonIO.from_vec3(HeadDef.EXPECTED_PIVOT),
		"neck_socket": [[10, 13], [10, 13], HeadDef.NECK_ROW],
		"eye_box": {
			"left_x": [EyeSet.BOX_X0, EyeSet.BOX_X0 + EyeSet.BOX_W - 1],
			"right_x": [VoxelAxes.MIRROR_X_MAX - EyeSet.BOX_X0 - EyeSet.BOX_W + 1,
				VoxelAxes.MIRROR_X_MAX - EyeSet.BOX_X0],
			"z": [EyeSet.BOX_Z0, EyeSet.BOX_Z0 + EyeSet.BOX_H - 1],
			"plane_y": VoxelAxes.FACE_PLANE_Y,
		},
		"voxels": JsonIO.voxel_list(part_cells(PART)),
	}


func save_to(path: String) -> String:
	var err := JsonIO.write_dict(path, to_json())
	if err.is_empty():
		source_path = path
	return err


## A HeadDef from the current state, for the preview to assemble.
func to_head_def() -> HeadDef:
	var def := HeadDef.new()
	def.shape = shape
	def.source_path = source_path
	def.pivot = HeadDef.EXPECTED_PIVOT
	def.cells = part_cells(PART).duplicate()
	def.neck_socket = {"x": Vector2i(10, 13), "y": Vector2i(10, 13), "z": HeadDef.NECK_ROW}
	def.eye_box = {
		"left_x": Vector2i(EyeSet.BOX_X0, EyeSet.BOX_X0 + EyeSet.BOX_W - 1),
		"right_x": Vector2i(VoxelAxes.MIRROR_X_MAX - EyeSet.BOX_X0 - EyeSet.BOX_W + 1,
			VoxelAxes.MIRROR_X_MAX - EyeSet.BOX_X0),
		"z": Vector2i(EyeSet.BOX_Z0, EyeSet.BOX_Z0 + EyeSet.BOX_H - 1),
		"plane_y": VoxelAxes.FACE_PLANE_Y,
	}
	return def
