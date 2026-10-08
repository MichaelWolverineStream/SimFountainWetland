extends Node

## Click-to-place tool for the pump (column bottom) and sprayer (column top).
## Assumes the Level sits at the world origin, so world x/z map directly to GridMap columns.

enum Mode { NONE, PUMP, SPRAYER }

signal placed(kind: Mode, column: Vector2i)
signal mode_changed(kind: Mode)

@export var simulation: Node
@export var camera: Camera3D

var mode := Mode.NONE

var _cursor: MeshInstance3D
var _cursor_material: StandardMaterial3D
var _hover := Vector2i(-1, -1)
var _hover_valid := false


func _ready() -> void:
	_cursor_material = StandardMaterial3D.new()
	_cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor_material.no_depth_test = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.08, 1.0)
	mesh.material = _cursor_material
	_cursor = MeshInstance3D.new()
	_cursor.mesh = mesh
	_cursor.visible = false
	add_child(_cursor)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_cursor.visible = false
	mode_changed.emit(mode)


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.NONE:
		return
	if event.is_action_pressed("cancel"):
		set_mode(Mode.NONE)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.is_action_pressed("place"):
		_update_hover(event.position)
		get_viewport().set_input_as_handled()
		if not _hover_valid:
			return
		var ok: bool
		if mode == Mode.PUMP:
			ok = simulation.PlacePump(_hover.x, _hover.y)
		else:
			ok = simulation.PlaceSprayer(_hover.x, _hover.y)
		if ok:
			var kind := mode
			set_mode(Mode.NONE)
			placed.emit(kind, _hover)


func _update_hover(screen_position: Vector2) -> void:
	var surface_y: float = simulation.GetWaterSurfaceY()
	var plane := Plane(Vector3.UP, surface_y)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if hit == null:
		_cursor.visible = false
		_hover_valid = false
		return
	var point := hit as Vector3
	_hover = Vector2i(floori(point.x), floori(point.z))
	_hover_valid = simulation.IsWaterColumn(_hover.x, _hover.y)
	_cursor_material.albedo_color = Color(0.2, 1.0, 0.4, 0.6) if _hover_valid else Color(1.0, 0.2, 0.2, 0.6)
	_cursor.position = Vector3(_hover.x + 0.5, surface_y + 0.05, _hover.y + 0.5)
	_cursor.visible = true
