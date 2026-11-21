@tool
class_name LowpolyAssembler
extends RefCounted

## A low-poly character, dressed: the garment rules of SPEC.md section 7.3, for polygons, then its face.
##
## It takes the same request the voxel assembler takes (CharacterAssembler.Request: body, head, skin tone, the
## wardrobe, the clothes worn, the features, the eye set and lid state, and a mouth), so a tab builds one request and
## either model can draw it. Body ids are the low-poly ones (LowpolyLibrary), which add a short body for each sex.
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
## The editor's move to low-poly, phase 3: ordinary clothing, hair made of regions, facial hair and the face. The
## other special shapes (straps, skirts, capes, drawn shapes, the hood) come later; an item that has one is worn
## without it, and the figure's warnings say so.

const BULK_UNIT := 1.0              ## how far one step of bulk stands off the body, in the files' units (lowpoly/README.md)
const FACE_PIECE := "face"


static func assemble(library: LowpolyLibrary, req: CharacterAssembler.Request) -> LowpolyFigure:
	var skin: Color = Palette.skin_tones(req.skin_tone)[1]
	var base := LowpolyFigure.make(library, req.body_id, req.head_shape, skin)
	if base == null:
		return null
	var head := library.head(req.head_shape)
	var raise := library.body(req.body_id).head_raise
	var f := base
	var whiskers: Array = []
	if req.wardrobe != null:
		var layers := _layers(req, base.warnings, whiskers)
		if not whiskers.is_empty():
			_grow_facial_hair(base, head, raise, whiskers, _wears_hair(req))
		if not layers.is_empty():
			f = _dress(base, layers)
	_draw_face(f, head, raise, req, skin, whiskers)
	return f


## Every worn item and feature, in the order worn: {cov: region -> {role, bulk}, order, colours: role -> Color, id}.
## Facial hair is added to `whiskers` as well: {parts, length, claim: [bulk, draw order, colour, item]}.
static func _layers(req: CharacterAssembler.Request, warnings: Array[String], whiskers: Array) -> Array:
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
		# soloing an item hides the other clothes; hair and facial hair stay, as on the voxel figure
		if index < features_from and not req.solo_item.is_empty() and it.id != req.solo_item:
			continue
		var way := String(e.get("colourway", ""))
		if not it.has_colourway(way):
			way = it.first_colourway()
		var colours := {}
		for role in it.roles:
			colours[role] = CharacterAssembler.role_tones(req, it.id, way, role)[1]
		for at in it.specials.size():
			var type := String((it.specials[at] as Dictionary).get("type", ""))
			if type != "facial_hair":
				warnings.append("%s: its %s is not on the low-poly figure yet" % [it.id, type.replace("_", " ")])
				continue
			var got := LowpolyFacialHair.read(it.special_params(at))
			for note in got[2]:
				warnings.append("%s: %s" % [it.id, note])
			var length := String(got[1])
			var colour: Color = colours.get("stubble" if length == "stubble" else "hair", Color.MAGENTA)
			whiskers.append({"parts": got[0], "length": length,
				"claim": [float(LowpolyFacialHair.STEPS[length]), it.draw_order, colour, it.id]})
		out.append({"cov": it.effective_coverage(), "order": it.draw_order, "colours": colours, "id": it.id})
	return out


## Whether hair is worn: a hair feature in a colour of its own (the sideburns then run up into it).
static func _wears_hair(req: CharacterAssembler.Request) -> bool:
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
			pts.append_array(PackedFloat64Array([head.points64[3 * k], head.points64[3 * k + 1], head.points64[3 * k + 2] + raise]))
		recs.append({"pts": pts, "at_key": hp["at_key"], "poly": f.polygons[first_poly + i], "claims": []})
	for w in whiskers:
		recs = LowpolyFacialHair.on_head(recs, head, w["parts"], w["claim"], hair, raise)
	f.points.resize(first_point)
	f.weights.resize(first_point)
	f.polygons.resize(first_poly)
	var index := {}
	for r in recs:
		var pts: PackedFloat64Array = r["pts"]
		var corners := PackedInt32Array()
		for i in pts.size() / 3:
			var key := Vector3i(roundi(pts[3 * i] * 1e4), roundi(pts[3 * i + 1] * 1e4), roundi(pts[3 * i + 2] * 1e4))
			if not index.has(key):
				index[key] = f.points.size()
				f.points.push_back(Vector3(pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]))
				f.weights.append({"head": 1.0})
			corners.push_back(index[key])
		var poly: Dictionary = (r["poly"] as Dictionary).duplicate()
		poly["corners"] = corners
		if not (r["claims"] as Array).is_empty():
			poly["claims"] = r["claims"]
		f.polygons.append(poly)


static func _dress(base: LowpolyFigure, layers: Array) -> LowpolyFigure:
	var polys := base.polygons
	var points := base.points

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

	# Each corner's normal (the sum of its visible polygons' area-weighted normals), and who is across each edge.
	var normals := PackedVector3Array()
	normals.resize(points.size())
	var across := {}
	for i in polys.size():
		var corners: PackedInt32Array = polys[i]["corners"]
		if not bool(polys[i]["hidden"]):
			var n := Vector3.ZERO
			for a in corners.size():
				n += points[corners[a]].cross(points[corners[(a + 1) % corners.size()]])
			for k in corners:
				normals[k] += n
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
	f.points = points.duplicate()
	f.weights = base.weights.duplicate()
	var welded := {}                    ## a lifted corner, by its source corner and where it went -> its index

	var corner_of := func(i: int, k: int) -> int:
		var w: Array = win[i]
		if w.is_empty() or float(w[0]) == 0.0:
			return k
		var at := _moved(polys[i], points[k], normals[k], float(w[0]))
		var key := "%d|%.4f|%.4f|%.4f" % [k, at.x, at.y, at.z]
		if not welded.has(key):
			welded[key] = f.points.size()
			f.points.push_back(at)
			f.weights.append(base.weights[k])
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
			if maxf(f.points[hem[0]].distance_to(f.points[hem[3]]), f.points[hem[1]].distance_to(f.points[hem[2]])) > 1e-6:
				var h := _poly(p, hem, w[2], w[3])
				h["hem"] = true
				f.polygons.append(h)
	return f


static func _edge(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


static func _poly(like: Dictionary, corners: PackedInt32Array, colour: Color, by: String) -> Dictionary:
	var out := like.duplicate()
	out.erase("claims")
	out["corners"] = corners
	out["colour"] = colour
	out["by"] = by
	return out


## Where a corner goes when its polygon is lifted by that much bulk (rules 2, 3 and 8).
static func _moved(p: Dictionary, v: Vector3, normal: Vector3, bulk: float) -> Vector3:
	var ln := normal.length()
	if bulk == 0.0 or ln < 1e-9:
		return v
	var n := normal / ln
	var step := bulk * BULK_UNIT
	var flat := Vector3(n.x, n.y, 0.0)
	var fl := flat.length()
	var d := flat / fl * step if (absf(n.z) < 0.7 and fl > 1e-9) else n * step       # rule 2, rule 3
	if v.z + d.z < 0.0 and fl > 1e-9:                                                  # rule 3: not below the floor
		d = flat / fl * step
		d.z = -v.z
	var part := String(p["part"])
	if part.begins_with("thigh") or part.begins_with("shin"):                         # rule 8: the gap between the legs
		var left := RegionMap.key_side(String(p["region"])) == RegionMap.SIDE_LEFT
		d.x = maxf(d.x, 0.0) if left else minf(d.x, 0.0)
	return v + d


# ---------------------------------------------------------------------------------------------- the face ---

## The eyes with their lids and brows (when the wardrobe has an eye set: the one asked for, or its first) and the
## mouth, as their own polygons on the head's flat patches: piece "face", following the head. An eye the eye set has
## not drawn at all is left out.
static func _draw_face(f: LowpolyFigure, head: LowpolyLibrary.Head, raise: float, req: CharacterAssembler.Request,
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
				CharacterAssembler.brow_colour(req))
	if Mouths.has_state(req.mouth):
		var hides := false
		for w in whiskers:
			hides = hides or ((w["parts"] as Array).has("moustache") and String(w["length"]) != "stubble")
		face.append_array(LowpolyFace.mouth(head, req.mouth, skin, LowpolyFacialHair.cover() if hides else []))
	for q in face:
		var pts: PackedFloat64Array = q["pts"]
		var corners := PackedInt32Array()
		for i in pts.size() / 3:
			corners.push_back(f.points.size())
			f.points.push_back(Vector3(pts[3 * i], pts[3 * i + 1], pts[3 * i + 2] + raise))
			f.weights.append({"head": 1.0})
		f.polygons.append({"corners": corners, "colour": q["colour"], "region": "", "part": "head",
			"piece": FACE_PIECE, "hidden": false, "by": "", "at": "", "unlit": q["unlit"], "role": q["role"]})
