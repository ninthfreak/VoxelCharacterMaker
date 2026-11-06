extends SceneTree

## Screenshot the editor, so its layout can actually be looked at.
##
## The editor builds its whole UI in code and the acceptance tests run headless,
## so nothing else in this project ever renders a control. A screenshot is the
## only check that the panels lay out, the preview fills its pane, and the text
## fits. Needs a real GL context, so not under --headless:
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script res://tools/screenshot_editor.gd -- --out docs/renders --tab Body
##
## --tab names the tab to bring forward; omit it for whatever opens first.

const SETTLE_FRAMES := 12
const SIZE := Vector2i(1800, 1000)

var _out := "docs/renders"
var _tab := ""
var _frames := 0
var _editor: Control = null
var _edit_body := false
var _row := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if String(args[i]) == "--out" and i + 1 < args.size():
			_out = String(args[i + 1])
		elif String(args[i]) == "--tab" and i + 1 < args.size():
			_tab = String(args[i + 1])
		elif String(args[i]) == "--edit-body":
			_edit_body = true
		elif String(args[i]) == "--row" and i + 1 < args.size():
			_row = int(args[i + 1])


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
		if not _tab.is_empty() and _editor.has_method("show_tab"):
			_editor.call("show_tab", _tab)
		if _edit_body:
			var panel: Variant = _editor.get("body_panel")
			if panel != null and (panel as Object).has_method("start_editing_preview_body"):
				(panel as Object).call("start_editing_preview_body")
				if _row >= 0:
					(panel as Object).call("set_row", _row)
		return false
	if _frames < SETTLE_FRAMES:
		return false

	var image := root.get_texture().get_image()
	if image == null:
		printerr("no image: a real GL context is needed")
		return true
	var name := "editor" if _tab.is_empty() else "editor_%s" % _tab.to_lower()
	var path := "%s/%s.png" % [_out.rstrip("/"), name]
	var err := image.save_png(path)
	if err != OK:
		printerr("could not write %s (error %d)" % [path, err])
	else:
		print("wrote %s" % path)
	return true
