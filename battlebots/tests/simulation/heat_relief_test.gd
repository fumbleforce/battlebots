extends SceneTree
## Heat relief (#67, #68): kill sprees vent heat and chain combos, cooling
## zones shed heat even while firing, coolant canisters vent on collection.
## Real AuthorityWorld and Jolt bodies; tuning from data/heat_relief.json.
var failures := 0
var world: AuthorityWorld
var relief := HeatRelief.settings()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int, active := true) -> void:
	for index: int in range(count):
		world.step(1.0 / 60, active, 1)
		await physics_frame

func spree() -> void:
	var state := CombatState.new(world.registry.validate(world.registry.atlas()).stats)
	state.heat = 100.0
	state.overheated = true
	state.credit_kill()
	check(state.spree == 1 and is_equal_approx(state.heat, 100.0 - relief.kill_vent(1)) and not state.overheated,
		"A kill vents heat and lifts the overheat lock: heat %.0f" % state.heat)
	state.heat = 90.0
	state.credit_kill()
	check(state.spree == 2 and is_equal_approx(state.heat, 90.0 - relief.kill_vent(2)), "A second kill in the window is a combo that vents more")
	check(relief.kill_vent(2) > relief.kill_vent(1), "Combos vent more heat")
	for index: int in 10: state.credit_kill()
	check(state.spree == int(relief.value("spree", "max_combo")), "The combo caps at max_combo")
	var idle := BotCommand.new()
	for index: int in ceili(relief.value("spree", "window_seconds") * 60.0) + 2:
		state.tick(1.0 / 60.0, idle, true)
	check(state.spree == 0, "The spree ends when the window passes without a kill")
	# Boosted cooling right after a kill.
	var plain := CombatState.new(state.stats)
	var boosted := CombatState.new(state.stats)
	plain.heat = 60.0
	boosted.heat = 100.0
	boosted.credit_kill()
	boosted.heat = 60.0
	for index: int in 60:
		plain.tick(1.0 / 60.0, idle, true)
		boosted.tick(1.0 / 60.0, idle, true)
	check(boosted.heat < plain.heat - 5.0, "Post-kill cooling boost: %.1f vs %.1f" % [boosted.heat, plain.heat])
	var record := MvpBot.create(9, 0, world.registry.atlas(), world.registry)
	root.add_child(record)
	record.combat.spree = 3
	record.combat.in_cooling_zone = true
	var decoded := WireCodec.decode_bot(WireCodec.encode_bot(record, "m:1"), record.combat.stats)
	check(not decoded.is_empty() and decoded.spree == 3 and decoded.cooling, "Snapshot carries the spree and cooling state")
	record.queue_free()

func kill_credit() -> void:
	world.clear_bots()
	await frames(2)
	var killer := world.spawn(1, 0, 0, world.registry.atlas())
	var victim := world.spawn(2, 1, 0, world.registry.starter())
	killer.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(-20, 1, 0))
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(-20, 1, -25))
	await frames(30)
	killer.combat.heat = 95.0
	victim.combat.recent_attackers[killer.entity_id] = world.weapons.time
	victim.combat.eliminate("core")
	await frames(1)
	check(killer.combat.eliminations == 1 and killer.combat.spree == 1 and killer.combat.heat < 95.0 - relief.kill_vent(1) + 1.0,
		"Eliminating a bot credits the spree and vents heat: spree %d heat %.0f" % [killer.combat.spree, killer.combat.heat])

func zones() -> void:
	world.clear_bots()
	await frames(2)
	var zones := world.cooling_zones()
	check(zones.size() == 4, "Four cooling zones per arena")
	var bot := world.spawn(1, 0, 0, world.registry.atlas())
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, zones[0] + Vector3.UP)
	await frames(30)
	bot.combat.heat = 90.0
	# Holding the primary keeps a lifter building heat; the zone still cools.
	for index: int in 60:
		var command := BotCommand.new()
		command.sequence = bot.last_sequence + 1
		command.primary_held = true
		bot.submit_command(command)
		world.step(1.0 / 60, true, 1)
		await physics_frame
	print("Zone: heat 90 -> %.1f while working the weapon, in zone %s" % [bot.combat.heat, bot.combat.in_cooling_zone])
	check(bot.combat.in_cooling_zone and bot.combat.heat < 60.0, "A cooling zone sheds heat fast even while the weapon runs")
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	await frames(5)
	check(not bot.combat.in_cooling_zone, "Leaving the zone stops zone cooling")

func coolant() -> void:
	world.clear_bots()
	await frames(2)
	var bot := world.spawn(1, 0, 0, world.registry.atlas())
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, 30))
	await frames(10)
	world.begin_pickups(7)
	var canisters := world.pickups.items.filter(func(item: Dictionary) -> bool: return item.kind == "coolant")
	check(canisters.size() == int(relief.value("coolant", "count")), "Coolant canisters spread around the arena: %d" % canisters.size())
	var point: Vector3 = canisters[0].point
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, point + Vector3.UP)
	await frames(3, false)
	bot.combat.heat = 90.0
	await frames(3)
	check(bot.combat.heat <= 90.0 - relief.value("coolant", "heat") + 1.0 and not canisters[0].available,
		"Driving over a canister vents its heat: %.0f" % bot.combat.heat)

func run() -> void:
	world = AuthorityWorld.new()
	root.add_child(world)
	await frames(2, false)
	spree()
	await kill_credit()
	await zones()
	await coolant()
	print("HEAT RELIEF PASS" if failures == 0 else "HEAT RELIEF FAIL")
	quit(mini(failures, 1))
