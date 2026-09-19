extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var registry := ContentRegistry.new()
	var ticket := "a".repeat(64)
	var config := {"schema":1, "allocation_id":"test-allocation", "build":WireCodec.BUILD,
		"protocol":WireCodec.PROTOCOL, "content_hash":registry.content_hash, "port":24567,
		"bind_address":"127.0.0.1", "mode":"teams", "capacity":2, "lease_expires_at":1030,
		"slots":[{"slot":1, "player_id":"player-one", "reservation_id":"a".repeat(32), "ticket_hash":ticket.sha256_text(), "expires_at":1010}]}
	var policy := HostedAdmission.new()
	var decoded: Variant = JSON.parse_string(JSON.stringify(config))
	check(policy.configure(decoded, 1000, registry.content_hash) == OK, "Real JSON numeric types configure allocated duel")
	var identity := policy.admit(ticket, {}, 1000)
	check(identity == {"service_player_id":"player-one", "allocation_slot":1, "reservation_id":"a".repeat(32)}, "Hashed ticket binds canonical identity, reservation and slot")
	check(policy.admit("", {}, 1000).is_empty(), "Missing ticket denied")
	check(policy.admit("b".repeat(64), {}, 1000).is_empty(), "Forged ticket denied")
	check(policy.admit(ticket, {1:identity}, 1000).is_empty(), "Occupied identity cannot replay its ticket")
	check(policy.admit(ticket, {}, 1010).is_empty(), "Expired admission ticket denied at boundary")
	check(policy.retains(identity, 1011), "Existing reconnect identity survives admission-ticket expiry")
	check(not policy.retains(identity, 1030), "Expired allocation lease denies reconnect")
	var rotated := config.duplicate(true)
	rotated.slots[0].ticket_hash = "b".repeat(64).sha256_text()
	check(policy.configure(rotated, 1001, registry.content_hash) == OK and policy.retains(identity, 1001),
		"Ticket rotation preserves the existing reservation's reconnect identity")
	rotated.slots[0].reservation_id = "b".repeat(32)
	check(policy.configure(rotated, 1001, registry.content_hash) == OK and not policy.retains(identity, 1001),
		"Cancel/rejoin generation revokes old identity even when player and slot are unchanged")
	var revoked := config.duplicate(true)
	revoked.slots = []
	check(policy.configure(revoked, 1001, registry.content_hash) == OK and not policy.retains(identity, 1001),
		"Removing current roster membership revokes admitted identity")
	for field: String in ["allocation_id", "build", "content_hash", "mode", "bind_address"]:
		var invalid := config.duplicate(true)
		invalid[field] = "different"
		check(policy.configure(invalid, 1001, registry.content_hash) != OK, "Immutable/wrong allocation field rejected: " + field)
	for mutation: Dictionary in [
		{"schema":2}, {"protocol":3}, {"revoked":true}, {"lease_expires_at":999},
		{"port":1.5}, {"capacity":3}, {"slots":null},
		{"slots":[{"slot":2, "player_id":"x", "ticket_hash":ticket.sha256_text(), "expires_at":1010}]},
		{"slots":[config.slots[0], config.slots[0]]},
	]:
		var invalid := config.duplicate(true)
		invalid.merge(mutation, true)
		check(HostedAdmission.new().configure(invalid, 1000, registry.content_hash) != OK, "Malformed/expired/revoked allocation rejected: " + str(mutation.keys()))
	check(not HostedAdmission.hex_token(12) and not HostedAdmission.hex_token("g".repeat(64)), "Opaque ticket syntax is bounded hexadecimal")
	print("HOSTED ADMISSION PASS" if failures == 0 else "HOSTED ADMISSION FAIL")
	quit(0 if failures == 0 else 1)
