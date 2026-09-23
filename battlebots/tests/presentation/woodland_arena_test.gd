extends SceneTree
## Woodland structural regression and reproducible rendered review captures.
## godot --headless --path battlebots --script res://tests/presentation/woodland_arena_test.gd
## godot --path battlebots --script res://tests/presentation/woodland_arena_test.gd -- --capture
const GROUND = preload("res://scripts/arena/woodland_ground.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := AuthorityWorld.new()
	world.arena_id = "woodland"
	root.add_child(world)
	var arena := world.arena
	await physics_frame
	await physics_frame
	check(arena.get_node("SpawnPoints").get_child_count() == 18, "Spawn contract changed")
	check(arena.get_node("Walls").get_child_count() == 8, "Wall contract changed")
	check(ArenaBounds.half_extent("woodland") == 120.0, "Woodland is the 240 m giant-bot octagon")
	var space := arena.get_world_3d().direct_space_state
	for side: int in range(8):
		var direction := Vector3(sin(side * PI / 4 + PI / 8), 0, cos(side * PI / 4 + PI / 8))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 3, 0), direction * 140 + Vector3(0, 1, 0), 1))
		check(not hit.is_empty(), "Missing octagon side %d" % side)
		# Rays between the outcrops reach the wall at the octagon's inner plane.
		if not hit.is_empty() and hit.collider.get_parent().name == "Walls":
			check(Vector2(hit.position.x, hit.position.z).length() > 119.9, "Unexpected obstacle towards side %d: %s at %s" % [side, hit.collider.name, hit.position])
	# Baked load-time data must match the generators (tools/bake_woodland_cache.gd).
	var baked := GROUND.grid_heights(true)
	var fresh := GROUND.grid_heights(false)
	var drift := 0.0
	for i: int in range(fresh.size()):
		drift = maxf(drift, absf(baked[i] - fresh[i]))
	check(ResourceLoader.exists(GROUND.HEIGHT_CACHE) and drift < 0.0001, "Baked terrain heights are stale (drift %.4f m): rerun tools/bake_woodland_cache.gd" % drift)
	for model: String in GROUND.BOULDER_MODELS:
		var cached: Dictionary = GROUND.scan_shape(model)
		var computed: Dictionary = GROUND.scan_shape(model, false)
		check(cached.aabb.is_equal_approx(computed.aabb) and cached.hull == computed.hull, "Baked collision hull for %s is stale: rerun tools/bake_woodland_cache.gd" % model)
	check(ResourceLoader.exists("res://assets/textures/woodland/scatter_cache.res"), "Woodland scatter cache missing: run tools/bake_woodland_cache.gd")
	var obstacles := arena.get_node("WoodlandObstacles")
	var items := GROUND.obstacles()
	check(obstacles.get_child_count() == items.size() and items.size() > 60, "Obstacle set changed")
	# Point symmetry keeps both team halves equivalent.
	for item: Dictionary in items:
		var mirrored := false
		for other: Dictionary in items:
			mirrored = mirrored or (other.kind == item.kind and other.at.distance_to(Vector3(-item.at.x, item.at.y, -item.at.z)) < 0.01)
		check(mirrored, "Obstacle lacks its mirrored partner: %s" % str(item.at))
	for body: StaticBody3D in obstacles.get_children():
		check(body.collision_layer == 1 and body.collision_mask == 2, "Obstacle layers differ from the arena shell")
	# Spawns, the open centre and practice homes stay clear with room to turn.
	var clear_points: Array[Vector3] = [Vector3.ZERO, Vector3(0, 0, 4), Vector3(0, 0, -4), Vector3(-13, 0, -2), Vector3(12, 0, -11)]
	for marker: Node3D in arena.get_node("SpawnPoints").get_children():
		clear_points.append(marker.position)
	for point: Vector3 in clear_points:
		var clearance := SphereShape3D.new()
		clearance.radius = 7.0
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = clearance
		query.collision_mask = 1
		query.transform.origin = point + Vector3(0, 7.3, 0)
		var hits := space.intersect_shape(query)
		hits = hits.filter(func(hit: Dictionary) -> bool: return not String(hit.collider.get_parent().name) == "Walls" and hit.collider.name != "WoodlandTerrain")
		check(hits.is_empty(), "Obstacle crowds spawn or practice point %s" % str(point))
	for point: Vector3 in clear_points:
		for dx: float in [-8.0, 0.0, 8.0]:
			for dz: float in [-8.0, 0.0, 8.0]:
				check(absf(GROUND.height_at(point.x + dx, point.z + dz) - GROUND.height_at(point.x, point.z)) < 0.02, "Spawn or practice pad is not level at %s" % str(point))
	for wall: StaticBody3D in arena.get_node("Walls").get_children():
		var box := (wall.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
		check(box.size.y == GROUND.WALL_HEIGHT and is_equal_approx(wall.position.y, GROUND.WALL_HEIGHT * 0.5), "Walls must stop jumping giants")
	# Spawned bots stand on the terrain, not inside it.
	var registry := ContentRegistry.new()
	var spawned := world.spawn(1, 0, 0, registry.starter(true), 5)
	var origin: Vector3 = spawned.spawn_pose.origin if spawned else Vector3.ZERO
	check(spawned != null and origin.y > GROUND.height_at(origin.x, origin.z) + 0.05, "Woodland spawn height %s" % str(origin))
	world.clear_bots()
	var art := arena.get_node("FoundryVisuals")
	check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "Art created gameplay collision")
	if DisplayServer.get_name() == "headless":
		check(art.get_child_count() == 0, "Headless arena constructed presentation")
		check(arena.find_children("*", "VisualInstance3D", true, false).is_empty(), "Headless world kept visuals")
	else:
		check(art.find_children("*", "Node3D", true, false).size() > 40, "Woodland art did not build")
		if "--capture" in OS.get_cmdline_user_args():
			await _capture(world)
	world.queue_free()
	await process_frame
	print("WOODLAND PASS" if failures == 0 else "WOODLAND FAIL")
	quit(0 if failures == 0 else 1)

func _capture(world: AuthorityWorld) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.substr(7).split("x")
			root.size = Vector2i(int(parts[0]), int(parts[1]))
	if "--benchmark" in OS.get_cmdline_user_args():
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		root.mesh_lod_threshold = 2.0 # Matches GraphicsRuntime.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 68
	camera.far = 1200
	var registry := ContentRegistry.new()
	for index: int in range(2):
		var bot := MvpBot.create(index + 1, index, registry.starter(index == 1), registry)
		world.add_child(bot)
		bot.body.freeze = true
		bot.body.position = Vector3(-6 + index * 12, 1.2 + GROUND.MESA_TOP, 8 - index * 14)
		bot.body.rotation.y = index * PI + 0.35
		bot.previous_pose = bot.body.global_transform
	var views := [
		["overview", Vector3(0, 70, 150), Vector3(0, 0, -20)],
		["valley", Vector3(-60, 95, 330), Vector3(0, 10, 0)],
		["floor", Vector3(10, 5.0, 24), Vector3(-6, 5.0, -60)],
		["wall", Vector3(-20, 5.0, -80), Vector3(-6, 10.0, -120)],
		["corner", Vector3(-35, 7.0, -70), Vector3(-48, 18.0, -118)],
		["gate", Vector3(70, 6.0, 12), Vector3(120, 8.0, 0)],
		["outcrop", Vector3(-14, 7.0, -64), Vector3(-32, 2.0, -48)],
		["mesa", Vector3(40, 14.0, 42), Vector3(0, 3.0, 0)],
		["ramp", Vector3(-70, 6.0, 14), Vector3(-58, 2.0, -6)],
		["bunker", Vector3(-28, 7.0, -92), Vector3(-48, 2.0, -76)],
		# Looking into the low sun across rutted mud: glints and fireflies show here.
		["glare", Vector3(12, 5.0, 84), Vector3(-14, 0.0, 58)],
		# Tank-camera height beside the grassy wall foot.
		["grass", Vector3(-8, 3.2, -104), Vector3(-2, 0.0, -117)],
		# Default giant-tank chase camera: ~12 m boom, looking across open ground.
		["tower", Vector3(-41.2, 40.0, -99.4), Vector3(-51.5, 46.0, -124.3)],
		["chase", Vector3(-62, 6.0, 72), Vector3(-45, 1.0, 30)],
	]
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			only = arg.substr(7)
	var output := "res://exports/arena-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open(output + "/.gdignore", FileAccess.WRITE)
	ignore.close()
	for view: Array in views:
		if only != "" and view[0] != only:
			continue
		camera.position = view[1]
		camera.look_at(view[2])
		for frame: int in range(60):
			await process_frame
			await RenderingServer.frame_post_draw
		var path: String = output + "/woodland-" + view[0] + ".png"
		check(root.get_texture().get_image().save_png(path) == OK, "Capture failed")
		print("CAPTURE: ", ProjectSettings.globalize_path(path))
		if "--benchmark" in OS.get_cmdline_user_args():
			var timings: Array[float] = []
			var gpu_times: Array[float] = []
			var previous := Time.get_ticks_usec()
			for sample: int in range(120):
				await process_frame
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				timings.append((now - previous) / 1000.0)
				gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				previous = now
			timings.sort()
			gpu_times.sort()
			var vp := root.get_viewport_rid()
			print("FRAME SAMPLE ", view[0], " %dx%d / 120 frames: median=" % [root.size.x, root.size.y], snappedf(timings[60], 0.1),
				" ms p95=", snappedf(timings[114], 0.1), " gpu_min=", snappedf(gpu_times[0], 0.1), " gpu_med=", snappedf(gpu_times[60], 0.1),
				" cpu=", snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp), 0.1),
				" prims=", snappedf(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6, 0.01), "M draws=",
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	print("RENDER: ", RenderingServer.get_video_adapter_name(), " | objects=",
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " | draw calls=",
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " | primitives=",
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
