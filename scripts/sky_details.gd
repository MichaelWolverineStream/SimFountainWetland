extends Node3D

## Puffy clouds drifting around the diorama (faster in wind, tinted by daylight) and a dome of
## twinkling stars that fades in at night.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const CLOUD_SHADER := preload("res://shaders/cloud.gdshader")
const STAR_SHADER := preload("res://shaders/star.gdshader")
const DAY_CLOUD := Color(1.0, 1.0, 1.0)
const DUSK_CLOUD := Color(1.0, 0.80, 0.72)
const NIGHT_CLOUD := Color(0.36, 0.42, 0.62)
const WIND_SPEED := [0.35, 0.9, 1.8]

@export var simulation: Node
@export var cloud_count := 8
@export var star_count := 420
@export var cloud_height := Vector2(20.0, 30.0)
@export var cloud_margin := 16.0  # cloud lanes stay this far outside the level
@export var drift_reach := 70.0  # clouds wrap this far past the level ends
@export var star_distance := 260.0
@export var random_seed := 13

var _rng := RandomNumberGenerator.new()
var _clouds: Array[Dictionary] = []
var _cloud_material: ShaderMaterial
var _star_material: ShaderMaterial
var _stars: MultiMeshInstance3D
var _center := Vector3.ZERO
var _half := Vector3.ZERO
var _speed: float = WIND_SPEED[0]
var _time := 0.0


func _ready() -> void:
	if simulation == null or not simulation.IsLoaded:
		return
	_rng.seed = random_seed
	var origin: Vector3i = simulation.GetGridOrigin()
	var size: Vector3i = simulation.GetGridSize()
	_half = Vector3(size) * 0.5
	_center = Vector3(origin) + _half
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = CLOUD_SHADER
	_cloud_material.set_shader_parameter("box_min", Vector3(origin) - Vector3(1.0, 4.0, 1.0))
	_cloud_material.set_shader_parameter("box_max", Vector3(origin + size) + Vector3(1.0, 4.0, 1.0))
	_spawn_clouds()
	_spawn_stars()


## 0 calm, 1 breezy, 2 windy.
func set_wind(wind: int) -> void:
	_speed = WIND_SPEED[clampi(wind, 0, WIND_SPEED.size() - 1)]


func set_daylight(daylight: float) -> void:
	if _cloud_material == null:
		return
	var twilight := 1.0 - absf(daylight * 2.0 - 1.0)
	var tint := NIGHT_CLOUD.lerp(DAY_CLOUD, daylight).lerp(DUSK_CLOUD, twilight * 0.6)
	_cloud_material.set_shader_parameter("tint", tint)
	var night := 1.0 - smoothstep(0.1, 0.6, daylight)
	_star_material.set_shader_parameter("visibility", night)
	_stars.visible = night > 0.01


func get_cloud_count() -> int:
	return _clouds.size()


func _process(delta: float) -> void:
	_time += delta
	var span := _half.x + drift_reach
	for cloud in _clouds:
		var node: Node3D = cloud.node
		var x := node.position.x + _speed * float(cloud.speed) * delta
		if x > _center.x + span:
			x -= span * 2.0
		var edge := minf(_center.x + span - x, x - (_center.x - span))
		node.position = Vector3(x, float(cloud.y) + sin(_time * 0.2 + float(cloud.phase)) * 0.4, node.position.z)
		node.scale = Vector3.ONE * float(cloud.scale) * smoothstep(0.0, 18.0, edge)


func _spawn_clouds() -> void:
	var meshes: Array[ArrayMesh] = []
	for i in 3:
		meshes.append(_cloud_mesh(i))
	var span := _half.x + drift_reach
	for i in cloud_count:
		var side := 1.0 if i % 2 == 0 else -1.0
		var lane := _center.z + side * (_half.z + cloud_margin + _rng.randf_range(0.0, 22.0))
		var node := MeshInstance3D.new()
		node.name = "Cloud"
		node.mesh = meshes[i % meshes.size()]
		node.material_override = _cloud_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(_center.x - span + span * 2.0 * (i + _rng.randf_range(0.0, 0.6)) / cloud_count, 0.0, lane)
		node.rotation.y = _rng.randf_range(-0.4, 0.4)
		add_child(node)
		_clouds.append({"node": node, "speed": _rng.randf_range(0.7, 1.3), "y": _rng.randf_range(cloud_height.x, cloud_height.y),
				"phase": _rng.randf() * TAU, "scale": _rng.randf_range(0.8, 1.3)})
	_process(0.0)


func _spawn_stars() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = star_count
	for i in star_count:
		var yaw := _rng.randf() * TAU
		var elevation := asin(_rng.randf_range(0.08, 1.0))
		var direction := Vector3(cos(elevation) * cos(yaw), sin(elevation), cos(elevation) * sin(yaw))
		var star_size := star_distance * _rng.randf_range(0.004, 0.011)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * star_size), _center + direction * star_distance))
		var warmth := _rng.randf()
		multimesh.set_instance_custom_data(i, Color(1.0, 0.92, 0.8).lerp(Color(0.78, 0.86, 1.0), warmth))
	_star_material = ShaderMaterial.new()
	_star_material.shader = STAR_SHADER
	_stars = MultiMeshInstance3D.new()
	_stars.name = "Stars"
	_stars.multimesh = multimesh
	_stars.material_override = _star_material
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.extra_cull_margin = star_distance
	_stars.visible = false
	add_child(_stars)


static func _cloud_mesh(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var st := MeshKit.begin()
	var puffs := 5 + variant * 2
	var length := 5.0 + variant * 2.5
	for i in puffs:
		var t := (i + 0.5) / puffs
		var middle := 1.0 - absf(t * 2.0 - 1.0)
		var radius := lerpf(1.3, 2.6, middle) * rng.randf_range(0.85, 1.15)
		var spot := Vector3((t - 0.5) * length, radius * 0.35 + middle * 0.6, rng.randf_range(-0.9, 0.9))
		var shade := lerpf(0.86, 1.0, clampf(spot.y / 2.0, 0.0, 1.0))
		MeshKit.add_primitive(st, MeshKit.sphere(radius, 14, 8), MeshKit.at(spot, Vector3(1.0, 0.78, 0.9)), Color(shade, shade, shade * 1.02))
	MeshKit.add_primitive(st, MeshKit.sphere(length * 0.5, 16, 6), MeshKit.at(Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.22, 0.42)), Color(0.86, 0.88, 0.92))
	return st.commit()
