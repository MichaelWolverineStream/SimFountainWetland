extends SceneTree

## Renders the game and saves screenshots for visual checks (needs Godot .NET and a display):
##   $GODOT4 --path . --script res://tools/screenshot.gd -- /tmp/sfw
## Writes <prefix>_report.png (comparison report: no fountains vs three), _overview.png
## (Nature view, fountains running, 13:00), _oxygen.png (Oxygen view), _closeup.png, _jetty.png, _field.png,
## _pond.png and _heron.png (props and critters), _night.png (22:00) and _slice.png (cross-section
## at the first pump).

const Main := preload("res://scripts/main.gd")
const PlacementTool := preload("res://scripts/placement_tool.gd")
const UNITS := [[Vector2i(54, 23), Vector2i(55, 23)], [Vector2i(40, 34), Vector2i(42, 34)], [Vector2i(64, 38), Vector2i(62, 38)]]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://screenshot"
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var sim: Node = main.simulation

	main._start_measure(Main.Mode.MEASURE_BASELINE)
	await _wait_live(main)

	main.hud.set_lpm(2000.0)
	main._on_lpm_changed(2000.0)
	for unit: Array in UNITS:
		var pump: Vector2i = _water_near(sim, unit[0])
		var sprayer: Vector2i = _water_near(sim, unit[1])
		main._on_add_fountain()
		_place(main, PlacementTool.Mode.PUMP, pump)
		_place(main, PlacementTool.Mode.SPRAYER, sprayer)
	var first: Dictionary = sim.GetFountains()[0]
	var pump_column: Vector2i = first.pump_column

	main._start_measure(Main.Mode.MEASURE_COMPARISON)
	await _wait_live(main)
	await _frames(40)
	await _save(prefix + "_report.png")
	main.hud.hide_report()

	main._select(first.id)
	# Run a day and a half, ending at 13:00, then pause so the light stays put.
	var hour: int = sim.GetStats().hour
	sim.StepTicks(36 + posmod(13 - (hour + 36), 24))
	main._set_speed(0)
	main.day_night.set_hour(sim.GetStats().hour, true)
	await _frames(90)
	await _save(prefix + "_overview.png")

	main.hud.toggle_water_view()
	await _frames(40)
	await _save(prefix + "_oxygen.png")
	main.hud.toggle_water_view()
	await _frames(20)

	var camera: Camera3D = main.get_node("Camera")
	_aim(camera, -35.0, 32.0, 34.0, Vector3(pump_column.x - 4, 12.0, pump_column.y + 6))
	await _frames(20)
	await _save(prefix + "_closeup.png")

	var jetty: Array = main.decor.get_spots("jetty_end")
	if not jetty.is_empty():
		_aim(camera, 30.0, 30.0, 14.0, jetty[0])
		await _frames(20)
		await _save(prefix + "_jetty.png")

	var fences: Array = main.decor._batches.get("fence", [[]])[0]
	if not fences.is_empty():
		var fence: Transform3D = fences[floori(fences.size() / 3.0)]
		_aim(camera, -20.0, 30.0, 14.0, fence.origin)
		await _frames(20)
		await _save(prefix + "_field.png")

	if not main.critters._frogs.is_empty():
		var frog: Node3D = main.critters._frogs[0].node
		_aim(camera, 15.0, 35.0, 8.0, frog.position)
		await _frames(20)
		await _save(prefix + "_pond.png")

	if not main.critters._herons.is_empty():
		var heron: Node3D = main.critters._herons[0].node
		_aim(camera, heron.rotation_degrees.y + 140.0, 18.0, 8.0, heron.position + Vector3(0.0, 0.6, 0.0))
		await _frames(20)
		await _save(prefix + "_heron.png")

	camera.reset_view()
	main.day_night.set_hour(22, true)
	await _frames(240)
	await _save(prefix + "_night.png")

	main.hud.toggle_water_view()
	main.day_night.set_hour(13, true)
	main.hud.configure_slice(0, 95, pump_column.x)
	main.slice.set_slice(true, pump_column.x, false)
	main.fountain_visuals.set_slice(true, pump_column.x, false)
	_aim(camera, 90.0, 20.0, 60.0, Vector3(pump_column.x, 8.0, pump_column.y + 4))
	await _frames(40)
	await _save(prefix + "_slice.png")
	quit(0)


func _place(main: Main, kind: PlacementTool.Mode, column: Vector2i) -> void:
	main.placement.set_mode(PlacementTool.Mode.NONE)
	main._on_placed(kind, column)


# Nearest water column to the wanted one, so the shots survive small level edits.
func _water_near(sim: Node, wanted: Vector2i) -> Vector2i:
	for radius in 12:
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := wanted + Vector2i(dx, dz)
				if sim.IsWaterColumn(c.x, c.y):
					return c
	return wanted


func _aim(camera: Camera3D, yaw: float, pitch: float, distance: float, target: Vector3) -> void:
	camera.yaw_degrees = yaw
	camera.pitch_degrees = pitch
	camera.distance = distance
	camera.target = target
	camera._apply()


func _wait_live(main: Main) -> void:
	while main.mode != Main.Mode.LIVE:
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	print("Saved %s (%s)" % [path, error_string(error)])
