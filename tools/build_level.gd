extends SceneTree

## Generates assets/tiles.tres (MeshLibrary) and scenes/level_wetland.tscn from a layout
## traced off _design/aerial_photo.jpeg. The output is a starting point for hand editing
## in the GridMap editor; re-running overwrites both files.
##
## Run: godot --headless --path . --script res://tools/build_level.gd [-- --preview /tmp/level.png]

const SIZE_X := 96
const SIZE_Z := 64
const GROUND_Y := 12
const WATER_LEVEL_Y := 11
const MAX_DEPTH := 10
const PHOTO := Vector2(1023.0, 597.0)

const TILES_PATH := "res://assets/tiles.tres"
const LEVEL_PATH := "res://scenes/level_wetland.tscn"
const SHADER_PATH := "res://shaders/terrain_clip.gdshader"
const LEVEL_SCRIPT_PATH := "res://scripts/level_wetland.gd"
const GUIDE_PATH := "res://assets/guides/aerial_photo.jpeg"

enum Tile { GRASS, MEADOW, FIELD, SOIL, MUD, ISLAND, PATH, HEDGE, ROAD, POND }

const TILE_COLORS := {
	Tile.GRASS: Color(0.36, 0.60, 0.24),
	Tile.MEADOW: Color(0.47, 0.70, 0.30),
	Tile.FIELD: Color(0.52, 0.42, 0.30),
	Tile.SOIL: Color(0.38, 0.25, 0.16),
	Tile.MUD: Color(0.13, 0.11, 0.10),
	Tile.ISLAND: Color(0.52, 0.62, 0.33),
	Tile.PATH: Color(0.66, 0.62, 0.54),
	Tile.HEDGE: Color(0.15, 0.36, 0.15),
	Tile.ROAD: Color(0.30, 0.30, 0.32),
	Tile.POND: Color(0.22, 0.42, 0.62),
}

# Traced in photo pixels (1023 x 597).
const BASIN_PX: Array[Vector2] = [
	Vector2(205, 110), Vector2(240, 100), Vector2(330, 105), Vector2(450, 115),
	Vector2(560, 125), Vector2(680, 140), Vector2(790, 160), Vector2(860, 175),
	Vector2(885, 205), Vector2(888, 245), Vector2(870, 275), Vector2(830, 305),
	Vector2(805, 335), Vector2(798, 400), Vector2(790, 455), Vector2(765, 495),
	Vector2(720, 512), Vector2(640, 505), Vector2(560, 490), Vector2(470, 495),
	Vector2(380, 500), Vector2(305, 492), Vector2(290, 450), Vector2(283, 380),
	Vector2(270, 320), Vector2(240, 270), Vector2(210, 225), Vector2(195, 170),
	Vector2(195, 130),
]

# [centre, radii] ellipses in photo pixels.
const ISLANDS_PX := [
	[Vector2(413, 232), Vector2(64, 28)],
	[Vector2(390, 368), Vector2(42, 36)],
	[Vector2(578, 357), Vector2(52, 52)],
]
const PONDS_PX := [
	[Vector2(985, 320), Vector2(55, 62)],
	[Vector2(935, 470), Vector2(78, 72)],
]

const DEEP_POCKET_PX := Vector2(650, 230)
const DEEP_POCKET_RADIUS_PX := 120.0
const DEEP_POCKET_EXTRA := 2.0
const SHORE_SLOPE := 0.8  # depth layers per cell of distance from shore

const ROAD_A_PX := Vector2(0, 380)
const ROAD_B_PX := Vector2(75, 597)


func _init() -> void:
	var lib := _build_tiles()
	var err := ResourceSaver.save(lib, TILES_PATH)
	if err != OK:
		push_error("Saving %s failed: %s" % [TILES_PATH, error_string(err)])
		quit(1)
		return
	lib = load(TILES_PATH)

	var level := _build_level(lib)
	var packed := PackedScene.new()
	err = packed.pack(level)
	if err == OK:
		err = ResourceSaver.save(packed, LEVEL_PATH)
	level.free()
	if err != OK:
		push_error("Saving %s failed: %s" % [LEVEL_PATH, error_string(err)])
		quit(1)
		return
	print("Wrote %s and %s" % [TILES_PATH, LEVEL_PATH])
	quit()


func _build_tiles() -> MeshLibrary:
	var shader: Shader = load(SHADER_PATH)
	var lib := MeshLibrary.new()
	for tile: int in TILE_COLORS:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("albedo", TILE_COLORS[tile])
		material.set_shader_parameter("roughness", 0.15 if tile == Tile.POND else 0.95)
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = material
		lib.create_item(tile)
		lib.set_item_name(tile, String(Tile.keys()[tile]).capitalize())
		lib.set_item_mesh(tile, mesh)
	return lib


func _build_level(lib: MeshLibrary) -> Node3D:
	var root := Node3D.new()
	root.name = "LevelWetland"
	root.set_script(load(LEVEL_SCRIPT_PATH))
	root.set("water_level_y", WATER_LEVEL_Y)

	var grid := GridMap.new()
	grid.name = "GridMap"
	grid.mesh_library = lib
	grid.cell_size = Vector3.ONE
	root.add_child(grid)
	grid.owner = root

	var basin := PackedByteArray()
	basin.resize(SIZE_X * SIZE_Z)
	var basin_polygon := PackedVector2Array(BASIN_PX)
	for z in SIZE_Z:
		for x in SIZE_X:
			var p := _px(x, z)
			var inside := Geometry2D.is_point_in_polygon(p, basin_polygon) and not _in_any(p, ISLANDS_PX)
			basin[x + SIZE_X * z] = 1 if inside else 0

	var depths := _depths(basin)
	var seed_cell := Vector3i(-1, -1, -1)
	var seed_depth := 0

	for z in SIZE_Z:
		for x in SIZE_X:
			var i := x + SIZE_X * z
			var p := _px(x, z)
			if basin[i] == 1:
				var bed_y := WATER_LEVEL_Y - depths[i]
				for y in bed_y + 1:
					grid.set_cell_item(Vector3i(x, y, z), Tile.MUD if y >= bed_y - 1 else Tile.SOIL)
				if depths[i] > seed_depth:
					seed_depth = depths[i]
					seed_cell = Vector3i(x, WATER_LEVEL_Y, z)
			elif _in_any(p, PONDS_PX):
				for y in WATER_LEVEL_Y:
					grid.set_cell_item(Vector3i(x, y, z), Tile.SOIL)
				grid.set_cell_item(Vector3i(x, WATER_LEVEL_Y, z), Tile.POND)
			else:
				var top := Tile.ISLAND if Geometry2D.is_point_in_polygon(p, basin_polygon) else _land_tile(p)
				for y in GROUND_Y:
					grid.set_cell_item(Vector3i(x, y, z), Tile.SOIL)
				grid.set_cell_item(Vector3i(x, GROUND_Y, z), top)
				if (top == Tile.GRASS or top == Tile.MEADOW) and _is_hedge(x, z, p):
					grid.set_cell_item(Vector3i(x, GROUND_Y + 1, z), Tile.HEDGE)

	var basin_seed := Marker3D.new()
	basin_seed.name = "BasinSeed"
	basin_seed.position = Vector3(seed_cell) + Vector3(0.5, 0.5, 0.5)
	root.add_child(basin_seed)
	basin_seed.owner = root

	_add_guides(root)
	_save_preview(grid, depths)
	print("Basin seed %s, max depth %d layers" % [seed_cell, seed_depth])
	return root


# Optional top-down PNG (8 px per column) for checking the layout without the editor.
func _save_preview(grid: GridMap, depths: PackedInt32Array) -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--preview")
	if at < 0 or at + 1 >= args.size():
		return
	var image := Image.create(SIZE_X, SIZE_Z, false, Image.FORMAT_RGB8)
	for z in SIZE_Z:
		for x in SIZE_X:
			var color := Color(0.2, 0.5, 1.0).darkened(depths[x + SIZE_X * z] / float(MAX_DEPTH) * 0.8)
			for y in range(GROUND_Y + 1, WATER_LEVEL_Y - 1, -1):
				var item := grid.get_cell_item(Vector3i(x, y, z))
				if item != GridMap.INVALID_CELL_ITEM:
					color = TILE_COLORS[item]
					break
			image.set_pixel(x, z, color)
	image.resize(SIZE_X * 8, SIZE_Z * 8, Image.INTERPOLATE_NEAREST)
	image.save_png(args[at + 1])
	print("Preview written to %s" % args[at + 1])


func _add_guides(root: Node3D) -> void:
	var texture := load(GUIDE_PATH) as Texture2D
	if texture == null:
		push_warning("Guide photo not imported; run 'godot --headless --path . --import' first. Skipping _Guides.")
		return
	var guides := Node3D.new()
	guides.name = "_Guides"
	guides.visible = false
	root.add_child(guides)
	guides.owner = root

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color(1, 1, 1, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE_X, SIZE_Z)
	plane.material = material

	var photo := MeshInstance3D.new()
	photo.name = "AerialPhoto"
	photo.mesh = plane
	photo.position = Vector3(SIZE_X * 0.5, GROUND_Y + 2.05, SIZE_Z * 0.5)
	guides.add_child(photo)
	photo.owner = root


# Distance to shore via a two-pass chamfer transform, mapped to depth layers.
func _depths(basin: PackedByteArray) -> PackedInt32Array:
	var dist := PackedFloat32Array()
	dist.resize(SIZE_X * SIZE_Z)
	for i in dist.size():
		dist[i] = INF if basin[i] == 1 else 0.0

	const DIAG := 1.41421356
	for z in SIZE_Z:
		for x in SIZE_X:
			var i := x + SIZE_X * z
			if basin[i] == 0:
				continue
			var d := dist[i]
			d = minf(d, _dist_at(dist, x - 1, z) + 1.0)
			d = minf(d, _dist_at(dist, x, z - 1) + 1.0)
			d = minf(d, _dist_at(dist, x - 1, z - 1) + DIAG)
			d = minf(d, _dist_at(dist, x + 1, z - 1) + DIAG)
			dist[i] = d
	for z in range(SIZE_Z - 1, -1, -1):
		for x in range(SIZE_X - 1, -1, -1):
			var i := x + SIZE_X * z
			if basin[i] == 0:
				continue
			var d := dist[i]
			d = minf(d, _dist_at(dist, x + 1, z) + 1.0)
			d = minf(d, _dist_at(dist, x, z + 1) + 1.0)
			d = minf(d, _dist_at(dist, x + 1, z + 1) + DIAG)
			d = minf(d, _dist_at(dist, x - 1, z + 1) + DIAG)
			dist[i] = d

	var depths := PackedInt32Array()
	depths.resize(SIZE_X * SIZE_Z)
	for z in SIZE_Z:
		for x in SIZE_X:
			var i := x + SIZE_X * z
			if basin[i] == 0:
				continue
			var pocket := (_px(x, z) - DEEP_POCKET_PX) / DEEP_POCKET_RADIUS_PX
			var extra := DEEP_POCKET_EXTRA * exp(-pocket.length_squared())
			depths[i] = clampi(roundi(dist[i] * SHORE_SLOPE + 0.2 + extra), 1, MAX_DEPTH)
	return depths


func _dist_at(dist: PackedFloat32Array, x: int, z: int) -> float:
	if x < 0 or x >= SIZE_X or z < 0 or z >= SIZE_Z:
		return 0.0
	return dist[x + SIZE_X * z]


func _land_tile(p: Vector2) -> Tile:
	if _distance_to_segment(p, ROAD_A_PX, ROAD_B_PX) < 18.0:
		return Tile.ROAD
	if absf(p.y - 68.0) < 5.0 and p.x > 150.0 and p.x < 920.0:
		return Tile.PATH
	if absf(p.x - 912.0) < 6.0 and p.y > 63.0 and p.y < 400.0:
		return Tile.PATH
	if p.y < 62.0:
		return Tile.MEADOW if int(p.x / 32.0) % 2 == 0 else Tile.GRASS
	if p.x < 150.0 and p.y < 360.0:
		return Tile.FIELD
	if p.y > 540.0 and p.x > 85.0 and p.x < 530.0:
		return Tile.FIELD
	return Tile.GRASS


func _is_hedge(x: int, z: int, p: Vector2) -> bool:
	var h := _hash01(x, z)
	if p.x > 935.0 and p.y > 70.0 and p.y < 250.0:
		return h < 0.75
	if p.x > 800.0 and p.x < 870.0 and p.y > 330.0 and p.y < 560.0:
		return h < 0.35
	return false


func _px(x: int, z: int) -> Vector2:
	return Vector2((x + 0.5) / SIZE_X * PHOTO.x, (z + 0.5) / SIZE_Z * PHOTO.y)


func _in_any(p: Vector2, ellipses: Array) -> bool:
	for e: Array in ellipses:
		var q: Vector2 = (p - e[0]) / e[1]
		if q.length_squared() <= 1.0:
			return true
	return false


func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


func _hash01(x: int, z: int) -> float:
	var n := (x * 73856093) ^ (z * 19349663)
	return float(posmod(n, 1000)) / 1000.0
