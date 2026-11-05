@tool
class_name OrbitCamera
extends Camera3D

## Orbit / pan / zoom around the figure, plus the front/back/side buttons
## SPEC.md section 8 asks for.
##
## Mouse: left or middle drag orbits, right drag or shift+drag pans, wheel
## zooms. Keys 1-6 jump to the fixed views. The figure faces -Z in Godot space,
## so "front" means looking from -Z toward the figure -- the same test the
## coordinate lock in tests/test_axes.gd performs.

const ORBIT_SPEED := 0.6
const PAN_SPEED := 0.0025
const ZOOM_STEP := 1.12
const MIN_DISTANCE := 0.35
const MAX_DISTANCE := 12.0
const PITCH_LIMIT := 89.0

## Views, as (yaw, pitch) in degrees. Yaw 0 looks at the figure's front.
const VIEWS := {
	"front": Vector2(0, 0),
	"back": Vector2(180, 0),
	"left": Vector2(-90, 0),
	"right": Vector2(90, 0),
	"three_quarter": Vector2(-30, -12),
	"top": Vector2(0, -75),
}

var target: Vector3 = Vector3(0, 0.875, 0)  ## mid-figure: 1.75 m / 2
var distance: float = 3.0
var yaw: float = -30.0
var pitch: float = -10.0

var _dragging_orbit := false
var _dragging_pan := false


func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = 35.0
	near = 0.05
	far = 50.0
	_apply()


## Frame the figure: centre on its bounds and back off enough to see all of it.
func frame(bounds: AABB) -> void:
	if bounds.size == Vector3.ZERO:
		return
	target = bounds.get_center()
	var radius := bounds.size.length() * 0.5
	var half_fov := deg_to_rad(fov) * 0.5
	distance = clampf(radius / maxf(0.01, sin(half_fov)) * 1.05, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func set_view(view: String) -> void:
	if not VIEWS.has(view):
		return
	var v: Vector2 = VIEWS[view]
	yaw = v.x
	pitch = v.y
	_apply()


func view_names() -> Array[String]:
	return ["front", "three_quarter", "left", "right", "back", "top"]


static func view_label(view: String) -> String:
	match view:
		"front": return "Front"
		"back": return "Back"
		"left": return "Left"
		"right": return "Right"
		"three_quarter": return "3/4"
		"top": return "Top"
	return view


func _apply() -> void:
	pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	# Yaw 0 puts the camera on -Z, which is the side the figure faces.
	var yaw_rad := deg_to_rad(yaw)
	var pitch_rad := deg_to_rad(pitch)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		-cos(yaw_rad) * cos(pitch_rad),
	)
	position = target + offset * distance
	look_at(target, Vector3.UP)


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if mb.shift_pressed:
					_dragging_pan = mb.pressed
				else:
					_dragging_orbit = mb.pressed
				return mb.pressed
			MOUSE_BUTTON_RIGHT:
				_dragging_pan = mb.pressed
				return mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance /= ZOOM_STEP
					_apply()
					return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance *= ZOOM_STEP
					_apply()
					return true
		return false

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_orbit:
			yaw += mm.relative.x * ORBIT_SPEED
			pitch -= mm.relative.y * ORBIT_SPEED
			_apply()
			return true
		if _dragging_pan:
			# Pan in the camera's own plane so dragging feels direct.
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			target -= (right * mm.relative.x - up * mm.relative.y) * PAN_SPEED * distance
			_apply()
			return true
		return false

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		var views := view_names()
		for i in views.size():
			if key.keycode == KEY_1 + i:
				set_view(views[i])
				return true
	return false
