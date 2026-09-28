extends SceneTree
## Frozen Maelstrom lethal edges (#102): the ice holds a bot that stays on it,
## the eye and the open sea eliminate one that falls in (its wreck keeps
## sinking, out of collision), driving off the rim is fatal, other arenas keep
## the reset-to-last-floor rule, and Practice returns the player afterwards.
## godot --headless --path battlebots --script res://tests/simulation/maelstrom_fall_test.gd
const GROUND = preload("res://scripts/arena/maelstrom_ground.gd")
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

func drop(bot: MvpBot, at: Vector3) -> void:
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, at)
	bot.body.sleeping = false

func run() -> void:
	var cfg: RefCounted = GROUND.settings()
	var world := AuthorityWorld.new()
	world.arena_id = "maelstrom"
	root.add_child(world)
	await physics_frame
	var bot := world.spawn(1, 0, 0, world.registry.starter(true), 1)
	await tick(world, 180)
	# Starts lie on the cone's slope: the bot settles onto it and holds there.
	var settled := bot.body.global_position
	await tick(world, 180)
	check(not bot.combat.eliminated and Vector2(settled.x - bot.spawn_pose.origin.x, settled.z - bot.spawn_pose.origin.z).length() < 0.6
		and bot.body.global_position.distance_to(settled) < 0.3,
		"A bot on its start pad settles and stays put, alive (from %s to %s)" % [str(settled), str(bot.body.global_position)])
	# Driving through a small breakable shatters it without slowing or deflecting the bot.
	# (one with a clear run: ribs and masts stay solid for a slow bot)
	var barrel: String = world.props.props.keys().filter(func(n: String) -> bool: return world.props.props[n].kind in ["barrel", "crate", "icicle"] and _clear_run(world, n))[0]
	var target: Vector3 = world.props.props[barrel].at
	var approach := Vector3(target.x, 0, target.z).normalized()
	var start := target - approach * 14.0
	var facing := Basis(Vector3.UP, atan2(-approach.x, -approach.z))
	bot.body.reset_pose = Transform3D(facing, Vector3(start.x, _highest(start, 4.0) + bot.ground_clearance() + 0.3, start.z))
	await tick(world, 20)
	await tick(world, 180, bot)
	var past := (bot.body.global_position - target).dot(approach)
	check(world.props.destroyed.has(barrel) and past > 2.0, "Driving through a small breakable shatters it and carries on (%.1f m past, broken %s)" % [past, world.props.destroyed.has(barrel)])
	world.props.reset_round()
	world.reset_round()
	await tick(world, 5)
	# Parked on the gentle sag right beside the eye's lip, it does not slide in.
	var lip := Vector3(0, 0, cfg.eye_radius + 4.0)
	drop(bot, lip + Vector3(0, _highest(lip, 4.0) + bot.ground_clearance() + 0.3, 0))
	await tick(world, 180)
	check(not bot.combat.eliminated and Vector2(bot.body.global_position.x, bot.body.global_position.z).length() > cfg.eye_radius + 2.0,
		"A bot parked by the lip does not slide into the eye (at %s)" % str(bot.body.global_position))
	# Into the eye.
	drop(bot, Vector3(0, 3, 0))
	await tick(world, 150)
	check(bot.combat.eliminated and bot.combat.elimination_reason == GROUND.FALL_REASON, "The eye eliminates (%s)" % bot.combat.elimination_reason)
	check(bot.body.collision_layer == 0, "A swallowed wreck leaves collision")
	var sinking := bot.body.global_position.y
	await tick(world, 30)
	check(bot.body.global_position.y < sinking - 1.0 or bot.body.freeze, "The wreck keeps sinking")
	await tick(world, 300)
	check(bot.body.freeze and bot.body.global_position.y < cfg.kill_y - cfg.sink_depth + 1.0, "The wreck comes to rest out of sight (%.1f m)" % bot.body.global_position.y)
	# Over the side, into the sea.
	world.reset_round()
	await tick(world, 5)
	check(not bot.combat.eliminated and bot.body.collision_layer != 0 and not bot.body.freeze, "A new round restores the bot")
	drop(bot, Vector3(0, 3, cfg.rim_radius + 8.0))
	await tick(world, 150)
	check(bot.combat.eliminated and bot.combat.elimination_reason == GROUND.FALL_REASON, "The open sea eliminates")
	# Driving straight off the rim.
	world.reset_round()
	await tick(world, 5)
	var edge := Vector3(0, 0, cfg.rim_radius - 14.0)
	var outward := Transform3D(Basis(Vector3.UP, PI), edge + Vector3(0, _highest(edge, 4.0) + bot.ground_clearance() + 0.3, 0))
	bot.body.reset_pose = outward
	await tick(world, 600, bot)
	check(bot.combat.eliminated and bot.combat.elimination_reason == GROUND.FALL_REASON,
		"Driving off the rim is fatal (at %s, eliminated %s)" % [str(bot.body.global_position), bot.combat.eliminated])
	world.queue_free()
	await physics_frame
	# Other arenas keep the reset-to-last-floor rule.
	var woodland := AuthorityWorld.new()
	woodland.arena_id = "woodland"
	root.add_child(woodland)
	await physics_frame
	var other := woodland.spawn(1, 0, 0, woodland.registry.starter(true), 1)
	await tick(woodland, 5)
	check(not is_finite(other.lethal_fall_y), "Woodland has no lethal fall")
	drop(other, Vector3(0, -5, 60))
	await tick(woodland, 10)
	check(not other.combat.eliminated, "Woodland puts a fallen bot back instead of eliminating it")
	woodland.queue_free()
	await physics_frame
	# Practice returns the player after the maelstrom takes it.
	var session := MvpSession.new()
	root.add_child(session)
	check(session.practice(session.registry.starter(), "maelstrom") == OK, "Maelstrom practice starts")
	for index: int in 5:
		await physics_frame
	var player: MvpBot = session.local_source()
	drop(player, Vector3(0, 3, 0))
	for index: int in 150:
		await physics_frame
	check(player.combat.eliminated and player.combat.elimination_reason == GROUND.FALL_REASON, "The practice player falls into the eye")
	for index: int in 60 * 5:
		await physics_frame
	player = session.local_source()
	check(not player.combat.eliminated and GROUND.on_ice(player.body.global_position.x, player.body.global_position.z),
		"Practice returns the player to the ice (at %s)" % str(player.body.global_position))
	session.leave()
	session.queue_free()
	await physics_frame
	for failure: String in failures:
		push_error(failure)
	print("MAELSTROM FALL PASS" if failures.is_empty() else "MAELSTROM FALL FAIL")
	quit(0 if failures.is_empty() else 1)

## Highest ice within reach of a point (a hull placed on the slope clears it).
func _highest(at: Vector3, reach: float) -> float:
	var top := -INF
	for dx: float in [-reach, 0.0, reach]:
		for dz: float in [-reach, 0.0, reach]:
			top = maxf(top, GROUND.height_at(at.x + dx, at.z + dz))
	return top

## No other obstacle or prop within 9 m of the straight run from 14 m before a
## prop (on the eye side) to 10 m past it.
func _clear_run(world: AuthorityWorld, name: String) -> bool:
	var at: Vector3 = world.props.props[name].at
	var flat := Vector2(at.x, at.z)
	var dir := flat.normalized()
	var blockers: Array[Vector2] = []
	for item: Dictionary in GROUND.obstacles():
		blockers.append(Vector2(item.at.x, item.at.z))
	for other: String in world.props.props:
		if other != name:
			blockers.append(Vector2(world.props.props[other].at.x, world.props.props[other].at.z))
	for step: int in range(-14, 11):
		var p := flat + dir * step
		for blocker: Vector2 in blockers:
			if p.distance_to(blocker) < 9.0:
				return false
	return true
