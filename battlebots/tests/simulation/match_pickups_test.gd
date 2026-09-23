extends SceneTree
## Authoritative pickup rules, credit reward and live match-loadout swaps on real
## Jolt bodies. Network replication is covered by tests/network/pickup_session.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func run() -> void:
	rules()
	await world_swaps("foundry")
	await world_swaps("moon")
	await world_swaps("woodland")
	print("MATCH PICKUPS PASS" if failures == 0 else "MATCH PICKUPS FAIL")
	quit(0 if failures == 0 else 1)

func rules() -> void:
	var pickups := MatchPickups.new()
	var strict := ContentRegistry.new()
	check(not pickups.pool.has("nitro_off") and not pickups.pool.has("jump_off"), "Removing a perk never drops")
	check(not pickups.pool.has("compact") and not pickups.pool.has("wide"), "Only Customize bodies drop")
	check(pickups.pool.has("atlas_mx") and pickups.pool.has("walker") and pickups.pool.has("nitro_boost"),
		"Every Customize slot, including body, drive and perks, can drop")
	var starter := strict.starter()
	check(pickups.swapped(starter, starter.parts.weapon).is_empty(), "The same part is not picked up")
	check(pickups.swapped(starter, "nitro_boost").is_empty() and pickups.swapped(starter, "charged_jump").is_empty(),
		"An already-equipped perk is not picked up")
	var bare := starter.duplicate(true)
	bare.parts.nitro = "nitro_off"
	var nitro := pickups.swapped(bare, "nitro_boost")
	check(nitro.parts.nitro == "nitro_boost" and bare.parts.nitro == "nitro_off", "A missing perk is granted without mutating the source")
	var hammer := pickups.swapped(starter, "hammer")
	check(hammer.parts.weapon == "hammer" and hammer.parts.chassis == starter.parts.chassis, "A part replaces only its slot")
	var scorpion := pickups.swapped(starter, "scorpion_hex")
	check(scorpion.parts.chassis == "scorpion_hex" and scorpion.parts.drive == "walker", "A Scorpion body brings its walking drive")
	check(SawbladeConfig.enabled(scorpion), "A body change keeps a modular appearance record")
	var atlas := pickups.swapped(starter, "atlas_mx")
	check(atlas.parts.drive == "traction", "Atlas brings its tracks")
	check(pickups.swapped(scorpion, "standard_wheels").is_empty(), "Wheels cannot replace a Scorpion's required legs")
	var gunner := strict.scorpion()
	var balanced := pickups.swapped(gunner, "balanced")
	check(balanced.parts.utility == MatchPickups.FALLBACK_UTILITY and balanced.parts.drive == "walker",
		"A body without a gun socket drops the auxiliary gun and keeps a compatible drive")
	check(pickups.swapped(gunner, "minigun").is_empty(), "A second minigun cannot share the gun socket")
	var heavy := gunner.duplicate(true)
	heavy.parts.armor = "heavy"
	heavy.parts.weapon = "horizontal_spinner"
	check(not strict.validate(heavy).valid and pickups.registry.validate(heavy).valid,
		"Pickups are a bonus above the build budget; lobby validation stays strict")
	check(strict.enforce_budget, "A default registry keeps enforcing the budget")

	pickups.begin([Vector3.ZERO, Vector3(5, 0, 5)], 7)
	check(pickups.items.size() == 2 and pickups.items.all(func(item: Dictionary) -> bool: return item.available),
		"Every point starts stocked")
	var item: Dictionary = pickups.items[0]
	item.kind = "credits"
	item.part = ""
	item.amount = 50
	var event := pickups.collect(item, 3, starter)
	check(event.kind == "credits" and pickups.credits[3] == 50 and not item.available, "Credits add to the picker's match tally")
	check(pickups.collect(item, 3, starter).is_empty(), "A collected item cannot be taken twice")
	item.available = true
	item.amount = 25
	pickups.collect(item, 3, starter)
	check(pickups.credits[3] == 75, "Credit pickups accumulate")
	var perk: Dictionary = pickups.items[1]
	perk.kind = "perk"
	perk.part = "nitro_boost"
	var before := pickups.revision
	check(pickups.collect(perk, 4, starter).is_empty() and perk.available and pickups.revision == before,
		"An ignored perk pickup stays in the world")
	check(pickups.refusals.size() == 1 and pickups.refusals[0].entity == 4 and pickups.refusals[0].reason == "equipped"
		and pickups.refusals[0].part == "nitro_boost", "A refused pickup reports why to its toucher")
	pickups.tick(0.0)
	pickups.collect(perk, 4, starter)
	check(pickups.refusals.is_empty(), "A bot parked on a refused item is told once, not every tick")
	pickups.tick(0.0)
	pickups.tick(0.0)
	pickups.collect(perk, 4, starter)
	check(pickups.refusals.size() == 1, "Driving back onto a refused item tells the player again")
	pickups.tick(0.0)
	var wheels := {"id":9, "kind":"part", "part":"standard_wheels", "amount":0, "available":true}
	pickups.collect(wheels, 5, scorpion)
	check(pickups.refusals.size() == 1 and pickups.refusals[0].reason == "incompatible", "An unfittable part reports incompatibility")
	pickups.tick(MatchPickups.RESPAWN_SECONDS - 0.1)
	check(not item.available, "Collected items wait for their respawn")
	pickups.tick(0.2)
	check(item.available, "Collected items restock after the respawn delay")
	item.available = false
	pickups.reset_round()
	check(item.available and pickups.credits[3] == 75, "A new round restocks points and keeps match credits")
	var reward := MatchPickups.reward({"damage":257, "eliminations":2, "assists":1}, true, 75)
	check(reward.performance == 50 + 150 + 100 + 20 + 25 and reward.pickups == 75
		and reward.total == reward.performance + 75, "Post-match reward combines performance and pickups")
	check(MatchPickups.reward({}, false, 0).total == MatchPickups.REWARD_PARTICIPATION, "Every finisher earns participation")
	var public := pickups.snapshot()
	check(public.items.size() == 2 and not public.items[0].has("respawn") and public.credits[3] == 75,
		"Public state omits timers and carries match credits")

func place(world: AuthorityWorld, bot: MvpBot, point: Vector3) -> void:
	bot.body.reset_pose = world.clear_spawn_pose(bot, Transform3D(Basis.IDENTITY, point))
	bot.body.linear_velocity = Vector3.ZERO
	bot.body.angular_velocity = Vector3.ZERO

func force(world: AuthorityWorld, kind: String, part: String, amount := 0) -> Dictionary:
	var item: Dictionary = world.pickups.items[0]
	item.kind = kind
	item.part = part
	item.amount = amount
	item.available = true
	return item

func step(world: AuthorityWorld, count := 1) -> void:
	for index: int in range(count):
		world.step(1.0 / 60.0, true, 1)
		await physics_frame
		await process_frame

func world_swaps(arena_id: String) -> void:
	var world := AuthorityWorld.new()
	world.arena_id = arena_id
	root.add_child(world)
	var registry := world.registry
	var picker := world.spawn(1, 0, 0, registry.starter(), 1)
	var rival := world.spawn(2, 1, 0, registry.starter(true), 1)
	check(picker != null and rival != null, arena_id + " duel spawns")
	world.begin_pickups(11)
	var points := world.pickup_points()
	check(points.size() == 5 and world.pickups.items.size() == 5, arena_id + " stocks five pickup points")
	for item: Dictionary in world.pickups.items:
		for bot: MvpBot in [picker, rival]:
			check(not world.touches_pickup(bot, item.point) or bot.body.global_position.distance_to(bot.spawn_pose.origin) > 1.0,
				arena_id + " no pickup overlaps a spawn")
	for point: Vector3 in points:
		check(ArenaBounds.contains(point, ArenaBounds.half_extent(arena_id), 6.0), arena_id + " pickup lies well inside the walls")
	var changes: Array[int] = []
	world.loadout_changed.connect(func(id: int) -> void: changes.append(id))
	await frames(2)
	var center: Vector3 = world.pickups.items[0].point

	# Credits: tally only, same bot instance.
	force(world, "credits", "", 100)
	place(world, picker, center)
	await frames(3)
	check(world.touches_pickup(picker, center) and not world.touches_pickup(rival, center), arena_id + " contact test uses hull footprint")
	var standing := picker.body.global_position
	var half_height: float = picker.collision_bounds().size.y * 0.5
	picker.body.global_position = standing + Vector3.UP * 8.0
	check(world.touches_pickup(picker, center), arena_id + " a jumping bot inside the light beam collects")
	picker.body.global_position = Vector3(center.x, center.y + MatchPickups.REACH_UP + half_height - 0.1, center.z)
	check(world.touches_pickup(picker, center), arena_id + " the hull touching the top of the beam collects")
	picker.body.global_position = Vector3(center.x, center.y + MatchPickups.REACH_UP + half_height + 0.5, center.z)
	check(not world.touches_pickup(picker, center), arena_id + " a bot above the beam does not collect")
	picker.body.global_position = Vector3(center.x, center.y - half_height - MatchPickups.REACH_DOWN - 0.5, center.z)
	check(not world.touches_pickup(picker, center), arena_id + " a bot well below the point does not collect")
	picker.body.global_position = standing
	await step(world)
	check(world.pickups.credits.get(1, 0) == 100 and world.bots[1] == picker and changes.is_empty(),
		arena_id + " credit pickup tallies without touching the bot")

	# Weapon swap: new node, fresh weapon, damage fractions and counters retained.
	picker.combat.damage("front", 60.0)
	picker.combat.zones.weapon = 0.0
	picker.combat.effective_damage = 42
	picker.combat.eliminations = 1
	picker.combat.recent_attackers[2] = 1.0
	picker.combat.overheated = true
	picker.combat.heat = 80.0
	var core_fraction: float = picker.combat.core / picker.combat.stats.core
	var front_fraction: float = picker.combat.zones.front / picker.combat.stats.plate_integrity
	force(world, "part", "hammer")
	await step(world)
	var armed: MvpBot = world.bots[1]
	check(armed != picker, arena_id + " weapon swap rebuilds the bot")
	check(armed.loadout.parts.weapon == "hammer" and armed.combat.stats.weapon == "hammer", arena_id + " picked weapon is installed")
	check(is_equal_approx(armed.combat.core / armed.combat.stats.core, core_fraction), arena_id + " core fraction carries over")
	check(is_equal_approx(armed.combat.zones.front / armed.combat.stats.plate_integrity, front_fraction), arena_id + " plate damage carries over")
	check(armed.combat.zones.weapon == 140.0, arena_id + " the picked weapon arrives intact")
	check(armed.combat.effective_damage == 42 and armed.combat.eliminations == 1 and armed.combat.recent_attackers.has(2),
		arena_id + " score counters and attacker credit carry over")
	check(armed.combat.overheated, arena_id + " shared overheat lock carries over")
	check(changes == [1] and armed.get_parent() == world and armed.name == "Bot1", arena_id + " swap announces and keeps the entity identity")
	check(armed.body.global_position.distance_to(center) < 8.0, arena_id + " swap keeps the bot where it stood")

	# Perk: equipped perk ignored, missing perk granted on the same instance.
	force(world, "perk", "nitro_boost")
	await step(world)
	check(world.pickups.items[0].available and world.bots[1] == armed, arena_id + " an equipped perk stays in the world")
	var bare := armed.loadout.duplicate(true)
	bare.parts.nitro = "nitro_off"
	world.apply_loadout(1, bare)
	check(world.bots[1] == armed and not armed.combat.stats.nitro and not armed.body.nitro_equipped, arena_id + " perk-only change updates in place")
	force(world, "perk", "nitro_boost")
	await step(world)
	check(world.bots[1] == armed and armed.combat.stats.nitro and armed.body.nitro_equipped
		and armed.loadout.parts.nitro == "nitro_boost" and not world.pickups.items[0].available,
		arena_id + " a missing perk is granted for the match")

	# Body swap: required drive, new collision, raised clear of the floor.
	force(world, "part", "atlas_mx")
	await step(world)
	var atlas: MvpBot = world.bots[1]
	check(atlas != armed and atlas.loadout.parts.chassis == "atlas_mx" and atlas.loadout.parts.drive == "traction",
		arena_id + " body pickup rebuilds with its required drive")
	check(atlas.collision_bounds().size.is_equal_approx(AtlasGeometry.COLLISION_SIZE * atlas.body.geometry_scale),
		arena_id + " body pickup installs the new collision")
	await step(world, 90)
	var rest := atlas.body.global_position.y - center.y
	check(rest > -0.5 and rest < 6.0, arena_id + " rebuilt body settles on the floor (%.2f m above the point)" % rest)
	check(not atlas.combat.eliminated, arena_id + " rebuilt body stays in the match")

	# Rounds keep the match loadout; reset restocks.
	world.reset_round()
	await frames(3)
	check(world.bots[1].loadout.parts.chassis == "atlas_mx" and world.pickups.items[0].available,
		arena_id + " a new round keeps the match loadout and restocks")
	# Practice NPCs never collect.
	var npc: MvpBot = world.bots[2]
	npc.set_meta("practice_variant", "wedge")
	force(world, "part", "saw")
	place(world, npc, center)
	place(world, world.bots[1], center + Vector3(0, 0, 12) if arena_id == "moon" else center + Vector3(30, 0, 0))
	await frames(3)
	await step(world)
	check(world.pickups.items[0].available and world.bots[2] == npc, arena_id + " practice NPCs keep their training builds")
	world.clear_bots()
	check(world.pickups.items.is_empty(), arena_id + " clearing the match clears pickups")
	world.queue_free()
	await frames(2)
