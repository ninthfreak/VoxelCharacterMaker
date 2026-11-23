@tool
class_name ItemsWorkspace
extends Workspace

## The Items tab: held items -- weapons, shields, tools, potions -- built from simple parts placed, turned and sized
## (HeldItemShape; SPEC.md section 7.5), with the grip that says how a hand holds them.
##
## The item is put together by hand in the view (ItemStage): click a part to choose it, drag it to move it, pull the
## squares on its sides to size it, the ring to turn it; the shape buttons above the view add a part. The panels'
## numbers follow, and are there for fine work. On the Grip sub-tab the view moves and turns the grip instead.
## Copy, cut and paste a part with Ctrl+C, Ctrl+X, Ctrl+V, in one item or from one to another.
##
## Kept small on purpose (owner): an item is a handful of parts and is small in the game, so there is one snap, one
## way to do each thing, and nothing for detail finer than a quarter unit.
##
## Show: the item alone, or in a character's right or left hand, in any pose.

const SHOW_ITEM := "item"
const SHOW_RIGHT := "R"
const SHOW_LEFT := "L"
const HINT_PARTS := "Drag a part to move it.   Pull a square to size it.   Drag the ring to turn it.   " \
	+ "Drag empty space to turn the view."
const HINT_GRIP := "Drag the hand to move the grip.   Drag the ring to turn it.   Drag empty space to turn the view."
const HINT_KEYS := "Arrow keys: move a quarter unit   |   Ctrl+C copy   |   Ctrl+V paste   |   Ctrl+X cut   |   " \
	+ "Delete   |   Ctrl+Z undo"
const CENTRE_TIPS: Array[String] = ["Put the chosen part on the item's middle, across (x 0)",
	"Put the chosen part on the item's middle, front to back (y 0)",
	"Put the chosen part at the item's own height 0 (z 0), where the grip starts"]

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
var _hint: Label = null
var _keys: Label = null
## The part copied or cut (Ctrl+C, Ctrl+X): pasted into this item or another.
var _clipboard: Dictionary = {}
var _hand_body := ""
var _shown_id := ""


func title() -> String:
	return "Items"


func _build() -> void:
	held = ItemSelection.make(editor, GarmentItem.HELD)
	held.changed.connect(func() -> void:
		part = 0
		rebuild())
	var stage := view.item_stage
	stage.part_chosen.connect(select_part)
	stage.edited.connect(_on_dragging)
	stage.edit_finished.connect(func(label: String, merge: bool) -> void:
		editor.commit(label, self, merge)
		edited.emit(self))
	stage.delete_requested.connect(func() -> void: _parts._on_delete())
	_build_toolbar()

	heading(side, "Held items")
	note(side, "Weapons, shields, tools, potions: built from simple parts, by hand in the view. The numbers below "
		+ "follow, for fine work.")
	_show_pick = picker(side, "Show", [SHOW_ITEM, SHOW_RIGHT, SHOW_LEFT],
		["The item alone (edit it here)", "In the right hand", "In the left hand"], func(value: String) -> void:
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
	_tabs.tab_changed.connect(func(_index: int) -> void: rebuild())      # the Grip sub-tab: the view edits the grip
	start_fresh()


## Above the view: a button for each kind of part, one to centre the chosen part on each axis, and what the mouse
## and the keys do.
func _build_toolbar() -> void:
	var bar := VBoxContainer.new()
	var row := HFlowContainer.new()
	var add := Label.new()
	add.text = "Add a part:"
	row.add_child(add)
	for kind in HeldItemShape.KINDS:
		var button := Button.new()
		button.text = HeldItemShape.kind_name(kind)
		button.tooltip_text = "Add a %s on top of the item" % HeldItemShape.kind_label(kind).to_lower()
		button.pressed.connect(add_part.bind(kind))
		row.add_child(button)
	row.add_child(VSeparator.new())
	var centre := Label.new()
	centre.text = "Centre it on:"
	row.add_child(centre)
	for axis in 3:
		var button := Button.new()
		button.text = " %s " % ItemStage.AXES[axis]
		button.tooltip_text = CENTRE_TIPS[axis]
		button.pressed.connect(centre_part.bind(axis))
		row.add_child(button)
	bar.add_child(row)
	_hint = Label.new()
	_hint.text = HINT_PARTS
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	_keys = Label.new()
	_keys.text = HINT_KEYS
	_keys.add_theme_color_override("font_color", Color8(160, 168, 184))
	bar.add_child(_keys)
	view.add_item_toolbar(bar)


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


## Whether the view edits the grip (the Grip sub-tab is showing) rather than the parts.
func stage_mode() -> int:
	return ItemStage.Mode.GRIP if _tabs != null and _tabs.get_tab_title(_tabs.current_tab) == "Grip" \
		else ItemStage.Mode.PARTS


## Choose a part to edit (and show it chosen).
func select_part(index: int) -> void:
	part = index
	_parts.refresh()
	_grip.refresh()
	rebuild()


## Add a part of this kind on top of the item, chosen, ready to be dragged into place. With no item yet, a new item
## is made of it.
func add_part(kind: String) -> void:
	if show_mode != SHOW_ITEM:
		return
	var it := held.item()
	if it == null:
		_list._on_new()
		it = held.item()
		if it == null:
			return
		it.parts.clear()
	var fresh := HeldItemShape.new_part(kind, it.roles[0] if not it.roles.is_empty() else GarmentItem.DEFAULT_ROLE)
	var top := -INF
	for q in HeldItemShape.polygons(it, {}):
		var flat: PackedFloat64Array = q["pts"]
		for k in flat.size() / 3:
			top = maxf(top, flat[3 * k + 2])
	if top > -INF:
		fresh["position"] = [0.0, 0.0, ceilf((top + 0.5 * float(fresh["size"][2])) / ItemStage.SNAP - 1e-6) * ItemStage.SNAP]
	it.parts.append(fresh)
	part = it.parts.size() - 1
	show_section("Item")
	editor.commit("Add %s" % HeldItemShape.kind_name(kind).to_lower(), self)
	edited.emit(self)
	view.fit_view()                                    # the new part is on top: bring it into the view


## Put the chosen part on the item's middle along one axis (0 x, 1 y, 2 z): that place becomes 0.
func centre_part(axis: int) -> void:
	var it := held.item()
	if show_mode != SHOW_ITEM or it == null or part < 0 or part >= it.parts.size():
		return
	var p: Dictionary = it.parts[part]
	if float(p["position"][axis]) == 0.0:
		return
	var place: Array = (p["position"] as Array).duplicate()
	place[axis] = 0.0
	p["position"] = place
	editor.commit("Centre part %d on %s" % [part + 1, ItemStage.AXES[axis]], self)
	edited.emit(self)


## Copy the chosen part (Ctrl+C), to paste into this item or another.
func copy_part() -> bool:
	var it := held.item()
	if it == null or part < 0 or part >= it.parts.size():
		return false
	_clipboard = (it.parts[part] as Dictionary).duplicate(true)
	editor.set_status_hint("Copied part %d. Ctrl+V pastes it." % (part + 1))
	return true


## Cut the chosen part (Ctrl+X): copied, then removed.
func cut_part() -> bool:
	if not copy_part():
		return false
	_parts._on_delete()
	return true


## Paste the part copied (Ctrl+V), chosen. Where a part already is exactly where it would go (its own original, most
## often) it is put 1 unit to the side, so that it is seen to be there.
func paste_part() -> bool:
	var it := held.item()
	if it == null or _clipboard.is_empty():
		return false
	var fresh := HeldItemShape.clean_part(_clipboard, it.roles[0] if not it.roles.is_empty() else GarmentItem.DEFAULT_ROLE)
	if not it.roles.is_empty() and not it.roles.has(String(fresh["role"])):
		fresh["role"] = it.roles[0]
	var taken := true
	while taken:
		taken = false
		for p in it.parts:
			if (p as Dictionary)["position"] == fresh["position"]:
				fresh["position"][0] = float(fresh["position"][0]) + 1.0
				taken = true
	var at := clampi(part + 1, 0, it.parts.size())
	it.parts.insert(at, fresh)
	part = at
	editor.commit("Paste part", self)
	edited.emit(self)
	editor.set_status_hint("Pasted as part %d." % (at + 1))
	return true


func handle_shortcut(key: InputEventKey) -> bool:
	if show_mode != SHOW_ITEM:
		return false
	match key.keycode:
		KEY_C: return copy_part()
		KEY_X: return cut_part()
		KEY_V: return paste_part()
	return false


## A part is being dragged in the view: the numbers follow (no undo step until it is let go).
func _on_dragging() -> void:
	_parts.refresh()
	_grip.refresh()
	_show_status()


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
	var stage := view.item_stage
	if _hand_body != body_id:
		stage.hand = ItemStage.hand_of(editor.library, body_id)
		_hand_body = body_id
	var mode := stage_mode()
	_hint.text = HINT_GRIP if mode == ItemStage.Mode.GRIP else HINT_PARTS
	_keys.visible = mode == ItemStage.Mode.PARTS
	var it := held.item()
	if it == null:
		_shown_id = ""
		view.show_item(null, {}, -1, mode)
		_show_status()
		return
	var request := make_request()
	var colours := {}
	for role in it.roles:
		colours[role] = CharacterRequest.role_tones(request, it.id, held.colourway, role)[1]
	view.show_item(it, colours, part, mode, it.id != _shown_id)
	_shown_id = it.id
	_show_status()


func _show_status() -> void:
	var it := held.item()
	if it == null:
		editor.show_status_line(self, "No held item yet: press one of the Add a part buttons above the view, or New.", "")
		return
	var chosen := ""
	if stage_mode() == ItemStage.Mode.GRIP:
		chosen = "   |   the grip"
	elif part >= 0 and part < it.parts.size():
		var p: Dictionary = it.parts[part]
		chosen = "   |   part %d chosen: %s, %s wide, %s deep, %s tall" % [part + 1,
			HeldItemShape.kind_name(String(p["kind"])).to_lower(), _num(p["size"][0]), _num(p["size"][1]), _num(p["size"][2])]
	editor.show_status_line(self, "%s   |   %d part%s, %d polygons%s" % [it.name, it.parts.size(),
		"" if it.parts.size() == 1 else "s", view.item_stage.polygon_count(), chosen], "")


static func _num(v: Variant) -> String:
	return str(snappedf(float(v), 0.01))


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
