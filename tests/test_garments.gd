@tool
class_name TestGarments
extends RefCounted

## SPEC.md section 12: "A parametric garment generates without gaps on all six
## bodies; bulk-0 adds no voxels." Plus each of the section 7.3 bulk rules and
## the layering rule, checked one at a time.


static func run(t: TestReport, library: AssetLibrary) -> void:
	var map := library.region_map()
	var wardrobe := Wardrobe.create_default()

	t.group("garments: the region map")
	t.check(map != null, "a region map is available")
	if map == null:
		return
	# Head and torso bands split front/back; limb bands do not.
	for band_name in map.band_names():
		var band := map.band(band_name)
		var key_count := 0
		for key in map.all_keys():
			if String(RegionMap.parse_key(key)["band"]) == band_name:
				key_count += 1
		var want := 4 if RegionMap.splits_front_back(band.family) else 2
		t.check_equal(key_count, want,
			"band %s yields %d region keys" % [band_name, want])
	var seen := {}
	var duplicates := 0
	for key in map.all_keys():
		if seen.has(key):
			duplicates += 1
		seen[key] = true
	t.check_equal(duplicates, 0, "region keys are unique")
	t.note("%d region keys in total, %d per side" % [
		map.all_keys().size(), map.keys_for_side(RegionMap.SIDE_LEFT).size()])

	# Mirroring a key twice returns the original.
	for key2 in map.all_keys():
		t.check(RegionMap.mirror_key(RegionMap.mirror_key(key2)) == key2,
			"mirroring %s twice is a no-op" % key2)

	t.group("garments: bulk 0 adds no voxels")
	for id in library.body_ids():
		var bare := _assemble(library, wardrobe, id, [])
		var recolour := GarmentItem.create("skin_tight", "Skin tight", "top")
		recolour.roles = ["cloth"]
		recolour.colourways = {"default": {"cloth": "teal"}}
		for key3 in map.keys_for_side(RegionMap.SIDE_LEFT):
			recolour.set_region(key3, "cloth", 0)
		wardrobe.add_item(recolour)
		var worn := _assemble(library, wardrobe, id,
			[{"item": "skin_tight", "colourway": "default"}])
		t.check_equal(worn.total_voxels(), bare.total_voxels(),
			"%s: a bulk-0 garment over every region adds nothing" % id)

		# ...and it does recolour: no cell should still read as bare skin on a
		# part the garment covers.
		var recoloured := 0
		for name in worn.order:
			var part := worn.part(String(name))
			for cell in part.cells.keys():
				if String(part.owners.get(cell, "")) == "skin_tight":
					recoloured += 1
		t.check(recoloured > 0, "%s: the bulk-0 garment recolours cells" % id,
			"%d cells" % recoloured)
		wardrobe.remove_item("skin_tight")

	t.group("garments: a parametric garment generates on all six bodies")
	var tunic := wardrobe.item("tunic")
	t.check(tunic != null, "the starter tunic exists")
	for id2 in library.body_ids():
		var bare2 := _assemble(library, wardrobe, id2, [])
		var dressed := _assemble(library, wardrobe, id2,
			[{"item": "tunic", "colourway": "default"}])
		var added := dressed.total_voxels() - bare2.total_voxels()
		t.check(added > 0, "%s: the tunic adds voxels" % id2, "added %d" % added)

		# No gaps: every region the tunic covers must own at least one cell on
		# this body, or the garment has a hole on it.
		var owned_regions := {}
		for name2 in dressed.order:
			var part2 := dressed.part(String(name2))
			for cell2 in part2.cells.keys():
				if String(part2.owners.get(cell2, "")) == "tunic":
					owned_regions[String(part2.regions.get(cell2, ""))] = true
		var uncovered: Array[String] = []
		for key4 in tunic.effective_coverage().keys():
			if not owned_regions.has(key4):
				uncovered.append(String(key4))
		t.check(uncovered.is_empty(), "%s: the tunic covers every region it claims" % id2,
			"missing %s" % ", ".join(uncovered))

		# Mirrored definition on a mirror-symmetric body: symmetric result.
		var garment_cells := {}
		for name3 in dressed.order:
			var part3 := dressed.part(String(name3))
			for cell3 in part3.cells.keys():
				if String(part3.owners.get(cell3, "")) == "tunic":
					garment_cells[cell3] = true
		t.check(TestReport.same_cells(garment_cells, TestReport.mirror_of(garment_cells)),
			"%s: a mirrored garment comes out mirror-symmetric" % id2)

	t.group("garments: the bulk rules")
	var body := library.body("male_average")
	var chest := body.part("chest")
	var region_cells: Array = []
	for cell4 in chest.cells.keys():
		if map.key_for_cell("chest", cell4) == "belly.L.F":
			region_cells.append(cell4)
	t.check(not region_cells.is_empty(), "the belly front-left region has cells")

	# Rule 1: bulk 0 grows nothing.
	t.check_equal(BulkBuilder.grow(chest.cells, region_cells, 0).size(), 0,
		"rule 1: bulk 0 grows nothing")

	# Rule 1 again: growth never replaces the body's own voxels.
	var grown := BulkBuilder.grow(chest.cells, region_cells, 2)
	var inside := 0
	for cell5 in grown.keys():
		if chest.cells.has(cell5):
			inside += 1
	t.check_equal(inside, 0, "rule 1: grown cells are all outside the part")

	# Rule 3: nothing grows below z0.
	var shin := body.part("shin_L")
	var foot_cells: Array = []
	for cell6 in shin.cells.keys():
		if map.key_for_cell("shin_L", cell6) == "foot.L":
			foot_cells.append(cell6)
	var boots := BulkBuilder.grow(shin.cells, foot_cells, 3)
	var below := 0
	for cell7 in boots.keys():
		if (cell7 as Vector3i).z < 0:
			below += 1
	t.check_equal(below, 0, "rule 3: nothing grows below z0")
	t.check(not boots.is_empty(), "rule 3: a boot does grow around the foot")

	# Rule 7: soft rounds corners, so it never produces more than hard.
	var soft := BulkBuilder.grow(chest.cells, region_cells, 1, BulkBuilder.EdgeStyle.SOFT)
	var hard := BulkBuilder.grow(chest.cells, region_cells, 1, BulkBuilder.EdgeStyle.HARD)
	t.check(soft.size() <= hard.size(),
		"rule 7: soft edges never add more cells than hard",
		"soft %d, hard %d" % [soft.size(), hard.size()])
	t.check(soft.size() < hard.size(),
		"rule 7: soft and hard actually differ at bulk 1",
		"soft %d, hard %d" % [soft.size(), hard.size()])

	# Thicker bulk reaches farther.
	var b1 := BulkBuilder.grow(chest.cells, region_cells, 1).size()
	var b2 := BulkBuilder.grow(chest.cells, region_cells, 2).size()
	var b3 := BulkBuilder.grow(chest.cells, region_cells, 3).size()
	t.check(b1 < b2 and b2 < b3, "thicker bulk adds more cells",
		"%d, %d, %d" % [b1, b2, b3])

	# Rule 2: growth with dz == 0 stays in the band's rows. Only the up/down
	# exception may leave them, so a region with no open top or bottom face
	# cannot grow vertically at all.
	var band := map.band("belly")
	var outside_rows := 0
	for cell8 in BulkBuilder.grow(chest.cells, region_cells, 1).keys():
		var c8: Vector3i = cell8
		if c8.z < band.z0 or c8.z > band.z1:
			outside_rows += 1
	t.note(("rule 2 and 3: %d of the belly's grown cells sit outside its rows, "
		+ "which is the up/down-facing exception") % outside_rows)

	# Rule 3, the part that is easy to get wrong: "facing up or down" is a fact
	# about the FIGURE, not about one part. The chest sits straight on the
	# pelvis, so the chest's bottom row is not an exposed surface and a belly
	# garment must not grow down through that seam into the hips.
	var figure: Dictionary = {}
	for name5 in body.part_names():
		for cell13 in body.part(name5).cells.keys():
			figure[cell13] = true
	var chest_floor := 16
	var seam_aware := BulkBuilder.grow(
		chest.cells, region_cells, 2, BulkBuilder.EdgeStyle.SOFT, figure)
	var through_seam := 0
	for cell14 in seam_aware.keys():
		if (cell14 as Vector3i).z < chest_floor:
			through_seam += 1
	t.check_equal(through_seam, 0,
		"a belly garment does not grow down through the chest/pelvis seam")

	var part_only := BulkBuilder.grow(chest.cells, region_cells, 2)
	var part_only_through := 0
	for cell15 in part_only.keys():
		if (cell15 as Vector3i).z < chest_floor:
			part_only_through += 1
	t.check(part_only_through > 0,
		"judging exposure by the part alone is what would let it through",
		"that is why grow() takes the figure's occupancy")

	# And the same thing end to end: a dressed figure must not have the chest
	# and the pelvis both claiming the same cell.
	t.group("garments: joints do not bleed")
	for id4 in library.body_ids():
		var dressed2 := _assemble(library, wardrobe, id4,
			CharacterAssembler.worn_from_outfit(wardrobe, "everyday"))
		var seam_pairs := {
			"chest/pelvis": ["chest", "pelvis"],
			"head/chest": [BodyDef.HEAD_PART, "chest"],
		}
		for label in seam_pairs.keys():
			var pair: Array = seam_pairs[label]
			var first: Dictionary = dressed2.part(String(pair[0])).cells
			var second: Dictionary = dressed2.part(String(pair[1])).cells
			var shared2 := 0
			for cell16 in first.keys():
				if second.has(cell16):
					shared2 += 1
			t.check_equal(shared2, 0, "%s: %s do not share cells" % [id4, label])

	t.group("garments: layering")
	# A thick coat over a thin shirt: the coat owns the shared cells.
	var shirt := GarmentItem.create("shirt", "Shirt", "top")
	shirt.roles = ["cloth"]
	shirt.colourways = {"default": {"cloth": "bone"}}
	shirt.set_region("upper_chest.L.F", "cloth", 1)
	var coat := GarmentItem.create("coat", "Coat", "other")
	coat.roles = ["cloth"]
	coat.colourways = {"default": {"cloth": "ink"}}
	coat.set_region("upper_chest.L.F", "cloth", 3)
	wardrobe.add_item(shirt)
	wardrobe.add_item(coat)

	var layered := _assemble(library, wardrobe, "male_average", [
		{"item": "shirt", "colourway": "default"},
		{"item": "coat", "colourway": "default"},
	])
	var chest_part := layered.part("chest")
	var shared := 0
	var coat_owned := 0
	for cell9 in chest_part.cells.keys():
		var owner := String(chest_part.owners.get(cell9, ""))
		if owner == "coat":
			coat_owned += 1
		if String(chest_part.regions.get(cell9, "")) == "upper_chest.L.F" \
				and not owner.is_empty():
			shared += 1
	t.check(coat_owned > 0, "the coat owns cells")
	t.check(shared > 0, "the shared region has owned cells")
	var shirt_in_region := 0
	for cell10 in chest_part.cells.keys():
		if String(chest_part.owners.get(cell10, "")) == "shirt":
			shirt_in_region += 1
	t.check_equal(shirt_in_region, 0,
		"the item reaching farther from the body wins the whole stack")

	# Equal reach: draw order breaks the tie, and the higher order wins.
	coat.set_region("upper_chest.L.F", "cloth", 1)
	var tied := _assemble(library, wardrobe, "male_average", [
		{"item": "shirt", "colourway": "default"},
		{"item": "coat", "colourway": "default"},
	])
	var tied_chest := tied.part("chest")
	var winner := ""
	for cell11 in tied_chest.cells.keys():
		var owner2 := String(tied_chest.owners.get(cell11, ""))
		if owner2 == "shirt" or owner2 == "coat":
			winner = owner2
			break
	# "other" draws at 45, "top" at 30, so the coat is on top.
	t.check_equal(winner, "coat", "at equal reach the higher draw order wins")

	t.group("garments: special items")
	var skirt := GarmentItem.create("skirt", "Skirt", "bottom")
	skirt.kind = GarmentItem.Kind.SPECIAL
	skirt.special_type = "skirt"
	skirt.special_params = SpecialItem.default_params("skirt")
	skirt.roles = ["cloth", "hem"]
	skirt.colourways = {"default": {"cloth": "moss", "hem": "ochre"}}
	wardrobe.add_item(skirt)

	for id3 in library.body_ids():
		var with_skirt := _assemble(library, wardrobe, id3,
			[{"item": "skirt", "colourway": "default"}])
		t.check(with_skirt.warnings.is_empty(),
			"%s: the skirt generates without warnings" % id3,
			", ".join(with_skirt.warnings))
		var panel_count := 0
		var panel_cells := 0
		for name4 in with_skirt.order:
			var part4 := with_skirt.part(String(name4))
			if part4.is_panel():
				panel_count += 1
				panel_cells += part4.count()
		t.check_equal(panel_count, 4, "%s: four cloth panels" % id3)
		t.check(panel_cells > 0, "%s: the panels have geometry" % id3,
			"%d cells" % panel_cells)

	var hood := GarmentItem.create("hood", "Hood", "hat")
	hood.kind = GarmentItem.Kind.SPECIAL
	hood.special_type = "hood"
	hood.special_params = SpecialItem.default_params("hood")
	hood.roles = ["cloth", "lining"]
	hood.colourways = {"default": {"cloth": "ink", "lining": "rust"}}
	wardrobe.add_item(hood)

	for shape in library.head_shapes():
		var request := CharacterAssembler.Request.make(
			library, "male_average", shape, "neutral")
		request.wardrobe = wardrobe
		request.worn = [{"item": "hood", "colourway": "default"}]
		var hooded := CharacterAssembler.assemble(request)
		t.check(hooded.warnings.is_empty(),
			"the hood generates on the %s head" % shape, ", ".join(hooded.warnings))

		# The eyes must still be visible: no hood cell may sit in front of an
		# eye cell on the face plane.
		var head_part := hooded.part(BodyDef.HEAD_PART)
		var blocked := 0
		for cell12 in head_part.cells.keys():
			var c12: Vector3i = cell12
			if c12.y >= VoxelAxes.FACE_PLANE_Y:
				continue
			if String(head_part.owners.get(c12, "")) != "hood":
				continue
			if c12.x >= 7 and c12.x <= 16 and c12.z >= 30 and c12.z <= 34:
				blocked += 1
		t.check_equal(blocked, 0, "the hood leaves the eyes clear on the %s head" % shape)


static func _assemble(library: AssetLibrary, wardrobe: Wardrobe, body_id: String,
		worn: Array) -> CharacterAssembler.Assembled:
	var request := CharacterAssembler.Request.make(library, body_id, "round", "neutral")
	request.wardrobe = wardrobe
	request.worn = worn
	return CharacterAssembler.assemble(request)
