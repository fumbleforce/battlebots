extends "res://tests/integration/network_presentation_smoke.gd"

func run() -> void:
	var port := 31000 + OS.get_process_id() % 10000
	var host = make_app("FFAHost")
	host._build_console()
	host.preview.set_physics_process(false)
	host.port = port
	for capacity: int in range(4, 9):
		var index: int = host.player_count_choice.get_item_index(100 + capacity)
		check(index >= 0, "FFA capacity is selectable")
		host.player_count_choice.select(index)
		host.player_count_choice.item_selected.emit(index)
		host.host_game()
		await frames(3)
		check(host.session.lobby_view.mode == "ffa" and host.session.player_capacity == capacity, "Menu opens selected FFA lobby")
		check(host.menu_title.text == "Lobby / FFA" and "at least 4" in host.menu_hint.text, "FFA explains minimum and maximum")
		check("Team" not in host.menu_status.text and "Every bot for itself" in host.menu_status.text, "FFA lobby avoids team labels")
		if capacity < 8:
			host.session.leave()
	var clients: Array[Node] = []
	for index: int in range(3):
		var client = make_app("FFAClient%d" % index)
		clients.append(client)
		check(client.session.join("127.0.0.1", port) == OK, "FFA client connects")
	check(await until(func() -> bool: return host.session.players.size() == 4 and clients.all(func(c: Node) -> bool: return c.session.local_entity > 0)), "Four players admitted")
	host.toggle_ready()
	for client: Node in clients:
		client.session.set_ready(true)
	check(await until(func() -> bool: return host.session.match_view.get("phase") == "active"), "Menu starts four ready players below eight-slot maximum")
	await frames(3)
	check(host.forfeit_button.text == "Forfeit" and host.forfeit_button.visible, "FFA offers individual forfeit")
	check("Team 1" not in host.menu_status.text and "Free-for-all" in host.menu_status.text, "FFA match omits team scores")
	host.forfeit_button.pressed.emit()
	check(await until(func() -> bool: return host.session.local_source().read_view().eliminated), "Forfeit button eliminates local bot")
	check(host.session.spectator_sources().size() == 3, "FFA spectator can choose every survivor")
	await frames(3)
	check(not host.forfeit_button.visible, "Eliminated player cannot forfeit again")
	# Same-tick final eliminations share first; the earlier local forfeit ranks last.
	for client: Node in clients:
		host.session.world.bots[client.session.local_entity].combat.eliminate("fixture")
	check(await until(func() -> bool: return host.session.match_view.get("phase") == "results"), "Single FFA round reaches results")
	await frames(3)
	check("Shared win" in host.menu_status.text and "4. You" in host.menu_status.text, "Menu shows shared win and local placement")
	check(host.rematch_button.visible and not host.forfeit_button.visible, "Results expose rematch without live forfeit")
	for app: Node in apps:
		app.session.leave()
	for view: SubViewport in views:
		view.queue_free()
	await process_frame
	print("FFA MENU PASS" if failures == 0 else "FFA MENU FAIL")
	quit(0 if failures == 0 else 1)
