@tool
class_name GarmentPanel
extends EditorPanel

## Everything about one item's shape (SPEC.md section 8, "Garment editing"):
## its regions -- role and bulk per region, mirror flag, edge style -- and its
## special shapes, each anchored to the body at a named point.
##
## An item has both kinds at once; a dress is a bodice of regions and a skirt
## shape. So both sections are always here, and an item with no special shapes
## simply has an empty list.
##
## Regions are listed head to toe and, while the mirror flag is on, only the
## character's left side is listed -- that is what you author. Features can be
## limited to the regions that make sense for them (hair: the head).

## Region families to offer. Empty means all.
var families: Array[String] = []

var _summary: Label = null
var _mirror: CheckBox = null
var _edge: OptionButton = null
var _regions: ItemList = null
var _role: OptionButton = null
var _bulk: SpinBox = null
var _region_keys: Array[String] = []

var _specials: ItemList = null
var _add_type: OptionButton = null
var _special_detail: VBoxContainer = null
var _anchor_note: Label = null
var _params: VBoxContainer = null
var _shape_box: VBoxContainer = null
var _shape_grid: ShapeGrid = null
var _shape_role: OptionButton = null
var _shape_layer: HSlider = null
var _special_index := -1


func _build() -> void:
	var head := section("Shape of the item")
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_summary)

	_mirror = CheckBox.new()
	_mirror.text = "Mirror the left side onto the right"
	_mirror.toggled.connect(func(on: bool) -> void:
		if is_guarded():
			return
		var it := item()
		if it == null or it.mirror == on:
			return
		it.mirror = on
		commit("%s mirror on %s" % ["Enable" if on else "Disable", it.name])
		refresh())
	head.add_child(_mirror)
	hint(head, "Off means the two sides are authored separately, for a sash or a "
		+ "one-shouldered top. Turning it back on keeps the right-side work.")

	_edge = labelled(head, "Edge style", OptionButton.new()) as OptionButton
	_edge.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		var it := item()
		if it == null:
			return
		it.edge_style = BulkBuilder.edge_style_from_name(option_value(_edge))
		commit("Set edge style on %s" % it.name)
		refresh())
	hint(head, "Soft rounds the corners, for cloth. Hard squares them, for plate.")

	_build_regions()
	_build_specials()


func _build_regions() -> void:
	var box := section("Regions")
	_regions = make_list(box, 230, true)
	hint(box, "Select one or more regions, then apply a role and a bulk. Bulk 0 "
		+ "recolours the body's own voxels; 1 or more adds that many voxels outward. "
		+ "A trim band is one row thick: a cuff, belt, collar or hem.")
	var apply_row := HFlowContainer.new()
	box.add_child(apply_row)
	var role_label := Label.new()
	role_label.text = "Role"
	apply_row.add_child(role_label)
	_role = OptionButton.new()
	_role.custom_minimum_size = Vector2(150, 0)
	apply_row.add_child(_role)
	var bulk_label := Label.new()
	bulk_label.text = "Bulk"
	apply_row.add_child(bulk_label)
	_bulk = SpinBox.new()
	_bulk.min_value = 0
	_bulk.max_value = BulkBuilder.MAX_BULK
	_bulk.step = 1
	_bulk.value = 1
	apply_row.add_child(_bulk)
	button_row(box, [
		{"text": "Apply to selected", "action": _on_apply},
		{"text": "Clear selected", "action": _on_clear},
		{"text": "Select covered", "action": _on_select_covered},
		{"text": "Clear all", "action": _on_clear_all},
	])


func _build_specials() -> void:
	var box := section("Special shapes")
	hint(box, "Shapes anchored to the body at a named point, with a form of their "
		+ "own: skirts, capes, hoods, and anything drawn by hand.")
	_specials = make_list(box, 90)
	_specials.item_selected.connect(func(index: int) -> void:
		if is_guarded():
			return
		_special_index = index
		_refresh_special_detail())

	var add_row := HFlowContainer.new()
	box.add_child(add_row)
	_add_type = OptionButton.new()
	var labels: Array = []
	for type in SpecialItem.types():
		labels.append(SpecialItem.display_name(type))
	fill_options(_add_type, SpecialItem.types(), "skirt", labels)
	add_row.add_child(_add_type)
	var add := Button.new()
	add.text = "Add shape"
	add.pressed.connect(_on_add_special)
	add_row.add_child(add)
	var remove := Button.new()
	remove.text = "Remove shape"
	remove.pressed.connect(_on_remove_special)
	add_row.add_child(remove)

	_special_detail = VBoxContainer.new()
	box.add_child(_special_detail)
	_anchor_note = Label.new()
	_anchor_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor_note.add_theme_color_override("font_color", Palette.UI_SKY)
	_special_detail.add_child(_anchor_note)
	_params = VBoxContainer.new()
	_special_detail.add_child(_params)

	_shape_box = VBoxContainer.new()
	_special_detail.add_child(_shape_box)
	var shape_row := HFlowContainer.new()
	_shape_box.add_child(shape_row)
	var paint_label := Label.new()
	paint_label.text = "Paint with"
	shape_row.add_child(paint_label)
	_shape_role = OptionButton.new()
	_shape_role.custom_minimum_size = Vector2(140, 0)
	_shape_role.item_selected.connect(func(_i: int) -> void:
		_shape_grid.role = option_value(_shape_role)
		_shape_grid.queue_redraw())
	shape_row.add_child(_shape_role)
	var layer_line := HBoxContainer.new()
	_shape_box.add_child(layer_line)
	var layer_label := Label.new()
	layer_label.text = "Layer"
	layer_line.add_child(layer_label)
	_shape_layer = HSlider.new()
	_shape_layer.min_value = ShapeGenerator.B_MIN
	_shape_layer.max_value = ShapeGenerator.B_MAX
	_shape_layer.step = 1
	_shape_layer.value = 0
	_shape_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shape_layer.value_changed.connect(func(v: float) -> void:
		_shape_grid.layer = int(v)
		_shape_grid.queue_redraw())
	layer_line.add_child(_shape_layer)
	_shape_grid = ShapeGrid.new()
	_shape_grid.stroke_finished.connect(_on_shape_stroke)
	_shape_box.add_child(_shape_grid)


func refresh() -> void:
	var it := item()
	begin_guard()
	visible = it != null
	if it == null:
		end_guard()
		return

	_mirror.button_pressed = it.mirror
	fill_options(_edge, ["soft", "hard"], BulkBuilder.edge_style_name(it.edge_style))
	var detail := "%d regions, deepest bulk %d" % [it.effective_coverage().size(), it.max_bulk()]
	if it.is_special():
		detail += "; %d special shape%s" % [it.specials.size(),
			"" if it.specials.size() == 1 else "s"]
	_summary.text = "%s, draws at %d. %s." % [it.name, it.draw_order, detail]

	fill_options(_role, it.roles, it.roles[0] if not it.roles.is_empty() else "")
	_rebuild_region_list(it)

	_specials.clear()
	for i in it.specials.size():
		var type := it.special_type(i)
		var text := SpecialItem.display_name(type)
		if type == ShapeGenerator.KIND:
			text += " at %s" % String(it.special_params(i).get("anchor", "?"))
		_specials.add_item(text)
	if _special_index >= it.specials.size():
		_special_index = it.specials.size() - 1
	if _special_index < 0 and not it.specials.is_empty():
		_special_index = 0
	if _special_index >= 0:
		_specials.select(_special_index)
	end_guard()
	_refresh_special_detail()


func _rebuild_region_list(it: GarmentItem) -> void:
	var map := editor.library.region_map()
	if map == null:
		return
	var keys := map.keys_for_side(RegionMap.SIDE_LEFT) if it.mirror else map.all_keys()
	_region_keys.clear()
	_regions.clear()
	for key in keys:
		if not families.is_empty():
			var band := map.band(String(RegionMap.parse_key(key)["band"]))
			if band == null or not (band.family in families):
				continue
		_region_keys.append(key)
		var text := map.label_for(key)
		if it.coverage.has(key):
			var entry: Dictionary = it.coverage[key]
			text += "   ->  %s, bulk %d" % [String(entry["role"]), int(entry["bulk"])]
		_regions.add_item(text)


func _refresh_special_detail() -> void:
	var it := item()
	for child in _params.get_children():
		_params.remove_child(child)
		child.queue_free()
	var have := it != null and _special_index >= 0 and _special_index < it.specials.size()
	_special_detail.visible = have
	if not have:
		return

	var type := it.special_type(_special_index)
	var params := SpecialItem.with_defaults(type, it.special_params(_special_index))
	_anchor_note.text = SpecialItem.anchor_description(type, params)
	var index := _special_index
	for entry in SpecialItem.param_spec(type):
		var spec: Dictionary = entry
		var key := String(spec["name"])
		var label := String(spec["label"])
		match String(spec["type"]):
			"bool":
				var check := CheckBox.new()
				check.text = label
				check.button_pressed = bool(params.get(key, spec["default"]))
				check.toggled.connect(func(on: bool) -> void:
					_set_param(index, key, on, label))
				_params.add_child(check)
			"int":
				var spin := labelled(_params, label, SpinBox.new()) as SpinBox
				spin.min_value = int(spec.get("min", 0))
				spin.max_value = int(spec.get("max", 8))
				spin.step = 1
				spin.value = int(params.get(key, spec["default"]))
				spin.value_changed.connect(func(value: float) -> void:
					_set_param(index, key, int(value), label))
			"enum":
				var option := labelled(_params, label, OptionButton.new()) as OptionButton
				var options: Array = spec.get("options", [])
				var pretty: Array = []
				for o in options:
					pretty.append(Anchors.label(String(o)) if key == "anchor"
						else String(o).replace("_", " "))
				fill_options(option, options, String(params.get(key, spec["default"])), pretty)
				option.item_selected.connect(func(_i: int) -> void:
					_set_param(index, key, option_value(option), label))
			_:
				continue  # "cells" is drawn in the grid below
		if spec.has("hint"):
			hint(_params, String(spec["hint"]))

	var is_shape := type == ShapeGenerator.KIND
	_shape_box.visible = is_shape
	if is_shape:
		begin_guard()
		fill_options(_shape_role, it.roles,
			_shape_grid.role if _shape_grid.role in it.roles else it.roles[0])
		end_guard()
		_shape_grid.role = option_value(_shape_role)
		_shape_grid.cells = ShapeGenerator.cells_to_dict(params.get("cells", []))
		_shape_grid.anchor_name = String(params.get("anchor", "chest"))
		_shape_grid.mirror = bool(params.get("mirror", true))
		var colours := {}
		var way := selection.colourway if it.has_colourway(selection.colourway) \
			else it.first_colourway()
		for role in it.roles:
			colours[role] = editor.wardrobe.colour(it.palette_key_for(way, role))
		_shape_grid.colours = colours
		_shape_grid.queue_redraw()


func _set_param(index: int, key: String, value: Variant, label: String) -> void:
	if is_guarded():
		return
	var it := item()
	if it == null or index >= it.specials.size():
		return
	if it.special_params(index).get(key) == value:
		return
	it.set_special_param(index, key, value)
	commit("Set %s on %s" % [label.to_lower(), it.name])
	refresh()


func _on_shape_stroke() -> void:
	var it := item()
	if it == null or _special_index < 0:
		return
	it.set_special_param(_special_index, "cells",
		ShapeGenerator.dict_to_cells(_shape_grid.cells))
	commit("Draw on %s" % it.name)


# ------------------------------------------------------------------ actions --

## Called when a region is picked off the figure.
func select_region(region_key: String) -> void:
	var it := item()
	if it == null:
		return
	var key := region_key
	# While mirroring, the list only holds the left side, so a right-side pick
	# selects its mirror -- which is the region that actually gets authored.
	if it.mirror and RegionMap.key_side(key) == RegionMap.SIDE_RIGHT:
		key = RegionMap.mirror_key(key)
	var index := _region_keys.find(key)
	if index < 0:
		return
	_regions.deselect_all()
	_regions.select(index)
	_regions.ensure_current_is_visible()


func _selected_keys() -> Array[String]:
	var out: Array[String] = []
	for index in _regions.get_selected_items():
		if index >= 0 and index < _region_keys.size():
			out.append(_region_keys[index])
	return out


func _on_apply() -> void:
	var it := item()
	var keys := _selected_keys()
	if it == null or keys.is_empty():
		editor.set_status_hint("Select at least one region first.")
		return
	var role := option_value(_role)
	var bulk := int(_bulk.value)
	for key in keys:
		it.set_region(key, role, bulk)
	commit("Set %s bulk %d on %d region%s" % [
		role, bulk, keys.size(), "" if keys.size() == 1 else "s"])
	refresh()


func _on_clear() -> void:
	var it := item()
	var keys := _selected_keys()
	if it == null or keys.is_empty():
		return
	for key in keys:
		it.clear_region(key)
	commit("Clear %d region%s on %s" % [keys.size(), "" if keys.size() == 1 else "s", it.name])
	refresh()


func _on_select_covered() -> void:
	var it := item()
	if it == null:
		return
	_regions.deselect_all()
	for index in _region_keys.size():
		if it.coverage.has(_region_keys[index]):
			_regions.select(index, false)


func _on_clear_all() -> void:
	var it := item()
	if it == null or it.coverage.is_empty():
		return
	it.coverage.clear()
	commit("Clear every region on %s" % it.name)
	refresh()


func _on_add_special() -> void:
	var it := item()
	if it == null:
		return
	var type := option_value(_add_type)
	_special_index = it.add_special(type)
	# Hair and facial hair are on the head, so a drawn shape starts there.
	if type == ShapeGenerator.KIND and it.is_feature():
		it.set_special_param(_special_index, "anchor",
			"face" if it.slot == "facial_hair" else "nape")
	commit("Add %s to %s" % [SpecialItem.display_name(type).to_lower(), it.name])
	refresh()


func _on_remove_special() -> void:
	var it := item()
	if it == null or _special_index < 0 or _special_index >= it.specials.size():
		return
	var type := it.special_type(_special_index)
	it.remove_special(_special_index)
	_special_index -= 1
	commit("Remove %s from %s" % [SpecialItem.display_name(type).to_lower(), it.name])
	refresh()
