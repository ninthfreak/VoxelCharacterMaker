@tool
class_name AssetLibrary
extends RefCounted

## Loads and caches the body, head and face libraries from assets/.
##
## Two sources, in order:
##
##   assets/edited/   bodies and heads saved from the editor's Bodies tab
##   assets/          what tools/build_bodies.py generates
##
## An edited file wins over the generated one with the same name. The script
## never writes into assets/edited/, so regenerating cannot discard an edit,
## and reverting an edit is deleting one file. That keeps both CLAUDE.md's
## "regenerate rather than hand-edit" and SPEC 3.3's "the owner expects to tweak
## the bodies in the editor" true at once, without choosing between them yet.
##
## This class is the only place that knows the file naming scheme.

const DIR := "res://assets"
const EDITED_DIR := "res://assets/edited"

const SEXES: Array[String] = ["male", "female"]
const BUILDS: Array[String] = ["slim", "average", "heavy"]
const HEAD_SHAPES: Array[String] = ["round", "boxy", "oval", "strong", "heart"]

## The starter expressions (SPEC.md section 5). The owner expects to adjust
## these in the editor, so the list is discovered from disk rather than fixed;
## this is only the order they appear in UI.
const EXPRESSION_ORDER: Array[String] = [
	"neutral", "blink", "happy", "angry", "sad", "surprised",
	"bored", "wink", "look_left", "look_right", "look_down",
]

## Whether to prefer assets/edited/. Off for the acceptance tests, which check
## the generated assets against SPEC numbers an edit is free to change.
var use_edited := true
## Where edits are read from and saved to. A variable so tests can point it at
## a scratch folder rather than the project's own.
var edited_dir: String = EDITED_DIR

var bodies: Dictionary = {}       ## "male_average" -> BodyDef
var heads: Dictionary = {}        ## "round" -> HeadDef
var faces: Dictionary = {}        ## "neutral" -> FaceDef
var errors: Array[String] = []

var _body_order: Array[String] = []
var _face_order: Array[String] = []


static func body_path(sex: String, build: String) -> String:
	return "%s/body42_%s_%s_parts.json" % [DIR, sex, build]


static func head_path(shape: String) -> String:
	return "%s/head42_%s.json" % [DIR, shape]


static func face_path(name: String) -> String:
	return "%s/face42_%s.json" % [DIR, name]


func edited_body_path(sex: String, build: String) -> String:
	return "%s/body42_%s_%s_parts.json" % [edited_dir, sex, build]


func edited_head_path(shape: String) -> String:
	return "%s/head42_%s.json" % [edited_dir, shape]


func is_body_edited(id: String) -> bool:
	var body := body(id)
	return body != null and use_edited \
		and FileAccess.file_exists(edited_body_path(body.sex, body.build))


func is_head_edited(shape: String) -> bool:
	return use_edited and FileAccess.file_exists(edited_head_path(shape))


func _body_source(sex: String, build: String) -> String:
	if use_edited and FileAccess.file_exists(edited_body_path(sex, build)):
		return edited_body_path(sex, build)
	return body_path(sex, build)


func _head_source(shape: String) -> String:
	if use_edited and FileAccess.file_exists(edited_head_path(shape)):
		return edited_head_path(shape)
	return head_path(shape)


## Put an edited body in place for this session, so every tab sees it.
func replace_body(def: BodyDef) -> void:
	if def != null and bodies.has(def.id):
		bodies[def.id] = def


func replace_head(def: HeadDef) -> void:
	if def != null and heads.has(def.shape):
		heads[def.shape] = def


## Load a body or head again from disk -- the edited file if there is one --
## throwing away whatever was put in place for the session. Returns "" or an
## error message.
func reload_body(id: String) -> String:
	var body := body(id)
	if body == null:
		return "unknown body %s" % id
	var fresh := BodyDef.load_from(_body_source(body.sex, body.build))
	if fresh == null:
		return "could not reload %s" % id
	bodies[id] = fresh
	return ""


func reload_head(shape: String) -> String:
	var fresh := HeadDef.load_from(_head_source(shape))
	if fresh == null:
		return "could not reload the %s head" % shape
	heads[shape] = fresh
	return ""


## Drop an edit: delete its file and load the generated one back. Returns ""
## or an error message.
func revert_body(id: String) -> String:
	var body := body(id)
	if body == null:
		return "unknown body %s" % id
	var path := edited_body_path(body.sex, body.build)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return "could not delete %s (error %d)" % [path, err]
	var fresh := BodyDef.load_from(body_path(body.sex, body.build))
	if fresh == null:
		return "could not reload the generated %s" % id
	bodies[id] = fresh
	return ""


func revert_head(shape: String) -> String:
	var path := edited_head_path(shape)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return "could not delete %s (error %d)" % [path, err]
	var fresh := HeadDef.load_from(head_path(shape))
	if fresh == null:
		return "could not reload the generated %s head" % shape
	heads[shape] = fresh
	return ""


## Load everything. Returns true when nothing failed; check errors otherwise.
func load_all() -> bool:
	errors.clear()
	bodies.clear()
	heads.clear()
	faces.clear()
	_body_order.clear()
	_face_order.clear()

	for sex in SEXES:
		for build in BUILDS:
			var path := _body_source(sex, build)
			var def := BodyDef.load_from(path)
			if def == null:
				errors.append("body %s %s could not be loaded (%s)" % [sex, build, path])
				continue
			bodies[def.id] = def
			_body_order.append(def.id)

	for shape in HEAD_SHAPES:
		var head := HeadDef.load_from(_head_source(shape))
		if head == null:
			errors.append("head %s could not be loaded" % shape)
			continue
		heads[shape] = head

	for name in _discover_expressions():
		var face := FaceDef.load_from(face_path(name))
		if face == null:
			errors.append("expression %s could not be loaded" % name)
			continue
		faces[name] = face
		_face_order.append(name)

	return errors.is_empty()


## Expression files present on disk, in EXPRESSION_ORDER first and then any
## extras the owner has added, alphabetically.
func _discover_expressions() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			var f := String(file)
			# An imported project may show "face42_x.json.remap" or ".import".
			if not f.begins_with("face42_"):
				continue
			if not f.ends_with(".json"):
				continue
			found.append(f.substr(7, f.length() - 12))
	var out: Array[String] = []
	for name in EXPRESSION_ORDER:
		if name in found:
			out.append(name)
	var extras: Array[String] = []
	for name in found:
		if not (name in EXPRESSION_ORDER):
			extras.append(name)
	extras.sort()
	out.append_array(extras)
	if out.is_empty():
		# Nothing discoverable (can happen in an exported build): fall back.
		return EXPRESSION_ORDER.duplicate()
	return out


func body(id: String) -> BodyDef:
	return bodies.get(id, null) as BodyDef


func body_of(sex: String, build: String) -> BodyDef:
	return body("%s_%s" % [sex, build])


func head(shape: String) -> HeadDef:
	return heads.get(shape, null) as HeadDef


func face(name: String) -> FaceDef:
	return faces.get(name, null) as FaceDef


func body_ids() -> Array[String]:
	return _body_order.duplicate()


func head_shapes() -> Array[String]:
	var out: Array[String] = []
	for shape in HEAD_SHAPES:
		if heads.has(shape):
			out.append(shape)
	return out


func expression_names() -> Array[String]:
	return _face_order.duplicate()


## The region map, which SPEC section 3.4 says is identical on all six bodies.
## Taken from the first body loaded; verify_regions_match() checks the claim.
func region_map() -> RegionMap:
	for id in _body_order:
		return (bodies[id] as BodyDef).regions
	return null


func verify_regions_match() -> String:
	var reference: RegionMap = null
	var reference_id := ""
	for id in _body_order:
		var def: BodyDef = bodies[id]
		if reference == null:
			reference = def.regions
			reference_id = id
			continue
		for name in reference.bands.keys():
			var a: RegionMap.Band = reference.bands[name]
			var b: RegionMap.Band = def.regions.band(String(name))
			if b == null:
				return "%s is missing band %s that %s has" % [id, name, reference_id]
			if a.z0 != b.z0 or a.z1 != b.z1 or a.family != b.family or a.trim != b.trim:
				return "band %s differs between %s and %s" % [name, reference_id, id]
		if def.regions.bands.size() != reference.bands.size():
			return "%s has %d bands, %s has %d" % [
				id, def.regions.bands.size(), reference_id, reference.bands.size()]
	return ""


func summary() -> String:
	return "%d bodies, %d heads, %d expressions" % [bodies.size(), heads.size(), faces.size()]
