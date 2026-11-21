@tool
class_name LowpolyAssembler
extends RefCounted

## A low-poly character, dressed: the garment rules of SPEC.md section 7.3, for polygons.
##
## It takes the same request the voxel assembler takes (CharacterAssembler.Request: body, head, skin tone, the
## wardrobe, the clothes worn and the features), so a tab builds one request and either model can draw it. Body ids
## are the low-poly ones (LowpolyLibrary), which add a short body for each sex.
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
## The editor's move to low-poly, phase 2: ordinary clothing and hair made of regions. Special shapes (straps,
## skirts, capes, facial hair, drawn shapes, the hood) come later; an item that has one is worn without it, and the
## figure's warnings say so.

const BULK_UNIT := 1.0              ## how far one step of bulk stands off the body, in the files' units (lowpoly/README.md)


static func assemble(library: LowpolyLibrary, req: CharacterAssembler.Request) -> LowpolyFigure:
	var skin: Color = Palette.skin_tones(req.skin_tone)[1]
	var base := LowpolyFigure.make(library, req.body_id, req.head_shape, skin)
	if base == null or req.wardrobe == null:
		return base
	var layers := _layers(req, base.warnings)
	if layers.is_empty():
		return base
	return _dress(base, layers)


## Every worn item and feature, in the order worn: {cov: region -> {role, bulk}, order, colours: role -> Color, id}.
static func _layers(req: CharacterAssembler.Request, warnings: Array[String]) -> Array:
	var out: Array = []
	for entry in req.worn + req.features:
		var e: Dictionary = entry
		var id := String(e.get("item", ""))
		var it := req.wardrobe.item(id)
		if it == null:
			warnings.append("%s: not in the wardrobe" % id)
			continue
		if not req.solo_item.is_empty() and it.id != req.solo_item:
			continue
		var way := String(e.get("colourway", ""))
		if not it.has_colourway(way):
			way = it.first_colourway()
		for type in it.special_types():
			warnings.append("%s: its %s is not on the low-poly figure yet" % [it.id, type.replace("_", " ")])
		var colours := {}
		for role in it.roles:
			colours[role] = CharacterAssembler.role_tones(req, it.id, way, role)[1]
		out.append({"cov": it.effective_coverage(), "order": it.draw_order, "colours": colours, "id": it.id})
	return out


static func _dress(base: LowpolyFigure, layers: Array) -> LowpolyFigure:
	var polys := base.polygons
	var points := base.points

	# rule 6: which worn item wins each polygon. Ears stay skin.
	var win: Array = []                 ## per polygon: [] or [bulk, draw order, colour, item]
	for p in polys:
		var best: Array = []
		if not bool(p["hidden"]) and String(p["at"]) != "ear":
			for layer in layers:
				var cov: Dictionary = layer["cov"]
				if not cov.has(p["region"]):
					continue
				var e: Dictionary = cov[p["region"]]
				var bulk := int(e["bulk"])
				var order := int(layer["order"])
				if best.is_empty() or bulk > int(best[0]) or (bulk == int(best[0]) and order > int(best[1])):
					best = [bulk, order, (layer["colours"] as Dictionary).get(String(e["role"]), Color.MAGENTA), layer["id"]]
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
		if w.is_empty() or int(w[0]) == 0:
			return k
		var at := _moved(polys[i], points[k], normals[k], int(w[0]))
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
			f.polygons.append(p.duplicate())
			continue
		var bulk := int(w[0])
		var lifted := PackedInt32Array()
		for k in corners:
			lifted.push_back(corner_of.call(i, k))
		f.polygons.append(_poly(p, lifted, w[2], w[3]))
		if bulk == 0:
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
			var m := 0 if (win[o] as Array).is_empty() else int(win[o][0])
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
	out["corners"] = corners
	out["colour"] = colour
	out["by"] = by
	return out


## Where a corner goes when its polygon is lifted by that much bulk (rules 2, 3 and 8).
static func _moved(p: Dictionary, v: Vector3, normal: Vector3, bulk: int) -> Vector3:
	var ln := normal.length()
	if bulk == 0 or ln < 1e-9:
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
