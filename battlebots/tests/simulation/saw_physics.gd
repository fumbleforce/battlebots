extends Node3D
## Independent F6 checks against real Jolt colliders. Empty space and disabled
## chassis collision isolate the saw query, timing, damage and authored impulses.
var failures := 0
var attacker: MvpBot
var victim: MvpBot
var weapons: CombatWorld
var bots: Dictionary
var tick := 0
const ORIGIN := Vector3(0, 10, 0) * BotScale.FACTOR
const TARGET := Vector3(0, 10, -2.6) * BotScale.FACTOR

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

func place(bot: MvpBot, position: Vector3, yaw := 0.0) -> void:
	bot.body.global_transform = Transform3D(Basis(Vector3.UP, yaw), position)
	await flush_physics()
	bot.previous_pose = bot.body.global_transform

func reset_case(target := TARGET, source := ORIGIN, yaw := 0.0) -> void:
	weapons = CombatWorld.new()
	for bot: MvpBot in [attacker, victim]:
		bot.body.freeze = true
		bot.body.linear_velocity = Vector3.ZERO
		bot.body.angular_velocity = Vector3.ZERO
		bot.combat = CombatState.new(bot.combat.stats)
		bot.previous_velocity = Vector3.ZERO
	attacker.team = 0
	victim.team = 1
	await place(attacker, source, yaw)
	await place(victim, target)
	attacker.combat.weapon_phase = "active"
	attacker.combat.charge = 1.0

func resolve(count := 1) -> Array:
	var impacts: Array = []
	for frame: int in range(count):
		tick += 1
		weapons.step(1.0 / 60.0, bots, tick, 4)
		impacts.append_array(weapons.events.duplicate(true))
	return impacts

func verify_restart(label: String) -> void:
	check(resolve(19).is_empty(), label + ": new contact waits a full cadence")
	check(resolve().size() == 1, label + ": new contact strikes on its twentieth tick")

func run() -> void:
	var registry := ContentRegistry.new()
	var build := registry.starter()
	build.parts.weapon = "saw"
	attacker = MvpBot.create(1, 0, build, registry)
	victim = MvpBot.create(2, 1, registry.starter(), registry)
	if attacker == null or victim == null:
		push_error("Saw must assemble from the canonical catalogue")
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
	check(resolve().is_empty() and victim.combat.core == 260.0, "First contact is not immediate damage")
	check(resolve(18).is_empty(), "Nineteen contact ticks are shorter than one damage cadence")
	var first := resolve()
	check(first.size() == 1 and is_equal_approx(victim.combat.zones.rear, 84.0)
		and is_equal_approx(victim.combat.core, 255.5),
		"Twentieth contact tick deals exactly 6 raw to rear plate and 4.5 core through standard armor")
	if not first.is_empty():
		check(first[0].zone == "rear" and first[0].attacker == 1 and first[0].target == 2
			and first[0].tick == tick and first[0].round == 4 and first[0].attack_id > 0,
			"Cadence event identifies the actual zone, target, attack and server tick")
	var next := resolve(40)
	check(next.size() == 2 and is_equal_approx(victim.combat.zones.rear, 72.0)
		and is_equal_approx(victim.combat.core, 246.5),
		"One second of maintained contact yields three pulses and exactly 18 raw damage")
	if first.size() == 1 and next.size() == 2:
		check(first[0].attack_id != next[0].attack_id and next[0].attack_id != next[1].attack_id,
			"Separate cadence impacts receive distinct deduplication identifiers")
	await reset_case(Vector3(0.8, 10.1, -1.4) * BotScale.FACTOR)
	check(resolve(20).size() == 1 and is_equal_approx(victim.combat.zones.drive_left, 95.5)
		and is_equal_approx(victim.combat.core, 258.5),
		"Drive-pod contact routes 6 raw into 4.5 component and 1.5 core damage once")
	await reset_case(Vector3(0, 9.6, -1.4) * BotScale.FACTOR)
	var top := resolve(20)
	check(top.size() == 1 and top[0].zone == "top" and is_equal_approx(victim.combat.core, 254.3)
		and victim.combat.zones.rear == 90.0 and victim.combat.zones.weapon == 140.0,
		"Blade contacting top applies baseline reduction without damaging unrelated zones")

	await reset_case()
	resolve(19)
	await place(victim, Vector3(0, 10, -5) * BotScale.FACTOR)
	check(resolve().is_empty(), "Separation prevents a pending damage pulse")
	await place(victim, TARGET)
	verify_restart("Separation clears accrued contact")
	await reset_case()
	var passing_hits := 0
	for pass_index: int in range(6):
		await place(victim, TARGET)
		passing_hits += resolve(10).size()
		await place(victim, Vector3(0, 10, -5) * BotScale.FACTOR)
		passing_hits += resolve().size()
	check(passing_hits == 0 and victim.combat.core == 260,
		"Repeated brief mobile contacts cannot accumulate into sustained-contact damage")
	await reset_case()
	resolve(19)
	tick += 60 # AuthorityWorld skips CombatWorld entirely while the round is inactive.
	verify_restart("Skipped inactive world ticks clear accrued contact")
	await reset_case()
	resolve(19)
	tick += 1
	weapons.step(1.0 / 60.0, bots, tick, 5)
	check(weapons.events.is_empty(), "A new round cannot consume the preceding round's contact time")
	for interruption: String in ["release", "secondary", "inactive", "disabled", "overheated"]:
		await reset_case()
		resolve(19)
		var command := BotCommand.new()
		command.primary_held = interruption != "release"
		command.secondary_held = interruption == "secondary"
		if interruption == "disabled":
			attacker.combat.zones.weapon = 0
		if interruption == "overheated":
			attacker.combat.overheated = true
			attacker.combat.heat = 100
		attacker.combat.tick(1.0 / 60.0, command, interruption != "inactive")
		check(resolve().is_empty(), interruption + " suppresses contact damage")
		attacker.combat.zones.weapon = 140
		attacker.combat.overheated = false
		attacker.combat.heat = 0
		attacker.combat.weapon_phase = "active"
		attacker.combat.charge = 1
		verify_restart(interruption + " clears accrued contact")

	# Stagger arrival by half a cadence: one victim must not borrow the other's
	# progress or share a single attacker-wide cooldown.
	await reset_case(Vector3(-0.7, 10, -2.6) * BotScale.FACTOR)
	check(resolve(10).is_empty(), "First target starts its own contact timer")
	var other := MvpBot.create(3, 1, registry.starter(), registry)
	add_child(other)
	other.body.freeze = true
	other.body.collision_mask = 0
	await place(other, Vector3(0.7, 10, -2.6) * BotScale.FACTOR)
	bots[3] = other
	var a := resolve(10)
	var b := resolve(10)
	check(a.size() == 1 and a[0].target == 2 and b.size() == 1 and b[0].target == 3,
		"Every target independently accumulates a full third-second of contact")
	bots.erase(3)
	other.queue_free()
	await flush_physics()

	for point: Vector3 in [Vector3(1.1, 10, -2.6) * BotScale.FACTOR, Vector3(0, 10, -3) * BotScale.FACTOR, Vector3(0, 11, -2.6) * BotScale.FACTOR, Vector3(0, 10, 2) * BotScale.FACTOR]:
		await reset_case(point)
		check(resolve(60).is_empty(), "Side/height/range/rear miss cannot accrue contact damage: " + str(point))
	await reset_case()
	victim.team = attacker.team
	check(resolve(60).is_empty(), "Friendly bodies never take saw damage")
	await reset_case()
	victim.combat.eliminate("fixture")
	check(resolve(60).is_empty(), "Destroyed target never takes saw damage")

	# Accrue real contact, then move through on the final cadence tick. Each
	# stationary endpoint misses, so only the between-tick sweep can finish it.
	await reset_case()
	resolve(19)
	await place(attacker, Vector3(3, 10, 0) * BotScale.FACTOR)
	attacker.previous_pose = Transform3D(Basis.IDENTITY, Vector3(-3, 10, 0) * BotScale.FACTOR)
	check(resolve().size() == 1, "Fast translation preserves a real swept contact on the cadence tick")
	var arc_target := Vector3(-1.4, 10, 0) * BotScale.FACTOR
	await reset_case(arc_target, ORIGIN, PI * 0.5)
	resolve(19)
	await place(attacker, ORIGIN, PI - 0.001)
	attacker.previous_pose = Transform3D(Basis.IDENTITY, ORIGIN)
	check(resolve().size() == 1, "Body yaw sweeps the blade arc through a target between endpoints")
	await reset_case(arc_target)
	check(resolve(20).is_empty(), "Yaw start endpoint alone misses")
	await reset_case(arc_target, ORIGIN, PI - 0.001)
	check(resolve(20).is_empty(), "Yaw finish endpoint alone misses")

	await reset_case()
	attacker.body.freeze = false
	victim.body.freeze = false
	await flush_physics()
	check(resolve(20).size() == 1, "Unfrozen impulse fixture receives real saw damage")
	await flush_physics()
	check(attacker.body.linear_velocity.is_zero_approx() and victim.body.linear_velocity.is_zero_approx()
		and attacker.body.angular_velocity.is_zero_approx() and victim.body.angular_velocity.is_zero_approx(),
		"Saw damage adds no authored attack or recoil impulse")
	print("SAW PHYSICS PASS" if failures == 0 else "SAW PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)
