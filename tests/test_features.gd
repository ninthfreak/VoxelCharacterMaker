@tool
class_name TestFeatures
extends RefCounted

## Features (eyes, hair, facial hair) and special shapes anchored to the body.
##
## Eyes, hair and facial hair "work like clothes", so these mostly check that
## they assemble through the same machinery and fit every head. Special shapes
## are "anchored to the bodies at specific points but have a shape that isn't
## otherwise based on the body", so the checks are that every anchor exists on
## every figure and that a shape drawn once lands sensibly on all of them.


static func run(t: TestReport, library: AssetLibrary) -> void:
	_eye_sets(t, library)
	_wardrobe_v2(t, library)
	_anchors(t, library)
	_shapes(t, library)
	_items_with_specials(t, library)
	_panels_clear(t, library)
	_lids(t, library)


# ------------------------------------------------------------- eye sets ----

static func _eye_sets(t: TestReport, library: AssetLibrary) -> void:
	t.group("features: the standard eye set is the shipped faces")
	var eyes := EyeSet.from_library(library)
	t.check_equal(eyes.expression_names().size(), library.expression_names().size(),
		"every shipped expression is in the set")
	for name in library.expression_names():
		var face := library.face(name)
		var from_set := eyes.to_absolute(name)
		t.check(from_set == face.ink_cells(),
			"%s draws exactly the shipped face's painted cells" % name)
		for shape in library.head_shapes():
			t.check(eyes.missing_on_head(name, library.head(shape)).is_empty(),
				"%s fits the %s head" % [name, shape])

	t.group("features: editing an eye set")
	var edited := eyes.duplicate_as("test", "Test")
	t.check(edited.is_symmetric("neutral"), "neutral starts symmetric")
	edited.set_cell("neutral", EyeSet.EYE_LEFT, 0, 2, EyeSet.ROLE_LINE, true)
	t.check(edited.is_symmetric("neutral"), "painting both eyes keeps it symmetric")
	t.check_equal(edited.role_at("neutral", EyeSet.EYE_RIGHT, 0, 2), EyeSet.ROLE_LINE,
		"and the other eye has the cell")
	edited.set_cell("neutral", EyeSet.EYE_LEFT, 0, 2, EyeSet.ROLE_SKIN, false)
	t.check(not edited.is_symmetric("neutral"), "painting one eye alone breaks symmetry")
	t.check_equal(edited.role_at("neutral", EyeSet.EYE_LEFT, 0, 2), EyeSet.ROLE_SKIN,
		"and skin clears the cell")

	t.check(edited.add_expression("squint", "happy"), "an expression can be added")
	t.check(edited.to_absolute("squint") == edited.to_absolute("happy"),
		"copied from another")
	t.check(not edited.remove_expression(EyeSet.NEUTRAL), "neutral cannot be removed")
	t.check(edited.rename_expression("squint", "glare"), "an expression can be renamed")
	t.check_equal(edited.resolve("no such face"), EyeSet.NEUTRAL,
		"a missing expression falls back to neutral, so the eyes never vanish")

	var json := edited.to_json()
	var again := EyeSet.from_json("test", json)
	t.check(JSON.stringify(again.to_json(), "", true) == JSON.stringify(json, "", true),
		"an eye set round-trips")

	t.group("features: an eye set draws through the assembler")
	var w := Wardrobe.create_default(library)
	t.check(w.eye_set("standard") != null, "the default wardrobe has the standard set")
	var with_set := _figure(library, w, "male_average", "oval", "angry", "standard", [])
	var without := _figure(library, w, "male_average", "oval", "angry", "", [])
	var a := _face_cells(with_set)
	var b := _face_cells(without)
	t.check(a.keys().size() == b.keys().size() and not a.is_empty(),
		"the same cells are painted with the eye set as without it",
		"%d vs %d" % [a.size(), b.size()])
	# A colourway changes the pupil.
	var eyes2: EyeSet = w.eye_set("standard")
	eyes2.add_colourway("blue")
	eyes2.set_palette_key("blue", EyeSet.ROLE_PUPIL, "eye_blue")
	var blue := _figure(library, w, "male_average", "oval", "neutral", "standard", [],
		"blue")
	var head := blue.part(BodyDef.HEAD_PART)
	var found_blue := false
	for cell in head.cells.keys():
		if head.colours.get(cell) == w.colour("eye_blue"):
			found_blue = true
			break
	t.check(found_blue, "an eye colourway colours the pupils from the palette")


static func _face_cells(assembled: CharacterAssembler.Assembled) -> Dictionary:
	var out := {}
	var head := assembled.part(BodyDef.HEAD_PART)
	for cell in head.cells.keys():
		if int(head.sources.get(cell, 0)) == CharacterAssembler.Source.FACE:
			out[cell] = true
	return out


# ---------------------------------------------------------- wardrobe v2 ----

static func _wardrobe_v2(t: TestReport, library: AssetLibrary) -> void:
	t.group("features: the wardrobe file keeps features and eye sets apart")
	var w := Wardrobe.create_default(library)
	var json := w.to_json()
	t.check_equal(int(json["version"]), Wardrobe.VERSION, "written as the current version")
	t.check((json["features"] as Dictionary).has("hair"), "hair has its own section")
	t.check(((json["features"] as Dictionary)["hair"] as Dictionary).has("short_crop"),
		"with the hair styles in it")
	t.check(not (json["items"] as Dictionary).has("short_crop"),
		"and not among the clothes")
	t.check((json["eye_sets"] as Dictionary).has("standard"), "eye sets have their own")

	var once := w.to_text()
	var twice := Wardrobe.from_json(JSON.parse_string(once)).to_text()
	t.check(twice == once, "a wardrobe with features and eye sets round-trips")

	t.check(w.clothing_ids().has("tunic") and not w.clothing_ids().has("short_crop"),
		"clothing lists hold only clothing")
	t.check(w.feature_ids("hair").has("short_crop"), "and hair lists only hair")

	t.group("features: version 1 files still load")
	var v1 := {
		"format": Wardrobe.FORMAT, "version": 1,
		"palette": {"ink": "#262a3a"},
		"items": {
			"old_hair": {"name": "Old hair", "category": "hair", "draw_order": 70,
				"kind": "parametric", "edge_style": "soft", "mirror": true,
				"roles": ["hair"], "colourways": {"default": {"hair": "ink"}},
				"coverage": {"crown.L.F": {"role": "hair", "bulk": 1}}},
			"old_skirt": {"name": "Old skirt", "category": "bottom", "draw_order": 10,
				"kind": "special", "special_type": "skirt",
				"special_params": {"length": "to_knee", "flare": 2.0},
				"edge_style": "soft", "mirror": true, "roles": ["cloth"],
				"colourways": {"default": {"cloth": "ink"}}},
		},
		"outfits": {},
	}
	var migrated := Wardrobe.from_json(v1)
	t.check(migrated != null, "a version 1 file loads")
	if migrated != null:
		t.check_equal(migrated.item("old_hair").slot, "hair",
			"its hair item moves to the hair slot")
		t.check_equal(migrated.item("old_skirt").special_types(), ["skirt"] as Array[String],
			"its special item becomes an item with one special shape")
		t.check_equal(typeof(migrated.item("old_skirt").special_params(0)["flare"]),
			TYPE_INT, "with its parameters normalised")


# ---------------------------------------------------------------- anchors --

static func _anchors(t: TestReport, library: AssetLibrary) -> void:
	t.group("features: every anchor exists on every figure")
	var w := Wardrobe.new()
	for id in library.body_ids():
		for shape in library.head_shapes():
			var assembled := _figure(library, w, id, shape, "neutral", "", [])
			var cells := {}
			for name in assembled.order:
				cells[name] = assembled.part(String(name)).cells
			for anchor_name in Anchors.names():
				var anchor := Anchors.find(cells, anchor_name)
				if anchor == null:
					t.check(false, "%s / %s head: anchor %s found" % [id, shape, anchor_name])
					continue
				var part_cells: Dictionary = cells[anchor.part]
				# The origin is the first voxel outside, touching the surface.
				var ok := not part_cells.has(anchor.origin) \
					and part_cells.has(anchor.origin - anchor.out)
				if not ok:
					t.check(false, "%s / %s head: anchor %s sits on the surface"
						% [id, shape, anchor_name], str(anchor.origin))
	t.note("%d anchors checked on %d bodies x %d heads" % [
		Anchors.names().size(), library.body_ids().size(), library.head_shapes().size()])


# ----------------------------------------------------------------- shapes --

static func _shapes(t: TestReport, library: AssetLibrary) -> void:
	t.group("features: a drawn beard fits every head")
	var w := Wardrobe.create_default(library)
	var per_head := {}
	for shape in library.head_shapes():
		var assembled := _figure(library, w, "male_average", shape, "neutral", "standard",
			[{"item": "short_beard", "colourway": "default"}])
		t.check(assembled.warnings.is_empty(), "the beard generates on the %s head" % shape,
			", ".join(assembled.warnings))
		var head := assembled.part(BodyDef.HEAD_PART)
		var beard := {}
		for cell in head.cells.keys():
			if String(head.owners.get(cell, "")) == "short_beard":
				beard[cell] = true
		per_head[shape] = beard.size()
		t.check(not beard.is_empty(), "the %s head grows a beard" % shape)
		t.check(VoxelTopology.is_mirror_symmetric(beard), "the beard is symmetric on %s" % shape)
		# Wrapped: every beard voxel touches the head it grew on.
		var head_cells: Dictionary = library.head(shape).cells
		var floating := 0
		for cell2 in beard.keys():
			var touching := false
			for offset in VoxelAxes.NEIGHBOURS:
				if head_cells.has((cell2 as Vector3i) + offset) \
						or beard.has((cell2 as Vector3i) + offset):
					touching = true
					break
			if not touching:
				floating += 1
		t.check_equal(floating, 0, "no beard voxel floats free of the %s head" % shape)
		# And the eyes are still all there.
		var eyes := 0
		for cell3 in head.cells.keys():
			if int(head.sources.get(cell3, 0)) == CharacterAssembler.Source.FACE:
				eyes += 1
		t.check(eyes > 0, "the beard leaves the eyes visible on %s" % shape)
	t.check(int(per_head.get("heart", 0)) < int(per_head.get("round", 0)),
		"the narrow heart jaw gets a smaller beard than the round one",
		str(per_head))

	t.group("features: wrapped, rigid and recolour placement")
	var item := GarmentItem.create("test_shape", "Test shape", "accessory")
	item.roles = ["cloth"]
	item.colourways = {"default": {"cloth": "rust"}}
	var at := item.add_special("shape")
	item.set_special_param(at, "anchor", "chest")
	item.set_special_param(at, "mirror", false)
	item.set_special_param(at, "cells", [[0, 0, 0, "cloth"], [0, 1, 0, "cloth"]])
	w.add_item(item)
	var worn := [{"item": "test_shape", "colourway": "default"}]
	for wrap in [true, false]:
		item.set_special_param(at, "wrap", wrap)
		var fig := _figure(library, w, "female_heavy", "round", "neutral", "", worn)
		var chest := fig.part("chest")
		var n := 0
		for cell4 in chest.cells.keys():
			if String(chest.owners.get(cell4, "")) == "test_shape":
				n += 1
		t.check_equal(n, 2, "%s: two drawn cells, two voxels" % ("wrapped" if wrap else "rigid"))

	# Depth -1 recolours the surface instead of adding to it.
	item.set_special_param(at, "wrap", true)
	item.set_special_param(at, "cells", [[0, -1, 0, "cloth"], [1, -1, 0, "cloth"]])
	var bare := _figure(library, w, "male_slim", "round", "neutral", "", [])
	var painted := _figure(library, w, "male_slim", "round", "neutral", "", worn)
	t.check_equal(painted.total_voxels(), bare.total_voxels(),
		"a recolour shape adds no voxels")
	var repainted := 0
	var chest2 := painted.part("chest")
	for cell5 in chest2.cells.keys():
		if String(chest2.owners.get(cell5, "")) == "test_shape":
			repainted += 1
	t.check_equal(repainted, 2, "it repaints the two surface voxels")


# ---------------------------------------------- items with several shapes --

static func _items_with_specials(t: TestReport, library: AssetLibrary) -> void:
	t.group("features: one item, regions and special shapes together")
	var w := Wardrobe.create_default(library)
	var dress := w.item("dress")
	t.check(dress.has_coverage() and dress.is_special(),
		"the dress has a bodice of regions and a skirt shape")
	for id in library.body_ids():
		var fig := _figure(library, w, id, "round", "neutral", "",
			[{"item": "dress", "colourway": "default"}])
		t.check(fig.warnings.is_empty(), "%s: the dress generates" % id,
			", ".join(fig.warnings))
		var bodice := 0
		for cell in fig.part("chest").cells.keys():
			if String(fig.part("chest").owners.get(cell, "")) == "dress":
				bodice += 1
		var panels := 0
		for name in fig.order:
			if fig.part(String(name)).is_panel():
				panels += 1
		t.check(bodice > 0 and panels > 0, "%s: both the bodice and the skirt" % id,
			"bodice %d, panels %d" % [bodice, panels])

	t.group("features: two skirts are two sets of panels")
	var extra := GarmentItem.create("over_skirt", "Over skirt", "bottom")
	extra.roles = ["cloth", "hem"]
	extra.colourways = {"default": {"cloth": "moss", "hem": "ochre"}}
	extra.add_special("skirt")
	w.add_item(extra)
	var both := _figure(library, w, "female_average", "round", "neutral", "", [
		{"item": "dress", "colourway": "default"},
		{"item": "over_skirt", "colourway": "default"},
	])
	var panel_names: Array[String] = []
	for name2 in both.order:
		if both.part(String(name2)).is_panel():
			panel_names.append(String(name2))
	t.check_equal(panel_names.size(), 8,
		"a dress skirt and a second skirt make eight panels, not four merged ones")

	t.group("features: the cape and the hooded cloak")
	for id2 in library.body_ids():
		var fig2 := _figure(library, w, id2, "round", "neutral", "",
			[{"item": "cloak", "colourway": "default"}])
		t.check(fig2.warnings.is_empty(), "%s: the cloak generates" % id2,
			", ".join(fig2.warnings))
		var cape: CharacterAssembler.Part = null
		for name3 in fig2.order:
			var p := fig2.part(String(name3))
			if p.is_panel() and String(name3).ends_with(CapeGenerator.PANEL):
				cape = p
		t.check(cape != null and cape.count() > 0, "%s: the cape hangs" % id2)
		if cape == null:
			continue
		var body_cells := fig2.body.all_cells()
		var inside := 0
		for cell6 in cape.cells.keys():
			if body_cells.has(cell6):
				inside += 1
		t.check_equal(inside, 0, "%s: the cape clears the body at rest" % id2)

	var stride := Poses.get_pose(Poses.MID_STRIDE)
	var sit := Poses.get_pose(Poses.SITTING)
	t.check(Poses.panel_rotation(SpecialItem.DRIVER_TRAIL, stride).x < 0.0,
		"a cape trails back in a stride")
	t.check(is_zero_approx(Poses.panel_rotation(SpecialItem.DRIVER_TRAIL, sit).x),
		"and does not swing forward through the body when sitting")


static func _figure(library: AssetLibrary, w: Wardrobe, body: String, head: String,
		expression: String, eye_set: String, worn: Array,
		eye_colourway: String = "") -> CharacterAssembler.Assembled:
	var request := CharacterAssembler.Request.make(library, body, head, expression)
	request.wardrobe = w
	request.worn = worn
	request.eye_set_id = eye_set
	request.eye_colourway = eye_colourway
	return CharacterAssembler.assemble(request)


# ---------------------------------------------------------- panels clear ----

## A hanging panel is its own rigid part. If it shares a voxel with another
## part, the two draw faces in the same place and flicker (z-fight), and they
## tear apart when the panel swings. Capes and skirts must hang clear of what
## is worn under them, not just of the body.
static func _panels_clear(t: TestReport, library: AssetLibrary) -> void:
	t.group("specials: hanging panels clear everything worn under them")
	var w := Wardrobe.create_default(library)
	var looks: Array = []
	for outfit in w.outfit_names():
		looks.append([outfit, w.outfit(outfit)])
	looks.append(["dress over trousers", [{"item": "trousers", "colourway": "default"},
		{"item": "dress", "colourway": "default"}]])
	for look in looks:
		var shared := 0
		var example := ""
		for body in library.body_ids():
			var a := _figure(library, w, body, "round", "neutral", "", look[1])
			# Panels against everything else. (Garments on two body parts can
			# also meet in one cell -- trousers in the gap between the thighs --
			# which is the separate, deferred trouser problem.)
			var fixed := {}
			for name in a.order:
				var part := a.part(String(name))
				if not part.is_panel():
					for cell in part.cells.keys():
						fixed[cell] = String(name)
			var panel_of := {}
			for name in a.order:
				var part := a.part(String(name))
				if not part.is_panel():
					continue
				for cell in part.cells.keys():
					var other := String(fixed.get(cell, panel_of.get(cell, "")))
					if not other.is_empty():
						shared += 1
						if example.is_empty():
							example = "%s: %s and %s at %s" % [body, other, name, cell]
					panel_of[cell] = String(name)
		t.check(shared == 0, "%s: no panel shares a voxel with another part, on any body" % look[0],
			"%d shared, e.g. %s" % [shared, example])


# ------------------------------------------------------------ lids, brows ----

static func _roles_in(cells: Dictionary, role: String) -> Array:
	var out: Array = []
	for cell in cells.keys():
		if String(cells[cell]) == role:
			out.append(cell)
	return out


static func _lids(t: TestReport, library: AssetLibrary) -> void:
	t.group("eyes: the G7 open eye, the same size on every head")
	var w := Wardrobe.create_default(library)
	var eyes := w.eye_set(w.first_eye_set_id())
	var open := eyes.eye_cells(EyeSet.NEUTRAL, EyeSet.EYE_LEFT)
	t.check_equal(EyeSet.BOX_W * 100 + EyeSet.BOX_H, 506, "the eye box is 5 wide x 6 tall")
	t.check_equal(_roles_in(open, EyeSet.ROLE_PUPIL).size(), 2, "neutral has a 1 x 2 pupil")
	t.check_equal(_roles_in(open, EyeSet.ROLE_WHITE).size(), 5 * 6 - 4 - 2,
		"and is white everywhere else but its four rounded corners")
	t.check(_roles_in(open, EyeSet.ROLE_PUPIL).has(Vector2i(2, 2))
		and _roles_in(open, EyeSet.ROLE_PUPIL).has(Vector2i(2, 3)),
		"the pupil is centred: column 2, rows 2-3")
	for shape in library.head_shapes():
		var head := library.head(shape)
		var missing := 0
		var blocked := 0
		for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
			for c in EyeSet.BOX_W:
				for r in EyeSet.BOX_H + 1:   # the box and the brow row above it
					var v := EyeSet.cell_to_voxel(c, r, eye)
					if not head.cells.has(v):
						missing += 1
					if head.cells.has(v + Vector3i(0, -1, 0)):
						blocked += 1
		t.check(missing == 0 and blocked == 0,
			"%s head has a flat face for the whole eye box and brow row" % shape,
			"%d missing, %d covered" % [missing, blocked])

	t.group("eyes: lids and brows")
	var h := EyeSet.BOX_H
	var neutral := EyeLids.apply(open, EyeLids.eye_state("neutral", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	var brow_rows := {}
	for cell in _roles_in(neutral, EyeLids.ROLE_BROW):
		brow_rows[(cell as Vector2i).y] = true
	t.check_equal(brow_rows.keys(), [h - 1], "neutral: the brow covers the eye's top row")
	t.check_equal(_roles_in(neutral, EyeLids.ROLE_BROW).size(), EyeSet.BOX_W,
		"and is the full eye width")
	t.check(_roles_in(neutral, EyeLids.ROLE_LID).is_empty(), "with no lid showing")
	var wide := EyeLids.apply(open, EyeLids.eye_state("wide_open", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	t.check(wide.get(Vector2i(0, h)) == EyeLids.ROLE_BROW and wide.get(Vector2i(4, h)) == EyeLids.ROLE_BROW,
		"wide open: the brow is raised to the row above the eye, full width")
	var tired := EyeLids.apply(open, EyeLids.eye_state("tired", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	t.check(tired.get(Vector2i(2, h - 3)) == EyeLids.ROLE_BROW, "tired: the brow leads the lid down")
	t.check(tired.get(Vector2i(2, h - 1)) == EyeLids.ROLE_LID, "with lid above it")
	t.check(tired.get(Vector2i(2, 0)) == EyeLids.ROLE_LID, "the lower lid is lid colour")
	t.check(tired.get(Vector2i(2, 1)) == EyeSet.ROLE_PUPIL, "and the pupil has moved down")
	var sus := EyeLids.apply(open, EyeLids.eye_state("suspicious", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	var low_brow := false
	for cell in _roles_in(sus, EyeLids.ROLE_BROW):
		low_brow = low_brow or (cell as Vector2i).y < 2
	t.check(not low_brow, "the lower lid has no dark line")
	var blink := EyeLids.apply(open, EyeLids.eye_state("blink", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	t.check(_roles_in(blink, EyeSet.ROLE_WHITE).is_empty() and _roles_in(blink, EyeSet.ROLE_PUPIL).is_empty(),
		"blink: no white or pupil shows")
	t.check_equal(_roles_in(blink, EyeLids.ROLE_BROW).size(), EyeSet.BOX_W, "just one brow line")
	var wink_l := EyeLids.apply(open, EyeLids.eye_state("wink", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	var wink_r := EyeLids.apply(open, EyeLids.eye_state("wink", EyeSet.EYE_RIGHT), EyeSet.EYE_RIGHT)
	t.check(not _roles_in(wink_l, EyeSet.ROLE_WHITE).is_empty() and _roles_in(wink_r, EyeSet.ROLE_WHITE).is_empty(),
		"wink: one eye open, the other closed")

	t.group("eyes: lid, brow and skin colours")
	var tail := {"item": "ponytail", "colourway": "default"}
	var req := CharacterAssembler.Request.make(library, "male_average", "round", "neutral")
	req.wardrobe = w
	req.eye_set_id = eyes.id
	req.features = [tail]
	var brow := CharacterAssembler.brow_colour(req)
	var hair_tones := w.tones_for("ponytail", "default", "hair")
	t.check(brow.is_equal_approx(hair_tones[2]), "the brow is the hair colour one shade darker")
	req.features = []
	t.check(CharacterAssembler.brow_colour(req).is_equal_approx(
		Palette.brow_from_hair(w.colour(Palette.DEFAULT_BROW_HAIR))), "bald: the brow of dark brown hair")
	req.brow_colour = Color8(10, 20, 30)
	t.check(CharacterAssembler.brow_colour(req).is_equal_approx(Color8(10, 20, 30)), "a brow colour set wins")
	req.brow_colour = Color(0, 0, 0, 0)
	for tone in Palette.SKIN_TONE_NAMES:
		req.skin_tone = tone
		req.lids = "tired"
		var a := CharacterAssembler.assemble(req)
		var head_part := a.part(BodyDef.HEAD_PART)
		var mids := Palette.skin_tones(tone)
		var lid_ok := false
		var skin_ok := false
		for cell in head_part.cells.keys():
			var src := int(head_part.sources.get(cell, 0))
			if src == CharacterAssembler.Source.FACE and head_part.colours[cell].is_equal_approx(Palette.lid_colour(tone)):
				lid_ok = true
			if src == CharacterAssembler.Source.SKIN and int(head_part.tones[cell]) == Shading.Tone.MID:
				skin_ok = skin_ok or head_part.colours[cell].is_equal_approx(mids[1]) \
					or head_part.colours[cell].is_equal_approx(mids[1] * Palette.FACE_MUL_FRONT)
		t.check(skin_ok, "%s skin tone colours the skin" % tone)
		t.check(lid_ok, "%s: the lid is the skin half a shade darker" % tone)
	t.check(Palette.lid_colour("light").is_equal_approx(Palette.SKIN_MID.lerp(Palette.SKIN_DARK, 0.5)),
		"half a shade: halfway from the skin's mid to its dark")

	t.group("eyes: every lid state fits every head")
	for shape in library.head_shapes():
		var bad: Array[String] = []
		for state in EyeLids.names():
			var r2 := CharacterAssembler.Request.make(library, "female_slim", shape, "neutral")
			r2.wardrobe = w
			r2.eye_set_id = eyes.id
			r2.lids = state
			var expected := 0
			for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
				expected += EyeLids.apply(eyes.eye_cells(EyeSet.NEUTRAL, eye),
					EyeLids.eye_state(state, eye), eye).size()
			if _face_cells(CharacterAssembler.assemble(r2)).size() != expected:
				bad.append(state)
		t.check(bad.is_empty(), "%s head: every lid state lands on the face" % shape, ", ".join(bad))

