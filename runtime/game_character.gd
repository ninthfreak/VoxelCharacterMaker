@tool
class_name GameCharacter
extends Node3D

## A saved character in the game: built by its id from a wardrobe (CharacterDef), through the same assembler the
## editor uses, and shown by a LowpolyRig under this node. The node's origin is at the figure's feet.
##
##   setup(wardrobe, "farmer")        build a character (or set wardrobe_path and character_id, and add it to a tree)
##   set_expression("angry", "frown") eyelids and mouth; the clothes are not dressed again
##   set_pose("mid_stride")           a pose from runtime/poses.gd (stops any animation); the cloth follows its bones
##   play("walk")                     an animation from runtime/animations.gd, blended in from the pose it has
##   wear_outfit("travelling")        other clothes for this character, here only: the wardrobe is not changed
##
## The low-poly library (the bodies and heads) is read once and shared by every GameCharacter; so is a wardrobe read
## from a file.

signal built

## The wardrobe file the character is in; "" = the starter wardrobe (Wardrobe.create_default()).
@export var wardrobe_path: String = ""
## The saved character's id in that wardrobe.
@export var character_id: String = ""
@export var pose: String = Poses.REST
## An animation to play from the start ("" = none: hold the pose).
@export var animation: String = ""

var wardrobe: Wardrobe = null
## The character as built: a copy of the saved one, so what the game changes here (wear_outfit) stays here.
var definition: CharacterDef = null
var lids: String = EyeLids.DEFAULT
var mouth: String = Mouths.DEFAULT
var figure: LowpolyFigure = null
var rig: LowpolyRig = null
var animator: RigAnimator = null

var _dressed: Array = []

static var _library: LowpolyLibrary = null
static var _wardrobes: Dictionary = {}


## The bodies and heads, read once for every character.
static func library() -> LowpolyLibrary:
	if _library == null:
		var lib := LowpolyLibrary.new()
		if not lib.load_all():
			push_error("low-poly library: %s" % ", ".join(lib.errors))
			return null
		_library = lib
	return _library


## A wardrobe by its file, read once ("" = the starter wardrobe). Null if the file cannot be read.
static func load_wardrobe(path: String) -> Wardrobe:
	if not _wardrobes.has(path):
		var w := Wardrobe.create_default() if path.is_empty() else Wardrobe.load_from(path)
		if w == null:
			push_error("cannot read the wardrobe %s" % path)
			return null
		_wardrobes[path] = w
	return _wardrobes[path]


func _ready() -> void:
	if definition == null and not character_id.is_empty():
		setup(load_wardrobe(wardrobe_path), character_id)


## Build a saved character. Returns false, and builds nothing, if the wardrobe or the character is missing or its
## body or head is not in the library.
func setup(p_wardrobe: Wardrobe, p_character_id: String) -> bool:
	wardrobe = p_wardrobe
	character_id = p_character_id
	var who := wardrobe.character(character_id) if wardrobe != null else null
	if who == null:
		push_error("no character '%s' in the wardrobe" % character_id)
		return false
	definition = who.duplicate_as(who.id, who.name)
	lids = definition.lids
	mouth = definition.mouth
	return _dress()


## Eyelids (EyeLids) and mouth (Mouths). The figure is faced again; its clothes are not dressed again.
func set_expression(p_lids: String, p_mouth: String = "") -> void:
	lids = p_lids
	if not p_mouth.is_empty():
		mouth = p_mouth
	if not _dressed.is_empty():
		_show(_request())


func set_pose(p_pose: String) -> void:
	pose = p_pose
	if animator != null:
		animator.stop()
	if rig != null and rig.figure != null:
		rig.apply_pose(pose)


## Play an animation (Animations), blending in from the pose the figure has over `crossfade` seconds.
func play(clip_name: String, crossfade: float = 0.2) -> void:
	animation = clip_name
	if animator != null:
		animator.play(clip_name, crossfade)


## Stop the animation; the figure keeps the pose it has.
func stop() -> void:
	animation = ""
	if animator != null:
		animator.stop()


## Other clothes, for this character here: Array of {"item": id, "colourway": name}.
func wear(worn: Array) -> bool:
	if definition == null:
		return false
	definition.worn = worn.duplicate(true)
	return _dress()


func wear_outfit(outfit_name: String) -> bool:
	if wardrobe == null or not wardrobe.outfit_names().has(outfit_name):
		push_error("no outfit '%s' in the wardrobe" % outfit_name)
		return false
	return wear(wardrobe.outfit(outfit_name))


## Build again from the saved character, as the wardrobe has it now (after the wardrobe was changed).
func reload() -> bool:
	return setup(wardrobe, character_id)


func _request() -> CharacterRequest:
	var request := definition.make_request(wardrobe)
	request.lids = lids
	request.mouth = mouth
	return request


func _dress() -> bool:
	var lib := library()
	if lib == null:
		return false
	var request := _request()
	_dressed = LowpolyAssembler.dress(lib, request)
	if _dressed.is_empty():
		push_error("%s: no low-poly body '%s' or head '%s'" % [character_id, request.body_id, request.head_shape])
		return false
	return _show(request)


func _show(request: CharacterRequest) -> bool:
	figure = LowpolyAssembler.face_on(library(), _dressed, request)
	for warning in figure.warnings:
		push_warning("%s: %s" % [character_id, warning])
	if rig == null:
		rig = LowpolyRig.new()
		rig.name = "Figure"
		add_child(rig)
		animator = RigAnimator.make(rig)
		add_child(animator)
	var playing := animator.playing
	rig.build(figure, rig.current_pose() if playing else Poses.get_pose(pose))
	if not playing and not animation.is_empty():
		animator.play(animation, 0.0)
	built.emit()
	return true
