extends SceneTree
## Real ENet recovery; damage is authored to isolate identity/state preservation.
var failures := 0
var sessions: Array[MvpSession] = []
var server: MvpSession
var client: MvpSession
var joined: Dictionary = {}
var errors: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

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
	return session

func drop() -> bool:
	var peer: int = server.players[client.local_entity].peer
	server.multiplayer.multiplayer_peer.disconnect_peer(peer)
	return await until(func() -> bool: return client.connection_state == "offline" and client.can_reconnect())

func run() -> void:
	create_timer(55).timeout.connect(func() -> void: quit(1))
	server = make_session("Server")
	client = make_session("Client")
	client.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "joined": joined = details
		if kind == "error": errors.append(details))
	var port := 38000 + OS.get_process_id() % 10000
	check(server.host(port, true, 2) == OK and client.join("127.0.0.1", port) == OK, "Duel starts")
	if not await until(func() -> bool: return client.local_entity > 0):
		check(false, "Client joins")
		await finish()
		return
	check(not joined.reconnected and not client.can_reconnect(), "Initial admission is not recovery")
	server.set_ready(true)
	client.set_ready(true)
	if not await until(func() -> bool: return client.match_view.get("phase") == "active"):
		check(false, "Duel becomes active")
		await finish()
		return
	var id := client.local_entity
	var body: MvpBot = server.world.bots[id]
	body.combat.damage("top", 30)
	var core := body.combat.core
	var token := client.reconnect_token
	check(await drop(), "Unexpected ENet loss offers recovery")
	check(errors.back().reconnect_available and client.reconnect_seconds_remaining() > 18, "Loss event publishes bounded recovery")
	check(client.reconnect() == OK and client.is_reconnecting(), "Manual reconnect begins")
	check(await until(func() -> bool: return client.local_entity == id and client.world.bots.has(id)), "Original identity receives new baseline")
	check(server.world.bots[id] == body and is_equal_approx(client.world.bots[id].remote_state.core, core), "Recovery retains damaged authoritative body")
	check(joined.reconnected and client.reconnect_token != token and not client.is_reconnecting(), "Welcome marks recovery and rotates credential")
	check(await drop(), "Second loss is recoverable")
	var current_token := client.reconnect_token
	client.leave()
	check(not client.can_reconnect() and client.reconnect_token.is_empty() and client.reconnect() == ERR_UNAVAILABLE, "Explicit leave cancels recovery and erases credentials")
	# A saved obsolete credential must be rejected, never become a fresh player.
	check(client.join("127.0.0.1", port, token) == OK, "Obsolete credential reaches server")
	check(await until(func() -> bool: return client.connection_state == "offline"), "Server rejects obsolete credential")
	check(not client.can_reconnect() and client.reconnect_token.is_empty() and server.players.size() == 2, "Rejected credential cannot create a new identity")
	check(client.join("127.0.0.1", port, current_token) == OK, "Valid retained fixture credential rejoins")
	check(await until(func() -> bool: return client.local_entity == id), "Fixture rejoins reserved entity")
	check(await drop(), "Third transport loss begins fresh recovery interval")
	var remaining := client.reconnect_seconds_remaining()
	check(client.reconnect() == OK, "Retry can begin within recovery window")
	# Inject the transport failure signal before ENet polls, to exercise a failed
	# attempt deterministically without spending its platform-dependent timeout.
	client.multiplayer.connection_failed.emit()
	check(client.can_reconnect() and not client.is_reconnecting() and client.reconnect_seconds_remaining() <= remaining,
		"Failed retry preserves credentials without extending the first-loss deadline")
	var retained_token := client.reconnect_token
	server.players[id].token = "revoked-by-fixture"
	check(client.reconnect() == OK, "Recovery with a server-revoked token reaches admission")
	check(await until(func() -> bool: return client.connection_state == "offline"), "Server rejects revoked recovery")
	check(not client.can_reconnect() and client.reconnect_token.is_empty(), "Rejected recovery terminates instead of falling back to fresh admission")
	server.players[id].token = retained_token
	check(client.join("127.0.0.1", port, retained_token) == OK, "Fixture restores original identity for expiry check")
	check(await until(func() -> bool: return client.local_entity == id), "Expiry fixture receives welcome")
	check(await drop(), "Expiry fixture loses transport")
	check(await until(func() -> bool: return client.reconnect_token.is_empty(), 21.0), "Real wall-clock expiry retires credentials without a retry")
	check(not client.can_reconnect() and client.reconnect() == ERR_UNAVAILABLE and not errors.back().reconnect_available, "Expired recovery is unavailable and terminal")
	await finish()

func finish() -> void:
	for session: MvpSession in sessions: session.leave()
	for node: Node in root.get_children(): node.queue_free()
	await process_frame
	print("RECONNECT SESSION PASS" if failures == 0 else "RECONNECT SESSION FAIL")
	quit(0 if failures == 0 else 1)
