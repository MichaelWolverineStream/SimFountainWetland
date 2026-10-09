extends Node3D

## A mother duck and her ducklings paddling around the basin. The mother wanders over water
## columns and steers clear of the shore and the fountain; the ducklings follow her trail.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const TRAIL_STEP := 0.1
const LOOKAHEAD := 1.6

@export var simulation: Node
@export var duckling_count := 4
@export var speed := 1.1
@export var duckling_spacing := 0.8
@export var avoid_radius := 2.5
@export var random_seed := 3

var _rng := RandomNumberGenerator.new()
var _ducks: Array[MeshInstance3D] = []  # mother first
var _position := Vector2.ZERO  # x/z of the mother
var _heading := 0.0  # radians, 0 = +Z
var _turn := 0.0
var _turn_timer := 0.0
var _trail: Array[Vector2] = []  # newest first, TRAIL_STEP apart
var _avoid := PackedVector2Array()
var _surface_y := 0.0
var _time := 0.0


func _ready() -> void:
	if simulation == null or not simulation.IsLoaded:
		return
	_rng.seed = random_seed
	_surface_y = simulation.GetWaterSurfaceY()
	var material := MeshKit.decor_material()
	var mother := _duck_mesh(Color(0.98, 0.97, 0.92))
	var duckling := _duck_mesh(Color(1.0, 0.86, 0.35))
	for i in duckling_count + 1:
		var duck := MeshInstance3D.new()
		duck.mesh = mother if i == 0 else duckling
		duck.material_override = material
		duck.scale = Vector3.ONE * (1.0 if i == 0 else 0.55)
		add_child(duck)
		_ducks.append(duck)
	_position = _find_start()
	_heading = _rng.randf() * TAU
	_trail.clear()
	_trail.append(_position)
	_process(0.0)


func set_avoid(points: PackedVector2Array) -> void:
	_avoid = points


func _process(delta: float) -> void:
	if _ducks.is_empty():
		return
	_time += delta
	_steer(delta)
	var step := _dir(_heading) * speed * delta
	if _is_water(_position + step):
		_position += step
	if _trail[0].distance_to(_position) >= TRAIL_STEP:
		_trail.push_front(_position)
		var keep := int(ceil((duckling_count + 1) * duckling_spacing / TRAIL_STEP)) + 2
		if _trail.size() > keep:
			_trail.resize(keep)

	_place(_ducks[0], _position, _heading, 0)
	for i in range(1, _ducks.size()):
		var at := mini(roundi(i * duckling_spacing / TRAIL_STEP), _trail.size() - 1)
		var ahead := _trail[maxi(at - 1, 0)]
		var heading := _heading if at == 0 else atan2(ahead.x - _trail[at].x, ahead.y - _trail[at].y)
		_place(_ducks[i], _trail[at], heading, i)


func _steer(delta: float) -> void:
	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_turn = _rng.randf_range(-0.8, 0.8)
		_turn_timer = _rng.randf_range(1.5, 4.0)
	if _blocked(_position + _dir(_heading) * LOOKAHEAD):
		if not _blocked(_position + _dir(_heading + 0.7) * LOOKAHEAD):
			_heading += 2.4 * delta
		elif not _blocked(_position + _dir(_heading - 0.7) * LOOKAHEAD):
			_heading -= 2.4 * delta
		else:
			_heading += 3.5 * delta
	else:
		_heading += _turn * delta


func _place(duck: MeshInstance3D, at: Vector2, heading: float, index: int) -> void:
	var bob := sin(_time * 3.0 + index * 1.3) * 0.025
	duck.position = Vector3(at.x, _surface_y + 0.01 + bob, at.y)
	duck.rotation = Vector3(0.0, heading, sin(_time * 2.2 + index) * 0.06)


func _blocked(p: Vector2) -> bool:
	if not _is_water(p):
		return true
	for point in _avoid:
		if p.distance_to(point) < avoid_radius:
			return true
	return false


func _is_water(p: Vector2) -> bool:
	return simulation.IsWaterColumn(floori(p.x), floori(p.y))


func _dir(heading: float) -> Vector2:
	return Vector2(sin(heading), cos(heading))


# A random water column with open water all around it.
func _find_start() -> Vector2:
	var origin: Vector3i = simulation.GetGridOrigin()
	var size: Vector3i = simulation.GetGridSize()
	var open: Array[Vector2] = []
	for z in range(origin.z + 2, origin.z + size.z - 2):
		for x in range(origin.x + 2, origin.x + size.x - 2):
			var all_water := true
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if not simulation.IsWaterColumn(x + dx, z + dz):
						all_water = false
						break
				if not all_water:
					break
			if all_water:
				open.append(Vector2(x + 0.5, z + 0.5))
	if open.is_empty():
		return Vector2(origin.x + size.x * 0.5, origin.z + size.z * 0.5)
	return open[_rng.randi() % open.size()]


# Low-poly duck facing +Z with its waterline at y = 0.
static func _duck_mesh(body: Color) -> ArrayMesh:
	var st := MeshKit.begin()
	var beak := Color(1.0, 0.58, 0.15)
	MeshKit.add_primitive(st, MeshKit.sphere(0.28, 12, 6), MeshKit.at(Vector3(0.0, 0.1, 0.0), Vector3(0.8, 0.62, 1.1)), body)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.0, 0.09, 0.2, 6), Transform3D(Basis(Vector3.RIGHT, -1.0), Vector3(0.0, 0.2, -0.3)), body)
	MeshKit.add_primitive(st, MeshKit.sphere(0.15, 10, 5), MeshKit.at(Vector3(0.0, 0.37, 0.2)), body)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.035, 0.06, 0.13, 6), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.35, 0.37)), beak)
	for side in [-1.0, 1.0]:
		MeshKit.add_primitive(st, MeshKit.sphere(0.025, 6, 3), MeshKit.at(Vector3(side * 0.085, 0.41, 0.31)), Color(0.08, 0.08, 0.1))
	return st.commit()
