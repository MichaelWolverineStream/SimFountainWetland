extends RefCounted

## Helpers for merging low-poly props into one ArrayMesh with SurfaceTool.
## Colours are given in sRGB and stored linear. Vertex alpha 1 marks parts that take the
## per-instance tint (INSTANCE_CUSTOM.rgb) in shaders/decor.gdshader; alpha 0 keeps the colour.

const DECOR_SHADER := preload("res://shaders/decor.gdshader")
const PARTICLE_SHADER := preload("res://shaders/particle.gdshader")


static func decor_material(sway := 0.0, nature_only := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DECOR_SHADER
	material.set_shader_parameter("sway", sway)
	material.set_shader_parameter("nature_only", nature_only)
	return material


static func particle_material(color: Color, energy := 1.0, blink := 0.0, billboard := true, soft_dot := true) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PARTICLE_SHADER
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("energy", energy)
	material.set_shader_parameter("blink", blink)
	material.set_shader_parameter("billboard", billboard)
	material.set_shader_parameter("soft_dot", soft_dot)
	return material


## Alpha fade-in/out ramp for particle colour.
static func fade_ramp(peak_alpha := 1.0, fade_in := 0.15, fade_out := 0.7) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(fade_in, Color(1.0, 1.0, 1.0, peak_alpha))
	gradient.add_point(fade_out, Color(1.0, 1.0, 1.0, peak_alpha))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func add_primitive(st: SurfaceTool, mesh: PrimitiveMesh, xform: Transform3D, color: Color, tinted := false) -> void:
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := xform.basis.inverse().transposed()
	var c := _vertex_color(color, tinted)
	for index in indices:
		st.set_color(c)
		st.set_normal((normal_basis * normals[index]).normalized())
		st.add_vertex(xform * vertices[index])


## A single grass-like blade. Normals point up so blades light like the ground they grow from.
static func add_blade(st: SurfaceTool, base: Vector3, yaw: float, height: float, lean: float, width: float, base_color: Color, tip_color: Color, tinted := true) -> void:
	var side := Vector3(cos(yaw), 0.0, sin(yaw)) * width * 0.5
	var tip := base + Vector3(-sin(yaw) * lean, height, cos(yaw) * lean)
	var bottom := _vertex_color(base_color, tinted)
	var top := _vertex_color(tip_color, tinted)
	for vertex: Array in [[base - side, bottom], [base + side, bottom], [tip, top]]:
		st.set_color(vertex[1])
		st.set_normal(Vector3.UP)
		st.add_vertex(vertex[0])


static func sphere(radius: float, segments := 10, rings := 6) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


static func cylinder(top_radius: float, bottom_radius: float, height: float, segments := 8) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func at(position: Vector3, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_scale(scale), position)


static func _vertex_color(color: Color, tinted: bool) -> Color:
	var c := color.srgb_to_linear()
	c.a = 1.0 if tinted else 0.0
	return c
