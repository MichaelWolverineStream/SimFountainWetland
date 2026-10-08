extends Node3D

## Pump, sprayer, L-shaped pipe, spray particles and pump-zone ring, driven by
## SimulationNode.GetFountainInfo().

@export var max_lpm := 3000.0
@export var spray_height := 7.0  # render units (vertical exaggeration applies)

var _pump: MeshInstance3D
var _sprayer: MeshInstance3D
var _riser: MeshInstance3D
var _run: MeshInstance3D
var _spray: GPUParticles3D
var _zone_ring: MeshInstance3D


func _ready() -> void:
	_pump = _make_mesh(_box(Vector3(0.8, 0.6, 0.8)), Color(0.2, 0.3, 0.75))
	_sprayer = _make_mesh(_cylinder(0.3, 0.6), Color(0.75, 0.75, 0.78))
	_riser = _make_mesh(_cylinder(0.12, 1.0), Color(0.6, 0.6, 0.62))
	_run = _make_mesh(_cylinder(0.12, 1.0), Color(0.6, 0.6, 0.62))
	_zone_ring = _make_mesh(_ring(), Color(1.0, 0.8, 0.2, 0.55), true)
	_spray = _make_spray()
	add_child(_spray)
	update_from({})


func update_from(info: Dictionary) -> void:
	var has_pump: bool = info.get("has_pump", false)
	var has_sprayer: bool = info.get("has_sprayer", false)
	var surface_y: float = info.get("surface_y", 0.0)
	var pump: Vector3 = info.get("pump_position", Vector3.ZERO)
	var sprayer: Vector3 = info.get("sprayer_position", Vector3.ZERO)

	_pump.visible = has_pump
	_pump.position = pump
	_sprayer.visible = has_sprayer
	_sprayer.position = sprayer + Vector3(0.0, 0.8, 0.0)

	var connected := has_pump and has_sprayer
	_riser.visible = connected
	_run.visible = connected
	if connected:
		var top := Vector3(pump.x, surface_y + 0.15, pump.z)
		_place_segment(_riser, pump, top)
		_place_segment(_run, top, Vector3(sprayer.x, surface_y + 0.15, sprayer.z))

	var active: bool = info.get("active", false)
	var lpm: float = info.get("lpm", 0.0)
	_spray.position = sprayer + Vector3(0.0, 1.1, 0.0)
	_spray.emitting = active
	_spray.amount_ratio = clampf(lpm / max_lpm, 0.05, 1.0)

	var radius: float = info.get("pump_zone_radius", 1.0)
	_zone_ring.visible = has_pump
	_zone_ring.position = Vector3(pump.x, surface_y + 0.06, pump.z)
	_zone_ring.scale = Vector3(radius, 1.0, radius)


func _place_segment(segment: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	segment.visible = length > 0.01
	if not segment.visible:
		return
	var y := (b - a) / length
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := y.cross(helper).normalized()
	var z := x.cross(y)
	segment.transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)


func _make_mesh(mesh: Mesh, color: Color, transparent := false) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.visible = false
	add_child(instance)
	return instance


func _make_spray() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 14.0
	var speed := sqrt(2.0 * 9.8 * spray_height)
	process.initial_velocity_min = speed * 0.9
	process.initial_velocity_max = speed
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.2

	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var drop := SphereMesh.new()
	drop.radius = 0.09
	drop.height = 0.18
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = drop_material

	var particles := GPUParticles3D.new()
	particles.amount = 400
	particles.lifetime = 2.0 * speed / 9.8
	particles.process_material = process
	particles.draw_pass_1 = drop
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, spray_height + 4.0, 20))
	return particles


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	return mesh


# Unit-radius ring; scaled in x/z by the pump-zone radius (in cells).
static func _ring() -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.96
	mesh.outer_radius = 1.0
	mesh.rings = 64
	mesh.ring_segments = 4
	return mesh
