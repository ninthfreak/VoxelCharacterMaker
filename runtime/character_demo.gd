@tool
class_name CharacterDemo
extends Node3D

## The game-side path, shown on its own.
##
## This is here to make one thing plain: the runtime and the editor assemble a
## character through exactly the same call. Nothing in this file knows about
## bulk generation, shading or meshing -- it asks CharacterAssembler for a
## figure and hands the result to a CharacterRig (SPEC.md section 8).

@export var body_id: String = "male_average"
@export var head_shape: String = "round"
@export var lids: String = EyeLids.DEFAULT
@export var outfit: String = "everyday"
@export var wardrobe_path: String = ""
@export var cycle_poses: bool = true
@export var seconds_per_pose: float = 1.6

var rig: CharacterRig = null
var library := AssetLibrary.new()
var wardrobe: Wardrobe = null

var _elapsed := 0.0
var _pose_index := 0


func _ready() -> void:
	if not library.load_all():
		push_error("asset library: %s" % ", ".join(library.errors))
		return

	if not wardrobe_path.is_empty():
		wardrobe = Wardrobe.load_from(wardrobe_path)
	if wardrobe == null:
		wardrobe = Wardrobe.create_default()

	rig = CharacterRig.new()
	rig.name = "Figure"
	add_child(rig)
	rebuild()

	if not Engine.is_editor_hint():
		_add_camera_and_light()


func rebuild() -> void:
	var request := CharacterAssembler.Request.make(library, body_id, head_shape)
	request.wardrobe = wardrobe
	request.lids = lids
	request.worn = CharacterAssembler.worn_from_outfit(wardrobe, outfit)
	var assembled := CharacterAssembler.assemble(request)
	for warning in assembled.warnings:
		push_warning(warning)
	rig.build(assembled)


func _process(delta: float) -> void:
	if not cycle_poses or rig == null or Engine.is_editor_hint():
		return
	_elapsed += delta
	if _elapsed < seconds_per_pose:
		return
	_elapsed = 0.0
	var names := Poses.names()
	_pose_index = (_pose_index + 1) % names.size()
	rig.apply_pose(names[_pose_index])


func _add_camera_and_light() -> void:
	# The figure faces -Z, so a camera on -Z sees its face (SPEC section 2).
	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.position = Vector3(0.9, 1.1, -2.6)
	add_child(camera)
	camera.look_at(Vector3(0, 0.85, 0), Vector3.UP)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(32, 36, 46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	environment.environment = env
	add_child(environment)
