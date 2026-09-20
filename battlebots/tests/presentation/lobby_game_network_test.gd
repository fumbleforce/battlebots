extends SceneTree
## Full B frontend with two isolated real UDP peers and public player input.
var failures := 0
var peers: Array[Dictionary] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func until(predicate: Callable, limit := 900) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await process_frame
	return false
func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame
func make_peer(label: String) -> Dictionary:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	root.add_child(view)
	set_multiplayer(SceneMultiplayer.new(), view.get_path())
	var game: Node3D = load("res://scenes/dev/b_lobby_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	view.add_child(game)
	var peer := {"view":view, "game":game}
	peers.append(peer)
	return peer
func run() -> void:
	var host := make_peer("GameHost")
	var client := make_peer("GameClient")
	var port := 39000 + OS.get_process_id() % 10000
	host.game.coordinator.request_host(port, 2)
	client.game.coordinator.request_join("127.0.0.1", port)
	var admitted := await until(func() -> bool: return client.game.session.local_entity > 0 and client.game.session.lobby_view.get("slots", []).size() == 2)
	check(admitted, "Playable frontend joins actual two-player UDP lobby")
	if admitted:
		host.game.coordinator.request_ready_state(true)
		client.game.coordinator.request_ready_state(true)
		var countdown := await until(func() -> bool: return client.game.session.match_view.get("phase") == "countdown")
		check(countdown, "Client receives authoritative countdown")
		await ticks(2)
		check(client.game.match_hud.visible and not client.game.lobby.visible and not client.game.gameplay_input_allowed(),
			"Countdown shows arena HUD while gameplay remains blocked")
		client.game.show_lobby()
		var active := await until(func() -> bool: return host.game.session.match_view.get("phase") == "active" and client.game.session.match_view.get("phase") == "active")
		check(active, "Both ready players enter authoritative active match")
		if active:
			await ticks(15)
			check(not host.game.lobby.visible and host.game.preview.controls_enabled, "Host automatically enters playable arena")
			check(client.game.lobby.visible and not client.game.preview.controls_enabled,
				"Countdown ending preserves explicitly opened menu")
			client.game.lobby.resume_button.pressed.emit()
			await ticks(2)
			check(not client.game.lobby.visible and client.game.preview.controls_enabled, "Client automatically enters playable arena")
			# Inputs are process-global; only the client's frontend produces drive commands.
			host.game.preview.set_physics_process(false)
			var authoritative: BotSource = host.game.session.world.bots[client.game.session.local_entity]
			var start := authoritative.read_view().pose.origin
			Input.action_press("drive_forward")
			await ticks(90)
			Input.action_release("drive_forward")
			check(authoritative.read_view().pose.origin.distance_to(start) > 1.0, "Client WASD input moves server-authoritative bot through UDP")
			client.game.show_lobby()
			check(client.game.lobby.visible and not client.game.gameplay_input_allowed(), "Client menu blocks gameplay")
			Input.action_press("drive_forward")
			await ticks(20)
			Input.action_release("drive_forward")
			check(client.game.session.connection_state == "connected" and not client.game.preview.controls_enabled, "Menu preserves live connection without resuming on held drive")
			client.game.resume_gameplay()
			await ticks(2)
			check(not client.game.lobby.visible and client.game.preview.controls_enabled, "Resume returns connected client to arena")
			host.game.session.vote_forfeit()
			check(await until(func() -> bool: return client.game.session.match_view.get("phase") == "intermission"),
				"Server round outcome reaches client")
			await ticks(2)
			check(client.game.match_hud.visible and not client.game.lobby.visible and not client.game.gameplay_input_allowed(),
				"Intermission keeps outcome visible without allowing drive")
			check([client.game.match_hud.score_label.text, client.game.match_hud.opponent_score_label.text].has("1"), "Authoritative round score appears in the split HUD")
			check(await until(func() -> bool: return client.game.session.match_view.get("phase") == "active", 1800),
				"Server starts second round")
			host.game.session.vote_forfeit()
			check(await until(func() -> bool: return client.game.session.match_view.get("phase") == "results"),
				"Server final outcome reaches client")
			await ticks(2)
			check(client.game.match_hud.visible and not client.game.gameplay_input_allowed(), "Results remain visible with gameplay blocked")
			check(not client.game.match_hud.result_label.text.is_empty(), "Final authoritative result is presented")
			client.game.show_lobby()
			check(client.game.lobby.resume_button.visible, "Results menu permits returning to the outcome")
			client.game.lobby.resume_button.pressed.emit()
			await ticks(2)
			check(client.game.match_hud.visible and not client.game.gameplay_input_allowed(),
				"Returning to results cannot re-enable driving")
	Input.action_release("drive_forward")
	for index: int in range(peers.size() - 1, -1, -1):
		peers[index].game.session.leave()
	await process_frame
	for index: int in range(peers.size() - 1, -1, -1):
		var view: SubViewport = peers[index].view
		set_multiplayer(null, view.get_path())
		view.queue_free()
	await process_frame
	print("LOBBY GAME NETWORK PASS" if failures == 0 else "LOBBY GAME NETWORK FAIL")
	quit(0 if failures == 0 else 1)
