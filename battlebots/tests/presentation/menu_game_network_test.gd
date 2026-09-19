extends SceneTree
## Imported lobby -> authoritative loading/countdown -> persistent playable arena.
var failures := 0
var views: Array[SubViewport] = []
var audio_cues: Array[String] = []
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
	var host_view := viewport("Host")
	var game: Node3D = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	game.audio_settings_path = ""
	host_view.add_child(game)
	game.gameplay_audio.cue_played.connect(func(cue: String) -> void: audio_cues.append(cue))
	var client_view := viewport("Client")
	var peer := Node3D.new()
	peer.name = "MenuGame"
	var client := MvpSession.new()
	client.name = "Session"
	peer.add_child(client)
	client_view.add_child(peer)
	var router: Node = root.get_node("MenuRouter")
	router.match_setup.mode = "duel"
	router.goto("lobby")
	await ticks(3)
	var lobby: Control = game.screen
	check(lobby.has_method("host_session"), "Router mounts imported lobby in persistent game")
	var port := 39000 + OS.get_process_id() % 10000
	lobby.port.value = port
	lobby.host_button.pressed.emit()
	check(game.session.connection_state == "hosting", "Imported Host button starts real session")
	check(client.join("127.0.0.1", port) == OK, "Second independent peer connects")
	var admitted := await until(func() -> bool: return client.local_entity > 0 and client.lobby_view.get("slots", []).size() == 2)
	check(admitted, "Real UDP admission populates authoritative duel lobby")
	if admitted:
		client.set_ready(true)
		await ticks(15)
		lobby.get_node("%Ready").pressed.emit()
		check(await until(func() -> bool: return game.session.match_view.get("phase") == "loading" or game.session.match_view.get("phase") == "countdown"), "Ready button starts authoritative loading")
		check(await until(func() -> bool: return game.session.match_view.get("phase") == "countdown"), "Server advances loaded peers into countdown")
		await ticks(3)
		check(not game.menu_host.visible and game.match_hud.visible, "Countdown enters arena with match HUD")
		check(not game.gameplay_input_allowed(), "Countdown keeps player command production neutral")
		var active := await until(func() -> bool: return game.session.match_view.get("phase") == "active" and client.match_view.get("phase") == "active")
		check(active, "Real peers reach active match")
		if active:
			await ticks(5)
			check(audio_cues.count("countdown") == 3 and audio_cues.count("start") == 1, "Authoritative countdown and start produce exactly one cue each")
			check(game.preview.controls_enabled and game.session.local_source() != null, "Persistent shell keeps active bot and controls")
			var bot: BotSource = game.session.local_source()
			var start := bot.read_view().pose.origin
			Input.action_press("drive_forward")
			await ticks(90)
			Input.action_release("drive_forward")
			check(bot.read_view().pose.origin.distance_to(start) > 1.0, "WASD moves actual authoritative host bot")
			var pause := InputEventAction.new()
			pause.action = "pause"
			pause.pressed = true
			game._input(pause)
			check(game.preview.pause_menu.visible and not game.gameplay_input_allowed(), "Pause exposes actual pause menu and blocks input")
			Input.action_press("drive_forward")
			await ticks(10)
			check(client.connection_state == "connected", "Paused arena retains peer connection")
			game._input(pause)
			await ticks(2)
			check(game.preview.controls_enabled and not game.preview.pause_menu.visible, "Pause again resumes existing arena")
			Input.action_release("drive_forward")
			await ticks(3)
			game._forfeit.pressed.emit()
			check(await until(func() -> bool: return client.match_view.get("phase") == "intermission"), "Shell forfeit action reaches authority and peer")
			check(await until(func() -> bool: return game.session.match_view.get("phase") == "active", 1800), "Second round starts without replacing menu shell")
			game._forfeit.pressed.emit()
			check(await until(func() -> bool: return client.match_view.get("phase") == "results"), "Shell finishes real first-to-two match")
			await ticks(3)
			check(game.results_panel.visible and not game.gameplay_input_allowed(), "Results open automatically with driving blocked")
			check(audio_cues.count("round_end") == 1 and audio_cues.count("results") == 1, "Round and match completion cues follow actual session transitions")
			check(game.results_panel.record.get("participants", {}).size() == 2, "Results panel receives both authoritative participant records")
			check(game.results_panel.scope.item_count == 3, "Both completed rounds available")
			var completed_match: String = game.session.match_view.get("match_id", "")
			game.results_panel.rematch.pressed.emit()
			check(game.results_panel.rematch.disabled, "Rematch button suppresses duplicate requests")
			client.vote_rematch()
			check(await until(func() -> bool: return game.session.match_view.get("match_id") != completed_match and game.session.match_view.get("phase") == "active"), "Both rematch votes start a new authoritative match")
			await ticks(3)
			check(not game.menu_host.visible and game.preview.controls_enabled, "Persistent shell reopens arena after rematch loading")
			check(not game.results_panel.visible and game.results_panel.record.is_empty(), "Rematch clears previous result UI")
	Input.action_release("drive_forward")
	# Drain live world teardown before releasing its isolated physics spaces.
	# A process_frame signal fires before deferred deletions finish that frame.
	game.preview.release_controls(false)
	client.leave()
	game.session.leave()
	await ticks(3)
	for index: int in range(views.size() - 1, -1, -1):
		var view := views[index]
		set_multiplayer(null, view.get_path())
		view.queue_free()
	await ticks(3)
	for view: SubViewport in views:
		check(not is_instance_valid(view), "Peer viewport fully freed before engine shutdown")
	views.clear()
	print("MENU GAME NETWORK PASS" if failures == 0 else "MENU GAME NETWORK FAIL")
	quit(0 if failures == 0 else 1)
