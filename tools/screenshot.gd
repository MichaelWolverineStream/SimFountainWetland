extends SceneTree

## Renders the game and saves screenshots for visual checks (needs Godot .NET and a display):
##   $GODOT4 --path . --script res://tools/screenshot.gd -- /tmp/sfw
## Writes <prefix>_overview.png (fountain running) and <prefix>_slice.png (cross-section at the pump).

const Main := preload("res://scripts/main.gd")
const PlacementTool := preload("res://scripts/placement_tool.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://screenshot"
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var sim: Node = main.simulation

	main._on_primary_action()
	while main.stage != Main.Stage.FOUNTAIN:
		await process_frame

	var pump := Vector2i(54, 23)
	var sprayer := Vector2i(55, 23)
	if sim.PlacePump(pump.x, pump.y):
		main._on_placed(PlacementTool.Mode.PUMP, pump)
	if sim.PlaceSprayer(sprayer.x, sprayer.y):
		main._on_placed(PlacementTool.Mode.SPRAYER, sprayer)
	main.hud.set_lpm(2500.0)
	main._on_lpm_changed(2500.0)
	sim.StepTicks(36)
	await _frames(90)
	await _save(prefix + "_overview.png")

	main.hud.configure_slice(0, 95, pump.x)
	main.slice.set_slice(true, pump.x, false)
	var camera: Camera3D = main.get_node("Camera")
	camera.yaw_degrees = 90.0
	camera.pitch_degrees = 20.0
	camera.distance = 60.0
	camera.target = Vector3(pump.x, 8.0, pump.y + 4)
	camera._apply()
	await _frames(10)
	await _save(prefix + "_slice.png")
	quit(0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	print("Saved %s (%s)" % [path, error_string(error)])
