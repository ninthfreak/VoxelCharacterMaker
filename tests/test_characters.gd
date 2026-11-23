class_name TestCharacters
extends RefCounted

## Saved characters: the model (CharacterDef, in the wardrobe file) and the game's node (GameCharacter).


static func run(t: TestReport, library: LowpolyLibrary) -> void:
	_model(t, library)
	_file(t)
	_game(t)


static func _model(t: TestReport, library: LowpolyLibrary) -> void:
	t.group("characters: the starter characters")
	var w := Wardrobe.create_default()
	var names: Array[String] = []
	for id in w.character_ids():
		names.append(w.character(id).name)
	t.check_equal(names, ["Elder", "Farmer", "Traveller", "Villager"] as Array[String], "four, listed by name")
	for id in w.character_ids():
		var who := w.character(id)
		var f := LowpolyAssembler.assemble(library, who.make_request(w))
		var by := {}
		for p in f.polygons:
			by[String(p["by"])] = true
		for c in f.cloths:
			by[(c as LowpolyCloth).by] = true
		var wears_all := true
		for entry in who.worn:
			wears_all = wears_all and by.has(String((entry as Dictionary)["item"]))
		for feature in [who.hair_id, who.facial_id, who.accessory_id]:
			wears_all = wears_all and (feature.is_empty() or by.has(feature))
		t.check(f != null and f.warnings.is_empty() and wears_all,
			"%s builds with no warnings, wearing everything it has" % who.name, ", ".join(f.warnings))

	t.group("characters: what a character asks the assembler for")
	var who := CharacterDef.create("test", "Test")
	who.body_id = "female_heavy"
	who.head_shape = "boxy"
	who.skin_tone = "deep"
	who.lids = "angry"
	who.mouth = "frown"
	who.brow_hair = "hair_black"
	who.hair_id = "short_crop"
	who.hair_colourway = "no such colourway"
	who.accessory_id = "long_beard"
	who.worn = [{"item": "tunic", "colourway": "rust"}, {"item": "gone", "colourway": "default"},
		{"item": "boots", "colourway": "missing"}, {"item": "ponytail", "colourway": "default"}]
	var req := who.make_request(w)
	t.check(req.body_id == "female_heavy" and req.head_shape == "boxy" and req.skin_tone == "deep"
		and req.lids == "angry" and req.mouth == "frown", "body, head, skin, eyelids and mouth as saved")
	t.check_equal(req.worn, [{"item": "tunic", "colourway": "rust"}, {"item": "boots", "colourway": "default"}],
		"clothes the wardrobe has, in colourways it has (an item it lacks, or a feature, is left out)")
	t.check_equal(req.features, [{"item": "short_crop", "colourway": "default"}, {"item": "long_beard", "colourway": "default"}],
		"hair and the face accessory, a missing colourway falling back to the first")
	t.check(req.brow_colour.is_equal_approx(Palette.brow_from_hair(w.colour("hair_black"))), "brows like black hair")

	t.group("characters: the wardrobe keeps them whole")
	w.add_character(who)
	w.remove_item("short_crop")
	w.remove_item("tunic")
	t.check(who.hair_id == "" and not who.uses_item("tunic") and who.uses_item("boots"),
		"deleting an item takes it off every character (hair slot and clothes)")
	t.check(w.colour_users("hair_black").has("character Test (brows)"), "a character's brows count as using a colour")
	t.check(w.character("farmer").uses_item("full_beard") and not w.character("traveller").uses_item("tunic"),
		"and only the item: other characters keep theirs")


static func _file(t: TestReport) -> void:
	t.group("characters: in the wardrobe file")
	var w := Wardrobe.create_default()
	var copy := w.character("farmer").duplicate_as("farmer_2", "Farmer, older")
	copy.brow_hair = "hair_auburn"
	w.add_character(copy)
	var data := w.to_json()
	t.check_equal(int(data["version"]), 3, "saved as version 3")
	var back := Wardrobe.from_json(JSON.parse_string(JSON.stringify(data)))
	t.check(back != null and back.to_json() == data, "saved and read back: the same wardrobe, characters and all")
	t.check(back.character("farmer_2").same_as(copy) and back.character("farmer_2").name == "Farmer, older",
		"a character comes back as it was saved")
	var v2 := data.duplicate(true)
	v2["version"] = 2
	v2.erase("characters")
	var old := Wardrobe.from_json(v2)
	t.check(old != null and old.characters.is_empty(), "a version 2 file (before characters) still opens, with none")
	var odd := data.duplicate(true)
	odd["characters"] = {"bad": "not a character", "half": {"body_id": "male_slim", "worn": "not a list"}}
	var tolerant := Wardrobe.from_json(odd)
	t.check(tolerant != null and tolerant.character("bad") == null and tolerant.character("half").name == "half"
		and tolerant.character("half").worn.is_empty() and tolerant.character("half").body_id == "male_slim",
		"a hand-edited file: what is not a character is skipped, what is missing takes its default")


static func _game(t: TestReport) -> void:
	t.group("characters: the game builds one by its id (GameCharacter)")
	var w := Wardrobe.create_default()
	var who := GameCharacter.new()
	var ok := who.setup(w, "farmer")
	t.check(ok and who.figure != null and who.rig.figure == who.figure and who.figure.warnings.is_empty(),
		"the farmer, built and shown")
	var same := LowpolyAssembler.assemble(GameCharacter.library(), w.character("farmer").make_request(w))
	t.check_equal(who.figure.polygons.size(), same.polygons.size(), "the same figure the editor would build")

	var dressed_before: Variant = who._dressed[0]
	who.set_expression("angry", "frown")
	t.check(is_same(who._dressed[0], dressed_before) and who.lids == "angry" and who.mouth == "frown",
		"a new expression faces it again without dressing it again")

	who.set_pose(Poses.MID_STRIDE)
	t.check(who.rig.current_pose() == Poses.get_pose(Poses.MID_STRIDE), "a pose turns its bones")

	t.check(who.wear_outfit("everyday") and not is_same(who._dressed[0], dressed_before), "another outfit dresses it again")
	var wears_tunic := false
	for p in who.figure.polygons:
		wears_tunic = wears_tunic or String(p["by"]) == "tunic"
	t.check(wears_tunic and not w.character("farmer").uses_item("tunic"),
		"it wears the tunic now, and the saved farmer does not: the wardrobe is not changed")
	who.free()

	var missing := GameCharacter.new()
	t.check(not missing.setup(w, "nobody") and missing.figure == null, "an id the wardrobe does not have builds nothing")
	missing.free()
