@tool
class_name GarmentPanel
extends EditorPanel

## Garment editing (SPEC.md section 8): pick regions from the list or off the
## figure, set a role and a bulk per region, set the mirror flag and the edge
## style. Special items show their generator's parameters instead.
##
## Regions are listed head to toe and, while the mirror flag is on, only the
## character's left side is listed -- because that is what you author. The right
## side follows, which the hint says in words rather than leaving you to notice.

var _summary: Label = null
var _mirror: CheckBox = null
var _edge: OptionButton = null
var _regions: ItemList = null
var _role: OptionButton = null
var _bulk: SpinBox = null
var _special_box: VBoxContainer = null
var _parametric_box: VBoxContainer = null
var _special_type: OptionButton = null
var _special_params: VBoxContainer = null

var _region_keys: Array[String] = []


func _build() -> void:
	var head := section("Garment")
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_summary)

	_mirror = CheckBox.new()
	_mirror.text = "Mirror the left side onto the right"
	_mirror.toggled.connect(func(on: bool) -> void:
		if is_guarded():
			return
		var item := editor.selected_item()
		if item == null or item.mirror == on:
			return
		item.mirror = on
		editor.commit("%s mirror on %s" % ["Enable" if on else "Disable", item.name])
		refresh())
	head.add_child(_mirror)
	hint(head, "Off means the two sides are authored separately, for a sash or "
		+ "a one-shouldered top. Turning it on keeps the right-side work on "
		+ "disk; it is just ignored while on.")

	_edge = labelled(head, "Edge style", OptionButton.new()) as OptionButton
	_edge.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		var item := editor.selected_item()
		if item == null:
			return
		item.edge_style = BulkBuilder.edge_style_from_name(option_value(_edge))
		editor.commit("Set edge style on %s" % item.name)
		refresh())
	hint(head, "Soft rounds the corners, for cloth. Hard squares them, for plate.")

	# -- parametric ---------------------------------------------------------
	_parametric_box = VBoxContainer.new()
	add_child(_parametric_box)

	var regions_head := Label.new()
	regions_head.text = "Regions"
	regions_head.add_theme_font_size_override("font_size", 15)
	_parametric_box.add_child(regions_head)
	_parametric_box.add_child(HSeparator.new())

	_regions = make_list(_parametric_box, 260, true)
	hint(_parametric_box, "Select one or more regions, then apply a role and a "
		+ "bulk. Bulk 0 recolours the body's own voxels; 1 or more adds that "
		+ "many voxels outward. A trim band is one row thick, so a cuff, belt, "
		+ "collar or hem is just a trim band in another colour.")

	var apply_row := HFlowContainer.new()
	_parametric_box.add_child(apply_row)
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

	button_row(_parametric_box, [
		{"text": "Apply to selected", "action": _on_apply},
		{"text": "Clear selected", "action": _on_clear},
		{"text": "Select covered", "action": _on_select_covered},
		{"text": "Clear all", "action": _on_clear_all},
	])

	# -- special ------------------------------------------------------------
	_special_box = VBoxContainer.new()
	add_child(_special_box)

	var special_head := Label.new()
	special_head.text = "Special shape"
	special_head.add_theme_font_size_override("font_size", 15)
	_special_box.add_child(special_head)
	_special_box.add_child(HSeparator.new())

	_special_type = labelled(_special_box, "Type", OptionButton.new()) as OptionButton
	_special_type.item_selected.connect(func(_i: int) -> void:
		if is_guarded():
			return
		var item := editor.selected_item()
		if item == null:
			return
		item.special_type = option_value(_special_type)
		item.special_params = SpecialItem.default_params(item.special_type)
		editor.commit("Set %s to a %s" % [item.name, item.special_type])
		refresh())

	_special_params = VBoxContainer.new()
	_special_box.add_child(_special_params)
	hint(_special_box, "Special shapes are generated from body measurements, so "
		+ "they still fit all six bodies. Skirts hang cloth panels that swing "
		+ "with the stride.")


func refresh() -> void:
	var item := editor.selected_item() if editor != null else null
	begin_guard()

	if item == null:
		_summary.text = "No item selected. Pick one in the Wardrobe tab."
		_parametric_box.visible = false
		_special_box.visible = false
		_mirror.disabled = true
		_edge.disabled = true
		end_guard()
		return

	_mirror.disabled = false
	_edge.disabled = false
	_mirror.button_pressed = item.mirror
	fill_options(_edge, ["soft", "hard"], BulkBuilder.edge_style_name(item.edge_style))

	var detail := ""
	if item.is_special():
		detail = "Generated shape: %s." % item.special_type
	else:
		detail = "%d regions covered, deepest bulk %d." % [
			item.effective_coverage().size(), item.max_bulk()]
	_summary.text = "%s - %s, draws at %d. %s" % [
		item.name, item.category, item.draw_order, detail]

	_parametric_box.visible = not item.is_special()
	_special_box.visible = item.is_special()

	if item.is_special():
		fill_options(_special_type, SpecialItem.types(), item.special_type)
		_rebuild_special_params(item)
	else:
		fill_options(_role, item.roles, item.roles[0] if not item.roles.is_empty() else "")
		_rebuild_region_list(item)

	end_guard()


func _rebuild_region_list(item: GarmentItem) -> void:
	var map := editor.library.region_map()
	if map == null:
		return
	var keys := map.keys_for_side(RegionMap.SIDE_LEFT) if item.mirror else map.all_keys()
	_region_keys = keys

	var coverage := item.coverage
	_regions.clear()
	for index in keys.size():
		var key := keys[index]
		var text := map.label_for(key)
		if coverage.has(key):
			var entry: Dictionary = coverage[key]
			text += "   ->  %s, bulk %d" % [String(entry["role"]), int(entry["bulk"])]
		_regions.add_item(text)


func _rebuild_special_params(item: GarmentItem) -> void:
	for child in _special_params.get_children():
		_special_params.remove_child(child)
		child.queue_free()

	var params := SpecialItem.with_defaults(item.special_type, item.special_params)
	for entry in SpecialItem.param_spec(item.special_type):
		var spec: Dictionary = entry
		var key := String(spec["name"])
		var label := String(spec["label"])
		match String(spec["type"]):
			"bool":
				var check := CheckBox.new()
				check.text = label
				check.button_pressed = bool(params.get(key, spec["default"]))
				check.toggled.connect(func(on: bool) -> void:
					_set_param(key, on, label))
				_special_params.add_child(check)
			"int":
				var spin := labelled(_special_params, label, SpinBox.new()) as SpinBox
				spin.min_value = int(spec.get("min", 0))
				spin.max_value = int(spec.get("max", 8))
				spin.step = 1
				spin.value = int(params.get(key, spec["default"]))
				spin.value_changed.connect(func(value: float) -> void:
					_set_param(key, int(value), label))
			"enum":
				var option := labelled(_special_params, label, OptionButton.new()) as OptionButton
				var options: Array = spec.get("options", [])
				var pretty: Array = []
				for o in options:
					pretty.append(String(o).replace("_", " "))
				fill_options(option, options, String(params.get(key, spec["default"])), pretty)
				option.item_selected.connect(func(_i: int) -> void:
					_set_param(key, option_value(option), label))
		if spec.has("hint"):
			hint(_special_params, String(spec["hint"]))


func _set_param(key: String, value: Variant, label: String) -> void:
	if is_guarded():
		return
	var item := editor.selected_item()
	if item == null:
		return
	if item.special_params.get(key) == value:
		return
	item.special_params[key] = value
	editor.commit("Set %s on %s" % [label.to_lower(), item.name])


# ------------------------------------------------------------------ actions --

## Called when a region is picked off the figure.
func select_region(region_key: String) -> void:
	var item := editor.selected_item()
	if item == null or item.is_special():
		return
	var key := region_key
	# While mirroring, the list only holds the left side, so a right-side pick
	# selects its mirror -- which is the region that actually gets authored.
	if item.mirror and RegionMap.key_side(key) == RegionMap.SIDE_RIGHT:
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
	var item := editor.selected_item()
	var keys := _selected_keys()
	if item == null or keys.is_empty():
		editor.set_status_hint("Select at least one region first.")
		return
	var role := option_value(_role)
	var bulk := int(_bulk.value)
	for key in keys:
		item.set_region(key, role, bulk)
	editor.commit("Set %s bulk %d on %d region%s" % [
		role, bulk, keys.size(), "" if keys.size() == 1 else "s"])
	refresh()


func _on_clear() -> void:
	var item := editor.selected_item()
	var keys := _selected_keys()
	if item == null or keys.is_empty():
		return
	for key in keys:
		item.clear_region(key)
	editor.commit("Clear %d region%s on %s" % [
		keys.size(), "" if keys.size() == 1 else "s", item.name])
	refresh()


func _on_select_covered() -> void:
	var item := editor.selected_item()
	if item == null:
		return
	_regions.deselect_all()
	for index in _region_keys.size():
		if item.coverage.has(_region_keys[index]):
			_regions.select(index, false)


func _on_clear_all() -> void:
	var item := editor.selected_item()
	if item == null or item.coverage.is_empty():
		return
	item.coverage.clear()
	editor.commit("Clear every region on %s" % item.name)
	refresh()
