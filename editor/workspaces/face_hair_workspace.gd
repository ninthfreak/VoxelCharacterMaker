@tool
class_name FaceHairWorkspace
extends Workspace

## The Face & Hair tab: eyes, hair, and facial hair.
##
## These work like clothes -- regions, roles, colourways, special shapes -- but
## they are not optional and they live in their own area: a character always
## has one eye set, one hair style, one facial-hair choice. "None" is a hair
## style (bald) and a facial-hair choice (clean-shaven); it is not an absence.
##
## The head type can be changed here, because hair has to fit all five head
## shapes and their widths differ. The preview frames the head by default.

var body_id: String = "male_average"
var head_shape: String = "round"
var eye_set_id: String = ""
var eye_colourway: String = ""

var hair: ItemSelection = null
var facial_hair: ItemSelection = null

var _head_pick: OptionButton = null
var _body_pick: OptionButton = null
var _frame_pick: OptionButton = null
var _tabs: TabContainer = null
var _eyes_panel: EyeSetPanel = null
var _hair_garment: GarmentPanel = null
var _facial_garment: GarmentPanel = null


func title() -> String:
	return "Face & Hair"


func _build() -> void:
	view.fit_mode = PreviewView.Fit.HEAD
	view.allow_picking(true)
	view.region_picked.connect(_on_region_picked)

	hair = ItemSelection.make(editor, "hair")
	facial_hair = ItemSelection.make(editor, "facial_hair")
	# Start on something rather than nothing -- and before the panels are
	# built, since they read this state as they set themselves up.
	eye_set_id = editor.wardrobe.first_eye_set_id()
	var styles := editor.wardrobe.feature_ids("hair")
	if not styles.is_empty():
		hair.select(styles[0])
	hair.changed.connect(rebuild)
	facial_hair.changed.connect(rebuild)

	heading(side, "Face and hair")
	note(side, "Eyes, hair and facial hair work like clothes, but every character "
		+ "has exactly one of each. Change the head to check a style fits them all.")
	_head_pick = cycler(side, "Head", editor.library.head_shapes(), [],
		func(value: String) -> void:
			head_shape = value
			rebuild())
	_body_pick = picker(side, "Body", editor.library.body_ids(), body_labels(),
		func(value: String) -> void:
			body_id = value
			rebuild())
	_frame_pick = picker(side, "Show", ["head", "figure"], ["The head", "The whole figure"],
		func(value: String) -> void:
			view.fit_mode = PreviewView.Fit.HEAD if value == "head" else PreviewView.Fit.FIGURE
			view.camera.moved_by_user = false
			view.fit_view())

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_tabs)

	var eyes_box := _tab("Eyes")
	_eyes_panel = add_panel(EyeSetPanel.new(), null, eyes_box) as EyeSetPanel

	var hair_box := _tab("Hair")
	add_panel(ItemListPanel.new(), hair, hair_box)
	_hair_garment = GarmentPanel.new()
	_hair_garment.families = ["head"]
	add_panel(_hair_garment, hair, hair_box)
	add_panel(ColourPanel.new(), hair, hair_box)

	var facial_box := _tab("Facial hair")
	note(facial_box, "The head's regions are too coarse for a face: the lower band "
		+ "also holds the bottom of the eyes. So facial hair is usually a drawn "
		+ "shape anchored to the face, which wraps onto every jaw line.")
	add_panel(ItemListPanel.new(), facial_hair, facial_box)
	_facial_garment = GarmentPanel.new()
	_facial_garment.families = ["head"]
	add_panel(_facial_garment, facial_hair, facial_box)
	add_panel(ColourPanel.new(), facial_hair, facial_box)



func _tab(name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = name
	box.add_theme_constant_override("separation", 8)
	_tabs.add_child(box)
	return box


## Bring a sub-tab forward: "Eyes", "Hair" or "Facial hair".
func show_section(name: String) -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == name:
			_tabs.current_tab = i


func on_eyes_changed() -> void:
	rebuild()


func make_request() -> CharacterAssembler.Request:
	var request := CharacterAssembler.Request.make(editor.library, body_id, head_shape)
	request.wardrobe = editor.wardrobe
	request.eye_set_id = eye_set_id
	request.eye_colourway = eye_colourway
	request.features = hair.as_worn() + facial_hair.as_worn()
	# Wide open: no lid covers any of the drawing being edited, and the brow
	# still shows (raised, above the eye) against the hair.
	request.lids = "wide_open"
	return request


func refresh() -> void:
	if editor.wardrobe == null:
		return
	if editor.wardrobe.eye_set(eye_set_id) == null:
		eye_set_id = editor.wardrobe.first_eye_set_id()
	hair.validate()
	facial_hair.validate()
	select_value(_head_pick, head_shape)
	select_value(_body_pick, body_id)
	# The eye panel works on this tab's own state rather than a selection, so
	# nothing else tells it when that state has moved on.
	if _eyes_panel != null:
		_eyes_panel.refresh()


func status_text(assembled: CharacterAssembler.Assembled) -> String:
	var eyes := editor.wardrobe.eye_set(eye_set_id)
	var bits: Array[String] = [super.status_text(assembled)]
	bits.append("eyes: %s, wide open" % (eyes.name if eyes != null else "basic"))
	bits.append("hair: %s" % (hair.item().name if hair.item() != null else "none"))
	bits.append("facial hair: %s" % (facial_hair.item().name
		if facial_hair.item() != null else "none"))
	return "   |   ".join(bits)


func _on_region_picked(region: String) -> void:
	var title := _tabs.get_tab_title(_tabs.current_tab)
	if title == "Hair":
		_hair_garment.select_region(region)
	elif title == "Facial hair":
		_facial_garment.select_region(region)
	else:
		return
	editor.set_status_hint("Picked %s" % editor.library.region_map().label_for(region))
