extends SceneTree
## #71 destructible Woodland props on real arena colliders: which props break,
## railgun slugs through a felled tree, saws, mortar blasts and rams, the
## replicated state a client adopts, and the round reset.
const PROPS := preload("res://scripts/simulation/arena_props.gd")
const GROUND := preload("res://scripts/arena/woodland_ground.gd")
var failures: Array[String] = []
var world: AuthorityWorld

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func settle(frames := 3) -> void:
	for frame: int in frames:
		await physics_frame

func first(kind: String) -> String:
	for name: String in world.props.props:
		if world.props.props[name].kind == kind and not world.props.destroyed.has(name):
			return name
	return ""

func frozen(bot: MvpBot) -> MvpBot:
	bot.body.reset_pose = null
	bot.body.gravity_scale = 0
	bot.body.collision_mask = 0
	bot.body.freeze = true
	return bot

func run() -> void:
	world = AuthorityWorld.new()
	world.arena_id = "woodland"
	root.add_child(world)
	await settle()
	var counts := {}
	for name: String in world.props.props:
		counts[world.props.props[name].kind] = int(counts.get(world.props.props[name].kind, 0)) + 1
		check(not name.begins_with("Mesa") and not name.begins_with("Terrace"), "Arena structure never breaks: " + name)
	check(counts.get("tree", 0) > 10 and counts.get("barricade", 0) > 0 and counts.get("boulder", 0) > 0,
		"Woodland trees, barricades and outcrop boulders are destructible: %s" % str(counts))
	check(world.weapons.props == world.props, "Combat resolves against the world's props")
	await railgun()
	await saw()
	mortar_and_ram()
	await replication()
	world.reset_round()
	check(world.props.destroyed.is_empty() and world.weapons.props == world.props, "A new round rebuilds every prop")
	for name: String in world.props.props:
		var prop: Dictionary = world.props.props[name]
		check(prop.body.collision_layer == prop.layer and is_equal_approx(prop.hp, prop.max), "Reset restores %s" % name)
	var problems: Array[String] = []
	check(PROPS.from_json("{}", problems).is_empty() and not problems.is_empty(), "Missing prop tuning is rejected")
	for failure: String in failures:
		push_error(failure)
	print("ARENA PROPS PASS" if failures.is_empty() else "ARENA PROPS FAIL")
	quit(0 if failures.is_empty() else 1)

## A tree and a level approach whose line meets its trunk first and is clear
## for the bot hiding behind it: [name, height point, direction] or [].
func clear_line(space: PhysicsDirectSpaceState3D) -> Array:
	for name: String in world.props.props:
		if world.props.props[name].kind != "tree":
			continue
		var height: Vector3 = world.props.props[name].at + Vector3.UP * 3.0
		for step: int in 8:
			var direction := Vector3.FORWARD.rotated(Vector3.UP, step * TAU / 8.0)
			var approach := space.intersect_ray(PhysicsRayQueryParameters3D.create(height - direction * 20.0, height, BaselineConfig.WORLD_LAYER))
			var beyond := space.intersect_ray(PhysicsRayQueryParameters3D.create(height + direction * 1.0, height + direction * 16.0, BaselineConfig.WORLD_LAYER))
			if world.props.prop_at(approach.get("collider_id", 0)) == name and beyond.is_empty():
				return [name, height, direction]
	return []

## A railgun slug fells a tree and flies on into the bot hiding behind it.
func railgun() -> void:
	var line := clear_line(world.get_world_3d().direct_space_state)
	check(not line.is_empty(), "Woodland has a tree with a clear firing line")
	if line.is_empty():
		return
	var tree: String = line[0]
	var height: Vector3 = line[1]
	var direction: Vector3 = line[2]
	var draft := world.registry.atlas()
	draft.parts.utility = "turret_railgun"
	var shooter := frozen(world.spawn(1, 0, 0, draft))
	var hiding := frozen(world.spawn(2, 1, 0, world.registry.starter()))
	shooter.body.global_position = height - direction * 30.0
	hiding.body.global_position = height + direction * 10.0
	await settle()
	var end := height - direction * 30.0 + direction * 140.0
	var query := PhysicsRayQueryParameters3D.create(height - direction * 20.0, end,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [shooter.body.get_rid()])
	var result := shooter.body.get_world_3d().direct_space_state.intersect_ray(query)
	check(world.props.prop_at(result.get("collider_id", 0)) == tree, "The slug's first contact is the tree trunk")
	world.weapons.events.clear()
	world.weapons.pending_hits.clear()
	world.weapons._railgun_path(shooter, world.bots, result, end, direction, 1, 0)
	var tuning := TurretTuning.settings()
	var needed: float = world.props.props[tree].max / world.props.multiplier("railgun", "tree")
	var carried: float = (tuning.value("railgun", "damage") - needed) * tuning.value("railgun", "overpenetration_retain")
	check(world.props.destroyed.has(tree) and world.props.destroyed[tree].kind == "railgun", "The railgun fells the tree")
	check(world.props.props[tree].body.collision_layer == 0, "A felled tree stops blocking at once")
	check(world.weapons.pending_hits.size() == 1 and world.weapons.pending_hits[0][1] == hiding
		and is_equal_approx(world.weapons.pending_hits[0][3], carried),
		"The slug carries its unspent energy into the bot behind: %s" % str(world.weapons.pending_hits.map(func(hit: Array) -> float: return hit[3])))
	world.clear_bots()
	await settle()


## A running saw fells a tree in its reach within a couple of seconds.
func saw() -> void:
	var tree := first("tree")
	var at: Vector3 = world.props.props[tree].at
	var draft := world.registry.starter()
	draft.parts.weapon = "saw"
	var sawyer := frozen(world.spawn(1, 0, 0, draft))
	var size: Vector3 = sawyer.combat.stats.size
	sawyer.body.global_transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 1.0, size.z * 0.5 + GROUND.TRUNK_RADIUS * 0.5))
	await settle()
	var seconds := 0.0
	while not world.props.destroyed.has(tree) and seconds < 3.0:
		sawyer.combat.weapon_phase = "active"
		sawyer.combat.charge = 1.0
		world.weapons.step(1.0 / 60.0, world.bots, 10, 0)
		seconds += 1.0 / 60.0
	check(world.props.destroyed.has(tree) and world.props.destroyed[tree].kind == "saw",
		"A saw fells a tree in its reach (%.2f s)" % seconds)
	var expected: float = world.props.props[tree].max / (ARENA_DPS("saw") * world.props.multiplier("saw", "tree"))
	check(absf(seconds - expected) < 0.1, "Sawing takes the configured time: %.2f vs %.2f s" % [seconds, expected])
	world.clear_bots()
	await settle()

func ARENA_DPS(weapon: String) -> float:
	return float(PROPS.settings().melee[weapon].dps)

## Mortar blasts wear props down with distance; rams batter them.
func mortar_and_ram() -> void:
	var barricade := first("barricade")
	var at: Vector3 = world.props.props[barricade].at
	var before: float = world.props.props[barricade].hp
	var shooter := frozen(world.spawn(1, 0, 0, world.registry.atlas()))
	world.weapons._shells.append({"attacker":1, "point":at + Vector3.UP, "lands":world.weapons.time})
	world.weapons._detonate_shells(world.bots, 1, 0)
	var tuning := TurretTuning.settings()
	check(is_equal_approx(before - world.props.props[barricade].hp, tuning.value("mortar", "damage") * world.props.multiplier("mortar", "barricade")),
		"A shell landing on a barricade deals full blast damage to it")
	var boulder := first("boulder")
	var rock: Vector3 = world.props.props[boulder].at
	var rock_hp: float = world.props.props[boulder].hp
	shooter.body.global_position = rock + Vector3(0, 2, 8)
	shooter.previous_velocity = Vector3(0, 0, -12)
	shooter.body.contact_bodies = [world.props.props[boulder].body.get_instance_id()]
	world.weapons._ram_props(world.bots)
	var rule: Dictionary = PROPS.settings().ram
	var expected: float = (12.0 - rule.min_closing_speed) * rule.damage_per_speed * shooter.body.mass / rule.reference_mass * world.props.multiplier("ram", "boulder")
	check(is_equal_approx(rock_hp - world.props.props[boulder].hp, expected), "Ramming a boulder at speed batters it")
	world.weapons._ram_props(world.bots)
	check(is_equal_approx(rock_hp - world.props.props[boulder].hp, expected), "Rams on one prop respect their cooldown")
	world.clear_bots()

## A client world adopts the server's broken props and drops the same colliders.
func replication() -> void:
	var tree := first("tree")
	world.props.damage(tree, 1000.0, "cannon", world.props.props[tree].at, Vector3.RIGHT)
	var state: Dictionary = bytes_to_var(var_to_bytes(world.props.snapshot()))
	var client := AuthorityWorld.new()
	client.arena_id = "woodland"
	root.add_child(client)
	await settle()
	check(client.props.accept(state) and client.props.destroyed.has(tree), "A client adopts the broken props")
	check(client.props.props[tree].body.collision_layer == 0, "The client drops the same collider")
	var bad := state.duplicate(true)
	bad.destroyed["NoSuchProp"] = ["cannon", Vector3.ZERO, Vector3.UP]
	check(not client.props.accept(bad), "Unknown props are rejected")
	var healed := {"revision":state.revision + 1, "destroyed":{}}
	check(client.props.accept(healed) and client.props.props[tree].body.collision_layer != 0, "A reset from the server restores the collider")
	client.queue_free()
	await settle()
