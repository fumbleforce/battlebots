extends "res://tests/network/contact_reconciliation.gd"
## Independent F6 scene: all ENet traffic traverses opaque impaired UDP relays.
## Run in real time: --max-fps 60, never --fixed-fps (ENet uses wall clocks).
const Relay = preload("res://tests/network/fixtures/udp_relay.gd")
var relays: Array[Node] = []
var drive_entity := 0
var server_port := 0
var injected_rtt := 0.0
var jitter := 0.0
var loss := 0.0

func frame() -> void:
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.throttle = 1.0 if client.local_entity == drive_entity and drive_entity > 0 else 0.0
		command.brake = is_zero_approx(command.throttle)
		client.submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame

func make_relay(seed_offset: int) -> Node:
	var relay := Relay.new()
	relay.uplink = {"delay_ms":injected_rtt / 2, "jitter_ms":jitter, "loss":loss, "duplicate":0.02, "seed":7001 + seed_offset}
	relay.downlink = {"delay_ms":injected_rtt / 2, "jitter_ms":jitter, "loss":loss, "duplicate":0.02, "seed":9001 + seed_offset}
	var path_mtu := OS.get_environment("BATTLEBOTS_NET_MTU").to_int()
	relay.uplink["max_datagram_bytes"] = path_mtu
	relay.downlink["max_datagram_bytes"] = path_mtu
	add_child(relay)
	relays.append(relay)
	if relay.start(0, server_port) != OK:
		return null
	return relay

func active_everywhere() -> bool:
	return server.match_state.phase == "active" and clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "active" and c.world != null and c.world.bots.size() == 4)

func run() -> void:
	injected_rtt = float(profile) if profile in ["0", "80", "150"] else 80.0
	jitter = 20.0 if injected_rtt == 150 else (10.0 if injected_rtt == 80 else 0.0)
	loss = 0.03 if injected_rtt == 150 else (0.01 if injected_rtt == 80 else 0.0)
	server = make_session("TransportServer")
	server_port = FreePort.udp()
	if not await require(server.host(server_port, false, 4) == OK, "Transport server binds"):
		return
	# Stagger the client clocks from the server and force the first ENet connect
	# packet to be lost. Successful admission must include transport retransmission.
	await frames(60)
	for index: int in range(4):
		var relay := make_relay(index)
		if not await require(relay != null, "Loopback relay binds"):
			return
		if index == 0:
			relay.drop_next_uplink = 1
		var client := make_session("TransportClient%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", relay.bound_port) == OK, "Join through raw relay starts")
	if not await require(await until(func() -> bool:
		return server.players.size() == 4 and clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0), 1800),
		"Four clients admitted despite lost connect packet"):
		return
	check(relays[0].stats.uplink.forced_dropped == 1, "Initial client UDP packet actually dropped")
	var lifter := clients[1].registry.starter(true)
	# JSON control messages normalize numeric variants (schema int -> float).
	var wire_lifter := WireCodec.read_json(WireCodec.json_packet(lifter), 4096)
	clients[1].set_loadout(lifter)
	if not await require(await until(func() -> bool:
		return server.players[clients[1].local_entity].loadout == wire_lifter), "Reliable loadout request reaches authority"):
		return
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await require(await until(active_everywhere), "Ready, baseline and countdown cross impaired reliable transport"):
		return
	await frames(150)
	for session: MvpSession in sessions:
		check(session.network_simulation.delay_ms == 0 and session.network_simulation.loss == 0,
			"Production message simulator stays off: raw relay is the only impairment")
	for client: MvpSession in clients:
		check_clock(client, "active")
	var id := clients[0].local_entity
	var other := clients[1].local_entity
	var start: Vector3 = server.world.bots[id].body.global_position
	var other_start: Vector3 = server.world.bots[other].body.global_position
	drive_entity = id
	await frames(90)
	drive_entity = 0
	check(server.world.bots[id].body.global_position.distance_to(start) > 2, "Remote intent moves its owned bot")
	check(server.world.bots[other].body.global_position.distance_to(other_start) < 0.1, "Other player's idle bot remains stationary")
	server.world.bots[id].combat.damage("top", 30)
	var damaged_core: float = server.world.bots[id].combat.core
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return is_equal_approx(c.world.bots[id].remote_state.core, damaged_core))), "Authoritative damage reaches every observer")
	# Authoritative setup accelerates the match; no test-only RPC is exposed.
	eliminate_team(1)
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "intermission" and c.match_view.get("scores") == [1, 0])),
		"Every client receives round result and score"):
		return
	server.match_state.remaining = 0
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("round") == 2 and c.match_view.get("phase") == "countdown")), "Round two reliably arrives"):
		return
	await frames(45)
	for client: MvpSession in clients:
		for entity: int in server.world.bots:
			var bot: MvpBot = client.world.bots[entity]
			check(not bot.remote_state.eliminated and is_equal_approx(bot.remote_state.core, bot.combat.stats.core), "Round reset repairs and revives every observer")
			check(bot.remote_state.epoch == WireCodec.snapshot_epoch(server.match_state.match_id, 2), "Reset uses new round identity")
			var spawn_error := bot.presentation.global_position.distance_to(server.world.bots[entity].body.global_position)
			if spawn_error >= 0.1:
				print("Transport reset fault observer=", client.local_entity, " entity=", entity,
					" authority=", server.world.bots[entity].body.global_position, " presentation=", bot.presentation.global_position,
					" body=", bot.body.global_position, " tick=", bot.remote_state.tick, " server_tick=", server.world.tick)
			check(spawn_error < 0.1, "Reset reaches authoritative spawn")
	if not await require(await until(active_everywhere), "Round two becomes active"):
		return
	var retained: MvpBot = server.world.bots[id]
	retained.combat.damage("top", 30)
	damaged_core = retained.combat.core
	var token := clients[0].reconnect_token
	clients[0].leave()
	if not await require(await until(func() -> bool: return server.players[id].peer == 0), "Disconnect reserves entity through relay"):
		return
	relays[0].stop()
	var reconnect_relay := make_relay(10)
	if not await require(reconnect_relay != null, "Reconnect relay binds"):
		return
	check(clients[0].join("127.0.0.1", reconnect_relay.bound_port, token) == OK, "Reconnect uses fresh UDP endpoint")
	if not await require(await until(func() -> bool:
		return clients[0].local_entity == id and clients[0].world != null and clients[0].world.bots.has(id)), "Reliable reconnect baseline restores original entity"):
		return
	check(server.world.bots[id] == retained and retained.combat.core == damaged_core, "Reconnect retains authoritative body and damage")
	check(clients[0].reconnect_token != token, "Reconnect rotates token")
	check(is_equal_approx(clients[0].world.bots[id].remote_state.core, damaged_core), "Reconnect baseline contains existing damage")
	await frames(180)
	check_clock(clients[0], "reconnect")
	eliminate_team(1)
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "results" and c.match_view.get("winner") == 0)), "Complete first-to-two results agree"):
		return
	var old_match := server.match_state.match_id
	for client: MvpSession in clients:
		client.vote_rematch()
	check(await until(func() -> bool:
		return active_everywhere() and server.match_state.match_id != old_match and clients.all(func(c: MvpSession) -> bool:
			return c.match_view.get("match_id") == server.match_state.match_id and c.match_view.get("round") == 1)),
		"Reliable rematch votes start a new match for every player")
	await finish()

func eliminate_team(team: int) -> void:
	for entity: int in server.world.bots:
		if server.players[entity].team == team:
			server.world.bots[entity].combat.eliminate("transport test")

func check_clock(client: MvpSession, label: String) -> void:
	var error := absf(client._client_tick + client._server_tick_offset - server.world.tick)
	print("Whole UDP injected RTT %.0f ms %s: measured RTT=%.1f ms clock error=%.2f ticks" %
		[injected_rtt, label, client.diagnostics.rtt_ms, error])
	check(client._clock_ready and error <= 4, "%s synchronizes actual delayed control replies within four physics ticks" % label)
	check(client.diagnostics.rtt_ms >= injected_rtt - jitter * 2, "Measured RTT includes both relay directions")

func require(ok: bool, message: String) -> bool:
	check(ok, message)
	if not ok:
		await finish()
	return ok

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for relay: Node in relays:
		if relay.stats.is_empty():
			relay.stop()
			continue
		for direction: String in ["uplink", "downlink"]:
			var counters: Dictionary = relay.stats[direction]
			check(counters.packets_in > 0 and counters.packets_out > 0, "Actual UDP traffic crosses each relay direction")
			check(counters.queue_dropped == 0 and counters.send_errors == 0 and counters.receive_errors == 0,
				"Test relay has no overflow or socket errors")
			if OS.get_environment("BATTLEBOTS_NET_MTU").to_int() > 0:
				check(counters.mtu_dropped == 0, "Current game traffic stays within the simulated path MTU")
		print("Whole UDP profile %.0f relay: %s" % [injected_rtt, relay.stats])
		relay.stop()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("TRANSPORT SESSION PASS" if failures == 0 else "TRANSPORT SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
