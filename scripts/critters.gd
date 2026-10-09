extends Node3D

## Small animated wildlife: herons fishing in the shallows, frogs hopping between pond lily pads,
## turtles sunning on shore rocks, a fish that leaps out of open water now and then, and
## butterflies and dragonflies by day. Spots come from level_decor.gd.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const BUTTERFLY_COLORS := [Color(1.0, 0.84, 0.30), Color(1.0, 1.0, 1.0), Color(1.0, 0.58, 0.28), Color(0.55, 0.76, 1.0), Color(1.0, 0.64, 0.86)]
const DRAGONFLY_COLORS := [Color(0.25, 0.62, 0.95), Color(0.30, 0.80, 0.55), Color(0.85, 0.30, 0.30)]
const HOP_TIME := 0.55
const FROG_SIZE := 1.7
const JUMP_TIME := 0.9

@export var simulation: Node
@export var decor: Node3D  # level_decor.gd
@export var heron_count := 2
@export var frog_count := 4
@export var turtle_count := 3
@export var butterfly_count := 16
@export var dragonfly_count := 8
@export var random_seed := 5

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _surface_y := 0.0
var _avoid := PackedVector2Array()
var _herons: Array[Dictionary] = []
var _frogs: Array[Dictionary] = []
var _pads: Array = []
var _turtles: Array[Dictionary] = []
var _open_water: Array[Vector2] = []
var _fish: MeshInstance3D
var _fish_jump := {}
var _fish_timer := 3.0
var _splash: GPUParticles3D
var _butterflies: MultiMeshInstance3D
var _butterfly_paths: Array[Dictionary] = []
var _dragonflies: MultiMeshInstance3D
var _dragonfly_paths: Array[Dictionary] = []


func _ready() -> void:
	if simulation == null or decor == null or not simulation.IsLoaded:
		return
	_rng.seed = random_seed
	_surface_y = simulation.GetWaterSurfaceY()
	var material := MeshKit.decor_material()
	_spawn_herons(material)
	_spawn_frogs(material)
	_spawn_turtles(material)
	_spawn_fish(material)
	_butterflies = _spawn_flyers("Butterflies", _butterfly_mesh(), decor.get_spots("flower"), butterfly_count,
			BUTTERFLY_COLORS, _butterfly_paths, Vector2(0.45, 0.9), 1.8, 0.95, 15.0)
	_dragonflies = _spawn_flyers("Dragonflies", _dragonfly_mesh(), decor.get_spots("reeds"), dragonfly_count,
			DRAGONFLY_COLORS, _dragonfly_paths, Vector2(0.7, 1.1), 1.6, 0.3, 45.0)


## Fountain parts and other spots the fish should not jump near.
func set_avoid(points: PackedVector2Array) -> void:
	_avoid = points


## Butterflies and dragonflies are out by day only.
func set_daylight(daylight: float) -> void:
	for flyers in [_butterflies, _dragonflies]:
		if flyers:
			flyers.visible = daylight > 0.3


func get_counts() -> Dictionary:
	return {
		"herons": _herons.size(),
		"frogs": _frogs.size(),
		"turtles": _turtles.size(),
		"fish": 1 if _fish else 0,
		"butterflies": _butterfly_paths.size(),
		"dragonflies": _dragonfly_paths.size(),
	}


func _process(delta: float) -> void:
	_time += delta
	_update_herons(delta)
	_update_frogs(delta)
	_update_turtles()
	_update_fish(delta)
	if _butterflies and _butterflies.visible:
		_update_flyers(_butterflies, _butterfly_paths, delta)
	if _dragonflies and _dragonflies.visible:
		_update_flyers(_dragonflies, _dragonfly_paths, delta)


# ---- Herons ----

func _spawn_herons(material: Material) -> void:
	var spots := _pick(decor.get_spots("shallows"), heron_count, 12.0, decor.jetty_points())
	var body := _heron_body()
	var neck := _heron_neck()
	for spot: Vector3 in spots:
		var heron := Node3D.new()
		heron.name = "Heron"
		heron.position = spot
		heron.rotation.y = _toward_open_water(spot) + _rng.randf_range(-0.5, 0.5)
		heron.add_child(_mesh_node(body, material))
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.92, 0.2)
		pivot.add_child(_mesh_node(neck, material))
		heron.add_child(pivot)
		add_child(heron)
		_herons.append({"node": heron, "neck": pivot, "timer": _rng.randf_range(1.0, 4.0), "peck": -1.0,
				"yaw": heron.rotation.y, "home": heron.rotation.y})


func _update_herons(delta: float) -> void:
	for heron in _herons:
		var node: Node3D = heron.node
		var neck: Node3D = heron.neck
		if heron.peck >= 0.0:
			heron.peck += delta / 1.1
			neck.rotation.x = sin(minf(heron.peck, 1.0) * PI) * 1.15
			if heron.peck >= 1.0:
				heron.peck = -1.0
		else:
			heron.timer -= delta
			neck.rotation.x = sin(_time * 1.3 + node.position.x) * 0.04
			if heron.timer <= 0.0:
				heron.timer = _rng.randf_range(3.0, 8.0)
				if _chance(0.65):
					heron.peck = 0.0
				else:
					heron.yaw = heron.home + _rng.randf_range(-0.9, 0.9)
		node.rotation.y = lerp_angle(node.rotation.y, heron.yaw, minf(delta * 1.5, 1.0))


func _toward_open_water(spot: Vector3) -> float:
	var best := 0.0
	var best_count := -1
	for i in 8:
		var angle := TAU * i / 8.0
		var count := 0
		for step in range(1, 4):
			var probe := Vector2(spot.x, spot.z) + Vector2(sin(angle), cos(angle)) * step
			if simulation.IsWaterColumn(floori(probe.x), floori(probe.y)):
				count += 1
		if count > best_count:
			best_count = count
			best = angle
	return best


# ---- Frogs ----

func _spawn_frogs(material: Material) -> void:
	_pads = decor.get_spots("lily_pad")
	var spots := _pick(_pads, frog_count, 2.5)
	var body := _frog_mesh()
	var throat := _throat_mesh()
	for spot: Vector3 in spots:
		var frog := _mesh_node(body, material)
		frog.name = "Frog"
		frog.position = spot
		frog.rotation.y = _rng.randf() * TAU
		frog.scale = Vector3.ONE * FROG_SIZE
		var chin := _mesh_node(throat, material)
		chin.position = Vector3(0.0, 0.07, 0.15)
		frog.add_child(chin)
		add_child(frog)
		_frogs.append({"node": frog, "throat": chin, "at": spot, "from": spot, "to": spot, "hop": -1.0,
				"timer": _rng.randf_range(2.0, 7.0), "phase": _rng.randf() * TAU})


func _update_frogs(delta: float) -> void:
	for frog in _frogs:
		var node: Node3D = frog.node
		var throat: Node3D = frog.throat
		if frog.hop >= 0.0:
			frog.hop += delta / HOP_TIME
			var t := minf(frog.hop, 1.0)
			var from: Vector3 = frog.from
			var to: Vector3 = frog.to
			node.position = from.lerp(to, t) + Vector3.UP * (0.35 + from.distance_to(to) * 0.15) * 4.0 * t * (1.0 - t)
			node.scale = Vector3(1.0, 1.0 + sin(t * PI) * 0.25, 1.0) * FROG_SIZE
			throat.scale = Vector3.ONE * 0.5
			if frog.hop >= 1.0:
				frog.hop = -1.0
				frog.at = to
				node.scale = Vector3.ONE * FROG_SIZE
		else:
			var breath := 0.5 + 0.5 * sin(_time * 6.0 + frog.phase)
			throat.scale = Vector3.ONE * lerpf(0.55, 1.15, breath * breath)
			frog.timer -= delta
			if frog.timer <= 0.0:
				frog.timer = _rng.randf_range(3.0, 9.0)
				_start_hop(frog)


func _start_hop(frog: Dictionary) -> void:
	var at: Vector3 = frog.at
	var options: Array = []
	for pad: Vector3 in _pads:
		var distance := pad.distance_to(at)
		if distance > 0.5 and distance < 3.5 and not _pad_taken(pad):
			options.append(pad)
	var to: Vector3 = options[_rng.randi() % options.size()] if not options.is_empty() else at
	frog.from = at
	frog.to = to
	frog.hop = 0.0
	var node: Node3D = frog.node
	if to != at:
		node.rotation.y = atan2(to.x - at.x, to.z - at.z)
	else:
		node.rotation.y += _rng.randf_range(-1.5, 1.5)


func _pad_taken(pad: Vector3) -> bool:
	for frog in _frogs:
		if (frog.to as Vector3).distance_to(pad) < 0.3:
			return true
	return false


# ---- Turtles ----

func _spawn_turtles(material: Material) -> void:
	var spots := _pick(decor.get_spots("shore_rock"), turtle_count, 6.0)
	var shell := _turtle_mesh()
	var head_mesh := _turtle_head()
	for spot: Vector3 in spots:
		var turtle := _mesh_node(shell, material)
		turtle.name = "Turtle"
		turtle.position = spot - Vector3(0.0, 0.03, 0.0)
		turtle.rotation.y = _rng.randf() * TAU
		var head := _mesh_node(head_mesh, material)
		head.position = Vector3(0.0, 0.08, 0.2)
		turtle.add_child(head)
		add_child(turtle)
		_turtles.append({"node": turtle, "head": head, "phase": _rng.randf() * TAU})


func _update_turtles() -> void:
	for turtle in _turtles:
		var head: Node3D = turtle.head
		var cycle: float = fmod(_time * 0.35 + turtle.phase, TAU)
		var out := smoothstep(-0.2, 0.4, sin(cycle))
		head.position = Vector3(0.0, 0.07 + 0.02 * out, lerpf(0.13, 0.22, out))
		head.rotation = Vector3(-0.25 * out * maxf(sin(_time * 2.5 + turtle.phase), 0.0), sin(_time * 0.7 + turtle.phase) * 0.5 * out, 0.0)


# ---- Fish ----

func _spawn_fish(material: Material) -> void:
	var origin: Vector3i = simulation.GetGridOrigin()
	var size: Vector3i = simulation.GetGridSize()
	for z in range(origin.z + 2, origin.z + size.z - 2):
		for x in range(origin.x + 2, origin.x + size.x - 2):
			if _all_water(x, z, 2):
				_open_water.append(Vector2(x + 0.5, z + 0.5))
	if _open_water.is_empty():
		return
	_fish = _mesh_node(_fish_mesh(), material)
	_fish.name = "Fish"
	_fish.visible = false
	add_child(_fish)
	_splash = _make_splash()
	add_child(_splash)


func _update_fish(delta: float) -> void:
	if _fish == null:
		return
	if _fish_jump.is_empty():
		_fish_timer -= delta
		if _fish_timer <= 0.0:
			_fish_timer = _rng.randf_range(3.0, 8.0)
			_start_jump()
		return
	_fish_jump.t += delta / JUMP_TIME
	var t := minf(_fish_jump.t, 1.0)
	var from: Vector3 = _fish_jump.from
	var to: Vector3 = _fish_jump.to
	var height: float = _fish_jump.height
	_fish.position = from.lerp(to, t) + Vector3.UP * height * 4.0 * t * (1.0 - t)
	var rise := height * 4.0 * (1.0 - 2.0 * t)
	_fish.rotation = Vector3(-atan2(rise, from.distance_to(to)), atan2(to.x - from.x, to.z - from.z), sin(_time * 30.0) * 0.15)
	if _fish_jump.t >= 1.0:
		_fish.visible = false
		_fish_jump = {}
		_burst(to)


func _start_jump() -> void:
	for _attempt in 12:
		var spot: Vector2 = _open_water[_rng.randi() % _open_water.size()]
		var clear := true
		for point in _avoid:
			if point.distance_to(spot) < 4.0:
				clear = false
				break
		if not clear:
			continue
		var heading := _rng.randf() * TAU
		var end := spot + Vector2(sin(heading), cos(heading)) * _rng.randf_range(1.0, 1.6)
		if not simulation.IsWaterColumn(floori(end.x), floori(end.y)):
			continue
		var from := Vector3(spot.x, _surface_y - 0.1, spot.y)
		_fish_jump = {"from": from, "to": Vector3(end.x, _surface_y - 0.1, end.y), "t": 0.0, "height": _rng.randf_range(0.6, 1.0)}
		_fish.scale = Vector3.ONE * _rng.randf_range(0.9, 1.3)
		_fish.visible = true
		_burst(from)
		return


func _burst(at: Vector3) -> void:
	_splash.global_position = Vector3(at.x, _surface_y + 0.02, at.z)
	_splash.restart()


func _all_water(x: int, z: int, reach: int) -> bool:
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if not simulation.IsWaterColumn(x + dx, z + dz):
				return false
	return true


func _make_splash() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.4
	process.gravity = Vector3(0.0, -7.0, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color_ramp = MeshKit.fade_ramp(0.9, 0.05, 0.6)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = MeshKit.particle_material(Color(0.92, 0.97, 1.0), 1.3)
	var particles := GPUParticles3D.new()
	particles.name = "FishSplash"
	particles.amount = 18
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


# ---- Butterflies and dragonflies ----

func _spawn_flyers(node_name: String, mesh: Mesh, homes: Array, count: int, colors: Array, paths: Array[Dictionary],
		height: Vector2, size: float, flap: float, flap_speed: float) -> MultiMeshInstance3D:
	if homes.is_empty():
		return null
	for i in count:
		var home: Vector3 = homes[_rng.randi() % homes.size()]
		paths.append({
			"home": home, "target": home, "phase": Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU),
			"freq": Vector3(_rng.randf_range(0.5, 0.9), _rng.randf_range(1.0, 1.6), _rng.randf_range(0.4, 0.8)),
			"radius": _rng.randf_range(0.8, 1.6), "height": _rng.randf_range(height.x, height.y),
			"timer": _rng.randf_range(4.0, 12.0), "homes": homes,
		})
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	for i in count:
		multimesh.set_instance_custom_data(i, (colors[i % colors.size()] as Color).srgb_to_linear())
	var material := MeshKit.decor_material()
	material.set_shader_parameter("flap", flap)
	material.set_shader_parameter("flap_speed", flap_speed)
	material.set_shader_parameter("flap_body", 0.015)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("size", size)
	add_child(instance)
	_update_flyers(instance, paths, 0.0)
	return instance


func _update_flyers(instance: MultiMeshInstance3D, paths: Array[Dictionary], delta: float) -> void:
	var size: float = instance.get_meta("size")
	for i in paths.size():
		var path := paths[i]
		path.timer -= delta
		if path.timer <= 0.0:
			path.timer = _rng.randf_range(5.0, 12.0)
			var homes: Array = path.homes
			var next: Vector3 = homes[_rng.randi() % homes.size()]
			if next.distance_to(path.target) < 8.0:
				path.target = next
		var home: Vector3 = path.home
		path.home = home.move_toward(path.target, delta * 0.8)
		var at := _flyer_at(path, _time)
		var ahead := _flyer_at(path, _time + 0.1)
		var heading := atan2(ahead.x - at.x, ahead.z - at.z)
		instance.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, heading).scaled(Vector3.ONE * size), at))


func _flyer_at(path: Dictionary, time: float) -> Vector3:
	var phase: Vector3 = path.phase
	var freq: Vector3 = path.freq
	var radius: float = path.radius
	var home: Vector3 = path.home
	return home + Vector3(
			sin(time * freq.x + phase.x) * radius,
			path.height + sin(time * freq.y + phase.y) * 0.18,
			sin(time * freq.z + phase.z) * radius)


# ---- Helpers ----

func _pick(spots: Array, count: int, spacing: float, avoid := PackedVector2Array()) -> Array:
	var pool := spots.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	var picked: Array = []
	for spot: Vector3 in pool:
		if picked.size() >= count:
			break
		var flat := Vector2(spot.x, spot.z)
		var ok := true
		for other: Vector3 in picked:
			if Vector2(other.x, other.z).distance_to(flat) < spacing:
				ok = false
				break
		for point in avoid:
			if point.distance_to(flat) < 3.0:
				ok = false
				break
		if ok:
			picked.append(spot)
	return picked


func _mesh_node(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node


func _chance(p: float) -> bool:
	return _rng.randf() < p


# ---- Meshes (facing +Z, origin at the feet or waterline) ----

static func _heron_body() -> ArrayMesh:
	var st := MeshKit.begin()
	var grey := Color(0.74, 0.78, 0.84)
	MeshKit.add_primitive(st, MeshKit.sphere(0.22, 12, 6), MeshKit.at(Vector3(0.0, 0.86, 0.02), Vector3(0.8, 0.72, 1.3)), grey)
	MeshKit.add_primitive(st, MeshKit.sphere(0.2, 10, 5), MeshKit.at(Vector3(0.0, 0.9, -0.06), Vector3(0.88, 0.6, 1.2)), Color(0.56, 0.61, 0.70))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.08, 0.22, 5), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 - 0.3), Vector3(0.0, 0.84, -0.32)), Color(0.50, 0.55, 0.64))
	for x in [-0.06, 0.06]:
		MeshKit.add_primitive(st, MeshKit.cylinder(0.014, 0.016, 1.0, 5), MeshKit.at(Vector3(x, 0.2, 0.0)), Color(0.86, 0.74, 0.42))
	return st.commit()


# Neck and head around a pivot at the shoulders; pecking rotates the pivot about X.
static func _heron_neck() -> ArrayMesh:
	var st := MeshKit.begin()
	var white := Color(0.94, 0.95, 0.97)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.035, 0.05, 0.42, 6), Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.0, 0.18, 0.06)), white)
	MeshKit.add_primitive(st, MeshKit.sphere(0.075, 10, 5), MeshKit.at(Vector3(0.0, 0.41, 0.13), Vector3(0.9, 0.9, 1.15)), white)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.026, 0.26, 5), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.12), Vector3(0.0, 0.39, 0.32)), Color(1.0, 0.74, 0.25))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.006, 0.012, 0.2, 4), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.4), Vector3(0.0, 0.45, 0.0)), Color(0.18, 0.2, 0.26))
	for x in [-0.055, 0.055]:
		MeshKit.add_primitive(st, MeshKit.sphere(0.016, 6, 3), MeshKit.at(Vector3(x, 0.43, 0.17)), Color(0.08, 0.08, 0.1))
	return st.commit()


static func _frog_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var green := Color(0.44, 0.76, 0.30)
	MeshKit.add_primitive(st, MeshKit.sphere(0.12, 10, 5), MeshKit.at(Vector3(0.0, 0.08, -0.01), Vector3(1.0, 0.7, 1.15)), green)
	MeshKit.add_primitive(st, MeshKit.sphere(0.095, 10, 5), MeshKit.at(Vector3(0.0, 0.12, 0.08), Vector3(1.2, 0.72, 1.0)), green.lightened(0.05))
	for side in [-1.0, 1.0]:
		MeshKit.add_primitive(st, MeshKit.sphere(0.042, 8, 4), MeshKit.at(Vector3(side * 0.06, 0.18, 0.1)), green.lightened(0.1))
		MeshKit.add_primitive(st, MeshKit.sphere(0.024, 6, 3), MeshKit.at(Vector3(side * 0.066, 0.19, 0.13)), Color(0.06, 0.06, 0.08))
		MeshKit.add_primitive(st, MeshKit.sphere(0.065, 8, 4), MeshKit.at(Vector3(side * 0.11, 0.04, -0.06), Vector3(0.8, 0.55, 1.4)), green.darkened(0.08))
		MeshKit.add_primitive(st, MeshKit.sphere(0.03, 6, 3), MeshKit.at(Vector3(side * 0.09, 0.02, 0.13), Vector3(1.2, 0.5, 1.2)), green.darkened(0.05))
		MeshKit.add_primitive(st, MeshKit.sphere(0.018, 6, 3), MeshKit.at(Vector3(side * 0.04, 0.14, 0.15)), Color(1.0, 0.62, 0.66))
	return st.commit()


static func _throat_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, MeshKit.sphere(0.05, 8, 4), MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.8, 0.8)), Color(0.98, 0.94, 0.62))
	return st.commit()


static func _turtle_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var skin := Color(0.56, 0.66, 0.40)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.17, 0.17, 0.03, 12), MeshKit.at(Vector3(0.0, 0.035, 0.0), Vector3(1.0, 1.0, 1.2)), Color(0.66, 0.56, 0.34))
	MeshKit.add_primitive(st, MeshKit.sphere(0.16, 12, 6), MeshKit.at(Vector3(0.0, 0.05, 0.0), Vector3(1.0, 0.6, 1.2)), Color(0.33, 0.50, 0.30))
	for spot: Vector3 in [Vector3(0.0, 0.145, 0.0), Vector3(0.0, 0.13, 0.09), Vector3(0.0, 0.13, -0.09), Vector3(0.08, 0.12, 0.0), Vector3(-0.08, 0.12, 0.0)]:
		MeshKit.add_primitive(st, MeshKit.sphere(0.045, 6, 3), MeshKit.at(spot, Vector3(1.0, 0.3, 1.0)), Color(0.48, 0.62, 0.36))
	for x in [-0.13, 0.13]:
		for z in [-0.12, 0.12]:
			MeshKit.add_primitive(st, MeshKit.sphere(0.04, 6, 3), MeshKit.at(Vector3(x, 0.025, z), Vector3(1.2, 0.6, 1.0)), skin)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.025, 0.07, 4), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.03, -0.2)), skin)
	return st.commit()


static func _turtle_head() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, MeshKit.sphere(0.055, 8, 4), MeshKit.at(Vector3.ZERO, Vector3(0.9, 0.85, 1.25)), Color(0.56, 0.66, 0.40))
	for x in [-0.032, 0.032]:
		MeshKit.add_primitive(st, MeshKit.sphere(0.012, 5, 3), MeshKit.at(Vector3(x, 0.02, 0.04)), Color(0.06, 0.06, 0.08))
	return st.commit()


static func _fish_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var orange := Color(1.0, 0.55, 0.22)
	MeshKit.add_primitive(st, MeshKit.sphere(0.1, 10, 5), MeshKit.at(Vector3.ZERO, Vector3(0.55, 0.8, 1.6)), orange)
	MeshKit.add_primitive(st, MeshKit.sphere(0.06, 8, 4), MeshKit.at(Vector3(0.0, 0.03, 0.03), Vector3(0.6, 0.8, 1.5)), Color(1.0, 0.97, 0.92))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.09, 0.14, 4), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(0.25, 1.0, 1.0)), Vector3(0.0, 0.0, -0.2)), orange)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.05, 0.08, 4), Transform3D(Basis.from_scale(Vector3(0.2, 1.0, 1.0)), Vector3(0.0, 0.1, -0.02)), orange)
	for x in [-0.04, 0.04]:
		MeshKit.add_primitive(st, MeshKit.sphere(0.014, 5, 3), MeshKit.at(Vector3(x, 0.025, 0.11)), Color(0.06, 0.06, 0.08))
	return st.commit()


# Wings are tinted and flap in the shader (|x| beyond flap_body).
static func _butterfly_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var dark := Color(0.2, 0.15, 0.12)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.008, 0.011, 0.11, 5), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), dark)
	for side in [-1.0, 1.0]:
		MeshKit.add_primitive(st, MeshKit.sphere(0.06, 8, 3), MeshKit.at(Vector3(side * 0.07, 0.0, 0.025), Vector3(1.0, 0.12, 0.85)), Color.WHITE, true)
		MeshKit.add_primitive(st, MeshKit.sphere(0.045, 8, 3), MeshKit.at(Vector3(side * 0.055, 0.0, -0.035), Vector3(1.0, 0.12, 0.85)), Color(0.92, 0.92, 0.92), true)
		MeshKit.add_primitive(st, MeshKit.sphere(0.016, 6, 3), MeshKit.at(Vector3(side * 0.085, 0.008, 0.03), Vector3(1.0, 0.3, 1.0)), dark)
		MeshKit.add_primitive(st, MeshKit.cylinder(0.002, 0.003, 0.06, 3), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.5) * Basis(Vector3.BACK, side * 0.4), Vector3(side * 0.01, 0.015, 0.075)), dark)
	return st.commit()


static func _dragonfly_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var wing := Color(0.88, 0.95, 1.0)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.008, 0.012, 0.26, 5), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -0.08)), Color.WHITE, true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.022, 8, 4), MeshKit.at(Vector3(0.0, 0.0, 0.06), Vector3(1.0, 0.9, 1.4)), Color.WHITE, true)
	MeshKit.add_primitive(st, MeshKit.sphere(0.024, 8, 4), MeshKit.at(Vector3(0.0, 0.005, 0.1), Vector3(1.3, 1.0, 1.0)), Color(0.15, 0.2, 0.3))
	for side in [-1.0, 1.0]:
		for z in [0.07, 0.035]:
			MeshKit.add_primitive(st, MeshKit.sphere(0.06, 8, 3), MeshKit.at(Vector3(side * 0.075, 0.01, z), Vector3(1.2, 0.05, 0.25)), wing)
	return st.commit()
