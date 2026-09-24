extends "res://tests/network/contact_reconciliation.gd"
## Actual ENet: Scorpion commands, natural-height gun hits, snapshots and reconnect.
## Optional 80 ms profile impairs input/snapshots; reliable transport stays genuine.
var gun_held := false
var press_next := false
var controls_enabled := true
var send_commands := true
var input_gate := GameplayInputGate.new()
var authority_effects: Array[Dictionary] = []
var received_effects: Array[Dictionary] = []
var saw_active := false
var saw_spool := false
var observed_sequence := 0
var pitch_history: Dictionary = {}

func frame() -> void:
	if is_instance_valid(server) and server.local_entity > 0:
		var idle := BotCommand.new()
		idle.brake = true
		server.submit_local(idle)
	for client: MvpSession in clients:
		if send_commands:
			var strengths := {&"secondary": 1.0 if gun_held else 0.0, &"primary": 1.0 if press_next else 0.0}
			var command := input_gate.sample(strengths, {&"primary": press_next}, controls_enabled)
			command.brake = true
			client.submit_local(command)
	press_next = false
	await get_tree().physics_frame
	await get_tree().process_frame
	if is_instance_valid(server) and server.world != null:
		for client: MvpSession in clients:
			if server.world.bots.has(client.local_entity):
				pitch_history[server.world.tick] = server.world.bots[client.local_entity].combat.gun_pitch
	for client: MvpSession in clients:
		if client.world != null and client.world.bots.has(client.local_entity):
			var view: BotView = client.world.bots[client.local_entity].read_view()
			saw_active = saw_active or view.secondary_active
			saw_spool = saw_spool or (view.secondary_charge > 0.0 and view.secondary_charge < 0.99)
			observed_sequence = maxi(observed_sequence, view.shot_sequence)

func require(ok: bool, message: String) -> bool:
	check(ok, message)
	if not ok: await finish()
	return ok

func run() -> void:
	input_gate.auxiliary_weapon = true
	input_gate.toggle_primary = true
	input_gate.sample({}, {}, true)
	server = make_session("ScorpionHost")
	var port := FreePort.udp()
	if not await require(server.host(port, true, 2) == OK, "Scorpion listen host binds"):
		return
	var client := make_session("ScorpionClient")
	clients.append(client)
	server.combat_event.connect(func(event: Dictionary) -> void: authority_effects.append(event.duplicate(true)))
	client.combat_event.connect(func(event: Dictionary) -> void: received_effects.append(event.duplicate(true)))
	if not await require(client.join("127.0.0.1", port) == OK, "Scorpion client starts real ENet join"):
		return
	if not await require(await until(func() -> bool: return client.local_entity > 0, 600), "Scorpion client admitted"):
		return
	var attacker_id := client.local_entity
	var victim_id := server.local_entity
	client.set_loadout(client.registry.scorpion())
	if not await require(await until(func() -> bool:
		return server.players[attacker_id].loadout.parts.chassis == "scorpion_hex", 300),
		"Reliable loadout request installs canonical Scorpion and auxiliary gun"):
		return
	client.set_ready(true)
	server.set_ready(true)
	if not await require(await until(func() -> bool:
		return server.match_state.phase == "active" and client.match_view.get("phase") == "active", 900),
		"Scorpion duel reaches active"):
		return
	for session: MvpSession in sessions:
		if profile == "80":
			session.network_simulation.delay_ms = 40
			session.network_simulation.jitter_ms = 10
			session.network_simulation.loss = 0.01
			session.network_simulation.duplicate = 0.02
	var attacker: MvpBot = server.world.bots[attacker_id]
	var victim: MvpBot = server.world.bots[victim_id]
	attacker.body.reset_pose = server.world.clear_spawn_pose(attacker, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	victim.body.reset_pose = server.world.clear_spawn_pose(victim, Transform3D(Basis.IDENTITY, Vector3(0, 0, -7.8)))
	await frames(90)
	if not await require(client.world.bots[attacker_id].remote_state.has("shot_sequence"),
		"Extended snapshot passes session envelope validation and populates remote state"):
		return
	check(attacker.body.global_position.y > 2.0 and victim.body.global_position.y < 1.2,
		"Real network arena settles tall walker opposite low wheeled hull")
	check(client.world.bots[attacker_id].read_view().has_auxiliary_weapon,
		"Remote BotView retains auxiliary capability from admitted loadout")
	gun_held = true
	if not await require(await until(func() -> bool: return attacker.combat.shot_sequence >= 6, 180),
		"Actual remote RMB passes gate, codec and server to fire six rounds"):
		return
	check(victim.combat.core < victim.combat.stats.core and authority_effects.size() >= 5,
		"Real settled-height minigun damages the intended opponent")
	press_next = true
	if not await require(await until(func() -> bool: return attacker.combat.attack_id == 1, 120),
		"LMB in toggle mode starts hammer while RMB remains held"):
		return
	if not await require(await until(func() -> bool:
		return authority_effects.any(func(event: Dictionary) -> bool: return event.kind == "hammer"), 120),
		"Authoritative tail strike reaches low bot while auxiliary is firing"):
		return
	if not await require(await until(func() -> bool: return attacker.combat.shot_sequence >= 12, 120),
		"Auxiliary continues firing through the committed hammer strike"):
		return
	gun_held = false
	if not await require(await until(func() -> bool: return not attacker.command.auxiliary_held, 120),
		"Remote release clears explicit auxiliary intent"):
		return
	await frames(60)
	check(saw_active and saw_spool and observed_sequence > 0,
		"Snapshots expose spool, active gun and nonzero shot sequence through BotView")
	var shots := attacker.combat.shot_sequence
	var health := victim.combat.core
	check(await until(func() -> bool:
		var remote: Dictionary = client.world.bots[attacker_id].remote_state
		return remote.shot_sequence == shots and remote.last_shot_tick == attacker.combat.last_shot_tick \
			and is_equal_approx(client.world.bots[victim_id].remote_state.core, health), 180),
		"Observer converges to exact gun sequence, last shot tick and victim health")
	var view: BotView = client.world.bots[attacker_id].read_view()
	check(view.last_shot_from.is_equal_approx(attacker.combat.last_shot_from)
		and view.last_shot_to.is_equal_approx(attacker.combat.last_shot_to),
		"Remote tracer endpoints equal actual authoritative ray results")
	check(view.gun_pitch < -0.1 and pitch_history.has(view.server_tick)
		and is_equal_approx(view.gun_pitch, float(pitch_history.get(view.server_tick, 100.0))),
		"Accepted snapshots animate the same bounded downward servo pitch as authority")
	var gun_events := authority_effects.filter(func(event: Dictionary) -> bool: return event.kind == "minigun")
	for index: int in range(1, gun_events.size()):
		check(gun_events[index].tick - gun_events[index - 1].tick >= 5,
			"Real server shots never exceed twelve rounds per second")
	var unique_events: Dictionary = {}
	for event: Dictionary in received_effects:
		check(not unique_events.has(event.event_id), "Each accepted impact event is emitted once")
		unique_events[event.event_id] = true
		check(authority_effects.any(func(source: Dictionary) -> bool:
			return event.event_id == source.event_id and event.kind == source.kind and event.attack_id == source.attack_id),
			"Received impact identity and kind match an authoritative hit")
	# Point away: misses still need replicated muzzle/tracer animation.
	victim.body.reset_pose = server.world.clear_spawn_pose(victim, Transform3D(Basis.IDENTITY, Vector3(-14, 0, 0)))
	await frames(45)
	var effects_before := authority_effects.size()
	gun_held = true
	if not await require(await until(func() -> bool: return attacker.combat.shot_sequence >= shots + 3, 180),
		"Remote gun still fires in empty space"):
		return
	controls_enabled = false
	if not await require(await until(func() -> bool: return not attacker.command.auxiliary_held, 120),
		"Menu suppression sends safe cancellation across ENet"):
		return
	shots = attacker.combat.shot_sequence
	controls_enabled = true
	await frames(60)
	check(attacker.combat.shot_sequence == shots and authority_effects.size() == effects_before,
		"Held RMB after menu resume cannot rearm or invent hit events")
	check(await until(func() -> bool:
		return client.world.bots[attacker_id].remote_state.shot_sequence == shots, 120),
		"Miss shot sequence still reaches observer")
	gun_held = false
	await frames(5)
	gun_held = true
	if not await require(await until(func() -> bool: return attacker.combat.shot_sequence >= shots + 3, 180),
		"Release and fresh RMB rearms after menu suppression"):
		return
	send_commands = false
	await frames(60)
	shots = attacker.combat.shot_sequence
	check(attacker.input_age >= 0.25 and not attacker.command.auxiliary_held,
		"Missing remote input times out the gun after queued packets drain")
	await frames(45)
	check(attacker.combat.shot_sequence == shots, "Timed-out remote gun cannot continue shooting")
	gun_held = false
	send_commands = true
	await frames(30)
	var retained_tick := attacker.combat.last_shot_tick
	var retained_to := attacker.combat.last_shot_to
	var token := client.reconnect_token
	client.leave()
	if not await require(await until(func() -> bool: return server.players[attacker_id].peer == 0, 600),
		"Disconnect reserves original Scorpion entity"):
		return
	if not await require(client.join("127.0.0.1", port, token) == OK, "Scorpion reconnect begins"):
		return
	if not await require(await until(func() -> bool:
		return client.local_entity == attacker_id and client.world != null and client.world.bots.has(victim_id), 600),
		"Reconnect receives complete gun baseline"):
		return
	view = client.world.bots[attacker_id].read_view()
	check(server.world.bots[attacker_id] == attacker and view.shot_sequence == shots
		and view.last_shot_tick == retained_tick and view.last_shot_to.is_equal_approx(retained_to),
		"Reconnect retains entity and gun history without replaying an attack")
	check(not view.secondary_active and view.has_auxiliary_weapon
		and is_equal_approx(client.world.bots[victim_id].remote_state.core, health),
		"Reconnect restores stopped gun, installed capability and prior real damage")
	server.vote_forfeit()
	if not await require(await until(func() -> bool: return client.match_view.get("phase") == "intermission", 300),
		"Forfeit ends the fixture round"):
		return
	server.match_state.remaining = 0.0
	if not await require(await until(func() -> bool:
		return client.match_view.get("round") == 2 and client.match_view.get("phase") == "countdown", 300),
		"Fixture advances to a reset round"):
		return
	check(await until(func() -> bool:
		var reset: BotView = client.world.bots[attacker_id].read_view()
		return reset.shot_sequence == 0 and reset.last_shot_tick == -1 and reset.secondary_charge == 0.0 \
			and not reset.secondary_active and reset.has_auxiliary_weapon, 180),
		"Round reset clears gun history/spool while retaining installed modules")
	print("Scorpion profile %s: real_hits=%d shot_sequence=%d effects=%d grounded_y=%.2f/%.2f" %
		[profile, gun_events.size(), shots, received_effects.size(), attacker.body.global_position.y, victim.body.global_position.y])
	await finish()

func finish() -> void:
	for session: MvpSession in sessions: session.leave()
	await get_tree().physics_frame
	for child: Node in get_children():
		if child is SubViewport: get_tree().set_multiplayer(null, child.get_path())
		child.queue_free()
	await get_tree().process_frame
	print("SCORPION SESSION PASS" if failures == 0 else "SCORPION SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
