extends Node3D
## F6: real Jolt overlap/sweep and impulse checks, without arena/UI dependencies.
## Bodies retain their full catalogue colliders. No floor, gravity, damping or
## physical chassis contacts can masquerade as an authored weapon impulse.
var failures := 0
var attacker: MvpBot
var victim: MvpBot
var weapons: CombatWorld
var bots: Dictionary
var tick := 0
const ORIGIN := Vector3(0, 10, 0)
const SIDE := Vector3(1.65, 10, -2.1)

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func flush_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func reset_case(target: Vector3, source := ORIGIN, yaw := 0.0) -> void:
	weapons = CombatWorld.new()
	for bot: MvpBot in [attacker, victim]:
		bot.body.freeze = true
		bot.body.linear_velocity = Vector3.ZERO
		bot.body.angular_velocity = Vector3.ZERO
		bot.combat = CombatState.new(bot.combat.stats)
		bot.previous_velocity = Vector3.ZERO
	attacker.body.global_transform = Transform3D(Basis(Vector3.UP, yaw), source)
	victim.body.global_transform = Transform3D(Basis.IDENTITY, target)
	attacker.team = 0
	victim.team = 1
	await flush_physics()
	attacker.previous_pose = attacker.body.global_transform
	victim.previous_pose = victim.body.global_transform
	attacker.combat.charge = 1.0

func strike(delta := 1.0 / 60.0) -> void:
	tick += 1
	weapons.step(delta, bots, tick, 3)

func expect_miss(label: String) -> void:
	var before := victim.combat.core
	strike()
	check(weapons.events.is_empty() and victim.combat.core == before,
		label + ": no damage/event")
	check(attacker.combat.charge == 1.0, label + ": no charge consumed")

func run() -> void:
	var registry := ContentRegistry.new()
	var build := registry.starter()
	build.parts.weapon = "horizontal_spinner"
	attacker = MvpBot.create(1, 0, build, registry)
	victim = MvpBot.create(2, 1, registry.starter(), registry)
	if attacker == null or victim == null:
		push_error("Horizontal spinner must assemble from canonical catalogue")
		get_tree().quit(1)
		return
	for bot: MvpBot in [attacker, victim]:
		add_child(bot)
		bot.body.gravity_scale = 0
		bot.body.linear_damp = 0
		bot.body.angular_damp = 0
		bot.body.collision_mask = 0
		bot.body.freeze = true
	bots = {1: attacker, 2: victim}

	# This full-size victim is beyond the old vertical spinner's narrow box.
	await reset_case(SIDE)
	strike()
	check(weapons.events.size() == 1, "Wide horizontal edge reaches a side-offset enemy")
	check(is_equal_approx(victim.combat.zones.left, 50.0)
		and is_equal_approx(victim.combat.core, 230.0),
		"Full charge deals 40 raw: 40 left plate plus 30 core through standard armor")
	check(attacker.combat.effective_damage == 70, "Damage credit matches actual plate/core loss")
	check(is_equal_approx(attacker.combat.charge, 0.4), "Registered hit consumes 60% charge")
	if not weapons.events.is_empty():
		var event: Dictionary = weapons.events[0]
		check(event.attacker == 1 and event.target == 2 and event.tick == tick
			and event.round == 3 and event.attack_id > 0 and event.zone == "left",
			"Authoritative event identifies attack, target, server tick, round and actual zone")
	await reset_case(Vector3(1.65, 10, -1.3))
	strike()
	check(is_equal_approx(victim.combat.zones.drive_left, 70.0)
		and is_equal_approx(victim.combat.core, 250.0)
		and attacker.combat.effective_damage == 40,
		"Drive-pod contact splits 40 raw into 30 component and 10 core damage")

	await reset_case(Vector3(0, 10, 2.3))
	expect_miss("Enemy behind chassis")
	await reset_case(Vector3(2.2, 10, -1.2))
	expect_miss("Enemy outside blade radius")
	await reset_case(Vector3(0, 10.6, -1.8))
	expect_miss("Enemy above thin horizontal blade")
	await reset_case(Vector3(0, 9.4, -1.8))
	expect_miss("Enemy below thin horizontal blade")

	await reset_case(SIDE)
	attacker.combat.charge = 0.249
	strike()
	check(weapons.events.is_empty(), "Below 25% charge cannot strike")
	attacker.combat.charge = 0.25
	strike()
	check(weapons.events.size() == 1 and is_equal_approx(victim.combat.zones.left, 80.0)
		and is_equal_approx(victim.combat.core, 252.5),
		"25% threshold deals exactly 10 raw damage")
	var core_after := victim.combat.core
	attacker.combat.charge = 1.0
	strike(0.299)
	check(weapons.events.is_empty() and victim.combat.core == core_after,
		"Same-target cooldown lasts at least 0.3 seconds")
	strike(0.002)
	check(weapons.events.size() == 1 and victim.combat.core < core_after,
		"Same-target contact can strike after cooldown expires")

	await reset_case(SIDE)
	victim.team = attacker.team
	attacker.body.freeze = false
	victim.body.freeze = false
	await flush_physics()
	expect_miss("Friendly target")
	await flush_physics()
	check(attacker.body.linear_velocity.is_zero_approx()
		and victim.body.linear_velocity.is_zero_approx(),
		"Friendly contact applies no authored attack or recoil impulse")
	await reset_case(SIDE)
	attacker.combat.zones.weapon = 0
	expect_miss("Disabled weapon")
	await reset_case(SIDE)
	attacker.combat.overheated = true
	expect_miss("Overheated weapon")
	await reset_case(SIDE)
	victim.combat.eliminate("fixture")
	expect_miss("Eliminated target")

	# Both endpoint poses miss. Only movement between ticks crosses the target.
	var crossed_target := Vector3(0, 10, -1.2)
	await reset_case(crossed_target, Vector3(-5, 10, 0))
	expect_miss("Translation start endpoint")
	await reset_case(crossed_target, Vector3(5, 10, 0))
	expect_miss("Translation finish endpoint")
	attacker.previous_pose = Transform3D(Basis.IDENTITY, Vector3(-5, 10, 0))
	strike()
	check(weapons.events.size() == 1, "Fast translation hits between endpoint poses")

	# Half-turn carries the front blade around the left side. Interpolating only
	# the two weapon-center positions would sweep a chord and miss this bot.
	var arc_target := Vector3(-2.8, 10, 0)
	await reset_case(arc_target)
	expect_miss("Turning start endpoint")
	await reset_case(arc_target, ORIGIN, PI - 0.001)
	expect_miss("Turning finish endpoint")
	attacker.previous_pose = Transform3D(Basis.IDENTITY, ORIGIN)
	strike()
	check(weapons.events.size() == 1, "Turning sweep covers the blade's arc between poses")

	# Read velocities only after Jolt consumes the actual impulses. The victim is
	# slightly higher, so accidentally using a 3D direction would impart lift.
	await reset_case(SIDE + Vector3.UP * 0.1)
	attacker.body.freeze = false
	victim.body.freeze = false
	await flush_physics()
	strike()
	await flush_physics()
	var target_velocity := victim.body.linear_velocity
	var recoil_velocity := attacker.body.linear_velocity
	check(weapons.events.size() == 1, "Impulse case registers exactly one hit")
	check(absf(target_velocity.y) < 0.001 and absf(recoil_velocity.y) < 0.001,
		"Horizontal spinner authors no upward/downward velocity")
	check(absf(target_velocity.length() - 4.0) < 0.01,
		"Actual target impulse produces 4 m/s lateral velocity")
	var expected_recoil := 4.0 * victim.body.mass / attacker.body.mass * 0.6
	check(absf(recoil_velocity.length() - expected_recoil) < 0.01
		and recoil_velocity.dot(target_velocity) < 0,
		"Jolt applies opposite attacker recoil at 60% of target impulse")
	check(victim.body.angular_velocity.length() <= 12.001
		and attacker.body.angular_velocity.length() <= 12.001,
		"Physical impact preserves the simulation angular speed cap")
	print("Horizontal physical velocities: target=", target_velocity, " recoil=", recoil_velocity)
	print("HORIZONTAL SPINNER PHYSICS PASS" if failures == 0 else "HORIZONTAL SPINNER PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)
