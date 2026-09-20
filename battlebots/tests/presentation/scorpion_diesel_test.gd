extends Node3D
## Real Jolt walking, rendered GPU smoke, and observation lifecycle regression.
var failures: Array[String] = []
var world: AuthorityWorld
var bot: MvpBot
var throttle := 0.0
var sequence := 0
var camera: Camera3D
var native := DisplayServer.get_name() != "headless"

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _physics_process(delta: float) -> void:
	if bot == null: return
	var command := BotCommand.new()
	sequence += 1
	command.sequence = sequence
	command.throttle = throttle
	command.brake = is_zero_approx(throttle)
	bot.submit_command(command)
	world.step(delta, true, 1)
	if camera != null:
		camera.global_position = bot.body.global_position + Vector3(11, 7.5, 11)
		camera.look_at(bot.body.global_position + Vector3(0, 2.4, 2.0))

func frames(count: int) -> void:
	for index: int in count: await get_tree().physics_frame
	await get_tree().process_frame

func capture(label: String) -> void:
	if not native: return
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("SCORPION_DIESEL_CAPTURE_DIR")
	if output.is_empty(): output = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output.path_join("scorpion_diesel_" + label + ".png"))

func run() -> void:
	var registry := ContentRegistry.new()
	var draft := registry.scorpion()
	var preview := ScorpionVisual.new()
	add_child(preview)
	preview.assemble(draft, registry.validate(draft).stats.size)
	preview.walker_legs.terrain = false
	var preview_view := BotView.new()
	for index: int in 60:
		preview.position.x += 0.1
		preview.show_state(preview_view, 1.0 / 60.0)
	check(not preview.diesel_exhaust.engine_running and preview.diesel_exhaust.emission_density == 0.0,
		"Moving garage showcase stays engine-off with no exhaust")
	for emitter: GPUParticles3D in preview.diesel_exhaust.emitters:
		check(not emitter.emitting, "Garage never emits residual GPU particles")
	preview.free()
	world = AuthorityWorld.new()
	add_child(world)
	bot = world.spawn(1, 0, 0, draft)
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 2.9, 12))
	bot.spawn_pose = bot.body.reset_pose
	if bot.scorpion_visual == null:
		bot.scorpion_visual = ScorpionVisual.new()
		bot.presentation.add_child(bot.scorpion_visual)
		bot.scorpion_visual.assemble(draft, bot.combat.stats.size)
		bot.scorpion_visual.walker_legs.exclusions = [bot.body.get_rid()]
	if native:
		camera = Camera3D.new()
		add_child(camera)
		camera.fov = 53.0
		camera.current = true
	var visual := bot.scorpion_visual
	var diesel := visual.diesel_exhaust
	check(diesel.emitters.size() == 2, "Both imported open stack lips have working emitters")
	await frames(150)
	check(bot.body.walker_contacts.size() == 6, "Diesel test settles on the real six-foot Jolt suspension")
	check(diesel.engine_running and diesel.engine_load < 0.04, "Steady real idle has an unloaded running engine")
	check(diesel.emission_density > 0.0 and diesel.emission_density < 0.10, "Idle emits only sparse residual exhaust")
	await capture("idle")
	var start := bot.body.global_position
	throttle = 1.0
	await frames(180)
	var moving_load := diesel.engine_load
	var moving_density := diesel.emission_density
	check(bot.body.global_position.distance_to(start) > 7.0, "Commanded heavy walker physically travels through the arena")
	check(moving_load > 0.7 and moving_density > 0.9, "Actual walking builds a dense loaded diesel plume")
	for index: int in diesel.emitters.size():
		var emitter := diesel.emitters[index]
		var marker: Node3D = visual.nodes[ScorpionDieselExhaust.OUTLETS[index]]
		check(emitter.global_position.distance_to(marker.global_position) < 0.002, "Smoke originates at the actual imported stack lip")
		check(emitter.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Particle dimensions apply bot scale only once")
		check(not emitter.local_coords and emitter.top_level, "Emitted plumes remain in world space behind the walker")
		check(emitter.amount_ratio > 0.50, "Native moving system is actively emitting its dense pressure pulses")
	await capture("walking")
	throttle = 0.0
	await frames(45)
	check(diesel.engine_load < moving_load and diesel.engine_load > 0.1, "Braking decays engine load smoothly instead of popping the trail off")
	await capture("stopping")
	await frames(180)
	check(diesel.engine_load < 0.04 and diesel.emission_density < 0.10, "Stopped walker returns to residual idle density")
	# A presentation pose turn must load the same engine even with no travel.
	var pose := visual.global_transform
	var view := bot.read_view()
	for index: int in 90:
		pose.basis = Basis(Vector3.UP, 0.016) * pose.basis
		diesel.show_state(view, pose, 1.0 / 60.0, true)
	check(diesel.engine_load > 0.30, "Turning in place loads the diesel engine")
	# Leave a freshly rendered loaded trail for the native shutdown/fade check.
	throttle = 1.0
	await frames(75)
	throttle = 0.0
	await frames(45)
	pose = visual.global_transform
	view = bot.read_view()
	var resets := diesel.reset_count
	bot.set_process(false)
	view.eliminated = true
	diesel.show_state(view, pose, 1.0 / 60.0, true)
	check(not diesel.engine_running and diesel.emission_density == 0.0, "Eliminated engine cannot produce new soot")
	check(diesel.reset_count == resets, "Elimination preserves the already emitted plume for natural dissipation")
	for emitter: GPUParticles3D in diesel.emitters: check(not emitter.emitting, "Shutdown stops every stack")
	await frames(45)
	await capture("shutdown")
	await frames(180)
	await capture("cleared")
	visual.reset_observation()
	check(diesel.reset_count == resets + 1 and diesel.engine_load == 0.0, "Explicit round reset clears old smoke and motion history at the same pose")
	view.eliminated = false
	diesel.show_state(view, pose, 1.0 / 60.0, true)
	check(diesel.engine_load == 0.0, "Fresh observation cannot synthesize a load burst")
	pose.origin.x += 30.0
	diesel.show_state(view, pose, 1.0 / 60.0, true)
	check(diesel.engine_load == 0.0 and diesel.reset_count == resets + 2, "Teleport clears trails and cannot create a speed spike")
	view.server_tick -= 1
	diesel.show_state(view, pose, 1.0 / 60.0, true)
	check(diesel.engine_load == 0.0 and diesel.reset_count == resets + 3, "Accepted tick rollback resets exhaust observation")
	print("SCORPION DIESEL movement=", bot.body.global_position.distance_to(start), " load=", moving_load, " density=", moving_density,
		" particles_per_bot=", diesel.emitters.size() * ScorpionDieselExhaust.PARTICLES_PER_STACK, " native=", native)
	bot = null
	world.queue_free()
	await get_tree().process_frame
	for message: String in failures: push_error(message)
	print("SCORPION DIESEL PASS" if failures.is_empty() else "SCORPION DIESEL FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
