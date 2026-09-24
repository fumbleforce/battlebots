extends SceneTree
## Practice Duel (#83): the player plus one stationary, non-aggressive Atlas MX
## at the arena centre, with no pilots, roamers, Woodland giant or cooling zones.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame

func run() -> void:
	for arena: String in ["foundry", "woodland"]:
		var session := MvpSession.new()
		root.add_child(session)
		check(session.practice(session.registry.starter(), arena, "nonsense") == ERR_INVALID_PARAMETER, "Unknown practice kinds are refused")
		check(session.practice(session.registry.starter(), arena, "duel") == OK, "%s duel practice starts" % arena)
		check(session.practice_kind == "duel", "Session reports the duel layout")
		await frames(5)
		check(session.world.bots.size() == 2, "%s duel has only the player and one NPC" % arena)
		check(session.woodland_boss == null, "%s duel has no roaming giant" % arena)
		check(session.world.cooling_zones().is_empty(), "%s duel has no cooling zones" % arena)
		check(session.world.pickups.items.size() > 0 and not session.world.pickups.items.any(func(item: Dictionary) -> bool:
			return item.kind == "coolant"), "%s duel keeps part pickups but has no coolant canisters" % arena)
		check(session.practice_director.roamers.is_empty() and session.practice_director.records.size() == 1, "No pilots or roamers")
		var target := session.practice_target() as MvpBot
		var player: MvpBot = session.local_source()
		check(target != null and AtlasGeometry.enabled(target.loadout), "%s duel target is an Atlas MX" % arena)
		check(not target.has_meta("practice_variant"), "The Atlas keeps its own model, not a training-NPC shell")
		check(Vector2(target.spawn_pose.origin.x, target.spawn_pose.origin.z).length() < 1.0, "%s Atlas starts at the arena centre" % arena)
		var start := target.body.global_position
		var initial_core := player.combat.core
		await frames(240)
		check(target.body.global_position.distance_to(start) < 0.3, "%s Atlas stays put" % arena)
		check(player.combat.core == initial_core, "%s Atlas never attacks the player" % arena)
		check(session.restart_practice() == OK, "%s duel practice restarts" % arena)
		await frames(2)
		check(session.world.bots.size() == 2, "Restart keeps the duel layout")
		session.leave()
		check(session.practice_kind == "full", "Leaving resets the practice layout")
		check(session.practice(session.registry.starter(), arena) == OK and not session.world.cooling_zones().is_empty(),
			"%s full practice keeps its cooling zones" % arena)
		check(session.world.pickups.items.any(func(item: Dictionary) -> bool: return item.kind == "coolant"),
			"%s full practice keeps its coolant canisters" % arena)
		check(session.world.bots.size() > 2, "%s full practice keeps its NPCs" % arena)
		session.leave()
		session.queue_free()
		await frames(2)
	if failures.is_empty():
		print("PRACTICE_DUEL_TEST_PASS")
		quit(0)
	else:
		for failure: String in failures: push_error(failure)
		print("PRACTICE_DUEL_TEST_FAIL")
		quit(1)
