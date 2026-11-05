@tool
class_name FigurePanel
extends EditorPanel

## Preview controls: any of the 6 bodies x 5 heads x expressions, plus the test
## poses that are the real check on part splits and pivots (SPEC.md section 8).

var _body: OptionButton = null
var _head: OptionButton = null
var _expression: OptionButton = null
var _pose: OptionButton = null
var _eye: ColorPickerButton = null
var _multiplier: CheckBox = null
var _counts: Label = null


func _build() -> void:
	var figure := section("Figure")

	_body = labelled(figure, "Body", OptionButton.new()) as OptionButton
	_body.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		editor.body_id = option_value(_body)
		editor.rebuild())

	_head = labelled(figure, "Head", OptionButton.new()) as OptionButton
	_head.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		editor.head_shape = option_value(_head)
		editor.rebuild())

	_expression = labelled(figure, "Expression", OptionButton.new()) as OptionButton
	_expression.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		editor.expression = option_value(_expression)
		editor.rebuild())

	hint(figure, "Every head shares the neck socket and eye box, so any face "
		+ "and any wardrobe item fits any head.")

	var pose_box := section("Pose")
	_pose = labelled(pose_box, "Pose", OptionButton.new()) as OptionButton
	_pose.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		editor.pose_name = option_value(_pose)
		editor.rig.apply_pose(editor.pose_name))
	hint(pose_box, "Poses rotate the rigid parts about their pivots. Gaps and "
		+ "overlaps at bent joints are expected: there are no joint caps.")

	var look := section("Look")
	_eye = labelled(look, "Eye colour", ColorPickerButton.new()) as ColorPickerButton
	_eye.edit_alpha = false
	_eye.color_changed.connect(func(c: Color) -> void:
		if is_guarded():
			return
		editor.eye_colour = c
		editor.rebuild())

	_multiplier = CheckBox.new()
	_multiplier.text = "Shade faces by orientation"
	_multiplier.toggled.connect(func(on: bool) -> void:
		if is_guarded():
			return
		editor.use_face_multiplier = on
		editor.rebuild())
	look.add_child(_multiplier)
	hint(look, "Multiplies each voxel face by how it is turned (top brightest, "
		+ "bottom darkest) on top of the baked light/mid/dark tone.")

	var info := section("This figure")
	_counts = Label.new()
	_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_counts)
	if editor != null:
		editor.figure_changed.connect(_refresh_counts)


func refresh() -> void:
	if editor == null or editor.library == null:
		return
	begin_guard()

	var body_ids := editor.library.body_ids()
	var body_labels: Array = []
	for id in body_ids:
		body_labels.append((editor.library.body(id) as BodyDef).display_name())
	fill_options(_body, body_ids, editor.body_id, body_labels)

	fill_options(_head, editor.library.head_shapes(), editor.head_shape)

	var expressions := editor.library.expression_names()
	var expression_labels: Array = []
	for name in expressions:
		expression_labels.append(String(name).replace("_", " "))
	fill_options(_expression, expressions, editor.expression, expression_labels)

	var poses := Poses.names()
	var pose_labels: Array = []
	for pose in poses:
		pose_labels.append(Poses.display_name(pose))
	fill_options(_pose, poses, editor.pose_name, pose_labels)

	_eye.color = editor.eye_colour
	_multiplier.button_pressed = editor.use_face_multiplier
	end_guard()
	_refresh_counts()


func _refresh_counts() -> void:
	if _counts == null or editor == null or editor.rig == null:
		return
	var assembled := editor.rig.assembled
	if assembled == null:
		_counts.text = ""
		return
	var body := assembled.body
	var skin := 0
	var garment := 0
	var face := 0
	for name in assembled.order:
		var part := assembled.part(String(name))
		for cell in part.cells.keys():
			match int(part.sources.get(cell, CharacterAssembler.Source.SKIN)):
				CharacterAssembler.Source.GARMENT: garment += 1
				CharacterAssembler.Source.FACE: face += 1
				_: skin += 1
	_counts.text = "%d voxels: %d skin, %d garment, %d eye.\n%d parts, %d quads." % [
		assembled.total_voxels(), skin, garment, face,
		assembled.order.size(), editor.rig.total_faces(),
	]
	if body != null:
		_counts.text += "\nBody file holds %d voxels before the head." % body.total_voxels()
