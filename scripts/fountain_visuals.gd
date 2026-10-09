extends Node3D

## Visuals for every fountain unit (see fountain_unit_visual.gd), driven by
## SimulationNode.GetFountains(). Units are created and freed by id.

const FountainUnitVisual := preload("res://scripts/fountain_unit_visual.gd")

@export var max_lpm := 3000.0
@export var spray_height := 7.0  # render units (vertical exaggeration applies)

var _units := {}  # id -> FountainUnitVisual
var _clip_rect := Vector4(-1.0e6, -1.0e6, 1.0e6, 1.0e6)
var _slice_enabled := false
var _slice_plane := 0.0
var _slice_flip := false


## Clips the pump-zone rings to the level footprint (GridMap cells).
func set_bounds(origin: Vector3i, size: Vector3i) -> void:
	_clip_rect = Vector4(origin.x, origin.z, origin.x + size.x, origin.z + size.z)
	for unit: FountainUnitVisual in _units.values():
		unit.set_clip_rect(_clip_rect)


## Mirrors slice_controller.gd so the number badges hide with the parts they label.
func set_slice(enabled: bool, cell_x: int, flip: bool) -> void:
	_slice_enabled = enabled
	_slice_plane = float(cell_x) if flip else float(cell_x + 1)
	_slice_flip = flip
	_update_badges()


func update_units(units: Array, surface_y: float, selected_id: int) -> void:
	var seen := {}
	for i in units.size():
		var info: Dictionary = units[i]
		var id: int = info.id
		seen[id] = true
		var unit: FountainUnitVisual = _units.get(id)
		if unit == null:
			unit = FountainUnitVisual.new()
			unit.name = "Unit%d" % id
			unit.max_lpm = max_lpm
			unit.spray_height = spray_height
			add_child(unit)
			unit.set_clip_rect(_clip_rect)
			_units[id] = unit
		unit.update_from(info, surface_y, i + 1, id == selected_id)
	for id: int in _units.keys():
		if not seen.has(id):
			_units[id].queue_free()
			_units.erase(id)
	_update_badges()


func get_unit_count() -> int:
	return _units.size()


func _update_badges() -> void:
	for unit: FountainUnitVisual in _units.values():
		var cut := _slice_enabled and (unit.badge_x < _slice_plane if _slice_flip else unit.badge_x > _slice_plane)
		unit.set_badge_shown(not cut)
