extends Node3D

## One pump + buoy sprayer unit: parts, pipe, spray, splash ripples, pump-zone ring, upwelling
## foam and a number badge. Meshes and the spray process are shared by all units.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const PIPE_RADIUS := 0.15
const PIPE_Y := 0.08  # pipe centre above the water surface
const PIPE_COLOR := Color(0.66, 0.74, 0.80)
const RING_SELECTED := Color(1.0, 0.82, 0.3)
const RING_IDLE := Color(0.92, 0.97, 1.0)
const BADGE_SELECTED := Color(1.0, 0.86, 0.4)
const BADGE_IDLE := Color(1.0, 1.0, 1.0)

static var _shared := {}

var max_lpm := 3000.0
var spray_height := 7.0  # render units (vertical exaggeration applies)
var selected := false
var badge_x := 0.0

var _pump: MeshInstance3D
var _sprayer: MeshInstance3D
var _riser: MeshInstance3D
var _run: MeshInstance3D
var _elbow: MeshInstance3D
var _zone_ring: MeshInstance3D
var _ring_mesh: TorusMesh
var _ring_material: ShaderMaterial
var _spray: GPUParticles3D
var _splash: GPUParticles3D
var _splash_process: ParticleProcessMaterial
var _upwell: GPUParticles3D
var _upwell_process: ParticleProcessMaterial
var _badge: Label3D
var _time := 0.0


func _ready() -> void:
	var shared := _get_shared(spray_height)
	var material: ShaderMaterial = shared.material
	_pump = _part(shared.pump, material)
	_sprayer = _part(shared.buoy, material)
	_riser = _part(shared.pipe, material)
	_run = _part(shared.pipe, material)
	_elbow = _part(shared.elbow, material)

	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.94
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 64
	_ring_mesh.ring_segments = 4
	_ring_material = MeshKit.particle_material(Color(RING_IDLE, 0.3), 1.0, 0.0, false, false)
	_ring_material.set_shader_parameter("clip_pixels", true)
	_zone_ring = _part(_ring_mesh, _ring_material)
	_zone_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_spray = _make_spray(shared)
	_splash = _make_splash(shared)
	_upwell = _make_upwell(shared)
	for particles: GPUParticles3D in [_spray, _splash, _upwell]:
		particles.emitting = false
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(particles)

	_badge = Label3D.new()
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.no_depth_test = true
	_badge.fixed_size = false
	_badge.font_size = 96
	_badge.pixel_size = 0.012
	_badge.outline_size = 28
	_badge.outline_modulate = Color(0.12, 0.16, 0.24, 0.9)
	_badge.render_priority = 2
	_badge.outline_render_priority = 1
	_badge.visible = false
	add_child(_badge)


func _process(delta: float) -> void:
	if not _zone_ring.visible or not selected:
		return
	_time += delta
	_ring_material.set_shader_parameter("color", Color(RING_SELECTED, 0.45 + 0.2 * sin(_time * 2.5)))


func set_clip_rect(rect: Vector4) -> void:
	_ring_material.set_shader_parameter("clip_rect", rect)


func update_from(info: Dictionary, surface_y: float, number: int, is_selected: bool) -> void:
	selected = is_selected
	var has_pump: bool = info.get("has_pump", false)
	var has_sprayer: bool = info.get("has_sprayer", false)
	var pump: Vector3 = info.get("pump_position", Vector3.ZERO)
	var sprayer: Vector3 = info.get("sprayer_position", Vector3.ZERO)
	var active: bool = info.get("active", false)
	var ratio := clampf(float(info.get("lpm", 0.0)) / max_lpm, 0.05, 1.0)

	_pump.visible = has_pump
	_pump.position = pump
	_sprayer.visible = has_sprayer
	_sprayer.position = Vector3(sprayer.x, surface_y, sprayer.z)

	var connected := has_pump and has_sprayer
	_riser.visible = connected
	_run.visible = connected
	_elbow.visible = connected
	if connected:
		var top := Vector3(pump.x, surface_y + PIPE_Y, pump.z)
		_place_segment(_riser, pump + Vector3(0.0, 0.45, 0.0), top)
		_place_segment(_run, top, Vector3(sprayer.x, surface_y + PIPE_Y, sprayer.z))
		_elbow.position = top

	_spray.position = Vector3(sprayer.x, surface_y + 0.4, sprayer.z)
	_spray.emitting = active
	_spray.amount_ratio = ratio
	_splash.position = Vector3(sprayer.x, surface_y + 0.03, sprayer.z)
	_splash.emitting = active
	_splash.amount_ratio = ratio
	var spray_radius := maxf(float(info.get("spray_radius", 3.0)), 1.5)
	_splash_process.emission_ring_radius = spray_radius
	_splash_process.emission_ring_inner_radius = spray_radius * 0.35

	var zone: float = info.get("pump_zone_radius", 1.0)
	_zone_ring.visible = has_pump
	_zone_ring.position = Vector3(pump.x, surface_y + 0.06, pump.z)
	_zone_ring.scale = Vector3(zone, 1.0, zone)
	# Keep the band about 0.3 cells wide whatever the radius.
	_ring_mesh.inner_radius = 1.0 - clampf(0.3 / maxf(zone, 0.1), 0.005, 0.3)
	if not selected:
		_ring_material.set_shader_parameter("color", Color(RING_IDLE, 0.3))
	_upwell.position = Vector3(pump.x, surface_y + 0.05, pump.z)
	_upwell.emitting = active
	_upwell_process.emission_ring_radius = maxf(zone * 0.8, 0.5)

	var anchor := sprayer if has_sprayer else pump
	_badge.position = Vector3(anchor.x, surface_y + 1.6, anchor.z)
	_badge.text = str(number)
	_badge.modulate = BADGE_SELECTED if selected else BADGE_IDLE
	_badge.scale = Vector3.ONE * (1.25 if selected else 1.0)
	badge_x = anchor.x
	_badge.visible = has_pump or has_sprayer


func set_badge_shown(shown: bool) -> void:
	_badge.visible = shown and (_pump.visible or _sprayer.visible)


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


func _part(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.visible = false
	add_child(instance)
	return instance


# ---- Shared resources ----

static func _get_shared(height: float) -> Dictionary:
	if not _shared.is_empty():
		return _shared
	_shared.material = MeshKit.decor_material()
	_shared.pump = _pump_mesh()
	_shared.buoy = _buoy_mesh()
	_shared.pipe = _solid(MeshKit.cylinder(PIPE_RADIUS, PIPE_RADIUS, 1.0, 10), PIPE_COLOR)
	_shared.elbow = _solid(MeshKit.sphere(PIPE_RADIUS * 1.25), PIPE_COLOR)

	var spray := ParticleProcessMaterial.new()
	spray.direction = Vector3.UP
	spray.spread = 14.0
	var speed := sqrt(2.0 * 9.8 * height)
	spray.initial_velocity_min = speed * 0.85
	spray.initial_velocity_max = speed
	spray.gravity = Vector3(0.0, -9.8, 0.0)
	spray.scale_min = 0.6
	spray.scale_max = 1.4
	spray.color_ramp = MeshKit.fade_ramp(0.9, 0.05, 0.8)
	_shared.spray_process = spray
	_shared.spray_lifetime = 2.0 * speed / 9.8
	var drop := QuadMesh.new()
	drop.size = Vector2(0.22, 0.22)
	drop.material = MeshKit.particle_material(Color(0.82, 0.95, 1.0), 1.3)
	_shared.drop = drop

	var ring := TorusMesh.new()
	ring.inner_radius = 0.82
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 3
	_shared.splash_ring = ring
	_shared.splash_material = MeshKit.particle_material(Color(1.0, 1.0, 1.0, 0.7), 1.1, 0.0, false, false)
	_shared.splash_ramp = MeshKit.fade_ramp(0.8, 0.1, 0.35)
	_shared.splash_curve = _grow_curve(0.2)

	var bubble := QuadMesh.new()
	bubble.size = Vector2(0.2, 0.2)
	bubble.material = MeshKit.particle_material(Color(0.92, 0.98, 1.0), 1.15)
	_shared.bubble = bubble
	_shared.upwell_ramp = MeshKit.fade_ramp(0.75, 0.15, 0.5)
	_shared.upwell_curve = _grow_curve(0.4)
	return _shared


static func _solid(primitive: PrimitiveMesh, color: Color) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.add_primitive(st, primitive, Transform3D.IDENTITY, color)
	return st.commit()


# Chunky orange pump centred on its cell.
static func _pump_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var body := CapsuleMesh.new()
	body.radius = 0.3
	body.height = 0.9
	body.radial_segments = 12
	body.rings = 4
	var band := Color(0.32, 0.34, 0.4)
	MeshKit.add_primitive(st, body, Transform3D.IDENTITY, Color(1.0, 0.56, 0.22))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.33, 0.33, 0.12, 12), MeshKit.at(Vector3(0.0, -0.12, 0.0)), band)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.33, 0.33, 0.06, 12), MeshKit.at(Vector3(0.0, 0.1, 0.0)), band)
	MeshKit.add_primitive(st, MeshKit.cylinder(0.12, 0.16, 0.12, 10), MeshKit.at(Vector3(0.0, 0.47, 0.0)), PIPE_COLOR)
	return st.commit()


# Floating buoy with a nozzle; origin at the water surface.
static func _buoy_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var float_ring := TorusMesh.new()
	float_ring.inner_radius = 0.3
	float_ring.outer_radius = 0.58
	float_ring.rings = 20
	float_ring.ring_segments = 10
	MeshKit.add_primitive(st, float_ring, MeshKit.at(Vector3(0.0, 0.03, 0.0)), Color(1.0, 0.46, 0.42))
	MeshKit.add_primitive(st, MeshKit.sphere(0.32, 14, 7), MeshKit.at(Vector3(0.0, 0.04, 0.0), Vector3(1.0, 0.62, 1.0)), Color(0.96, 0.97, 0.99))
	MeshKit.add_primitive(st, MeshKit.cylinder(0.06, 0.1, 0.22, 10), MeshKit.at(Vector3(0.0, 0.27, 0.0)), PIPE_COLOR)
	for i in 4:
		var angle := TAU * i / 4.0 + PI * 0.25
		MeshKit.add_primitive(st, MeshKit.sphere(0.06, 6, 3), MeshKit.at(Vector3(cos(angle) * 0.44, 0.13, sin(angle) * 0.44)), Color(1.0, 0.92, 0.5))
	return st.commit()


static func _grow_curve(start: float) -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


# ---- Particles ----

func _make_spray(shared: Dictionary) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Spray"
	particles.amount = 500
	particles.lifetime = shared.spray_lifetime
	particles.process_material = shared.spray_process
	particles.draw_pass_1 = shared.drop
	particles.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, spray_height + 4.0, 20))
	return particles


# Ripple rings where the spray lands.
func _make_splash(shared: Dictionary) -> GPUParticles3D:
	_splash_process = ParticleProcessMaterial.new()
	_splash_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_splash_process.emission_ring_axis = Vector3.UP
	_splash_process.emission_ring_height = 0.0
	_splash_process.emission_ring_radius = 3.0
	_splash_process.emission_ring_inner_radius = 1.0
	_splash_process.gravity = Vector3.ZERO
	_splash_process.initial_velocity_min = 0.0
	_splash_process.initial_velocity_max = 0.0
	_splash_process.scale_min = 0.35
	_splash_process.scale_max = 0.75
	_splash_process.scale_curve = shared.splash_curve
	_splash_process.color_ramp = shared.splash_ramp

	var particles := GPUParticles3D.new()
	particles.name = "Splash"
	particles.amount = 48
	particles.lifetime = 1.4
	particles.process_material = _splash_process
	particles.draw_pass_1 = shared.splash_ring
	particles.material_override = shared.splash_material
	particles.visibility_aabb = AABB(Vector3(-10, -1, -10), Vector3(20, 2, 20))
	return particles


# Foam bubbling up over the pump zone.
func _make_upwell(shared: Dictionary) -> GPUParticles3D:
	_upwell_process = ParticleProcessMaterial.new()
	_upwell_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_upwell_process.emission_ring_axis = Vector3.UP
	_upwell_process.emission_ring_height = 0.0
	_upwell_process.emission_ring_radius = 1.0
	_upwell_process.emission_ring_inner_radius = 0.0
	_upwell_process.direction = Vector3.UP
	_upwell_process.spread = 60.0
	_upwell_process.initial_velocity_min = 0.05
	_upwell_process.initial_velocity_max = 0.2
	_upwell_process.gravity = Vector3.ZERO
	_upwell_process.damping_min = 0.2
	_upwell_process.damping_max = 0.4
	_upwell_process.scale_min = 0.5
	_upwell_process.scale_max = 1.2
	_upwell_process.scale_curve = shared.upwell_curve
	_upwell_process.color_ramp = shared.upwell_ramp

	var particles := GPUParticles3D.new()
	particles.name = "Upwell"
	particles.amount = 90
	particles.lifetime = 2.5
	particles.process_material = _upwell_process
	particles.draw_pass_1 = shared.bubble
	particles.visibility_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 3, 16))
	return particles
