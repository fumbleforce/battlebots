extends Node3D
## Deterministic frozen poses on real lunar Jolt collision, not a driving simulation.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var arena: Node3D = preload("res://scenes/arenas/moon_arena.tscn").instantiate()
	add_child(arena)
	var registry := ContentRegistry.new()
	var bot := MvpBot.create(1, 0, registry.starter(), registry)
	bot.simulated = false
	add_child(bot)
	bot.set_process(false)
	var rig: BotOrbitCamera = preload("res://scenes/ui/orbit_camera.tscn").instantiate()
	add_child(rig)
	rig.set_physics_process(false)
	rig.bind_source(bot)
	await sync_physics()
	var space := get_world_3d().direct_space_state
	var collider: CollisionShape3D = bot.body.get_node("Collision")
	var terrain_cases := 0
	for location: Vector2 in [Vector2.ZERO, Vector2(12.5, 8.125), Vector2(-13.75, 11.875), Vector2(16.1, -9.2), Vector2(22.8, 0)]:
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(location.x, 4, location.y), Vector3(location.x, -1, location.y), BaselineConfig.WORLD_LAYER))
		check(not ground.is_empty(), "Lunar fixture has ground beneath bot")
		if ground.is_empty():
			continue
		if ground.position.y > 0.2:
			terrain_cases += 1
		for roll: float in [0.0, PI * 0.5, PI]:
			# Sweep the actual chassis down from clear space, then stop 1cm above
			# its first support contact. The upside-down bot is never sunk into terrain.
			var support := PhysicsShapeQueryParameters3D.new()
			support.shape = collider.shape
			support.transform = Transform3D(Basis(Vector3.FORWARD, roll), Vector3(location.x, 4, location.y))
			support.motion = Vector3.DOWN * 5.0
			support.collision_mask = BaselineConfig.WORLD_LAYER
			support.margin = 0.001
			var fractions := space.cast_motion(support)
			check(fractions[0] < 1.0, "Chassis sweep finds a real support contact")
			var pose := support.transform
			pose.origin += support.motion * fractions[0] + Vector3.UP * 0.01
			bot.body.global_transform = pose
			bot.presentation.global_transform = pose
			support.transform = pose
			support.motion = Vector3.ZERO
			await sync_physics()
			check(space.intersect_shape(support, 1).is_empty(), "Frozen chassis fixture must not overlap world")
			var label := "location=%s roll=%.0f ground=%.3f anchor=%.3f" % [location, rad_to_deg(roll), ground.position.y, bot.camera_anchor().global_position.y]
			for heading: float in [0.0, PI * 0.5, PI]:
				for elevation: float in [-15.0, 24.0, 70.0]:
					rig.yaw = heading
					rig.pitch = deg_to_rad(elevation)
					rig.desired_distance = 12.0
					rig.update_camera(1.0)
					var probe := PhysicsShapeQueryParameters3D.new()
					var sphere := SphereShape3D.new()
					sphere.radius = rig.camera_radius
					probe.shape = sphere
					probe.collision_mask = BaselineConfig.WORLD_LAYER
					probe.transform = Transform3D(Basis.IDENTITY, rig.camera.global_position)
					check(space.intersect_shape(probe, 1).is_empty(),
						"Camera sphere intersects lunar surface: %s yaw=%.0f pitch=%.0f pivot=%s boom=%.3f" % [label, rad_to_deg(heading), elevation, rig.global_position, rig.actual_distance])
					check(absf(rig.camera.global_basis.x.dot(Vector3.UP)) < 0.001, "Lunar roll never rolls camera horizon")
			if location == Vector2(12.5, 8.125) and is_equal_approx(roll, PI):
				await capture(rig)
				await check_obstructions(bot, rig)
	check(terrain_cases >= 2, "Fixture exercises multiple raised lunar terrain patches")
	rig.queue_free()
	bot.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	print("CAMERA TERRAIN PASS" if failures == 0 else "CAMERA TERRAIN FAIL: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func obstruction(at: Vector3, size: Vector3) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	obstacle.position = at
	obstacle.collision_layer = BaselineConfig.WORLD_LAYER
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	obstacle.add_child(collider)
	add_child(obstacle)
	return obstacle

func check_obstructions(bot: MvpBot, rig: BotOrbitCamera) -> void:
	# Keep this deliberately constrained clearance case: a larger hull leaves
	# sufficient room for the ordinary 25cm probe beneath the old ceiling.
	# Exercise the exported conservative probe size at the same hull ratio.
	var normal_radius := rig.camera_radius
	rig.camera_radius *= BotScale.FACTOR
	var space := get_world_3d().direct_space_state
	var collider: CollisionShape3D = bot.body.get_node("Collision")
	var shape: BoxShape3D = collider.shape
	var chassis := PhysicsShapeQueryParameters3D.new()
	chassis.shape = shape
	chassis.transform = bot.body.global_transform
	chassis.collision_mask = BaselineConfig.WORLD_LAYER
	chassis.margin = 0.001
	rig.yaw = 0.0
	rig.pitch = deg_to_rad(24.0)
	rig.update_camera(1.0)
	var clear_pivot := rig.global_position
	check(clear_pivot.y > 0.3, "Inverted lunar pose requires ground correction")
	# The ceiling fits just above the real frozen upside-down chassis. It can
	# constrain a camera sphere even though the bot itself still fits beneath it.
	var underside := bot.body.global_position.y + shape.size.y * 0.5 + 0.015
	var ceiling := obstruction(Vector3(clear_pivot.x, underside + 0.1, clear_pivot.z), Vector3(5, 0.2, 5))
	await sync_physics()
	check(space.intersect_shape(chassis, 1).is_empty(), "Ceiling fixture does not intersect chassis")
	rig.update_camera(1.0)
	check(rig.global_position.y < clear_pivot.y - 0.05, "Low ceiling actually prevents terrain-pivot rise")
	check(rig.global_position.y < underside and rig.camera.global_position.y < underside,
		"Ground recovery never jumps through a low ceiling")
	ceiling.queue_free()
	await sync_physics()
	rig.update_camera(1.0)
	check(rig.global_position.is_equal_approx(clear_pivot) and rig.actual_distance > 3,
		"Removing ceiling restores clear terrain pivot and readable boom")
	var wall_x := bot.body.global_position.x + shape.size.x * 0.5 + 0.02
	var wall := obstruction(Vector3(wall_x + 0.1, 2, clear_pivot.z), Vector3(0.2, 4, 8))
	await sync_physics()
	check(space.intersect_shape(chassis, 1).is_empty(), "Side-wall fixture does not intersect chassis")
	rig.yaw = PI * 0.5
	rig.update_camera(1.0)
	check(rig.camera.global_position.x + rig.camera_radius < wall_x,
		"Raised-ground boom remains on chassis side of wall")
	check(rig.actual_distance < 1.0 * BotScale.FACTOR, "Adjacent wall shortens boom")
	wall.queue_free()
	await sync_physics()
	rig.update_camera(1.0)
	check(rig.actual_distance > 3.0, "Removing side wall restores boom")
	rig.camera_radius = normal_radius

func capture(rig: BotOrbitCamera) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	rig.yaw = 0.0
	rig.pitch = deg_to_rad(24.0)
	rig.update_camera(1.0)
	rig.camera.current = true
	for frame: int in range(3):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var destination := OS.get_environment("TEMP").path_join("camera-lunar-inverted.png")
	check(get_viewport().get_texture().get_image().save_png(destination) == OK, "Native inverted lunar capture saved")
	print("CAMERA TERRAIN CAPTURE: ", destination)
