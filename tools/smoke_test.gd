extends SceneTree

## Headless smoke test of the full game flow (needs Godot .NET):
##   $GODOT4 --headless --path . --script res://tools/smoke_test.gd [-- 1000 2000 3000 PumpZoneLpmPerRadius=250]
## Runs the baseline, places a pump in the deepest column and a sprayer nearby,
## then evaluates each flow rate given on the command line and prints the results.
## Name=value arguments override SimParamsResource properties for calibration; lowercase
## options set the scenario: season=0..3 wind=0..2 rain=0/1 bloom=0/1 sprayer_distance=cells.

const MAX_FRAMES := 5000
const Main := preload("res://scripts/main.gd")
const PlacementTool := preload("res://scripts/placement_tool.gd")
const OPTIONS := ["season", "wind", "rain", "bloom", "sprayer_distance"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var flows := PackedFloat32Array()
	var options := {"season": 1, "wind": 0, "rain": 0, "bloom": 0, "sprayer_distance": 8}
	var params: Resource = main.get_node("Simulation").Params
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var parts := arg.split("=")
			if parts[0] in OPTIONS:
				options[parts[0]] = int(parts[1])
			else:
				params.set(parts[0], float(parts[1]))
				print("Override %s = %s" % [parts[0], params.get(parts[0])])
		else:
			flows.append(float(arg))
	if flows.is_empty():
		flows = PackedFloat32Array([1500.0, 3000.0])
	root.add_child(main)
	await process_frame
	var sim: Node = main.simulation
	if not sim.IsLoaded:
		_fail("simulation not loaded: %s" % sim.LoadError)
		return
	print("Water cells: %d, grid origin %s, size %s, surface y %.1f" % [sim.WaterCellCount, sim.GetGridOrigin(), sim.GetGridSize(), sim.GetWaterSurfaceY()])

	main._on_environment_changed(options.season, options.wind, options.rain == 1, options.bloom == 1)
	main._on_primary_action()
	if not await _wait_for_stage(main, Main.Stage.FOUNTAIN):
		return
	print("Baseline (season %d, wind %d, rain %d, bloom %d): mean %.2f mg/L, hypoxic %.1f%%" % [options.season, options.wind, options.rain, options.bloom, main.baseline_mean_do, main.baseline_hypoxic * 100.0])

	var pump := _deepest_column(sim)
	var sprayer := _column_near(sim, pump, options.sprayer_distance)
	_click_column(main, PlacementTool.Mode.PUMP, pump)
	_click_column(main, PlacementTool.Mode.SPRAYER, sprayer)
	var placed: Dictionary = sim.GetFountainInfo()
	_check(placed.has_pump and placed.has_sprayer, "placement by mouse click")
	main.slice.set_slice(true, pump.x, false)

	for lpm in flows:
		main.hud.set_lpm(lpm)
		main._on_lpm_changed(lpm)
		var info: Dictionary = sim.GetFountainInfo()
		main._on_primary_action()
		if not await _wait_for_stage(main, Main.Stage.RESULTS):
			return
		var stats: Dictionary = sim.GetStats()
		print("LPM %4d  pump %s sprayer %s  zone r %.1f  head %.2f m  %.2f kW  ->  24 h mean %.2f mg/L, hypoxic %.1f%%, streak %d, %s" % [
			lpm, pump, sprayer, info.pump_zone_radius, info.head_m, info.power_kw,
			main._last_day.get("mean_do", 0.0), main._last_day.get("hypoxic_fraction", 0.0) * 100.0,
			stats.pass_streak_days, "PASS" if stats.passed else "FAIL"])
		main._enter_fountain()

	main._enter_setup()
	print("Smoke test finished OK")
	quit(0)


func _wait_for_stage(main: Main, stage: int) -> bool:
	for i in MAX_FRAMES:
		if main.stage == stage:
			return true
		await process_frame
	_fail("timed out waiting for stage %d (at %d)" % [stage, main.stage])
	return false


func _deepest_column(sim: Node) -> Vector2i:
	var origin: Vector3i = sim.GetGridOrigin()
	var grid_size: Vector3i = sim.GetGridSize()
	var best := Vector2i(-1, -1)
	var best_y := INF
	for x in range(origin.x, origin.x + grid_size.x):
		for z in range(origin.z, origin.z + grid_size.z):
			if sim.IsWaterColumn(x, z):
				var bottom: Vector3 = sim.GetColumnBottomCenter(x, z)
				if bottom.y < best_y:
					best_y = bottom.y
					best = Vector2i(x, z)
	return best


func _column_near(sim: Node, from: Vector2i, distance: int) -> Vector2i:
	for d in range(distance, 0, -1):
		for offset in [Vector2i(d, 0), Vector2i(-d, 0), Vector2i(0, d), Vector2i(0, -d)]:
			var c: Vector2i = from + offset
			if sim.IsWaterColumn(c.x, c.y):
				return c
	return from


func _check(ok: bool, what: String) -> void:
	if not ok:
		push_error("Smoke test: %s failed" % what)


# Exercises the placement tool's ray cast by clicking the screen position of a column centre.
func _click_column(main: Main, mode: PlacementTool.Mode, column: Vector2i) -> void:
	main.placement.set_mode(mode)
	var surface_y: float = main.simulation.GetWaterSurfaceY()
	var camera: Camera3D = main.get_node("Camera")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(Vector3(column.x + 0.5, surface_y, column.y + 0.5))
	main.placement._unhandled_input(click)
	_check(main.placement.mode == PlacementTool.Mode.NONE, "click on column %s" % column)


func _fail(message: String) -> void:
	push_error("Smoke test FAILED: " + message)
	quit(1)
