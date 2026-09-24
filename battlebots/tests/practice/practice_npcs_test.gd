extends SceneTree
## Live Jolt pilots/hits; elimination below is explicit lifecycle fixture setup.
const FreePort := preload("res://tests/fixtures/free_port.gd")
var failures: Array[String] = []
var events: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame

func run() -> void:
	var session := MvpSession.new()
	root.add_child(session)
	check(session.practice_director == null, "Offline session has no NPC authority")
	check(session.practice(session.registry.starter()) == OK, "Practice starts canonical build")
	session.combat_event.connect(func(event: Dictionary) -> void: events.append(event))
	await frames(5)
	var roamers := session.practice_director.roamers
	check(session.world.bots.size() == 4 + NimbleBots.ORDER.size() and roamers.size() == NimbleBots.ORDER.size(),
		"Foundry practice spawns one player, three authored NPCs and the four nimble roamers")
	var target := session.practice_target() as MvpBot
	var player: MvpBot = session.local_source()
	check(target.get_meta("practice_variant") == "wedge", "Stable HUD target is the stationary calibration wedge")
	var bots := session.world.bots.values()
	for a: MvpBot in bots:
		for b: MvpBot in bots:
			if a == b: continue
			check(a.spawn_pose.origin.distance_to(b.spawn_pose.origin) > 6.0, "Enlarged machines start in separate lanes")
	var start := {}
	for bot: MvpBot in bots: start[bot.entity_id] = bot.body.global_position
	await frames(220)
	check(target.body.global_position.distance_to(start[target.entity_id]) < 0.2, "Calibration wedge remains stationary")
	for record: Dictionary in session.practice_director.records:
		var bot: MvpBot = session.world.bots[record.id]
		if record.index != 0:
			check(bot.last_sequence > 100 and bot.body.global_position.distance_to(start[record.id]) > 0.4,
				"Mobile NPC submits normal valid commands and moves through live physics")
	for record: Dictionary in roamers:
		var roamer: MvpBot = session.world.bots[record.id]
		check(NimbleBots.enabled(roamer.loadout) and roamer.body.gait != "", "Roamer %s runs its own gait" % roamer.loadout.name)
		check(roamer.last_sequence > 100 and roamer.body.global_position.distance_to(start[record.id]) > 5.0,
			"Roamer %s patrols through live physics with normal commands" % roamer.loadout.name)
	# The remaining fixtures isolate the authored NPCs: park the roamers at home.
	for record: Dictionary in roamers:
		record.grace = 100000.0
		session.world.bots[record.id].body.reset_pose = record.home
	# Put the player into the sentry's authored fire lane; damage must then result
	# exclusively from pilot commands and the accepted minigun query/cadence.
	var sentry: MvpBot = session.world.bots[session.practice_director.records[2].id]
	player.body.reset_pose = session.world.clear_spawn_pose(player, Transform3D(Basis.IDENTITY, Vector3(12,0,3)))
	sentry.body.reset_pose = session.world.clear_spawn_pose(sentry, Transform3D(Basis(Vector3.UP,PI),Vector3(12,0,-10)))
	var initial_core := player.combat.core
	for frame: int in 360:
		await frames(1)
		if events.any(func(event: Dictionary) -> bool: return event.attacker == sentry.entity_id and event.target == player.entity_id): break
	check(player.combat.core < initial_core and events.any(func(event: Dictionary) -> bool:
		return event.attacker == sentry.entity_id and event.target == player.entity_id and event.kind == "minigun"),
		"Sentry uses genuine server-authoritative minigun hits against the player")
	# A wreck cannot collide; regeneration preserves the target identity and player.
	var identity := target.entity_id
	var player_state := player.combat.snapshot()
	target.combat.damage("top", 100000)
	await frames(2)
	check(target.combat.eliminated and target.body.freeze and target.body.collision_layer == 0,
		"Destroyed NPC becomes a frozen non-colliding wreck")
	# Freeze pilots for this isolated respawn setup; retain the full six-second gate.
	# Park the other NPCs at their homes so how far patrols drove (a drive-tuning
	# detail) cannot occupy the wreck's home and defer its regeneration.
	for record: Dictionary in session.practice_director.records:
		record.grace = 100.0
		if record.id != identity:
			session.world.bots[record.id].body.reset_pose = record.home
	await frames(380)
	check(session.practice_target() == target and target.entity_id == identity and not target.combat.eliminated,
		"Expired wreck regenerates the same stable calibration entity")
	check(target.combat.core == target.combat.stats.core and not target.body.freeze and target.body.collision_layer != 0,
		"Regenerated NPC restores health and physics participation")
	check(player.combat.core <= float(player_state.core), "NPC replacement never repairs the player")
	# Occupancy defers regeneration rather than dropping collision into the player.
	player.body.reset_pose = target.spawn_pose
	await frames(4)
	target.combat.damage("top", 100000)
	await frames(2)
	var rec: Dictionary = session.practice_director.records[0]
	rec.wreck_age = PracticeBotDirector.WRECK_SECONDS
	session.practice_director.step(1.0/60.0)
	check(target.combat.eliminated, "Occupied home defers regeneration")
	check(session.restart_practice() == OK, "Full practice restart remains available")
	check(session.practice_target() == target and session.world.bots.size() == 4 + NimbleBots.ORDER.size(),
		"Restart preserves all NPC instances and bounded count")
	check(session.practice_director.elapsed == 0.0 and rec.wreck_age == 0.0,
		"Restart clears pilot clocks and pending respawns")
	await frames(4)
	# A knocked-out player returns to its own spawn after the practice delay.
	var director := session.practice_director
	var player_home := player.spawn_pose
	check(is_nan(director.player_respawn_remaining()), "No respawn countdown while the player is alive")
	player.combat.damage("top", 100000)
	await frames(2)
	director.step(PracticeBotDirector.PLAYER_RESPAWN_SECONDS - 0.1)
	check(player.combat.eliminated and director.player_respawn_remaining() > 0.0, "Player waits out the respawn delay")
	director.step(0.2)
	check(not player.combat.eliminated and player.combat.core == player.combat.stats.core and not player.body.freeze
		and player.spawn_pose.origin.is_equal_approx(player_home.origin) and director.player_respawns == 1,
		"Player respawns repaired at its own spawn")
	check(session.local_source() == player and session.world.bots.size() == 4 + roamers.size(), "Player respawn keeps the same entity and bot count")
	# Playtest regression: the rammer parked on the player's spawn while the
	# calibration target covered every nearby fallback held the player out forever.
	await frames(4)
	var rammer: MvpBot = session.world.bots[director.records[1].id]
	rammer.body.reset_pose = player_home
	await frames(4)
	player.combat.damage("top", 100000)
	await frames(2)
	director.step(PracticeBotDirector.PLAYER_RESPAWN_SECONDS + 0.1)
	check(not player.combat.eliminated and not player.spawn_pose.origin.is_equal_approx(player_home.origin)
		and director._pose_clear(player, player.spawn_pose),
		"Occupied player spawn falls back to a clear authored spawn")
	check(session.restart_practice() == OK and player.spawn_pose.origin.is_equal_approx(player_home.origin),
		"Restart returns the player to its original spawn")
	session.leave()
	check(session.practice_director == null and session.practice_target() == null, "Leave removes all practice authority")
	check(session.host(FreePort.udp(), true, 2) == OK, "Online host can start after practice")
	check(session.practice_director == null and session.world.bots.is_empty(), "Online lobby never starts practice NPCs")
	session.leave()
	session.queue_free()
	await frames(3)
	for failure: String in failures: push_error(failure)
	print("PRACTICE NPC PASS" if failures.is_empty() else "PRACTICE NPC FAIL")
	quit(0 if failures.is_empty() else 1)
