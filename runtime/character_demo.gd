@tool
class_name CharacterDemo
extends Node3D

## The game-side path, shown on its own: saved characters, each a GameCharacter built by its id from the wardrobe,
## standing in a row, walking on the spot (or, with no animation, going through the test poses).
##
## This is here to make one thing plain: the game builds a character through exactly the same calls as the editor.
## Nothing in this file knows about dressing or cloth -- GameCharacter asks LowpolyAssembler for a figure and hands
## it to a LowpolyRig (SPEC.md section 9).

## The wardrobe file; "" = the starter wardrobe.
@export var wardrobe_path: String = ""
## The characters to show, by id; empty = every saved character in the wardrobe.
@export var character_ids: Array[String] = []
@export var spacing: float = 0.9
## An animation every character plays (Animations); "" = cycle the test poses instead.
@export var animation: String = Animations.WALK
@export var cycle_poses: bool = true
@export var seconds_per_pose: float = 1.6

var characters: Array[GameCharacter] = []

var _elapsed := 0.0
var _pose_index := 0


func _ready() -> void:
	var wardrobe := GameCharacter.load_wardrobe(wardrobe_path)
	if wardrobe == null:
		return
	var ids: Array[String] = character_ids if not character_ids.is_empty() else wardrobe.character_ids()
	for i in ids.size():
		var who := GameCharacter.new()
		who.name = ids[i]
		who.position = Vector3((i - 0.5 * (ids.size() - 1)) * spacing, 0, 0)
		add_child(who)
		if who.setup(wardrobe, ids[i]):
			characters.append(who)
			if not animation.is_empty():
				who.play(animation, 0.0)
				who.animator.time = 0.37 * i               # out of step with each other
	if not Engine.is_editor_hint():
		_add_camera_and_light(ids.size())


func _process(delta: float) -> void:
	if not animation.is_empty() or not cycle_poses or characters.is_empty() or Engine.is_editor_hint():
		return
	_elapsed += delta
	if _elapsed < seconds_per_pose:
		return
	_elapsed = 0.0
	var names := Poses.names()
	_pose_index = (_pose_index + 1) % names.size()
	for who in characters:
		who.set_pose(names[_pose_index])


func _add_camera_and_light(count: int) -> void:
	# The figures face -Z, so a camera on -Z sees their faces (SPEC section 2).
	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.position = Vector3(0.6, 1.1, -2.2 - 0.9 * count)
	add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0), Vector3.UP)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color8(32, 36, 46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	environment.environment = env
	add_child(environment)
