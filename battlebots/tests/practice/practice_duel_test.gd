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
	for arena: String in ["foundry", "woodland", "moon"]:
		var session := MvpSession.new()
		root.add_child(session)
		check(session.practice(session.registry.starter(), arena, "nonsense") == ERR_INVALID_PARAMETER, "Unknown practice kinds are refused")
		check(session.practice(session.registry.starter(), arena, "duel") == OK, "%s duel practice starts" % arena)
		check(session.practice_kind == "duel", "Session reports the duel layout")
		await frames(5)
		var wheels_count := ArenaSpawns.settings().duel_monowheel_count
		check(session.world.bots.size() == 2 + wheels_count, "%s duel has the player, the Atlas and %d monowheels" % [arena, wheels_count])
		check(session.woodland_boss == null, "%s duel has no roaming giant" % arena)
		check(session.world.cooling_zones().is_empty(), "%s duel has no cooling zones" % arena)
		check(session.world.pickups.items.size() > 0 and not session.world.pickups.items.any(func(item: Dictionary) -> bool:
			return item.kind == "coolant"), "%s duel keeps part pickups but has no coolant canisters" % arena)
		check(session.practice_director.roamers.is_empty() and session.practice_director.records.size() == 1 + wheels_count, "No pilots or roamers")
		var target := session.practice_target() as MvpBot
		var player: MvpBot = session.local_source()
		check(target != null and AtlasGeometry.enabled(target.loadout), "%s duel target is an Atlas MX" % arena)
		check(not target.has_meta("practice_variant"), "The Atlas keeps its own model, not a training-NPC shell")
		check(Vector2(target.spawn_pose.origin.x, target.spawn_pose.origin.z).length() < 1.0, "%s Atlas starts at the arena centre" % arena)
		var start := target.body.global_position
		var wheels: Array[MvpBot] = []
		for bot: MvpBot in session.world.bots.values():
			if NimbleBots.enabled(bot.loadout): wheels.append(bot)
		check(wheels.size() == wheels_count and wheels.all(func(w: MvpBot) -> bool: return w.loadout.parts.drive == "mono_wheel" and w.has_meta("practice_fixture")),
			"%s monowheels are stationary fixtures" % arena)
		# On the player's left, seen from its start; tight but never overlapping.
		var forward := (-player.spawn_pose.basis.z).slide(Vector3.UP).normalized()
		var left := Vector3.UP.cross(forward).normalized()
		# Rows by depth toward the left wall: front row nearest the room.
		var depths: Array[float] = []
		for a: MvpBot in wheels:
			check(a.spawn_pose.origin.dot(left) > 5.0, "%s monowheel stands on the player's left" % arena)
			var depth := snappedf(a.spawn_pose.origin.dot(left), 0.01)
			if not depths.any(func(d: float) -> bool: return absf(d - depth) < 0.05): depths.append(depth)
		var rows := ArenaSpawns.settings().duel_monowheel_rows
		check(depths.size() == rows, "%s monowheels stand in %d rows (depths %s)" % [arena, rows, str(depths)])
		# Hull-to-hull gaps: side by side within a row, front to back between rows.
		var hull := wheels[0].collision_bounds().size
		var side_gaps: Array[float] = []
		var row_gaps: Array[float] = []
		for a: MvpBot in wheels:
			var beside := INF
			var behind := INF
			for b: MvpBot in wheels:
				if a == b: continue
				var offset := b.spawn_pose.origin - a.spawn_pose.origin
				if absf(offset.dot(left)) < 0.05: beside = minf(beside, absf(offset.dot(forward)))
				elif absf(offset.dot(forward)) < 0.05: behind = minf(behind, absf(offset.dot(left)))
			side_gaps.append(beside - hull.x)
			row_gaps.append(behind - hull.z)
		check(side_gaps.all(func(g: float) -> bool: return g > 0.0 and g < 1.0) and row_gaps.all(func(g: float) -> bool: return g > 0.0 and g < 1.0),
			"%s monowheels are tightly packed without overlapping (side %s, rows %s)" % [arena, str(side_gaps), str(row_gaps)])
		var wheel_starts := wheels.map(func(w: MvpBot) -> Vector3: return w.body.global_position)
		var initial_core := player.combat.core
		await frames(240)
		check(target.body.global_position.distance_to(start) < 0.3, "%s Atlas stays put" % arena)
		for index: int in wheels.size():
			check(wheels[index].body.global_position.distance_to(wheel_starts[index]) < 0.5 and wheels[index].body.global_basis.y.y > 0.7,
				"%s monowheel %d stays put and upright (moved %.2f m, up %.2f, at %s)" % [arena, index,
				wheels[index].body.global_position.distance_to(wheel_starts[index]), wheels[index].body.global_basis.y.y, str(wheel_starts[index])])
		check(player.combat.core == initial_core, "%s Atlas never attacks the player" % arena)
		check(session.restart_practice() == OK, "%s duel practice restarts" % arena)
		await frames(2)
		check(session.world.bots.size() == 2 + wheels_count, "Restart keeps the duel layout")
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
