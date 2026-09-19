extends SceneTree
## Real ENet admission must not put an unsupported match in the four-card menu.
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
		{"count":8, "mode":"ffa", "label":"ffa", "reject":true},
		{"count":10, "mode":"teams", "label":"5v5", "reject":true},
		{"count":2, "mode":"teams", "label":"1v1", "reject":false},
		{"count":4, "mode":"teams", "label":"2v2", "reject":false},
	]:
		check(server.host(port, false, spec.count, spec.mode) == OK, "%s host starts" % spec.label)
		router.goto("lobby", false)
		await ticks(3)
		var lobby: Control = game.screen
		lobby.address.text = "127.0.0.1"
		lobby.port.value = port
		var previous_joined := joined
		lobby.join_button.pressed.emit()
		check(await until(func() -> bool: return joined > previous_joined), "%s admitted over actual ENet" % spec.label)
		if spec.reject:
			check(await until(func() -> bool: return client.connection_state == "offline"), "%s client leaves unsupported mode" % spec.label)
			await ticks(3)
			check(client.world == null and client.local_entity == 0, "%s clears local session" % spec.label)
			check(router.current == "mode_select", "%s returns to mode selection" % spec.label)
			check("5V5 / FFA PLAYTEST" in router.session_notice and spec.label.to_upper() in router.session_notice, "%s has explanatory route notice" % spec.label)
			var visible_notice := false
			for child: Node in game.get_children():
				if child is AcceptDialog:
					visible_notice = visible_notice or (child.visible and "5V5 / FFA PLAYTEST" in child.dialog_text)
					child.queue_free()
			check(visible_notice, "%s notice is visible" % spec.label)
		else:
			check(await until(func() -> bool: return client.lobby_view.get("mode") == spec.label), "%s authoritative baseline arrives" % spec.label)
			await ticks(5)
			check(client.connection_state == "connected" and router.current == "lobby", "%s remains usable in menu" % spec.label)
		check(server.connection_state == "hosting" and server.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "%s guard leaves authority running" % spec.label)
		client.leave()
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
