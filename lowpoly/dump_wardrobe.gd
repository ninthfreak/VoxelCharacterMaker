extends SceneTree
# Writes what lowpoly/ needs from the game, so that nothing there is a second copy of it:
#   --out <file>     the starter wardrobe, as its normal JSON file (items, palette, outfits)
#   --tables <file>  the test poses (runtime/poses.gd) and every special shape's settings with their defaults
#
#   godot --headless --path . --script lowpoly/dump_wardrobe.gd -- --out lowpoly/_work/starter_wardrobe.json \
#         --tables lowpoly/_work/game_tables.json

func _init() -> void:
	var out := ""
	var tables := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--tables" and i + 1 < args.size():
			tables = args[i + 1]
	if out != "":
		var w := Wardrobe.create_default()
		_write(out, w.to_json())
	if tables != "":
		var poses := {}
		for pose_name in Poses.names():
			var pose := {}
			var p: Dictionary = Poses.get_pose(pose_name)
			for part in p.keys():
				var v: Vector3 = p[part]
				pose[part] = [v.x, v.y, v.z]
			poses[pose_name] = {"label": Poses.display_name(pose_name), "parts": pose}
		var specials := {}
		for type in SpecialItem.types():
			specials[type] = SpecialItem.param_spec(type)
		_write(tables, {"format": "lowpoly_game_tables", "poses": poses, "specials": specials})
	quit()


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("wrote ", path)
