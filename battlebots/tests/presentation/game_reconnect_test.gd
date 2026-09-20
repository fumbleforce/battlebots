extends SceneTree
## Real transport loss in the composed client game; authored damage is a fixture.
var failures := 0
var views: Array[SubViewport] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable, seconds := 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func viewport(label: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	root.add_child(view)
	set_multiplayer(SceneMultiplayer.new(), view.get_path())
	views.append(view)
	return view

func run() -> void:
	create_timer(60).timeout.connect(func() -> void:
		push_error("Game reconnect fixture exceeded wall-clock limit")
		quit(1))
	var host_root := Node.new()
	host_root.name = "MenuGame"
	var server := MvpSession.new()
	server.name = "Session"
	host_root.add_child(server)
	viewport("Host").add_child(host_root)
	var game: Node3D = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	viewport("Client").add_child(game)
	var client: MvpSession = game.session
	var router: Node = root.get_node("MenuRouter")
	router.lobby_intent = "join"
	router.goto("lobby", false)
	var port := 43000 + OS.get_process_id() % 9000
	check(server.host(port, true, 2) == OK, "Listen server starts")
	check(client.join("127.0.0.1", port) == OK, "Game client connects")
	if await until(func() -> bool: return client.lobby_view.get("slots", []).size() == 2):
		server.set_ready(true)
		client.set_ready(true)
		if await until(func() -> bool: return client.match_view.get("phase") == "active"):
			var id := client.local_entity
			var token := client.reconnect_token
			var match_id: String = client.match_view.match_id
			var body: MvpBot = server.world.bots[id]
			body.combat.damage("top", 30)
			var retained_core: float = body.combat.core
			# Model an already connected service membership; the ENet connection is real.
			router.lobby_intent = "online"
			game.public_service.state = "connected"
			game.public_service.membership = {"room_id":"fixture-room"}
			game.preview.open_settings()
			game.hud_settings_button.pressed.emit()
			game.hud_settings.text_scale_choice.select(2)
			game.hud_settings.text_scale_choice.item_selected.emit(2)
			server.multiplayer.multiplayer_peer.disconnect_peer(int(server.players[id].peer))
			check(await until(func() -> bool: return game.reconnect_panel.visible and client.connection_state == "offline"), "Transport loss opens reconnect panel")
			await process_frame
			check(not game.gameplay_input_allowed() and not game.combat_hud.visible, "Recovery suppresses controls and stale combat HUD")
			check(not game._hud_overlay.visible and game.combat_hud.text_scale == 1.0, "Connection loss closes HUD settings and restores unsaved preview")
			check(game.public_service.state == "connected" and not game.public_service.membership.is_empty(), "Recovery preserves hosted membership instead of failing/cancelling it")
			game.reconnect_panel.retry.pressed.emit()
			check(client.is_reconnecting(), "Retry action starts same-session connection")
			check(await until(func() -> bool: return client.connection_state == "connected" and not game.reconnect_panel.visible), "Received baseline restores composed game")
			check(client.local_entity == id and client.reconnect_token != token, "Recovery retains identity and rotates private token")
			check(server.world.bots[id] == body and body.combat.core == retained_core, "Reconnect retains damaged server bot")
			check(client.match_view.get("match_id") == match_id and not game.menu_host.visible, "Recovery returns to same match without lobby detour")
			client.vote_forfeit()
			check(await until(func() -> bool: return client.match_view.get("phase") == "intermission"), "Public forfeit ends first round")
			check(await until(func() -> bool: return client.match_view.get("phase") == "active", 25.0), "Real intermission/countdown completes")
			client.vote_forfeit()
			check(await until(func() -> bool: return game.results_panel.visible), "Second public forfeit reaches results")
			server.multiplayer.multiplayer_peer.disconnect_peer(int(server.players[id].peer))
			check(await until(func() -> bool: return game.reconnect_panel.visible), "Second transport loss remains recoverable")
			game.reconnect_panel.retry.pressed.emit()
			check(await until(func() -> bool: return not game.reconnect_panel.visible and game.results_panel.visible), "Results-phase reconnect restores score screen")
			check(game.results_panel.record.get("participants", {}).size() == 2 and not game.gameplay_input_allowed(), "Results baseline restores both participants without enabling arena controls")
			server.multiplayer.multiplayer_peer.disconnect_peer(int(server.players[id].peer))
			check(await until(func() -> bool: return game.reconnect_panel.visible), "Final dropout exposes leave action")
			game.reconnect_panel.leave_button.pressed.emit()
			await process_frame
			check(not game.reconnect_panel.visible and not client.can_reconnect() and client.reconnect_token.is_empty(), "Leave clears recovery and credentials")
			check(router.current == "main", "Leave returns to main menu")
		else:
			check(false, "Duel reaches active")
	else:
		check(false, "Client receives lobby")
	client.leave()
	server.leave()
	for view: SubViewport in views:
		view.queue_free()
	await process_frame
	await process_frame
	print("GAME RECONNECT PASS" if failures == 0 else "GAME RECONNECT FAILED")
	quit(0 if failures == 0 else 1)
