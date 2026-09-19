extends Node
## Independent F6 scene: live ENet tick origins/reconnect, then isolated clock probes.
## Synthetic pong probes check the estimator; they do not impair control transport.
var failures := 0
var sessions: Array[MvpSession] = []
var server: MvpSession
var clients: Array[MvpSession] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func make_session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	add_child(viewport)
	get_tree().set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var session := MvpSession.new()
	session.name = "Session"
	viewport.add_child(session)
	sessions.append(session)
	return session

func frame() -> void:
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.brake = true
		client.submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame

func frames(count: int) -> void:
	for index: int in range(count):
		await frame()

func until(predicate: Callable, limit := 1200) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await frame()
	return false

func run() -> void:
	server = make_session("ClockServer")
	var port := 34000 + OS.get_process_id() % 10000
	check(server.host(port, false, 2) == OK, "Clock server binds")
	await frames(180)
	for index: int in range(2):
		var client := make_session("ClockClient%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Clock client joins")
		await frames(90)
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)):
		check(false, "Staggered clients admitted")
		await finish()
		return
	await frames(120)
	for client: MvpSession in clients:
		check_clock(client, "staggered join")
		client.set_ready(true)
	check(absf(clients[0]._server_tick_offset - clients[1]._server_tick_offset) >= 80,
		"Clients actually use different tick origins")
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.match_view.get("phase") == "active")):
		check(false, "Clock match reaches active")
		await finish()
		return
	var client := clients[0]
	var id := client.local_entity
	var token := client.reconnect_token
	client.leave()
	check(client._ping_ticks.is_empty() and not client._clock_ready, "Leave clears outstanding clock samples")
	if not await until(func() -> bool: return server.players[id].peer == 0):
		check(false, "Disconnect reserves original entity")
		await finish()
		return
	await frames(90)
	check(client.join("127.0.0.1", port, token) == OK, "Reconnect starts")
	if not await until(func() -> bool: return client.local_entity == id and client.world.bots.has(id)):
		check(false, "Reconnect baseline restores original entity")
		await finish()
		return
	check(absf(client._client_tick + client._server_tick_offset - server.world.tick) <= 2,
		"Reconnect baseline immediately seeds the new tick origin")
	await frames(90)
	check_clock(client, "reconnect")
	check_pong_samples(client)
	check_replay_bounds(client, id)
	check_airborne_baseline(client, id)
	check_pending_reset_baselines(client)
	await finish()

func check_clock(client: MvpSession, label: String) -> void:
	var error := absf(client._client_tick + client._server_tick_offset - server.world.tick)
	print("Clock %s: offset=%.1f ticks error=%.1f ticks" % [label, client._server_tick_offset, error])
	check(client._clock_ready and error <= 2, "%s synchronizes clocks within two physics ticks" % label)

func check_pong_samples(client: MvpSession) -> void:
	# Send at client tick 100 while server tick is 500. Symmetric transit must
	# recover the known +400 origin, regardless of total round-trip duration.
	for rtt_ticks: int in [0, 4, 10, 60]:
		client._clock_ready = false
		client._client_tick = 100 + rtt_ticks
		client._ping_ticks[123456] = 100
		client._pong(123456, 500 + rtt_ticks / 2)
		check(is_equal_approx(client._server_tick_offset, 400), "Symmetric delayed pong preserves known clock origin")
	var prior := client._server_tick_offset
	client._pong(999999, 999999)
	check(client._server_tick_offset == prior, "Unsolicited pong cannot change clock estimate")
	# Reliable retransmission can delay just one direction. A slow first reply
	# must not keep biasing the origin after a clean short round trip arrives.
	client._clock_ready = false
	client._client_tick = 172
	client._ping_ticks[123457] = 100
	client._pong(123457, 504) # Four ticks up, 68 down; midpoint estimate is wrong.
	client._client_tick = 212
	client._ping_ticks[123458] = 200
	client._pong(123458, 606) # Clean six ticks each way, true origin remains +400.
	check(absf(client._server_tick_offset - 400) <= 2,
		"Clean pong promptly replaces a retransmission-biased first clock sample")
	client._client_tick = 372
	client._ping_ticks[123459] = 300
	client._pong(123459, 704)
	check(absf(client._server_tick_offset - 400) <= 2,
		"Later asymmetric retransmission does not displace the clean clock sample")
	# A formerly faster route must not lock the estimate forever when clock
	# origins change and all subsequent samples have a slightly longer transit.
	for index: int in range(8):
		var sent := 400 + index * 100
		client._client_tick = sent + 20
		client._ping_ticks[123460 + index] = sent
		client._pong(123460 + index, sent + 410 + 10)
	check(absf(client._server_tick_offset - 410) <= 2,
		"Recent slower samples eventually retire an obsolete faster clock estimate")
	print("Clock synthetic RTT samples: 0/67/167/1000 ms passed")

func airborne_values(id: int) -> Array:
	var epoch := WireCodec.snapshot_epoch(server.match_state.match_id, server.match_state.round_index)
	var values: Array = bytes_to_var(WireCodec.encode_bot(server.world.bots[id], epoch))
	values[4] = Transform3D(Basis.IDENTITY, Vector3(0, 10, 0))
	values[5] = Vector3(3, 0, 0)
	values[6] = Vector3.ZERO
	values[28] = false
	return values

func check_replay_bounds(client: MvpSession, id: int) -> void:
	var values := airborne_values(id)
	client._local_commands.clear()
	client._server_tick_offset = 0
	var bot: MvpBot = client.world.bots[id]
	# Constant airborne horizontal speed is an independent clock ruler. Expected
	# displacement includes two callback boundaries and caps extrapolation at 250 ms.
	for sample: Vector2 in [Vector2(-100, 0), Vector2(0, 0.1), Vector2(6, 0.4), Vector2(100, 0.75)]:
		values[1] += 1000
		client._client_tick = values[1] + int(sample.x)
		client._snapshot(var_to_bytes(values))
		check(not bot.body.correction.is_empty(), "Timing sample schedules physical correction")
		if not bot.body.correction.is_empty():
			check(absf(bot.body.correction.pose.origin.x - sample.y) < 0.001,
				"Snapshot age %d stays within expected replay interval" % int(sample.x))
	print("Clock replay bounds: future/current/delayed/stale snapshots checked")

func check_airborne_baseline(client: MvpSession, id: int) -> void:
	var states := {}
	var epoch := WireCodec.snapshot_epoch(server.match_state.match_id, server.match_state.round_index)
	for entity: int in server.world.bots:
		states[entity] = WireCodec.encode_bot(server.world.bots[entity], epoch)
	var values := airborne_values(id)
	values[1] = server.world.tick
	values[5] = Vector3(3, 6, 0)
	values[6] = Vector3(4, 0, 0)
	states[id] = var_to_bytes(values)
	client._baseline(var_to_bytes({"lobby":server._public_lobby(), "match":server.match_state.snapshot(),
		"bots":states, "server_tick":server.world.tick}))
	var restored: MvpBot = client.world.bots[id]
	# Baselines seed exact authority state; unchecked replay here could tunnel
	# through a nearby wall before the physics callback can sweep its motion.
	# Later snapshots schedule bounded replay, already checked above.
	var velocity := restored.body.linear_velocity
	var angular := restored.body.angular_velocity
	check(not restored.body.freeze, "Active baseline enables local prediction")
	check(restored.body.global_transform.is_equal_approx(values[4]), "Active baseline seeds authoritative pose")
	check(velocity.is_equal_approx(Vector3(3, 6, 0)), "Active baseline restores authoritative linear velocity")
	check(angular.is_equal_approx(Vector3(4, 0, 0)), "Active baseline restores authoritative angular velocity")
	check(restored.body.correction.is_empty(), "Baseline clears stale deferred correction")
	print("Clock active baseline: velocity=%s angular=%s" % [velocity, angular])

func check_pending_reset_baselines(client: MvpSession) -> void:
	# _start sends a baseline immediately after creating bots, before Jolt can
	# place them at their spawn markers. Exercise that exact pending-reset state.
	server._start()
	check_pending_reset_baseline(client, "initial spawn")
	for bot: MvpBot in server.world.bots.values():
		bot.body.global_position = Vector3(7 + bot.entity_id, 3, 5)
		bot.body.linear_velocity = Vector3(4, 2, 1)
		bot.body.angular_velocity = Vector3(3, 1, 2)
		bot.body._drive_input = 0.8
		bot.body._turn_input = -0.6
		bot.body.grounded = true
	server.world.reset_round()
	server.match_state.round_index += 1
	server.match_state.transition("countdown", 5)
	check_pending_reset_baseline(client, "post-motion round reset")
	print("Clock pending-reset baselines: initial spawn and post-motion reset checked")

func check_pending_reset_baseline(client: MvpSession, label: String) -> void:
	var states := {}
	var epoch := WireCodec.snapshot_epoch(server.match_state.match_id, server.match_state.round_index)
	for id: int in server.world.bots:
		var authoritative: MvpBot = server.world.bots[id]
		check(authoritative.body.reset_pose is Transform3D, "%s is tested before Jolt applies reset" % label)
		check(authoritative.body.global_position.distance_to(authoritative.spawn_pose.origin) > 1,
			"%s retains a distinguishable old physical pose" % label)
		states[id] = WireCodec.encode_bot(authoritative, epoch)
	client._baseline(var_to_bytes({"lobby":server._public_lobby(), "match":server.match_state.snapshot(),
		"bots":states, "server_tick":server.world.tick}))
	for id: int in server.world.bots:
		var authoritative: MvpBot = server.world.bots[id]
		var restored: MvpBot = client.world.bots[id]
		var expected: Transform3D = authoritative.body.reset_pose
		check(restored.body.global_transform.is_equal_approx(expected), "%s baseline uses pending authoritative spawn" % label)
		check(restored.presentation.global_transform.is_equal_approx(expected), "%s presentation starts at pending spawn" % label)
		check(restored.remote_state.velocity.is_zero_approx() and restored.remote_state.angular.is_zero_approx(),
			"%s baseline clears previous linear and angular motion" % label)
		check(is_zero_approx(restored.remote_state.drive_input) and is_zero_approx(restored.remote_state.turn_input)
			and not restored.remote_state.grounded, "%s baseline clears previous drive and ground state" % label)
		check(restored.remote_state.epoch == epoch, "%s baseline carries current round identity" % label)

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("CLOCK SYNC PASS" if failures == 0 else "CLOCK SYNC FAIL")
	get_tree().quit(0 if failures == 0 else 1)
