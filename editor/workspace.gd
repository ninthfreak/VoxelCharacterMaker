@tool
class_name Workspace
extends HSplitContainer

## One top-level tab of the editor: a preview on the left, its controls on the
## right, and its own idea of what the preview shows.
##
## The four tabs are deliberately separate (Bodies, Face & Hair, Clothes,
## Preview). They share the documents -- the wardrobe file, the asset library --
## through the editor shell, and nothing else. A tab that is not showing does
## not rebuild; it is marked stale and catches up when it is brought forward.

var editor: CharacterEditor = null
var view: PreviewView = null
## "voxel", or "lowpoly": the low-poly figure, which the editor is moving to a phase at a time (docs/NOTES.md 4t).
## A tab that offers the choice calls model_controls().
var model: String = "voxel"
## the low-poly figure's shading: "flat" or "smooth" (which the game uses is the owner's call)
var shading: String = "flat"
## The controls column, inside a scroller.
var side: VBoxContainer = null

var _stale := true
var _model_pick: OptionButton = null
var _shading_pick: OptionButton = null
var _lowpoly_note: Label = null


func setup(p_editor: CharacterEditor) -> void:
	editor = p_editor
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 980

	view = PreviewView.new()
	add_child(view)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	scroll.add_child(side)

	_build()
	editor.wardrobe_replaced.connect(func() -> void:
		refresh()
		mark_stale())


## The tab's name.
func title() -> String:
	return "Workspace"


## Override: create the controls once.
func _build() -> void:
	pass


## Override: push the model into this tab's own controls (panels refresh
## themselves).
func refresh() -> void:
	pass


## Override: what the preview should show.
func make_request() -> CharacterAssembler.Request:
	return CharacterAssembler.Request.make(editor.library, "male_average", "round")


## Re-assemble and show. A hidden tab only notes that it needs to.
func rebuild() -> void:
	if editor == null or editor.library == null:
		return
	if not is_visible_in_tree():
		_stale = true
		return
	_stale = false
	if model == "lowpoly":
		_rebuild_lowpoly()
		return
	var assembled := view.show_request(make_request())
	editor.show_status(self, assembled)


## The low-poly model: the same request, assembled by LowpolyAssembler.
func _rebuild_lowpoly() -> void:
	if editor.lowpoly == null:
		return
	var request := make_request()
	var figure := LowpolyAssembler.assemble(editor.lowpoly, request)
	if figure == null:
		editor.show_status_line(self, "", "no low-poly body '%s' or head '%s'" % [request.body_id, request.head_shape])
		return
	view.show_lowpoly(figure, shading == "flat")
	var warning := ""
	if not figure.warnings.is_empty():
		warning = figure.warnings[0] + ("" if figure.warnings.size() == 1 else " (and %d more)" % (figure.warnings.size() - 1))
	editor.show_status_line(self, lowpoly_status_text(figure), warning)


## Short description of a low-poly figure for the status line.
func lowpoly_status_text(figure: LowpolyFigure) -> String:
	var body := editor.lowpoly.body(figure.body_id)
	var cloth := view.lowpoly_rig.laid_cloth.size() if view.lowpoly_rig.figure == figure else 0
	return "%s - %s head   |   low-poly: %d polygons, %d triangles%s   |   %s shading%s" % [
		body.display_name() if body != null else figure.body_id, figure.head_shape, figure.visible_polygons(),
		figure.triangles(), " (and %d of hanging cloth)" % cloth if cloth > 0 else "", shading, status_extra()]


## Override: what a tab adds to its status line ("   |   ..."), for either model.
func status_extra() -> String:
	return ""


## The Model and Shading choices, and a note on what the low-poly model shows so far.
func model_controls(parent: Container, note_text: String) -> void:
	_model_pick = picker(parent, "Model", ["voxel", "lowpoly"], ["Voxel", "Low-poly"],
		func(value: String) -> void:
			model = value
			refresh()
			rebuild())
	_shading_pick = picker(parent, "Shading", ["flat", "smooth"],
		["Flat: every polygon one shade", "Smooth: shade blended across polygons"],
		func(value: String) -> void:
			shading = value
			view.set_flat_shading(value == "flat"))
	_lowpoly_note = note(parent, note_text)


## Push the model choice into its controls. Call from refresh().
func refresh_model_controls() -> void:
	if _model_pick == null:
		return
	select_value(_model_pick, model)
	select_value(_shading_pick, shading)
	_shading_pick.get_parent().visible = model == "lowpoly"
	_lowpoly_note.visible = model == "lowpoly"


## Fill a body picker with the bodies the chosen model has (the low-poly one adds a short body for each sex).
## Returns the body id to show: `current`, or the same sex's average where the model has no such body.
func refill_bodies(option: OptionButton, current: String) -> String:
	var ids: Array = []
	var labels: Array = []
	if model == "lowpoly" and editor.lowpoly != null:
		for id in editor.lowpoly.body_ids():
			ids.append(id)
			labels.append(editor.lowpoly.body(id).display_name())
	else:
		for id in editor.library.body_ids():
			ids.append(id)
		labels = body_labels()
	if not ids.has(current):
		current = current.split("_")[0] + "_average"
	refill(option, ids, labels, current)
	return current


func mark_stale() -> void:
	_stale = true
	if is_visible_in_tree():
		rebuild()


## The shell calls this when the tab is brought forward.
func on_shown() -> void:
	refresh()
	if model == "lowpoly":
		rebuild()
		return
	if _stale or view.assembled == null:
		rebuild()
	else:
		editor.show_status(self, view.assembled)


## Add a panel to the controls column (or to `parent`).
func add_panel(panel: EditorPanel, selection: ItemSelection = null,
		parent: Container = null) -> EditorPanel:
	(parent if parent != null else side).add_child(panel)
	panel.setup(editor, self, selection)
	return panel


# --------------------------------------------------------------- helpers ---

func heading(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)
	parent.add_child(HSeparator.new())
	return label


func row(parent: Container, text: String, control: Control) -> Control:
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(104, 0)
	line.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(control)
	parent.add_child(line)
	return control


func note(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color8(160, 168, 184))
	parent.add_child(label)
	return label


## A picker with "back" and "next" either side, for stepping through bodies
## or heads quickly. Labels say what they do; arrows alone are easy to miss.
func cycler(parent: Container, text: String, values: Array, labels: Array,
		on_change: Callable) -> OptionButton:
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(104, 0)
	line.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in values.size():
		option.add_item(String(labels[i]) if i < labels.size() else String(values[i]), i)
		option.set_item_metadata(i, String(values[i]))
	option.item_selected.connect(func(index: int) -> void:
		on_change.call(String(option.get_item_metadata(index))))
	var back := Button.new()
	back.text = "< back"
	back.pressed.connect(func() -> void:
		var i := posmod(option.selected - 1, option.item_count)
		option.select(i)
		on_change.call(String(option.get_item_metadata(i))))
	var next := Button.new()
	next.text = "next >"
	next.pressed.connect(func() -> void:
		var i := posmod(option.selected + 1, option.item_count)
		option.select(i)
		on_change.call(String(option.get_item_metadata(i))))
	line.add_child(back)
	line.add_child(option)
	line.add_child(next)
	parent.add_child(line)
	return option


## A plain picker. `on_change` gets the chosen value.
func picker(parent: Container, text: String, values: Array, labels: Array,
		on_change: Callable) -> OptionButton:
	var option := OptionButton.new()
	for i in values.size():
		option.add_item(String(labels[i]) if i < labels.size() else String(values[i]), i)
		option.set_item_metadata(i, String(values[i]))
	option.item_selected.connect(func(index: int) -> void:
		on_change.call(String(option.get_item_metadata(index))))
	row(parent, text, option)
	return option


## Select `value` in an option button without firing its signal.
static func select_value(option: OptionButton, value: String) -> void:
	for i in option.item_count:
		if String(option.get_item_metadata(i)) == value:
			option.select(i)
			return


## Refill an option button's entries, keeping `current` selected if present.
static func refill(option: OptionButton, values: Array, labels: Array, current: String) -> void:
	option.clear()
	for i in values.size():
		option.add_item(String(labels[i]) if i < labels.size() else String(values[i]), i)
		option.set_item_metadata(i, String(values[i]))
	select_value(option, current)
	if option.selected < 0 and option.item_count > 0:
		option.select(0)


static func option_value(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func body_labels() -> Array:
	var out: Array = []
	for id in editor.library.body_ids():
		out.append((editor.library.body(id) as BodyDef).display_name())
	return out


static func pose_labels() -> Array:
	var out: Array = []
	for pose in Poses.names():
		out.append(Poses.display_name(pose))
	return out


## Short description for the status line.
func status_text(assembled: CharacterAssembler.Assembled) -> String:
	if assembled == null or assembled.body == null:
		return ""
	return "%s - %s head   |   %d voxels, %d parts%s" % [
		assembled.body.display_name(),
		assembled.head.shape if assembled.head != null else "?",
		assembled.total_voxels(), assembled.order.size(), status_extra()]
