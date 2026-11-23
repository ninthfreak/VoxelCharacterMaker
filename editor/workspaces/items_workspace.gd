@tool
class_name ItemsWorkspace
extends Workspace

## The Items tab: held items -- weapons, shields, tools, potions -- built from simple parts placed, turned and sized
## (HeldItemShape; SPEC.md section 7.5), with the grip that says how a hand holds them.
##
## The preview shows the item on its own, standing on a grid of one-unit squares, the chosen part's edges drawn over
## everything and the grip marked; or in a character's right or left hand, in any pose or animation.

const SHOW_ITEM := "item"
const SHOW_RIGHT := "R"
const SHOW_LEFT := "L"

var body_id: String = "male_average"
var head_shape: String = "round"
var pose: String = Poses.REST
var show_mode: String = SHOW_ITEM
## The part being edited: its number in the item's parts (-1 for none).
var part: int = 0
var held: ItemSelection = null

var _show_pick: OptionButton = null
var _body_pick: OptionButton = null
var _pose_pick: OptionButton = null
var _figure_box: VBoxContainer = null
var _tabs: TabContainer = null
var _list: ItemListPanel = null
var _parts: PartsPanel = null
var _grip: GripPanel = null


func title() -> String:
	return "Items"


func _build() -> void:
	held = ItemSelection.make(editor, GarmentItem.HELD)
	held.changed.connect(func() -> void:
		part = 0
		rebuild())
	view.part_picked.connect(func(index: int) -> void:
		show_section("Item")
		select_part(index))

	heading(side, "Held items")
	note(side, "Weapons, shields, tools, potions: built from simple parts. Double-click a part in the view to choose it.")
	_show_pick = picker(side, "Show", [SHOW_ITEM, SHOW_RIGHT, SHOW_LEFT],
		["The item alone", "In the right hand", "In the left hand"], func(value: String) -> void:
			show_mode = value
			_figure_box.visible = show_mode != SHOW_ITEM
			camera_refit()
			rebuild())
	_figure_box = VBoxContainer.new()
	_figure_box.add_theme_constant_override("separation", 8)
	side.add_child(_figure_box)
	_body_pick = cycler(_figure_box, "Body", editor.library.body_ids(), body_labels(),
		func(value: String) -> void:
			body_id = value
			rebuild())
	_pose_pick = picker(_figure_box, "Pose", Poses.names(), pose_labels(),
		func(value: String) -> void:
			pose = value
			view.set_pose(value))
	figure_controls(_figure_box, "In a hand the character wears the everyday outfit. The item is always flat-shaded.")
	_figure_box.visible = false

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_tabs)
	var item_box := _tab("Item")
	_list = ItemListPanel.new()
	add_panel(_list, held, item_box)
	_parts = add_panel(PartsPanel.new(), held, item_box) as PartsPanel
	_grip = add_panel(GripPanel.new(), held, _tab("Grip")) as GripPanel
	add_panel(ColourPanel.new(), held, _tab("Colours"))
	start_fresh()


## A new or opened wardrobe: its first held item.
func start_fresh() -> void:
	var ids := editor.wardrobe.held_ids()
	held.select(ids[0] if not ids.is_empty() else "")
	part = 0


func _tab(name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = name
	box.add_theme_constant_override("separation", 8)
	_tabs.add_child(box)
	return box


func show_section(name: String) -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == name:
			_tabs.current_tab = i


## Choose a part to edit (and show it chosen).
func select_part(index: int) -> void:
	part = index
	_parts.refresh()
	_grip.refresh()
	rebuild()


func camera_refit() -> void:
	view.camera.moved_by_user = false


func make_request() -> CharacterRequest:
	var request := CharacterRequest.make(body_id, head_shape, editor.wardrobe)
	request.worn = editor.wardrobe.outfit("everyday") if editor.wardrobe.outfit_names().has("everyday") else []
	var hair_ids := editor.wardrobe.feature_ids("hair")
	if not hair_ids.is_empty():
		request.features = [{"item": hair_ids[0], "colourway": editor.wardrobe.item(hair_ids[0]).first_colourway()}]
	var it := held.item()
	if it != null and show_mode != SHOW_ITEM:
		request.held = [{"item": it.id, "colourway": held.colourway, "side": show_mode}]
	return request


func rebuild() -> void:
	if show_mode != SHOW_ITEM:
		super.rebuild()
		return
	if editor == null or editor.library == null:
		return
	if not is_visible_in_tree():
		_stale = true
		return
	_stale = false
	var it := held.item()
	if it == null:
		view.show_item([], -1, {}, {})
		editor.show_status_line(self, "No held item chosen: make one with New (Item, below).", "")
		return
	var request := make_request()
	var colours := {}
	for role in it.roles:
		colours[role] = CharacterRequest.role_tones(request, it.id, held.colourway, role)[1]
	var polys := HeldItemShape.polygons(it, colours)
	view.show_item(polys, part, it.grip, it.second_grip)
	editor.show_status_line(self, "%s   |   %d part%s, %d polygons   |   the item alone%s" % [it.name, it.parts.size(),
		"" if it.parts.size() == 1 else "s", polys.size(), _part_text(it)], "")


func _part_text(it: GarmentItem) -> String:
	if part < 0 or part >= it.parts.size():
		return ""
	return "   |   part %d chosen (its edges in white)" % (part + 1)


func status_extra() -> String:
	var it := held.item()
	return "   |   %s in the %s hand" % [it.name if it != null else "nothing", "right" if show_mode == SHOW_RIGHT else "left"]


func refresh() -> void:
	if editor.wardrobe == null:
		return
	held.validate()
	var it := held.item()
	if it == null:
		part = -1
	elif part < 0 or part >= it.parts.size():
		part = 0 if not it.parts.is_empty() else -1
	refresh_figure_controls()
	body_id = refill_bodies(_body_pick, body_id)
	select_value(_pose_pick, pose)
	select_value(_show_pick, show_mode)
	_figure_box.visible = show_mode != SHOW_ITEM
