extends SceneTree
## Start positions on every arena (#45): data/arena_spawns.json places the
## markers; every mode's starts stay inside the walls, apart, facing the centre,
## and practice starts at the edges instead of a central huddle.
const ARENA_SPAWNS = preload("res://scripts/core/arena_spawns.gd")
## Smallest gap (m) between two starts' bounding circles in one match; hulls
## side by side have several metres more.
const MIN_GAP := 1.0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	check_config()
	var spawns := ARENA_SPAWNS.settings()
	for arena_id: String in ArenaBounds.IDS:
		var world := AuthorityWorld.new()
		world.arena_id = arena_id
		root.add_child(world)
		await physics_frame
		for number: int in range(1, ARENA_SPAWNS.LANES + 1):
			for team: int in 2:
				var marker: Node3D = world.arena.get_node("SpawnPoints/Team%d_%d" % [team + 1, number])
				var pose := spawns.team_start(arena_id, team, number)
				check(Vector2(marker.position.x - pose.origin.x, marker.position.z - pose.origin.z).length() < 0.001
					and marker.basis.is_equal_approx(pose.basis), "%s marker %s follows the data" % [arena_id, marker.name])
		check_match(world, arena_id, "5v5", func(id: int) -> MvpBot: return world.spawn(id, 0 if id <= 5 else 1, (id - 1) % 5, world.registry.starter(), 5), 10)
		check_match(world, arena_id, "2v2", func(id: int) -> MvpBot: return world.spawn(id, 0 if id <= 2 else 1, (id - 1) % 2, world.registry.starter()), 4)
		check_match(world, arena_id, "duel", func(id: int) -> MvpBot: return world.spawn(id, id - 1, 0, world.registry.starter(), 1), 2)
		check_match(world, arena_id, "ffa", func(id: int) -> MvpBot: return world.spawn(id, id, id - 1, world.registry.starter(), 1, "ffa"), 8)
		world.queue_free()
		await process_frame
		await check_practice(arena_id)
	for failure: String in failures: push_error(failure)
	print("ARENA SPAWNS PASS" if failures.is_empty() else "ARENA SPAWNS FAIL")
	quit(0 if failures.is_empty() else 1)

func check_match(world: AuthorityWorld, arena_id: String, label: String, spawn: Callable, count: int) -> void:
	world.clear_bots()
	var bots: Array[MvpBot] = []
	for id: int in range(1, count + 1):
		bots.append(spawn.call(id))
	var half := ArenaBounds.half_extent(arena_id)
	for bot: MvpBot in bots:
		var at := bot.spawn_pose.origin
		check(ArenaBounds.contains(at, half, 1.0), "%s %s bot %d starts inside the walls" % [arena_id, label, bot.entity_id])
		var to_centre := -Vector3(at.x, 0, at.z).normalized()
		check((-bot.spawn_pose.basis.z).dot(to_centre) > 0.99, "%s %s bot %d faces the centre" % [arena_id, label, bot.entity_id])
		check(Vector2(at.x, at.z).length() > half * 0.6, "%s %s bot %d starts near the edge" % [arena_id, label, bot.entity_id])
		for other: MvpBot in bots:
			if other.entity_id <= bot.entity_id: continue
			check(_gap(bot, other) >= MIN_GAP, "%s %s bots %d and %d start %.1f m apart" % [arena_id, label, bot.entity_id, other.entity_id, _gap(bot, other)])
	if label == "duel":
		check(absf(bots[0].spawn_pose.origin.x) < 0.01 and absf(bots[1].spawn_pose.origin.x) < 0.01, "%s duel meets across the centre" % arena_id)
	world.clear_bots()

## Gap between two hulls' bounding circles on the floor.
func _gap(a: MvpBot, b: MvpBot) -> float:
	var ra := Vector2(a.collision_bounds().size.x, a.collision_bounds().size.z).length() * 0.5
	var rb := Vector2(b.collision_bounds().size.x, b.collision_bounds().size.z).length() * 0.5
	var pa := Vector2(a.spawn_pose.origin.x, a.spawn_pose.origin.z)
	return pa.distance_to(Vector2(b.spawn_pose.origin.x, b.spawn_pose.origin.z)) - ra - rb

func check_practice(arena_id: String) -> void:
	var session := MvpSession.new()
	root.add_child(session)
	check(session.practice(session.registry.starter(), arena_id) == OK, "%s practice starts" % arena_id)
	await physics_frame
	var half := ArenaBounds.half_extent(arena_id)
	var player: MvpBot = session.local_source()
	var at := player.spawn_pose.origin
	check(Vector2(at.x, at.z).length() > half * 0.6, "%s practice player starts at its edge, not the centre" % arena_id)
	var target := session.practice_target() as MvpBot
	var ahead := target.spawn_pose.origin - at
	check((-player.spawn_pose.basis.z).dot(Vector3(ahead.x, 0, ahead.z).normalized()) > 0.99 and (-target.spawn_pose.basis.z).dot(-ahead.normalized()) > 0.9,
		"%s calibration target waits ahead of the player, facing it" % arena_id)
	for record: Dictionary in session.practice_director.records:
		var bot: MvpBot = session.world.bots[record.id]
		check(ArenaBounds.contains(bot.spawn_pose.origin, half, 1.0), "%s practice bot %d starts inside the walls" % [arena_id, record.index])
		if record.index != 0:
			var home: Vector3 = bot.spawn_pose.origin
			check(Vector2(home.x, home.z).length() > half * 0.6, "%s practice pilot %d starts at the edge" % [arena_id, record.index])
	var all: Array = session.world.bots.values()
	for a: MvpBot in all:
		for b: MvpBot in all:
			if a.entity_id < b.entity_id:
				check(_gap(a, b) >= MIN_GAP, "%s practice bots %d and %d start %.1f m apart" % [arena_id, a.entity_id, b.entity_id, _gap(a, b)])
	session.leave()
	session.queue_free()
	await process_frame

func check_config() -> void:
	var source := FileAccess.get_file_as_string(ARENA_SPAWNS.PATH)
	check(ARENA_SPAWNS.from_json(source) != null, "Shipped arena_spawns.json parses")
	var data: Dictionary = JSON.parse_string(source)
	for mutate: Callable in [
		func(d: Dictionary) -> void: d.team_lanes["1"] = [6],
		func(d: Dictionary) -> void: d.team_lanes["2"] = [2, 2],
		func(d: Dictionary) -> void: d.arenas.moon.team.pop_back(),
		func(d: Dictionary) -> void: d.arenas.woodland.ffa_radius = 0,
		func(d: Dictionary) -> void: d.arenas.erase("foundry"),
		func(d: Dictionary) -> void: d.practice.pilot_starts = [9]]:
		var copy: Dictionary = data.duplicate(true)
		mutate.call(copy)
		var problems: Array[String] = []
		check(ARENA_SPAWNS.from_json(JSON.stringify(copy), problems) == null and not problems.is_empty(), "Invalid spawn data is rejected: %s" % JSON.stringify(copy).left(0))
