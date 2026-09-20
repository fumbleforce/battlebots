extends SceneTree
## Reset contract fixture: damage/poses below are deliberate setup, not a natural
## combat claim. The final hit uses only public commands from the repaired spawn.
var failures := 0
var sessions: Array[MvpSession] = []
var viewports: Array[SubViewport] = []
var restart_events := 0
var hits: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func make_session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var session := MvpSession.new()
	session.name = "Session"
	viewport.add_child(session)
	sessions.append(session)
	viewports.append(viewport)
	return session

func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func denied(session: MvpSession, label: String) -> void:
	check(session.practice_target() == null, label + " exposes no practice target")
	var state := session.connection_state
	var world: AuthorityWorld = session.world
	var players := session.players.duplicate(true)
	var match_view := session.match_view.duplicate(true)
	var match_state := session.match_state.snapshot()
	var peer := session.multiplayer.multiplayer_peer
	check(session.restart_practice() != OK, label + " rejects practice restart")
	check(session.connection_state == state and session.world == world and session.players == players \
		and session.match_view == match_view and session.match_state.snapshot() == match_state \
		and session.multiplayer.multiplayer_peer == peer, label + " rejection leaves live session unchanged")

func damage_fixture(session: MvpSession) -> void:
	for bot: MvpBot in session.world.bots.values():
		bot.combat.damage("top", 50.0)
		bot.combat.zones.front = 4.0
		bot.combat.zones.drive_left = 0.0
		bot.combat.zones.weapon = 0.0
		bot.combat.battery = 2.0
		bot.combat.heat = 95.0
		bot.combat.charge = 0.8
		bot.combat.cooldown = 3.0
		bot.combat.recovery_cooldown = 12.0
		bot.combat.effective_damage = 21
		bot.combat.eliminations = 1
		bot.combat.assists = 2
		bot.combat.component_disables = 3
		bot.combat.recovery_count = 1
		bot.combat.eliminate("practice reset fixture")
	await frames(2)
	for bot: MvpBot in session.world.bots.values():
		check(bot.combat.eliminated and bot.body.freeze and bot.body.collision_layer == 0,
			"Fixture has a genuinely eliminated noncolliding body before restart")
		bot.body.global_transform = Transform3D(Basis(Vector3.UP, 0.8), Vector3(8, 1, 8))
		bot.body.linear_velocity = Vector3(4, 1, -2)
		bot.body.angular_velocity = Vector3(1, 3, 0)
	var stale := BotCommand.new()
	stale.throttle = 1
	stale.primary_held = true
	stale.primary_pressed = true
	stale.recovery_pressed = true
	session.submit_local(stale)
	# Explicit queue setup tests that a restart cannot replay pre-reset intent.
	session._input_queue[session.local_entity] = [stale]
	session._local_commands.append(stale)

func check_reset(session: MvpSession, original_world: AuthorityWorld, originals: Dictionary,
		builds: Dictionary, expected_events: int) -> void:
	var before_tick := session.world.tick
	check(session.restart_practice() == OK, "Practice restarts through public API")
	check(restart_events == expected_events, "One practice_restarted notification per accepted restart")
	check(session.world == original_world and session.world.tick == before_tick,
		"Restart preserves the existing world and its monotonic tick")
	check(session.world.bots.keys() == originals.keys(), "Restart preserves entity IDs")
	check(session.practice_target() != null and session.practice_target() != session.local_source() \
		and originals.values().has(session.practice_target()), "Restart preserves the public read-only target source")
	check(session.connection_state == "practice" and session.match_view.phase == "active" \
		and session.match_view.match_id == "practice", "Restart stays in active practice")
	check(session._input_queue.is_empty() and session._local_commands.is_empty(), "Restart clears all queued input")
	check(session.world.credited.is_empty() and session.world.weapons.events.is_empty(), "Restart clears old elimination credit and effects")
	for id: int in originals:
		var bot: MvpBot = session.world.bots[id]
		var fresh := CombatState.new(bot.combat.stats)
		check(bot == originals[id] and bot.loadout == builds[id], "Restart preserves each bot instance and selected loadout")
		check(bot.combat.snapshot() == fresh.snapshot(), "Restart restores complete combat health/resources/cooldowns/counters")
		check(not bot.command.primary_held and not bot.command.primary_pressed \
			and not bot.command.recovery_pressed and bot.command.throttle == 0,
			"Restart discards the bot's accepted old actions")
		check(not bot.body.freeze and bot.body.collision_layer == BaselineConfig.BOT_LAYER \
			and bot.body.collision_mask == BaselineConfig.BOT_LAYER | BaselineConfig.WORLD_LAYER,
			"Restart restores collision participation and unfreezes bodies")
	await frames(3)
	for bot: MvpBot in session.world.bots.values():
		var position := bot.body.global_position
		check(Vector2(position.x, position.z).distance_to(Vector2(bot.spawn_pose.origin.x, bot.spawn_pose.origin.z)) < 0.01 \
			and absf(position.y - bot.spawn_pose.origin.y) < 0.1,
			"Next physics frames restore the original spawn position")
		check(bot.body.global_basis.get_rotation_quaternion().angle_to(bot.spawn_pose.basis.get_rotation_quaternion()) < 0.01,
			"Next physics frames restore the original spawn orientation")
		check(Vector2(bot.body.linear_velocity.x, bot.body.linear_velocity.z).length() < 0.01 \
			and bot.body.angular_velocity.length() < 0.01 and absf(bot.body.linear_velocity.y) < 1.0,
			"Reset removes stale velocity; only ordinary gravity may resume")
		check(bot.command.throttle == 0 and not bot.command.primary_held and bot.combat.attack_id == 0,
			"Queued pre-reset attack and throttle do not return on the next tick")

func playable_hit(session: MvpSession) -> void:
	var bot: MvpBot = session.world.bots[session.local_entity]
	var target: MvpBot
	for candidate: MvpBot in session.world.bots.values():
		if candidate != bot: target = candidate
	var initial_core := target.combat.core
	var start := bot.body.global_position
	var contact_distance: float = (bot.combat.stats.size.z + target.combat.stats.size.z) * 0.5 + 0.15 * BotScale.FACTOR
	var previous_primary := false
	for tick: int in range(360):
		var own_view := bot.read_view()
		var target_view := target.read_view()
		var offset := target_view.pose.origin - own_view.pose.origin
		offset.y = 0
		var local := own_view.pose.basis.inverse() * offset
		var angle := atan2(local.x, -local.z)
		var command := BotCommand.new()
		command.steering = clampf(angle * 1.4, -1, 1)
		command.throttle = clampf((offset.length() - contact_distance) * 0.5, -0.2, 0.5)
		command.brake = absf(offset.length() - contact_distance) < 0.1 and absf(angle) < 0.1
		command.primary_held = offset.length() < contact_distance + 0.6 * BotScale.FACTOR and absf(angle) < 0.25 and fmod(tick / 60.0, 2.1) < 0.25
		command.primary_pressed = command.primary_held and not previous_primary
		previous_primary = command.primary_held
		session.submit_local(command)
		await frames(1)
		if target.combat.core < initial_core and hits.any(func(event: Dictionary) -> bool:
			return event.kind == "hammer" and event.attacker == bot.entity_id and event.target == target.entity_id and event.damage > 0):
			break
	check(bot.body.global_position.distance_to(start) > 0.5, "Fresh public commands drive away from repaired practice spawn")
	check(target.combat.core < initial_core and not hits.is_empty(), "Real post-reset attack physically damages the repaired target")
	print("PRACTICE post-reset hit: target_core=%.2f/%.2f events=%d" % [target.combat.core, initial_core, hits.size()])

func run() -> void:
	var practice := make_session("Practice")
	denied(practice, "Offline")
	var host := make_session("Host")
	var client := make_session("Client")
	var port := 41000 + OS.get_process_id() % 10000
	check(host.host(port, true, 2) == OK, "Non-practice host binds")
	denied(host, "Hosting")
	check(client.join("127.0.0.1", port) == OK, "Non-practice client begins join")
	denied(client, "Connecting")
	for tick: int in range(600):
		if client.local_entity > 0: break
		await frames(1)
	check(client.local_entity > 0, "Real client joins the non-practice lobby")
	denied(client, "Connected")
	var draft := practice.registry.duelist()
	check(practice.practice(draft) == OK, "Practice starts with canonical Duelist")
	practice.session_event.connect(func(kind: String, _details: Dictionary) -> void:
		if kind == "practice_restarted": restart_events += 1)
	practice.combat_event.connect(func(event: Dictionary) -> void: hits.append(event.duplicate(true)))
	await frames(3)
	var original_world := practice.world
	var originals := practice.world.bots.duplicate()
	check(practice.practice_target() != null and originals.values().has(practice.practice_target()),
		"Practice exposes its actual target through BotSource")
	var builds := {}
	for id: int in originals: builds[id] = originals[id].loadout.duplicate(true)
	await damage_fixture(practice)
	await check_reset(practice, original_world, originals, builds, 1)
	await damage_fixture(practice)
	await check_reset(practice, original_world, originals, builds, 2)
	hits.clear()
	await playable_hit(practice)
	for session: MvpSession in sessions: session.leave()
	await physics_frame
	for viewport: SubViewport in viewports:
		set_multiplayer(null, viewport.get_path())
		viewport.queue_free()
	await process_frame
	print("PRACTICE SESSION PASS" if failures == 0 else "PRACTICE SESSION FAIL")
	quit(0 if failures == 0 else 1)
