extends Node3D

## Static wetland diorama. Water cells are flood-filled from BasinSeed through empty
## GridMap cells with y <= water_level_y (see src/Game/GridMapVoxelizer.cs).

@export var water_level_y := 11

@onready var grid_map: GridMap = $GridMap
@onready var basin_seed: Marker3D = $BasinSeed


func _ready() -> void:
	var guides := get_node_or_null(^"_Guides")
	if guides:
		guides.queue_free()


func get_seed_cell() -> Vector3i:
	return grid_map.local_to_map(grid_map.to_local(basin_seed.global_position))
