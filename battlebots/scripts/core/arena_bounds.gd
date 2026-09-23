class_name ArenaBounds
extends RefCounted
## Shared regular-octagon dimensions; physical scenes use the same inner planes.
const FOUNDRY_HALF := 50.0
const MOON_HALF := 25.0
## Woodland is built for many giant bots: a 240 m octagon.
const WOODLAND_HALF := 120.0
## Lowest roof structure above the floor (m); open-sky arenas have none. The
## Foundry roof is visual only (foundry_visuals.gd trusses from 16.8 m), so
## high presentation cameras must stay below it themselves.
const FOUNDRY_CEILING := 16.5

## Every server-selectable arena.
const IDS := ["foundry", "moon", "woodland"]

static func half_extent(arena_id: String) -> float:
	match arena_id:
		"moon": return MOON_HALF
		"woodland": return WOODLAND_HALF
	return FOUNDRY_HALF

static func ceiling(arena_id: String) -> float:
	return FOUNDRY_CEILING if arena_id == "foundry" else INF

static func contains(point: Vector3, half: float, margin := 0.0) -> bool:
	return maxf(absf(point.x), absf(point.z)) <= half - margin \
		and absf(point.x) + absf(point.z) <= (half - margin) * sqrt(2.0)

static func resize_shell(arena: Node3D, half: float) -> void:
	# Inherited arenas may retain a different size from Foundry. Duplicate shared
	# resources before editing so loading Moon cannot shrink another live world.
	var floor_shape: CollisionShape3D = arena.get_node("Floor/Collision")
	var original_half: float = floor_shape.shape.size.x * 0.5
	if is_equal_approx(original_half, half): return
	floor_shape.shape = floor_shape.shape.duplicate()
	floor_shape.shape.size = Vector3(half * 2, 1, half * 2)
	var floor_mesh := arena.get_node_or_null("Floor/Mesh") as MeshInstance3D
	if floor_mesh:
		floor_mesh.mesh = floor_mesh.mesh.duplicate()
		floor_mesh.mesh.size = floor_shape.shape.size
	for wall: Node3D in arena.get_node("Walls").get_children():
		wall.position.x *= (half + 0.5) / (original_half + 0.5)
		wall.position.z *= (half + 0.5) / (original_half + 0.5)
		var collision: CollisionShape3D = wall.get_node("Collision")
		collision.shape = collision.shape.duplicate()
		var size: Vector3 = collision.shape.size
		var span := 2.0 * half * tan(PI / 8.0) + 2.0
		if size.x > size.z: size.x = span
		else: size.z = span
		collision.shape.size = size
		var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			mesh.mesh = mesh.mesh.duplicate()
			mesh.mesh.size = size
	for marker: Node3D in arena.get_node("SpawnPoints").get_children():
		marker.position.x *= half / original_half
		marker.position.z *= half / original_half
