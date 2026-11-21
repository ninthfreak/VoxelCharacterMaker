extends SceneTree
# Writes what lowpoly/ needs from the game, so that nothing there is a second copy of it:
#   --out <file>     the starter wardrobe, as its normal JSON file (items, features, eye sets, palette, outfits)
#   --tables <file>  the test poses (runtime/poses.gd); every special shape's settings with their defaults; the eyes
#                    (the eye box, the lid states, and every eye set's cells with each lid state applied); and the
#                    colours the game works out: each skin tone with its lid colour (and the tones' order), and for
#                    every palette colour the brow and the stubble it gives as a hair colour; and the mouths (Mouths)
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
	var w := Wardrobe.create_default()       # the standard eye set among it
	if out != "":
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
		var tones: Array = []                           # in the game's order, lightest first: JSON sorts a table's names
		for tone in Palette.SKIN_TONE_NAMES:
			tones.append(String(tone))
		_write(tables, {"format": "lowpoly_game_tables", "poses": poses, "specials": specials,
			"eyes": _eyes(w), "skin": _skin(), "skin_order": tones, "default_skin": Palette.DEFAULT_SKIN,
			"hair": _hair(w), "default_brow_hair": Palette.DEFAULT_BROW_HAIR,
			"mouths": {"order": Mouths.names(), "default": Mouths.DEFAULT, "states": Mouths.STATES}})
	quit()


## The eye box, the lid states, and every eye set's cells with each state applied (EyeLids.apply): the game's own
## lid rule, cell by cell, which lowpoly/check.py holds the low-poly eyes to.
func _eyes(w: Wardrobe) -> Dictionary:
	var states := {}
	for state in EyeLids.names():
		states[state] = [EyeLids.eye_state(state, EyeSet.EYE_LEFT), EyeLids.eye_state(state, EyeSet.EYE_RIGHT)]
	var applied := {}
	for set_id in w.eye_sets.keys():
		var eyes: EyeSet = w.eye_sets[set_id]
		var per_state := {}
		for state in EyeLids.names():
			var both := {}
			for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
				var cells := EyeLids.apply(eyes.eye_cells(eye), EyeLids.eye_state(state, eye), eye)
				var list: Array = []
				for cell in cells.keys():
					var c: Vector2i = cell
					list.append([c.x, c.y, String(cells[cell])])
				list.sort()
				both[eye] = list
			per_state[state] = both
		applied[String(set_id)] = per_state
	return {
		"box": {"w": EyeSet.BOX_W, "h": EyeSet.BOX_H, "x0": EyeSet.BOX_X0},
		"order": EyeLids.names(), "default": EyeLids.DEFAULT, "states": states,
		"state_numbers": ["upper", "lower", "pupil_dx", "pupil_dy", "tilt"],
		"flat_roles": [EyeSet.ROLE_WHITE, EyeSet.ROLE_PUPIL, EyeSet.ROLE_LINE],
		"applied": applied,
	}


func _skin() -> Dictionary:
	var out := {}
	for tone in Palette.SKIN_TONE_NAMES:
		out[tone] = {"mid": _rgb(Palette.skin_tones(tone)[1]), "lid": _rgb(Palette.lid_colour(tone))}
	return out


## For every palette colour, taken as a hair colour: the brow it gives, and the stubble it gives on each skin tone.
func _hair(w: Wardrobe) -> Dictionary:
	var out := {}
	for key in w.palette.keys():
		var c: Color = w.palette[key]
		var stubble := {}
		for tone in Palette.SKIN_TONE_NAMES:
			stubble[tone] = _rgb(Palette.stubble_colour(tone, c))
		out[String(key)] = {"brow": _rgb(Palette.brow_from_hair(c)), "stubble": stubble}
	return out


func _rgb(c: Color) -> Array:
	return [c.r8, c.g8, c.b8]


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("wrote ", path)
