extends "res://tests/network/contact_reconciliation.gd"
## Actual ENet plus optional input/snapshot simulation, not whole-UDP impairment.
var spinning := false
var received_effects: Array[Dictionary] = []
var authority_effects: Array[Dictionary] = []

func frame() -> void:
	if is_instance_valid(server) and server.local_entity > 0:
		server.submit_local(BotCommand.new())
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.primary_held = spinning
		client.submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame

func require(ok: bool, message: String) -> bool:
	check(ok, message)
	if not ok:
		await finish()
	return ok

func run() -> void:
	server = make_session("HorizontalHost")
	var port := 35000 + OS.get_process_id() % 10000
	if not await require(server.host(port, true, 2) == OK, "Horizontal listen host binds"):
		return
	var draft := server.registry.starter()
	draft.name = "Horizontal Striker"
	draft.parts.weapon = "horizontal_spinner"
	if not await require(server.registry.validate(draft).valid, "Canonical horizontal spinner build is legal"):
		return
	server.set_loadout(draft)
	var client := make_session("HorizontalClient")
	clients.append(client)
	client.combat_event.connect(func(event: Dictionary) -> void: received_effects.append(event.duplicate(true)))
	server.combat_event.connect(func(event: Dictionary) -> void: authority_effects.append(event.duplicate(true)))
	if not await require(client.join("127.0.0.1", port) == OK, "Horizontal client starts ENet join"):
		return
	if not await require(await until(func() -> bool: return client.local_entity > 0, 600), "Horizontal client admitted"):
		return
	client.set_loadout(draft)
	var attacker_id := client.local_entity
	var victim_id := server.local_entity
	if not await require(await until(func() -> bool:
		return server.players[attacker_id].loadout.parts.weapon == "horizontal_spinner" \
			and client.lobby_view.get("slots", []).all(func(slot: Dictionary) -> bool:
				return slot.loadout.parts.weapon == "horizontal_spinner"), 600), "Host and remote horizontal loadouts are authoritative"):
		return
	server.set_ready(true)
	client.set_ready(true)
	if not await require(await until(func() -> bool:
		return client.match_view.get("phase") == "active" and server.match_state.phase == "active", 900), "Horizontal duel reaches active"):
		return
	for session: MvpSession in sessions:
		if profile == "80":
			session.network_simulation.delay_ms = 40
			session.network_simulation.jitter_ms = 10
			session.network_simulation.loss = 0.01
			session.network_simulation.duplicate = 0.02
		elif profile == "150":
			session.network_simulation.delay_ms = 75
			session.network_simulation.jitter_ms = 20
			session.network_simulation.loss = 0.03
			session.network_simulation.duplicate = 0.03
	var attacker: MvpBot = server.world.bots[attacker_id]
	var victim: MvpBot = server.world.bots[victim_id]
	attacker.body.reset_pose = server.world.clear_spawn_pose(attacker, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	victim.body.reset_pose = server.world.clear_spawn_pose(victim, Transform3D(Basis.IDENTITY, Vector3(8, 0, 0)))
	await frames(30)
	spinning = true
	if not await require(await until(func() -> bool:
		return attacker.combat.charge >= 0.95 and client.world.bots[attacker_id].remote_state.charge >= 0.85, 240),
		"Real remote held input charges horizontal weapon and replicates charge"):
		return
	check(client.world.bots[attacker_id].remote_state.weapon == "horizontal_spinner"
		and client.world.bots[attacker_id].remote_state.weapon_state == "active", "Baseline and snapshots retain horizontal weapon identity and phase")
	# This side contact is outside the narrow vertical-spinner box. Hulls remain
	# separated, so the only source of damage is the charged horizontal disc.
	var contact_offset := Vector3(1.7, 0, -1.2) * BotScale.FACTOR
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, attacker.body.global_position + contact_offset)
	var before := victim.combat.core
	if not await require(await until(func() -> bool: return victim.combat.core < before, 60), "Horizontal disc produces authoritative lateral hit"):
		return
	spinning = false
	var authority_hit: Dictionary = authority_effects.back()
	check(authority_hit.attacker == attacker_id and authority_hit.target == victim_id and authority_hit.damage > 0,
		"Authority effect identifies horizontal attacker and damaged victim")
	check(attacker.combat.charge < 0.6, "Disc hit consumes accumulated charge")
	var direction := contact_offset.normalized()
	var victim_motion := false
	var attacker_recoil := false
	var remote_motion := false
	var remote_recoil := false
	var predicted: MvpBot = client.world.bots[attacker_id]
	var ticks: Array[int] = []
	var last_bad := -1
	var last_hit_tick: int = authority_hit.tick
	var event_cursor := authority_effects.size()
	var start_physics_tick := Engine.get_physics_frames()
	var peak_position := 0.0
	var peak_angle := 0.0
	while Engine.get_physics_frames() - start_physics_tick < 120:
		await frame()
		ticks.append(server.world.tick)
		for event: Dictionary in authority_effects.slice(event_cursor):
			if event.attacker == attacker_id and event.target == victim_id:
				last_hit_tick = maxi(last_hit_tick, int(event.tick))
		event_cursor = authority_effects.size()
		# MvpSession already applies visual_error to the local presentation pose.
		# Read that rendered transform, avoiding a second addition of the offset.
		var distance := predicted.presentation.global_position.distance_to(attacker.body.global_position)
		var angle := rad_to_deg(predicted.presentation.global_basis.get_rotation_quaternion().angle_to(attacker.body.global_basis.get_rotation_quaternion()))
		peak_position = maxf(peak_position, distance)
		peak_angle = maxf(peak_angle, angle)
		if distance > 0.25 or angle > 10:
			last_bad = ticks.size() - 1
		victim_motion = victim_motion or victim.body.linear_velocity.dot(direction) > 0.25
		attacker_recoil = attacker_recoil or attacker.body.linear_velocity.dot(-direction) > 0.25
		remote_motion = remote_motion or client.world.bots[victim_id].remote_state.velocity.dot(direction) > 0.25
		remote_recoil = remote_recoil or client.world.bots[attacker_id].remote_state.velocity.dot(-direction) > 0.25
	check(victim_motion and attacker_recoil, "Actual Jolt bodies receive lateral impulse and opposing recoil")
	check(remote_motion and remote_recoil, "Victim impulse and attacker recoil traverse state snapshots")
	var settle := settling_ms(ticks, last_bad, last_hit_tick)
	check(ticks.back() - last_hit_tick >= 30, "Observe at least 500 ms after the final actual horizontal hit")
	check(settle <= 250, "Horizontal recoil presentation settles within 250 ms and remains within 0.25 m / 10 degrees")
	var effect_received := received_effects.any(func(event: Dictionary) -> bool:
		return event.event_id == authority_hit.event_id and event.attacker == attacker_id and event.target == victim_id)
	if profile not in ["80", "150"]:
		check(effect_received, "Authoritative horizontal hit effect reaches client over ENet")
	for delivered: Dictionary in received_effects:
		check(authority_effects.any(func(event: Dictionary) -> bool:
			return event.event_id == delivered.event_id and event.attacker == delivered.attacker and event.target == delivered.target \
				and event.damage == delivered.damage), "Delivered cosmetic effect matches an actual authoritative hit")
	print("Horizontal profile %s recoil: settle=%.1f ms peak=%.3f m/%.1f deg last_hit=%d observed_after=%.1f ms cosmetic_received=%s" %
		[profile, settle, peak_position, peak_angle, last_hit_tick, (ticks.back() - last_hit_tick) * 1000.0 / 60, effect_received])
	check(await until(func() -> bool:
		return is_equal_approx(client.world.bots[victim_id].remote_state.core, victim.combat.core), 120), "Client observes exact authoritative damage")
	var retained_core := victim.combat.core
	var token := client.reconnect_token
	client.leave()
	if not await require(await until(func() -> bool: return server.players[attacker_id].peer == 0, 600), "Disconnect reserves horizontal entity"):
		return
	check(client.join("127.0.0.1", port, token) == OK, "Horizontal entity reconnect starts")
	if not await require(await until(func() -> bool:
		return client.local_entity == attacker_id and client.world != null and client.world.bots.has(victim_id), 600), "Reconnect restores horizontal baseline"):
		return
	check(server.world.bots[attacker_id] == attacker and client.world.bots[attacker_id].remote_state.weapon == "horizontal_spinner",
		"Reconnect retains original entity and horizontal loadout")
	check(is_equal_approx(client.world.bots[victim_id].remote_state.core, retained_core), "Reconnect baseline preserves combat damage")
	server.vote_forfeit()
	if not await require(await until(func() -> bool: return client.match_view.get("phase") == "intermission", 300), "Host forfeit finishes first round"):
		return
	server.match_state.remaining = 0
	if not await require(await until(func() -> bool:
		return client.match_view.get("round") == 2 and client.match_view.get("phase") == "countdown", 300), "Horizontal loadout continues into round two"):
		return
	check(await until(func() -> bool:
		return client.world.bots.values().all(func(bot: MvpBot) -> bool:
			return bot.remote_state.weapon == "horizontal_spinner" and is_zero_approx(bot.remote_state.charge) \
				and not bot.remote_state.eliminated and is_equal_approx(bot.remote_state.core, bot.combat.stats.core)), 120),
		"Round reset retains horizontal identity, repairs damage and clears charge")
	print("Horizontal ENet: hit=%s victim_motion=%s recoil=%s remote_motion=%s remote_recoil=%s" %
		[authority_hit, victim_motion, attacker_recoil, remote_motion, remote_recoil])
	await finish()

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	await get_tree().physics_frame
	for child: Node in get_children():
		if child is SubViewport:
			get_tree().set_multiplayer(null, child.get_path())
		child.queue_free()
	await get_tree().process_frame
	print("HORIZONTAL SPINNER SESSION PASS" if failures == 0 else "HORIZONTAL SPINNER SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
