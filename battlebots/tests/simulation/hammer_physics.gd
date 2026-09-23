extends Node3D
## Independent F6 test: real Jolt body queries, separated chassis and actual
## overhead contact. The fixture removes gravity/chassis collision, not hit shapes.
var failures := 0
var attacker: MvpBot
var victim: MvpBot
var weapons: CombatWorld
var bots: Dictionary
var tick := 0
const ORIGIN := Vector3(0, 10, 0) * BotScale.FACTOR
const TARGET := Vector3(0, 10, -2) * BotScale.FACTOR

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

func reset_case(target := TARGET, source := ORIGIN, yaw := 0.0) -> void:
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
	attacker.combat.attack_id = 7
	attacker.combat.strike = true

func resolve(delta := 1.0 / 60.0) -> void:
	tick += 1
	weapons.step(delta, bots, tick, 2)

func expect_miss(label: String) -> void:
	var before := victim.combat.snapshot()
	resolve()
	check(weapons.events.is_empty() and victim.combat.core == before.core
		and victim.combat.zones == before.zones, label + ": no damage/event")

func run() -> void:
	var registry := ContentRegistry.new()
	var build := registry.starter()
	build.parts.chassis = "compact"
	build.parts.weapon = "hammer"
	attacker = MvpBot.create(1, 0, build, registry)
	# Victim carries a 70 HP top machinery guard so the overhead blow exercises
	# plate shielding and overflow into the core.
	var armoured := registry.starter()
	var pieces := SawbladeConfig.defaults()
	pieces.armor_top = 1
	armoured.cosmetics = {"paint":"cyan", "sawblade":pieces}
	victim = MvpBot.create(2, 1, registry.starter(), registry)
	# Plain starter hull keeps the canonical hit geometry; only the combat state
	# carries the armour pieces (a Sawblade loadout would add its rear-pack collider).
	if victim != null:
		victim.combat = CombatState.new(registry.validate(armoured).stats)
	if attacker == null or victim == null:
		push_error("Hammer must assemble from the canonical catalogue")
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

	await reset_case()
	var armor_before := victim.combat.zones.duplicate()
	resolve()
	check(weapons.events.size() == 1, "Separated chassis still receive an overhead hammer strike")
	armor_before.top = 32.0
	check(is_equal_approx(victim.combat.core, 240.0) and victim.combat.zones == armor_before,
		"Top contact applies 38 raw to the intact top guard, shielding the core and leaving side armor/components intact")
	check(attacker.combat.effective_damage == 38, "Hammer damage credit counts plate plus core loss")
	if not weapons.events.is_empty():
		var event: Dictionary = weapons.events[0]
		check(event.zone == "top" and event.attack_id == 7 and event.attacker == 1
			and event.target == 2 and event.tick == tick and event.round == 2,
			"Actual overhead event records top zone and accepted activation/server tick")
		check(is_equal_approx(event.position.y, 10.25 * BotScale.FACTOR), "Impact position lies on the victim's top face")
	var damaged := victim.combat.core
	resolve()
	check(weapons.events.is_empty() and victim.combat.core == damaged,
		"Repeated world step cannot duplicate one activation's target hit")
	resolve(2.0)
	check(weapons.events.is_empty() and victim.combat.core == damaged,
		"Activation deduplication survives elapsed recovery time")
	attacker.combat.attack_id = 8
	resolve()
	check(weapons.events.size() == 1 and victim.combat.core < damaged,
		"A distinct activation may strike the same target")
	check(is_equal_approx(victim.combat.zones.top, 0.0) and is_equal_approx(victim.combat.core, 234.0),
		"Second 38 raw strips the remaining 32 top HP and overflows 6 into the core")
	await reset_case(Vector3(-0.7, 10, -2) * BotScale.FACTOR)
	var second_target := MvpBot.create(3, 1, registry.starter(), registry)
	add_child(second_target)
	second_target.body.freeze = true
	second_target.body.collision_mask = 0
	second_target.body.global_position = Vector3(0.7, 10, -2) * BotScale.FACTOR
	second_target.previous_pose = second_target.body.global_transform
	bots[3] = second_target
	await flush_physics()
	resolve()
	var targets: Array = []
	for event: Dictionary in weapons.events:
		targets.append(event.target)
		check(event.attack_id == 7, "One multi-target swing keeps one activation identifier")
	check(targets.size() == 2 and targets.has(2) and targets.has(3),
		"One overhead swing can strike two enemies once each")
	resolve(2.0)
	check(weapons.events.is_empty(), "Repeated multi-target swing cannot damage either target twice")
	bots.erase(3)
	second_target.queue_free()
	await flush_physics()

	for item: Array in [
		[Vector3(0, 10, 2) * BotScale.FACTOR, "Behind chassis"],
		[Vector3(2, 10, -2) * BotScale.FACTOR, "Outside the narrow hammer arc"],
		[Vector3(0, 10, -3.4) * BotScale.FACTOR, "Beyond forward reach"],
		[Vector3(0, 12.5, -2) * BotScale.FACTOR, "Above maximum head height"],
		[Vector3(0, 8.8, -2) * BotScale.FACTOR, "Below completed swing"],
	]:
		await reset_case(item[0])
		expect_miss(item[1])
	await reset_case()
	attacker.combat.strike = false
	expect_miss("Inactive hammer")
	await reset_case()
	attacker.combat.zones.weapon = 0
	expect_miss("Disabled hammer")
	await reset_case()
	attacker.combat.overheated = true
	attacker.combat.heat = 100.0
	var overheated_press := BotCommand.new()
	overheated_press.primary_pressed = true
	attacker.combat.tick(1.0 / 60.0, overheated_press, true)
	expect_miss("Overheated hammer")
	await reset_case()
	victim.combat.eliminate("fixture")
	expect_miss("Destroyed victim")
	await reset_case()
	attacker.combat.eliminate("fixture")
	expect_miss("Destroyed attacker")
	await reset_case()
	victim.team = attacker.team
	attacker.body.freeze = false
	victim.body.freeze = false
	await flush_physics()
	expect_miss("Friendly victim")
	await flush_physics()
	check(attacker.body.linear_velocity.is_zero_approx() and victim.body.linear_velocity.is_zero_approx(),
		"Friendly hammer applies neither attack nor recoil impulse")

	# Drive the genuine state machine into contact: a held command cannot bypass
	# windup, strike twice on following ticks, or activate during recovery.
	await reset_case()
	attacker.combat = CombatState.new(attacker.combat.stats)
	var command := BotCommand.new()
	command.primary_pressed = true
	command.primary_held = true
	attacker.combat.tick(1.0 / 60.0, command, true)
	expect_miss("Accepted press is still winding up")
	command.primary_pressed = false
	var registered := 0
	for frame: int in range(30):
		attacker.combat.tick(1.0 / 60.0, command, true)
		resolve()
		registered += weapons.events.size()
	check(registered == 1, "Windup completion emits exactly one real physical hit")
	command.primary_pressed = true
	attacker.combat.tick(1.0 / 60.0, command, true)
	expect_miss("Press during recovery cannot hit")
	attacker.combat.tick(1.0, command, false)
	expect_miss("Inactive round cannot hit")

	# Each stationary endpoint misses, while the moving hammer passes through.
	var crossing_target := Vector3(1.2, 10, -2) * BotScale.FACTOR
	await reset_case(crossing_target, Vector3(-3, 10, 0) * BotScale.FACTOR)
	expect_miss("Translation start endpoint")
	await reset_case(crossing_target, Vector3(3, 10, 0) * BotScale.FACTOR)
	expect_miss("Translation finish endpoint")
	attacker.previous_pose = Transform3D(Basis.IDENTITY, Vector3(-3, 10, 0) * BotScale.FACTOR)
	resolve()
	check(weapons.events.size() == 1, "Fast translation is swept through a target between endpoints")
	var turning_target := Vector3(-2.05, 10, 0.6) * BotScale.FACTOR
	await reset_case(turning_target)
	expect_miss("Turning start endpoint")
	await reset_case(turning_target, ORIGIN, PI - 0.001)
	expect_miss("Turning finish endpoint")
	attacker.previous_pose = Transform3D(Basis.IDENTITY, ORIGIN)
	resolve()
	check(weapons.events.size() == 1, "Body yaw and descending head arc are swept together")
	# Enemy blow: knockback away from the attacker, a lift and a drive stagger.
	await reset_case()
	attacker.body.freeze = false
	victim.body.freeze = false
	await flush_physics()
	resolve()
	await flush_physics()
	check(weapons.events.size() == 1, "Free bodies still register the staggering blow")
	check(victim.body.linear_velocity.z < -1.5 and victim.body.linear_velocity.y > 1.0,
		"Hammer knocks the victim away and off the floor: %s" % victim.body.linear_velocity)
	check(attacker.body.linear_velocity.z > 0.1, "Attacker takes a small recoil")
	check(victim.combat.stagger_seconds > 0.7 and victim.combat.stagger_factor() < 0.2,
		"Hammer staggers the victim drive control")
	check(is_equal_approx(attacker.combat.stagger_factor(), 1.0), "Attacker is not staggered")
	victim.step(1.0 / 60.0, true)
	check(victim.body.drive_multiplier < 0.25 and victim.body.steering_multiplier < 0.25
		and victim.body.grip_multiplier < 0.5, "Stagger reduces drive, steering and grip")
	victim.combat.stagger(0.1, 0.2)
	check(victim.combat.stagger_seconds > 0.7 and victim.combat.stagger_depth >= 0.85,
		"A lighter follow-up hit never shortens or softens a stagger")
	for step: int in 60: victim.step(1.0 / 60.0, true)
	check(is_equal_approx(victim.combat.stagger_factor(), 1.0) and is_equal_approx(victim.body.grip_multiplier, 1.0),
		"Control fully returns after the stagger")
	victim.combat.stagger(NAN, 1.0)
	victim.combat.stagger(1.0, INF)
	check(is_equal_approx(victim.combat.stagger_factor(), 1.0), "Invalid stagger is ignored")
	print("HAMMER PHYSICS PASS" if failures == 0 else "HAMMER PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)
