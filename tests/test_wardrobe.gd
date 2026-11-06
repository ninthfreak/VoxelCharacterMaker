@tool
class_name TestWardrobe
extends RefCounted

## SPEC.md section 12: "Wardrobe file round-trips unchanged (save -> load ->
## save is identical)." Plus the section 7 model rules: the mirror flag is not
## destructive, colourways resolve, and an outfit records items and colourways.

const TEMP_PATH := "user://test_wardrobe_round_trip.json"


static func run(t: TestReport, library: AssetLibrary) -> void:
	t.group("wardrobe: round-trip")
	var original := Wardrobe.create_default()
	var first := original.to_text()

	var reloaded := Wardrobe.from_json(original.to_json())
	t.check(reloaded != null, "a wardrobe reloads from its own JSON")
	if reloaded == null:
		return
	t.check(reloaded.to_text() == first,
		"save -> load -> save is byte identical",
		"%d vs %d bytes" % [first.length(), reloaded.to_text().length()])

	# And through the disk, which is what the requirement actually means.
	var error := original.save_to(TEMP_PATH)
	t.check(error.is_empty(), "the wardrobe saves to disk", error)
	var from_disk := Wardrobe.load_from(TEMP_PATH)
	t.check(from_disk != null, "the wardrobe loads back from disk")
	if from_disk != null:
		t.check(from_disk.to_text() == first, "the file on disk round-trips unchanged")
		var second_error := from_disk.save_to(TEMP_PATH)
		t.check(second_error.is_empty(), "it saves again", second_error)
		var text_on_disk := ""
		var handle := FileAccess.open(TEMP_PATH, FileAccess.READ)
		if handle != null:
			text_on_disk = handle.get_as_text()
			handle.close()
		t.check(text_on_disk == first, "the bytes on disk match the first write")
	DirAccess.remove_absolute(TEMP_PATH)

	# The default wardrobe is the easy case: every field in it is one that
	# from_json casts back. A real file also has special items, whose free-form
	# parameters are not cast, plus every non-default setting. That is where
	# the round-trip actually broke (an int 1 came back as 1.0).
	t.group("wardrobe: round-trip of a full file")
	var full := Wardrobe.create_default()
	full.set_colour("sage", Color8(141, 160, 120))
	var skirt := GarmentItem.create("skirt", "Skirt", "bottom")
	skirt.add_special("skirt")
	skirt.set_special_param(0, "flare", 3)
	skirt.roles = ["cloth", "hem"]
	skirt.colourways = {"default": {"cloth": "moss", "hem": "ochre"},
		"dusk": {"cloth": "plum", "hem": "bone"}}
	full.add_item(skirt)
	var hood := GarmentItem.create("hood", "Hood", "hat")
	hood.add_special("hood")
	hood.roles = ["cloth", "lining"]
	hood.colourways = {"default": {"cloth": "ink", "lining": "rust"}}
	full.add_item(hood)
	var sash := GarmentItem.create("sash", "Sash", "accessory")
	sash.mirror = false
	sash.edge_style = BulkBuilder.EdgeStyle.HARD
	sash.draw_order = 57
	sash.colourways = {"default": {"cloth": "sage"}}
	sash.set_region("upper_chest.L.F", "cloth", 2)
	sash.set_region("lower_chest.R.F", "cloth", 0)
	full.add_item(sash)
	full.save_outfit("travel", [
		{"item": "skirt", "colourway": "dusk"},
		{"item": "hood", "colourway": "default"},
		{"item": "sash", "colourway": "default"},
	])

	var once := full.to_text()
	var twice := Wardrobe.from_json(JSON.parse_string(once)).to_text()
	var thrice := Wardrobe.from_json(JSON.parse_string(twice)).to_text()
	t.check(twice == once, "a file with special items round-trips byte for byte",
		"first difference at line %d" % _first_difference(once, twice))
	t.check(thrice == twice, "and stays identical on every further round-trip")

	# Through the disk as well, since that is what the requirement means.
	var path2 := "user://test_wardrobe_full.json"
	t.check(full.save_to(path2).is_empty(), "the full wardrobe saves")
	var back := Wardrobe.load_from(path2)
	t.check(back != null and back.to_text() == once, "and reloads to the same bytes")
	DirAccess.remove_absolute(path2)

	# The special parameters come back as the type they went in as.
	var reloaded_skirt := Wardrobe.from_json(JSON.parse_string(once)).item("skirt")
	t.check_equal(typeof(reloaded_skirt.special_params(0)["flare"]), TYPE_INT,
		"an int parameter reloads as an int, not a float")

	t.group("wardrobe: colours survive exactly")
	for key in original.palette_names():
		var colour := original.colour(key)
		var round_tripped := JsonIO.hex_to_colour(JsonIO.colour_to_hex(colour))
		t.check(colour.to_html(false) == round_tripped.to_html(false),
			"palette colour %s survives hex" % key)
	t.check(original.colour("no such colour") == Color.MAGENTA,
		"a missing palette colour is loud, not quietly plausible")

	t.group("wardrobe: items and colourways")
	var tunic := original.item("tunic")
	t.check(tunic != null, "the starter tunic is present")
	if tunic == null:
		return
	t.check(tunic.colourway_names().size() >= 2, "the tunic has more than one colourway")
	var tones_default := original.tones_for("tunic", "default", "cloth")
	var tones_rust := original.tones_for("tunic", "rust", "cloth")
	t.check(tones_default[1] != tones_rust[1],
		"two colourways of one item resolve to different colours")
	t.check_equal(tones_default.size(), 3, "a colour resolves to a light/mid/dark triple")

	# The garment colour formula, SPEC section 6.
	var base := Color8(100, 100, 100)
	var tones := Palette.garment_tones(base)
	t.check(tones[0].r > base.r, "the light tone is lighter than the base")
	t.check(tones[2].r < base.r, "the dark tone is darker than the base")
	t.check_near(tones[2].r, base.r * Palette.GARMENT_DARK_SCALE,
		"dark is the base times 0.68")
	t.check_near(tones[0].r, base.r + (1.0 - base.r) * Palette.GARMENT_LIGHT_LIFT,
		"light lifts the base 28 per cent toward white")

	t.group("wardrobe: the mirror flag is not destructive")
	var item := GarmentItem.create("sash", "Sash", "accessory")
	item.roles = ["cloth"]
	item.colourways = {"default": {"cloth": "ochre"}}
	item.mirror = false
	item.set_region("upper_chest.L.F", "cloth", 1)
	item.set_region("lower_chest.R.F", "cloth", 2)
	t.check_equal(item.effective_coverage().size(), 2,
		"with mirror off both sides count")

	item.mirror = true
	var mirrored := item.effective_coverage()
	t.check(mirrored.has("upper_chest.L.F") and mirrored.has("upper_chest.R.F"),
		"with mirror on the left side is reflected")
	t.check(not mirrored.has("lower_chest.R.F"),
		"with mirror on, right-side-only work is ignored")
	item.mirror = false
	t.check(item.coverage.has("lower_chest.R.F"),
		"turning mirror on and off again kept the right-side work")

	t.group("wardrobe: outfits")
	var names := original.outfit_names()
	t.check(not names.is_empty(), "there is a starter outfit")
	if not names.is_empty():
		var worn := original.outfit(names[0])
		t.check(not worn.is_empty(), "the outfit names items")
		for entry in worn:
			var e: Dictionary = entry
			var worn_item := original.item(String(e["item"]))
			t.check(worn_item != null, "outfit item %s exists" % e["item"])
			if worn_item != null:
				t.check(worn_item.has_colourway(String(e["colourway"])),
					"outfit colourway %s exists on %s" % [e["colourway"], e["item"]])

	# An outfit that names a deleted item must not break on load.
	original.save_outfit("test", [{"item": "ghost", "colourway": "default"}])
	t.check_equal(original.outfit("test").size(), 0,
		"an outfit silently drops items that are no longer in the wardrobe")

	t.group("wardrobe: refuses what it should")
	t.check(Wardrobe.from_json({"format": "something else"}) == null,
		"a file that is not a wardrobe is refused")
	t.check(Wardrobe.from_json({"format": Wardrobe.FORMAT, "version": 999}) == null,
		"a file from a newer version is refused rather than half-read")


static func _first_difference(a: String, b: String) -> int:
	var la := a.split("\n")
	var lb := b.split("\n")
	for i in mini(la.size(), lb.size()):
		if la[i] != lb[i]:
			return i + 1
	return mini(la.size(), lb.size()) + 1
