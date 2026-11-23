@tool
class_name PreviewWorkspace
extends Workspace

## The Preview tab: put together anything made in the other tabs -- a body, a
## head, eyes in a colour, hair, facial hair, and clothes -- and see the whole
## character, posed; and save it as a character (CharacterDef) the game can
## build by name.
##
## The choices here are not themselves edits: trying things changes nothing.
## Saving, updating, renaming or deleting a character is (CharacterPanel).

var body_id: String = "male_average"
var head_shape: String = "round"
var pose: String = Poses.REST
var lids: String = EyeLids.DEFAULT
var mouth: String = Mouths.DEFAULT
var skin_tone: String = Palette.DEFAULT_SKIN
## A hair palette colour whose brow to use; "" = follow the hair worn.
var brow_hair: String = ""
var eye_set_id: String = ""
var eye_colourway: String = ""
var hair_id: String = ""
var hair_colourway: String = ""
var facial_id: String = ""
var facial_colourway: String = ""
var accessory_id: String = ""
var accessory_colourway: String = ""
var right_hand_id: String = ""
var right_hand_colourway: String = ""
var left_hand_id: String = ""
var left_hand_colourway: String = ""
## Clothing worn: Array of {"item": id, "colourway": name}
var worn: Array = []
## The saved character last loaded or saved here ("" = none): what Update writes to.
var character_id: String = ""
## The animation playing ("" = none: the pose holds).
var animation: String = ""
var _animator: RigAnimator = null
var _anim_pick: OptionButton = null

var _body_pick: OptionButton = null
var _head_pick: OptionButton = null
var _pose_pick: OptionButton = null
var _lid_pick: OptionButton = null
var _mouth_pick: OptionButton = null
var _skin_pick: OptionButton = null
var _brow_pick: OptionButton = null
var _eye_pick: OptionButton = null
var _eye_way_pick: OptionButton = null
var _hair_pick: OptionButton = null
var _hair_way_pick: OptionButton = null
var _facial_pick: OptionButton = null
var _facial_way_pick: OptionButton = null
var _accessory_pick: OptionButton = null
var _accessory_way_pick: OptionButton = null
var _right_pick: OptionButton = null
var _right_way_pick: OptionButton = null
var _left_pick: OptionButton = null
var _left_way_pick: OptionButton = null
var _outfit_pick: OptionButton = null
var _clothes_rows: VBoxContainer = null
var _summary: Label = null
var _guard := 0


func title() -> String:
	return "Preview"


func _build() -> void:
	heading(side, "The whole character")
	note(side, "Put together anything made in the other tabs, and save it as a character the game can build.")
	add_panel(CharacterPanel.new(), null, side)
	figure_controls(side, "Skirts and capes follow the legs. Not shown yet: edge style (its setting is kept).")

	_body_pick = cycler(side, "Body", editor.library.body_ids(), body_labels(),
		func(value: String) -> void: _choose("body_id", value))
	_head_pick = cycler(side, "Head", editor.library.head_shapes(), [],
		func(value: String) -> void: _choose("head_shape", value))
	_pose_pick = picker(side, "Pose", Poses.names(), pose_labels(),
		func(value: String) -> void:
			pose = value
			_play("")
			view.set_pose(value))
	var anim_labels: Array = ["(none: hold the pose)"]
	for clip in Animations.names():
		anim_labels.append(Animations.display_name(clip))
	_anim_pick = picker(side, "Animation", [""] + Animations.names(), anim_labels,
		func(value: String) -> void: _play(value))
	_skin_pick = picker(side, "Skin tone", Palette.SKIN_TONE_NAMES, [],
		func(value: String) -> void: _choose("skin_tone", value))

	heading(side, "Face")
	var lid_labels: Array = []
	for state in EyeLids.names():
		lid_labels.append(EyeLids.display_name(state))
	_lid_pick = picker(side, "Eyelids", EyeLids.names(), lid_labels,
		func(value: String) -> void: _choose("lids", value))
	note(side, "Eyelids are drawn over the open eye, and the brow above it moves "
		+ "with the lid. The brow is the hair colour one shade darker.")
	var mouth_labels: Array = []
	for state in Mouths.names():
		mouth_labels.append(Mouths.display_name(state))
	_mouth_pick = picker(side, "Mouth", Mouths.names() + [Mouths.OFF], mouth_labels + [Mouths.display_name(Mouths.OFF)],
		func(value: String) -> void: _choose("mouth", value))
	note(side, "Which mouth goes with which eyelids is not decided, so the two are chosen apart.")
	_brow_pick = picker(side, "Brows", [], [], func(value: String) -> void:
		_choose("brow_hair", value))
	_eye_pick = picker(side, "Eye set", [], [], func(value: String) -> void:
		_choose("eye_set_id", value))
	_eye_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("eye_colourway", value))

	heading(side, "Hair")
	_hair_pick = picker(side, "Style", [], [], func(value: String) -> void:
		_choose("hair_id", value))
	_hair_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("hair_colourway", value))
	_facial_pick = picker(side, "Facial hair", [], [], func(value: String) -> void:
		_choose("facial_id", value))
	_facial_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("facial_colourway", value))
	_accessory_pick = picker(side, "Face accessory", [], [], func(value: String) -> void:
		_choose("accessory_id", value))
	_accessory_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("accessory_colourway", value))

	heading(side, "Held")
	_right_pick = picker(side, "Right hand", [], [], func(value: String) -> void:
		_choose("right_hand_id", value))
	_right_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("right_hand_colourway", value))
	_left_pick = picker(side, "Left hand", [], [], func(value: String) -> void:
		_choose("left_hand_id", value))
	_left_way_pick = picker(side, "Colour", [], [], func(value: String) -> void:
		_choose("left_hand_colourway", value))
	note(side, "Held items are made in the Items tab.")

	heading(side, "Clothes")
	_outfit_pick = picker(side, "Outfit", [], [], func(value: String) -> void:
		if value.is_empty():
			return
		worn = editor.wardrobe.outfit(value)
		refresh()
		rebuild())
	note(side, "Choosing an outfit wears it; the list below can then be changed "
		+ "item by item without touching the saved outfit.")
	_clothes_rows = VBoxContainer.new()
	side.add_child(_clothes_rows)

	heading(side, "Summary")
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_summary)
	start_fresh()


## A new or opened wardrobe: its first eye set and hair, and its "everyday" outfit, as at start-up.
func start_fresh() -> void:
	character_id = ""
	eye_set_id = editor.wardrobe.first_eye_set_id()
	var hair_ids := editor.wardrobe.feature_ids("hair")
	hair_id = hair_ids[0] if not hair_ids.is_empty() else ""
	worn = editor.wardrobe.outfit("everyday") if editor.wardrobe.outfit_names().has("everyday") else []


## Play an animation on the figure ("" = stop, back to the pose chosen).
func _play(clip: String) -> void:
	if _guard > 0:
		return
	animation = clip
	if _animator == null:
		_animator = RigAnimator.make(view.lowpoly_rig)
		add_child(_animator)
	if clip.is_empty():
		_animator.stop()
		view.set_pose(pose)
	else:
		_animator.play(clip)
	if _anim_pick != null:
		_guard += 1
		select_value(_anim_pick, clip)
		_guard -= 1
	if view.lowpoly_rig.figure != null:
		editor.show_status_line(self, lowpoly_status_text(view.lowpoly_rig.figure), "")


## Choices that change what another menu offers (an eye set's colours, a hair's or a beard's colourways): after these
## the menus are filled again; after any other, only the summary changes.
const REFILLS: Array[String] = ["eye_set_id", "hair_id", "facial_id", "accessory_id", "right_hand_id", "left_hand_id"]
## The choices a saved character keeps (CharacterDef), but what it wears.
const KEPT: Array[String] = ["body_id", "head_shape", "skin_tone", "eye_set_id", "eye_colourway", "brow_hair", "lids",
	"mouth", "hair_id", "hair_colourway", "facial_id", "facial_colourway", "accessory_id", "accessory_colourway",
	"right_hand_id", "right_hand_colourway", "left_hand_id", "left_hand_colourway"]


func _choose(field: String, value: String) -> void:
	if _guard > 0:
		return
	set(field, value)
	if field in REFILLS:
		refresh()
	else:
		_refresh_summary()
	rebuild()



## The character the choices here make, as it would be saved: under the loaded character's id and name, if one was
## loaded. The figure shown is built from it, so a saved character is what was shown.
func current_character() -> CharacterDef:
	var loaded := editor.wardrobe.character(character_id) if not character_id.is_empty() else null
	var who := CharacterDef.create(character_id, loaded.name if loaded != null else "")
	for field in KEPT:
		who.set(field, get(field))
	who.worn = _live_worn()
	return who


## Take up a saved character's choices (its pose and shading are not part of it: they stay).
func load_character(who: CharacterDef) -> void:
	if who == null:
		return
	for field in KEPT:
		set(field, who.get(field))
	worn = who.worn.duplicate(true)
	character_id = who.id
	refresh()
	rebuild()


## Whether the choices here are the loaded character as saved.
func matches_saved() -> bool:
	var loaded := editor.wardrobe.character(character_id) if not character_id.is_empty() else null
	return loaded != null and current_character().looks_like(loaded, editor.wardrobe)


func make_request() -> CharacterRequest:
	return current_character().make_request(editor.wardrobe)


func refresh() -> void:
	var w := editor.wardrobe
	if w == null or _body_pick == null:
		return
	_guard += 1
	refresh_figure_controls()
	body_id = refill_bodies(_body_pick, body_id)
	select_value(_head_pick, head_shape)
	select_value(_pose_pick, pose)
	select_value(_anim_pick, animation)
	select_value(_skin_pick, skin_tone)
	select_value(_lid_pick, lids)
	select_value(_mouth_pick, mouth)
	var brow_values: Array = [""]
	var brow_labels: Array = ["follow the hair (dark brown if bald)"]
	for key in w.palette.keys():
		if String(key).begins_with("hair_"):
			brow_values.append(String(key))
			brow_labels.append("like %s hair" % String(key).trim_prefix("hair_"))
	if not (brow_hair in brow_values):
		brow_hair = ""
	refill(_brow_pick, brow_values, brow_labels, brow_hair)

	# Eyes: a set always, and its colours.
	if w.eye_set(eye_set_id) == null:
		eye_set_id = w.first_eye_set_id()
	var eye_ids: Array = []
	var eye_labels: Array = []
	for id in w.eye_set_ids():
		eye_ids.append(id)
		eye_labels.append(w.eye_set(id).name)
	if eye_ids.is_empty():
		eye_ids = [""]
		eye_labels = ["basic (no eye set saved)"]
	refill(_eye_pick, eye_ids, eye_labels, eye_set_id)
	var eyes := w.eye_set(eye_set_id)
	var ways: Array = []
	if eyes != null:
		for way in eyes.colourway_names():
			ways.append(way)
	if eyes != null and not eyes.colourways.has(eye_colourway):
		eye_colourway = eyes.first_colourway()                # as the assembler would draw it, not the first by name
	refill(_eye_way_pick, ways, [], eye_colourway)
	eye_colourway = option_value(_eye_way_pick)

	# Hair and facial hair: a choice per slot, "none" included.
	hair_id = _fill_slot(_hair_pick, "hair", hair_id, "(none - bald)")
	hair_colourway = _fill_ways(_hair_way_pick, hair_id, hair_colourway)
	facial_id = _fill_slot(_facial_pick, "facial_hair", facial_id, "(none - clean-shaven)")
	facial_colourway = _fill_ways(_facial_way_pick, facial_id, facial_colourway)
	accessory_id = _fill_slot(_accessory_pick, "face_accessory", accessory_id, "(none)")
	accessory_colourway = _fill_ways(_accessory_way_pick, accessory_id, accessory_colourway)
	right_hand_id = _fill_slot(_right_pick, GarmentItem.HELD, right_hand_id, "(nothing)")
	right_hand_colourway = _fill_ways(_right_way_pick, right_hand_id, right_hand_colourway)
	left_hand_id = _fill_slot(_left_pick, GarmentItem.HELD, left_hand_id, "(nothing)")
	left_hand_colourway = _fill_ways(_left_way_pick, left_hand_id, left_hand_colourway)
	if editor.wardrobe.character(character_id) == null:
		character_id = ""

	# Clothes.
	var outfit_values: Array = [""]
	var outfit_labels: Array = ["(choose an outfit to wear)"]
	for name2 in w.outfit_names():
		outfit_values.append(name2)
		outfit_labels.append(name2)
	refill(_outfit_pick, outfit_values, outfit_labels, "")
	worn = _live_worn()
	_rebuild_clothes_rows()
	_guard -= 1
	_refresh_summary()


func _fill_slot(option: OptionButton, slot: String, current: String, none_label: String) -> String:
	var values: Array = [""]
	var labels: Array = [none_label]
	for id in editor.wardrobe.feature_ids(slot):
		values.append(id)
		labels.append(editor.wardrobe.item(id).name)
	if not (current in values):
		current = ""
	refill(option, values, labels, current)
	return current


func _fill_ways(option: OptionButton, item_id: String, current: String) -> String:
	var it := editor.wardrobe.item(item_id) if not item_id.is_empty() else null
	var ways: Array = []
	if it != null:
		for way in it.colourway_names():
			ways.append(way)
		if not it.has_colourway(current):
			current = it.first_colourway()                    # as the assembler would draw it, not the first by name
	refill(option, ways, [], current)
	option.disabled = it == null
	return option_value(option)


## One row per clothing item: worn or not, and in which colourway. "worn" is
## said by the checkbox's tick and its label, not by colour.
func _rebuild_clothes_rows() -> void:
	for child in _clothes_rows.get_children():
		_clothes_rows.remove_child(child)
		child.queue_free()
	for id in editor.wardrobe.clothing_ids():
		var it := editor.wardrobe.item(id)
		var line := HBoxContainer.new()
		var check := CheckBox.new()
		check.text = it.name
		check.button_pressed = _worn_index(id) >= 0
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var way := OptionButton.new()
		var current := it.first_colourway()
		var at := _worn_index(id)
		if at >= 0:
			current = String((worn[at] as Dictionary)["colourway"])
		refill(way, it.colourway_names(), [], current)
		way.disabled = at < 0
		check.toggled.connect(func(on: bool) -> void:
			if on and _worn_index(id) < 0:
				worn.append({"item": id, "colourway": option_value(way)})
			elif not on:
				var index := _worn_index(id)
				if index >= 0:
					worn.remove_at(index)
			way.disabled = not on
			_refresh_summary()
			rebuild())
		way.item_selected.connect(func(_i: int) -> void:
			var index := _worn_index(id)
			if index >= 0:
				(worn[index] as Dictionary)["colourway"] = option_value(way)
				rebuild())
		line.add_child(check)
		line.add_child(way)
		_clothes_rows.add_child(line)


func _worn_index(item_id: String) -> int:
	for i in worn.size():
		if String((worn[i] as Dictionary)["item"]) == item_id:
			return i
	return -1


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


func _refresh_summary() -> void:
	var w := editor.wardrobe
	var eyes := w.eye_set(eye_set_id)
	var lines: Array[String] = []
	var loaded := w.character(character_id) if not character_id.is_empty() else null
	if loaded == null:
		lines.append("Character: not saved")
	elif matches_saved():
		lines.append("Character: %s, as saved" % loaded.name)
	else:
		lines.append("Character: %s, changed since saved (Update keeps the changes)" % loaded.name)
	var body_name := body_id
	if editor.library.body(body_id) != null:
		body_name = editor.library.body(body_id).display_name()
	lines.append("Body: %s, %s head, %s skin" % [body_name, head_shape, skin_tone])
	lines.append("Eyelids: %s; brows %s" % [EyeLids.display_name(lids),
		"follow the hair" if brow_hair.is_empty() else "like %s hair" % brow_hair.trim_prefix("hair_")])
	lines.append("Eyes: %s, %s" % [eyes.name if eyes != null else "basic",
		eye_colourway if not eye_colourway.is_empty() else "-"])
	lines.append("Mouth: %s" % Mouths.display_name(mouth))
	var hair := w.item(hair_id) if not hair_id.is_empty() else null
	var facial := w.item(facial_id) if not facial_id.is_empty() else null
	lines.append("Hair: %s" % ("%s (%s)" % [hair.name, hair_colourway] if hair != null
		else "none"))
	lines.append("Facial hair: %s" % ("%s (%s)" % [facial.name, facial_colourway]
		if facial != null else "none"))
	var accessory := w.item(accessory_id) if not accessory_id.is_empty() else null
	if accessory != null:
		lines.append("Face accessory: %s (%s)" % [accessory.name, accessory_colourway])
	for hand in [["Right hand", right_hand_id, right_hand_colourway], ["Left hand", left_hand_id, left_hand_colourway]]:
		var held := w.item(String(hand[1])) if not String(hand[1]).is_empty() else null
		if held != null:
			lines.append("%s: %s (%s)" % [hand[0], held.name, hand[2]])
	var names: Array[String] = []
	for entry in _live_worn():
		var e: Dictionary = entry
		names.append("%s (%s)" % [w.item(String(e["item"])).name, String(e["colourway"])])
	lines.append("Wearing: %s" % (", ".join(names) if not names.is_empty() else "nothing"))
	_summary.text = "\n".join(lines)


func status_extra() -> String:
	return "   |   %d worn   |   %s" % [_live_worn().size(),
		Animations.display_name(animation) + " (playing)" if not animation.is_empty() else Poses.display_name(pose)]


## The summary again, after a character was saved, updated, renamed or deleted.
func refresh_summary() -> void:
	_refresh_summary()
