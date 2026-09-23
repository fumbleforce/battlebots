extends SceneTree
## Heavy-machine physics from data/bot_physics.json, measured on real Jolt bodies.
const DROP_HEIGHT := 6.0
const TIMING_TOLERANCE := 0.1
const APEX_TOLERANCE := 0.12
const RAM_SPEED := 8.0
const AUTHORED_JUMP_SPEED := 6.0
const MOON_GRAVITY_SCALE := 1.62 / 9.8
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
	await ram_rebound()
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
	check(is_equal_approx(bot.body.hull_friction(), physics.hull_friction_at_1g), "Moon keeps 1 g hull friction")
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
	a.body.linear_velocity = Vector3.FORWARD * RAM_SPEED
	b.body.linear_velocity = Vector3.BACK * RAM_SPEED
	var rammed := false
	for index: int in range(60):
		world.step(1.0 / 60, true, 1)
		await physics_frame
		if world.weapons.events.any(func(event: Dictionary) -> bool: return event.kind == "ram"):
			rammed = true
			break
	await frames(3, true)
	var separating := (a.body.linear_velocity - b.body.linear_velocity).dot(b.body.global_position - a.body.global_position)
	print("Ram separation velocity dot: ", separating)
	check(rammed and separating < 0.0, "Heavy rams rebound the hulls apart")
