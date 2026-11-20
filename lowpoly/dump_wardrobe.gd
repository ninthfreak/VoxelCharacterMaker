extends SceneTree
# Writes the project's starter wardrobe out as its normal JSON file, for lowpoly/dress.py to read.
#   godot --headless --path . --script lowpoly/dump_wardrobe.gd -- --out lowpoly/_work/starter_wardrobe.json

func _init() -> void:
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var w := Wardrobe.create_default()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(w.to_json(), "  "))
	f.close()
	print("wrote ", out)
	quit()
