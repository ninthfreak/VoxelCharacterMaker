@tool
class_name ClothesWorkspace
extends Workspace

## The Clothes tab: every clothing item, with all its parameters -- regions,
## roles, colourways -- and any special shapes anchored to the body.
##
## Cycling through the body types is the point of this tab: a garment is only
## right when it is right on all six. The preview shows the item being edited on
## its own, or everything marked worn. A hair style can be put on, because a
## hat or a hood has to be checked against hair, even though hair itself is
## edited in the Face & Hair tab.

const SHOW_ITEM := "item"
const SHOW_WORN := "worn"

var body_id: String = "male_average"
var head_shape: String = "round"
var hair_id: String = ""
var pose: String = Poses.REST
var show_mode: String = SHOW_ITEM

## Clothing marked worn: Array of {"item": id, "colourway": name}
var worn: Array = []
var clothes: ItemSelection = null

var _body_pick: OptionButton = null
var _head_pick: OptionButton = null
var _hair_pick: OptionButton = null
var _pose_pick: OptionButton = null
var _show_pick: OptionButton = null
var _tabs: TabContainer = null
var _garment: GarmentPanel = null
var _list: ItemListPanel = null


func title() -> String:
	return "Clothes"


func _build() -> void:
	view.allow_picking(true)
	view.region_picked.connect(_on_region_picked)
	clothes = ItemSelection.make(editor, GarmentItem.CLOTHES)
	clothes.changed.connect(rebuild)

	heading(side, "Clothes")
	_body_pick = cycler(side, "Body", editor.library.body_ids(), body_labels(),
		func(value: String) -> void:
			body_id = value
			rebuild())
	note(side, "Step through all six bodies: a garment is only right when it is "
		+ "right on every one.")
	_head_pick = picker(side, "Head", editor.library.head_shapes(), [],
		func(value: String) -> void:
			head_shape = value
			rebuild())
	_hair_pick = picker(side, "Hair", [""], ["(none)"], func(value: String) -> void:
		hair_id = value
		rebuild())
	_pose_pick = picker(side, "Pose", Poses.names(), pose_labels(),
		func(value: String) -> void:
			pose = value
			view.set_pose(value))
	_show_pick = picker(side, "Show", [SHOW_ITEM, SHOW_WORN],
		["This item only", "Everything marked worn"], func(value: String) -> void:
			show_mode = value
			rebuild())

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_tabs)

	var item_box := _tab("Item")
	_list = ItemListPanel.new()
	_list.show_worn = true
	add_panel(_list, clothes, item_box)
	_garment = add_panel(GarmentPanel.new(), clothes, item_box) as GarmentPanel

	add_panel(ColourPanel.new(), clothes, _tab("Colours"))
	add_panel(OutfitPanel.new(), null, _tab("Outfits"))

	var names := editor.wardrobe.outfit_names()
	if names.has("everyday"):
		worn = editor.wardrobe.outfit("everyday")
	var ids := editor.wardrobe.clothing_ids()
	if not ids.is_empty():
		clothes.select(ids[0])


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


func make_request() -> CharacterAssembler.Request:
	var request := CharacterAssembler.Request.make(editor.library, body_id, head_shape,
		EyeSet.NEUTRAL)
	request.wardrobe = editor.wardrobe
	request.worn = clothes.as_worn() if show_mode == SHOW_ITEM else _live_worn()
	var hair := editor.wardrobe.item(hair_id) if not hair_id.is_empty() else null
	if hair != null:
		request.features = [{"item": hair.id, "colourway": hair.first_colourway()}]
	return request


func refresh() -> void:
	if editor.wardrobe == null:
		return
	clothes.validate()
	worn = _live_worn()
	select_value(_body_pick, body_id)
	select_value(_head_pick, head_shape)
	select_value(_pose_pick, pose)
	select_value(_show_pick, show_mode)
	var hair_ids: Array = [""]
	var hair_labels: Array = ["(none)"]
	for id in editor.wardrobe.feature_ids("hair"):
		hair_ids.append(id)
		hair_labels.append(editor.wardrobe.item(id).name)
	if editor.wardrobe.item(hair_id) == null:
		hair_id = ""
	refill(_hair_pick, hair_ids, hair_labels, hair_id)


func status_text(assembled: CharacterAssembler.Assembled) -> String:
	var what := "this item only" if show_mode == SHOW_ITEM else "%d worn" % worn.size()
	return "%s   |   %s" % [super.status_text(assembled), what]


# ------------------------------------------------------------- worn items --

## Worn entries whose item still exists, with valid colourways.
func _live_worn() -> Array:
	var out: Array = []
	for entry in worn:
		var e: Dictionary = entry
		var it := editor.wardrobe.item(String(e["item"]))
		if it == null or it.is_feature():
			continue
		var way := String(e["colourway"])
		out.append({"item": it.id, "colourway": way if it.has_colourway(way)
			else it.first_colourway()})
	return out


func is_worn(item_id: String) -> bool:
	for entry in worn:
		if String((entry as Dictionary)["item"]) == item_id:
			return true
	return false


func set_worn(item_id: String, on: bool) -> void:
	var it := editor.wardrobe.item(item_id)
	if it == null:
		return
	if on and not is_worn(item_id):
		worn.append({"item": item_id, "colourway": clothes.colourway
			if item_id == clothes.item_id else it.first_colourway()})
	elif not on:
		for i in range(worn.size() - 1, -1, -1):
			if String((worn[i] as Dictionary)["item"]) == item_id:
				worn.remove_at(i)
	if show_mode == SHOW_WORN:
		rebuild()


func set_worn_colourway(item_id: String, colourway: String) -> void:
	for entry in worn:
		var e: Dictionary = entry
		if String(e["item"]) == item_id:
			e["colourway"] = colourway
	rebuild()


func get_worn() -> Array:
	return _live_worn()


## Wear an outfit. Switches the preview to show what is worn, since that is
## what wearing an outfit is for.
func set_worn_list(list: Array) -> void:
	worn = list.duplicate(true)
	show_mode = SHOW_WORN
	select_value(_show_pick, show_mode)
	_list.refresh()
	rebuild()


func _on_region_picked(region: String) -> void:
	show_section("Item")
	_garment.select_region(region)
	editor.set_status_hint("Picked %s" % editor.library.region_map().label_for(region))
