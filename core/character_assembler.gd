@tool
class_name CharacterAssembler
extends RefCounted

## Body + head + face + worn items -> per-part voxels and colours.
##
## This module exists EXACTLY ONCE and both the game and the editor call it
## (SPEC.md section 8). That is the main reason the editor is built in-engine:
## two implementations of bulk generation would drift.
##
## Order of work:
##   1. base occupancy per part, head geometry from the head library
##   2. the face as a claim with reach 0 and a draw order below every garment,
##      which is what "the face draws under hair and hats" means (SPEC 5)
##   3. each worn item, in draw order, produces claims -- parametric items
##      through BulkBuilder, special items through their generator
##   4. layering: per cell the claim that reaches farthest from the body wins,
##      draw order breaks ties (SPEC 7.3 rule 6)
##   5. shading over the WHOLE assembled figure in its rest pose, so a sleeve
##      shades as part of the silhouette (SPEC 6)
##   6. colour resolution: skin tones, garment tones, flat face colours
##
## Growth is always measured from the BODY, never from the layer underneath
## (SPEC 7.3 rule 6), so every item grows from the same base occupancy rather
## than from whatever was applied before it.

## Draw order the face sits at: below every garment category.
const FACE_DRAW_ORDER := -1

## Reach of a recolour-only claim.
const REACH_RECOLOUR := 0

enum Source { SKIN, GARMENT, FACE }


class Request extends RefCounted:
	var library: AssetLibrary
	var body_id: String = "male_average"
	var head_shape: String = "round"
	var expression: String = "neutral"
	var wardrobe: Wardrobe = null
	## A body to use INSTEAD of looking body_id up in the library. The body
	## editor sets this so the preview shows what is being drawn rather than
	## what is on disk; everything downstream is unchanged.
	var body_override: BodyDef = null
	## A head to use instead of looking head_shape up, for the head editor.
	var head_override: HeadDef = null
	## Clothing: Array of {"item": id, "colourway": name}
	var worn: Array = []
	## Features filling slots -- hair, facial hair: same shape as `worn`. Kept
	## apart because they come from a different place (a character's chosen
	## features, not an outfit), but assembled exactly like clothing.
	var features: Array = []
	## The eye set to draw, by id in the wardrobe, and its colourway. With
	## none, the library's own face for `expression` is drawn in the stock
	## colours: the "basic profile of the eyes" the body workspace shows.
	var eye_set_id: String = ""
	var eye_colourway: String = ""
	## The lid state over the eyes, by name (EyeLids.STATES). EyeLids.OFF
	## draws the eye exactly as drawn: no lids, no brow.
	var lids: String = EyeLids.DEFAULT
	## The character's skin tone (Palette.SKIN_TONE_NAMES).
	var skin_tone: String = Palette.DEFAULT_SKIN
	## The brow colour. Transparent (the default) means "follow the hair": the
	## hair's colour one shade darker, or dark brown with no hair.
	var brow_colour: Color = Color(0, 0, 0, 0)
	## Only this item is applied, for the editor's "solo an item". "" = all.
	var solo_item: String = ""
	var eye_colour: Color = Palette.EYE_BLACK
	## Multiply colours by face orientation for extra legibility (SPEC 6).
	var use_face_multiplier: bool = true

	static func make(p_library: AssetLibrary, p_body: String, p_head: String,
			p_expression: String) -> Request:
		var r := Request.new()
		r.library = p_library
		r.body_id = p_body
		r.head_shape = p_head
		r.expression = p_expression
		return r


class Part extends RefCounted:
	var name: String
	var parent: String = ""
	var pivot: Vector3 = Vector3.ZERO
	## Vector3i -> true
	var cells: Dictionary = {}
	## Vector3i -> Color, after tone and any orientation multiplier
	var colours: Dictionary = {}
	## Vector3i -> int (Shading.Tone)
	var tones: Dictionary = {}
	## Vector3i -> String region key ("" for cells no band covers)
	var regions: Dictionary = {}
	## Vector3i -> String item id ("" for bare skin)
	var owners: Dictionary = {}
	## Vector3i -> int Source
	var sources: Dictionary = {}
	## Cloth panels only: which body part drives this one (SPEC 7.4)
	var driver: String = ""

	func is_panel() -> bool:
		return not driver.is_empty()

	func count() -> int:
		return cells.size()


class Assembled extends RefCounted:
	var body: BodyDef = null
	var head: HeadDef = null
	var face: FaceDef = null
	## part name -> Part, parents before children
	var parts: Dictionary = {}
	var order: Array[String] = []
	var warnings: Array[String] = []

	func part(name: String) -> Part:
		return parts.get(name, null) as Part

	func total_voxels() -> int:
		var n := 0
		for name in parts.keys():
			n += (parts[name] as Part).count()
		return n

	## Every cell of the figure, part name per cell. Used by tests and exports.
	func all_cells() -> Dictionary:
		var out := {}
		for name in order:
			for cell in (parts[name] as Part).cells.keys():
				out[cell] = name
		return out


static func assemble(req: Request) -> Assembled:
	var out := Assembled.new()
	if req.library == null:
		out.warnings.append("no asset library")
		return out

	out.body = req.body_override if req.body_override != null \
		else req.library.body(req.body_id)
	out.head = req.head_override if req.head_override != null \
		else req.library.head(req.head_shape)
	out.face = req.library.face(req.expression)
	if out.body == null:
		out.warnings.append("unknown body '%s'" % req.body_id)
		return out
	if out.head == null:
		out.warnings.append("unknown head '%s'" % req.head_shape)
		return out

	var regions := out.body.regions

	# -- 1. base occupancy ---------------------------------------------------
	var base: Dictionary = {}  # part name -> Dictionary of cells
	for name in out.body.part_names():
		var def := out.body.part(name)
		if name == BodyDef.HEAD_PART:
			base[name] = out.head.cells.duplicate()
		else:
			base[name] = def.cells.duplicate()

	# -- 2 and 3. claims -----------------------------------------------------
	# part name -> cell -> winning claim
	var claims: Dictionary = {}
	var panels: Array = []

	# What counts as an exposed surface is a property of the whole figure, not
	# of one part: the seam where the chest meets the pelvis is inside the
	# body, however it looks from the chest's own cells.
	var occupancy: Dictionary = {}
	for part_name in base.keys():
		for cell in (base[part_name] as Dictionary).keys():
			occupancy[cell] = true

	var eyes: EyeSet = null
	if req.wardrobe != null and not req.eye_set_id.is_empty():
		eyes = req.wardrobe.eye_set(req.eye_set_id)
		if eyes == null:
			out.warnings.append("unknown eye set '%s'" % req.eye_set_id)
	if eyes != null or out.face != null:
		_claim_eyes(claims, eyes, out.face, req, base.get(BodyDef.HEAD_PART, {}))

	# Every item has its regions AND its special shapes; neither excludes the
	# other, so a dress is a bodice and a skirt.
	for entry in _worn_in_draw_order(req):
		var e: Dictionary = entry
		var item: GarmentItem = e["item"]
		var colourway := String(e["colourway"])
		if item.has_coverage():
			_claim_parametric(claims, item, colourway, base, regions, occupancy)
		for hanging in [false, true]:
			for index in item.specials.size():
				if SpecialItem.hangs_clear(item.special_type(index)) == hanging:
					_claim_special(claims, panels, out, item, index, colourway, base, regions,
						occupancy)

	# -- 4 and 5. compose, then shade the whole figure -----------------------
	var solid: Dictionary = {}
	var part_final: Dictionary = {}
	for name in base.keys():
		var cells: Dictionary = (base[name] as Dictionary).duplicate()
		var part_claims: Dictionary = claims.get(name, {})
		for cell in part_claims.keys():
			cells[cell] = true
		part_final[name] = cells
		for cell in cells.keys():
			solid[cell] = true

	# Panels are part of the silhouette, so they shade with everything else.
	for panel in panels:
		var p: Dictionary = panel
		var panel_name := String(p["name"])
		var panel_claims: Dictionary = claims.get(panel_name, {})
		var panel_cells := {}
		for cell in panel_claims.keys():
			panel_cells[cell] = true
			solid[cell] = true
		part_final[panel_name] = panel_cells

	var tone_map := Shading.tone_map(solid)

	# -- 6. build the parts --------------------------------------------------
	var skin := Palette.skin_tones(req.skin_tone)
	for name in out.body.part_names():
		var part := Part.new()
		part.name = name
		var def := out.body.part(name)
		part.parent = def.parent
		part.pivot = out.head.pivot if name == BodyDef.HEAD_PART else def.pivot
		_fill_part(part, part_final[name], claims.get(name, {}), tone_map,
			regions, req, skin)
		out.parts[name] = part
		out.order.append(name)

	for panel in panels:
		var p2: Dictionary = panel
		var panel_name2 := String(p2["name"])
		var panel_part := Part.new()
		panel_part.name = panel_name2
		panel_part.parent = String(p2["parent"])
		panel_part.pivot = p2["pivot"]
		panel_part.driver = String(p2["driver"])
		_fill_part(panel_part, part_final.get(panel_name2, {}),
			claims.get(panel_name2, {}), tone_map, regions, req, skin)
		out.parts[panel_name2] = panel_part
		out.order.append(panel_name2)

	return out


# ------------------------------------------------------------------ claims --

static func _worn_in_draw_order(req: Request) -> Array:
	var out: Array = []
	if req.wardrobe == null:
		return out
	var entries: Array = []
	for entry in req.worn:
		var w: Dictionary = entry
		if not req.solo_item.is_empty() and String(w.get("item", "")) != req.solo_item:
			continue
		entries.append(w)
	entries.append_array(req.features)
	for entry in entries:
		var e: Dictionary = entry
		var item_id := String(e.get("item", ""))
		var item := req.wardrobe.item(item_id)
		if item == null:
			continue
		var colourway := String(e.get("colourway", item.first_colourway()))
		if not item.has_colourway(colourway):
			colourway = item.first_colourway()
		out.append({"item": item, "colourway": colourway})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia: GarmentItem = a["item"]
		var ib: GarmentItem = b["item"]
		if ia.draw_order != ib.draw_order:
			return ia.draw_order < ib.draw_order
		return ia.id < ib.id)
	return out


## The eyes: an eye set's expression (or, with no eye set, the library face),
## each eye with its lid state applied (EyeLids), coloured, and claimed as a
## recolour below every garment. The face never adds volume: a cell that is not
## on this head's face plane is skipped (the fit tests catch that).
static func _claim_eyes(claims: Dictionary, eyes: EyeSet, face: FaceDef, req: Request,
		head_cells: Dictionary) -> void:
	var way := ""
	var expression := req.expression
	if eyes != null:
		expression = eyes.resolve(req.expression)
		way = req.eye_colourway if eyes.colourways.has(req.eye_colourway) \
			else eyes.first_colourway()
	var lid := Palette.lid_colour(req.skin_tone)
	var brow := brow_colour(req)
	for eye in [EyeSet.EYE_LEFT, EyeSet.EYE_RIGHT]:
		var cells: Dictionary = {}
		if eyes != null:
			cells = eyes.eye_cells(expression, eye)
		else:
			var source: Dictionary = face.screen_right if eye == EyeSet.EYE_RIGHT \
				else face.screen_left
			for cell in source.keys():
				if String(source[cell]) != FaceDef.ROLE_SKIN:
					cells[cell] = source[cell]
		if req.lids != EyeLids.OFF:
			cells = EyeLids.apply(cells, EyeLids.eye_state(req.lids, eye), eye)
		for cell in cells.keys():
			var bc: Vector2i = cell
			var c := EyeSet.cell_to_voxel(bc.x, bc.y, eye)
			if not head_cells.has(c):
				continue
			var role := String(cells[cell])
			var colour: Color
			if role == EyeLids.ROLE_LID:
				colour = lid
			elif role == EyeLids.ROLE_BROW:
				colour = brow
			elif eyes != null:
				colour = req.wardrobe.eye_colour(eyes.id, way, role)
			else:
				colour = FaceDef.colour_for_role(role, req.eye_colour)
			_offer(claims, BodyDef.HEAD_PART, c, {
				"source": Source.FACE,
				"role": role,
				"item": "",
				"colourway": way,
				"reach": REACH_RECOLOUR,
				"draw_order": FACE_DRAW_ORDER,
				"region": "",
				"colour": colour,
			})


## The brow colour a request resolves to: set explicitly, or the hair's colour
## one shade darker, or -- bald -- the brow of dark brown hair.
static func brow_colour(req: Request) -> Color:
	if req.brow_colour.a > 0.0:
		return req.brow_colour
	if req.wardrobe != null:
		for entry in req.features:
			var e: Dictionary = entry
			var it := req.wardrobe.item(String(e.get("item", "")))
			if it == null or it.slot != "hair":
				continue
			var role := "hair" if it.roles.has("hair") else (it.roles[0] if not it.roles.is_empty() else "")
			if role.is_empty():
				continue
			var way := String(e.get("colourway", ""))
			if not it.has_colourway(way):
				way = it.first_colourway()
			return req.wardrobe.tones_for(it.id, way, role)[2]
		if req.wardrobe.palette.has(Palette.DEFAULT_BROW_HAIR):
			return Palette.brow_from_hair(req.wardrobe.colour(Palette.DEFAULT_BROW_HAIR))
	return Palette.brow_from_hair(Color8(98, 66, 44))


static func _claim_parametric(claims: Dictionary, item: GarmentItem, colourway: String,
		base: Dictionary, regions: RegionMap, occupancy: Dictionary) -> void:
	var coverage := item.effective_coverage()
	if coverage.is_empty():
		return
	for part_name in base.keys():
		var name := String(part_name)
		var part_cells: Dictionary = base[name]
		if part_cells.is_empty():
			continue
		var by_region := BulkBuilder.cells_by_region(name, part_cells, regions, coverage)
		for region_key in by_region.keys():
			var key := String(region_key)
			var entry: Dictionary = coverage[key]
			var role := String(entry["role"])
			var bulk := int(entry["bulk"])
			var region_cells: Array = by_region[key]

			if bulk == 0:
				# Rule 1: recolour the body's own voxels, add nothing.
				for cell in region_cells:
					_offer(claims, name, cell, {
						"source": Source.GARMENT, "role": role, "item": item.id,
						"colourway": colourway, "reach": REACH_RECOLOUR,
						"draw_order": item.draw_order, "region": key,
					})
				continue

			var grown := BulkBuilder.grow(
				part_cells, region_cells, bulk, item.edge_style, occupancy)
			for cell in grown.keys():
				# Rule 5: grown voxels belong to the region and part they grew
				# from. Rule 6: reach is how far the ITEM gets from the body.
				_offer(claims, name, cell, {
					"source": Source.GARMENT, "role": role, "item": item.id,
					"colourway": colourway, "reach": bulk,
					"draw_order": item.draw_order, "region": key,
				})


## The figure as worn so far, per part or panel: the base cells plus every
## claim made before now. Recolour-only claims sit on body cells, so they add
## nothing new.
static func _worn_so_far(base: Dictionary, claims: Dictionary) -> Dictionary:
	var out := {}
	for name in base.keys():
		out[name] = (base[name] as Dictionary).duplicate()
	for name in claims.keys():
		if not out.has(name):
			out[name] = {}
		var cells: Dictionary = out[name]
		for cell in (claims[name] as Dictionary).keys():
			cells[cell] = true
	return out


static func _claim_special(claims: Dictionary, panels: Array, out: Assembled,
		item: GarmentItem, index: int, colourway: String, base: Dictionary,
		regions: RegionMap, occupancy: Dictionary) -> void:
	var ctx := SpecialItem.Context.new()
	ctx.body = out.body
	ctx.head = out.head
	ctx.regions = regions
	ctx.part_cells = base
	ctx.occupancy = occupancy
	ctx.worn_cells = _worn_so_far(base, claims)

	var type := item.special_type(index)
	var result := SpecialItem.generate(type, ctx, item.special_params(index))
	for w in result.warnings:
		out.warnings.append("%s: %s" % [item.name, w])

	# Panels are named for the item and the shape that made them. A generator
	# names its panels the same way every time, so a dress's skirt and a second
	# skirt worn with it would otherwise merge into one rigid part.
	var renamed := {}
	for panel in result.panels:
		var p: Dictionary = panel
		var unique := panel_name(item.id, index, String(p["name"]))
		renamed[String(p["name"])] = unique
		panels.append({
			"name": unique,
			"parent": String(p["parent"]),
			"pivot": p["pivot"],
			"driver": String(p["driver"]),
		})

	for claim in result.claims:
		var c: Dictionary = claim
		var part_name := String(c["part"])
		part_name = String(renamed.get(part_name, part_name))
		var cell: Vector3i = c["cell"]
		var recolour := bool(c.get("recolour", false))
		var body_cells: Dictionary = base.get(part_name, {})
		if body_cells.has(cell) != recolour:
			# An ordinary claim never replaces a body voxel; a recolour claim
			# only ever repaints one.
			continue
		_offer(claims, part_name, cell, {
			"source": Source.GARMENT,
			"role": String(c["role"]),
			"item": item.id,
			"colourway": colourway,
			"reach": REACH_RECOLOUR if recolour else int(c.get("reach", 1)),
			"draw_order": item.draw_order,
			"region": regions.key_for_cell(part_name, cell),
		})


## The rig part a special's panel becomes: unique per item and per shape.
## Underscores, because a node name cannot hold "/" or ":".
static func panel_name(item_id: String, index: int, generator_name: String) -> String:
	return "%s_%d_%s" % [item_id, index, generator_name]


## Layering (SPEC 7.3 rule 6): the claim that reaches farthest from the body
## wins; draw order breaks ties.
##
## Note on reading the rule: at a shared cell both items are the same distance
## out, so "reaching farthest" is taken to mean the item whose bulk in that
## region is greater -- the outer garment owns the stack. Only buried cells are
## affected either way, because the visible surface is always the outermost one.
static func _offer(claims: Dictionary, part_name: String, cell: Vector3i,
		claim: Dictionary) -> void:
	if not claims.has(part_name):
		claims[part_name] = {}
	var part_claims: Dictionary = claims[part_name]
	var current: Variant = part_claims.get(cell)
	if current != null:
		var c: Dictionary = current
		var reach := int(claim["reach"])
		var current_reach := int(c["reach"])
		if reach < current_reach:
			return
		if reach == current_reach and int(claim["draw_order"]) <= int(c["draw_order"]):
			return
	part_claims[cell] = claim


# ------------------------------------------------------------------ colour --

static func _fill_part(part: Part, cells: Dictionary, part_claims: Dictionary,
		tone_map: Dictionary, regions: RegionMap, req: Request,
		skin: Array[Color]) -> void:
	for cell in cells.keys():
		var c: Vector3i = cell
		part.cells[c] = true
		var tone := int(tone_map.get(c, Shading.Tone.MID))
		part.tones[c] = tone

		var claim: Variant = part_claims.get(c)
		if claim == null:
			part.colours[c] = skin[tone]
			part.sources[c] = Source.SKIN
			part.owners[c] = ""
			part.regions[c] = regions.key_for_cell(part.name, c)
			continue

		var cl: Dictionary = claim
		var source := int(cl["source"])
		part.sources[c] = source
		part.owners[c] = String(cl["item"])
		var region := String(cl["region"])
		part.regions[c] = region if not region.is_empty() else regions.key_for_cell(part.name, c)

		if source == Source.FACE:
			# Flat, not toned: shading a 4x5 pixel eye would only muddy it.
			if cl.has("colour"):
				part.colours[c] = cl["colour"]
			else:
				part.colours[c] = FaceDef.colour_for_role(String(cl["role"]), req.eye_colour)
			continue

		var tones: Array[Color] = Palette.garment_tones(Color.MAGENTA)
		if req.wardrobe != null:
			tones = req.wardrobe.tones_for(
				String(cl["item"]), String(cl["colourway"]), String(cl["role"]))
		part.colours[c] = Palette.apply_tone(tones, tone)


# ------------------------------------------------------------------- utils --

## Default worn list for an outfit, ready to hand to a Request.
static func worn_from_outfit(wardrobe: Wardrobe, outfit_name: String) -> Array:
	if wardrobe == null:
		return []
	return wardrobe.outfit(outfit_name)
