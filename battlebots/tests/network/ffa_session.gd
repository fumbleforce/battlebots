extends "res://tests/network/transport_session.gd"
## Independent FFA lifecycle through opaque impaired UDP; real time only.
var client_relays: Array[Node] = []
var errors_by_client: Dictionary = {}
var results_by_client: Dictionary = {}
var expected_players := 4
var armed_entity := 0

func frame() -> void:
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.brake = true
		command.primary_held = client.local_entity == armed_entity and armed_entity > 0
		client.submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame

func active_everywhere() -> bool:
	return (server.match_state.phase == "active" and clients.size() == expected_players
		and clients.all(func(c: MvpSession) -> bool:
			return c.match_view.get("phase") == "active" and c.world != null and c.world.bots.size() == expected_players))

func begin_fixture(port_offset: int) -> bool:
	server = make_session("FfaServer")
	server_port = 43000 + OS.get_process_id() % 9000 + port_offset
	return await require(server.host(server_port, false, 8, "ffa") == OK, "FFA maximum-eight host binds")

func add_ffa_client(index: int) -> bool:
	var relay := make_relay(index)
	if not await require(relay != null, "FFA relay binds"):
		return false
	client_relays.append(relay)
	var client := make_session("FfaClient%d" % index)
	clients.append(client)
	errors_by_client[index] = []
	results_by_client[index] = []
	client.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "error":
			errors_by_client[index].append(details.duplicate(true))
		elif kind == "results":
			results_by_client[index].append(details.duplicate(true)))
	return await require(client.join("127.0.0.1", relay.bound_port) == OK, "FFA client connects through relay")

func ready_count() -> int:
	var count := 0
	for player: Dictionary in server.players.values():
		count += int(player.ready)
	return count

func run() -> void:
	injected_rtt = float(profile) if profile in ["0", "80", "150"] else 80.0
	jitter = 20.0 if injected_rtt == 150 else (10.0 if injected_rtt == 80 else 0.0)
	loss = 0.03 if injected_rtt == 150 else (0.01 if injected_rtt == 80 else 0.0)
	if not await begin_fixture(0):
		return
	for index: int in range(3):
		if not await add_ffa_client(index):
			return
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)), "First three FFA clients admitted"):
		return
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await require(await until(func() -> bool: return ready_count() == 3), "Three FFA ready requests reach server"):
		return
	await frames(30)
	check(server.match_state.phase == "lobby" and server.world.bots.is_empty(), "Three ready players cannot start FFA")
	if not await add_ffa_client(3):
		return
	if not await require(await until(func() -> bool: return clients[3].local_entity > 0), "Fourth FFA client admitted"):
		return
	var original_team: int = server.players[clients[0].local_entity].team
	clients[0].set_team(0)
	if not await require(await until(func() -> bool: return errors_by_client[0].any(func(details: Dictionary) -> bool:
		return details.get("operation") == "team")), "FFA team change receives explicit rejection"):
		return
	check(server.players[clients[0].local_entity].team == original_team, "Rejected team change preserves hostile faction identity")
	clients[3].set_ready(true)
	if not await require(await until(active_everywhere, 1800), "Four ready clients start below selected capacity eight"):
		return
	check_roster()
	if not await reject_extra("MidRoundFfa", 100):
		return
	if not await hostile_combat_and_reconnect():
		return
	var forfeiter := clients[2].local_entity
	clients[2].vote_forfeit()
	if not await require(await until(func() -> bool: return server.world.bots[forfeiter].combat.eliminated), "FFA forfeit eliminates its single requester"):
		return
	for client: MvpSession in clients:
		if client.local_entity != forfeiter:
			check(not server.world.bots[client.local_entity].combat.eliminated, "Individual forfeit leaves every other participant alive")
	check(server.match_state.phase == "active", "One forfeit cannot resolve a four-player FFA")
	if not await require(await until(func() -> bool: return clients[2].spectator_sources().size() == 3), "Eliminated FFA player may spectate all three survivors"):
		return
	var spectator_ids: Array[int] = []
	for source: BotSource in clients[2].spectator_sources():
		spectator_ids.append(source.read_view().entity_id)
	for client: MvpSession in clients:
		check(spectator_ids.has(client.local_entity) == (client.local_entity != forfeiter), "FFA spectator candidates match living entities")
	var winner := clients[3].local_entity
	server.world.bots[clients[0].local_entity].combat.eliminate("FFA placement fixture")
	server.world.bots[clients[1].local_entity].combat.eliminate("FFA placement fixture")
	if not await results_arrive([winner]):
		return
	for client: MvpSession in clients:
		var places := placement_map(client.match_view.placements)
		check(places[winner].place == 1 and places[winner].elimination_tick == -1, "Sole survivor receives first place")
		check(places[forfeiter].place == 4, "Earlier individual forfeit receives last place")
		var a: Dictionary = places[clients[0].local_entity]
		var b: Dictionary = places[clients[1].local_entity]
		check(a.place == 2 and b.place == 2 and a.elimination_tick == b.elimination_tick,
			"Same-tick later eliminations share second place")
	if not await rematch_case():
		return
	await clear_fixture()
	expected_players = 8
	if not await begin_fixture(1):
		return
	for index: int in range(8):
		if not await add_ffa_client(index):
			return
	if not await require(await until(func() -> bool:
		return server.players.size() == 8 and clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)), "All eight FFA slots are admitted before readying"):
		return
	if not await reject_extra("NinthFfa", 101):
		return
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await require(await until(active_everywhere, 1800), "Maximum eight-player FFA reaches active"):
		return
	check_roster()
	for index: int in range(6):
		server.world.bots[clients[index].local_entity].combat.eliminate("FFA earlier fixture")
	await frames(3)
	check(server.match_state.phase == "active", "Two remaining FFA bots continue fighting")
	var shared_winners: Array[int] = [clients[6].local_entity, clients[7].local_entity]
	for id: int in shared_winners:
		server.world.bots[id].combat.eliminate("FFA simultaneous finale")
	if not await results_arrive(shared_winners):
		return
	for client: MvpSession in clients:
		var places := placement_map(client.match_view.placements)
		check(client.match_view.winner == -1, "Shared first place has no fabricated sole winner")
		check(places[shared_winners[0]].place == 1 and places[shared_winners[1]].place == 1,
			"Same-tick final eliminations share first place")
		check(places[shared_winners[0]].elimination_tick == places[shared_winners[1]].elimination_tick,
			"Shared winners carry the same authoritative elimination tick")
		for index: int in range(6):
			check(places[clients[index].local_entity].place == 3,
				"Earlier six-way tie uses competition ranking after shared winners")
	if not await rematch_case():
		return
	await finish()

func reject_extra(label: String, seed: int) -> bool:
	var relay := make_relay(seed)
	if not await require(relay != null, "Rejected join relay binds"):
		return false
	var extra := make_session(label)
	var reasons: Array[String] = []
	extra.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "error":
			reasons.append(str(details.get("message", ""))))
	if not await require(extra.join("127.0.0.1", relay.bound_port) == OK, "Extra FFA client attempts connection"):
		return false
	if not await require(await until(func() -> bool: return extra.connection_state == "offline", 1800), "Extra FFA client is rejected"):
		return false
	check(reasons.has("Lobby full or match already started") and server.players.size() == expected_players,
		"FFA rejects full or mid-round admission without altering roster")
	return true

func check_roster() -> void:
	check(server.match_state.round_index == 1 and server.match_state.remaining > 290 and server.match_state.remaining <= 300,
		"FFA starts a single 300-second round")
	var origins: Array[Vector3] = []
	for id: int in server.world.bots:
		var bot: MvpBot = server.world.bots[id]
		check(bot.team == id and server.players[id].team == id, "Every FFA entity has a unique hostile team")
		check(absf(bot.spawn_pose.origin.x) < 25 and absf(bot.spawn_pose.origin.z) < 25, "FFA spawn lies within arena walls")
		var matched_marker := false
		for slot: int in range(1, 9):
			var marker := server.world.arena.get_node("SpawnPoints/FFA_%d" % slot) as Node3D
			matched_marker = matched_marker or bot.spawn_pose.is_equal_approx(marker.global_transform)
		check(matched_marker, "FFA spawn uses an existing authored marker")
		check(bot.body.global_position.distance_to(bot.spawn_pose.origin) < 0.35, "Active start or rematch restores authored FFA spawn")
		for origin: Vector3 in origins:
			check(bot.spawn_pose.origin.distance_to(origin) > 1, "FFA spawn markers are distinct")
		origins.append(bot.spawn_pose.origin)
	for client: MvpSession in clients:
		check(client.lobby_view.mode == "ffa" and client.lobby_view.capacity == 8, "Selected FFA lobby capacity remains eight")
		check(client.match_view.mode == "ffa" and client.world.bots.size() == expected_players, "Every client receives the actual FFA roster")

func hostile_combat_and_reconnect() -> bool:
	var attacker: MvpBot = server.world.bots[clients[0].local_entity]
	var victim: MvpBot = server.world.bots[clients[1].local_entity]
	attacker.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, -2.15))
	await frames(30)
	var before := victim.combat.core
	armed_entity = attacker.entity_id
	if not await require(await until(func() -> bool: return victim.combat.core < before, 180), "Real spinner contact damages another unique-team FFA bot"):
		return false
	armed_entity = 0
	attacker.body.reset_pose = attacker.spawn_pose
	victim.body.reset_pose = victim.spawn_pose
	await frames(30)
	var damage := victim.combat.core
	var observed_damage := await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return is_equal_approx(c.world.bots[victim.entity_id].remote_state.core, damage)))
	if not observed_damage:
		# Preserve the exact-health gate, but distinguish stale observers from
		# further authoritative damage when this fails on a remote CI runner.
		print("FFA damage convergence: expected=%.6f authority=%.6f entity=%d tick=%d" %
			[damage, victim.combat.core, victim.entity_id, server.world.tick])
		for observer: MvpSession in clients:
			var snapshot: Dictionary = observer.world.bots[victim.entity_id].remote_state
			print("FFA observer=%d connection=%s phase=%s victim_core=%s snapshot_tick=%s" %
				[observer.local_entity, observer.connection_state, observer.match_view.get("phase"),
				snapshot.get("core"), snapshot.get("tick")])
	if not await require(observed_damage, "Every FFA observer sees hostile damage"):
		return false
	var token := clients[1].reconnect_token
	clients[1].leave()
	if not await require(await until(func() -> bool: return server.players[victim.entity_id].peer == 0), "FFA disconnect retains participant reservation"):
		return false
	client_relays[1].stop()
	var replacement := make_relay(200)
	if not await require(replacement != null, "FFA reconnect relay binds"):
		return false
	client_relays[1] = replacement
	if not await require(clients[1].join("127.0.0.1", replacement.bound_port, token) == OK, "Damaged FFA participant reconnects"):
		return false
	if not await require(await until(func() -> bool:
		return clients[1].local_entity == victim.entity_id and clients[1].world != null and clients[1].world.bots.has(victim.entity_id)),
		"FFA reconnect baseline restores original entity"):
		return false
	check(server.world.bots[victim.entity_id] == victim and victim.combat.core == damage, "FFA reconnect retains physical bot and damage")
	check(clients[1].reconnect_token != token and is_equal_approx(clients[1].world.bots[victim.entity_id].remote_state.core, damage),
		"FFA reconnect rotates token and publishes retained damage")
	return true

func results_arrive(expected_winners: Array) -> bool:
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "results" and not c._results.is_empty())), "All FFA clients receive single-round results"):
		return false
	var sorted_winners := expected_winners.duplicate()
	sorted_winners.sort()
	for client: MvpSession in clients:
		var winners: Array = client.match_view.get("winners", []).duplicate()
		winners.sort()
		check(winners == sorted_winners, "Replicated FFA winner IDs match authoritative outcome")
		check(client.match_view.get("placements", []).size() == expected_players, "Results place every admitted participant")
		check(client.match_view.round == 1 and client._results.match.rounds.size() == 1,
			"FFA resolves after one round without overtime or team rounds")
		check(client._results.participants.size() == expected_players and client._results.match.placements == client.match_view.placements,
			"Detailed results preserve full participant statistics and placements")
	print("FFA injected%.0f %d-player result: winners=%s placements=%s" %
		[injected_rtt, expected_players, server.match_view.winners, server.match_view.placements])
	return true

func placement_map(placements: Array) -> Dictionary:
	var result := {}
	for placement: Dictionary in placements:
		result[placement.entity_id] = placement
	return result

func rematch_case() -> bool:
	var old_match := server.match_state.match_id
	for index: int in range(clients.size() - 1):
		clients[index].vote_rematch()
	if not await require(await until(func() -> bool: return server._rematch.size() == clients.size() - 1), "All but one FFA rematch vote arrives"):
		return false
	check(server.match_state.phase == "results" and server.match_state.match_id == old_match, "FFA waits for every connected rematch vote")
	clients.back().vote_rematch()
	if not await require(await until(func() -> bool: return active_everywhere() and server.match_state.match_id != old_match, 1800),
		"All connected FFA players rematch at the same admitted count"):
		return false
	check_roster()
	for client: MvpSession in clients:
		check(client.match_view.get("placements", []).is_empty() and client.match_view.get("winners", []).is_empty(),
			"FFA rematch clears prior placements and winners")
	return true

func clear_fixture() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for relay: Node in relays:
		if not relay.stats.is_empty():
			for direction: String in ["uplink", "downlink"]:
				var stats: Dictionary = relay.stats[direction]
				check(stats.queue_dropped == 0 and stats.send_errors == 0, "FFA raw relay has no overflow or send errors")
		relay.stop()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	sessions.clear()
	clients.clear()
	relays.clear()
	client_relays.clear()
	errors_by_client.clear()
	results_by_client.clear()
	armed_entity = 0

func finish() -> void:
	await clear_fixture()
	print("FFA SESSION PASS" if failures == 0 else "FFA SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
