extends "res://tests/network/contact_reconciliation.gd"
var policy: HostedAdmission
var allocation: Dictionary
var ticket_a := "a".repeat(64)
var ticket_b := "b".repeat(64)
var port := 0

func rejected(ticket: String, label: String) -> void:
	var probe := make_session("Rejected%d" % sessions.size())
	var errors: Array[String] = []
	probe.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "error": errors.append(str(details.get("message", ""))))
	check(probe.join("127.0.0.1", port, "", ticket) == OK, label + " connects to admission gate")
	check(await until(func() -> bool: return probe.connection_state == "offline", 300), label + " is rejected over ENet")
	check(not errors.is_empty() and probe.local_entity == 0, label + " never receives an entity")

func run() -> void:
	server = make_session("HostedServer")
	port = 45000 + OS.get_process_id() % 7000
	var now := Time.get_unix_time_from_system()
	allocation = {"schema":1, "allocation_id":"network-fixture", "build":WireCodec.BUILD,
		"protocol":WireCodec.PROTOCOL, "content_hash":server.registry.content_hash,
		"port":port, "bind_address":"127.0.0.1", "mode":"teams", "capacity":2, "lease_expires_at":now + 120,
		"slots":[{"slot":1, "player_id":"alpha", "reservation_id":"a".repeat(32), "ticket_hash":ticket_a.sha256_text(), "expires_at":now + 30},
			{"slot":0, "player_id":"beta", "reservation_id":"b".repeat(32), "ticket_hash":ticket_b.sha256_text(), "expires_at":now - 1}]}
	policy = HostedAdmission.new()
	check(policy.configure(allocation, now, server.registry.content_hash) == OK, "Hosted policy configures")
	server.hosted_admission = policy
	check(server.host(port, false, 2, "teams", "127.0.0.1") == OK, "Hosted loopback bind succeeds")
	await rejected("", "Missing ticket")
	await rejected("c".repeat(64), "Forged ticket")
	await rejected(ticket_b, "Expired ticket")
	var a := make_session("Alpha")
	clients.append(a)
	check(a.join("127.0.0.1", port, "", ticket_a) == OK, "Valid assigned ticket connects")
	check(await until(func() -> bool: return a.local_entity > 0, 300), "Valid ticket admits a player")
	if a.local_entity == 0:
		await finish()
		return
	var id := a.local_entity
	check(server.players[id].service_player_id == "alpha" and server.players[id].allocation_slot == 1
		and server.players[id].team == 1, "Admission binds identity, allocation slot and fixed team")
	await rejected(ticket_a, "Occupied ticket replay")
	var team_errors: Array = []
	a.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "error": team_errors.append(details))
	a.set_team(0)
	check(await until(func() -> bool: return not team_errors.is_empty(), 300), "Allocated team change receives explicit rejection")
	check(server.players[id].team == 1, "Team remains allocated")
	allocation.slots[1].expires_at = now + 60
	check(policy.configure(allocation, Time.get_unix_time_from_system(), server.registry.content_hash) == OK, "Updated roster refreshes ticket expiry")
	var b := make_session("Beta")
	clients.append(b)
	check(b.join("127.0.0.1", port, "", ticket_b) == OK, "Second allocated player connects")
	check(await until(func() -> bool: return b.local_entity > 0, 300), "Second assigned identity admitted")
	for client: MvpSession in clients: client.set_ready(true)
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "active"), 600), "Allocated players complete normal loading/countdown")
	var body: MvpBot = server.world.bots[id]
	body.combat.damage("top", 30)
	var retained_core := body.combat.core
	var token := a.reconnect_token
	a.leave()
	check(await until(func() -> bool: return server.players[id].peer == 0, 300), "Disconnect reserves allocated participant")
	allocation.slots[0].expires_at = Time.get_unix_time_from_system() - 1
	check(policy.configure(allocation, Time.get_unix_time_from_system(), server.registry.content_hash) == OK, "Admission token expires without revoking retained identity")
	check(a.join("127.0.0.1", port, token) == OK, "Reconnect needs no fresh admission ticket")
	check(await until(func() -> bool: return a.local_entity == id and a.world.bots.has(id), 300), "Reconnect restores original entity")
	check(server.world.bots[id] == body and body.combat.core == retained_core and a.reconnect_token != token,
		"Reconnect preserves body/damage and rotates private reconnect token")
	allocation.slots[0].reservation_id = "d".repeat(32)
	allocation.slots[0].ticket_hash = "d".repeat(64).sha256_text()
	allocation.slots[0].expires_at = Time.get_unix_time_from_system() + 60
	check(policy.configure(allocation, Time.get_unix_time_from_system(), server.registry.content_hash) == OK, "Cancel/rejoin reservation generation accepted")
	server.refresh_hosted_admission()
	check(await until(func() -> bool: return a.connection_state == "offline", 300), "Replaced reservation disconnects its old player")
	check(body.combat.eliminated, "Revoked active identity cannot keep playing")
	check(a.join("127.0.0.1", port, a.reconnect_token) == OK, "Revoked reservation attempts its retained reconnect token")
	check(await until(func() -> bool: return a.connection_state == "offline", 300) and a.local_entity == 0,
		"A valid-looking reconnect token cannot reclaim a revoked reservation generation")
	await rejected(ticket_a, "Revoked ticket")
	# A fresh unallocated server preserves the ordinary LAN connection contract.
	for client: MvpSession in clients: client.leave()
	server.leave()
	check(server.host(port, false, 2) == OK, "Same session may host ordinary LAN after allocated leave")
	check(a.join("127.0.0.1", port) == OK, "LAN join requires no ticket")
	check(await until(func() -> bool: return a.local_entity > 0, 300), "Unticketed LAN admission remains available")
	await finish()

func finish() -> void:
	for session: MvpSession in sessions: session.leave()
	for child: Node in get_children(): child.queue_free()
	await get_tree().process_frame
	print("HOSTED ADMISSION SESSION PASS" if failures == 0 else "HOSTED ADMISSION SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
