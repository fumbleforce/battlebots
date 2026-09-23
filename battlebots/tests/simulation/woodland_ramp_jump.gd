extends SceneTree
## Actual Woodland/Jolt jump; identical public commands with Nitro on/off.
const GROUND = preload("res://scripts/arena/woodland_ground.gd")
const MODEL = preload("res://assets/models/woodland/jump_ramp.gltf")
const RUN_UP := 28.0
const LANE_OFFSET := 1.5
const BRAKE_AFTER_CENTRE := 1.0
const WARMUP_TICKS := 75
const RUN_TICKS := 600
const SETTLE_TICKS := 180
const HOLD_TICKS := 120
var failures := 0
var capture := false
var evidence: Array[Dictionary] = []
var deck_samples: Array[Vector3] = []

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func model_faces(node: Node3D, parent: Transform3D) -> PackedVector3Array:
	var pose := parent * node.transform
	var faces := PackedVector3Array()
	if node is MeshInstance3D:
		for vertex: Vector3 in node.mesh.get_faces(): faces.append(pose * vertex)
	for child: Node in node.get_children():
		if child is Node3D: faces.append_array(model_faces(child, pose))
	return faces

func check_geometry() -> void:
	check(is_equal_approx(GROUND.RAMP_HEIGHT, 5.5), "Requested ramp lip is 5.5 m")
	var model := MODEL.instantiate() as Node3D
	# Runtime WoodlandVisuals rotates the exported -Z rise to collision's +Z.
	var faces := model_faces(model, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	model.free()
	check(not faces.is_empty(), "Imported ramp contains rendered triangles")
	for x: float in [-2.0, 0.0, 2.0]:
		for z: float in [-5.0, 0.0, 4.0, 6.7]:
			var highest := -INF
			for i: int in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 20, z), Vector3.DOWN,
					faces[i], faces[i + 1], faces[i + 2])
				if hit is Vector3: highest = maxf(highest, hit.y)
			check(is_finite(highest), "Imported deck covers sample (%s,%s)" % [x, z])
			deck_samples.append(Vector3(x, highest, z))

func check_collision(ramp: StaticBody3D) -> void:
	for sample: Vector3 in deck_samples:
		var above := ramp.to_global(Vector3(sample.x, 20, sample.z))
		var below := ramp.to_global(Vector3(sample.x, -2, sample.z))
		var query := PhysicsRayQueryParameters3D.create(above, below, 1)
		var hit := ramp.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == ramp, "Actual Jolt ramp covers deck sample")
		if hit.is_empty() or hit.collider != ramp: continue
		var collision_y: float = ramp.to_local(hit.position).y
		# Existing bevels, steel plates/ribs and cap sit above the concrete
		# wedge by up to 0.24 m; a stale 3.6 m asset fails these samples.
		check(sample.y >= collision_y - 0.08 and sample.y <= collision_y + 0.24,
			"Imported deck/collision disagree at %s: mesh %s, collision %s" % [sample, sample.y, collision_y])

func on_roof(bot: MvpBot, bunker: StaticBody3D) -> bool:
	if not bot.body.grounded or not bot.body.contact_bodies.has(bunker.get_instance_id()): return false
	var position := bot.body.global_position
	var query := PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * 20, 1)
	var hit := bot.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == bunker and hit.normal.y > 0.99

func save_capture(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var folder := "res://exports/ramp-jump-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var ignored := FileAccess.open(folder + "/.gdignore", FileAccess.WRITE)
	ignored.close()
	var path := folder + "/" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "Save native ramp capture")
	print("RAMP CAPTURE ", ProjectSettings.globalize_path(path))

func jump_case(mirrored: bool, nitro: bool) -> void:
	var world := AuthorityWorld.new()
	world.arena_id = "woodland"
	root.add_child(world)
	var suffix := "mirrored" if mirrored else "original"
	var label := suffix + ("_nitro" if nitro else "_normal")
	var ramp := world.arena.get_node("WoodlandObstacles/JumpRamp25" if mirrored else "WoodlandObstacles/JumpRamp24") as StaticBody3D
	var bunker := world.arena.get_node("WoodlandObstacles/Bunker29" if mirrored else "WoodlandObstacles/Bunker28") as StaticBody3D
	var shape := ramp.get_child(0) as CollisionShape3D
	var max_y := -INF
	for point: Vector3 in (shape.shape as ConvexPolygonShape3D).points: max_y = maxf(max_y, point.y)
	check(is_equal_approx(max_y, GROUND.RAMP_HEIGHT), "Actual ramp collision uses the authored lip")
	if capture:
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.global_position = ramp.to_global(Vector3(25, 19, 13))
		camera.look_at(ramp.global_position.lerp(bunker.global_position, 0.5) + Vector3.UP * 2)
		camera.current = true
	var bot := world.spawn(1, 0, 0, world.registry.atlas())
	var start := ramp.to_global(Vector3(LANE_OFFSET, 0, -RUN_UP))
	start.y = GROUND.height_at(start.x, start.z) + bot.ground_clearance() + 0.15
	bot.body.reset_pose = Transform3D(ramp.global_basis * Basis(Vector3.UP, PI), start)
	for tick: int in WARMUP_TICKS: await physics_frame
	check_collision(ramp)
	check(bot.body.grounded, label + " starts settled on the run-up")
	await save_capture(label + "_start")
	var landed := false
	var airborne := false
	var active_nitro := false
	var peak_y := bot.body.global_position.y
	var stable_ticks := 0
	var landing_tick := -1
	for tick: int in RUN_TICKS:
		var command := BotCommand.new()
		command.sequence = tick
		command.throttle = 1.0
		command.nitro_held = nitro
		# Boost up the ramp, then brake for the landing. No jump, steering,
		# impulses or pose/velocity edits once the run begins.
		if ramp.to_local(bot.body.global_position).z >= BRAKE_AFTER_CENTRE:
			command.throttle = 0.0
			command.nitro_held = false
			command.brake = true
		bot.submit_command(command)
		bot.step(1.0 / 60.0, true)
		await physics_frame
		peak_y = maxf(peak_y, bot.body.global_position.y)
		active_nitro = active_nitro or bot.combat.nitro_active
		if not bot.body.grounded and ramp.to_local(bot.body.global_position).z > 0: airborne = true
		if airborne and on_roof(bot, bunker):
			landed = true
			landing_tick = tick
			await save_capture(label + "_landing")
			for settle: int in SETTLE_TICKS:
				var stop := BotCommand.new()
				stop.sequence = tick + settle + 1
				stop.brake = true
				bot.submit_command(stop)
				bot.step(1.0 / 60.0, true)
				await physics_frame
				# Allow a second for the physical landing bounce to settle,
				# then require two seconds of continuing roof support.
				if settle >= SETTLE_TICKS - HOLD_TICKS and on_roof(bot, bunker): stable_ticks += 1
			break
	check(active_nitro == nitro, label + " exercises the intended Nitro state")
	check(landed == nitro, label + " reaches the roof only with Nitro on this route")
	if nitro:
		check(stable_ticks >= HOLD_TICKS - 2 and on_roof(bot, bunker)
			and bot.body.global_basis.y.y > 0.95 and bot.body.linear_velocity.length() < 0.5,
			label + " settles upright on the roof for two seconds")
	await save_capture(label + "_end")
	var record := {"case":label, "landed":landed, "airborne":airborne,
		"peak_y":peak_y, "landing_tick":landing_tick, "stable_ticks":stable_ticks,
		"final_position":str(bot.body.global_position), "final_speed":bot.body.linear_velocity.length()}
	evidence.append(record)
	print("RAMP RESULT ", JSON.stringify(record))
	world.queue_free()
	await process_frame

func run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		push_error("Capture requires the native renderer")
		quit(1)
		return
	if capture: root.size = Vector2i(1600, 900)
	check_geometry()
	for mirrored: bool in [false, true]:
		for nitro: bool in [false, true]: await jump_case(mirrored, nitro)
	print("WOODLAND RAMP JUMP PASS" if failures == 0 else "WOODLAND RAMP JUMP FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
