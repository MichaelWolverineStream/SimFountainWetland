extends Camera3D

## Orbit camera: RMB orbit, MMB pan, wheel zoom.

@export var target := Vector3(48.0, 8.0, 32.0)
@export var distance := 95.0
@export var yaw_degrees := -25.0
@export var pitch_degrees := 42.0
@export_range(5.0, 89.0) var min_pitch_degrees := 8.0
@export_range(5.0, 89.0) var max_pitch_degrees := 85.0
@export var min_distance := 8.0
@export var max_distance := 220.0
@export var orbit_degrees_per_pixel := 0.3
@export var pan_per_pixel := 0.0015
@export var zoom_factor := 1.12

var _orbiting := false
var _panning := false


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_action("cam_orbit"):
			_orbiting = event.pressed
		elif event.is_action("cam_pan"):
			_panning = event.pressed
		elif event.is_action_pressed("cam_zoom_in"):
			distance = maxf(min_distance, distance / zoom_factor)
			_apply()
		elif event.is_action_pressed("cam_zoom_out"):
			distance = minf(max_distance, distance * zoom_factor)
			_apply()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			yaw_degrees -= motion.relative.x * orbit_degrees_per_pixel
			pitch_degrees = clampf(pitch_degrees + motion.relative.y * orbit_degrees_per_pixel, min_pitch_degrees, max_pitch_degrees)
			_apply()
		elif _panning:
			var right := global_basis.x
			var forward := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z).normalized()
			target += (-right * motion.relative.x + forward * motion.relative.y) * pan_per_pixel * distance
			_apply()


func _apply() -> void:
	var offset := Vector3(0.0, 0.0, distance)
	offset = offset.rotated(Vector3.RIGHT, -deg_to_rad(pitch_degrees))
	offset = offset.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	global_position = target + offset
	look_at(target, Vector3.UP)
