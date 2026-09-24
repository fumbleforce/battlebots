extends "res://tests/network/contact_reconciliation.gd"
## Actual ENet 1v1 lobby rules, moved from the retired mvp.tscn console smoke
## test (duel_menu_smoke): capacity is validated, a full duel refuses a third
## player, duellists stay on opposite teams and one ready player cannot start.

func run() -> void:
	server = make_session("Server")
	var port := FreePort.udp()
	check(server.host(port, false, 3) == ERR_INVALID_PARAMETER and server.connection_state == "offline",
		"Unsupported player count is rejected without opening a session")
	check(server.host(port, false, 2) == OK, "Duel server binds")
	for index: int in range(2):
		var client := make_session("Client%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Duellist joins")
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
			return c.local_entity > 0 and c.lobby_view.get("capacity") == 2)):
		check(false, "Both duellists receive the 1v1 lobby")
		await finish()
		return
	var first_team: int = server.players[clients[0].local_entity].team
	clients[1].set_team(first_team)
	await frames(5)
	check(server.players[clients[1].local_entity].team != first_team, "1v1 keeps the duellists on opposite teams")
	var extra := make_session("Extra")
	check(extra.join("127.0.0.1", port) == OK, "Third client attempts to join")
	check(await until(func() -> bool: return extra.connection_state == "offline", 300), "Third player cannot enter a two-player lobby")
	clients[0].set_ready(true)
	await frames(10)
	check(server.match_state.phase == "lobby", "One ready player cannot start a duel")
	clients[1].set_ready(true)
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.match_view.get("phase") == "active")),
		"Both ready duellists start the match")
	check(server.world.bots.size() == 2, "Duel has exactly two bots")
	await finish()

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("DUEL LOBBY RULES PASS" if failures == 0 else "DUEL LOBBY RULES FAIL")
	get_tree().quit(0 if failures == 0 else 1)
