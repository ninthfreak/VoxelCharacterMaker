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
	_skirts(t, library)
	_straps(t, library)
	_lids(t, library)


# ------------------------------------------------------------- eye sets ----

static func _eye_sets(t: TestReport, library: AssetLibrary) -> void:
	t.group("features: the standard eye set is the shipped open eye")
	var eyes := EyeSet.from_library(library)
	t.check(eyes.to_absolute() == library.open_face().ink_cells(),
		"it draws exactly the shipped eye's painted cells")
	for shape in library.head_shapes():
		t.check(eyes.missing_on_head(library.head(shape)).is_empty(),
			"it fits the %s head" % shape)

	t.group("features: editing an eye set")
	var edited := eyes.duplicate_as("test", "Test")
	t.check(edited.is_symmetric(), "the eye starts symmetric")
	edited.set_cell(EyeSet.EYE_LEFT, 0, 2, EyeSet.ROLE_LINE, true)
	t.check(edited.is_symmetric(), "painting both eyes keeps it symmetric")
	t.check_equal(edited.role_at(EyeSet.EYE_RIGHT, 0, 2), EyeSet.ROLE_LINE,
		"and the other eye has the cell")
	edited.set_cell(EyeSet.EYE_LEFT, 0, 2, EyeSet.ROLE_SKIN, false)
	t.check(not edited.is_symmetric(), "painting one eye alone breaks symmetry")
	t.check_equal(edited.role_at(EyeSet.EYE_LEFT, 0, 2), EyeSet.ROLE_SKIN,
		"and skin clears the cell")

	# Files from before the expressions were retired load their neutral drawing.
	var legacy := {"name": "Old", "colourways": {}, "expressions": {
		"neutral": {"left": [[2, 2, "pupil"]], "right": [[2, 2, "pupil"]]},
		"happy": {"left": [[0, 0, "line"]], "right": [[0, 0, "line"]]}}}
	var old := EyeSet.from_json("old", legacy)
	t.check(old.role_at(EyeSet.EYE_LEFT, 2, 2) == EyeSet.ROLE_PUPIL
		and old.role_at(EyeSet.EYE_LEFT, 0, 0) == EyeSet.ROLE_SKIN,
		"an older file's neutral drawing becomes the eye; its other expressions are dropped")

	var json := edited.to_json()
	var again := EyeSet.from_json("test", json)
	t.check(JSON.stringify(again.to_json(), "", true) == JSON.stringify(json, "", true),
		"an eye set round-trips")

	t.group("features: an eye set draws through the assembler")
	var w := Wardrobe.create_default(library)
	t.check(w.eye_set("standard") != null, "the default wardrobe has the standard set")
	var with_set := _figure(library, w, "male_average", "oval", "standard", [])
	var without := _figure(library, w, "male_average", "oval", "", [])
	var a := _face_cells(with_set)
	var b := _face_cells(without)
	t.check(a.keys().size() == b.keys().size() and not a.is_empty(),
		"the same cells are painted with the eye set as without it",
		"%d vs %d" % [a.size(), b.size()])
	# A colourway changes the pupil.
	var eyes2: EyeSet = w.eye_set("standard")
	eyes2.add_colourway("blue")
	eyes2.set_palette_key("blue", EyeSet.ROLE_PUPIL, "eye_blue")
	var blue := _figure(library, w, "male_average", "oval", "standard", [], "blue")
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
			var assembled := _figure(library, w, id, shape, "", [])
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
	t.group("features: facial hair follows every head")
	var w := Wardrobe.create_default(library)
	var crop := {"item": "short_crop", "colourway": "default"}
	for shape in library.head_shapes():
		var bare := _figure(library, w, "male_average", shape, "standard", [])
		var bare_head := bare.part(BodyDef.HEAD_PART)
		var bare_face := _face_cells(bare).size()
		var per_style := {}
		for style in FacialHairGenerator.STYLES:
			var req := CharacterAssembler.Request.make(library, "male_average", shape)
			req.wardrobe = w
			req.eye_set_id = "standard"
			req.features = [crop, {"item": style, "colourway": "default"}]
			var a := CharacterAssembler.assemble(req)
			var head := a.part(BodyDef.HEAD_PART)
			t.check(a.warnings.is_empty(), "%s generates on the %s head" % [style, shape],
				", ".join(a.warnings))
			var mine := {}
			var added := 0
			var touching := true
			for cell in head.cells.keys():
				if String(head.owners.get(cell, "")) != style:
					continue
				mine[cell] = true
				if not bare_head.cells.has(cell):
					added += 1
					var near := false
					for offset in VoxelAxes.NEIGHBOURS:
						if bare_head.cells.has((cell as Vector3i) + offset):
							near = true
					touching = touching and near
			per_style[style] = [mine.size(), added]
			t.check(VoxelTopology.is_mirror_symmetric(mine), "%s is symmetric on %s" % [style, shape])
			t.check(touching, "no %s voxel floats free of the %s head" % [style, shape])
			t.check_equal(_face_cells(a).size(), bare_face, "%s leaves the eyes alone on %s" % [style, shape])
			if style == "stubble":
				t.check(added == 0 and not mine.is_empty(), "stubble only recolours (%s)" % shape,
					"%d cells, %d added" % [mine.size(), added])
			if style == "chinstrap":
				t.check(added > 0, "the chinstrap stands out from the %s face" % shape)
		var full: Array = per_style["full_beard"]
		var stub: Array = per_style["stubble"]
		var strap: Array = per_style["chinstrap"]
		t.check_equal(int(full[1]), int(strap[1]), "a full beard's added voxels are the chinstrap's (%s)" % shape)
		t.check_equal(int(full[0]), int(stub[0]) + int(strap[1]),
			"and the rest is the stubble (%s)" % shape)

	t.group("features: facial hair colours follow the character")
	var req2 := CharacterAssembler.Request.make(library, "male_average", "round")
	req2.wardrobe = w
	req2.features = [{"item": "ponytail", "colourway": "default"}, {"item": "full_beard", "colourway": "default"}]
	for tone in ["light", "deep"]:
		req2.skin_tone = tone
		var a2 := CharacterAssembler.assemble(req2)
		var head2 := a2.part(BodyDef.HEAD_PART)
		var hair_mid := CharacterAssembler.hair_tones(req2)[1]
		var stubble_mid := Palette.stubble_colour(tone, hair_mid)
		t.check(stubble_mid.get_luminance() <= Palette.lid_colour(tone).get_luminance() + 0.0001,
			"%s skin: stubble is darker than the skin" % tone)
		var strap_ok := true
		for cell in head2.cells.keys():
			if String(head2.owners.get(cell, "")) != "full_beard":
				continue
			var colour: Color = head2.colours[cell]
			var in_hair := false
			for c in CharacterAssembler.hair_tones(req2):
				in_hair = in_hair or colour.is_equal_approx(c)
			var in_stubble := false
			for c2 in Palette.skin_like_tones(stubble_mid):
				in_stubble = in_stubble or colour.is_equal_approx(c2)
			if not (in_hair or in_stubble):
				strap_ok = false
		t.check(strap_ok, "%s skin: every full-beard cell is the hair's or the stubble's colour" % tone)
	# Fair hair on deep skin: the case that made "always darker" the rule.
	t.check(Palette.stubble_colour("deep", w.colour("hair_fair")).get_luminance()
		<= Palette.lid_colour("deep").get_luminance() + 0.0001,
		"fair hair on deep skin still gives darker stubble")

	t.group("features: the long beard hangs under the chin")
	for shape2 in library.head_shapes():
		var req3 := CharacterAssembler.Request.make(library, "male_average", shape2)
		req3.wardrobe = w
		req3.features = [{"item": "long_beard", "colourway": "default"}]
		var a3 := CharacterAssembler.assemble(req3)
		t.check(a3.warnings.is_empty(), "it generates on the %s head" % shape2, ", ".join(a3.warnings))
		var head3 := a3.part(BodyDef.HEAD_PART)
		var beard := {}
		var below := 0
		for cell in head3.cells.keys():
			if String(head3.owners.get(cell, "")) == "long_beard":
				beard[cell] = true
				if (cell as Vector3i).z < BodyLayout.HEAD_BOTTOM:
					below += 1
		t.check(below == beard.size() and below > 0, "every voxel of it is below the %s chin" % shape2,
			"%d of %d" % [below, beard.size()])
		t.check(VoxelTopology.is_mirror_symmetric(beard), "and it is symmetric (%s)" % shape2)

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
		var fig := _figure(library, w, "female_heavy", "round", "", worn)
		var chest := fig.part("chest")
		var n := 0
		for cell4 in chest.cells.keys():
			if String(chest.owners.get(cell4, "")) == "test_shape":
				n += 1
		t.check_equal(n, 2, "%s: two drawn cells, two voxels" % ("wrapped" if wrap else "rigid"))

	# Depth -1 recolours the surface instead of adding to it.
	item.set_special_param(at, "wrap", true)
	item.set_special_param(at, "cells", [[0, -1, 0, "cloth"], [1, -1, 0, "cloth"]])
	var bare := _figure(library, w, "male_slim", "round", "", [])
	var painted := _figure(library, w, "male_slim", "round", "", worn)
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
	var skirt := w.item("skirt")
	t.check(skirt.has_coverage() and skirt.is_special(),
		"the skirt has hips of regions and a skirt shape")
	for id in library.body_ids():
		var fig := _figure(library, w, id, "round", "",
			[{"item": "skirt", "colourway": "default"}])
		t.check(fig.warnings.is_empty(), "%s: the skirt generates" % id,
			", ".join(fig.warnings))
		var hips := _owned(fig.part("pelvis"), "skirt").size()
		var panels := 0
		for name in fig.order:
			if fig.part(String(name)).is_panel():
				panels += 1
		t.check(hips > 0 and panels > 0, "%s: both the hips and the panels" % id,
			"hips %d, panels %d" % [hips, panels])

	t.group("features: two skirts are two sets of panels")
	var extra := GarmentItem.create("over_skirt", "Over skirt", "bottom")
	extra.roles = ["cloth", "hem"]
	extra.colourways = {"default": {"cloth": "moss", "hem": "ochre"}}
	extra.add_special("skirt")
	w.add_item(extra)
	var both := _figure(library, w, "female_average", "round", "", [
		{"item": "skirt", "colourway": "default"},
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
		var fig2 := _figure(library, w, id2, "round", "",
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
		eye_set: String, worn: Array,
		eye_colourway: String = "") -> CharacterAssembler.Assembled:
	var request := CharacterAssembler.Request.make(library, body, head)
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
	# Thick trousers under a skirt: the starter trousers are skin-tight now, so
	# the case the panels must clear needs legwear with bulk.
	var thick := GarmentItem.create("thick_trousers", "Thick trousers", "bottom")
	thick.roles = ["cloth"]
	thick.colourways = {"default": {"cloth": "slate"}}
	for key in ["hips.L.F", "hips.L.B", "upper_thigh.L", "lower_thigh.L", "knee.L", "shin.L"]:
		thick.set_region(key, "cloth", 1)
	w.add_item(thick)
	looks.append(["skirt over thick trousers", [{"item": "thick_trousers", "colourway": "default"},
		{"item": "skirt", "colourway": "default"}]])
	# A skirt is a "bottom" and boots are "feet", which draw after it. The
	# panels are placed after everything worn, so a skirt long enough to reach
	# the boots still hangs clear of them (it shared 34 voxels before).
	for long_skirt in ["wrap_skirt", "robe_skirt"]:
		looks.append(["%s and boots" % long_skirt, [{"item": "boots", "colourway": "default"},
			{"item": long_skirt, "colourway": "default"}]])
		looks.append(["%s, thick trousers and boots" % long_skirt, [
			{"item": "boots", "colourway": "default"},
			{"item": "thick_trousers", "colourway": "default"},
			{"item": long_skirt, "colourway": "default"}]])
	looks.append(["skirt under a cloak", [{"item": "cloak", "colourway": "default"},
		{"item": "skirt", "colourway": "default"}]])
	for look in looks:
		var shared := 0
		var example := ""
		for body in library.body_ids():
			var a := _figure(library, w, body, "round", "", look[1])
			# Panels against everything else. (Garments on two body parts can
			# still meet in one cell where an arm hangs against the torso; the
			# legs no longer do, by bulk rule 8.)
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


# ----------------------------------------------------------------- skirts ----

## The panels of one item's skirt, by the generator's own names.
static func _skirt_panels(a: CharacterAssembler.Assembled, item_id: String) -> Dictionary:
	var out := {}
	for generator_name in [SkirtGenerator.PANEL_FRONT, SkirtGenerator.PANEL_BACK,
			SkirtGenerator.PANEL_LEFT, SkirtGenerator.PANEL_RIGHT,
			SkirtGenerator.PANEL_FRONT_LEFT, SkirtGenerator.PANEL_FRONT_RIGHT]:
		var part := a.part(CharacterAssembler.panel_name(item_id, 0, generator_name))
		if part != null:
			out[generator_name] = part
	return out


## A test skirt with the hips in cloth, like the starter ones.
static func _test_skirt(w: Wardrobe, id: String, settings: Dictionary) -> void:
	var item := GarmentItem.create(id, id, "bottom")
	item.roles = ["cloth", "hem"]
	item.colourways = {"default": {"cloth": "plum", "hem": "ochre"}}
	item.set_region("hips.L.F", "cloth", 1)
	item.set_region("hips.L.B", "cloth", 1)
	var at := item.add_special("skirt")
	for key in settings.keys():
		item.set_special_param(at, String(key), settings[key])
	w.add_item(item)


## Lowest row of a panel in each column: x -> z.
static func _hemline(part: CharacterAssembler.Part) -> Dictionary:
	var out := {}
	for cell in part.cells.keys():
		var c: Vector3i = cell
		out[c.x] = mini(int(out.get(c.x, 999)), c.z)
	return out


## Skin showing on one part in one row, seen from the front and from the back.
static func _skin_showing(a: CharacterAssembler.Assembled, part_name: String, z: int) -> int:
	var count := 0
	for from_front in [true, false]:
		var nearest := {}   # x -> [y, part name, cell]
		for name in a.order:
			for cell in a.part(String(name)).cells.keys():
				var c: Vector3i = cell
				if c.z != z:
					continue
				var better: bool = not nearest.has(c.x) \
					or (c.y < int(nearest[c.x][0]) if from_front else c.y > int(nearest[c.x][0]))
				if better:
					nearest[c.x] = [c.y, String(name), c]
		for x in nearest.keys():
			if String(nearest[x][1]) != part_name:
				continue
			var part := a.part(part_name)
			if int(part.sources.get(nearest[x][2], 0)) == CharacterAssembler.Source.SKIN:
				count += 1
	return count


static func _skirts(t: TestReport, library: AssetLibrary) -> void:
	var w := Wardrobe.create_default(library)
	var e := func(item: String, colourway: String = "default") -> Dictionary:
		return {"item": item, "colourway": colourway}

	t.group("skirts: a dress is an outfit, not an item")
	t.check(w.item("dress") == null, "there is no one-piece dress item")
	for outfit in ["dress", "toga", "robe"]:
		t.check(outfit in w.outfit_names(), "the '%s' outfit exists" % outfit)
	for id in ["skirt", "wrap_skirt", "robe_skirt"]:
		var item := w.item(id)
		t.check(item != null and item.category == "bottom" and item.is_special()
			and item.has_coverage(), "%s is a skirt-only item: hips and a skirt shape" % id)

	# The owner's requirement: a matching top and skirt look like one garment.
	# Build the one-piece dress they replace and compare voxel for voxel.
	var one := GarmentItem.create("one_piece", "One-piece dress", "top")
	one.roles = ["cloth", "trim", "hem"]
	one.colourways = {"default": {"cloth": "plum", "trim": "bone", "hem": "ochre"}}
	for key in ["upper_chest.L.F", "upper_chest.L.B", "lower_chest.L.F", "lower_chest.L.B",
			"belly.L.F", "belly.L.B", "hips.L.F", "hips.L.B", "shoulder.L"]:
		one.set_region(key, "cloth", 1)
	for key in ["collar.L.F", "collar.L.B", "waist.L.F", "waist.L.B"]:
		one.set_region(key, "trim", 1)
	one.set_special_param(one.add_special("skirt"), "length", "to_shin")
	w.add_item(one)
	var differing := 0
	var where := ""
	for body in library.body_ids():
		var whole := _figure(library, w, body, "round", "", [e.call("boots"), e.call("one_piece")])
		var split := _figure(library, w, body, "round", "", w.outfit("dress"))
		t.check(split.warnings.is_empty(), "%s: the dress outfit assembles" % body,
			", ".join(split.warnings))
		var whole_panels := _skirt_panels(whole, "one_piece")
		var split_panels := _skirt_panels(split, "skirt")
		for name in whole.body.part_names():
			if not VoxelTopology.same_cells(whole.part(name).cells, split.part(name).cells):
				differing += 1
				where = "%s %s" % [body, name]
		for name in whole_panels.keys():
			if not split_panels.has(name) or not VoxelTopology.same_cells(
					(whole_panels[name] as CharacterAssembler.Part).cells,
					(split_panels[name] as CharacterAssembler.Part).cells):
				differing += 1
				where = "%s %s" % [body, name]
	t.check(differing == 0,
		"bodice + skirt is voxel for voxel the one-piece dress, on all six bodies",
		"%d parts differ, e.g. %s" % [differing, where])

	t.group("skirts: no skin at the waist under a top that stops short")
	_test_skirt(w, "no_band", {"length": "to_shin", "waistband": false})
	var showing := 0
	var showing_without := 0
	var waist := BodyLayout.z0("waist")
	for body in library.body_ids():
		showing += _skin_showing(_figure(library, w, body, "round", "",
			[e.call("shirt"), e.call("skirt")]), "pelvis", waist)
		showing_without += _skin_showing(_figure(library, w, body, "round", "",
			[e.call("shirt"), e.call("no_band")]), "pelvis", waist)
	t.check_equal(showing, 0, "shirt + skirt: the waistband closes the gap on every body")
	t.check(showing_without > 0, "and it is the waistband doing it: without one, skin shows",
		"%d voxels" % showing_without)

	t.group("skirts: panels are shaded by the way they face")
	var faces := {
		SkirtGenerator.PANEL_FRONT: Shading.Tone.MID,
		SkirtGenerator.PANEL_BACK: Shading.Tone.DARK,
		SkirtGenerator.PANEL_LEFT: Shading.Tone.DARK,     # the character's left faces viewer-right
		SkirtGenerator.PANEL_RIGHT: Shading.Tone.MID,
		SkirtGenerator.PANEL_FRONT_LEFT: Shading.Tone.MID,
		SkirtGenerator.PANEL_FRONT_RIGHT: Shading.Tone.MID,
	}
	t.check_equal(Shading.face_tone(VoxelAxes.UP), Shading.Tone.LIGHT, "a top face is light")
	t.check_equal(Shading.face_tone(VoxelAxes.FRONT), Shading.Tone.MID, "a front face is mid")
	t.check_equal(Shading.face_tone(VoxelAxes.BACK), Shading.Tone.DARK, "a back face is dark")
	t.check_equal(Shading.face_tone(VoxelAxes.VIEWER_LEFT), Shading.Tone.MID,
		"a face toward the viewer's left is mid")
	t.check_equal(Shading.face_tone(VoxelAxes.VIEWER_RIGHT), Shading.Tone.DARK,
		"a face toward the viewer's right is dark")
	var off_tone := 0
	var cloth_shades := {}
	for body in library.body_ids():
		for look in [w.outfit("dress"), w.outfit("robe"), w.outfit("toga"),
				[e.call("trousers"), e.call("skirt")]]:
			var a := _figure(library, w, body, "round", "", look)
			for item_id in ["skirt", "robe_skirt", "wrap_skirt"]:
				var panels := _skirt_panels(a, item_id)
				for name in panels.keys():
					var part: CharacterAssembler.Part = panels[name]
					for cell in part.cells.keys():
						if int(part.tones[cell]) != int(faces[name]):
							off_tone += 1
						if item_id == "skirt" and name == SkirtGenerator.PANEL_BACK \
								and (cell as Vector3i).z > BodyLayout.z0("shin"):
							cloth_shades[part.colours[cell]] = true
	t.check_equal(off_tone, 0, "every panel voxel has its panel's shade, on every body")
	t.check_equal(cloth_shades.size(), 1,
		"so the back of a skirt is one flat colour: the legs do not print through")
	var cape_off := 0
	for body in library.body_ids():
		var caped := _figure(library, w, body, "round", "", w.outfit("travelling"))
		for name in caped.order:
			var part := caped.part(String(name))
			if part.is_panel():
				for cell in part.cells.keys():
					if int(part.tones[cell]) != Shading.Tone.DARK:
						cape_off += 1
	t.check_equal(cape_off, 0, "a cape hangs behind the back: dark all over")

	t.group("skirts: a slanted hem")
	_test_skirt(w, "level", {"length": "to_ankle"})
	_test_skirt(w, "slant_left", {"length": "to_ankle", "slant": 4, "side": "left"})
	_test_skirt(w, "slant_right", {"length": "to_ankle", "slant": 4, "side": "right"})
	_test_skirt(w, "slant_short", {"length": "to_knee", "slant": SkirtGenerator.MAX_SLANT})
	for body in library.body_ids():
		var level := _skirt_panels(_figure(library, w, body, "round", "", [e.call("level")]), "level")
		var left_fig := _figure(library, w, body, "round", "", [e.call("slant_left")])
		var left := _skirt_panels(left_fig, "slant_left")
		var right := _skirt_panels(
			_figure(library, w, body, "round", "", [e.call("slant_right")]), "slant_right")
		var front: CharacterAssembler.Part = left[SkirtGenerator.PANEL_FRONT]
		var line := _hemline(front)
		var xs := line.keys()
		xs.sort()
		var hem_z := int(_hemline(level[SkirtGenerator.PANEL_FRONT]).values().min())
		t.check_equal(int(line[xs[0]]), hem_z, "%s: the low side stays at the level hem" % body)
		t.check_equal(int(line[xs[-1]]), hem_z + 4, "%s: the high side is 4 rows up" % body)
		var steps_ok := true
		for i in range(1, xs.size()):
			var step := int(line[xs[i]]) - int(line[xs[i - 1]])
			if step < 0 or step > 1:
				steps_ok = false
		t.check(steps_ok, "%s: the hem climbs toward the high side one row at a time" % body)
		# The hem trim follows the slant: the lowest voxel of every column is
		# the hem colour, and the one above it is not.
		var trimmed := true
		for x in xs:
			var low := Vector3i(int(x), 0, int(line[x]))
			for cell in front.cells.keys():
				if (cell as Vector3i).x == low.x and (cell as Vector3i).z == low.z:
					low = cell
			var above := low + VoxelAxes.UP
			if front.cells.has(above) and front.colours[above] == front.colours[low]:
				trimmed = false
		t.check(trimmed, "%s: the hem trim follows the slant" % body)
		var mirrored := true
		for name in left.keys():
			if not right.has(name):
				mirrored = false
		t.check(mirrored and VoxelTopology.same_cells(
				VoxelTopology.mirrored(front.cells),
				(right[SkirtGenerator.PANEL_FRONT] as CharacterAssembler.Part).cells),
			"%s: the other side is the mirror image" % body)
		# The high side's own panel is the short one.
		var high_side: CharacterAssembler.Part = left[SkirtGenerator.PANEL_LEFT]
		var low_side: CharacterAssembler.Part = left[SkirtGenerator.PANEL_RIGHT]
		t.check(high_side.count() < low_side.count(),
			"%s: the side panel on the high side is the shorter one" % body,
			"%d vs %d" % [high_side.count(), low_side.count()])
		for name in left.keys():
			t.check(VoxelTopology.is_one_piece((left[name] as CharacterAssembler.Part).cells),
				"%s: %s is one piece" % [body, name])
		var short := _skirt_panels(
			_figure(library, w, body, "round", "", [e.call("slant_short")]), "slant_short")
		var short_line := _hemline(short[SkirtGenerator.PANEL_FRONT])
		var top_row := BodyLayout.z0("hips") - 1
		t.check(top_row - int(short_line.values().max()) + 1 >= SkirtGenerator.MIN_ROWS,
			"%s: however steep, the high side keeps %d rows of cloth" % [body, SkirtGenerator.MIN_ROWS])

	t.group("skirts: a wrap opening shows one leg")
	_test_skirt(w, "wrap_left", {"length": "to_ankle", "opening": "wrap", "side": "left"})
	_test_skirt(w, "wrap_right", {"length": "to_ankle", "opening": "wrap", "side": "right"})
	for body in library.body_ids():
		var level := _skirt_panels(_figure(library, w, body, "round", "", [e.call("level")]), "level")
		var fig := _figure(library, w, body, "round", "", [e.call("wrap_left")])
		var wrap := _skirt_panels(fig, "wrap_left")
		var front: CharacterAssembler.Part = wrap[SkirtGenerator.PANEL_FRONT]
		var whole: CharacterAssembler.Part = level[SkirtGenerator.PANEL_FRONT]
		var hem_z := int(_hemline(whole).values().min())
		var top_row := BodyLayout.z0("hips") - 1
		t.check_equal(VoxelTopology.count_in_row(front.cells, top_row),
			VoxelTopology.count_in_row(whole.cells, top_row),
			"%s: the top row is whole, so the skirt still closes at the hip" % body)
		# At the hem the open side is bare from just past the middle outward.
		var past_middle := 0
		for cell in front.cells.keys():
			var c: Vector3i = cell
			if c.z == hem_z and c.x > VoxelAxes.MIRROR_X_MAX / 2 + 1:
				past_middle += 1
		t.check_equal(past_middle, 0, "%s: at the hem nothing covers the open leg" % body)
		# ...and the leg is what shows there: seen from the front, the nearest
		# voxel in the open leg's columns belongs to the leg, not to a panel.
		var leg_x := VoxelTopology.row_extent_x(fig.part("shin_L").cells, hem_z + 1)
		var leg_seen := 0
		for x in range(leg_x.x, leg_x.y + 1):
			var nearest := 999
			var owner := ""
			for name in fig.order:
				for cell in fig.part(String(name)).cells.keys():
					var c: Vector3i = cell
					if c.x == x and c.z == hem_z + 1 and c.y < nearest:
						nearest = c.y
						owner = String(name)
			if owner == "shin_L":
				leg_seen += 1
		t.check(leg_seen >= leg_x.y - leg_x.x, "%s: the open leg shows from the front" % body,
			"%d of %d columns" % [leg_seen, leg_x.y - leg_x.x + 1])
		t.check(VoxelTopology.is_one_piece(front.cells), "%s: the wrapped front is one piece" % body)
		t.check(VoxelTopology.same_cells(
				(wrap[SkirtGenerator.PANEL_BACK] as CharacterAssembler.Part).cells,
				(level[SkirtGenerator.PANEL_BACK] as CharacterAssembler.Part).cells),
			"%s: only the front opens; the back is untouched" % body)
		var other := _skirt_panels(
			_figure(library, w, body, "round", "", [e.call("wrap_right")]), "wrap_right")
		t.check(VoxelTopology.same_cells(VoxelTopology.mirrored(front.cells),
				(other[SkirtGenerator.PANEL_FRONT] as CharacterAssembler.Part).cells),
			"%s: the other side is the mirror image" % body)

	t.group("skirts: an open front is two flaps")
	_test_skirt(w, "open_front", {"length": "to_ankle", "opening": "front"})
	for body in library.body_ids():
		var fig := _figure(library, w, body, "round", "", [e.call("open_front")])
		var open := _skirt_panels(fig, "open_front")
		t.check(open.has(SkirtGenerator.PANEL_FRONT_LEFT) and open.has(SkirtGenerator.PANEL_FRONT_RIGHT)
			and not open.has(SkirtGenerator.PANEL_FRONT),
			"%s: the front is a left flap and a right flap" % body)
		if not open.has(SkirtGenerator.PANEL_FRONT_LEFT):
			continue
		var flap_l: CharacterAssembler.Part = open[SkirtGenerator.PANEL_FRONT_LEFT]
		var flap_r: CharacterAssembler.Part = open[SkirtGenerator.PANEL_FRONT_RIGHT]
		var in_gap := 0
		var wrong_side := 0
		for cell in flap_l.cells.keys():
			var c: Vector3i = cell
			if c.x <= VoxelAxes.MIRROR_X_MAX / 2 + 1:
				in_gap += 1
			if not VoxelAxes.is_left(c):
				wrong_side += 1
		t.check_equal(in_gap, 0, "%s: the two middle columns stay open top to bottom" % body)
		t.check_equal(wrong_side, 0, "%s: each flap keeps to its own side" % body)
		t.check(VoxelTopology.same_cells(VoxelTopology.mirrored(flap_l.cells), flap_r.cells),
			"%s: the flaps mirror each other" % body)
		t.check(VoxelTopology.is_one_piece(flap_l.cells), "%s: a flap is one piece" % body)
		t.check_equal(flap_l.driver, SpecialItem.DRIVER_FLAP_L, "%s: the left flap follows the left leg" % body)
		t.check_equal(flap_r.driver, SpecialItem.DRIVER_FLAP_R, "%s: the right flap follows the right leg" % body)
	var stride := Poses.get_pose(Poses.MID_STRIDE)
	var thigh_l: Vector3 = stride.get("thigh_L", Vector3.ZERO)
	var thigh_r: Vector3 = stride.get("thigh_R", Vector3.ZERO)
	var forward := SpecialItem.DRIVER_FLAP_L if thigh_l.x > thigh_r.x else SpecialItem.DRIVER_FLAP_R
	var behind := SpecialItem.DRIVER_FLAP_R if thigh_l.x > thigh_r.x else SpecialItem.DRIVER_FLAP_L
	t.check(Poses.panel_rotation(forward, stride).x > 0.0,
		"mid-stride, the forward leg's flap swings forward with it")
	t.check(is_zero_approx(Poses.panel_rotation(behind, stride).x),
		"and the other flap just hangs: it never follows a leg backward")

	t.group("skirts: the toga's top leaves one shoulder bare")
	var toga := _figure(library, w, "male_average", "strong", "", w.outfit("toga"))
	var top_owned := _owned(toga.part("chest"), "one_shoulder_top")
	var upper := BodyLayout.z1("upper_chest")
	var left_top := 0
	var right_top := 0
	for cell in top_owned.keys():
		var c: Vector3i = cell
		if c.z == upper:
			if VoxelAxes.is_left(c):
				left_top += 1
			else:
				right_top += 1
	t.check(left_top > 0 and right_top == 0,
		"the top row of the chest is covered on the left only",
		"left %d, right %d" % [left_top, right_top])
	t.check(toga.warnings.is_empty(), "the toga assembles without warnings", ", ".join(toga.warnings))


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
	var open := eyes.eye_cells(EyeSet.EYE_LEFT)
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

	t.group("eyes: lid tilt for angry and sad")
	var brow_row_at := func(cells: Dictionary, col: int) -> int:
		for cell in cells.keys():
			if (cell as Vector2i).x == col and String(cells[cell]) == EyeLids.ROLE_BROW:
				return (cell as Vector2i).y
		return -1
	var inner := EyeSet.BOX_W - 1   # c counts from the outer edge
	var angry := EyeLids.apply(open, EyeLids.eye_state("angry", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	t.check(brow_row_at.call(angry, inner) < brow_row_at.call(angry, 0),
		"angry: the brow slants down toward the nose",
		"outer row %d, inner row %d" % [brow_row_at.call(angry, 0), brow_row_at.call(angry, inner)])
	t.check(angry.get(Vector2i(inner, h - 2)) == EyeLids.ROLE_LID, "with lid above its inner end")
	var sad := EyeLids.apply(open, EyeLids.eye_state("sad", EyeSet.EYE_LEFT), EyeSet.EYE_LEFT)
	t.check(brow_row_at.call(sad, inner) > brow_row_at.call(sad, 0),
		"sad: the brow slants up toward the nose",
		"outer row %d, inner row %d" % [brow_row_at.call(sad, 0), brow_row_at.call(sad, inner)])
	t.check_equal(brow_row_at.call(sad, inner), h, "its inner end raised above the eye")
	var steps: Array[int] = []
	for col in EyeSet.BOX_W:
		steps.append(EyeLids.tilt_offset(col, 2))
	t.check_equal(steps, [0, 1, 1, 2, 2] as Array[int], "a tilt of 2 steps evenly across the eye")
	var a2 := CharacterAssembler.assemble(_tilt_request(library, w, eyes.id, "angry"))
	var mirrored := true
	var face := _face_cells(a2)
	for cell in face.keys():
		var c3: Vector3i = cell
		if not face.has(Vector3i(VoxelAxes.MIRROR_X_MAX - c3.x, c3.y, c3.z)):
			mirrored = false
	t.check(mirrored, "both eyes slant toward the nose (mirror images)")

	t.group("eyes: lid, brow and skin colours")
	var tail := {"item": "ponytail", "colourway": "default"}
	var req := CharacterAssembler.Request.make(library, "male_average", "round")
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
			var r2 := CharacterAssembler.Request.make(library, "female_slim", shape)
			r2.wardrobe = w
			r2.eye_set_id = eyes.id
			r2.lids = state
			var expected := 0
			for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
				expected += EyeLids.apply(eyes.eye_cells(eye),
					EyeLids.eye_state(state, eye), eye).size()
			if _face_cells(CharacterAssembler.assemble(r2)).size() != expected:
				bad.append(state)
		t.check(bad.is_empty(), "%s head: every lid state lands on the face" % shape, ", ".join(bad))


static func _tilt_request(library: AssetLibrary, w: Wardrobe, eye_set: String,
		state: String) -> CharacterAssembler.Request:
	var r := CharacterAssembler.Request.make(library, "male_average", "round")
	r.wardrobe = w
	r.eye_set_id = eye_set
	r.lids = state
	return r


# ------------------------------------------------------ straps, overalls ----

static func _owned(part: CharacterAssembler.Part, item_id: String) -> Dictionary:
	var out := {}
	for cell in part.cells.keys():
		if String(part.owners.get(cell, "")) == item_id:
			out[cell] = true
	return out


## Suspenders are a pair of shoulder straps placed on each chest; overalls are
## an outfit of trousers, bib and suspenders in one colour (owner's design).
static func _straps(t: TestReport, library: AssetLibrary) -> void:
	t.group("straps: suspenders fit every body")
	var w := Wardrobe.create_default(library)
	var bottom := BodyLayout.z0("belly")
	var columns := {}
	for id in library.body_ids():
		var chest_body: Dictionary = library.body(id).part("chest").cells
		var a := _figure(library, w, id, "round", "", w.outfit("shirt and suspenders"))
		t.check(a.warnings.is_empty(), "%s: they generate" % id, ", ".join(a.warnings))
		var straps := _owned(a.part("chest"), "suspenders")
		var on_body := 0
		var low := 99
		var high := -1
		var at_bottom := 0
		for cell in straps.keys():
			var c: Vector3i = cell
			if chest_body.has(c):
				on_body += 1
			low = mini(low, c.z)
			high = maxi(high, c.z)
			if c.z == bottom:
				at_bottom += 1
		t.check(not straps.is_empty() and on_body == 0, "%s: the straps stand out from the chest" % id)
		t.check(VoxelTopology.is_mirror_symmetric(straps), "%s: they are mirror images" % id)
		t.check_equal(VoxelTopology.components(straps), 2,
			"%s: each strap is one piece -- front, over the top, and back" % id)
		t.check(low == bottom and high == BodyLayout.NECK_ROW,
			"%s: they run from the belly's bottom row to over the shoulder" % id,
			"rows %d to %d" % [low, high])
		t.check_equal(at_bottom, 4, "%s: both straps reach the bottom, front and back" % id)
		var cols := StrapGenerator.strap_columns(chest_body, 1)
		var top_row := int(VoxelTopology.bounds(chest_body).end.z)
		t.check(cols.size() == 1 and cols[0] > BodyLayout.NECK_SOCKET_X.y
			and cols[0] <= VoxelTopology.row_extent_x(chest_body, top_row).y,
			"%s: the strap sits between the neck and the edge of the chest" % id, str(cols))
		columns[id] = cols[0] if not cols.is_empty() else -1
	t.check(int(columns["male_heavy"]) > int(columns["female_slim"]),
		"a wide chest carries its straps wider than a narrow one", str(columns))

	# Two voxels wide, and over a thick top.
	var wide := w.item("suspenders").duplicate_as("wide_suspenders", "Wide suspenders")
	wide.set_special_param(0, "width", 2)
	w.add_item(wide)
	var a2 := _figure(library, w, "male_average", "round", "",
		[{"item": "wide_suspenders", "colourway": "default"}])
	var wide_bottom := 0
	for cell in _owned(a2.part("chest"), "wide_suspenders").keys():
		if (cell as Vector3i).z == bottom:
			wide_bottom += 1
	t.check_equal(wide_bottom, 8, "width 2 doubles each strap")
	var over_tunic := _figure(library, w, "male_average", "round", "",
		w.outfit("everyday") + [{"item": "suspenders", "colourway": "default"}])
	t.check(not _owned(over_tunic.part("chest"), "suspenders").is_empty(),
		"suspenders show over a thick top: same reach, and accessories draw above tops")

	t.group("straps: overalls are an outfit of three pieces in one colour")
	t.check(w.outfit_names().has("overalls") and w.outfit_names().has("shirt and suspenders"),
		"the starter wardrobe has both outfits", ", ".join(w.outfit_names()))
	var denim := Palette.garment_tones(w.colour("denim"))
	for id2 in library.body_ids():
		var o := _figure(library, w, id2, "round", "", w.outfit("overalls"))
		t.check(o.warnings.is_empty(), "%s: the overalls outfit assembles" % id2, ", ".join(o.warnings))
		var seen := {}
		var one_colour := true
		for name in o.order:
			var part := o.part(String(name))
			for cell in part.cells.keys():
				var owner := String(part.owners.get(cell, ""))
				if owner.is_empty():
					continue
				seen[owner] = true
				if owner in ["bib", "suspenders", "trousers"]:
					var colour: Color = part.colours[cell]
					var is_denim := false
					for tone in denim:
						is_denim = is_denim or colour.is_equal_approx(tone)
					one_colour = one_colour and is_denim
		t.check(seen.has("bib") and seen.has("suspenders") and seen.has("trousers") and seen.has("shirt"),
			"%s: trousers, shirt, bib and suspenders all show" % id2, ", ".join(seen.keys()))
		t.check(one_colour, "%s: trousers, bib and suspenders are one colour" % id2)
		# ...and one SHADE where they meet: a thin raised strap would otherwise
		# catch the edge highlight on every voxel and read lighter than the bib.
		var chest_part := o.part("chest")
		var chest_body: Dictionary = library.body(id2).part("chest").cells
		var chest_top := int(VoxelTopology.bounds(chest_body).end.z)
		var wrong := 0
		for cell in _owned(chest_part, "suspenders").keys():
			var c: Vector3i = cell
			var want: Color = denim[0] if c.z > chest_top \
				else (denim[1] if c.y < VoxelAxes.DEPTH_CENTRE else denim[2])
			if not (chest_part.colours[c] as Color).is_equal_approx(want):
				wrong += 1
		t.check_equal(wrong, 0,
			"%s: the straps take the shade of the cloth they lie on (mid in front, dark behind)" % id2)

