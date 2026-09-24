extends Node3D
## Deterministic shared lunar collision. No UI, camera, preference or random state.
const GRID := 81
const STEP := 50.0 / (GRID-1)
const ROCKS := [Vector3(21,0,7),Vector3(-21,0,-7),Vector3(7,0,-21),Vector3(-7,0,21)]
const ARENA_SPAWNS = preload("res://scripts/core/arena_spawns.gd")
static var _spawns := PackedVector2Array()

func _enter_tree() -> void:
	# Moon inherits the shell but keeps its authored 50m terrain/spawn contract.
	ArenaBounds.resize_shell(self, ArenaBounds.MOON_HALF)
	ARENA_SPAWNS.settings().place_markers(self, "moon")

static func height_at(x: float, z: float) -> float:
	var radius := Vector2(x,z).length()
	var h := (0.32+sin(x*0.43)*cos(z*0.37)*0.18+sin(x*0.21+z*0.29)*0.08)*smoothstep(7.0,14.0,radius)
	# Level pads under every team and free-for-all start (data/arena_spawns.json).
	if _spawns.is_empty(): _spawns = ARENA_SPAWNS.settings().points("moon")
	for spawn: Vector2 in _spawns:
		h *= smoothstep(2.0,3.0,Vector2(x,z).distance_to(spawn))
	return maxf(0,h)

func _ready() -> void:
	var heights := PackedFloat32Array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z: int in range(GRID):
		for x: int in range(GRID):
			var px := -25+x*STEP
			var pz := -25+z*STEP
			var h := height_at(px,pz)
			heights.append(h)
			vertices.append(Vector3(px,h,pz))
			normals.append(Vector3(height_at(px-0.05,pz)-height_at(px+0.05,pz),0.1,height_at(px,pz-0.05)-height_at(px,pz+0.05)).normalized())
	for z: int in range(GRID-1):
		for x: int in range(GRID-1):
			var a := z*GRID+x
			indices.append_array(PackedInt32Array([a,a+1,a+GRID,a+1,a+GRID+1,a+GRID]))
	var body := StaticBody3D.new()
	body.name = "LunarSurface"
	body.collision_layer = 1
	body.collision_mask = 2
	var collider := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = GRID
	shape.map_depth = GRID
	shape.map_data = heights
	collider.shape = shape
	collider.scale = Vector3(STEP,1,STEP)
	body.add_child(collider)
	# The lunar height field replaces the slab's top, retaining the slab below as a
	# catch surface. Move it down slightly so coplanar contact cannot alternate.
	get_node("Floor").position.y = -0.55
	var old_mesh := get_node_or_null("Floor/Mesh") as MeshInstance3D
	if old_mesh:
		old_mesh.hide()
	if DisplayServer.get_name() != "headless":
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := preload("res://scripts/arena/lunar_materials.gd").ground(true)
		mesh.surface_set_material(0,material)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		body.add_child(visual)
	add_child(body)
	for at: Vector3 in ROCKS:
		var rock := StaticBody3D.new()
		rock.name = "SurfaceRock%d" % get_child_count()
		rock.collision_layer = 1
		rock.collision_mask = 2
		rock.position = at+Vector3(0,height_at(at.x,at.z)+0.11,0)
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.22
		collision.shape = sphere
		rock.add_child(collision)
		if DisplayServer.get_name() != "headless":
			var mesh := SphereMesh.new()
			mesh.radius = 0.22
			mesh.height = 0.44
			mesh.radial_segments = 8
			mesh.rings = 4
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.31,0.32,0.33)
			material.roughness = 1
			mesh.material = material
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			rock.add_child(visual)
		add_child(rock)
