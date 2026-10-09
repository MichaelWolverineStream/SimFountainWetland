extends SceneTree

## Headless smoke test of the full game flow (needs Godot .NET):
##   $GODOT4 --headless --path . --script res://tools/smoke_test.gd [-- 1000 2000 units=3 PumpZoneLpmPerRadius=250]
## Measures a no-fountain baseline, click-places fountain units (pump in deep water, sprayer
## nearby), then compares each flow rate given on the command line against the baseline.
## Name=value arguments override SimParamsResource properties for calibration; lowercase
## options set the scenario: season=0..3 wind=0..2 rain=0/1 bloom=0/1 sprayer_distance=cells
## units=count compare_season=0..3 (adds an environment-only comparison at the end).

const MAX_FRAMES := 5000
const Main := preload("res://scripts/main.gd")
const PlacementTool := preload("res://scripts/placement_tool.gd")
const OPTIONS := ["season", "wind", "rain", "bloom", "sprayer_distance", "units", "compare_season"]
const PUMP_SPACING := 6

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var flows := PackedFloat32Array()
	var options := {"season": 1, "wind": 0, "rain": 0, "bloom": 0, "sprayer_distance": 8, "units": 1, "compare_season": -1}
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

	_check(main.mode == Main.Mode.LIVE and main.baseline.is_empty(), "starts live without a baseline")
	_check(main.hud._compare_button.disabled, "compare disabled without a baseline")
	main._on_environment_changed(options.season, options.wind, options.rain == 1, options.bloom == 1)
	main._start_measure(Main.Mode.MEASURE_BASELINE)
	_check(main.hud._stop_button.visible and not main.hud._baseline_button.visible, "stop shown while measuring")
	if not await _wait_live(main):
		return
	_check(not main.baseline.is_empty() and not main.hud._compare_button.disabled, "baseline recorded")
	print("Baseline (season %d, wind %d, rain %d, bloom %d): %s" % [options.season, options.wind, options.rain, options.bloom, _describe(main.baseline)])

	_camera_checks(main)
	_scene_checks(main)

	var pumps := _pump_columns(sim, options.units)
	var used: Array[Vector2i] = []
	for pump in pumps:
		used.append(pump)
	for pump in pumps:
		var sprayer := _column_near(sim, pump, options.sprayer_distance, used)
		used.append(sprayer)
		_add_unit(main, pump, sprayer)
	var totals: Dictionary = sim.GetFountainTotals()
	_check(totals.count == pumps.size() and totals.active == pumps.size(), "%d unit(s) placed by mouse click" % pumps.size())
	_check(main.fountain_visuals.get_unit_count() == pumps.size(), "one visual per unit")
	_placement_rule_checks(main, pumps[0])

	_click_select(main, pumps[0])
	var first_id: int = sim.GetFountains()[0].id
	_check(main.selected_id == first_id, "click on a pump selects its unit")
	main.slice.set_slice(true, pumps[0].x, false)

	for lpm in flows:
		for unit: Dictionary in sim.GetFountains():
			main._select(unit.id)
			main._on_lpm_changed(lpm)
		if not await _compare(main, "LPM %4d x %d unit(s)" % [lpm, pumps.size()]):
			return

	if options.compare_season >= 0:
		main._on_make_baseline()
		_check(main.baseline == main.last_report.comparison, "make this the new baseline")
		var environment: Array = main.hud.get_environment()
		main._on_environment_changed(options.compare_season, environment[1], environment[2], environment[3])
		main.hud._season.select(options.compare_season)
		if not await _compare(main, "Season %d -> %d, same fountains" % [environment[0], options.compare_season]):
			return
		_check(main.hud._report._what_changed(main.last_report.baseline, main.last_report.comparison).contains("season"),
				"report names the season change")

	await _stop_check(main)
	_report_checks(main)

	main._select(first_id)
	main._on_remove_fountain()
	_check(sim.GetFountainTotals().count == pumps.size() - 1, "remove selected unit")
	main._on_clear_fountains()
	_check(sim.GetFountainTotals().count == 0 and main.fountain_visuals.get_unit_count() == 0, "clear all units")

	if _failures > 0:
		_fail("%d check(s) failed" % _failures)
		return
	print("Smoke test finished OK")
	quit(0)


func _compare(main: Main, label: String) -> bool:
	main._start_measure(Main.Mode.MEASURE_COMPARISON)
	if not await _wait_live(main):
		return false
	await process_frame
	var report: Dictionary = main.last_report
	_check(not report.is_empty() and main.hud.is_report_open(), "report opens after a comparison")
	var b: Dictionary = report.baseline
	var c: Dictionary = report.comparison
	print("%s: %s  vs baseline: mean %+.2f mg/L, hypoxic %+.1f pts" % [label, _describe(c),
			c.mean_do - b.mean_do, (c.hypoxic_fraction - b.hypoxic_fraction) * 100.0])
	main.hud.hide_report()
	return true


func _describe(m: Dictionary) -> String:
	return "mean %.2f mg/L, bottom %.2f, hypoxic %.1f%%, %.1f kWh/day, %d days%s" % [m.mean_do, m.bottom_mean_do,
			m.hypoxic_fraction * 100.0, m.kwh_per_day, m.days, "" if m.settled else " (not settled)"]


func _wait_live(main: Main) -> bool:
	for i in MAX_FRAMES:
		if main.mode == Main.Mode.LIVE:
			return true
		await process_frame
	_fail("timed out waiting for the measurement (mode %d)" % main.mode)
	return false


# Deep columns, at least PUMP_SPACING apart so units don't share a pump zone.
func _pump_columns(sim: Node, count: int) -> Array[Vector2i]:
	var origin: Vector3i = sim.GetGridOrigin()
	var grid_size: Vector3i = sim.GetGridSize()
	var columns := []
	for x in range(origin.x, origin.x + grid_size.x):
		for z in range(origin.z, origin.z + grid_size.z):
			if sim.IsWaterColumn(x, z):
				columns.append([sim.GetColumnBottomCenter(x, z).y, Vector2i(x, z)])
	columns.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var picked: Array[Vector2i] = []
	for entry: Array in columns:
		var column: Vector2i = entry[1]
		if picked.all(func(p: Vector2i) -> bool: return maxi(absi(p.x - column.x), absi(p.y - column.y)) >= PUMP_SPACING):
			picked.append(column)
			if picked.size() == count:
				break
	return picked


func _column_near(sim: Node, from: Vector2i, distance: int, used: Array[Vector2i]) -> Vector2i:
	for d in range(distance, 0, -1):
		for offset in [Vector2i(d, 0), Vector2i(-d, 0), Vector2i(0, d), Vector2i(0, -d)]:
			var c: Vector2i = from + offset
			if sim.IsWaterColumn(c.x, c.y) and c not in used:
				return c
	return from


func _add_unit(main: Main, pump: Vector2i, sprayer: Vector2i) -> void:
	var count: int = main.simulation.GetFountainTotals().count
	main._on_add_fountain()
	_check(main.placement.mode == PlacementTool.Mode.PUMP, "add starts pump placement")
	_click(main, pump)
	_check(main.placement.mode == PlacementTool.Mode.SPRAYER, "pump click moves on to the sprayer")
	_click(main, sprayer)
	_check(main.placement.mode == PlacementTool.Mode.NONE and not main._adding, "sprayer click finishes the unit")
	_check(main.simulation.GetFountainTotals().count == count + 1, "unit added at %s / %s" % [pump, sprayer])


# Occupied columns are rejected, Esc mid-add removes the half-built unit, modifier clicks don't place.
func _placement_rule_checks(main: Main, occupied: Vector2i) -> void:
	var sim: Node = main.simulation
	var count: int = sim.GetFountainTotals().count
	main._on_add_fountain()
	if count >= main.max_units:
		_check(main.placement.mode == PlacementTool.Mode.NONE, "add blocked at the unit limit")
		return
	_click(main, occupied)
	_check(main.placement.mode == PlacementTool.Mode.PUMP, "occupied column rejected")
	var alt_click := _click_event(main, occupied + Vector2i(0, 3))
	alt_click.alt_pressed = true
	main.placement._unhandled_input(alt_click)
	_check(main.placement.mode == PlacementTool.Mode.PUMP and sim.GetFountainTotals().count == count, "alt-click does not place")
	var free := _free_column(main)
	_click(main, free)
	_check(sim.GetFountainTotals().count == count + 1, "pump placed mid-add")
	var escape := InputEventAction.new()
	escape.action = &"cancel"
	escape.pressed = true
	main.placement._unhandled_input(escape)
	_check(sim.GetFountainTotals().count == count and not main._adding, "Esc mid-add removes the unit")


func _free_column(main: Main) -> Vector2i:
	var sim: Node = main.simulation
	var origin: Vector3i = sim.GetGridOrigin()
	var grid_size: Vector3i = sim.GetGridSize()
	for x in range(origin.x, origin.x + grid_size.x):
		for z in range(origin.z, origin.z + grid_size.z):
			if sim.IsWaterColumn(x, z) and main._is_column_free(PlacementTool.Mode.PUMP, Vector2i(x, z)):
				return Vector2i(x, z)
	return Vector2i(-1, -1)


func _stop_check(main: Main) -> void:
	main._start_measure(Main.Mode.MEASURE_COMPARISON)
	await process_frame
	main._stop_measure()
	_check(main.mode == Main.Mode.LIVE and not main.hud._stop_button.visible and not main.hud._speed_buttons[1].disabled,
			"stop cancels a measurement")


func _report_checks(main: Main) -> void:
	main._show_last_report()
	_check(main.hud.is_report_open(), "show last report")
	_check(main.hud._report._content.get_child_count() > 6, "report has content")
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	main.hud._report._input(escape)
	_check(not main.hud.is_report_open(), "Esc closes the report")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("Smoke test: %s failed" % what)


# Wheel, trackpad gestures and modifier drags reach the camera.
func _camera_checks(main: Main) -> void:
	var camera: Node = main.get_node("Camera")
	var start: float = camera.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	camera._unhandled_input(wheel)
	_check(camera.distance < start, "wheel zoom in")

	var before: float = camera.distance
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.5
	camera._unhandled_input(pinch)
	_check(camera.distance < before, "pinch zoom in")

	before = camera.distance
	var scroll := InputEventPanGesture.new()
	scroll.delta = Vector2(0.0, 3.0)
	camera._unhandled_input(scroll)
	_check(camera.distance > before, "two-finger scroll zoom out")

	var yaw: float = camera.yaw_degrees
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.alt_pressed = true
	camera._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40.0, 0.0)
	camera._unhandled_input(motion)
	_check(not is_equal_approx(camera.yaw_degrees, yaw), "alt-drag orbit")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	camera._unhandled_input(release)

	camera.reset_view()
	_check(is_equal_approx(camera.distance, start), "reset view")


# Props, critters, sky, ducks, night lights and the water view toggle.
func _scene_checks(main: Main) -> void:
	_check(main.decor.get_child_count() > 3, "decor scattered (%d nodes)" % main.decor.get_child_count())
	var props := PackedStringArray()
	for prop in ["Wheat", "Fence", "Bench", "LampPost", "Jetty", "Foam", "Mushrooms", "HayBale"]:
		if main.decor.get_node_or_null(prop) == null:
			props.append(prop)
	_check(props.is_empty(), "new props present%s" % ("" if props.is_empty() else " (missing %s)" % ", ".join(props)))
	_check(not main.decor.jetty_points().is_empty(), "jetty placed")
	_check(main.ducks.get_child_count() > 1, "ducks spawned")
	var counts: Dictionary = main.critters.get_counts()
	print("Critters: %s" % counts)
	_check(counts.herons > 0 and counts.frogs > 0 and counts.turtles > 0 and counts.fish > 0, "critters spawned")
	_check(counts.butterflies > 0 and counts.dragonflies > 0, "butterflies and dragonflies spawned")
	_check(main.sky.get_cloud_count() > 0, "clouds spawned")
	main.day_night.set_hour(22, true)
	var lamps: Node3D = main.decor.get_node_or_null("LampBulbs")
	_check(main.day_night.is_night() and main.decor._fireflies.emitting, "night fireflies")
	_check(lamps != null and lamps.visible, "lamps glow at night")
	_check(main.sky._stars.visible and not main.critters._butterflies.visible, "stars out, butterflies away at night")
	main.day_night.set_hour(12, true)
	_check(not main.day_night.is_night() and not main.decor._fireflies.emitting, "day without fireflies")
	_check(not lamps.visible and not main.sky._stars.visible and main.critters._butterflies.visible, "day: lamps off, no stars, butterflies out")
	main.hud.toggle_water_view()
	_check(main.hud.is_nature_view(), "nature view toggle")
	main.hud.toggle_water_view()
	_check(not main.hud.is_nature_view(), "oxygen view toggle")


func _click_event(main: Main, column: Vector2i) -> InputEventMouseButton:
	var surface_y: float = main.simulation.GetWaterSurfaceY()
	var camera: Camera3D = main.get_node("Camera")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(Vector3(column.x + 0.5, surface_y, column.y + 0.5))
	return click


# Exercises the placement tool's ray cast by clicking the screen position of a column centre.
func _click(main: Main, column: Vector2i) -> void:
	main.placement._unhandled_input(_click_event(main, column))


func _click_select(main: Main, column: Vector2i) -> void:
	main._select(-1)
	_click(main, column)


func _fail(message: String) -> void:
	push_error("Smoke test FAILED: " + message)
	quit(1)
