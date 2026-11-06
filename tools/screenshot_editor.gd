extends SceneTree

## Screenshot the editor, so its layout can actually be looked at.
##
## The editor builds its whole UI in code and the acceptance tests run headless,
## so nothing else in this project ever renders a control. A screenshot is the
## only check that the panels lay out, the preview fills its pane, and the text
## fits. Needs a real GL context, so not under --headless:
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script res://tools/screenshot_editor.gd -- --out docs/renders --tab Bodies
##
##   --tab NAME        the tab to bring forward (Bodies, Face & Hair, Clothes, Preview)
##   --section NAME    a sub-tab within it (Eyes, Hair, Facial hair; Item, Colours...)
##   --edit-body / --edit-head   open the body or head in the Bodies tab
##   --row N           the slice row to show while editing
##   --name NAME       the file name, without .png
##   --select ID       select a wardrobe item (in its own section)
##   --scroll PIXELS   scroll the controls column down

const SETTLE_FRAMES := 14
const SIZE := Vector2i(1800, 1000)

var _out := "docs/renders"
var _tab := ""
var _frames := 0
var _editor: Control = null
var _edit := ""
var _row := -1
var _section := ""
var _name := ""
var _select := ""
var _scroll := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if String(args[i]) == "--out" and i + 1 < args.size():
			_out = String(args[i + 1])
		elif String(args[i]) == "--tab" and i + 1 < args.size():
			_tab = String(args[i + 1])
		elif String(args[i]) == "--edit-body":
			_edit = "body"
		elif String(args[i]) == "--edit-head":
			_edit = "head"
		elif String(args[i]) == "--row" and i + 1 < args.size():
			_row = int(args[i + 1])
		elif String(args[i]) == "--section" and i + 1 < args.size():
			_section = String(args[i + 1])
		elif String(args[i]) == "--name" and i + 1 < args.size():
			_name = String(args[i + 1])
		elif String(args[i]) == "--select" and i + 1 < args.size():
			_select = String(args[i + 1])
		elif String(args[i]) == "--scroll" and i + 1 < args.size():
			_scroll = int(args[i + 1])


func _process(_delta: float) -> bool:
	_frames += 1
	# The window has to exist before its size can be set, and the editor has to
	# be in the tree before it can be told which tab to show.
	if _frames == 1:
		root.size = SIZE
		root.content_scale_size = SIZE
		return false
	if _frames == 2:
		var packed: PackedScene = load("res://editor/editor_main.tscn")
		_editor = packed.instantiate()
		root.add_child(_editor)
		return false
	if _frames == 3 and _editor != null:
		if not _tab.is_empty():
			_editor.call("show_tab", _tab)
		if not _edit.is_empty():
			var bodies: Object = _editor.get("bodies")
			bodies.call("start_editing", _edit)
			if _row >= 0:
				bodies.call("set_row", _row)
		var ws: Object = _editor.call("_current")
		if not _select.is_empty():
			# Select an item in whichever selection holds its section.
			var wardrobe: Object = _editor.get("wardrobe")
			var it: Object = wardrobe.call("item", _select)
			if it != null:
				var slot := String(it.get("slot"))
				var target: Object = null
				if slot == "hair":
					target = ws.get("hair")
				elif slot == "facial_hair":
					target = ws.get("facial_hair")
				else:
					target = ws.get("clothes")
				if target != null:
					target.call("select", _select)
		if not _section.is_empty() and ws.has_method("show_section"):
			ws.call("show_section", _section)
		return false
	if _frames == 8 and _scroll > 0 and _editor != null:
		var current: Object = _editor.call("_current")
		var scroller := (current.get("side") as Node).get_parent() as ScrollContainer
		if scroller != null:
			scroller.scroll_vertical = _scroll
		return false
	if _frames < SETTLE_FRAMES:
		return false

	var image := root.get_texture().get_image()
	if image == null:
		printerr("no image: a real GL context is needed")
		return true
	var name := _name
	if name.is_empty():
		name = "editor" if _tab.is_empty() else "editor_%s" % _tab.to_lower().replace(" & ", "_")
	var path := "%s/%s.png" % [_out.rstrip("/"), name]
	var err := image.save_png(path)
	if err != OK:
		printerr("could not write %s (error %d)" % [path, err])
	else:
		print("wrote %s" % path)
	return true
