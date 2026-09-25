extends SceneTree
## Hit stagger slows a moving target (#89): a bot cruising at full throttle
## through minigun fire loses ground speed with every bullet, instead of only
## losing drive acceleration it does not need at top speed.
const START := Vector3(0, 0, 12)
const RUN_UP_FRAMES := 90
const FIRE_FRAMES := 60
## The minigun fires about 12 times a second.
const FIRE_INTERVAL_FRAMES := 5
## Under sustained fire the mean speed must fall at least this far below the
## unshot run, and a single bullet must visibly check the hull's speed.
const MIN_SUSTAINED_SLOWDOWN := 0.2
const MIN_SINGLE_HIT_SLOWDOWN := 0.5
var failures := 0
var world: AuthorityWorld
var physics := BotPhysics.settings()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(physics.stagger_speed_bleed > 0.0, "Stagger bleeds speed (data/bot_physics.json impacts.stagger_speed_bleed)")
	world = AuthorityWorld.new()
	root.add_child(world)
	var unshot := await cruise(false)
	var shot := await cruise(true)
	print("Stagger speed: unshot %.2f m/s, under minigun fire %.2f m/s, single hit %.2f -> %.2f m/s"
		% [unshot.mean, shot.mean, shot.before_hit, shot.after_hit])
	check(unshot.mean > 1.0, "The unshot target reaches cruising speed")
	check(shot.mean < unshot.mean * (1.0 - MIN_SUSTAINED_SLOWDOWN), "Sustained minigun fire slows a moving target")
	var depth: float = CombatWorld.STAGGER.minigun[1]
	var expected: float = shot.before_hit * depth * physics.stagger_speed_bleed
	check(shot.before_hit - shot.after_hit > expected * MIN_SINGLE_HIT_SLOWDOWN, "Each bullet checks the target's ground speed")
	if failures == 0:
		print("STAGGER SPEED PASS")
	quit(failures)

func drive(bot: MvpBot, throttle: float) -> void:
	var command := BotCommand.new()
	command.sequence = bot.last_sequence + 1
	command.throttle = throttle
	command.brake = throttle == 0.0
	bot.submit_command(command)

func tick() -> void:
	world.step(1.0 / 60, true, 1)
	await physics_frame

## Full throttle towards -Z; with fire, the attacker's minigun hits every
## FIRE_INTERVAL_FRAMES. Returns mean speed while firing and the first hit's effect.
func cruise(fire: bool) -> Dictionary:
	world.clear_bots()
	await tick()
	var draft := world.registry.starter()
	draft.parts.weapon = "minigun"
	var attacker := world.spawn(1, 0, 0, draft)
	var victim := world.spawn(2, 1, 0, world.registry.starter())
	var height: float = victim.combat.stats.size.y
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, START + Vector3.UP * height)
	attacker.body.reset_pose = Transform3D(Basis.IDENTITY, START + Vector3(8, height, 0))
	for index: int in range(RUN_UP_FRAMES):
		drive(victim, 1.0)
		drive(attacker, 0.0)
		await tick()
	var total := 0.0
	var before_hit := -1.0
	var after_hit := -1.0
	for index: int in range(FIRE_FRAMES):
		if fire and index % FIRE_INTERVAL_FRAMES == 0:
			var speed := victim.body.linear_velocity.slide(Vector3.UP).length()
			world.weapons._apply_hit(attacker, victim, victim.body.global_position, CombatWorld.MINIGUN_DAMAGE,
				Vector3.ZERO, world.tick, 1, 0.0, "minigun", "top")
			if before_hit < 0.0:
				before_hit = speed
		drive(victim, 1.0)
		drive(attacker, 0.0)
		await tick()
		if fire and index == 0:
			after_hit = victim.body.linear_velocity.slide(Vector3.UP).length()
		total += victim.body.linear_velocity.slide(Vector3.UP).length()
	return {"mean":total / FIRE_FRAMES, "before_hit":before_hit, "after_hit":after_hit}
