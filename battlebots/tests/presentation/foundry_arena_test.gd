extends SceneTree
## Arena-only structural regression and reproducible rendered review captures.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var arena := load("res://scenes/arenas/baseline_arena.tscn").instantiate() as Node3D
	root.add_child(arena)
	await physics_frame
	await physics_frame
	check(arena.get_node("SpawnPoints").get_child_count() == 18, "Spawn contract changed")
	check(arena.get_node("Walls").get_child_count() == 8, "Wall contract changed")
	var shape: BoxShape3D = arena.get_node("Floor/Collision").shape
	check(shape.size == Vector3(50, 1, 50), "Floor contract changed")
	check(arena.get_node("Floor").position == Vector3(0, -0.5, 0), "Floor elevation changed")
	var space := arena.get_world_3d().direct_space_state
	for side: int in range(8):
		var direction := Vector3(sin(side*PI/4), 0, cos(side*PI/4))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), direction*30+Vector3(0, 1, 0), 1))
		check(not hit.is_empty(), "Missing octagon side %d" % side)
		if not hit.is_empty():
			check(absf(Vector2(hit.position.x, hit.position.z).length()-25.0) < 0.01, "Unequal octagon side distance")
	for marker: Node3D in arena.get_node("SpawnPoints").get_children():
		var clearance := SphereShape3D.new()
		clearance.radius = 1.25
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = clearance
		query.collision_mask = 1
		query.transform.origin = marker.position+Vector3(0, 1.0, 0)
		check(space.intersect_shape(query).is_empty(), "Spawn lacks wall clearance: " + String(marker.name))
	var art := arena.get_node("FoundryVisuals")
	check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "Art created gameplay collision")
	if DisplayServer.get_name() == "headless":
		check(art.get_child_count() == 0, "Headless arena constructed presentation")
	else:
		check(art.get_child_count() > 30, "Foundry art did not build")
		if "--capture" in OS.get_cmdline_user_args():
			await _capture(arena)
	arena.queue_free()
	await process_frame
	print("FOUNDRY PASS" if failures == 0 else "FOUNDRY FAIL")
	quit(0 if failures == 0 else 1)

func _capture(arena: Node3D) -> void:
	root.size = Vector2i(1600, 900)
	if "--benchmark" in OS.get_cmdline_user_args():
		root.size = Vector2i(1920, 1080)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.current = true
	camera.fov = 68
	camera.far = 150
	var registry := ContentRegistry.new()
	for index: int in range(2):
		var bot := MvpBot.create(index+1, index, registry.starter(index == 1), registry)
		arena.add_child(bot)
		bot.body.freeze = true
		bot.body.position = Vector3(-3+index*6, 0.5, 6-index*7)
		bot.body.rotation.y = index*PI+0.35
		bot.previous_pose = bot.body.global_transform
	var views := [
		["overview", Vector3(15, 12, 17), Vector3(0, 2.5, -5)],
		["floor", Vector3(6, 2.8, 15), Vector3(-2, 2.8, -18)],
		["gate", Vector3(-16, 3.7, -11), Vector3(0, 5.7, -26)]
	]
	var output := "res://exports/arena-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open(output + "/.gdignore", FileAccess.WRITE)
	ignore.close()
	for view: Array in views:
		camera.position = view[1]
		camera.look_at(view[2])
		for frame: int in range(45):
			await process_frame
			await RenderingServer.frame_post_draw
		var path: String = output + "/foundry-" + view[0] + ".png"
		check(root.get_texture().get_image().save_png(path) == OK, "Capture failed")
		print("CAPTURE: ", ProjectSettings.globalize_path(path))
		if "--benchmark" in OS.get_cmdline_user_args():
			var timings: Array[float] = []
			var previous := Time.get_ticks_usec()
			for sample: int in range(240):
				await process_frame
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				timings.append((now-previous)/1000.0)
				previous = now
			timings.sort()
			print("FRAME SAMPLE ", view[0], " 1080p / 240 frames: median=", timings[120],
				" ms p95=", timings[228], " ms (arena fixture, not combat certification)")
	print("RENDER: ", RenderingServer.get_video_adapter_name(), " | objects=",
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " | draw calls=",
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
