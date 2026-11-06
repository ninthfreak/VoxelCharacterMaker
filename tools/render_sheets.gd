extends SceneTree

## Renders review sheets of assembled characters to PNG.
##
## CLAUDE.md asks for visual results whenever something changes how characters
## look, and a headless test cannot see a figure rendered inside-out. This is
## how to look at one without opening the editor.
##
## Needs a real GL context, so it does NOT run under --headless. On a machine
## with no display, use a virtual one:
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script res://tools/render_sheets.gd -- --out docs/renders
##
## Sheets written: the six bodies bare, the six dressed in the starter outfit,
## one body through every test pose, and the special items (hood and skirt).

const SETTLE_FRAMES := 4
const SHEET_WIDTH := 1920
const SHEET_MIN_HEIGHT := 430
const SHEET_MAX_HEIGHT := 1000

## Metres between figures, per sheet. A heavy body is a full metre across and
## a T-pose reaches about a metre each side, so these are wide on purpose:
## figures that overlap make a review sheet useless.
## Figures are placed at DECREASING x so they read left to right on the sheet.
## The camera is on -Z, so its right hand points along world -X -- the same
## fact the coordinate lock in tests/test_axes.gd pins down.
const SPACING_FIGURES := 1.12
const SPACING_POSES := 2.25

var _library := AssetLibrary.new()
var _wardrobe: Wardrobe = null
var _out_dir := "docs/renders"
var _sheets: Array = []
var _at := -1
var _frames := 0
var _scene: Node3D = null
var _written: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if String(args[i]) == "--out" and i + 1 < args.size():
			_out_dir = String(args[i + 1])

	if not _library.load_all():
		for e in _library.errors:
			printerr(e)
		quit(1)
		return
	_wardrobe = Wardrobe.create_default(_library)
	_add_specials()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir)
		if _out_dir.begins_with("res://") else _out_dir)

	_sheets = [
		{"name": "six_bodies", "kind": "bodies", "worn": []},
		{"name": "six_dressed", "kind": "bodies", "worn": _outfit("everyday")},
		{"name": "poses", "kind": "poses", "worn": _outfit("everyday")},
		{"name": "specials", "kind": "specials", "worn": []},
		# Capes and ponytails hang behind; a front view cannot show them.
		{"name": "specials_back", "kind": "specials", "worn": [], "back": true},
	]
	print("rendering %d sheet(s) to %s" % [_sheets.size(), _out_dir])
	# The first sheet is built on the first frame, not here: the window does
	# not exist yet during _initialize, so a size set now is silently clamped
	# and the first sheet comes out narrower than the rest.


func _process(_delta: float) -> bool:
	if _at < 0:
		_next_sheet()
		return false
	if _at >= _sheets.size():
		return true
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	_capture(String((_sheets[_at] as Dictionary)["name"]))
	_next_sheet()
	if _at >= _sheets.size():
		print("\nwrote:")
		for path in _written:
			print("  %s" % path)
		return true
	return false


func _next_sheet() -> void:
	_at += 1
	_frames = 0
	if _at >= _sheets.size():
		return
	if _scene != null:
		root.remove_child(_scene)
		_scene.free()
	_scene = Node3D.new()
	root.add_child(_scene)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color8(28, 31, 40)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	_scene.add_child(env)

	var sheet: Dictionary = _sheets[_at]
	var bounds := AABB()
	match String(sheet["kind"]):
		"bodies":
			bounds = _lay_out_bodies(sheet["worn"])
		"poses":
			bounds = _lay_out_poses(sheet["worn"])
		"specials":
			bounds = _lay_out_specials()

	# Orthographic, so every figure in a row is seen from exactly the same
	# direction. Under perspective the ones at the ends turn away from the
	# camera, which is no use at all for comparing six builds side by side.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 80.0
	_scene.add_child(camera)
	# Grow the framed box downward so the captions are not cropped off.
	bounds = bounds.merge(AABB(bounds.position + Vector3(0, -0.3, 0), bounds.size))

	# Shape the image to the content. A row of six T-posed figures is much
	# wider than it is tall, and a fixed box would be mostly empty.
	var content_aspect := bounds.size.x / maxf(0.01, bounds.size.y)
	var height := clampi(int(round(float(SHEET_WIDTH) / maxf(0.5, content_aspect))),
		SHEET_MIN_HEIGHT, SHEET_MAX_HEIGHT)
	var size := Vector2i(SHEET_WIDTH, height)
	root.size = size
	root.content_scale_size = size

	var centre := bounds.get_center()
	# Slightly off to one side and above: the baked shading is lit from the
	# viewer's upper left front, so a dead-on view hides half of what it does.
	var aspect := float(size.x) / float(size.y)
	camera.size = maxf(bounds.size.y, bounds.size.x / aspect) * 1.1
	# look_at_from_position, not position + look_at: look_at refuses while the
	# node is outside the tree, and this runs as the scene is being built.
	var toward := Vector3(-0.18, 0.1, -1.0)
	if bool(sheet.get("back", false)):
		toward = Vector3(0.18, 0.1, 1.0)
	var eye := centre + toward.normalized() * 12.0
	camera.look_at_from_position(eye, centre, Vector3.UP)


## A caption under each figure. A review sheet you have to count your way
## through is not much of a review sheet.
func _caption(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.0016
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color8(206, 214, 230)
	label.outline_size = 10
	label.outline_modulate = Color8(28, 31, 40)
	label.position = at + Vector3(0, -0.16, 0)
	_scene.add_child(label)


func _outfit(name: String) -> Array:
	return CharacterAssembler.worn_from_outfit(_wardrobe, name)


func _add_specials() -> void:
	var skirt := GarmentItem.create("render_skirt", "Skirt", "bottom")
	skirt.add_special("skirt")
	skirt.roles = ["cloth", "hem"]
	skirt.colourways = {"default": {"cloth": "moss", "hem": "ochre"}}
	_wardrobe.add_item(skirt)

	var hood := GarmentItem.create("render_hood", "Hood", "hat")
	hood.add_special("hood")
	hood.roles = ["cloth", "lining"]
	hood.colourways = {"default": {"cloth": "ink", "lining": "rust"}}
	_wardrobe.add_item(hood)


func _rig(body_id: String, head: String, expression: String, worn: Array,
		at: Vector3, pose: String = Poses.REST, features: Array = []) -> AABB:
	var request := CharacterAssembler.Request.make(_library, body_id, head, expression)
	request.wardrobe = _wardrobe
	request.worn = worn
	request.features = features
	request.eye_set_id = _wardrobe.first_eye_set_id()
	var assembled := CharacterAssembler.assemble(request)
	for w in assembled.warnings:
		printerr("%s: %s" % [body_id, w])

	var rig := CharacterRig.new()
	_scene.add_child(rig)
	rig.build(assembled)
	rig.apply_pose(pose)
	rig.position = at

	var bounds := rig.figure_aabb()
	bounds.position += at
	return bounds


func _lay_out_bodies(worn: Array) -> AABB:
	var ids := _library.body_ids()
	var total := AABB()
	var first := true
	for i in ids.size():
		var x := (float(ids.size() - 1) * 0.5 - float(i)) * SPACING_FIGURES
		var b := _rig(ids[i], "round", "neutral", worn, Vector3(x, 0, 0))
		var body := _library.body(ids[i])
		_caption(body.display_name() if body != null else ids[i], Vector3(x, 0, 0))
		total = b if first else total.merge(b)
		first = false
	return total


func _lay_out_poses(worn: Array) -> AABB:
	var poses := Poses.names()
	var total := AABB()
	var first := true
	for i in poses.size():
		var x := (float(poses.size() - 1) * 0.5 - float(i)) * SPACING_POSES
		var b := _rig("male_average", "round", "neutral", worn,
			Vector3(x, 0, 0), poses[i])
		_caption(Poses.display_name(poses[i]), Vector3(x, 0, 0))
		total = b if first else total.merge(b)
		first = false
	return total


## One figure per head shape, each showing a different special shape: a
## dress (bodice regions + skirt), a hooded cloak (cape + hood), a raised hood,
## a drawn beard with a crop, and a ponytail with a moustache.
func _lay_out_specials() -> AABB:
	var shapes := _library.head_shapes()
	var looks := [
		{"body": "female_average", "worn": [_w("dress"), _w("boots")], "features": [],
			"label": "dress", "pose": Poses.MID_STRIDE},
		{"body": "male_average", "worn": _outfit("travelling"),
			"features": [_w("short_crop")], "label": "hooded cloak", "pose": Poses.REST},
		{"body": "female_slim", "worn": [_w("render_hood"), _w("tunic")], "features": [],
			"label": "hood up", "pose": Poses.REST},
		{"body": "male_heavy", "worn": _outfit("everyday"),
			"features": [_w("short_crop"), _w("short_beard")], "label": "crop, beard",
			"pose": Poses.REST},
		{"body": "male_slim", "worn": _outfit("everyday"),
			"features": [_w("ponytail"), _w("moustache")], "label": "ponytail, moustache",
			"pose": Poses.REST},
	]
	var total := AABB()
	var first := true
	for i in shapes.size():
		var look: Dictionary = looks[i % looks.size()]
		var x := (float(shapes.size() - 1) * 0.5 - float(i)) * SPACING_FIGURES
		var b := _rig(String(look["body"]), shapes[i], "neutral", look["worn"],
			Vector3(x, 0, 0), String(look["pose"]), look["features"])
		_caption("%s head\n%s" % [shapes[i], look["label"]], Vector3(x, 0, 0))
		total = b if first else total.merge(b)
		first = false
	return total


func _w(item_id: String) -> Dictionary:
	return {"item": item_id, "colourway": _wardrobe.item(item_id).first_colourway()}


func _capture(name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		printerr("no viewport texture: a real GL context is needed (see the header)")
		return
	var image := texture.get_image()
	if image == null:
		printerr("viewport produced no image")
		return
	var path := "%s/%s.png" % [_out_dir.rstrip("/"), name]
	var err := image.save_png(path)
	if err != OK:
		printerr("could not write %s (error %d)" % [path, err])
		return
	_written.append(path)
