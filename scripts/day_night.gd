extends Node

## Sun, moon, sky and ambient light follow the simulated hour. The shown hour chases the sim
## hour (forward only) so the light glides between ticks; big jumps snap.

signal night_changed(is_night: bool)
signal daylight_changed(daylight: float)  # 0 night .. 1 full day

const DAY_TOP := Color(0.36, 0.60, 0.92)
const DAY_HORIZON := Color(0.75, 0.86, 0.95)
const DUSK_TOP := Color(0.34, 0.40, 0.70)
const DUSK_HORIZON := Color(1.0, 0.70, 0.50)
const NIGHT_TOP := Color(0.03, 0.05, 0.13)
const NIGHT_HORIZON := Color(0.10, 0.13, 0.26)
const NIGHT_AMBIENT := Color(0.36, 0.44, 0.70)
const SNAP_HOURS := 8.0

@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var sun_energy := 1.15
@export var moon_energy := 0.4
@export var min_chase_hours_per_second := 2.5

var _shown := 12.5  # continuous hours
var _target := 12.5
var _night := false
var _daylight := -1.0
var _environment: Environment
var _sky: ProceduralSkyMaterial


func _ready() -> void:
	_environment = world_environment.environment
	_sky = _environment.sky.sky_material as ProceduralSkyMaterial
	_apply()


## Shows the middle of the given sim hour.
func set_hour(hour: float, snap := false) -> void:
	_target += fposmod(hour + 0.5 - _target, 24.0)
	if snap or _target - _shown > SNAP_HOURS:
		_shown = _target
		_apply()


func is_night() -> bool:
	return _night


func get_daylight() -> float:
	return _daylight


func _process(delta: float) -> void:
	if _shown >= _target:
		return
	var rate := maxf(min_chase_hours_per_second, (_target - _shown) * 3.0)
	_shown = minf(_shown + rate * delta, _target)
	_apply()


func _apply() -> void:
	var hour := fposmod(_shown, 24.0)
	var day_phase := (hour - 6.0) / 12.0  # 0 at sunrise, 1 at sunset
	var elevation := sin(day_phase * PI) * 65.0  # negative at night
	var daylight := smoothstep(-4.0, 20.0, elevation)
	var twilight := 1.0 - absf(daylight * 2.0 - 1.0)

	sun.rotation_degrees = Vector3(-maxf(elevation, 8.0), lerpf(100.0, -100.0, clampf(day_phase, 0.0, 1.0)), 0.0)
	sun.light_energy = daylight * sun_energy
	sun.light_color = Color(1.0, 0.62, 0.40).lerp(Color(1.0, 0.97, 0.92), smoothstep(4.0, 35.0, elevation))
	sun.visible = daylight > 0.01

	var night := 1.0 - daylight
	var night_phase := fposmod(hour - 18.0, 24.0) / 12.0
	moon.rotation_degrees = Vector3(-maxf(sin(night_phase * PI) * 50.0, 15.0), lerpf(100.0, -100.0, clampf(night_phase, 0.0, 1.0)), 0.0)
	moon.light_energy = night * moon_energy
	moon.visible = night > 0.01

	var top := NIGHT_TOP.lerp(DAY_TOP, daylight).lerp(DUSK_TOP, twilight * 0.7)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight).lerp(DUSK_HORIZON, twilight * 0.8)
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = horizon.darkened(0.6)
	_environment.ambient_light_color = NIGHT_AMBIENT
	_environment.ambient_light_sky_contribution = lerpf(0.2, 1.0, daylight)
	_environment.ambient_light_energy = lerpf(0.42, 0.8, daylight)

	var now_night := daylight < 0.35
	if now_night != _night:
		_night = now_night
		night_changed.emit(now_night)
	if absf(daylight - _daylight) > 0.005:
		_daylight = daylight
		daylight_changed.emit(daylight)
