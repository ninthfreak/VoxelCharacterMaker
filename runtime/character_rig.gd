@tool
class_name CharacterRig
extends Node3D

## An assembled character as a Node3D tree (SPEC.md section 9).
##
## Each part is a mesh under a Node3D sitting at that part's pivot, parented per
## SPEC 3.1. Animation rotates the pivots; there is no skinning. Cloth panels
## are garment-owned parts in the same tree, driven by the rule their generator
## declared (SPEC 7.4).
##
## The rig's own origin is at the figure's feet on the ground: a pivot at
## z = 0 maps to y = 0, so a character can be dropped straight onto a floor.

signal rebuilt

## part name -> Node3D at that part's pivot
var joints: Dictionary = {}
## part name -> MeshInstance3D
var mesh_instances: Dictionary = {}

var assembled: CharacterAssembler.Assembled = null
var use_face_multiplier: bool = true

var _material: StandardMaterial3D = null
var _pose: Dictionary = {}


func _init() -> void:
	_material = Mesher.make_material()


## Replace the whole figure. Call after any change to body, head, face or
## worn items; the pose is re-applied so a rebuild does not snap back to rest.
func build(p_assembled: CharacterAssembler.Assembled) -> void:
	assembled = p_assembled
	_clear()
	if assembled == null:
		return

	for name in assembled.order:
		var part := assembled.part(name)
		if part == null:
			continue

		var joint := Node3D.new()
		joint.name = name

		var parent_node: Node3D = self
		var parent_part: CharacterAssembler.Part = null
		if not part.parent.is_empty() and joints.has(part.parent):
			parent_node = joints[part.parent]
			parent_part = assembled.part(part.parent)

		# Joints are positioned relative to their parent's pivot, so rotating a
		# parent carries every child with it.
		#
		# The two cases are NOT the same conversion. A root joint's pivot is a
		# POINT in the rig's own space, so it takes the full affine mapping. A
		# child's position is the OFFSET between two pivots, so only the linear
		# part applies -- the translation cancels between them. Mapping
		# Vector3.ZERO as a stand-in parent pivot instead adds that translation
		# back in and shifts the whole figure half a metre off-centre.
		if parent_part == null:
			joint.position = VoxelAxes.pivot_to_godot(part.pivot)
		else:
			joint.position = VoxelAxes.direction_to_godot(part.pivot - parent_part.pivot)
		parent_node.add_child(joint)
		joints[name] = joint

		var mesh := Mesher.build_part(part, part.pivot, use_face_multiplier)
		if mesh != null:
			var instance := MeshInstance3D.new()
			instance.name = "%s_mesh" % name
			instance.mesh = mesh
			instance.material_override = _material
			joint.add_child(instance)
			mesh_instances[name] = instance

	if not _pose.is_empty():
		apply_pose_values(_pose)
	rebuilt.emit()


func _clear() -> void:
	# free(), not queue_free(): the children are detached first and nothing else
	# holds them, and a headless test run has no idle frame to flush a queue.
	for child in get_children():
		remove_child(child)
		child.free()
	joints.clear()
	mesh_instances.clear()


## Apply a named pose from Poses.
func apply_pose(pose_name: String) -> void:
	apply_pose_values(Poses.get_pose(pose_name))


## Apply explicit Euler angles in degrees: part name -> Vector3.
func apply_pose_values(pose: Dictionary) -> void:
	_pose = pose.duplicate()
	if assembled == null:
		return
	for name in joints.keys():
		var joint: Node3D = joints[name]
		var part := assembled.part(String(name))
		if part != null and part.is_panel():
			joint.rotation_degrees = Poses.panel_rotation(part.driver, _pose)
		else:
			joint.rotation_degrees = pose.get(name, Vector3.ZERO)


func current_pose() -> Dictionary:
	return _pose.duplicate()


func clear_pose() -> void:
	apply_pose_values({})


## Rotate one joint, for the editor's pivot checks.
func set_joint_rotation(part_name: String, euler_degrees: Vector3) -> void:
	_pose[part_name] = euler_degrees
	apply_pose_values(_pose)


func joint(part_name: String) -> Node3D:
	return joints.get(part_name, null) as Node3D


## Where a part's pivot ends up in world space, for pivot markers in the editor.
func pivot_global_position(part_name: String) -> Vector3:
	var node := joint(part_name)
	if node == null:
		return Vector3.ZERO
	return node.global_position


func total_voxels() -> int:
	return assembled.total_voxels() if assembled != null else 0


func total_faces() -> int:
	if assembled == null:
		return 0
	var n := 0
	for name in assembled.order:
		n += Mesher.count_faces(assembled.part(String(name)))
	return n


## Axis-aligned bounds of the figure in Godot space, for framing a camera.
func figure_aabb() -> AABB:
	if assembled == null:
		return AABB()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var any := false
	for name in assembled.order:
		var part := assembled.part(String(name))
		if part == null:
			continue
		for cell in part.cells.keys():
			var c: Vector3i = cell
			var p := VoxelAxes.voxel_centre_to_godot(c)
			lo = lo.min(p)
			hi = hi.max(p)
			any = true
	if not any:
		return AABB()
	var pad := Vector3.ONE * (VoxelAxes.VOXEL_SIZE * 0.5)
	return AABB(lo - pad, (hi + pad) - (lo - pad))


## Collision shape per SPEC section 9: one capsule, independent of pose, so arms
## and hair may poke through walls and nothing re-cooks when a limb moves.
static func make_collision_shape() -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	return shape
