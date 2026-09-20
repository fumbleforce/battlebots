extends SceneTree
## Every mode joins through the same menu with authoritative rules and roster.
var failures := 0
var views: Array[SubViewport] = []
var joined := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
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
	var host_view := viewport("Authority")
	var host_root := Node3D.new()
	host_root.name = "MenuGame"
	var server := MvpSession.new()
	server.name = "Session"
	host_root.add_child(server)
	host_view.add_child(host_root)
	var client_view := viewport("MenuClient")
	var game: Node3D = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	client_view.add_child(game)
	var client: MvpSession = game.session
	client.session_event.connect(func(kind: String, _details: Dictionary) -> void:
		if kind == "joined":
			joined += 1)
	var router: Node = root.get_node("MenuRouter")
	var port := 41000 + OS.get_process_id() % 10000
	for spec: Dictionary in [
		{"count":8, "mode":"ffa", "label":"ffa"},
		{"count":10, "mode":"teams", "label":"5v5"},
		{"count":2, "mode":"teams", "label":"1v1"},
		{"count":4, "mode":"teams", "label":"2v2"},
	]:
		check(server.host(port, false, spec.count, spec.mode) == OK, "%s host starts" % spec.label)
		router.lobby_intent = "join"
		router.goto("lobby", false)
		await ticks(3)
		var lobby: Control = game.screen
		check(lobby.address.is_visible_in_tree() and lobby.join_button.is_visible_in_tree() and not lobby.host_button.is_visible_in_tree(), "Join shows only its connection controls")
		check(not lobby.get_node("Layout/Body/Row/Blue").visible and not lobby.get_node("Layout/Body/Row/Match/Rules").visible, "Unknown join does not invent a roster or arena")
		check(lobby.get_node("%Back").text == "BACK" and not lobby.get_node("%Steps").visible, "Offline join has a plain Back action")
		lobby.address.text = "127.0.0.1"
		lobby.port.value = port
		var previous_joined := joined
		lobby.join_button.pressed.emit()
		check(await until(func() -> bool: return joined > previous_joined), "%s admitted over actual ENet" % spec.label)
		check(await until(func() -> bool: return client.lobby_view.get("mode") == spec.label), "%s authoritative baseline arrives" % spec.label)
		await ticks(5)
		check(client.connection_state == "connected" and router.current == "lobby", "%s remains usable in menu" % spec.label)
		lobby.refresh()
		check(lobby.get_node("%StatusBig").text == "1/%d PLAYERS" % spec.count, "%s displays authoritative capacity" % spec.label)
		check(not lobby.address.is_visible_in_tree() and not lobby.host_button.is_visible_in_tree() and not lobby.join_button.is_visible_in_tree() and not lobby.port.is_visible_in_tree(), "Connected lobby hides connection controls")
		check(lobby.team_choice.visible == (spec.mode != "ffa"), "%s team picker matches mode" % spec.label)
		var visible_cards := 0
		var local_cards := 0
		for cards: Array in lobby._roster_cards:
			for card: Control in cards:
				visible_cards += int(card.visible)
				local_cards += int(card.visible and "(YOU)" in card.get_node("%Name").text)
		check(visible_cards == spec.count and local_cards == 1, "%s has every slot and exactly one local player" % spec.label)
		check(lobby.get_node("%Back").text == "LEAVE GAME", "Connected lobby has Leave Game action")
		if spec.mode == "ffa":
			check(lobby.get_node("Layout/Body/Row/Blue/TeamHeader/Row/Team").text.begins_with("PLAYERS"), "FFA roster has neutral player labels")
			check(lobby.get_node("Layout/Body/Row/Match/Rules/Clock/Col/Value").text == "5:00", "FFA shows its actual round duration")
		check(server.connection_state == "hosting" and server.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "%s guard leaves authority running" % spec.label)
		lobby.leave_lobby()
		check(client.connection_state == "offline" and router.current == "main", "Leave returns directly to main")
		server.leave()
		await ticks(3)
		port += 1
	game.preview.release_controls(false)
	for index: int in range(views.size() - 1, -1, -1):
		var view := views[index]
		set_multiplayer(null, view.get_path())
		view.queue_free()
	await ticks(3)
	print("MENU MODE GUARD PASS" if failures == 0 else "MENU MODE GUARD FAIL")
	quit(0 if failures == 0 else 1)
