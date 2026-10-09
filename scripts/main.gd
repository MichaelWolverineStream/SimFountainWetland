extends Node3D

## Game flow. In LIVE mode the player changes conditions and fountains and watches the oxygen.
## "Set baseline" and "Compare with baseline" both reset the simulation, fast-forward until the
## daily mean DO settles and record the final 24 h. A comparison opens a report against the
## baseline, so any two setups can be compared (e.g. summer vs autumn, or 0 vs 3 fountains).

enum Mode { LIVE, MEASURE_BASELINE, MEASURE_COMPARISON }

const PlacementTool := preload("res://scripts/placement_tool.gd")
const Hud := preload("res://scripts/hud.gd")
const FountainVisuals := preload("res://scripts/fountain_visuals.gd")
const SliceController := preload("res://scripts/slice_controller.gd")
const DayNight := preload("res://scripts/day_night.gd")
const LevelDecor := preload("res://scripts/level_decor.gd")
const Ducks := preload("res://scripts/ducks.gd")
const Critters := preload("res://scripts/critters.gd")
const SkyDetails := preload("res://scripts/sky_details.gd")
const DAY_KEYS := ["mean_do", "min_do", "max_do", "surface_mean_do", "bottom_mean_do", "hypoxic_fraction",
		"total_do_kg", "layer_mean", "layer_min", "layer_max"]

@export var settle_min_days := 3
@export var settle_max_days := 14
@export var steady_tolerance := 0.01
@export var max_units := 8
@export var default_lpm := 1500.0

var mode := Mode.LIVE
var baseline := {}
var last_report := {}
var selected_id := -1

var _days_run := 0
# Adding a unit is two placements: the pump creates it, the sprayer completes it.
var _adding := false
var _adding_id := -1
var _lpm := 0.0
var _water_view := 1.0
var _water_view_tween: Tween

@onready var simulation: Node = $Simulation
@onready var hud: Hud = $HUD
@onready var placement: PlacementTool = $PlacementTool
@onready var fountain_visuals: FountainVisuals = $FountainVisuals
@onready var slice: SliceController = $SliceController
@onready var day_night: DayNight = $DayNight
@onready var decor: LevelDecor = $Decor
@onready var ducks: Ducks = $Ducks
@onready var critters: Critters = $Critters
@onready var sky: SkyDetails = $SkyDetails


func _ready() -> void:
	_fit_window_to_screen()
	if not simulation.IsLoaded:
		hud.set_status("Error", "The simulation could not be built from the level.")
		hud.set_controls_enabled(false, false, false)
		hud.set_measuring(false, false)
		hud.show_message("Simulation failed to load: %s" % simulation.LoadError, true)
		return

	simulation.connect("TicksAdvanced", _on_ticks_advanced)
	simulation.connect("DayCompleted", _on_day_completed)
	simulation.connect("FastForwardProgress", hud.set_progress)
	simulation.connect("FastForwardFinished", _on_fast_forward_finished)

	hud.speed_selected.connect(_set_speed)
	hud.reset_pressed.connect(_on_reset)
	hud.environment_changed.connect(_on_environment_changed)
	hud.set_baseline_pressed.connect(_start_measure.bind(Mode.MEASURE_BASELINE))
	hud.compare_pressed.connect(_start_measure.bind(Mode.MEASURE_COMPARISON))
	hud.stop_pressed.connect(_stop_measure)
	hud.show_report_pressed.connect(_show_last_report)
	hud.make_baseline_pressed.connect(_on_make_baseline)
	hud.add_fountain_pressed.connect(_on_add_fountain)
	hud.move_pump_pressed.connect(_on_move.bind(PlacementTool.Mode.PUMP))
	hud.move_sprayer_pressed.connect(_on_move.bind(PlacementTool.Mode.SPRAYER))
	hud.remove_fountain_pressed.connect(_on_remove_fountain)
	hud.clear_fountains_pressed.connect(_on_clear_fountains)
	hud.fountain_selected.connect(_select)
	hud.lpm_changed.connect(_on_lpm_changed)
	hud.slice_changed.connect(slice.set_slice)
	hud.slice_changed.connect(fountain_visuals.set_slice)
	hud.water_view_changed.connect(_on_water_view_changed)
	placement.is_valid = _is_column_free
	placement.placed.connect(_on_placed)
	placement.cancelled.connect(_on_placement_cancelled)
	placement.mode_changed.connect(_on_placement_mode_changed)
	placement.column_clicked.connect(_on_column_clicked)
	day_night.night_changed.connect(decor.set_night)
	day_night.daylight_changed.connect(decor.set_daylight)
	day_night.daylight_changed.connect(critters.set_daylight)
	day_night.daylight_changed.connect(sky.set_daylight)
	_set_water_view(1.0)

	var origin: Vector3i = simulation.GetGridOrigin()
	var grid_size: Vector3i = simulation.GetGridSize()
	slice.configure(origin, grid_size)
	fountain_visuals.set_bounds(origin, grid_size)
	fountain_visuals.max_lpm = simulation.MaxLpm
	hud.configure_slice(origin.x, origin.x + grid_size.x - 1, slice.cell_x)
	hud.set_max_lpm(simulation.MaxLpm)
	_lpm = minf(default_lpm, simulation.MaxLpm)
	hud.set_lpm(_lpm)
	var environment: Array = hud.get_environment()
	_on_environment_changed(environment[0], environment[1], environment[2], environment[3])
	hud.set_baseline({})
	_enter_live()
	_refresh_fountains()
	day_night.set_hour(simulation.GetStats().hour, true)
	decor.set_night(day_night.is_night())
	decor.set_daylight(day_night.get_daylight())
	critters.set_daylight(day_night.get_daylight())
	sky.set_daylight(day_night.get_daylight())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_view"):
		hud.toggle_water_view()
		get_viewport().set_input_as_handled()


# ---- Measuring ----

func _enter_live() -> void:
	mode = Mode.LIVE
	hud.set_progress(0, 0)
	hud.set_controls_enabled(true, true, true)
	hud.set_measuring(false, not baseline.is_empty())
	_set_speed(1)
	_update_status()


func _start_measure(target: Mode) -> void:
	if mode != Mode.LIVE or (target == Mode.MEASURE_COMPARISON and baseline.is_empty()):
		return
	_cancel_placement()
	hud.hide_report()
	mode = target
	_days_run = 0
	simulation.ResetSimulation()
	simulation.StartFastForward(settle_max_days * 24)
	hud.set_controls_enabled(false, false, false)
	hud.set_measuring(true, not baseline.is_empty())
	_update_status()


func _stop_measure() -> void:
	if mode == Mode.LIVE:
		return
	simulation.StopFastForward()
	_enter_live()
	hud.show_message("Measurement stopped. Nothing was recorded.")


func _finish_measure(settled: bool) -> void:
	simulation.StopFastForward()
	var finished := mode
	var measurement := _snapshot(settled)
	_enter_live()
	if finished == Mode.MEASURE_BASELINE:
		_set_baseline(measurement)
		hud.show_message("Baseline recorded. Change the season, weather or fountains, then press Compare with baseline.")
	else:
		last_report = {"baseline": baseline, "comparison": measurement}
		hud.set_has_report(true)
		_show_last_report()


func _snapshot(settled: bool) -> Dictionary:
	var day: Dictionary = simulation.GetLastDay()
	var totals: Dictionary = simulation.GetFountainTotals()
	var environment: Array = hud.get_environment()
	var layout := []
	for unit: Dictionary in simulation.GetFountains():
		layout.append([unit.pump_column, unit.sprayer_column, unit.lpm])
	var measurement := {
		"environment": environment,
		"environment_text": Hud.environment_text(environment),
		"fountain_count": totals.active,
		"total_lpm": totals.total_lpm,
		"power_kw": totals.power_kw,
		"kwh_per_day": day.get("energy_kwh", totals.power_kw * 24.0),
		"layout": layout,
		"days": _days_run,
		"settled": settled,
	}
	for key: String in DAY_KEYS:
		measurement[key] = day[key]
	measurement["fountain_text"] = Hud.fountain_summary(measurement)
	return measurement


func _set_baseline(measurement: Dictionary) -> void:
	baseline = measurement
	hud.set_baseline(baseline)
	hud.set_measuring(mode != Mode.LIVE, true)
	_update_status()


func _show_last_report() -> void:
	if not last_report.is_empty():
		hud.show_report(last_report.baseline, last_report.comparison, simulation.HypoxiaThreshold)


func _on_make_baseline() -> void:
	if last_report.is_empty():
		return
	_set_baseline(last_report.comparison)
	hud.show_message("The comparison run is now the baseline.")


func _update_status() -> void:
	match mode:
		Mode.MEASURE_BASELINE:
			hud.set_status("Measuring baseline", _measure_hint())
		Mode.MEASURE_COMPARISON:
			hud.set_status("Measuring comparison", _measure_hint())
		_:
			if baseline.is_empty():
				hud.set_status("Explore", "")
			else:
				hud.set_status("Explore", "Baseline: %s, %s. Change anything, then press Compare with baseline." % [
					baseline.environment_text, baseline.fountain_text.to_lower()])


func _measure_hint() -> String:
	return "Fast-forwarding from a fresh start until the daily mean DO settles (%d to %d days). Stop cancels." % [settle_min_days, settle_max_days]


# ---- Simulation events ----

func _on_ticks_advanced() -> void:
	var stats: Dictionary = simulation.GetStats()
	hud.update_time(stats.day, stats.hour)
	hud.update_stats(stats, simulation.GetLayerMeans())
	day_night.set_hour(stats.hour)


func _on_day_completed(_summary: Dictionary) -> void:
	if mode == Mode.LIVE:
		return
	_days_run += 1
	if _days_run >= settle_min_days and simulation.IsSteady(steady_tolerance):
		_finish_measure(true)


func _on_fast_forward_finished() -> void:
	if mode != Mode.LIVE:
		_finish_measure(false)


# ---- HUD events ----

func _set_speed(ticks_per_step: int) -> void:
	simulation.SetSpeed(ticks_per_step)
	hud.set_speed(ticks_per_step)


func _on_reset() -> void:
	if mode != Mode.LIVE:
		_stop_measure()
	simulation.ResetSimulation()


func _on_environment_changed(season: int, wind: int, rain: bool, bloom: bool) -> void:
	simulation.SetEnvironment(season, wind, rain, bloom)
	decor.set_wind(wind)
	sky.set_wind(wind)


func _on_lpm_changed(lpm: float) -> void:
	_lpm = lpm
	if selected_id >= 0:
		simulation.SetFountainLpm(selected_id, lpm)
		_refresh_fountains()


func _on_water_view_changed(nature: bool) -> void:
	if _water_view_tween:
		_water_view_tween.kill()
	var from: float = _water_view
	_water_view_tween = create_tween()
	_water_view_tween.tween_method(_set_water_view, from, 1.0 if nature else 0.0, 0.35)


func _set_water_view(value: float) -> void:
	_water_view = value
	RenderingServer.global_shader_parameter_set("water_view", value)


# ---- Fountain units ----

func _on_add_fountain() -> void:
	var was_adding := _adding
	_cancel_placement()
	if was_adding or simulation.GetFountainTotals().count >= max_units:
		return
	_adding = true
	placement.set_mode(PlacementTool.Mode.PUMP)


func _on_move(kind: PlacementTool.Mode) -> void:
	var toggling_off := not _adding and placement.mode == kind
	_cancel_placement()
	if toggling_off or selected_id < 0:
		return
	placement.set_mode(kind)


func _on_placed(kind: PlacementTool.Mode, column: Vector2i) -> void:
	if _adding:
		if kind == PlacementTool.Mode.PUMP:
			_adding_id = simulation.AddFountain()
			simulation.PlaceFountainPump(_adding_id, column.x, column.y)
			simulation.SetFountainLpm(_adding_id, _lpm)
			selected_id = _adding_id
			_refresh_fountains()
			placement.set_mode(PlacementTool.Mode.SPRAYER)
			return
		simulation.PlaceFountainSprayer(_adding_id, column.x, column.y)
		_adding = false
		_adding_id = -1
		hud.set_placement_mode(PlacementTool.Mode.NONE)
	elif selected_id >= 0:
		if kind == PlacementTool.Mode.PUMP:
			simulation.PlaceFountainPump(selected_id, column.x, column.y)
		else:
			simulation.PlaceFountainSprayer(selected_id, column.x, column.y)
	_refresh_fountains()


func _on_placement_cancelled(_kind: PlacementTool.Mode) -> void:
	if not _adding:
		return
	_adding = false
	if _adding_id >= 0:
		simulation.RemoveFountain(_adding_id)
		_adding_id = -1
		selected_id = _last_unit_id()
	hud.set_placement_mode(PlacementTool.Mode.NONE)
	_refresh_fountains()


func _on_placement_mode_changed(kind: PlacementTool.Mode) -> void:
	var id := _adding_id if _adding else selected_id
	hud.set_placement_mode(kind, _unit_number(id), _adding)


func _cancel_placement() -> void:
	var kind := placement.mode
	if kind == PlacementTool.Mode.NONE and not _adding:
		return
	placement.set_mode(PlacementTool.Mode.NONE)
	_on_placement_cancelled(kind)


func _on_remove_fountain() -> void:
	var id := selected_id
	_cancel_placement()
	var units: Array = simulation.GetFountains()
	var index := units.find_custom(func(unit: Dictionary) -> bool: return unit.id == id)
	if index < 0:
		return
	simulation.RemoveFountain(id)
	units.remove_at(index)
	selected_id = -1 if units.is_empty() else units[mini(index, units.size() - 1)].id
	_refresh_fountains()


func _on_clear_fountains() -> void:
	_cancel_placement()
	simulation.ClearFountains()
	selected_id = -1
	_refresh_fountains()


func _select(id: int) -> void:
	if mode != Mode.LIVE:
		return
	if id != selected_id or _adding:
		_cancel_placement()
	selected_id = id
	_refresh_fountains()


# Plain clicks on the water select the unit whose pump or sprayer is at (or next to) that column.
func _on_column_clicked(column: Vector2i) -> void:
	var best_id := -1
	var best := 2
	for unit: Dictionary in simulation.GetFountains():
		for key: String in ["pump_column", "sprayer_column"]:
			var at: Vector2i = unit[key]
			if at.x < 0:
				continue
			var distance := maxi(absi(at.x - column.x), absi(at.y - column.y))
			if distance < best:
				best = distance
				best_id = unit.id
	if best_id >= 0:
		_select(best_id)


# Placement rule: a column holds at most one pump or sprayer, except a unit's own parts.
func _is_column_free(_kind: PlacementTool.Mode, column: Vector2i) -> bool:
	var own := _adding_id if _adding else selected_id
	for unit: Dictionary in simulation.GetFountains():
		if unit.id != own and (unit.pump_column == column or unit.sprayer_column == column):
			return false
	return true


func _refresh_fountains() -> void:
	var units: Array = simulation.GetFountains()
	if not units.any(func(unit: Dictionary) -> bool: return unit.id == selected_id):
		selected_id = -1
	var surface_y: float = simulation.GetWaterSurfaceY()
	fountain_visuals.update_units(units, surface_y, selected_id)
	hud.update_fountains(units, selected_id, simulation.GetFountainTotals(), max_units)
	var avoid := decor.jetty_points().duplicate()
	for unit: Dictionary in units:
		for key: String in ["pump", "sprayer"]:
			if unit["has_" + key]:
				var at: Vector3 = unit[key + "_position"]
				avoid.append(Vector2(at.x, at.z))
	ducks.set_avoid(avoid)
	critters.set_avoid(avoid)


func _unit_number(id: int) -> int:
	var units: Array = simulation.GetFountains()
	for i in units.size():
		if units[i].id == id:
			return i + 1
	return units.size() + 1


func _last_unit_id() -> int:
	var units: Array = simulation.GetFountains()
	return -1 if units.is_empty() else units[-1].id


# On HiDPI screens the window opens at the design size in pixels, which looks tiny; grow it by
# the screen scale (stretch mode keeps the UI proportional) and keep it on screen.
func _fit_window_to_screen() -> void:
	var window := get_window()
	if DisplayServer.get_name() == "headless" or window.mode != Window.MODE_WINDOWED or Engine.is_embedded_in_editor():
		return
	var screen := window.current_screen
	var screen_scale := DisplayServer.screen_get_scale(screen)
	if screen_scale <= 1.0:
		return
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var target := Vector2(window.content_scale_size) * screen_scale
	target *= minf(1.0, minf(usable.size.x * 0.9 / target.x, usable.size.y * 0.9 / target.y))
	window.size = Vector2i(target)
	window.position = usable.position + (usable.size - window.size) / 2
