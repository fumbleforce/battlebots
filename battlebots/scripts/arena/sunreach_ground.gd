extends Node3D
## Shared baked geometry. No renderer resources are loaded by the server.
## Rebuild with art_source/sunreach/build_arena.py; art and collision share vertices.
const ARENA_SPAWNS = preload("res://scripts/core/arena_spawns.gd")
const STEP := 1.0
const CONFIG := "res://data/sunreach/layout.json"
static var _heights := PackedFloat32Array()
class Layout extends RefCounted:
	var half: float
	var grid_step: float
	var wall_height: float
	var water_level: float
	var bridges: Array[Dictionary] = []
	var art: Dictionary

static var _layout: Layout
static var _hulls: Array = []

static func settings() -> Layout:
	if _layout == null:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		assert(data is Dictionary, "Invalid Sunreach configuration")
		var parsed := Layout.new()
		parsed.half = float(data.half)
		parsed.grid_step = float(data.grid_step)
		parsed.wall_height = float(data.wall_height)
		parsed.water_level = float(data.water_level)
		parsed.bridges.assign(data.bridges)
		parsed.art = data.art
		assert(is_finite(parsed.half) and parsed.half > 0.0)
		assert(parsed.grid_step == STEP and parsed.wall_height > 0.0)
		assert(is_finite(parsed.water_level) and parsed.bridges.size() == 2)
		_layout = parsed
	return _layout

static func grid_heights() -> PackedFloat32Array:
	if _heights.is_empty():
		_heights = FileAccess.get_file_as_bytes("res://data/sunreach/heights.bin").to_float32_array()
		var n := roundi(float(settings().half) * 2.0 / STEP) + 1
		assert(_heights.size() == n * n, "Sunreach terrain bake is incomplete")
	return _heights

static func height_at(x: float, z: float) -> float:
	var half: float = settings().half
	var n := roundi(half * 2.0 / STEP) + 1
	var fx := clampf((x + half) / STEP, 0.0, n - 1.000001)
	var fz := clampf((z + half) / STEP, 0.0, n - 1.000001)
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h := grid_heights()
	var a := h[iz * n + ix]
	var b := h[iz * n + ix + 1]
	var c := h[(iz + 1) * n + ix]
	var d := h[(iz + 1) * n + ix + 1]
	return a + (b - a) * tx + (c - a) * tz if tx + tz < 1.0 else d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)

## Placement height includes the bridge surface for spawned bots and pickups.
static func support_height(x: float, z: float) -> float:
	for bridge: Dictionary in settings().bridges:
		if absf(x - float(bridge.x)) <= float(bridge.width) * 0.5 and absf(z - float(bridge.z)) <= float(bridge.length) * 0.5:
			return float(bridge.deck_height)
	return height_at(x, z)

func _enter_tree() -> void:
	var cfg := settings()
	ArenaBounds.resize_shell(self, float(cfg.half))
	ARENA_SPAWNS.settings().place_markers(self, "sunreach")
	for wall: Node3D in get_node("Walls").get_children():
		var shape: CollisionShape3D = wall.get_node("Collision")
		shape.shape = shape.shape.duplicate()
		shape.shape.size.y = float(cfg.wall_height)
		wall.position.y = float(cfg.wall_height) * 0.5

func _ready() -> void:
	get_node("Floor").position.y = -6.0
	var slab := get_node_or_null("Floor/Mesh") as MeshInstance3D
	if slab: slab.hide()
	var terrain := StaticBody3D.new()
	terrain.name = "SunreachTerrain"
	terrain.collision_layer = 1
	terrain.collision_mask = 2
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = roundi(float(settings().half) * 2.0 / STEP) + 1
	shape.map_depth = shape.map_width
	shape.map_data = grid_heights()
	collision.shape = shape
	collision.scale = Vector3(STEP, 1, STEP)
	terrain.add_child(collision)
	add_child(terrain)
	if _hulls.is_empty():
		_hulls = JSON.parse_string(FileAccess.get_file_as_string("res://data/sunreach/collision.json"))
	var obstacles := StaticBody3D.new()
	obstacles.name = "SunreachStructures"
	obstacles.collision_layer = 1
	obstacles.collision_mask = 2
	for entry: Dictionary in _hulls:
		var hull := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for point: Array in entry.points:
			points.append(Vector3(point[0], point[1], point[2]))
		hull.points = points
		var part := CollisionShape3D.new()
		part.name = entry.name
		part.shape = hull
		obstacles.add_child(part)
	add_child(obstacles)
