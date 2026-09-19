extends "res://tests/network/ffa_session.gd"
## Focused real-ENet FFA reservation expiry, results reconnect and roster shrink.
## Only the server's reservation/results deadlines are accelerated.

func make_relay(seed_offset: int) -> Node:
	var node := super.make_relay(seed_offset)
	if node != null:
		node.uplink.duplicate = 0.0
		node.downlink.duplicate = 0.0
	return node

func run() -> void:
	injected_rtt = 0
	jitter = 0
	loss = 0
	expected_players = 5
	if not await begin_fixture(2):
		return
	for index: int in range(5):
		if not await add_ffa_client(index):
			return
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)),
		"Five FFA participants are admitted before readying"):
		return
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await require(await until(active_everywhere), "Five-player FFA starts"):
		return
	var expired_id := clients[4].local_entity
	clients[4].leave()
	if not await require(await until(func() -> bool: return server.players[expired_id].peer == 0), "Server observes fifth player's disconnect"):
		return
	check(not server.world.bots[expired_id].combat.eliminated, "Disconnected FFA bot remains vulnerable during reservation")
	server.players[expired_id].deadline = server._time - 1
	if not await require(await until(func() -> bool:
		return server.world.bots[expired_id].combat.eliminated and server.match_state._elimination_ticks.has(expired_id)), "Expired reservation is eliminated and receives an authoritative tick"):
		return
	var expiry_tick: int = server.match_state._elimination_ticks[expired_id]
	check(server.world.bots[expired_id].combat.elimination_reason == "disconnect", "Expiry records disconnect reason")
	check(server.match_state.phase == "active", "Four connected survivors keep the current FFA running")
	# Keep the departed node in sessions for cleanup, but participant expectations
	# now concern the four connected observers. The match itself retains five ranks.
	clients.pop_back()
	client_relays.pop_back()
	expected_players = 4
	var winner := clients[0].local_entity
	await frames(3)
	for index: int in range(1, 4):
		server.world.bots[clients[index].local_entity].combat.eliminate("disconnect fixture finish")
	if not await require(await until(func() -> bool: return all_connected_results(5)), "Four observers receive results retaining five original participants"):
		return
	for client: MvpSession in clients:
		var places := placement_map(client.match_view.placements)
		check(places.has(expired_id), "Disconnected participant remains in completed match placements")
		if places.has(expired_id):
			check(places[expired_id].place == 5 and places[expired_id].elimination_tick == expiry_tick,
				"Reservation expiry keeps its original tick and last-place rank")
		check(client.match_view.winners == [winner], "Connected survivor wins after expiry and later eliminations")
	var reconnecting := clients[3]
	var reconnect_id := reconnecting.local_entity
	var token := reconnecting.reconnect_token
	var old_body: MvpBot = server.world.bots[reconnect_id]
	var old_results := reconnecting._results.duplicate(true)
	var prior_events: int = results_by_client[3].size()
	reconnecting.leave()
	if not await require(await until(func() -> bool: return server.players[reconnect_id].peer == 0), "Results-phase disconnect reserves participant"):
		return
	client_relays[3].stop()
	var replacement := make_relay(300)
	if not await require(replacement != null, "Results reconnect relay binds"):
		return
	client_relays[3] = replacement
	if not await require(reconnecting.join("127.0.0.1", replacement.bound_port, token) == OK, "Valid token starts results reconnect"):
		return
	if not await require(await until(func() -> bool:
		return (reconnecting.local_entity == reconnect_id and reconnecting.match_view.get("phase") == "results"
			and results_by_client[3].size() == prior_events + 1)), "Results baseline restores participant and emits full results event"):
		return
	check(server.world.bots[reconnect_id] == old_body and old_body.combat.eliminated,
		"Results reconnect preserves the eliminated body rather than reviving it")
	check(reconnecting.reconnect_token != token, "Results reconnect rotates reservation token")
	check(reconnecting._results == old_results and results_by_client[3].back() == old_results,
		"Results reconnect preserves winners, placements and complete participant statistics")
	if not await rematch_case():
		return
	check(server.players.size() == 4 and server.world.bots.size() == 4 and not server.players.has(expired_id),
		"Four connected votes prune the departed fifth player before rematch")
	for client: MvpSession in clients:
		check(not client.world.bots.has(expired_id) and client.match_view.placements.is_empty(),
			"Rematch publishes the reduced roster and clears old ranks")
	var second_match := server.match_state.match_id
	for index: int in range(1, 4):
		server.world.bots[clients[index].local_entity].combat.eliminate("minimum-rematch fixture finish")
	if not await require(await until(func() -> bool: return all_connected_results(4)), "Reduced four-player match finishes normally"):
		return
	var departing_id := clients[3].local_entity
	clients[3].leave()
	if not await require(await until(func() -> bool: return server.players[departing_id].peer == 0), "One results participant leaves three connected"):
		return
	clients.pop_back()
	client_relays.pop_back()
	for client: MvpSession in clients:
		client.vote_rematch()
	if not await require(await until(func() -> bool: return server._rematch.size() == 3), "Every remaining connected participant votes"):
		return
	await frames(10)
	check(server.match_state.phase == "results" and server.match_state.match_id == second_match,
		"Unanimous three-player votes cannot bypass FFA's four-player minimum")
	server.match_state.remaining = 0
	if not await require(await until(func() -> bool:
		return server.match_state.phase == "lobby" and clients.all(func(c: MvpSession) -> bool: return c.match_view.get("phase") == "lobby")), "Results timeout returns insufficient roster to lobby"):
		return
	check(server.players.size() == 3 and server.world.bots.is_empty() and not server.players.has(departing_id),
		"Lobby retains only connected players and clears finished bodies")
	check(server.players.values().all(func(player: Dictionary) -> bool: return not player.ready), "Returned lobby requires fresh ready decisions")
	await finish()

func all_connected_results(participant_count: int) -> bool:
	for client: MvpSession in clients:
		if (client.match_view.get("phase") != "results" or client._results.is_empty()
			or client._results.get("participants", {}).size() != participant_count
			or client.match_view.get("placements", []).size() != participant_count):
			return false
	return true

func finish() -> void:
	await clear_fixture()
	print("FFA DISCONNECT PASS" if failures == 0 else "FFA DISCONNECT FAIL")
	get_tree().quit(0 if failures == 0 else 1)
