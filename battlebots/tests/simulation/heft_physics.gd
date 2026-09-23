extends SceneTree
## Heavy-machine physics from data/bot_physics.json, measured on real Jolt bodies.
const DROP_HEIGHT := 6.0
const TIMING_TOLERANCE := 0.1
const APEX_TOLERANCE := 0.12
const AUTHORED_JUMP_SPEED := 6.0
const MOON_GRAVITY_SCALE := 1.62 / 9.8
## A knocked hull with released throttle must bite in, not skate away.
const KNOCK_SPEED := 8.0
const MAX_KNOCK_SLIDE := 3.0
const STOPPED_SPEED := 0.3
## Flipper: stays low while charging, then launches and flips its target.
const LIFTER_CHARGE_FRAMES := 66
const LIFTER_OBSERVE_FRAMES := 150
const MAX_CHARGE_RISE := 0.05
const MIN_LAUNCH_RISE := 2.0
const MIN_FLIP_DEGREES := 150.0
var failures := 0
var world: AuthorityWorld
var physics := BotPhysics.settings()
var earth_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int, active := false) -> void:
	for index: int in range(count):
		world.step(1.0 / 60, active, 1)
		await physics_frame
	await process_frame

func run() -> void:
	config_validation()
	world = AuthorityWorld.new()
	root.add_child(world)
	var bot := world.spawn(1, 0, 0, world.registry.starter())
	await frames(2)
	await fall_time(bot)
	await jump_apex(bot)
	moon_exemption(bot)
	await knock_slide(bot, Vector3.RIGHT)
	await knock_slide(bot, Vector3.BACK)
	await ram_rebound()
	await flipper_launch()
	if failures == 0:
		print("HEFT PHYSICS PASS")
	quit(failures)

func config_validation() -> void:
	check(physics.gravity_multiplier > 1.0, "Heft makes bots heavier than arena gravity")
	var source := FileAccess.get_file_as_string(BotPhysics.PATH)
	var broken: Dictionary = JSON.parse_string(source)
	broken.impacts.erase("weapon_impulse_multiplier")
	var problems: Array[String] = []
	check(BotPhysics.from_json(JSON.stringify(broken), problems) == null and problems.size() == 1,
		"Missing tuning fields are rejected, never defaulted")

## A hull dropped from rest lands in sqrt(2h / (g * heft)) seconds.
func fall_time(bot: MvpBot) -> void:
	var rest_height: float = bot.combat.stats.size.y * 0.5
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3.UP * (rest_height + DROP_HEIGHT))
	bot.body.sleeping = false
	await frames(1)
	var elapsed := 0.0
	while bot.body.global_position.y > rest_height + 0.05 and elapsed < 3.0:
		await frames(1)
		elapsed += 1.0 / 60
	var expected := sqrt(2.0 * DROP_HEIGHT / (earth_gravity * physics.gravity_multiplier))
	print("Heft fall: %.3fs expected %.3fs (1 g would be %.3fs)" % [elapsed, expected, sqrt(2.0 * DROP_HEIGHT / earth_gravity)])
	check(absf(elapsed - expected) < TIMING_TOLERANCE, "Hulls fall under heft gravity")
	await frames(60)

## Launch speeds scale by sqrt(heft): apex height matches the authored 1 g jump.
func jump_apex(bot: MvpBot) -> void:
	var authored_speed := AUTHORED_JUMP_SPEED
	var start := bot.body.global_position.y
	bot.body.queue_jump(authored_speed)
	var apex := start
	for index: int in range(90):
		await frames(1)
		apex = maxf(apex, bot.body.global_position.y)
	var expected := authored_speed * authored_speed / (2.0 * earth_gravity)
	print("Heft jump apex: %.3fm expected %.3fm" % [apex - start, expected])
	check(absf(apex - start - expected) < APEX_TOLERANCE, "Heft keeps authored jump height")
	check(bot.body.model_config().gravity.is_equal_approx(Vector3.DOWN * earth_gravity * physics.gravity_multiplier),
		"Client replay uses the same heft gravity as live Jolt")

func moon_exemption(bot: MvpBot) -> void:
	bot.body.gravity_scale = MOON_GRAVITY_SCALE
	check(is_equal_approx(bot.body.heft(), 1.0) and is_equal_approx(bot.body.model_config().gravity.y, -earth_gravity * MOON_GRAVITY_SCALE),
		"Moon keeps its authored low gravity")
	bot.body.gravity_scale = 1.0

## Plastic Jolt contacts stop rams dead; the configured knock-back separates hulls.
func ram_rebound() -> void:
	world.clear_bots()
	await frames(2)
	var a := world.spawn(1, 0, 0, world.registry.starter())
	var b := world.spawn(2, 1, 0, world.registry.starter())
	var length: float = a.combat.stats.size.z
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, length))
	b.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -length))
	await frames(60)
	b.body.reset_pose = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1, -length))
	await frames(2)
	# Both drivers hold full throttle into each other, as in a real ram.
	var rammed := false
	for index: int in range(120):
		for bot: MvpBot in [a, b]:
			var command := BotCommand.new()
			command.sequence = bot.last_sequence + 1
			command.throttle = 1.0
			bot.submit_command(command)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		if world.weapons.events.any(func(event: Dictionary) -> bool: return event.kind == "ram"):
			rammed = true
			break
	await frames(3, true)
	var separating := (a.body.linear_velocity - b.body.linear_velocity).dot(b.body.global_position - a.body.global_position)
	print("Ram separation velocity dot: ", separating)
	check(rammed and separating < 0.0, "Heavy rams rebound the hulls apart")

## Released-throttle hull knocked sideways or backward stops within MAX_KNOCK_SLIDE.
func knock_slide(bot: MvpBot, direction: Vector3) -> void:
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3.UP * bot.combat.stats.size.y)
	await frames(60)
	var start := bot.body.global_position
	bot.body.linear_velocity = direction * KNOCK_SPEED
	for index: int in range(120):
		var command := BotCommand.new()
		command.sequence = bot.last_sequence + 1
		bot.submit_command(command)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		if bot.body.linear_velocity.length() < STOPPED_SPEED:
			break
	var slide := bot.body.global_position.distance_to(start)
	print("Knock slide %s: %.2fm" % [direction, slide])
	check(slide < MAX_KNOCK_SLIDE, "Knocked heavy hull bites into the floor instead of sliding")

func lifter_tick(attacker: MvpBot, victim: MvpBot, held: bool, pressed: bool) -> void:
	for bot: MvpBot in [attacker, victim]:
		var command := BotCommand.new()
		command.sequence = bot.last_sequence + 1
		command.brake = true
		command.primary_held = held and bot == attacker
		command.primary_pressed = pressed and bot == attacker
		bot.submit_command(command)
	world.step(1.0 / 60, true, 1)
	await physics_frame

## Atlas flipper against a grounded hull: no floating during charge, one
## violent launch that throws the target up and over.
func flipper_launch() -> void:
	world.clear_bots()
	await frames(2)
	var draft := world.registry.atlas()
	draft.parts.weapon = "lifter"
	var attacker := world.spawn(1, 0, 0, draft)
	var victim := world.spawn(2, 1, 0, world.registry.starter())
	var length: float = victim.combat.stats.size.z
	attacker.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, attacker.combat.stats.size.y, length * 0.66))
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, victim.combat.stats.size.y, -length * 0.47))
	for index: int in range(120):
		await lifter_tick(attacker, victim, false, false)
	var rest := victim.body.global_position.y
	var charge_peak := rest
	await lifter_tick(attacker, victim, true, true)
	for index: int in range(LIFTER_CHARGE_FRAMES):
		await lifter_tick(attacker, victim, true, false)
		charge_peak = maxf(charge_peak, victim.body.global_position.y)
	var apex := rest
	var lowest_up := 1.0
	for index: int in range(LIFTER_OBSERVE_FRAMES):
		await lifter_tick(attacker, victim, false, false)
		apex = maxf(apex, victim.body.global_position.y)
		lowest_up = minf(lowest_up, victim.body.global_basis.y.dot(Vector3.UP))
	var flip := rad_to_deg(acos(clampf(lowest_up, -1, 1)))
	print("Flipper: charge rise %.2fm, launch rise %.2fm, flip %.0f deg" % [charge_peak - rest, apex - rest, flip])
	check(charge_peak - rest < MAX_CHARGE_RISE, "Charging flipper stays low instead of floating its target")
	check(apex - rest > MIN_LAUNCH_RISE and flip > MIN_FLIP_DEGREES, "Released flipper violently launches and flips its target")
