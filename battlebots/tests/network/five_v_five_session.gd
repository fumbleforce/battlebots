extends "res://tests/network/transport_session.gd"
## Ten real ENet clients and separate physics worlds; all packets use UDP relays.
## Real-time only. Traffic includes 28 bytes of IPv4/UDP overhead per datagram.
var client_relays: Array[Node] = []
var results_events: Dictionary = {}

func frame() -> void:
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.throttle = 1.0 if client.local_entity == drive_entity and drive_entity > 0 else 0.0
		command.brake = is_zero_approx(command.throttle)
		client.submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame

func active_everywhere() -> bool:
	return (server.match_state.phase == "active" and clients.size() == 10
		and clients.all(func(c: MvpSession) -> bool:
			return c.match_view.get("phase") == "active" and c.world != null and c.world.bots.size() == 10))

func all_ready(count: int) -> bool:
	var ready := 0
	for player: Dictionary in server.players.values():
		ready += int(player.ready)
	return ready == count

func add_client(index: int) -> bool:
	var relay := make_relay(index)
	if not await require(relay != null, "5v5 client relay binds"):
		return false
	client_relays.append(relay)
	var client := make_session("FiveClient%d" % index)
	clients.append(client)
	results_events[index] = []
	client.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "results":
			results_events[index].append(details.duplicate(true)))
	return await require(client.join("127.0.0.1", relay.bound_port) == OK, "5v5 client starts relay connection")

func run() -> void:
	injected_rtt = float(profile) if profile in ["0", "80", "150"] else 80.0
	jitter = 20.0 if injected_rtt == 150 else (10.0 if injected_rtt == 80 else 0.0)
	loss = 0.03 if injected_rtt == 150 else (0.01 if injected_rtt == 80 else 0.0)
	server = make_session("FiveServer")
	server_port = 41000 + OS.get_process_id() % 10000
	if not await require(server.host(server_port, false, 10) == OK, "Ten-player server binds"):
		return
	await frames(30)
	for index: int in range(9):
		if not await add_client(index):
			return
	if not await require(await until(func() -> bool:
		return (server.players.size() == 9 and clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)), 1800), "First nine clients admitted"):
		return
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await require(await until(func() -> bool: return all_ready(9)), "Nine ready requests reach authority"):
		return
	await frames(30)
	check(server.match_state.phase == "lobby" and server.world.bots.is_empty(), "Nine ready players cannot start 5v5")
	if not await add_client(9):
		return
	if not await require(await until(func() -> bool:
		return (server.players.size() == 10 and clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0 and c.lobby_view.get("slots", []).size() == 10))),
		"Tenth client fills lobby on every observer"):
		return
	check_teams()
	for client: MvpSession in clients:
		check(client.lobby_view.capacity == 10 and client.lobby_view.mode == "5v5", "Every lobby publishes 5v5 capacity")
		check(client.match_view.get("capacity") == 10 and client.match_view.get("mode") == "5v5",
			"Pre-match baseline publishes the selected mode before readiness")
	# A reliable ready request behind the team request proves the authority has
	# processed the attempted sixth teammate; absence of a reply alone is no proof.
	var id := clients[0].local_entity
	var original_team: int = server.players[id].team
	clients[0].set_team(1 - original_team)
	clients[0].set_ready(false)
	if not await require(await until(func() -> bool: return not server.players[id].ready), "Team request ordering barrier arrives"):
		return
	check(server.players[id].team == original_team, "Sixth player cannot join a full team")
	check_teams()
	var extra_relay := make_relay(100)
	if not await require(extra_relay != null, "Oversubscription relay binds"):
		return
	var extra := make_session("EleventhClient")
	var rejection: Array[String] = []
	extra.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "error":
			rejection.append(str(details.get("message", ""))))
	if not await require(extra.join("127.0.0.1", extra_relay.bound_port) == OK, "Eleventh client attempts admission"):
		return
	if not await require(await until(func() -> bool: return extra.connection_state == "offline", 1800), "Eleventh client is rejected"):
		return
	check(rejection.has("Lobby full or match already started") and server.players.size() == 10,
		"Full-lobby rejection preserves the ten admitted slots")
	for index: int in range(9):
		clients[index].set_ready(true)
	if not await require(await until(func() -> bool: return all_ready(9)), "Nine of ten connected players are ready"):
		return
	await frames(30)
	check(server.match_state.phase == "lobby", "Connected but unready tenth player also prevents start")
	clients[9].set_ready(true)
	if not await require(await until(active_everywhere, 1800), "All ten ready players receive baselines and become active"):
		return
	check(server.match_state.remaining > 235 and server.match_state.remaining <= 240, "5v5 starts a 240-second round")
	check_spawns()
	for session: MvpSession in sessions:
		check(session.network_simulation.delay_ms == 0 and session.network_simulation.loss == 0,
			"Raw UDP is the only impairment layer")
	await measure_active_traffic(id)
	server.world.bots[id].combat.damage("top", 30)
	var damaged_core: float = server.world.bots[id].combat.core
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return is_equal_approx(c.world.bots[id].remote_state.core, damaged_core))), "Damage reaches all ten observers"):
		return
	var retained: MvpBot = server.world.bots[id]
	var token := clients[0].reconnect_token
	clients[0].leave()
	if not await require(await until(func() -> bool: return server.players[id].peer == 0), "Disconnected 5v5 slot is reserved"):
		return
	client_relays[0].stop()
	var replacement := make_relay(200)
	if not await require(replacement != null, "5v5 reconnect relay binds"):
		return
	client_relays[0] = replacement
	if not await require(clients[0].join("127.0.0.1", replacement.bound_port, token) == OK, "5v5 reconnect begins"):
		return
	if not await require(await until(func() -> bool:
		return clients[0].local_entity == id and clients[0].world != null and clients[0].world.bots.has(id)), "Reconnect restores original entity"):
		return
	check(server.world.bots[id] == retained and retained.combat.core == damaged_core, "Reconnect retains physical body and damage")
	check(clients[0].reconnect_token != token, "Reconnect rotates its reservation token")
	check(is_equal_approx(clients[0].world.bots[id].remote_state.core, damaged_core), "Reconnect baseline carries retained damage")
	# Three rounds exercise both reset transitions and a first-to-two 2–1 result.
	for round_index: int in range(1, 4):
		eliminate_team(0 if round_index == 2 else 1)
		var expected_scores := [1, 0] if round_index == 1 else ([1, 1] if round_index == 2 else [2, 1])
		var expected_phase := "results" if round_index == 3 else "intermission"
		if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
			return c.match_view.get("phase") == expected_phase and c.match_view.get("scores") == expected_scores)),
			"All ten observers agree on round %d score and phase" % round_index):
			return
		if round_index < 3:
			server.match_state.remaining = 0
			if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
				return c.match_view.get("round") == round_index + 1 and c.match_view.get("phase") == "countdown")),
				"Next round countdown reaches all ten clients"):
				return
			if not await require(await until(func() -> bool: return reset_complete(round_index + 1)), "Round reset revives every bot on every observer"):
				return
			if not await require(await until(active_everywhere), "Next 5v5 round starts"):
				return
	check(clients.all(func(c: MvpSession) -> bool: return c.match_view.get("winner") == 0), "Ten-client match agrees on winner")
	if not await require(await until(func() -> bool: return results_events.values().all(func(events: Array) -> bool: return not events.is_empty())),
		"Every player receives its reliable detailed results event"):
		return
	for index: int in range(10):
		check(results_events[index].size() == 1, "Detailed results are emitted once per client")
		var result: Dictionary = results_events[index][0]
		check(result.participants.size() == 10 and result.match.rounds.size() == 3,
			"Results retain ten aggregate participants and all three rounds")
		for round_result: Dictionary in result.match.rounds:
			check(round_result.get("participants", {}).size() == 10, "Detailed round result retains all participant statistics")
		for round_summary: Dictionary in clients[index].match_view.rounds:
			check(not round_summary.has("participants"), "Ordinary match view contains compact round summaries")
	var control_bytes := var_to_bytes({"view":server.match_view, "results":server._results}).size()
	print("5v5 three-round detailed result control payload: %d bytes" % control_bytes)
	check(control_bytes <= 131072, "Detailed ten-player results fit the bounded 128 KiB control packet")
	var old_match := server.match_state.match_id
	for index: int in range(9):
		clients[index].vote_rematch()
	if not await require(await until(func() -> bool: return server._rematch.size() == 9), "Nine rematch votes reach server"):
		return
	check(server.match_state.phase == "results" and server.match_state.match_id == old_match, "Rematch requires the tenth vote")
	clients[9].vote_rematch()
	if not await require(await until(func() -> bool:
		return (active_everywhere() and server.match_state.match_id != old_match and clients.all(func(c: MvpSession) -> bool:
			return c.match_view.get("match_id") == server.match_state.match_id and c.match_view.get("round") == 1)), 1800),
		"All ten rematch votes start a fresh match"):
		return
	check_spawns()
	await finish()

func check_teams() -> void:
	var counts := [0, 0]
	for player: Dictionary in server.players.values():
		counts[player.team] += 1
	check(counts == [5, 5], "Teams contain five players each")

func check_spawns() -> void:
	var origins: Array[Vector3] = []
	for id: int in server.world.bots:
		var bot: MvpBot = server.world.bots[id]
		for origin: Vector3 in origins:
			check(bot.spawn_pose.origin.distance_to(origin) > 1, "All ten authoritative spawn markers are distinct")
		origins.append(bot.spawn_pose.origin)
		for client: MvpSession in clients:
			var observed: MvpBot = client.world.bots[id]
			check(not observed.remote_state.is_empty(), "Every client baseline contains every bot")
			check(observed.remote_state.entity == id and observed.remote_state.epoch == WireCodec.snapshot_epoch(server.match_state.match_id, 1),
				"Ten-bot baseline preserves entity and match identity")
			check(observed.presentation.global_position.distance_to(bot.body.global_position) < 0.15, "Every observer starts at the authoritative spawn")

func reset_complete(round_index: int) -> bool:
	var epoch := WireCodec.snapshot_epoch(server.match_state.match_id, round_index)
	for client: MvpSession in clients:
		for id: int in server.world.bots:
			var bot: MvpBot = client.world.bots[id]
			if (bot.remote_state.get("epoch") != epoch or bot.remote_state.get("eliminated", true)
				or not is_equal_approx(bot.remote_state.core, bot.combat.stats.core)
				or bot.presentation.global_position.distance_to(server.world.bots[id].body.global_position) >= 0.15):
				return false
	return true

func measure_active_traffic(id: int) -> void:
	await frames(90)
	var starts := {}
	for entity: int in server.world.bots:
		starts[entity] = server.world.bots[entity].body.global_position
	var initial: Array[Dictionary] = []
	for relay: Node in client_relays:
		initial.append(relay.stats.duplicate(true))
	var started := Time.get_ticks_usec()
	var physics_started := Engine.get_physics_frames()
	drive_entity = id
	while Time.get_ticks_usec() - started < 5000000:
		if Time.get_ticks_usec() - started > 1500000:
			drive_entity = 0
		await frame()
	drive_entity = 0
	var seconds := (Time.get_ticks_usec() - started) / 1000000.0
	check(server.world.bots[id].body.global_position.distance_to(starts[id]) > 2, "Selected player's input moves its authoritative bot")
	for entity: int in server.world.bots:
		if entity != id:
			check(server.world.bots[entity].body.global_position.distance_to(starts[entity]) < 0.15, "Other nine bots stay stationary")
	print("5v5 local primitive-geometry fixture: %.3fs traffic window, %d physics ticks; one server + ten client worlds in one process" %
		[seconds, Engine.get_physics_frames() - physics_started])
	for index: int in range(10):
		var relay: Node = client_relays[index]
		var before: Dictionary = initial[index]
		var up: float = (relay.stats.uplink.bytes_in - before.uplink.bytes_in
			+ 28 * (relay.stats.uplink.packets_in - before.uplink.packets_in)) / seconds
		var down: float = (relay.stats.downlink.bytes_out - before.downlink.bytes_out
			+ 28 * (relay.stats.downlink.packets_out - before.downlink.packets_out)) / seconds
		var server_down: float = (relay.stats.downlink.bytes_in - before.downlink.bytes_in
			+ 28 * (relay.stats.downlink.packets_in - before.downlink.packets_in)) / seconds
		print("5v5 injected%.0f client%d: measuredRTT=%.1fms uplink=%.1fB/s received_downlink=%.1fB/s server_downlink=%.1fB/s (IPv4+UDP included)" %
			[injected_rtt, index, clients[index].diagnostics.rtt_ms, up, down, server_down])
		check(clients[index]._clock_ready, "Each client synchronizes through real delayed control replies")

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for relay: Node in relays:
		if not relay.stats.is_empty():
			for direction: String in ["uplink", "downlink"]:
				var counters: Dictionary = relay.stats[direction]
				check(counters.queue_dropped == 0 and counters.send_errors == 0 and counters.receive_errors == 0,
					"Ten-client relay has no overflow or socket errors")
				check(counters.packets_in > 0 and counters.packets_out > 0, "Each relay direction carried actual UDP")
		relay.stop()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("FIVE V FIVE SESSION PASS" if failures == 0 else "FIVE V FIVE SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
