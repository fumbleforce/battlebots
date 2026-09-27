extends SceneTree
const GROUND = preload("res://scripts/arena/sunreach_ground.gd")
const SPAWNS = preload("res://scripts/core/arena_spawns.gd")
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var bake: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sunreach/bake.json"))
	for path: String in bake:
		check(FileAccess.get_sha256("res://" + path) == bake[path], "Sunreach bake matches " + path)
	var world := AuthorityWorld.new()
	world.arena_id = "sunreach"
	root.add_child(world)
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	check(world.arena.has_node("SunreachTerrain"), "Sunreach terrain loaded")
	check(world.arena.get_node("SpawnPoints").get_child_count() == 18, "All match spawns retained")
	check(world.arena.get_node("SunreachStructures").get_child_count() > 500, "Authored structure hulls loaded")
	for point: Vector2 in SPAWNS.settings().points("sunreach"):
		var shape := BoxShape3D.new()
		shape.size = Vector3(9, 5, 9)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1
		query.transform.origin = Vector3(point.x, GROUND.height_at(point.x, point.y) + 3, point.y)
		check(space.intersect_shape(query).is_empty(), "Spawn is clear: %s" % point)
	# Compare independently queried physical height against the placement sampler.
	for x: float in [-55.3, -18.4, 12.1, 58.7]:
		for z: float in [-74.2, -15.8, 39.3, 77.1]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 2, z), Vector3(x, -5, z), 1))
			if not hit.is_empty() and hit.collider.name == "SunreachTerrain":
				check(absf(hit.position.y - GROUND.height_at(x, z)) < 0.015, "Heightmap sampler agrees with Jolt")
	for bridge: Dictionary in GROUND.settings().bridges:
		# Sweep a full-size robot envelope across every deck seam and abutment.
		var previous := 0.0
		for step: int in range(-20, 21):
			for offset: float in [-5.0, 0.0, 5.0]:
				var x := float(bridge.x) + offset
				var z := float(bridge.z) + step
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 5, z), Vector3(x, -5, z), 1))
				check(not hit.is_empty(), "Bridge crossing has continuous support")
				if hit.is_empty(): continue
				if offset == 0.0:
					if step > -20: check(absf(hit.position.y - previous) < 0.35, "Bridge approach has no catching step %s z=%s y=%s previous=%s" % [bridge.x, z, hit.position.y, previous])
					previous = hit.position.y
				if abs(step) <= 12: check(absf(hit.position.y - float(bridge.deck_height)) < 0.02, "Bridge deck matches art height %s %s y=%s" % [x, z, hit.position.y])
	var bot := world.spawn(1, 0, 0, world.registry.starter(), 1)
	check(bot != null and bot.spawn_pose.origin.y > GROUND.height_at(bot.spawn_pose.origin.x, bot.spawn_pose.origin.z), "Robot starts above ground")
	world.clear_bots()
	if DisplayServer.get_name() == "headless":
		check(world.arena.find_children("*", "VisualInstance3D", true, false).is_empty(), "Server constructs no presentation")
	else:
		check(world.arena.get_node("FoundryVisuals").get_child_count() > 0, "Presentation root exists")
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		await capture(world)
	world.queue_free()
	await process_frame
	print("SUNREACH PASS" if failures == 0 else "SUNREACH FAIL")
	quit(0 if failures == 0 else 1)

func capture(world: AuthorityWorld) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1672, 941)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.far = 2500
	camera.fov = 56
	var directory := "res://exports/sunreach-review"
	DirAccess.make_dir_recursive_absolute(directory)
	# Staging: south rim looking north into the sunlit basin; both bridges in
	# midground, NW waterfall and NE arch behind. No bots obscure the layout.
	var views := [
		["overview", Vector3(32, 138, 160), Vector3(0, 0, -13)],
		["chase", Vector3(8, 8, 49), Vector3(-4, 3, -12)],
		["bridge", Vector3(-61, 9, -4), Vector3(-77, 1, -30)],
		["ruins", Vector3(14, 8, -1), Vector3(-7, 5, -29)]]
	for view: Array in views:
		camera.position = view[1]
		camera.look_at(view[2])
		for i: int in 35: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(directory + "/" + view[0] + ".png")
		if view[0] == "overview":
			image.save_jpg("res://ui/menus/art/arena_sunreach.jpg", .92)
			var tank := world.spawn(2, 0, 0, world.registry.bracken())
			tank.body.freeze = true
			tank.body.reset_pose = null
			tank.body.position = Vector3(0, GROUND.height_at(0, 30) + tank.ground_clearance(), 30)
	print("SUNREACH CAPTURES: ", ProjectSettings.globalize_path(directory))
