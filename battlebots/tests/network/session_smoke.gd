extends SceneTree
var failures := 0
var sessions: Array[MvpSession] = []
var containers: Array[SubViewport] = []
var server: MvpSession
var clients: Array[MvpSession] = []
var port := 25000 + OS.get_process_id() % 10000

func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func make_session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	root.add_child(viewport)
	var api := SceneMultiplayer.new()
	set_multiplayer(api, viewport.get_path())
	var session := MvpSession.new()
	session.name = "Session"
	viewport.add_child(session)
	containers.append(viewport)
	sessions.append(session)
	return session
func until(predicate: Callable, max_frames := 1200) -> bool:
	for frame: int in range(max_frames):
		if predicate.call():
			return true
		await process_frame
	return false
func frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame
func run() -> void:
	server = make_session("Server")
	check(server.host(port, false) == OK, "Server binds UDP")
	for index: int in range(4):
		var client := make_session("Client%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Client starts connection")
	check(await until(func() -> bool: return server.players.size() == 4 and clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)), "Four clients admitted")
	if server.players.size() != 4:
		finish()
		return
	check(clients[0].lobby_view.get("slots", []).size() == 4, "Lobby replicated")
	var bad := clients[0].registry.starter()
	bad.parts.weapon = "unknown"
	clients[0].set_loadout(bad)
	await frames(10)
	check(server.registry.validate(server.players[clients[0].local_entity].loadout).valid, "Invalid loadout does not replace server build")
	clients[1].set_loadout(clients[1].registry.starter(true))
	await frames(10)
	for client: MvpSession in clients:
		client.set_ready(true)
	check(await until(func() -> bool: return server.match_state.phase == "active"), "Ready/loading/countdown reaches active")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.world.bots.size() == 4 and c.diagnostics.snapshots_received >= 4)), "Four clients receive full baselines/snapshots")
	check(server.diagnostics.snapshot_bytes <= 1200, "Entity datagrams fit budget")
	var id := clients[0].local_entity
	var start: Vector3 = server.world.bots[id].body.global_position
	for frame: int in range(90):
		var command := BotCommand.new()
		command.throttle = 1
		clients[0].submit_local(command)
		await physics_frame
	check(server.world.bots[id].body.global_position.distance_to(start) > 2, "Remote intent moves only owned physical bot")
	var rejected: int = server.diagnostics.rejected_inputs
	clients[0]._inputs.rpc_id(1, var_to_bytes([[999999, 1.0, 0.0, 0], [91, NAN, 0.0, 0]]))
	await frames(10)
	check(server.diagnostics.rejected_inputs > rejected, "Malformed/non-finite/sequence-jump commands rejected")
	check(server.world.bots[id].body.global_position.is_finite(), "Hostile input leaves finite server state")
	var token := clients[0].reconnect_token
	var retained: MvpBot = server.world.bots[id]
	retained.combat.damage("top", 30)
	var core_before: float = retained.combat.core
	clients[0].leave()
	check(await until(func() -> bool: return server.players[id].peer == 0, 180), "Disconnect reserves slot")
	check(clients[0].join("127.0.0.1", port, token) == OK, "Reconnect starts")
	check(await until(func() -> bool: return clients[0].local_entity == id and server.players[id].peer != 0, 600), "Token restores original entity")
	check(server.world.bots[id] == retained and retained.combat.core == core_before, "Reconnect preserves bot/damage")
	check(clients[0].reconnect_token != token, "Reconnect rotates token")
	# Use server-local elimination to exercise lifecycle quickly; no remote test/debug RPC exists.
	for round_number: int in range(2):
		for entity: int in server.world.bots:
			if server.players[entity].team == 1:
				server.world.bots[entity].combat.eliminate("test")
		await frames(5)
		if round_number == 0:
			check(server.match_state.phase == "intermission", "Round ends on elimination")
			server.match_state.remaining = 0
			check(await until(func() -> bool: return server.match_state.phase == "active", 600), "Next round repairs and starts")
	check(server.match_state.phase == "results" and server.match_state.winner == 0, "Complete first-to-two match")
	var old_id := server.match_state.match_id
	for client: MvpSession in clients:
		client.vote_rematch()
	check(await until(func() -> bool: return server.match_state.match_id != old_id and server.match_state.phase == "active", 900), "Unanimous rematch starts new match")
	clients[0].leave()
	await until(func() -> bool: return server.players[id].peer == 0, 180)
	server.players[id].deadline = server._time - 1
	await frames(5)
	check(server.world.bots[id].combat.eliminated, "Disconnect expiry eliminates retained bot")
	print("Max entity snapshot bytes: ", server.diagnostics.snapshot_bytes)
	finish()
func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for viewport: SubViewport in containers:
		viewport.queue_free()
	await process_frame
	print("NETWORK PASS" if failures == 0 else "NETWORK FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
