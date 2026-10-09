extends Camera3D

## Orbit camera.
## Mouse: right-drag or Option/Alt+left-drag orbits, middle-drag or Shift+left-drag pans, wheel zooms.
## Trackpad / Magic Mouse (macOS sends these as gestures): two-finger scroll zooms (vertical) and
## orbits (horizontal), Shift+scroll pans, pinch zooms.
## Keys: WASD/arrows pan, Q/E orbit, R/F tilt, +/- zoom, Home resets the view.

@export var target := Vector3(48.0, 8.0, 32.0)
@export var distance := 84.0
@export var yaw_degrees := -25.0
@export var pitch_degrees := 42.0
@export_range(5.0, 89.0) var min_pitch_degrees := 8.0
@export_range(5.0, 89.0) var max_pitch_degrees := 85.0
@export var min_distance := 8.0
@export var max_distance := 220.0
@export var orbit_degrees_per_pixel := 0.3
@export var pan_per_pixel := 0.0015
@export var zoom_factor := 1.12
@export var gesture_zoom_rate := 0.12
@export var gesture_orbit_degrees := 6.0
@export var gesture_pan_pixels := 30.0
@export var key_pan_rate := 0.6  # fraction of the distance per second
@export var key_orbit_degrees_per_second := 90.0
@export var key_zoom_rate := 1.5  # e-folds per second

var _orbiting := false
var _panning := false
var _left_drag := false
var _home := {}


func _ready() -> void:
	_home = {"target": target, "distance": distance, "yaw": yaw_degrees, "pitch": pitch_degrees}
	_apply()


func reset_view() -> void:
	target = _home.target
	distance = _home.distance
	yaw_degrees = _home.yaw
	pitch_degrees = _home.pitch
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			_orbit(motion.relative * orbit_degrees_per_pixel)
		elif _panning:
			_pan(motion.relative)
	elif event is InputEventPanGesture:
		var gesture := event as InputEventPanGesture
		if gesture.shift_pressed:
			_pan(-gesture.delta * gesture_pan_pixels)
		else:
			_zoom(exp(gesture.delta.y * gesture_zoom_rate))
			_orbit(Vector2(gesture.delta.x * gesture_orbit_degrees, 0.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		if magnify.factor > 0.0:
			_zoom(1.0 / magnify.factor)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cam_reset"):
		reset_view()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var move := Input.get_vector("cam_pan_left", "cam_pan_right", "cam_pan_forward", "cam_pan_back")
	var turn := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	var tilt := Input.get_axis("cam_tilt_down", "cam_tilt_up")
	var zoom := Input.get_axis("cam_zoom_in_key", "cam_zoom_out_key")
	if move == Vector2.ZERO and turn == 0.0 and tilt == 0.0 and zoom == 0.0:
		return
	target += (_ground_right() * move.x - _ground_forward() * move.y) * key_pan_rate * distance * delta
	yaw_degrees -= turn * key_orbit_degrees_per_second * delta
	pitch_degrees = clampf(pitch_degrees + tilt * key_orbit_degrees_per_second * 0.6 * delta, min_pitch_degrees, max_pitch_degrees)
	distance = clampf(distance * exp(zoom * key_zoom_rate * delta), min_distance, max_distance)
	_apply()


func _on_mouse_button(button: InputEventMouseButton) -> void:
	if button.button_index == MOUSE_BUTTON_LEFT:
		# Modifier + left drag stands in for the right/middle buttons on trackpads.
		if button.pressed and (button.alt_pressed or button.shift_pressed):
			_left_drag = true
			_orbiting = button.alt_pressed
			_panning = not button.alt_pressed
			get_viewport().set_input_as_handled()
		elif not button.pressed and _left_drag:
			_left_drag = false
			_orbiting = false
			_panning = false
	elif button.is_action("cam_orbit"):
		_orbiting = button.pressed
	elif button.is_action("cam_pan"):
		_panning = button.pressed
	elif button.is_action_pressed("cam_zoom_in"):
		_zoom(1.0 / zoom_factor)
	elif button.is_action_pressed("cam_zoom_out"):
		_zoom(zoom_factor)


func _orbit(degrees: Vector2) -> void:
	yaw_degrees -= degrees.x
	pitch_degrees = clampf(pitch_degrees + degrees.y, min_pitch_degrees, max_pitch_degrees)
	_apply()


# Drag-style pan: the ground follows the pointer.
func _pan(pixels: Vector2) -> void:
	target += (-_ground_right() * pixels.x + _ground_forward() * pixels.y) * pan_per_pixel * distance
	_apply()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func _ground_right() -> Vector3:
	return Vector3(global_basis.x.x, 0.0, global_basis.x.z).normalized()


func _ground_forward() -> Vector3:
	return Vector3(-global_basis.z.x, 0.0, -global_basis.z.z).normalized()


func _apply() -> void:
	var offset := Vector3(0.0, 0.0, distance)
	offset = offset.rotated(Vector3.RIGHT, -deg_to_rad(pitch_degrees))
	offset = offset.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	global_position = target + offset
	look_at(target, Vector3.UP)
