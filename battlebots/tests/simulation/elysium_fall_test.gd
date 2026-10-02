extends SceneTree
## Elysium lethal edges (#115): the islands hold a bot that stays on them, a
## bridge carries it across the chasm, a balustrade gives way to a bot that
## rams it, while driving off the Halo's rim, falling
## into the chasm or a cloud well is fatal (the wreck keeps falling, out of
## collision, into the clouds), and Practice returns the player afterwards.
## godot --headless --path battlebots --script res://tests/simulation/elysium_fall_test.gd
const GROUND = preload("res://scripts/arena/elysium_ground.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func tick(world: AuthorityWorld, count: int, drive: MvpBot = null) -> void:
	for index: int in count:
		if drive != null:
			var command := BotCommand.new()
			command.sequence = drive.last_sequence + 1
			command.throttle = 1.0
			drive.submit_command(command)
		world.step(STEP, true, 0)
		await physics_frame

func place(bot: MvpBot, at: Vector2, yaw: float) -> void:
	var y := GROUND.height_at(at.x, at.y)
	for dx: float in [-4.0, 0.0, 4.0]:
		for dz: float in [-4.0, 0.0, 4.0]:
			if GROUND.on_land(at.x + dx, at.y + dz):
				y = maxf(y, GROUND.height_at(at.x + dx, at.y + dz))
	bot.body.reset_pose = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y + bot.ground_clearance() + 0.3, at.y))
	bot.body.sleeping = false

## Yaw that points the bot's -Z forward along dir.
static func facing(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)

func run() -> void:
	var cfg: RefCounted = GROUND.settings()
	var world := AuthorityWorld.new()
	world.arena_id = "elysium"
	root.add_child(world)
	await physics_frame
	var bot := world.spawn(1, 0, 0, world.registry.starter(true), 1)
	check(is_finite(cfg.kill_y), "Elysium has a kill height")
	await tick(world, 120)
	check(not bot.combat.eliminated and is_equal_approx(bot.lethal_fall_y, cfg.kill_y), "Elysium arms the lethal fall")
	var settled := bot.body.global_position
	await tick(world, 120)
	check(not bot.combat.eliminated and bot.body.global_position.distance_to(settled) < 0.3,
		"A bot on its start pad settles and stays put, alive (from %s to %s)" % [str(settled), str(bot.body.global_position)])
	# Up the bridge from the Halo onto the Sanctum, alive.
	place(bot, Vector2(0, 76), facing(Vector2(0, -1)))
	await tick(world, 20)
	await tick(world, 420, bot)
	var at := bot.body.global_position
	check(not bot.combat.eliminated and at.z < GROUND.sanctum_radius(PI * 0.5) - 2.0 and at.y > float(cfg.sanctum.height) - 0.5,
		"A bridge carries a bot over the chasm onto the Sanctum (at %s)" % str(at))
	# Ramming a balustrade on the Sanctum's edge breaks it (#115): the bot
	# carries on through and over the edge.
	world.reset_round()
	await tick(world, 5)
	var rail_bearing := 0.49
	var outward := Vector2(cos(rail_bearing), sin(rail_bearing))
	var rail: String = world.props.props.keys().filter(func(n: String) -> bool:
		var spot: Vector3 = world.props.props[n].at
		return world.props.props[n].kind == "balustrade" and Vector2(spot.x, spot.z).normalized().dot(outward) > 0.999)[0]
	place(bot, outward * 25.0, facing(outward))
	await tick(world, 20)
	await tick(world, 480, bot)
	check(world.props.destroyed.has(rail), "Ramming the balustrade breaks it (%s)" % rail)
	check(bot.combat.eliminated and bot.combat.elimination_reason == MvpBot.FALL_REASON,
		"A bot that rams through a balustrade goes over the edge (at %s)" % str(bot.body.global_position))
	# Off the Halo's outer rim.
	world.reset_round()
	await tick(world, 5)
	check(not bot.combat.eliminated and bot.body.collision_layer != 0 and not bot.body.freeze, "A new round restores the bot")
	var bearing := PI * 0.25
	var out := Vector2(cos(bearing), sin(bearing))
	place(bot, out * (GROUND.halo_outer(bearing) - 16.0), facing(out))
	await tick(world, 20)
	await tick(world, 600, bot)
	check(bot.combat.eliminated and bot.combat.elimination_reason == MvpBot.FALL_REASON,
		"Driving off the rim is fatal (at %s, eliminated %s)" % [str(bot.body.global_position), bot.combat.eliminated])
	check(bot.body.collision_layer == 0, "A fallen wreck leaves collision")
	var falling := bot.body.global_position.y
	await tick(world, 30)
	check(bot.body.global_position.y < falling - 1.0 or bot.body.freeze, "The wreck keeps falling")
	await tick(world, 600)
	check(bot.body.freeze and bot.body.global_position.y < float(cfg.art.cloud_sea_y),
		"The wreck comes to rest out of sight below the clouds (%.1f m)" % bot.body.global_position.y)
	# Into the chasm between the Sanctum and the Halo, between the bridges.
	world.reset_round()
	await tick(world, 5)
	var gap := (GROUND.sanctum_radius(bearing) + GROUND.halo_inner(bearing)) * 0.5
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(out.x * gap, 3.0, out.y * gap))
	bot.body.sleeping = false
	await tick(world, 150)
	check(bot.combat.eliminated and bot.combat.elimination_reason == MvpBot.FALL_REASON, "The chasm is fatal")
	# Down a cloud well.
	world.reset_round()
	await tick(world, 5)
	var well: Dictionary = GROUND.wells()[0]
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(well.at.x, 3.0, well.at.y))
	bot.body.sleeping = false
	await tick(world, 150)
	check(bot.combat.eliminated and bot.combat.elimination_reason == MvpBot.FALL_REASON, "A cloud well is fatal")
	world.queue_free()
	await physics_frame
	# Practice returns the player after a fall.
	var session := MvpSession.new()
	root.add_child(session)
	check(session.practice(session.registry.starter(), "elysium") == OK, "Elysium practice starts")
	for index: int in 5:
		await physics_frame
	var player: MvpBot = session.local_source()
	player.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 3, 140))
	player.body.sleeping = false
	for index: int in 150:
		await physics_frame
	check(player.combat.eliminated and player.combat.elimination_reason == MvpBot.FALL_REASON, "The practice player falls off the edge")
	for index: int in 60 * 5:
		await physics_frame
	player = session.local_source()
	check(not player.combat.eliminated and GROUND.on_land(player.body.global_position.x, player.body.global_position.z),
		"Practice returns the player to the islands (at %s)" % str(player.body.global_position))
	session.leave()
	session.queue_free()
	await physics_frame
	for failure: String in failures:
		push_error(failure)
	print("ELYSIUM FALL PASS" if failures.is_empty() else "ELYSIUM FALL FAIL")
	quit(0 if failures.is_empty() else 1)
