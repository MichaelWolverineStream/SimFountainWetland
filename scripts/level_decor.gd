extends Node3D

## Scatters props over the level at start-up: trees, grass tufts, flowers, reeds, rocks, lily pads,
## wheat rows, hay bales, fences, logs, mushrooms, berry shrubs, pebbles, benches, lamp posts, a
## signpost and a jetty, plus shoreline foam, fireflies and lamp glow at night. Props stay out of
## the GridMap because the voxelizer treats every GridMap cell as solid. Lily pads and foam on the
## simulated water only show in the Nature water view.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const SIDES := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const TRUNK := Color(0.50, 0.33, 0.20)
const WOOD := Color(0.72, 0.53, 0.36)
const DARK_WOOD := Color(0.46, 0.32, 0.21)
const IRON := Color(0.22, 0.27, 0.27)
const TREE_GREENS := [Color(0.42, 0.74, 0.30), Color(0.50, 0.80, 0.33), Color(0.36, 0.66, 0.28)]
const BLOSSOM := Color(1.0, 0.72, 0.82)
const PINE_GREENS := [Color(0.24, 0.54, 0.32), Color(0.20, 0.47, 0.30)]
const FLOWER_COLORS := [Color(1.0, 0.55, 0.75), Color(1.0, 0.86, 0.30), Color(1.0, 1.0, 1.0), Color(0.74, 0.60, 1.0), Color(1.0, 0.45, 0.42)]
const LAMP_LIGHT := Color(1.0, 0.78, 0.45)
const LAMP_HEIGHT := 1.62
const JETTY_LENGTH := 3.3
const WIND_SWAY := [1.0, 1.8, 2.8]

@export var level: Node3D
@export var simulation: Node
@export var random_seed := 7
@export var tree_spacing := 2.2

var _rng := RandomNumberGenerator.new()
var _fireflies: GPUParticles3D
var _night_lights: Array[Node3D] = []
var _batches := {}  # prop name -> [transforms, tints]
var _sway := {}  # ShaderMaterial -> sway in calm wind
var _spots := {}  # critter spot name -> Array[Vector3]
var _trees: Array[Vector2] = []
var _benches: Array[Vector2] = []
var _lamps: Array[Vector2] = []
var _lamp_bulbs := PackedVector3Array()
var _jetty_options: Array = []  # [column, direction, top, on_path]
var _jetty_points := PackedVector2Array()
var _signpost := false


func _ready() -> void:
	if level == null or simulation == null or not simulation.IsLoaded:
		return
	_rng.seed = random_seed
	_scatter()
	_place_jetty()
	_build()
	_build_lamp_glow()
	_fireflies = _make_fireflies()
	add_child(_fireflies)


func set_night(on: bool) -> void:
	if _fireflies:
		_fireflies.emitting = on
	for light in _night_lights:
		light.visible = on


## 0 night .. 1 day: fireflies still alive after dawn (or a jump in time) fade out.
func set_daylight(daylight: float) -> void:
	if _fireflies:
		var shown := 1.0 - smoothstep(0.25, 0.6, daylight)
		((_fireflies.draw_pass_1 as QuadMesh).material as ShaderMaterial).set_shader_parameter("color", Color(0.85, 1.0, 0.45, shown))
		_fireflies.visible = shown > 0.0


## 0 calm, 1 breezy, 2 windy: trees, grass and reeds sway more.
func set_wind(wind: int) -> void:
	var factor: float = WIND_SWAY[clampi(wind, 0, WIND_SWAY.size() - 1)]
	for material: ShaderMaterial in _sway:
		material.set_shader_parameter("sway", _sway[material] * factor)
		material.set_shader_parameter("sway_speed", 1.6 + 0.6 * wind)


## Points on the water the ducks should steer around (the jetty).
func jetty_points() -> PackedVector2Array:
	return _jetty_points


## Spots for critters: "lily_pad", "shore_rock", "shallows", "flower", "reeds", "jetty_end".
func get_spots(spot_name: String) -> Array:
	return _spots.get(spot_name, [])


# ---- Placement ----

func _scatter() -> void:
	var grid: GridMap = level.get_node("GridMap")
	var lib := grid.mesh_library
	var origin: Vector3i = simulation.GetGridOrigin()
	var size: Vector3i = simulation.GetGridSize()
	var surface_y: float = simulation.GetWaterSurfaceY()

	# Top tile name and surface height per column.
	var kinds := {}
	var tops := {}
	for z in range(origin.z, origin.z + size.z):
		for x in range(origin.x, origin.x + size.x):
			var column := Vector2i(x, z)
			if simulation.IsWaterColumn(x, z):
				kinds[column] = "Water"
				continue
			for y in range(origin.y + size.y - 1, origin.y - 1, -1):
				var item := grid.get_cell_item(Vector3i(x, y, z))
				if item != GridMap.INVALID_CELL_ITEM:
					kinds[column] = lib.get_item_name(item)
					tops[column] = grid.to_global(grid.map_to_local(Vector3i(x, y, z))).y + 0.5
					break

	# Steps from each near-shore water column to the land (1 = touching), up to 3.
	var shore_steps := {}
	var frontier: Array[Vector2i] = []
	for column: Vector2i in kinds:
		if kinds[column] == "Water" and _touches(kinds, column, false):
			shore_steps[column] = 1
			frontier.append(column)
	for step in range(2, 4):
		var next: Array[Vector2i] = []
		for column in frontier:
			for offset: Vector2i in NEIGHBOURS:
				var other := column + offset
				if kinds.get(other, "") == "Water" and not shore_steps.has(other):
					shore_steps[other] = step
					next.append(other)
		frontier = next

	for column: Vector2i in kinds:
		var kind: String = kinds[column]
		var center := Vector3(column.x + 0.5, 0.0, column.y + 0.5)
		if kind == "Water":
			_scatter_water(column, center, shore_steps.get(column, 99), surface_y, kinds)
		elif tops.has(column):
			_scatter_land(kind, column, center, tops[column], _touches(kinds, column, true), kinds)


func _scatter_water(column: Vector2i, center: Vector3, steps: int, surface_y: float, kinds: Dictionary) -> void:
	if steps > 3:
		return
	if steps == 1:
		for side: Vector2i in SIDES:
			if kinds.get(column + side, "Water") != "Water":
				var edge := center + Vector3(side.x, 0.0, side.y) * 0.4
				edge.y = surface_y + 0.03
				var turn := Basis(Vector3.UP, PI * 0.5 if side.x != 0 else 0.0)
				_add("foam", Transform3D(turn * Basis.from_scale(Vector3(_rng.randf_range(0.9, 1.15), 1.0, 1.0)), edge), Color.WHITE)
	var depth: float = simulation.GetColumnTopCenter(column.x, column.y).y - simulation.GetColumnBottomCenter(column.x, column.y).y + 1.0
	if steps == 1 and depth <= 3.0:
		_mark("shallows", Vector3(center.x, surface_y, center.z))
		if _chance(0.3):
			var xform := _spot(center, surface_y - 0.4)
			_add("reeds", xform, _tint(0.1))
			_mark("reeds", xform.origin + Vector3(0.0, 0.4, 0.0))
			return
	if _chance(0.1):
		_add("lily_flower" if _chance(0.3) else "lily", _spot(center, surface_y + 0.02, 0.3), _tint(0.1))


func _scatter_land(kind: String, column: Vector2i, center: Vector3, top: float, shore: bool, kinds: Dictionary) -> void:
	match kind:
		"Pond":
			if _chance(0.3):
				var xform := _spot(center, top + 0.02, 0.3)
				_add("pond_lily_flower" if _chance(0.35) else "pond_lily", xform, _tint(0.1))
				_mark("lily_pad", xform.origin + Vector3(0.0, 0.02, 0.0))
		"Grass", "Meadow", "Island":
			var tree_chance: float = {"Grass": 0.025, "Meadow": 0.01, "Island": 0.10}[kind]
			if not shore and _chance(tree_chance):
				_try_tree(center, top)
			if _chance(0.45):
				_add("tuft", _spot(center, top), _tint(0.08))
			var flower_chance: float = {"Grass": 0.06, "Meadow": 0.45, "Island": 0.15}[kind]
			for i in 2:
				if _chance(flower_chance):
					var xform := _spot(center, top, 0.42, Vector2(0.8, 1.3))
					_add("flower", xform, FLOWER_COLORS[_rng.randi() % FLOWER_COLORS.size()].srgb_to_linear())
					if kind == "Meadow" and i == 0:
						_mark("flower", xform.origin)
			if shore and _chance(0.4):
				var xform := _spot(center, top, 0.35, Vector2(0.6, 0.9))
				_add("reeds", xform, _tint(0.1))
				_mark("reeds", xform.origin)
			if _chance(0.07 if shore else 0.006):
				var xform := _spot(center, top, 0.3, Vector2(0.6, 1.4))
				_add("rock", xform, _grey())
				if shore:
					_mark("shore_rock", xform.origin + Vector3(0.0, 0.2 * xform.basis.get_scale().y, 0.0))
			elif not shore and kind != "Meadow" and _chance(0.015):
				_add("shrub", _spot(center, top, 0.25, Vector2(0.8, 1.2)), _tint(0.12))
			if shore and kind != "Island":
				_note_jetty(column, top, kinds, false)
		"Field":
			if _chance(0.012):
				_add("hay_bale", _spot(center, top, 0.15, Vector2(0.9, 1.1)), _tint(0.08))
			elif _chance(0.75):
				var spot := Vector3(center.x + _rng.randf_range(-0.06, 0.06), top, center.z + _rng.randf_range(-0.12, 0.12))
				_add("wheat", Transform3D(Basis.from_scale(Vector3.ONE * _rng.randf_range(0.85, 1.1)), spot), _tint(0.1))
			for side: Vector2i in SIDES:
				if kinds.get(column + side, "") in ["Road", "Path"]:
					var edge := center + Vector3(side.x, 0.0, side.y) * 0.45
					edge.y = top
					_add("fence", Transform3D(Basis(Vector3.UP, PI * 0.5 if side.x != 0 else 0.0), edge), _tint(0.08))
		"Path":
			_scatter_path(column, center, top, kinds)
			if shore:
				_note_jetty(column, top, kinds, true)
		"Hedge":
			if _chance(0.35):
				_add("hedge_berries", _spot(center, top - 0.02, 0.1), Color.WHITE)
		"Soil", "Mud":
			if _chance(0.15):
				_add("pebbles", _spot(center, top, 0.25), _grey())


func _scatter_path(column: Vector2i, center: Vector3, top: float, kinds: Dictionary) -> void:
	var at := Vector2(center.x, center.z)
	var to_water := _water_direction(kinds, column, 3)
	if to_water != Vector2.ZERO:
		var water := Vector3(to_water.x, 0.0, to_water.y)
		if _far_from(_benches, at, 9.0) and _chance(0.35):
			_benches.append(at)
			var spot := center + water * 0.22
			spot.y = top
			_add("bench", Transform3D(Basis(Vector3.UP, atan2(to_water.x, to_water.y)), spot), _tint(0.06))
			return
		if _far_from(_lamps, at, 11.0) and _far_from(_benches, at, 3.0) and _chance(0.3):
			_lamps.append(at)
			var spot := center - water * 0.38
			spot.y = top
			_add("lamp_post", Transform3D(Basis(), spot), Color.WHITE)
			_lamp_bulbs.append(spot + Vector3(0.0, LAMP_HEIGHT, 0.0))
			return
	if not _signpost and _chance(0.25):
		for side: Vector2i in SIDES:
			if kinds.get(column + side, "") == "Road":
				_signpost = true
				var spot := center - Vector3(side.x, 0.0, side.y) * 0.3
				spot.y = top
				_add("signpost", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), spot), Color.WHITE)
				return


func _try_tree(center: Vector3, top: float) -> void:
	var at := Vector2(center.x, center.z)
	if not _far_from(_trees, at, tree_spacing):
		return
	_trees.append(at)
	var xform := _spot(center, top, 0.3, Vector2(0.85, 1.35))
	if _chance(0.3):
		_add("pine", xform, PINE_GREENS[_rng.randi() % PINE_GREENS.size()].srgb_to_linear())
	else:
		var color: Color = BLOSSOM if _chance(0.12) else TREE_GREENS[_rng.randi() % TREE_GREENS.size()]
		_add("round_tree", xform, color.srgb_to_linear())
	# Something at the foot of the tree, on the side away from the trunk.
	var away := Vector2(center.x - xform.origin.x, center.z - xform.origin.z)
	var side := away.normalized() if away.length() > 0.05 else Vector2.RIGHT.rotated(_rng.randf() * TAU)
	var foot := Vector3(center.x + side.x * 0.3, top, center.z + side.y * 0.3)
	if _chance(0.3):
		_add("mushrooms", _spot(foot, top, 0.08, Vector2(0.8, 1.3)), _tint(0.15))
	elif _chance(0.15):
		_add("log", _spot(foot, top, 0.05, Vector2(0.8, 1.1)), _tint(0.1))


# Remembers shore land columns with a straight run of open water for the jetty.
func _note_jetty(column: Vector2i, top: float, kinds: Dictionary, on_path: bool) -> void:
	for side: Vector2i in SIDES:
		var open := true
		for i in range(1, ceili(JETTY_LENGTH) + 2):
			if kinds.get(column + side * i, "") != "Water":
				open = false
				break
		if open:
			_jetty_options.append([column, side, top, on_path])


func _place_jetty() -> void:
	if _jetty_options.is_empty():
		return
	var pool := _jetty_options.filter(func(option: Array) -> bool: return option[3])
	if pool.is_empty():
		pool = _jetty_options
	var best: Array = pool[floori(pool.size() * 0.5)]
	if not _benches.is_empty():
		var best_distance := INF
		for option: Array in pool:
			var column: Vector2i = option[0]
			for bench in _benches:
				var distance := bench.distance_to(Vector2(column.x + 0.5, column.y + 0.5))
				if distance > 2.0 and distance < best_distance:
					best_distance = distance
					best = option
	var column: Vector2i = best[0]
	var side: Vector2i = best[1]
	var direction := Vector3(side.x, 0.0, side.y)
	var start := Vector3(column.x + 0.5, best[2] - 0.15, column.y + 0.5) + direction * 0.5
	_add("jetty", Transform3D(Basis(Vector3.UP, atan2(direction.x, direction.z)), start), Color.WHITE)
	for i in range(1, ceili(JETTY_LENGTH) + 1):
		_jetty_points.append(Vector2(column.x + 0.5 + side.x * i, column.y + 0.5 + side.y * i))
	_mark("jetty_end", start + direction * (JETTY_LENGTH - 0.35))


func _touches(kinds: Dictionary, column: Vector2i, want_water: bool) -> bool:
	for offset: Vector2i in NEIGHBOURS:
		var kind: String = kinds.get(column + offset, "")
		if kind != "" and (kind == "Water") == want_water:
			return true
	return false


# Axis direction to the nearest water column within reach, or zero.
func _water_direction(kinds: Dictionary, column: Vector2i, reach: int) -> Vector2:
	var best := Vector2i.ZERO
	var best_distance := INF
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var offset := Vector2i(dx, dz)
			if kinds.get(column + offset, "") == "Water" and offset.length() < best_distance:
				best_distance = offset.length()
				best = offset
	if best == Vector2i.ZERO:
		return Vector2.ZERO
	if absi(best.x) >= absi(best.y):
		return Vector2(signi(best.x), 0.0)
	return Vector2(0.0, signi(best.y))


func _far_from(points: Array[Vector2], at: Vector2, distance: float) -> bool:
	for point in points:
		if point.distance_to(at) < distance:
			return false
	return true


func _chance(p: float) -> bool:
	return _rng.randf() < p


func _spot(center: Vector3, y: float, jitter := 0.38, scale_range := Vector2(0.8, 1.2)) -> Transform3D:
	var spot := Vector3(center.x + _rng.randf_range(-jitter, jitter), y, center.z + _rng.randf_range(-jitter, jitter))
	var turn := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(scale_range.x, scale_range.y))
	return Transform3D(turn, spot)


# Multiplier close to white, so tinted parts vary a little.
func _tint(amount: float) -> Color:
	var v := 1.0 - _rng.randf() * amount
	return Color(v * _rng.randf_range(1.0 - amount, 1.0), v, v * _rng.randf_range(1.0 - amount, 1.0)).srgb_to_linear()


func _grey() -> Color:
	var v := _rng.randf_range(0.62, 0.78)
	return Color(v, v * 0.98, v * _rng.randf_range(0.93, 1.02)).srgb_to_linear()


func _add(prop: String, xform: Transform3D, tint: Color) -> void:
	if not _batches.has(prop):
		_batches[prop] = [[], []]
	_batches[prop][0].append(xform)
	_batches[prop][1].append(tint)


func _mark(spot_name: String, at: Vector3) -> void:
	if not _spots.has(spot_name):
		_spots[spot_name] = []
	_spots[spot_name].append(at)


# ---- Meshes ----

func _build() -> void:
	var lily := _lily_pad(false)
	var lily_flower := _lily_pad(true)
	var foam_quad := QuadMesh.new()
	foam_quad.orientation = PlaneMesh.FACE_Y
	foam_quad.size = Vector2(1.0, 0.3)
	var foam_material := MeshKit.particle_material(Color(1.0, 1.0, 1.0, 0.5), 1.0, 0.35, false)
	foam_material.set_shader_parameter("nature_only", true)
	var props := {
		"round_tree": [_round_tree(), 0.012, true],
		"pine": [_pine(), 0.01, true],
		"tuft": [_tuft(), 0.45, false],
		"flower": [_flower(), 0.45, false],
		"reeds": [_reeds(), 0.07, true],
		"rock": [_rock(), 0.0, true],
		"lily": [lily, 0.0, false, true],
		"lily_flower": [lily_flower, 0.0, false, true],
		"pond_lily": [lily, 0.0, false],
		"pond_lily_flower": [lily_flower, 0.0, false],
		"wheat": [_wheat(), 0.4, false],
		"hay_bale": [_hay_bale(), 0.0, true],
		"fence": [_fence(), 0.0, true],
		"mushrooms": [_mushrooms(), 0.0, false],
		"log": [_log(), 0.0, true],
		"shrub": [_shrub(), 0.012, true],
		"hedge_berries": [_hedge_berries(), 0.0, false],
		"pebbles": [_pebbles(), 0.0, false],
		"bench": [_bench(), 0.0, true],
		"lamp_post": [_lamp_post(), 0.0, true],
		"signpost": [_signpost_mesh(), 0.0, true],
		"jetty": [_jetty(), 0.0, true],
		"foam": [foam_quad, foam_material, false],
	}
	for prop: String in _batches:
		var entry: Array = props[prop]
		var material: ShaderMaterial
		if entry[1] is ShaderMaterial:
			material = entry[1]
		else:
			material = MeshKit.decor_material(entry[1], entry.size() > 3)
			if entry[1] > 0.0:
				_sway[material] = entry[1]
		var instance := _multimesh(prop.to_pascal_case(), entry[0], _batches[prop][0], _batches[prop][1], material)
		if not entry[2]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _multimesh(node_name: String, mesh: Mesh, transforms: Array, tints: Array, material: Material) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_custom_data(i, tints[i] if i < tints.size() else Color.WHITE)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)
	return instance


# Warm bulbs and soft light pools under the lamp posts, shown at night.
func _build_lamp_glow() -> void:
	if _lamp_bulbs.is_empty():
		return
	var bulbs: Array = []
	var pools: Array = []
	for bulb in _lamp_bulbs:
		bulbs.append(Transform3D(Basis(), bulb))
		pools.append(Transform3D(Basis(), Vector3(bulb.x, bulb.y - LAMP_HEIGHT + 0.04, bulb.z)))
	var bulb_quad := QuadMesh.new()
	bulb_quad.size = Vector2(0.7, 0.7)
	var pool_quad := QuadMesh.new()
	pool_quad.orientation = PlaneMesh.FACE_Y
	pool_quad.size = Vector2(3.4, 3.4)
	var bulb_light := Color(LAMP_LIGHT, 0.95)
	var pool_light := Color(LAMP_LIGHT, 0.32)
	for instance in [
			_multimesh("LampBulbs", bulb_quad, bulbs, [], MeshKit.particle_material(bulb_light, 4.0, 0.05)),
			_multimesh("LampPools", pool_quad, pools, [], MeshKit.particle_material(pool_light, 1.4, 0.0, false))]:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visible = false
		_night_lights.append(instance)


static func _round_tree() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, MeshKit.cylinder(0.09, 0.14, 0.9), MeshKit.at(Vector3(0.0, 0.45, 0.0)), TRUNK)
	MeshKit.add_primitive(st, MeshKit.sphere(0.55), MeshKit.at(Vector3(0.0, 1.3, 0.0)), Color.WHITE, true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.42), MeshKit.at(Vector3(0.34, 1.05, 0.12)), Color(0.9, 0.9, 0.9), true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.40), MeshKit.at(Vector3(-0.28, 1.1, -0.2)), Color(0.95, 0.95, 0.95), true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.32), MeshKit.at(Vector3(0.06, 1.72, 0.04)), Color(1.0, 1.0, 1.0), true)
	return st.commit()


static func _pine() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, MeshKit.cylinder(0.08, 0.12, 0.7), MeshKit.at(Vector3(0.0, 0.35, 0.0)), TRUNK)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.62, 0.8, 10), MeshKit.at(Vector3(0.0, 0.9, 0.0)), Color(0.9, 0.9, 0.9), true)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.48, 0.7, 10), MeshKit.at(Vector3(0.0, 1.35, 0.0)), Color(0.97, 0.97, 0.97), true)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.32, 0.6, 10), MeshKit.at(Vector3(0.0, 1.75, 0.0)), Color.WHITE, true)
	return st.commit()


static func _tuft() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var st := MeshKit.begin()
	for i in 7:
		var base := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
		MeshKit.add_blade(st, base, rng.randf() * TAU, rng.randf_range(0.22, 0.4), rng.randf_range(0.04, 0.12), 0.08,
				Color(0.30, 0.54, 0.20), Color(0.62, 0.88, 0.36))
	return st.commit()


static func _flower() -> ArrayMesh:
	var st := MeshKit.begin()
	var stem := Color(0.32, 0.6, 0.24)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.015, 0.02, 0.3, 5), MeshKit.at(Vector3(0.0, 0.15, 0.0)), stem)
	MeshKit.add_blade(st, Vector3.ZERO, 0.4, 0.16, 0.08, 0.07, stem, stem, false)
	MeshKit.add_blade(st, Vector3.ZERO, 2.6, 0.13, 0.07, 0.07, stem, stem, false)
	for i in 5:
		var angle := TAU * i / 5.0
		var petal := Vector3(cos(angle) * 0.065, 0.31, sin(angle) * 0.065)
		MeshKit.add_primitive(st, MeshKit.sphere(0.055, 8, 4), MeshKit.at(petal, Vector3(1.0, 0.45, 1.0)), Color.WHITE, true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.04, 8, 4), MeshKit.at(Vector3(0.0, 0.325, 0.0)), Color(1.0, 0.82, 0.25))
	return st.commit()


static func _reeds() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var st := MeshKit.begin()
	for i in 8:
		var base := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
		MeshKit.add_blade(st, base, rng.randf() * TAU, rng.randf_range(0.8, 1.25), rng.randf_range(0.08, 0.22), 0.07,
				Color(0.32, 0.50, 0.22), Color(0.58, 0.78, 0.32))
	for spot: Vector3 in [Vector3(0.05, 0.0, -0.04), Vector3(-0.08, 0.0, 0.06)]:
		var height := 1.05 if spot.x > 0.0 else 0.9
		MeshKit.add_primitive(st, MeshKit.cylinder(0.012, 0.015, height, 5), MeshKit.at(spot + Vector3(0.0, height * 0.5, 0.0)), Color(0.4, 0.58, 0.26))
		MeshKit.add_primitive(st, MeshKit.cylinder(0.045, 0.045, 0.2, 8), MeshKit.at(spot + Vector3(0.0, height, 0.0)), Color(0.48, 0.30, 0.16))
	return st.commit()


static func _rock() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, MeshKit.sphere(0.3, 7, 4), MeshKit.at(Vector3(0.0, 0.06, 0.0), Vector3(1.0, 0.62, 0.85)), Color.WHITE, true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.17, 6, 3), MeshKit.at(Vector3(0.27, 0.03, 0.12), Vector3(1.0, 0.7, 0.9)), Color(0.92, 0.92, 0.92), true)
	return st.commit()


static func _lily_pad(with_flower: bool) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, MeshKit.cylinder(0.32, 0.32, 0.03, 14), MeshKit.at(Vector3(0.0, 0.0, 0.0)), Color(0.40, 0.72, 0.30), true)
	if with_flower:
		for i in 6:
			var angle := TAU * i / 6.0
			var petal := Vector3(cos(angle) * 0.07, 0.07, sin(angle) * 0.07)
			MeshKit.add_primitive(st, MeshKit.sphere(0.06, 8, 4), MeshKit.at(petal, Vector3(1.0, 0.7, 1.0)), Color(1.0, 0.72, 0.84))
		MeshKit.add_primitive(st, MeshKit.sphere(0.035, 8, 4), MeshKit.at(Vector3(0.0, 0.1, 0.0)), Color(1.0, 0.85, 0.3))
	return st.commit()


# A row of wheat along X with golden ears.
static func _wheat() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var st := MeshKit.begin()
	for i in 9:
		var base := Vector3(-0.4 + i * 0.1 + rng.randf_range(-0.03, 0.03), 0.0, rng.randf_range(-0.06, 0.06))
		var height := rng.randf_range(0.34, 0.5)
		var yaw := rng.randf() * TAU
		var lean := rng.randf_range(0.02, 0.07)
		MeshKit.add_blade(st, base, yaw, height, lean, 0.05, Color(0.56, 0.62, 0.26), Color(0.92, 0.80, 0.42))
		var tip := base + Vector3(-sin(yaw) * lean, height, cos(yaw) * lean)
		MeshKit.add_primitive(st, MeshKit.sphere(0.03, 6, 3), MeshKit.at(tip, Vector3(1.0, 2.4, 1.0)), Color(0.98, 0.84, 0.46), true)
	return st.commit()


static func _hay_bale() -> ArrayMesh:
	var st := MeshKit.begin()
	var lying := Basis(Vector3.BACK, PI * 0.5)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.28, 0.28, 0.55, 14), Transform3D(lying, Vector3(0.0, 0.28, 0.0)), Color(0.95, 0.80, 0.42), true)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.2, 0.2, 0.57, 14), Transform3D(lying, Vector3(0.0, 0.28, 0.0)), Color(0.84, 0.66, 0.30), true)
	for x in [-0.13, 0.13]:
		MeshKit.add_primitive(st, MeshKit.cylinder(0.29, 0.29, 0.03, 14), Transform3D(lying, Vector3(x, 0.28, 0.0)), Color(0.62, 0.42, 0.25))
	return st.commit()


# One fence span along X, posts at both ends.
static func _fence() -> ArrayMesh:
	var st := MeshKit.begin()
	for x in [-0.5, 0.5]:
		MeshKit.add_primitive(st, MeshKit.box(Vector3(0.07, 0.56, 0.07)), MeshKit.at(Vector3(x, 0.28, 0.0)), Color(0.86, 0.80, 0.70), true)
		MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.055, 0.06, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(x, 0.59, 0.0)), Color(0.86, 0.80, 0.70), true)
	for y in [0.22, 0.42]:
		MeshKit.add_primitive(st, MeshKit.box(Vector3(1.0, 0.05, 0.035)), MeshKit.at(Vector3(0.0, y, 0.0)), Color(0.96, 0.92, 0.84), true)
	return st.commit()


static func _mushrooms() -> ArrayMesh:
	var st := MeshKit.begin()
	for spec: Array in [[Vector3(0.0, 0.0, 0.0), 0.16, 0.08], [Vector3(0.11, 0.0, 0.06), 0.11, 0.06], [Vector3(-0.07, 0.0, 0.09), 0.08, 0.045]]:
		var base: Vector3 = spec[0]
		var height: float = spec[1]
		var radius: float = spec[2]
		MeshKit.add_primitive(st, MeshKit.cylinder(radius * 0.35, radius * 0.45, height, 6), MeshKit.at(base + Vector3(0.0, height * 0.5, 0.0)), Color(0.97, 0.93, 0.85))
		MeshKit.add_primitive(st, MeshKit.sphere(radius, 10, 5), MeshKit.at(base + Vector3(0.0, height, 0.0), Vector3(1.0, 0.62, 1.0)), Color(0.92, 0.22, 0.18), true)
		for i in 4:
			var angle := TAU * i / 4.0 + 0.4
			var dot := base + Vector3(cos(angle) * radius * 0.55, height + radius * 0.42, sin(angle) * radius * 0.55)
			MeshKit.add_primitive(st, MeshKit.sphere(radius * 0.17, 5, 3), MeshKit.at(dot, Vector3(1.0, 0.5, 1.0)), Color(1.0, 0.98, 0.94))
	return st.commit()


static func _log() -> ArrayMesh:
	var st := MeshKit.begin()
	var lying := Basis(Vector3.BACK, PI * 0.5)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.12, 0.13, 0.7, 9), Transform3D(lying, Vector3(0.0, 0.12, 0.0)), Color(0.50, 0.36, 0.24), true)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.1, 0.1, 0.72, 9), Transform3D(lying, Vector3(0.0, 0.12, 0.0)), Color(0.88, 0.74, 0.54))
	MeshKit.add_primitive(st, MeshKit.sphere(0.09, 8, 4), MeshKit.at(Vector3(0.08, 0.23, 0.0), Vector3(1.8, 0.45, 1.1)), Color(0.42, 0.68, 0.30))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.008, 0.012, 0.1, 4), MeshKit.at(Vector3(-0.2, 0.28, 0.02)), Color(0.42, 0.62, 0.28))
	MeshKit.add_primitive(st, MeshKit.sphere(0.03, 6, 3), MeshKit.at(Vector3(-0.2, 0.33, 0.02)), Color(1.0, 0.95, 0.5))
	return st.commit()


static func _shrub() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var st := MeshKit.begin()
	var green := Color(0.40, 0.68, 0.30)
	MeshKit.add_primitive(st, MeshKit.sphere(0.3, 10, 5), MeshKit.at(Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.85, 1.0)), green, true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.22, 9, 5), MeshKit.at(Vector3(0.22, 0.17, 0.08)), green.darkened(0.06), true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.2, 9, 5), MeshKit.at(Vector3(-0.2, 0.16, -0.1)), green.lightened(0.05), true)
	for i in 9:
		var angle := rng.randf() * TAU
		var up := rng.randf_range(0.15, 1.0)
		var dir := Vector3(cos(angle) * sqrt(1.0 - up * up), up * 0.85, sin(angle) * sqrt(1.0 - up * up))
		MeshKit.add_primitive(st, MeshKit.sphere(0.04, 6, 3), MeshKit.at(Vector3(0.0, 0.25, 0.0) + dir * 0.3), Color(0.92, 0.16, 0.26))
	return st.commit()


static func _hedge_berries() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var st := MeshKit.begin()
	for i in 7:
		var spot := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, 0.05), rng.randf_range(-0.4, 0.4))
		var berry := Color(0.50, 0.22, 0.62) if i % 2 == 0 else Color(0.88, 0.18, 0.28)
		MeshKit.add_primitive(st, MeshKit.sphere(0.045, 6, 3), MeshKit.at(spot), berry)
	for i in 4:
		var spot := Vector3(rng.randf_range(-0.4, 0.4), 0.04, rng.randf_range(-0.4, 0.4))
		for p in 4:
			var angle := TAU * p / 4.0
			MeshKit.add_primitive(st, MeshKit.sphere(0.03, 6, 3), MeshKit.at(spot + Vector3(cos(angle) * 0.035, 0.0, sin(angle) * 0.035), Vector3(1.0, 0.5, 1.0)), Color(1.0, 0.97, 0.92))
		MeshKit.add_primitive(st, MeshKit.sphere(0.02, 6, 3), MeshKit.at(spot + Vector3(0.0, 0.01, 0.0)), Color(1.0, 0.82, 0.3))
	return st.commit()


static func _pebbles() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var st := MeshKit.begin()
	for i in 5:
		var radius := rng.randf_range(0.045, 0.09)
		var spot := Vector3(rng.randf_range(-0.28, 0.28), radius * 0.2, rng.randf_range(-0.28, 0.28))
		MeshKit.add_primitive(st, MeshKit.sphere(radius, 7, 4), MeshKit.at(spot, Vector3(1.0, 0.55, rng.randf_range(0.7, 1.0))), Color(1.0, 1.0, 1.0).darkened(rng.randf() * 0.15), true)
	return st.commit()


# A park bench facing +Z.
static func _bench() -> ArrayMesh:
	var st := MeshKit.begin()
	for z in [-0.08, 0.04, 0.16]:
		MeshKit.add_primitive(st, MeshKit.box(Vector3(1.0, 0.045, 0.1)), MeshKit.at(Vector3(0.0, 0.36, z)), WOOD, true)
	var tilt := Basis(Vector3.RIGHT, -0.18)
	for y in [0.52, 0.65]:
		MeshKit.add_primitive(st, MeshKit.box(Vector3(1.0, 0.09, 0.035)), Transform3D(tilt, Vector3(0.0, y, -0.17 - (y - 0.52) * 0.18)), WOOD, true)
	for x in [-0.42, 0.42]:
		MeshKit.add_primitive(st, MeshKit.box(Vector3(0.05, 0.34, 0.3)), MeshKit.at(Vector3(x, 0.17, 0.04)), IRON)
		MeshKit.add_primitive(st, MeshKit.box(Vector3(0.05, 0.36, 0.04)), Transform3D(tilt, Vector3(x, 0.55, -0.16)), IRON)
		MeshKit.add_primitive(st, MeshKit.box(Vector3(0.05, 0.04, 0.3)), MeshKit.at(Vector3(x, 0.46, 0.04)), IRON)
	return st.commit()


static func _lamp_post() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, MeshKit.cylinder(0.09, 0.12, 0.14, 8), MeshKit.at(Vector3(0.0, 0.07, 0.0)), IRON)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.035, 0.045, 1.4, 8), MeshKit.at(Vector3(0.0, 0.8, 0.0)), IRON)
	MeshKit.add_primitive(st, MeshKit.box(Vector3(0.22, 0.04, 0.22)), MeshKit.at(Vector3(0.0, LAMP_HEIGHT - 0.13, 0.0)), IRON)
	MeshKit.add_primitive(st, MeshKit.box(Vector3(0.17, 0.22, 0.17)), MeshKit.at(Vector3(0.0, LAMP_HEIGHT, 0.0)), Color(1.0, 0.93, 0.70))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.17, 0.14, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, LAMP_HEIGHT + 0.18, 0.0)), IRON)
	MeshKit.add_primitive(st, MeshKit.sphere(0.03, 6, 3), MeshKit.at(Vector3(0.0, LAMP_HEIGHT + 0.27, 0.0)), IRON)
	return st.commit()


static func _signpost_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var cream := Color(0.97, 0.94, 0.86)
	MeshKit.add_primitive(st, MeshKit.box(Vector3(0.08, 1.15, 0.08)), MeshKit.at(Vector3(0.0, 0.575, 0.0)), DARK_WOOD)
	for spec: Array in [[0.98, 0.0, 1.0], [0.76, 2.3, -1.0]]:
		var turn := Basis(Vector3.UP, spec[1])
		var side: float = spec[2]
		var board := Transform3D(turn, turn * Vector3(side * 0.22, spec[0], 0.0))
		MeshKit.add_primitive(st, MeshKit.box(Vector3(0.5, 0.15, 0.035)), board, WOOD)
		MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.106, 0.035, 4), board * Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI * 0.25), Vector3(side * 0.25, 0.0, 0.0)), WOOD)
		for row in [-0.03, 0.03]:
			MeshKit.add_primitive(st, MeshKit.box(Vector3(0.32, 0.018, 0.04)), board * MeshKit.at(Vector3(-side * 0.02, row, 0.0)), cream)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.07, 0.08, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, 1.19, 0.0)), DARK_WOOD)
	return st.commit()


# Planks on posts running along +Z from the shore, deck top at y = 0.
static func _jetty() -> ArrayMesh:
	var st := MeshKit.begin()
	var count := floori(JETTY_LENGTH / 0.22)
	for i in count:
		var plank := WOOD if i % 2 == 0 else WOOD.darkened(0.08)
		MeshKit.add_primitive(st, MeshKit.box(Vector3(1.0, 0.06, 0.19)), MeshKit.at(Vector3(0.0, -0.03, 0.11 + i * 0.22)), plank)
	for x in [-0.36, 0.36]:
		MeshKit.add_primitive(st, MeshKit.box(Vector3(0.08, 0.1, JETTY_LENGTH)), MeshKit.at(Vector3(x, -0.11, JETTY_LENGTH * 0.5)), DARK_WOOD)
	for z in [0.9, 2.0, JETTY_LENGTH - 0.15]:
		for x in [-0.44, 0.44]:
			MeshKit.add_primitive(st, MeshKit.cylinder(0.06, 0.06, 2.2, 8), MeshKit.at(Vector3(x, -0.9, z)), DARK_WOOD)
			MeshKit.add_primitive(st, MeshKit.sphere(0.06, 8, 3), MeshKit.at(Vector3(x, 0.2, z), Vector3(1.0, 0.5, 1.0)), DARK_WOOD)
	# A little rope coil at the end.
	MeshKit.add_primitive(st, MeshKit.cylinder(0.11, 0.11, 0.05, 12), MeshKit.at(Vector3(0.25, 0.025, JETTY_LENGTH - 0.45)), Color(0.86, 0.76, 0.56))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.06, 0.06, 0.06, 10), MeshKit.at(Vector3(0.25, 0.03, JETTY_LENGTH - 0.45)), Color(0.62, 0.50, 0.34))
	return st.commit()


# ---- Fireflies ----

func _make_fireflies() -> GPUParticles3D:
	var origin: Vector3i = simulation.GetGridOrigin()
	var size: Vector3i = simulation.GetGridSize()
	var half := Vector3(size.x * 0.5, 1.2, size.z * 0.5)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = half
	process.gravity = Vector3.ZERO
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.35
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 4.0
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.15
	process.color_ramp = MeshKit.fade_ramp(1.0, 0.2, 0.8)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.36, 0.36)
	quad.material = MeshKit.particle_material(Color(0.85, 1.0, 0.45), 6.0, 0.8)
	var particles := GPUParticles3D.new()
	particles.name = "Fireflies"
	particles.amount = 160
	particles.lifetime = 7.0
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.position = Vector3(origin.x + half.x, simulation.GetWaterSurfaceY() + 2.5, origin.z + half.z)
	particles.visibility_aabb = AABB(-half - Vector3(2.0, 3.0, 2.0), half * 2.0 + Vector3(4.0, 6.0, 4.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = false
	return particles
