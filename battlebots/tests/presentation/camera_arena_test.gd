extends SceneTree
## Integration checks against actual arena collision and camera placement.
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func sync_physics() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	check(InputMap.event_is_action(key, "drive_forward"), "Physical W must match drive action")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	check(InputMap.event_is_action(mouse, "camera_recenter"), "MMB must match recenter action")
	var sandbox: Node3D = load("res://scenes/dev/b_presentation.tscn").instantiate()
	sandbox.get_node("Preview").settings_path = ""
	root.add_child(sandbox)
	await sync_physics()
	var source: BotSource = sandbox.get_node("Bot")
	source.set_physics_process(false)
	var preview: Node3D = sandbox.get_node("Preview")
	preview.set_physics_process(false)
	preview.release_controls()
	# The HUD must never retain a removed bot's values or propagate invalid fractions.
	var hud: BotStatusHud = preview.hud
	var sample := BotView.new()
	sample.core_fraction = 1.5
	sample.heat_fraction = NAN
	hud.show_view(sample)
	check(hud.rows.get_node("Core/Value").text == "100%", "HUD must clamp over-range data")
	check(hud.rows.get_node("Heat/Value").text == "--", "HUD must label invalid data")
	hud.show_view(null)
	check(hud.state_label.text == "TARGET UNAVAILABLE", "HUD must identify missing target")
	check(hud.rows.get_node("Core/Bar").value == 0.0, "HUD must clear stale core value")
	hud.show_view(source.read_view())
	var rig: BotOrbitCamera = preview.rig
	rig.set_physics_process(false)
	var space := sandbox.get_world_3d().direct_space_state
	var markers: Node3D = sandbox.get_node("Arena/SpawnPoints")
	check(markers.get_child_count() == 18, "Expected ten team and eight FFA markers")
	for index: int in range(1, 9):
		var marker: Marker3D = markers.get_node("FFA_%d" % index)
		check(is_equal_approx(Vector2(marker.position.x, marker.position.z).length(), 20.0),
			"FFA radius must be 20 meters")
		var to_center := -Vector3(marker.position.x, 0, marker.position.z).normalized()
		check((-marker.basis.z).dot(to_center) > 0.999, "FFA must face center")
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0),
			direction * 30.0 + Vector3(0, 1, 0), BaselineConfig.WORLD_LAYER)
		var hit := space.intersect_ray(ray)
		check(not hit.is_empty(), "Missing perimeter wall")
		if not hit.is_empty():
			check(absf(hit.position.x) <= 25.01 and absf(hit.position.z) <= 25.01,
				"Wall interior must preserve 50-meter dimensions")
	var shape := SphereShape3D.new()
	var corner_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0),
		Vector3(30, 1, 30), BaselineConfig.WORLD_LAYER)
	var corner_hit := space.intersect_ray(corner_ray)
	check(not corner_hit.is_empty(), "Corner chamfer missing")
	if not corner_hit.is_empty():
		check(absf(corner_hit.position.x - 24.0) < 0.01,
			"Diagonal corner must meet at (24, 24)")
	shape.radius = 0.2
	for location: Vector3 in [Vector3(0, 0.3, 0), Vector3(0, 0.3, 22.8),
			Vector3(22.8, 0.3, 22.8), Vector3(-22.8, 0.3, -22.8)]:
		source.position = location
		await sync_physics()
		for heading: float in [0.0, PI / 4.0, PI / 2.0, PI, -PI / 2.0]:
			for elevation: float in [-15.0, 0.0, 24.0, 70.0]:
				rig.yaw = heading
				rig.pitch = deg_to_rad(elevation)
				rig.desired_distance = 9.0
				rig.update_camera(1.0)
				var at := rig.camera.global_position
				check(absf(at.x) < 25.0 and absf(at.z) < 25.0 and at.y > 0.2,
					"Camera escaped the arena or floor")
				var probe := PhysicsShapeQueryParameters3D.new()
				probe.shape = shape
				probe.transform = Transform3D(Basis.IDENTITY, at)
				probe.collision_mask = BaselineConfig.WORLD_LAYER
				check(space.intersect_shape(probe, 1).is_empty(), "Camera sphere clips geometry")
	source.position = Vector3(0, 0.3, 22.8)
	rig.yaw = 0.0
	rig.pitch = 0.0
	rig.update_camera(1.0)
	check(rig.actual_distance < 2.3, "Boom must shorten near wall")
	# An interior obstacle exercises the physics sweep independently of arena bounds.
	var obstacle := StaticBody3D.new()
	obstacle.position = Vector3(0, 1.5, 3)
	obstacle.collision_layer = BaselineConfig.BOT_LAYER
	var collider := CollisionShape3D.new()
	var obstacle_shape := BoxShape3D.new()
	obstacle_shape.size = Vector3(3, 3, 0.5)
	collider.shape = obstacle_shape
	obstacle.add_child(collider)
	sandbox.add_child(obstacle)
	source.position = Vector3(0, 0.3, 0)
	await sync_physics()
	rig.update_camera(1.0)
	check(rig.actual_distance < 2.6, "Physics sweep must avoid other bots")
	obstacle.queue_free()
	await sync_physics()
	source.position = Vector3(0, 0.3, 0)
	source.rotation = Vector3(0, 0.7, PI)
	rig.recenter()
	rig.update_camera(1.0)
	check(absf(rig.camera.global_basis.x.dot(Vector3.UP)) < 0.001,
		"Chassis flip must not roll the horizon")
	check(absf(angle_difference(rig.yaw, 0.7)) < 0.001, "Recenter must follow heading")
	rig.zoom(100.0)
	check(rig.desired_distance == 9.0, "Zoom out clamp")
	rig.zoom(-100.0)
	check(rig.desired_distance == 4.0, "Zoom in clamp")
	rig.orbit(Vector2(0, 100000))
	check(is_equal_approx(rad_to_deg(rig.pitch), 70.0), "Down pitch clamp")
	rig.orbit(Vector2(0, -100000))
	check(is_equal_approx(rad_to_deg(rig.pitch), -15.0), "Up pitch clamp")
	rig.yaw = -0.5
	rig.driving = true
	rig.auto_recenter = true
	rig.seconds_since_orbit = 0.0
	rig.update_camera(0.1)
	check(is_equal_approx(rig.yaw, -0.5), "Recent mouse input must prevent auto-center")
	rig.seconds_since_orbit = 2.0
	rig.update_camera(0.5)
	check(absf(angle_difference(rig.yaw, 0.7)) < 1.2, "Idle driving must auto-center")
	var command := BotCommand.new()
	command.throttle = 1.0
	command.primary_held = true
	source.submit_command(command)
	preview.release_controls()
	check(source.last_command.throttle == 0.0 and not source.last_command.primary_held,
		"Releasing control must immediately submit neutral command")

	# Optional rendered preview for visual review, outside the headless check.
	if "--capture" in OS.get_cmdline_user_args():
		source.rotation = Vector3.ZERO
		source.position = Vector3(0, 0.3, 0)
		rig.driving = false
		rig.desired_distance = 6.0
		rig.recenter()
		rig.update_camera(1.0)
		for frame: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var output := "user://b-camera-preview.png"
		var error := root.get_texture().get_image().save_png(output)
		check(error == OK, "Screenshot save failed")
		print("CAPTURE: ", ProjectSettings.globalize_path(output))

	source.queue_free()
	await process_frame
	rig.update_camera(0.1)
	preview._physics_process(0.1)
	check(not preview.controls_enabled, "Deleted target must not retain control")
	sandbox.queue_free()
	await process_frame

	# Existing A scene remains compatible, including its real collider exclusion.
	var a_scene: Node3D = load("res://scenes/dev/a_simulation.tscn").instantiate()
	a_scene.get_node("Preview").settings_path = ""
	root.add_child(a_scene)
	await sync_physics()
	var a_preview: Node3D = a_scene.get_node("Preview")
	var body: RigidBody3D = a_scene.get_node("Bot/Body")
	body.freeze = true
	body.rotation.z = PI
	a_preview.rig.recenter()
	a_preview.rig.update_camera(1.0)
	check(a_preview.rig.actual_distance > 3.0, "Camera must exclude own inverted bot")
	a_scene.queue_free()
	await process_frame
	print("PRESENTATION PASS" if failures == 0 else "PRESENTATION FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
