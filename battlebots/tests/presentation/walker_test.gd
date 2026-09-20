extends Node3D
var failures: Array[String] = []
var bot: MvpBot
var throttle := 0.0
var steering := 0.0
var ticks := 0
var peak_y := 0.0
var visual_legs: WalkerLegs

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ready() -> void:
	run.call_deferred()

func _physics_process(delta: float) -> void:
	if bot == null or bot.body == null: return
	ticks += 1
	var command := BotCommand.new()
	command.sequence = ticks
	command.throttle = throttle
	command.steering = steering
	command.brake = is_zero_approx(throttle) and is_zero_approx(steering)
	bot.submit_command(command)
	bot.step(delta, true)
	peak_y = maxf(peak_y, bot.body.global_position.y)

func block(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)

func wait_ticks(count: int) -> void:
	for frame: int in count: await get_tree().physics_frame

func run() -> void:
	get_window().size = Vector2i(1280, 720)
	block(Vector3(0, -0.25, 0), Vector3(18, 0.5, 24), Color("253543"))
	block(Vector3(0, 0.175, 0), Vector3(5, 0.35, 2.4), Color("64757b"))
	block(Vector3(0, 0.35, -2.4), Vector3(5, 0.70, 2.4), Color("89969b"))
	block(Vector3(0, 1.5, -5.5), Vector3(5, 3, 0.5), Color("3f5263"))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("16222e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.5
	add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 45
	var registry := ContentRegistry.new()
	var draft := SawbladeConfig.starter(registry)
	draft.parts.drive = "walker"
	draft.parts.weapon = "hammer"
	check(registry.validate(draft).valid, "Walking hammer build is legal")
	bot = MvpBot.create(1, 0, draft, registry)
	bot.position = Vector3(0, 0.5, 4.5)
	add_child(bot)
	if bot.sawblade_visual != null:
		visual_legs = bot.sawblade_visual.walker_legs
	else:
		visual_legs = WalkerLegs.new()
		bot.presentation.add_child(visual_legs)
		visual_legs.exclusions = [bot.body.get_rid()]
		visual_legs.assemble(bot.combat.stats.size, null, draft.cosmetics.sawblade)
	await wait_ticks(120)
	check(bot.body.grounded, "Legs establish support")
	check(absf(bot.body.global_position.y - WalkerDrive.RIDE_HEIGHT) < 0.08, "Leg forces hold authored ride height")
	check(bot.body.walker_contacts.size() == 4, "Four footholds on flat ground")
	throttle = 1
	await wait_ticks(115)
	throttle = 0
	await wait_ticks(50)
	print("WALKER CLIMB pose=", bot.body.global_position, " peak_y=", peak_y)
	check(peak_y > 1.50, "Physically climbs two 0.35 m steps")
	check(bot.body.global_position.z < -1.2, "Moves onto the raised platform")
	check(bot.body.global_basis.y.dot(Vector3.UP) > 0.85, "Stance remains upright after climbing")
	for leg: Dictionary in visual_legs.legs:
		var foot: Vector3 = leg.foot_mesh.global_position
		var floor_y := 0.7 if foot.z >= -3.6 and foot.z < -1.2 else (0.35 if absf(foot.z) <= 1.2 else 0.0)
		check(foot.y >= floor_y - 0.025, "IK feet do not penetrate raised surfaces")
		if leg.time >= 1.0:
			check(foot.distance_to(leg.foot) < 0.035, "Reachable planted foot matches terrain contact")
	camera.position = bot.body.global_position + Vector3(4, 2.5, 3.5)
	camera.look_at(bot.body.global_position + Vector3.UP * 0.15)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-walker.png"))
	throttle = 1
	await wait_ticks(180)
	check(bot.body.global_position.z > -5.1, "Cannot climb a three-meter wall")
	throttle = 0
	# An unsupported inverted walker must fall; stance is not a free self-right.
	bot.body.reset_pose = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(7, 3, 3))
	await wait_ticks(20)
	check(not bot.body.grounded and bot.body.walker_contacts.is_empty(), "Inversion disables foot support")
	check(bot.body.global_position.y < 2.7, "Unsupported legs obey gravity")
	bot.body.gravity_scale = 1.62 / 9.8
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(7, 1, 3))
	await wait_ticks(90)
	check(absf(bot.body.global_position.y - WalkerDrive.RIDE_HEIGHT) < 0.08, "Walker stance supports lunar gravity")
	for ankle: Vector3 in [Vector3(0.3, -0.9, 0.1), Vector3(-0.2, -1.0, 0), Vector3(0.5, -0.6, 0.3)]:
		var knee := WalkerLegs.solve_knee(Vector3.ZERO, ankle, Vector3.RIGHT)
		check(absf(knee.length() - WalkerLegs.UPPER) < 0.001, "IK preserves upper segment length")
		check(absf(knee.distance_to(ankle) - WalkerLegs.LOWER) < 0.001, "IK bends lower segment to foot target")
	if failures.is_empty(): print("WALKER PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
