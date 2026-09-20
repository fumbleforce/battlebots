extends Node3D
## Real Jolt ray/shape queries; frozen bodies isolate weapon contact from driving.
const STEP := 1.0 / 60.0
const ORIGIN := Vector3(0, 20, 0)
const TARGET := Vector3(0, 20, -14)
var failures := 0
var attacker: MvpBot
var victim: MvpBot
var weapons: CombatWorld
var bots: Dictionary
var tick := 0

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

func reset_case(target := TARGET, yaw := 0.0) -> void:
	weapons = CombatWorld.new()
	for bot: MvpBot in [attacker, victim]:
		bot.body.freeze = true
		bot.body.linear_velocity = Vector3.ZERO
		bot.body.angular_velocity = Vector3.ZERO
		bot.combat = CombatState.new(bot.combat.stats)
		bot.previous_velocity = Vector3.ZERO
	attacker.body.global_transform = Transform3D(Basis(Vector3.UP, yaw), ORIGIN)
	victim.body.global_transform = Transform3D(Basis.IDENTITY, target)
	attacker.team = 0
	victim.team = 1
	await flush_physics()
	attacker.previous_pose = attacker.body.global_transform
	victim.previous_pose = victim.body.global_transform

func resolve() -> Array:
	tick += 1
	weapons.step(STEP, bots, tick, 1)
	return weapons.events.duplicate(true)

func fire(count := 36, primary_press := false) -> Array:
	var command := BotCommand.new()
	command.secondary_held = true
	command.auxiliary_held = true
	var result: Array = []
	for index: int in count:
		command.primary_pressed = primary_press and index == 0
		attacker.combat.tick(STEP, command, true)
		result.append_array(resolve())
	return result

func wall_at(position: Vector3, thickness := 0.5) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = BaselineConfig.WORLD_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 10, thickness)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = position
	return wall

func run() -> void:
	var registry := ContentRegistry.new()
	attacker = MvpBot.create(1, 0, registry.scorpion(), registry)
	victim = MvpBot.create(2, 1, registry.starter(), registry)
	if attacker == null or victim == null:
		push_error("Minigun fixture must assemble canonical catalogue bots")
		get_tree().quit(1)
		return
	for bot: MvpBot in [attacker, victim]:
		add_child(bot)
		bot.body.gravity_scale = 0
		bot.body.collision_mask = 0
		bot.body.freeze = true
	bots = {1: attacker, 2: victim}
	await reset_case()
	var impacts := fire()
	check(impacts.size() == 1 and victim.combat.core < victim.combat.stats.core,
		"Full auxiliary spool resolves a real Jolt hit fourteen meters ahead")
	if impacts.size() == 1:
		check(impacts[0].kind == "minigun" and impacts[0].attacker == 1
			and impacts[0].target == 2 and impacts[0].attack_id == 1 and impacts[0].tick == tick,
			"Confirmed hit identifies minigun, authoritative attacker/target, shot and tick")
	check(attacker.combat.last_shot_tick == tick and attacker.combat.last_shot_to.z > TARGET.z,
		"Shot presentation terminates at nearest victim surface")
	var damaged := victim.combat.core
	check(resolve().is_empty() and victim.combat.core == damaged,
		"Repeated world step cannot replay the consumed shot pulse")
	check(fire(60).size() == 12, "A second of held fire yields exactly twelve physical hits")
	for point: Vector3 in [Vector3(10, 20, -14), Vector3(0, 20, 14), Vector3(0, 30, -14), Vector3(0, 20, -34)]:
		await reset_case(point)
		check(fire().is_empty() and victim.combat.core == victim.combat.stats.core,
			"Off-axis/behind/elevated/beyond-range target remains undamaged: " + str(point))
		check(attacker.combat.shot_sequence == 1 and attacker.combat.last_shot_tick == tick,
			"Miss still publishes an authoritative visual shot")
	await reset_case()
	victim.team = attacker.team
	check(fire().is_empty() and victim.combat.core == victim.combat.stats.core,
		"Friendly ray contact does no damage")
	await reset_case()
	var ally := MvpBot.create(3, 0, registry.starter(), registry)
	add_child(ally)
	ally.body.freeze = true
	ally.body.collision_mask = 0
	ally.body.global_position = Vector3(0, 20, -9)
	bots[3] = ally
	await flush_physics()
	check(fire().is_empty() and victim.combat.core == victim.combat.stats.core
		and ally.combat.core == ally.combat.stats.core,
		"Friendly blocker stops bullets before enemy without either taking damage")
	bots.erase(3)
	ally.queue_free()
	await flush_physics()
	for position: Vector3 in [Vector3(0, 20, -9), Vector3(0, 20, -4)]:
		await reset_case()
		var wall := wall_at(position)
		await flush_physics()
		check(fire().is_empty() and victim.combat.core == victim.combat.stats.core,
			"World wall blocks shot, including a wall pierced by the visual barrel")
		check(attacker.combat.last_shot_to.z > position.z - 0.3,
			"Occluded tracer terminates on wall")
		wall.queue_free()
		await flush_physics()
	await reset_case(Vector3(-14, 20, 0), PI * 0.5)
	check(fire().size() == 1, "Authoritative chassis yaw rotates minigun aim")
	await reset_case()
	attacker.combat.eliminate("fixture")
	check(fire(60).is_empty() and attacker.combat.shot_sequence == 0,
		"Eliminated bot cannot generate or resolve bullets")
	for reason: String in ["disabled", "overheated", "battery", "inactive"]:
		await reset_case()
		fire(35)
		if reason == "disabled": attacker.combat.zones.weapon = 0.0
		if reason == "overheated":
			attacker.combat.heat = 80.0
			attacker.combat.overheated = true
		if reason == "battery": attacker.combat.battery = 0.0
		var locked := BotCommand.new()
		locked.secondary_held = true
		locked.auxiliary_held = true
		attacker.combat.tick(STEP, locked, reason != "inactive")
		check(resolve().is_empty() and victim.combat.core == victim.combat.stats.core,
			reason + " cannot create physical damage after winding up")
	await reset_case()
	victim.combat.eliminate("fixture")
	check(fire().is_empty(), "Eliminated victim cannot receive further damage")
	await reset_case(Vector3(0, 20, -7.8))
	impacts = fire(40)
	impacts.append_array(fire(21, true))
	var hammer_count := 0
	var gun_count := 0
	for impact: Dictionary in impacts:
		hammer_count += int(impact.kind == "hammer")
		gun_count += int(impact.kind == "minigun")
	check(hammer_count == 1 and gun_count == 6,
		"Articulated Scorpion arch and minigun both contact the same target in one activation")
	check(weapons.events.size() == 2 and attacker.combat.strike,
		"The hammer impact and an auxiliary bullet resolve on the very same Jolt tick")
	await reset_case(Vector3(0, 20, 7.8))
	check(fire(21, true).is_empty(), "Scorpion overhead hammer cannot strike behind its tail")
	await reset_case()
	attacker.combat.stats.weapon = "minigun"
	attacker.combat.stats.secondary_weapon = ""
	var primary := BotCommand.new()
	primary.primary_held = true
	for frame: int in 36:
		attacker.combat.tick(STEP, primary, true)
		impacts = resolve()
	check(impacts.size() == 1 and impacts[0].kind == "minigun",
		"Swapped primary minigun fires via LMB without an auxiliary module")
	attacker.combat = CombatState.new(attacker.combat.stats)
	check(resolve().is_empty() and attacker.combat.shot_sequence == 0,
		"Combat reset clears stale fire without world recreation")
	await scorpion_swapped_geometry()
	await grounded_contacts(registry)
	print("MINIGUN PHYSICS PASS" if failures == 0 else "MINIGUN PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func scorpion_swapped_geometry() -> void:
	# Scorpion retains the shared appearance record, but its interchangeable
	# non-tail weapons are primitive socket modules rather than Sawblade meshes.
	await reset_case(Vector3(2.58, 20.3, -4.2))
	attacker.combat.stats.weapon = "saw"
	attacker.loadout.parts.weapon = "saw"
	check(weapons._saw_sweep(attacker).has(victim.body.get_instance_id()),
		"Scorpion saw uses the displayed primitive blade width, not Sawblade authored mesh")
	await reset_case(Vector3(0, 19.2, -6.5))
	attacker.combat.stats.weapon = "lifter"
	attacker.loadout.parts.weapon = "lifter"
	attacker.combat.charge = 1.0
	check(weapons._sweep(attacker).has(victim.body.get_instance_id()),
		"Scorpion lifter query follows the displayed primitive low front socket")
	attacker.loadout.parts.weapon = "hammer"

func grounded_contacts(registry: ContentRegistry) -> void:
	# Real walker ride height is considerably above a wheeled bot. This catches
	# the false-positive equal-height fixture that previously shot over NPCs.
	var floor := StaticBody3D.new()
	floor.collision_layer = BaselineConfig.WORLD_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 0.2, 80)
	collision.shape = shape
	floor.add_child(collision)
	add_child(floor)
	floor.position.y = -0.1
	attacker.combat = CombatState.new(registry.validate(registry.scorpion()).stats)
	weapons = CombatWorld.new()
	for bot: MvpBot in [attacker, victim]:
		bot.body.freeze = false
		bot.body.gravity_scale = 1.0
		bot.body.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	attacker.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 4, 0))
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -14))
	for frame: int in 150:
		await grounded_step(false, false)
	check(attacker.body.global_position.y > 2.0 and victim.body.global_position.y < 1.2,
		"Natural Jolt settling preserves tall walker and low wheeled hull heights")
	var before := victim.combat.core
	var shots := 0
	for frame: int in 70:
		for event: Dictionary in await grounded_step(true, false):
			shots += int(event.kind == "minigun")
	check(shots >= 5 and victim.combat.core < before,
		"Elevation servo lands real shots from settled tall Scorpion into low grounded NPC")
	check(attacker.combat.gun_pitch < -0.1 and attacker.combat.gun_pitch >= deg_to_rad(-35) - ScorpionGeometry.GUN_REST_PITCH,
		"Authority servo respects bounded depression while aiming down to a low target")
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -7.8))
	for frame: int in 100: await grounded_step(false, false)
	before = victim.combat.core
	var hammer_hits := 0
	for frame: int in 25:
		for event: Dictionary in await grounded_step(false, frame == 0):
			hammer_hits += int(event.kind == "hammer")
	check(hammer_hits == 1 and victim.combat.core < before,
		"Articulated tail reaches a low wheeled target from the real walker ride height")

func grounded_step(auxiliary: bool, hammer: bool) -> Array:
	for bot: MvpBot in [attacker, victim]:
		var command := BotCommand.new()
		command.sequence = bot.last_sequence + 1
		command.brake = true
		command.auxiliary_held = auxiliary and bot == attacker
		command.secondary_held = command.auxiliary_held
		command.primary_pressed = hammer and bot == attacker
		bot.submit_command(command)
		bot.step(STEP, true)
	var result := resolve()
	await get_tree().physics_frame
	await get_tree().process_frame
	return result
