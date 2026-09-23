extends "res://tests/network/contact_reconciliation.gd"
## Actual ENet: authoritative pickups replicate item state, live part swaps and
## match credits to both clients, survive reconnect, and pay into results.
var collected: Array[Dictionary] = []
var results: Array[Dictionary] = []

func require(ok: bool, message: String) -> bool:
	check(ok, message)
	if not ok: await finish()
	return ok

func take(item_index: int, kind: String, part: String, entity: int, amount := 0) -> void:
	var item: Dictionary = server.world.pickups.items[item_index]
	item.kind = kind
	item.part = part
	item.amount = amount
	item.available = true
	var bot: MvpBot = server.world.bots[entity]
	bot.body.reset_pose = server.world.clear_spawn_pose(bot, Transform3D(Basis.IDENTITY, item.point))

func run() -> void:
	server = make_session("Server")
	var port := 38000 + OS.get_process_id() % 10000
	if not await require(server.host(port, false, 2) == OK, "Pickup server binds"):
		return
	for index: int in range(2):
		var client := make_session("Client%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Pickup client joins")
	if not await require(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)),
		"Two pickup clients admitted"):
		return
	var picker := clients[0]
	var watcher := clients[1]
	var id := picker.local_entity
	picker.pickup_collected.connect(func(event: Dictionary) -> void: collected.append(event))
	picker.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "results": results.append(details))
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await require(await until(func() -> bool:
		return server.match_state.phase == "active" and clients.all(func(c: MvpSession) -> bool: return c.match_view.get("phase") == "active")),
		"Pickup duel reaches active"):
		return
	if not await require(await until(func() -> bool:
		return clients.all(func(c: MvpSession) -> bool: return c.pickup_view.get("items", []).size() == 5)),
		"Clients receive stocked pickup points with the match baseline"):
		return
	check(picker.pickup_view.match_id == server.match_state.match_id, "Pickup state is bound to the running match")

	take(0, "part", "hammer", id)
	if not await require(await until(func() -> bool:
		return clients.all(func(c: MvpSession) -> bool: return c.world.bots[id].loadout.parts.weapon == "hammer")),
		"Both clients rebuild the picker with the picked weapon"):
		return
	check(server.world.bots[id].combat.stats.weapon == "hammer", "Authority installs the picked weapon")
	check(not picker.pickup_view.items[0].available and not watcher.pickup_view.items[0].available,
		"Clients see the collected item leave the world")
	check(collected.size() == 1 and collected[0].kind == "part" and collected[0].part == "hammer"
		and collected[0].entity == id and not collected[0].has("loadout"), "Picker receives one public pickup event")

	take(1, "credits", "", id, 50)
	if not await require(await until(func() -> bool:
		return int(picker.pickup_view.get("credits", {}).get(id, 0)) == 50 and int(watcher.pickup_view.get("credits", {}).get(id, 0)) == 50),
		"Match credits replicate to both clients"):
		return

	take(0, "part", "atlas_mx", id)
	if not await require(await until(func() -> bool:
		return clients.all(func(c: MvpSession) -> bool: return c.world.bots[id].loadout.parts.chassis == "atlas_mx")),
		"Body pickup rebuilds the picker on every client"):
		return
	check(picker.world.bots[id].loadout.parts.drive == "traction" and picker.world.bots[id].loadout.parts.weapon == "hammer",
		"Body pickup keeps earlier picks and brings its drive")
	check(picker.world.bots.size() == 2 and watcher.world.bots.size() == 2, "Swaps keep one bot per entity")
	await frames(30)
	check(picker.local_source() == picker.world.bots[id] and picker.world.bots[id].remote_state.get("epoch", "") != "",
		"Local source follows the rebuilt bot and keeps receiving snapshots")

	var token := picker.reconnect_token
	picker.leave()
	if not await require(await until(func() -> bool: return server.players[id].peer == 0), "Authority observes picker disconnect"):
		return
	check(picker.join("127.0.0.1", port, token) == OK, "Picker reconnect begins")
	if not await require(await until(func() -> bool:
		return picker.local_entity == id and picker.world.bots.has(id) and picker.world.bots[id].loadout.parts.chassis == "atlas_mx"),
		"Reconnect baseline restores the match loadout"):
		return
	check(int(picker.pickup_view.get("credits", {}).get(id, 0)) == 50, "Reconnect baseline restores match credits")

	var winner_team: int = server.players[id].team
	var rival := watcher.local_entity
	server.match_state.scores[winner_team] = 1
	server.world.bots[rival].combat.eliminate("core")
	if not await require(await until(func() -> bool: return results.size() >= 1), "Picker receives match results"):
		return
	var credits: Dictionary = results.back().participants[id].credits
	var rival_credits: Dictionary = results.back().participants[rival].credits
	check(credits.pickups == 50 and credits.performance >= MatchPickups.REWARD_PARTICIPATION + MatchPickups.REWARD_VICTORY
		and credits.total == credits.pickups + credits.performance, "Winner's reward adds pickups to performance")
	check(rival_credits.pickups == 0 and rival_credits.performance < credits.performance, "Loser earns participation without the victory bonus")
	await finish()

func finish() -> void:
	for session: MvpSession in sessions: session.leave()
	await get_tree().physics_frame
	for child: Node in get_children():
		if child is SubViewport: get_tree().set_multiplayer(null, child.get_path())
		child.queue_free()
	await get_tree().process_frame
	print("PICKUP SESSION PASS" if failures == 0 else "PICKUP SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
