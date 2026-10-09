extends Node3D

## Whole-cell X cross-section. Drives the slice_* global shader uniforms used by
## terrain_clip.gdshader and do_voxel.gdshader, and shows an orange frame at the cut.

@export var frame_color := Color(1.0, 0.55, 0.1)
@export var frame_thickness := 0.15
## Optional box under the level (BoxMesh) trimmed to the visible side of the cut.
@export var plinth: MeshInstance3D

var enabled := false
var cell_x := 0
var flip := false

var _frame: Array[MeshInstance3D] = []
var _y_range := Vector2(0.0, 14.0)
var _z_range := Vector2(0.0, 64.0)
var _plinth_x := Vector2.ZERO


func _ready() -> void:
	if plinth:
		var half := (plinth.mesh as BoxMesh).size.x * 0.5
		_plinth_x = Vector2(plinth.position.x - half, plinth.position.x + half)
	var material := StandardMaterial3D.new()
	material.albedo_color = frame_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 4:
		var bar := MeshInstance3D.new()
		bar.mesh = BoxMesh.new()
		bar.material_override = material
		add_child(bar)
		_frame.append(bar)
	_apply()


## Grid origin and size come from SimulationNode (GridMap coordinates).
func configure(origin: Vector3i, size: Vector3i) -> void:
	_y_range = Vector2(origin.y, origin.y + size.y)
	_z_range = Vector2(origin.z, origin.z + size.z)
	cell_x = origin.x + size.x / 2
	_apply()


func set_slice(new_enabled: bool, new_cell_x: int, new_flip: bool) -> void:
	enabled = new_enabled
	cell_x = new_cell_x
	flip = new_flip
	_apply()


func _apply() -> void:
	# Cells are cut by their centre x, so the plane sits on a cell boundary: column cell_x
	# stays visible and everything beyond it (or before it, when flipped) disappears.
	var plane_x := float(cell_x) if flip else float(cell_x + 1)
	RenderingServer.global_shader_parameter_set("slice_x", plane_x if enabled else 1.0e6)
	RenderingServer.global_shader_parameter_set("slice_enabled", enabled)
	RenderingServer.global_shader_parameter_set("slice_flip", flip)

	if plinth:
		var lo := _plinth_x.x
		var hi := _plinth_x.y
		if enabled:
			lo = plane_x if flip else lo
			hi = hi if flip else plane_x
		plinth.scale.x = (hi - lo) / (_plinth_x.y - _plinth_x.x)
		plinth.position.x = (lo + hi) * 0.5

	visible = enabled
	if _frame.is_empty():
		return
	var t := frame_thickness
	var x := plane_x + (-t if flip else t) * 0.5
	var y_mid := (_y_range.x + _y_range.y) * 0.5
	var z_mid := (_z_range.x + _z_range.y) * 0.5
	var height := _y_range.y - _y_range.x
	var depth := _z_range.y - _z_range.x
	_set_bar(_frame[0], Vector3(x, _y_range.x, z_mid), Vector3(t, t, depth + t))
	_set_bar(_frame[1], Vector3(x, _y_range.y, z_mid), Vector3(t, t, depth + t))
	_set_bar(_frame[2], Vector3(x, y_mid, _z_range.x), Vector3(t, height + t, t))
	_set_bar(_frame[3], Vector3(x, y_mid, _z_range.y), Vector3(t, height + t, t))


func _set_bar(bar: MeshInstance3D, center: Vector3, bar_size: Vector3) -> void:
	bar.position = center
	(bar.mesh as BoxMesh).size = bar_size
