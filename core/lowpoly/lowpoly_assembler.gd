@tool
class_name LowpolyAssembler
extends RefCounted

## A low-poly character, dressed: the garment rules of SPEC.md section 7.3, for polygons, then its face.
##
## It takes a CharacterRequest (body, head, skin tone, the wardrobe, the clothes worn, the features, the eye set and
## lid state, and a mouth); every editor tab and the game build one. Body ids are LowpolyLibrary's: slim, average,
## heavy and short, for each sex.
##
## The rules, as lowpoly/dress.py has them, which this is checked against (tests/test_lowpoly.gd):
##
##   1  bulk 0 recolours the body's own polygons; bulk N lifts them N units off the body
##   2  growth is sideways, so a covered band next to a bare one makes a level hem step
##   3  surfaces that face up or down also grow up or down; nothing goes below the floor
##   4  arms, feet and head are separate pieces, so their bulk may overlap the torso's
##   6  where worn items claim the same region, the larger bulk wins, then the higher draw order (then whichever
##      is worn first)
##   8  nothing on a leg or foot grows toward the other leg
##
## Ears stay skin: nothing made of regions covers them. Where a lifted polygon meets a neighbour with less bulk, a
## hem polygon closes the step between them, in the lifted polygon's colour.
##
## Facial hair (LowpolyFacialHair) is cut out of the head's own polygons before anything is lifted, and claims them
## as a worn item claims a region: stubble and short recolour, medium and long lift by half a step and a step. The
## face (LowpolyFace: eyes, lids, brows, mouth) is drawn last, on the head's flat patches; a moustache longer than
## stubble hides the mouth under it.
##
## Special shapes come last, measured from the figure as dressed: straps (LowpolyShapes) lie on the chest and bend
## with it; the shapes of their own (LowpolyDrawn: long beard, ponytail, bun, horns, pauldrons) follow the head or the
## shoulders; a hood (LowpolyHood) is built after them when raised, so that it stands clear of them; skirts and capes
## are hanging cloth (LowpolyCloth), kept on the figure and laid afresh for every pose, over everything worn and over
## the cloths before them. A skirt's waistband covers the waist as a garment would.
##
## Everything is worked out in full precision (the figure's points64; Vec64), so that it agrees with lowpoly/.
##
## Not built: an old drawn shape (cells) that did not become one of the shapes of their own, and edge style; an item
## that has one is worn without it, and the figure's warnings say so.

const BULK_UNIT := 1.0              ## how far one step of bulk stands off the body, in the files' units (lowpoly/README.md)
const FACE_PIECE := "face"


static func assemble(library: LowpolyLibrary, req: CharacterRequest) -> LowpolyFigure:
	var skin: Color = Palette.skin_tones(req.skin_tone)[1]
	var base := LowpolyFigure.make(library, req.body_id, req.head_shape, skin)
	if base == null:
		return null
	var body := library.body(req.body_id)
	var head := library.head(req.head_shape)
	var raise := body.head_raise
	var f := base
	var whiskers: Array = []
	if req.wardrobe != null:
		var shapes: Array = []
		var layers := _layers(req, base.warnings, whiskers, shapes)
		if not whiskers.is_empty():
			_grow_facial_hair(base, head, raise, whiskers, _wears_hair(req))
		var surface := {}
		var bare_count := base.points.size()             # the body's corners, then the head's (after facial hair)
		if not layers.is_empty():
			var dressed := _dress(base, layers)
			f = dressed[0]
			surface = dressed[1]
		if not shapes.is_empty():
			_add_shapes(f, body, head, surface, shapes, bare_count)
	_draw_face(f, head, raise, req, skin, whiskers)
	return f


## Every worn item and feature, in the order worn: {cov: region -> {role, bulk}, order, colours: role -> Color, id}.
## Facial hair is added to `whiskers` as well: {parts, length, claim: [bulk, draw order, colour, item]}; straps,
## skirts and capes to `shapes`: [hangs, draw order, number, item, kind, settings, colours].
static func _layers(req: CharacterRequest, warnings: Array[String], whiskers: Array, shapes: Array) -> Array:
	var out: Array = []
	var features_from := req.worn.size()
	var all: Array = req.worn + req.features
	for index in all.size():
		var e: Dictionary = all[index]
		var id := String(e.get("item", ""))
		var it := req.wardrobe.item(id)
		if it == null:
			warnings.append("%s: not in the wardrobe" % id)
			continue
		# soloing an item hides the other clothes; hair and facial hair stay
		if index < features_from and not req.solo_item.is_empty() and it.id != req.solo_item:
			continue
		var way := String(e.get("colourway", ""))
		if not it.has_colourway(way):
			way = it.first_colourway()
		var colours := {}
		for role in it.roles:
			colours[role] = CharacterRequest.role_tones(req, it.id, way, role)[1]
		var cov := it.effective_coverage()
		for at in it.specials.size():
			var type := String((it.specials[at] as Dictionary).get("type", ""))
			var params := it.special_params(at)
			if type == "facial_hair":                      # it claims the head's own polygons: see _grow_facial_hair
				var got := LowpolyFacialHair.read(params)
				for note in got[2]:
					warnings.append("%s: %s" % [it.id, note])
				var length := String(got[1])
				var colour: Color = colours.get("stubble" if length == "stubble" else "hair", Color.MAGENTA)
				whiskers.append({"parts": got[0], "length": length,
					"claim": [float(LowpolyFacialHair.STEPS[length]), it.draw_order, colour, it.id]})
				continue
			if not LowpolyShapes.BUILT.has(type):
				if type == "shape":
					warnings.append("%s: its old drawn shape is not on the low-poly figure (the shapes of their own replace it)" % it.id)
				else:
					warnings.append("%s: its %s is not on the low-poly figure yet" % [it.id, type.replace("_", " ")])
				continue
			var own := cov
			cov = LowpolyShapes.coverage(type, params)      # the shape's regions, then the item's own over them
			for key in own.keys():
				cov[key] = own[key]
			shapes.append([LowpolyShapes.HANGS.has(type), it.draw_order, shapes.size(), it.id, type, params, colours])
		out.append({"cov": cov, "order": it.draw_order, "colours": colours, "id": it.id})
	return out


## Whether hair is worn: a hair feature in a colour of its own (the sideburns then run up into it).
static func _wears_hair(req: CharacterRequest) -> bool:
	for entry in req.features:
		var e: Dictionary = entry
		var it := req.wardrobe.item(String(e.get("item", "")))
		if it == null or it.slot != "hair" or not it.roles.has("hair"):
			continue
		var way := String(e.get("colourway", ""))
		if not it.has_colourway(way):
			way = it.first_colourway()
		var key := it.palette_key_for(way, "hair")
		if not key.is_empty() and not Palette.is_reference(key):
			return true
	return false


## Facial hair: the head's polygons cut along each item's parts, in full precision, and the pieces it covers given
## its claim. The head's corners are then made again from the pieces, welded where they meet (to a ten-thousandth,
## as the garment rules weld corners).
static func _grow_facial_hair(f: LowpolyFigure, head: LowpolyLibrary.Head, raise: float, whiskers: Array,
		hair: bool) -> void:
	var first_poly := f.polygons.size() - head.polygons.size()
	var first_point := f.points.size() - head.points.size()
	var recs: Array = []
	for i in head.polygons.size():
		var hp: Dictionary = head.polygons[i]
		var pts := PackedFloat64Array()
		for k in hp["corners"]:
			pts.append_array(f.point64(first_point + int(k)))
		recs.append({"pts": pts, "at_key": hp["at_key"], "poly": f.polygons[first_poly + i], "claims": []})
	for w in whiskers:
		recs = LowpolyFacialHair.on_head(recs, head, w["parts"], w["claim"], hair, raise)
	f.points.resize(first_point)
	f.points64.resize(3 * first_point)
	f.weights.resize(first_point)
	f.polygons.resize(first_poly)
	var index := {}
	for r in recs:
		var pts: PackedFloat64Array = r["pts"]
		var corners := PackedInt32Array()
		for i in pts.size() / 3:
			var key := Vector3i(roundi(pts[3 * i] * 1e4), roundi(pts[3 * i + 1] * 1e4), roundi(pts[3 * i + 2] * 1e4))
			if not index.has(key):
				index[key] = f.add_point(Vec64.at(pts, i), {"head": 1.0})
			corners.push_back(index[key])
		var poly: Dictionary = (r["poly"] as Dictionary).duplicate()
		poly["corners"] = corners
		if not (r["claims"] as Array).is_empty():
			poly["claims"] = r["claims"]
		f.polygons.append(poly)


## The garment rules. Returns [the dressed figure, the dressed surface: {corner: where it went}, for every corner
## that moved, as the polygon with the most bulk on it carries it (what the special shapes measure)].
static func _dress(base: LowpolyFigure, layers: Array) -> Array:
	var polys := base.polygons

	# rule 6: which worn item wins each polygon, then what claims the head's own polygons (facial hair). Ears stay
	# skin.
	var win: Array = []                 ## per polygon: [] or [bulk, draw order, colour, item]
	for p in polys:
		var best: Array = []
		if not bool(p["hidden"]) and String(p["at"]) != "ear":
			for layer in layers:
				var cov: Dictionary = layer["cov"]
				if not cov.has(p["region"]):
					continue
				var e: Dictionary = cov[p["region"]]
				var bulk := float(int(e["bulk"]))
				var order := int(layer["order"])
				if best.is_empty() or bulk > float(best[0]) or (bulk == float(best[0]) and order > int(best[1])):
					best = [bulk, order, (layer["colours"] as Dictionary).get(String(e["role"]), Color.MAGENTA), layer["id"]]
			for c in p.get("claims", []):
				var claim: Array = c
				if best.is_empty() or float(claim[0]) > float(best[0]) \
						or (float(claim[0]) == float(best[0]) and int(claim[1]) > int(best[1])):
					best = claim
		win.append(best)

	# Each corner's normal (the sum of its visible polygons' area-weighted normals), the most bulk worn on it, and
	# who is across each edge.
	var normals := PackedFloat64Array()
	normals.resize(base.points64.size())
	normals.fill(0.0)
	var most := {}                      ## corner -> [bulk, polygon]: the first polygon with the most bulk on it
	var across := {}
	for i in polys.size():
		var corners: PackedInt32Array = polys[i]["corners"]
		if not bool(polys[i]["hidden"]):
			var n := PackedFloat64Array([0.0, 0.0, 0.0])
			for a in corners.size():
				n = Vec64.add(n, Vec64.cross(base.point64(corners[a]), base.point64(corners[(a + 1) % corners.size()])))
			var b := 0.0 if (win[i] as Array).is_empty() else float(win[i][0])
			for k in corners:
				for c in 3:
					normals[3 * k + c] += n[c]
				if not most.has(k) or b > float(most[k][0]):
					most[k] = [b, i]
		for a in corners.size():
			var edge := _edge(corners[a], corners[(a + 1) % corners.size()])
			if not across.has(edge):
				across[edge] = []
			(across[edge] as Array).append(i)

	var f := LowpolyFigure.new()
	f.body_id = base.body_id
	f.head_shape = base.head_shape
	f.parts = base.parts
	f.warnings = base.warnings
	f.points = base.points.duplicate()
	f.points64 = base.points64.duplicate()
	f.weights = base.weights.duplicate()
	var welded := {}                    ## a lifted corner, by its source corner and where it went -> its number

	var lifted_at := func(i: int, k: int) -> PackedFloat64Array:
		var w: Array = win[i]
		if w.is_empty():
			return base.point64(k)
		return _moved(polys[i], base.point64(k), Vec64.at(normals, k), float(w[0]))
	var corner_of := func(i: int, k: int) -> int:
		var w: Array = win[i]
		if w.is_empty() or float(w[0]) == 0.0:
			return k
		var at: PackedFloat64Array = lifted_at.call(i, k)
		var key := Vector4i(k, roundi(at[0] * 1e4), roundi(at[1] * 1e4), roundi(at[2] * 1e4))
		if not welded.has(key):
			welded[key] = f.add_point(at, base.weights[k])
		return welded[key]

	for i in polys.size():
		var p: Dictionary = polys[i]
		var w: Array = win[i]
		var corners: PackedInt32Array = p["corners"]
		if w.is_empty():
			f.polygons.append(_poly(p, corners, p["colour"], ""))
			continue
		var bulk := float(w[0])
		var lifted := PackedInt32Array()
		for k in corners:
			lifted.push_back(corner_of.call(i, k))
		f.polygons.append(_poly(p, lifted, w[2], w[3]))
		if bulk == 0.0:
			continue
		# rule 2: a hem steps down to each neighbour that has less bulk
		for a in corners.size():
			var ka := corners[a]
			var kb := corners[(a + 1) % corners.size()]
			var o := -1
			for j in across[_edge(ka, kb)]:
				if int(j) != i:
					o = int(j)
					break
			if o < 0 or bool(polys[o]["hidden"]):
				continue
			var m := 0.0 if (win[o] as Array).is_empty() else float(win[o][0])
			if m >= bulk:
				continue
			# wound to face out over the step, toward the neighbour: this polygon runs ka to kb, so the hem runs the
			# other way round (the same way round, it faced back into the garment and was never drawn)
			var hem := PackedInt32Array([corner_of.call(o, ka), corner_of.call(o, kb), corner_of.call(i, kb), corner_of.call(i, ka)])
			var gap := maxf(Vec64.norm(Vec64.sub(f.point64(hem[0]), f.point64(hem[3]))),
				Vec64.norm(Vec64.sub(f.point64(hem[1]), f.point64(hem[2]))))
			if gap > 1e-6:
				var h := _poly(p, hem, w[2], w[3])
				h["hem"] = true
				f.polygons.append(h)

	var surface := {}
	for k in most.keys():
		if float(most[k][0]) > 0.0:
			surface[k] = lifted_at.call(int(most[k][1]), int(k))
	return [f, surface]


static func _edge(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


static func _poly(like: Dictionary, corners: PackedInt32Array, colour: Color, by: String) -> Dictionary:
	var out := like.duplicate()
	out.erase("claims")
	out["corners"] = corners
	out["colour"] = colour
	out["by"] = by
	return out


## Where a corner goes when its polygon is lifted by that much bulk (rules 2, 3 and 8). Full precision.
static func _moved(p: Dictionary, v: PackedFloat64Array, normal: PackedFloat64Array, bulk: float) -> PackedFloat64Array:
	if bulk == 0.0:
		return v
	var ln := Vec64.norm(normal)
	if ln < 1e-9:
		return v
	var n := Vec64.div(normal, ln)
	var step := bulk * BULK_UNIT
	var flat := Vec64.v(n[0], n[1], 0.0)
	var fl := Vec64.norm(flat)
	var d := Vec64.mul(Vec64.div(flat, fl), step) if (absf(n[2]) < 0.7 and fl > 1e-9) else Vec64.mul(n, step)   # rule 2, rule 3
	if v[2] + d[2] < 0.0 and fl > 1e-9:                                                # rule 3: not below the floor
		d = Vec64.mul(Vec64.div(flat, fl), step)
		d[2] = -v[2]
	var part := String(p["part"])
	if part.begins_with("thigh") or part.begins_with("shin"):                         # rule 8: the gap between the legs
		var left := RegionMap.key_side(String(p["region"])) == RegionMap.SIDE_LEFT
		d[0] = maxf(d[0], 0.0) if left else minf(d[0], 0.0)
	return Vec64.add(v, d)


# ------------------------------------------------------------------------------------------- the shapes ---

## Special shapes, measured from the dressed figure: those that lie on it first (a raised hood last of them, so that
## it stands clear of a ponytail or a bun; a lowered one lies on the back under them), then hanging cloth in draw
## order, each hanging over everything before it (laid standing, so the next one hangs over it).
static func _add_shapes(f: LowpolyFigure, body: LowpolyLibrary.Body, head: LowpolyLibrary.Head, surface: Dictionary,
		shapes: Array, bare_count: int) -> void:
	var fit := LowpolyShapes.Fit.new()
	fit.body = body
	fit.figure = f
	fit.surface = surface
	fit.cx = 12.0
	if head != null:
		var first := body.points.size()
		fit.use_head(head, body.head_raise, first, bare_count - first)
	var raised_hood := func(s: Array) -> bool:
		return String(s[4]) == "hood" and LowpolyShapes._flag(LowpolyShapes.settings("hood", s[5])["raised"])
	var order := shapes.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool:
		if bool(a[0]) != bool(b[0]):
			return not bool(a[0])
		var ha: bool = raised_hood.call(a)
		var hb: bool = raised_hood.call(b)
		if ha != hb:
			return not ha
		if int(a[1]) != int(b[1]):
			return int(a[1]) < int(b[1])
		return int(a[2]) < int(b[2]))
	var rest := LowpolyPose.rest()
	for shape in order:
		var item_id := String(shape[3])
		var kind := String(shape[4])
		var params: Dictionary = shape[5]
		var colours: Dictionary = shape[6]
		var made: Array = []
		match kind:
			"straps": made = LowpolyShapes.straps(fit, params, colours, item_id)
			"skirt": made = LowpolyShapes.skirt(fit, params, colours, item_id)
			"cape": made = LowpolyShapes.cape(fit, params, colours, item_id)
			"hood": made = LowpolyHood.hood(fit, params, colours, item_id)
			_:
				if SpecialItem.OWN_SHAPES.has(kind):
					made = LowpolyDrawn.build(fit, kind, params, colours, item_id)
		if made.size() < 2:
			f.warnings.append("%s: its %s could not be built" % [item_id, kind])
			continue
		for note in made[1]:
			f.warnings.append(String(note))
		if not bool(shape[0]):
			for q in made[0]:
				var pts: PackedFloat64Array = q["pts"]
				var shares: Array = q["shares"]
				var corners := PackedInt32Array()
				for i in pts.size() / 3:
					corners.push_back(f.add_point(Vec64.at(pts, i), (shares[i] as Dictionary).duplicate()))
				f.polygons.append({"corners": corners, "colour": q["colour"], "region": "", "part": String(q.get("part", "chest")),
					"piece": "shape:" + kind, "hidden": false, "by": item_id, "at": ""})
		elif made[0] != null:
			var cloth: LowpolyCloth = made[0]
			cloth.by = item_id
			f.cloths.append(cloth)
			var got := fit.points(cloth.over)
			fit.laid.append_array(cloth.lay(rest, got[0], got[1]))


# ---------------------------------------------------------------------------------------------- the face ---

## The eyes with their lids and brows (when the wardrobe has an eye set: the one asked for, or its first) and the
## mouth, as their own polygons on the head's flat patches: piece "face", following the head. An eye the eye set has
## not drawn at all is left out.
static func _draw_face(f: LowpolyFigure, head: LowpolyLibrary.Head, raise: float, req: CharacterRequest,
		skin: Color, whiskers: Array) -> void:
	var face: Array = []
	if req.wardrobe != null:
		var eyes := req.wardrobe.eye_set(req.eye_set_id)
		if eyes == null and not req.eye_set_id.is_empty():
			f.warnings.append("eye set '%s': not in the wardrobe; the first one is drawn" % req.eye_set_id)
		if eyes == null and not req.wardrobe.first_eye_set_id().is_empty():
			eyes = req.wardrobe.eye_set(req.wardrobe.first_eye_set_id())
		if eyes == null:
			f.warnings.append("the wardrobe has no eye set: the face has no eyes")
		else:
			var way := req.eye_colourway if eyes.colourways.has(req.eye_colourway) else eyes.first_colourway()
			var colours := {}
			for role in LowpolyFace.UNLIT_ROLES:
				colours[role] = req.wardrobe.eye_colour(eyes.id, way, role)
			face = LowpolyFace.eyes(head, eyes, colours, req.lids, Palette.lid_colour(req.skin_tone),
				CharacterRequest.brow_colour_of(req))
	if Mouths.has_state(req.mouth):
		var hides := false
		for w in whiskers:
			hides = hides or ((w["parts"] as Array).has("moustache") and String(w["length"]) != "stubble")
		face.append_array(LowpolyFace.mouth(head, req.mouth, skin, LowpolyFacialHair.cover() if hides else []))
	for q in face:
		var pts: PackedFloat64Array = q["pts"]
		var corners := PackedInt32Array()
		for i in pts.size() / 3:
			corners.push_back(f.add_point(Vec64.v(pts[3 * i], pts[3 * i + 1], pts[3 * i + 2] + raise), {"head": 1.0}))
		f.polygons.append({"corners": corners, "colour": q["colour"], "region": "", "part": "head",
			"piece": FACE_PIECE, "hidden": false, "by": "", "at": "", "unlit": q["unlit"], "role": q["role"]})
