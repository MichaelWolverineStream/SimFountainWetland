extends Node3D

## Game flow: SETUP -> BASELINE_RUN -> FOUNTAIN -> EVALUATING -> RESULTS.
## The baseline is the steady no-fountain state; fountain designs are judged against it.

enum Stage { SETUP, BASELINE_RUN, FOUNTAIN, EVALUATING, RESULTS }

const PlacementTool := preload("res://scripts/placement_tool.gd")
const Hud := preload("res://scripts/hud.gd")
const FountainVisuals := preload("res://scripts/fountain_visuals.gd")
const SliceController := preload("res://scripts/slice_controller.gd")

@export var baseline_min_days := 3
@export var baseline_max_days := 14
@export var steady_tolerance := 0.01
@export var evaluate_max_days := 10

var stage := Stage.SETUP
var baseline_mean_do := 0.0
var baseline_hypoxic := 0.0
var baseline_stale := false
var best_kwh_per_day := INF

var _days_run := 0
var _last_day := {}
# Remembered so a baseline re-run can remove the fountain and restore it afterwards.
var _pump_column := Vector2i(-1, -1)
var _sprayer_column := Vector2i(-1, -1)
var _lpm := 0.0

@onready var simulation: Node = $Simulation
@onready var hud: Hud = $HUD
@onready var placement: PlacementTool = $PlacementTool
@onready var fountain_visuals: FountainVisuals = $FountainVisuals
@onready var slice: SliceController = $SliceController
@onready var sun: DirectionalLight3D = $Sun


func _ready() -> void:
	if not simulation.IsLoaded:
		hud.set_stage("Error", "The simulation could not be built from the level.", "", false)
		hud.set_controls_enabled(false, false, false)
		hud.show_message("Simulation failed to load: %s" % simulation.LoadError, true)
		return

	simulation.connect("TicksAdvanced", _on_ticks_advanced)
	simulation.connect("DayCompleted", _on_day_completed)
	simulation.connect("FastForwardProgress", hud.set_progress)
	simulation.connect("FastForwardFinished", _on_fast_forward_finished)

	hud.primary_action_pressed.connect(_on_primary_action)
	hud.speed_selected.connect(_set_speed)
	hud.reset_pressed.connect(_enter_setup)
	hud.environment_changed.connect(_on_environment_changed)
	hud.place_pump_pressed.connect(placement.set_mode.bind(PlacementTool.Mode.PUMP))
	hud.place_sprayer_pressed.connect(placement.set_mode.bind(PlacementTool.Mode.SPRAYER))
	hud.clear_fountain_pressed.connect(_on_clear_fountain)
	hud.lpm_changed.connect(_on_lpm_changed)
	hud.slice_changed.connect(slice.set_slice)
	hud.keep_tuning_pressed.connect(_enter_fountain)
	hud.new_scenario_pressed.connect(_enter_setup)
	placement.placed.connect(_on_placed)
	placement.mode_changed.connect(hud.set_placement_mode)

	var origin: Vector3i = simulation.GetGridOrigin()
	var grid_size: Vector3i = simulation.GetGridSize()
	slice.configure(origin, grid_size)
	hud.configure_slice(origin.x, origin.x + grid_size.x - 1, slice.cell_x)
	hud.set_max_lpm(simulation.MaxLpm)
	hud.set_targets(simulation.TargetMeanDo, simulation.MaxHypoxicFraction, simulation.RequiredPassDays)
	var environment: Array = hud.get_environment()
	simulation.SetEnvironment(environment[0], environment[1], environment[2], environment[3])
	_enter_setup()


# ---- Stages ----

func _enter_setup() -> void:
	stage = Stage.SETUP
	placement.set_mode(PlacementTool.Mode.NONE)
	_pump_column = Vector2i(-1, -1)
	_sprayer_column = Vector2i(-1, -1)
	_lpm = 0.0
	hud.set_lpm(0.0)
	simulation.ClearFountain()
	simulation.SetLpm(0.0)
	simulation.ResetSimulation()
	baseline_stale = false
	best_kwh_per_day = INF
	hud.hide_results()
	hud.set_progress(0, 0)
	hud.set_stage("1. Setup", "Choose the conditions, then measure the basin without a fountain.", "Run baseline", true)
	hud.set_controls_enabled(true, false, true)
	_set_speed(1)
	_refresh_fountain()


func _start_baseline() -> void:
	stage = Stage.BASELINE_RUN
	placement.set_mode(PlacementTool.Mode.NONE)
	simulation.ClearFountain()
	simulation.ResetSimulation()
	_days_run = 0
	_last_day = {}
	simulation.StartFastForward(baseline_max_days * 24)
	hud.set_stage("2. Baseline", "Fast-forwarding without a fountain until the daily mean DO settles (max %d days)." % baseline_max_days, "Stop", true)
	hud.set_controls_enabled(false, false, false)
	_refresh_fountain()


func _finish_baseline() -> void:
	simulation.StopFastForward()
	var stats: Dictionary = simulation.GetStats()
	baseline_mean_do = _last_day.get("mean_do", stats.rolling_mean_do)
	baseline_hypoxic = _last_day.get("hypoxic_fraction", stats.rolling_hypoxic_fraction)
	baseline_stale = false
	_enter_fountain()


func _enter_fountain() -> void:
	stage = Stage.FOUNTAIN
	simulation.StopFastForward()
	hud.hide_results()
	hud.set_progress(0, 0)
	_restore_fountain()
	simulation.ResetScoring()
	hud.set_controls_enabled(true, true, true)
	_set_speed(1)
	_update_fountain_stage()


func _update_fountain_stage() -> void:
	if stage != Stage.FOUNTAIN:
		return
	var hint := "Baseline: %.2f mg/L mean, %.0f%% hypoxic. Place a pump and sprayer, set the flow, then evaluate." % [baseline_mean_do, baseline_hypoxic * 100.0]
	if baseline_stale:
		hud.set_stage("3. Fountain", "Conditions changed since the baseline was measured. Re-measure it before evaluating.", "Re-measure baseline", true)
	else:
		# Evaluating without a fountain is allowed: some conditions pass with 0 kWh/day.
		hud.set_stage("3. Fountain", hint, "Evaluate", true)


func _start_evaluation() -> void:
	stage = Stage.EVALUATING
	placement.set_mode(PlacementTool.Mode.NONE)
	simulation.ResetScoring()
	_days_run = 0
	_last_day = {}
	simulation.StartFastForward(evaluate_max_days * 24)
	hud.set_stage("4. Evaluating", "Fast-forwarding until the target holds for %d days (max %d days)." % [simulation.RequiredPassDays, evaluate_max_days], "Stop", true)
	hud.set_controls_enabled(false, false, false)


func _show_results() -> void:
	stage = Stage.RESULTS
	simulation.StopFastForward()
	hud.set_progress(0, 0)
	var stats: Dictionary = simulation.GetStats()
	var info: Dictionary = simulation.GetFountainInfo()
	var mean_do: float = _last_day.get("mean_do", stats.rolling_mean_do)
	var hypoxic: float = _last_day.get("hypoxic_fraction", stats.rolling_hypoxic_fraction)
	var kwh_per_day: float = _last_day.get("energy_kwh", info.power_kw * 24.0)
	var passed: bool = stats.passed
	if passed and not baseline_stale:
		best_kwh_per_day = minf(best_kwh_per_day, kwh_per_day)
	hud.show_results({
		"baseline_mean_do": baseline_mean_do,
		"baseline_hypoxic": baseline_hypoxic,
		"mean_do": mean_do,
		"hypoxic": hypoxic,
		"kwh_per_day": kwh_per_day,
		"gain_per_kwh": (mean_do - baseline_mean_do) / kwh_per_day if kwh_per_day > 0.0 else 0.0,
		"passed": passed,
		"streak": stats.pass_streak_days,
		"required_days": simulation.RequiredPassDays,
		"best_kwh_per_day": best_kwh_per_day,
		"stale": baseline_stale,
	})
	hud.set_stage("5. Results", "Keep tuning to lower the energy use, or start a new scenario.", "", false)
	hud.set_controls_enabled(false, false, true)
	_set_speed(1)


# ---- Simulation events ----

func _on_ticks_advanced() -> void:
	var stats: Dictionary = simulation.GetStats()
	hud.update_time(stats.day, stats.hour)
	hud.update_stats(stats, simulation.GetLayerMeans())
	_update_sun(stats.hour)


func _on_day_completed(result: Dictionary) -> void:
	_last_day = result
	_days_run += 1
	match stage:
		Stage.BASELINE_RUN:
			if _days_run >= baseline_min_days and simulation.IsSteady(steady_tolerance):
				_finish_baseline()
		Stage.EVALUATING:
			if simulation.GetStats().passed:
				_show_results()


func _on_fast_forward_finished() -> void:
	match stage:
		Stage.BASELINE_RUN:
			_finish_baseline()
		Stage.EVALUATING:
			_show_results()


# ---- HUD events ----

func _on_primary_action() -> void:
	match stage:
		Stage.SETUP:
			_start_baseline()
		Stage.BASELINE_RUN:
			_finish_baseline()
		Stage.FOUNTAIN:
			if baseline_stale:
				_start_baseline()
			else:
				_start_evaluation()
		Stage.EVALUATING:
			_show_results()


func _set_speed(ticks_per_step: int) -> void:
	simulation.SetSpeed(ticks_per_step)
	hud.set_speed(ticks_per_step)


func _on_environment_changed(season: int, wind: int, rain: bool, bloom: bool) -> void:
	simulation.SetEnvironment(season, wind, rain, bloom)
	if stage == Stage.FOUNTAIN:
		baseline_stale = true
		simulation.ResetScoring()
		_update_fountain_stage()


func _on_placed(kind: PlacementTool.Mode, column: Vector2i) -> void:
	if kind == PlacementTool.Mode.PUMP:
		_pump_column = column
	else:
		_sprayer_column = column
	_on_fountain_changed()


func _on_clear_fountain() -> void:
	placement.set_mode(PlacementTool.Mode.NONE)
	_pump_column = Vector2i(-1, -1)
	_sprayer_column = Vector2i(-1, -1)
	simulation.ClearFountain()
	_on_fountain_changed()


func _on_lpm_changed(lpm: float) -> void:
	_lpm = lpm
	simulation.SetLpm(lpm)
	_on_fountain_changed()


func _on_fountain_changed() -> void:
	simulation.ResetScoring()
	_refresh_fountain()
	_update_fountain_stage()


# ---- Helpers ----

func _restore_fountain() -> void:
	simulation.ClearFountain()
	if _pump_column.x >= 0:
		simulation.PlacePump(_pump_column.x, _pump_column.y)
	if _sprayer_column.x >= 0:
		simulation.PlaceSprayer(_sprayer_column.x, _sprayer_column.y)
	simulation.SetLpm(_lpm)
	_refresh_fountain()


func _refresh_fountain() -> void:
	var info: Dictionary = simulation.GetFountainInfo()
	info["surface_y"] = simulation.GetWaterSurfaceY()
	fountain_visuals.update_from(info)
	hud.update_fountain(info)


# Sun rises at 06:00, peaks at noon and sets at 18:00; at night it stays dim and low.
func _update_sun(hour: int) -> void:
	var day_phase := (hour + 0.5 - 6.0) / 12.0
	var elevation := sin(day_phase * PI) * 65.0
	sun.light_energy = clampf(elevation / 30.0, 0.08, 1.0)
	sun.rotation_degrees = Vector3(-maxf(elevation, 12.0), lerpf(100.0, -100.0, clampf(day_phase, 0.0, 1.0)), 0.0)
