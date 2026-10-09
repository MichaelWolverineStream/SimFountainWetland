extends Node

## Click-to-place tool for a fountain's pump (column bottom) and sprayer (column top). It only
## picks water columns; main.gd decides what a click does. Plain clicks outside placement mode
## emit column_clicked for selecting units.
## Assumes the Level sits at the world origin, so world x/z map directly to GridMap columns.

enum Mode { NONE, PUMP, SPRAYER }

signal placed(kind: Mode, column: Vector2i)
signal mode_changed(kind: Mode)
signal cancelled(kind: Mode)
signal column_clicked(column: Vector2i)

@export var simulation: Node
@export var camera: Camera3D

## Optional extra rule: func(kind: Mode, column: Vector2i) -> bool (e.g. column already in use).
var is_valid := Callable()
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
		if event is InputEventMouseButton and event.is_action_pressed("place") \
				and not (event.alt_pressed or event.shift_pressed):
			var column: Variant = _pick_column(event.position)
			if column != null and simulation.IsWaterColumn(column.x, column.y):
				column_clicked.emit(column)
		return
	if event.is_action_pressed("cancel"):
		var kind := mode
		set_mode(Mode.NONE)
		get_viewport().set_input_as_handled()
		cancelled.emit(kind)
	elif event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.is_action_pressed("place"):
		# Option/Alt or Shift + left drag belongs to the camera.
		if event.alt_pressed or event.shift_pressed:
			return
		_update_hover(event.position)
		get_viewport().set_input_as_handled()
		if not _hover_valid:
			return
		var kind := mode
		set_mode(Mode.NONE)
		placed.emit(kind, _hover)


func _pick_column(screen_position: Vector2) -> Variant:
	var plane := Plane(Vector3.UP, simulation.GetWaterSurfaceY())
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if hit == null:
		return null
	var point := hit as Vector3
	return Vector2i(floori(point.x), floori(point.z))


func _update_hover(screen_position: Vector2) -> void:
	var column: Variant = _pick_column(screen_position)
	if column == null:
		_cursor.visible = false
		_hover_valid = false
		return
	var surface_y: float = simulation.GetWaterSurfaceY()
	_hover = column
	_hover_valid = simulation.IsWaterColumn(_hover.x, _hover.y) and (is_valid.is_null() or is_valid.call(mode, _hover))
	_cursor_material.albedo_color = Color(0.2, 1.0, 0.4, 0.6) if _hover_valid else Color(1.0, 0.2, 0.2, 0.6)
	_cursor.position = Vector3(_hover.x + 0.5, surface_y + 0.05, _hover.y + 0.5)
	_cursor.visible = true
