extends SceneTree
const FakeApi := preload("res://tests/fixtures/fake_public_api.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index: int in range(count):
		await process_frame

func until(predicate: Callable, seconds := 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func run() -> void:
	root.size = Vector2i(1280, 720)
	var api := FakeApi.new()
	root.add_child(api)
	var bind_error := api.start()
	check(bind_error == OK, "Online UI HTTP fixture binds: %s (%d)" % [error_string(bind_error), bind_error])
	if bind_error != OK:
		api.queue_free()
		await frames()
		print("ONLINE MENU FAIL")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.name = "DedicatedServer"
	viewport.own_world_3d = true
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var server_root := Node3D.new()
	server_root.name = "MenuGame"
	viewport.add_child(server_root)
	var server := MvpSession.new()
	server.name = "Session"
	server_root.add_child(server)
	var port := 38000 + OS.get_process_id() % 7000
	check(server.host(port, false, 2) == OK, "Independent real ENet server binds")
	api.assignment_port = 0
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	game.public_service.endpoint = api.url()
	var router: Node = root.get_node("MenuRouter")
	var profile: Node = root.get_node("PlayerProfile")
	var original_bot: int = profile.active_bot
	profile.active_bot = 1
	await frames()
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	var online: Button = game.screen.get_node("%PlayOnline")
	for action: Control in online.get_parent().get_children():
		if action.visible:
			check(bounds.encloses(action.get_global_rect()), "Main menu action fits viewport: " + str(action.name))
	var click := InputEventMouseButton.new()
	click.position = online.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	await frames()
	check(router.current == "online" and router.lobby_intent == "online", "Actual main-menu click opens online flow")
	if router.current == "online":
		var screen: Control = game.screen
		for action: Control in [screen.quick_button, screen.create_button, screen.join_button, screen.back_button]:
			action.grab_focus()
			await frames()
			check(bounds.encloses(action.get_global_rect()), "Online action fits viewport: " + action.text)
		check(screen.quick_button.text.contains("1V1") and screen.create_button.text.contains("1V1") and not screen.cancel_button.visible, "Idle screen offers quick and private duels with no Cancel action")
		screen.quick_button.pressed.emit()
		check(await until(func() -> bool: return game.public_service.state == "waiting"), "Quick Play reaches actual HTTP queue")
		check(api.last_payload.get("capacity") == 2 and screen.cancel_button.visible and not screen.copy_button.visible and screen.state_heading.text.contains("FINDING"), "Duel queue shows opponent search and cancellation without a private code")
		api.unauthorized_route = "GET /v1/membership"
		game.public_service._next_poll = 0
		check(await until(func() -> bool: return game.public_service.state == "failed"), "Expired queue session reaches recovery UI")
		check(screen.actions.visible and not screen.quick_button.disabled and not screen.cancel_button.visible and screen.status_label.text.contains("expired"), "Expired queue restores usable actions without mandatory Cancel")
		screen.create_button.pressed.emit()
		check(await until(func() -> bool: return game.public_service.state == "waiting"), "Private duel reaches real HTTP waiting membership")
		check(api.last_payload.get("capacity") == 2, "Private duel requests exactly two players")
		check(screen.cancel_button.visible and screen.region_label.text.contains("test-region") and screen.status_label.text.contains("1 / 2"), "Waiting UI shows region, actual count and Cancel")
		screen.cancel_button.pressed.emit()
		check(await until(func() -> bool: return game.public_service.state == "idle"), "Cancel clears private room without entering gameplay")
		api.assignment_port = port
		screen.create_button.pressed.emit()
		var joined := await until(func() -> bool: return router.current == "lobby" and game.session.connection_state == "connected")
		check(joined, "HTTP assignment enters existing lobby only after actual ENet welcome")
		if joined:
			await frames()
			var lobby: Control = game.screen
			check(game.public_service.state == "connected" and server.players.size() == 1, "Dedicated authority admits the actual online client")
			check(lobby.get_node("%StatusSub").text.contains("ABCD1234") and lobby.get_node("%StatusSub").text.contains("test-region"), "Online lobby preserves shareable friend code and region")
			check(not lobby.host_button.is_visible_in_tree() and not lobby.join_button.is_visible_in_tree() and not lobby.address.is_visible_in_tree(), "Online lobby hides direct-IP hosting/joining controls")
			check(not lobby.team_choice.is_visible_in_tree(), "Online lobby does not offer changes to server-assigned teams")
			check(await until(func() -> bool: return server.players[game.session.local_entity].loadout.parts.weapon == "lifter"), "Selected saved build reaches actual server after welcome")
			game.session.session_event.emit("error", {"operation":"ready", "message":"Fixture request rejected"})
			await frames()
			check(router.current == "lobby" and game.public_service.state == "connected" and lobby.get_node("%StatusSub").text.contains("Fixture request rejected"), "Rejected lobby action stays connected and shows the authority's reason")
			lobby.get_node("%Back").pressed.emit()
			check(await until(func() -> bool: return router.current == "main" and game.public_service.state == "idle"), "Leave returns to main and deletes online membership")
			check(game.session.connection_state == "offline" and api.membership.state == "none", "Online leave releases ENet and HTTP reservation")
	profile.active_bot = original_bot
	game.session.leave()
	server.leave()
	game.queue_free()
	viewport.queue_free()
	api.queue_free()
	await frames()
	print("ONLINE MENU PASS" if failures == 0 else "ONLINE MENU FAIL")
	quit(0 if failures == 0 else 1)
