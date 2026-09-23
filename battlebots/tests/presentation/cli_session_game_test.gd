extends SceneTree
## Windowed CLI host/join enter the full menu game (lobby, then combat HUD and
## impact feedback) instead of the legacy mvp.tscn console. Real ENet sessions.
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

func game_in(label: String) -> Node3D:
	var game: Node3D = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	viewport(label).add_child(game)
	return game

func peer_in(label: String) -> MvpSession:
	var holder := Node.new()
	holder.name = "MenuGame"
	var peer := MvpSession.new()
	peer.name = "Session"
	holder.add_child(peer)
	viewport(label).add_child(holder)
	return peer

func dump(label: String, game: Node3D) -> void:
	print(label, " router=", game.get_tree().root.get_node("MenuRouter").current, " state=", game.session.connection_state, " phase=", game.session.match_view.get("phase"), " slots=", game.session.lobby_view.get("slots", []).map(func(s): return [s.get("entity_id"), s.get("ready"), s.get("loadout", {}).is_empty()]), " local=", game.session.local_entity, " menu=", game.menu_host.visible, " hud=", game.combat_hud.visible, " controls=", game.preview.controls_enabled)

func local_ready(session: MvpSession) -> bool:
	for slot: Dictionary in session.lobby_view.get("slots", []):
		if int(slot.get("entity_id", 0)) == session.local_entity:
			return bool(slot.get("ready", false)) and not slot.get("loadout", {}).is_empty()
	return false

func in_full_presentation(game: Node3D) -> bool:
	var session: MvpSession = game.session
	return session.match_view.get("phase") in ["countdown", "active"] and session.local_source() != null \
		and not game.menu_host.visible and game.combat_hud.visible and is_instance_valid(game.impact_feedback) \
		and game.preview.controls_enabled

func run() -> void:
	create_timer(90).timeout.connect(func() -> void:
		push_error("CLI session fixture exceeded wall-clock limit")
		quit(1))
	var router: Node = root.get_node("MenuRouter")
	var base_port := 43000 + OS.get_process_id() % 9000

	# Join: a windowed client given --join=… --ready reaches the lobby, sends its build and readies.
	var server := peer_in("JoinHost")
	var joiner := game_in("Joiner")
	check(not joiner._cli_handoff, "Windowed client keeps the full presentation")
	joiner._start_cli_session([])
	check(joiner.session.connection_state == "offline", "No CLI session arguments leave the menu idle")
	check(server.host(base_port, true, 2) == OK, "Listen server starts")
	joiner._start_cli_session(["--join=127.0.0.1", "--port=%d" % base_port, "--ready"])
	check(router.lobby_intent == "join", "CLI join uses the join lobby")
	check(await until(func() -> bool: return router.current == "lobby" and local_ready(joiner.session)), "CLI join shows the lobby and readies its build")
	dump("join-lobby", joiner)
	server.set_loadout(server.registry.starter(false))
	server.set_ready(true)
	check(await until(func() -> bool: return in_full_presentation(joiner)), "CLI joiner plays with combat HUD and impact feedback")
	dump("join-play", joiner)
	joiner.return_to_main()
	server.leave()
	joiner.get_parent().queue_free()
	server.get_parent().get_parent().queue_free()
	await process_frame
	await process_frame

	# Host: --host --players=2 --ready hosts a duel lobby in the full game.
	var hoster := game_in("Hoster")
	var guest := peer_in("Guest")
	hoster._start_cli_session(["--host", "--port=%d" % (base_port + 1), "--players=2", "--ready"])
	check(hoster.session.connection_state == "hosting", "CLI host listens")
	check(router.lobby_intent == "host" and router.match_setup.mode == "duel", "CLI host opens a duel lobby")
	check(await until(func() -> bool: return router.current == "lobby" and local_ready(hoster.session)), "CLI host shows the lobby and readies its build")
	check(guest.join("127.0.0.1", base_port + 1) == OK, "Guest connects")
	check(await until(func() -> bool: return guest.lobby_view.get("slots", []).size() == 2), "Guest joins the CLI host lobby")
	guest.set_loadout(guest.registry.starter(false))
	guest.set_ready(true)
	check(await until(func() -> bool: return in_full_presentation(hoster)), "CLI host plays with combat HUD and impact feedback")
	dump("host-play", hoster)
	hoster.return_to_main()
	guest.leave()
	await process_frame
	if failures == 0:
		print("CLI SESSION GAME PASS")
	quit(failures)
