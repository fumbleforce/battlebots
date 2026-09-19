extends "res://tests/integration/network_presentation_smoke.gd"

func run() -> void:
	var port := 29000 + OS.get_process_id() % 10000
	var host = make_app("Host")
	host._build_console()
	host.preview.set_physics_process(false)
	host.port = port
	check(host.player_count == 2 and host.player_count_choice.get_selected_id() == 2, "Two-player default is selected")
	check(host.host_setup.visible and host.join_setup.visible, "Offline menu offers host and join")
	check(not host.leave_button.visible and not host.forfeit_button.visible and not host.ready_button.visible and not host.rematch_button.visible, "Offline menu hides all session-only actions")
	check(host.session.host(port, true, 3) == ERR_INVALID_PARAMETER, "Unsupported count is rejected without opening a session")
	host.host_game()
	await frames(3)
	check(host.session.player_capacity == 2 and host.session.lobby_view.capacity == 2, "Host uses selected capacity")
	check(host.ready_button.visible and host.leave_button.visible and not host.host_setup.visible and not host.join_setup.visible, "Lobby offers ready/close, not host/join")
	check(not host.forfeit_button.visible and not host.rematch_button.visible, "Lobby hides match-only actions")
	host.toggle_ready()
	await frames(3)
	check(host.local_ready() and host.ready_button.text == "Not ready", "Ready state comes from server and can be undone")
	host.toggle_ready()
	await frames(3)
	check(not host.local_ready(), "Ready toggle unsets readiness")
	var client = make_app("Client")
	client._build_console()
	client.preview.set_physics_process(false)
	client.port = port
	client.address.text = "127.0.0.1"
	client.select_build(true)
	client.join_game()
	client._process(0)
	check(client.leave_button.visible and client.leave_button.text == "Cancel connection", "Connecting offers cancel")
	check(not client.ready_button.visible and not client.forfeit_button.visible, "Connecting hides ready/forfeit")
	check(await until(func() -> bool: return client.session.local_entity > 0 and client.session.lobby_view.get("capacity") == 2), "Client receives chosen 1v1 lobby")
	check(await until(func() -> bool: return host.session.players[client.session.local_entity].loadout.parts.weapon == "lifter"), "Selected build survives joining")
	client.session.set_team(0)
	await frames(5)
	check(host.session.players[client.session.local_entity].team == 1, "1v1 disallows two players on the same team")
	var extra = make_app("Extra")
	extra.session.join("127.0.0.1", port)
	check(await until(func() -> bool: return extra.session.connection_state == "offline", 300), "Third player cannot enter a two-player lobby")
	host.toggle_ready()
	await frames(10)
	check(host.session.match_state.phase == "lobby", "One ready player cannot start a duel")
	client.toggle_ready()
	check(await until(func() -> bool: return client.session.match_view.get("phase") == "active"), "One window per player starts 1v1")
	check(host.session.world.bots.size() == 2 and client.session.world.bots.size() == 2, "Duel has exactly two bots")
	await frames(3)
	check(host.forfeit_button.visible and host.leave_button.visible and not host.ready_button.visible and not host.build_row.visible and not host.rematch_button.visible, "Active match offers forfeit/leave and locks loadout")
	for round_number: int in range(2):
		host.session.vote_forfeit()
		check(await until(func() -> bool: return host.session.match_state.phase in ["intermission", "results"], 120), "Single-player team can forfeit a round")
		if round_number == 0:
			host.session.match_state.remaining = 0
			check(await until(func() -> bool: return host.session.match_state.phase == "active", 600), "Duel starts its second round")
	check(await until(func() -> bool: return client.session.match_view.get("phase") == "results", 300), "Duel results reach client")
	await frames(3)
	check(host.rematch_button.visible and host.leave_button.visible and not host.forfeit_button.visible and not host.resume_button.visible, "Results offer rematch/leave only")
	var old_match: String = host.session.match_state.match_id
	host.session.vote_rematch()
	await frames(5)
	check(host.session.match_state.match_id == old_match, "Rematch waits for both players")
	client.session.vote_rematch()
	check(await until(func() -> bool: return host.session.match_state.match_id != old_match and client.session.match_view.get("phase") == "active", 900), "Both votes restart a two-player match")
	client.session.leave()
	await frames(3)
	check(client.host_setup.visible and not client.leave_button.visible and not client.forfeit_button.visible, "Leaving restores setup without stale match buttons")
	for app: Node in apps:
		app.session.leave()
	for view: SubViewport in views:
		view.queue_free()
	await process_frame
	print("DUEL MENU PASS" if failures == 0 else "DUEL MENU FAIL")
	quit(0 if failures == 0 else 1)
