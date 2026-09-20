extends "res://tests/network/contact_reconciliation.gd"
## Real ENet hammer edges; optional simulator affects only input and snapshots.
var held := false
var press_next := false
var secondary := false
var authority_effects: Array[Dictionary] = []
var received_effects: Array[Dictionary] = []
var observed_phases: Dictionary = {}

func frame() -> void:
	if is_instance_valid(server) and server.local_entity > 0:
		var idle := BotCommand.new()
		idle.brake = true
		server.submit_local(idle)
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.brake = true
		command.primary_pressed = press_next
		command.primary_held = held
		command.secondary_held = secondary
		client.submit_local(command)
	press_next = false
	await get_tree().physics_frame
	await get_tree().process_frame
	for client: MvpSession in clients:
		if client.world != null and client.world.bots.has(client.local_entity):
			var state: Dictionary = client.world.bots[client.local_entity].remote_state
			observed_phases[str(state.get("weapon_state", ""))] = true

func require(ok: bool, message: String) -> bool:
	check(ok, message)
	if not ok:
		await finish()
	return ok

func hit_count(attacker_id: int, victim_id: int) -> int:
	return authority_effects.filter(func(event: Dictionary) -> bool:
		return event.attacker == attacker_id and event.target == victim_id).size()

func place_pair(attacker: MvpBot, victim: MvpBot) -> void:
	attacker.body.reset_pose = server.world.clear_spawn_pose(attacker, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var separation: float = (attacker.combat.stats.size.z + victim.combat.stats.size.z) * 0.5 + 0.1 * BotScale.FACTOR
	victim.body.reset_pose = server.world.clear_spawn_pose(victim, Transform3D(Basis.IDENTITY, Vector3(0, 0, -separation)))

func observe_recoil(client: MvpSession, attacker: MvpBot, victim_id: int, duration_ticks: int, label: String) -> void:
	var predicted: MvpBot = client.world.bots[attacker.entity_id]
	var strike_tick: int = authority_effects.back().tick
	var event_cursor := authority_effects.size()
	var start_tick := Engine.get_physics_frames()
	var ticks: Array[int] = []
	var last_bad := -1
	var peak_position := 0.0
	var peak_angle := 0.0
	while Engine.get_physics_frames() - start_tick < duration_ticks:
		await frame()
		ticks.append(server.world.tick)
		for event: Dictionary in authority_effects.slice(event_cursor):
			if event.attacker == attacker.entity_id and event.target == victim_id:
				strike_tick = maxi(strike_tick, int(event.tick))
		event_cursor = authority_effects.size()
		# Session presentation already includes the local visual_error correction.
		var distance := predicted.presentation.global_position.distance_to(attacker.body.global_position)
		var angle := rad_to_deg(predicted.presentation.global_basis.get_rotation_quaternion().angle_to(attacker.body.global_basis.get_rotation_quaternion()))
		peak_position = maxf(peak_position, distance)
		peak_angle = maxf(peak_angle, angle)
		if distance > 0.25 or angle > 10:
			last_bad = ticks.size() - 1
	var settle := settling_ms(ticks, last_bad, strike_tick)
	check(ticks.back() - strike_tick >= 30, "%s observes at least 500 ms after final real hammer hit" % label)
	check(settle <= 250, "%s hammer recoil settles within 250 ms and stays within 0.25 m / 10 degrees" % label)
	print("Hammer profile %s %s recoil: settle=%.1f ms peak=%.3f m/%.1f deg observed_after=%.1f ms" %
		[profile, label, settle, peak_position, peak_angle, (ticks.back() - strike_tick) * 1000.0 / 60])

func run() -> void:
	server = make_session("HammerHost")
	var port := 36000 + OS.get_process_id() % 10000
	if not await require(server.host(port, true, 2) == OK, "Hammer listen host binds"):
		return
	var draft := server.registry.duelist()
	if not await require(server.registry.validate(draft).valid and draft.parts.weapon == "hammer", "Canonical Duelist hammer build is legal"):
		return
	var client := make_session("HammerClient")
	clients.append(client)
	client.combat_event.connect(func(event: Dictionary) -> void: received_effects.append(event.duplicate(true)))
	server.combat_event.connect(func(event: Dictionary) -> void: authority_effects.append(event.duplicate(true)))
	if not await require(client.join("127.0.0.1", port) == OK, "Hammer client begins real ENet join"):
		return
	if not await require(await until(func() -> bool: return client.local_entity > 0, 600), "Hammer client admitted"):
		return
	client.set_loadout(draft)
	var attacker_id := client.local_entity
	var victim_id := server.local_entity
	if not await require(await until(func() -> bool:
		return server.players[attacker_id].loadout.parts.weapon == "hammer", 300), "Reliable request admits canonical hammer loadout"):
		return
	client.set_ready(true)
	server.set_ready(true)
	if not await require(await until(func() -> bool:
		return client.match_view.get("phase") == "active" and server.match_state.phase == "active", 900), "Hammer duel reaches active"):
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
	place_pair(attacker, victim)
	await frames(45)
	check(client.world.bots[attacker_id].remote_state.weapon == "hammer", "Hammer identity crosses active baseline and snapshots")
	var before := victim.combat.core
	held = true
	press_next = true
	if not await require(await until(func() -> bool: return attacker.combat.attack_id == 1, 120), "One real remote press starts hammer attack"):
		return
	check(attacker.combat.weapon_phase == "windup", "Accepted press enters windup before damage")
	check(is_equal_approx(victim.combat.core, before), "Windup has not already damaged victim")
	if not await require(await until(func() -> bool: return hit_count(attacker_id, victim_id) == 1, 120), "Committed first swing produces one authoritative hit"):
		return
	check(authority_effects.back().zone == "top" and is_equal_approx(victim.combat.core, before - 38.0 * 0.95),
		"First overhead strike applies exactly 38 raw damage through the top multiplier")
	# Continue holding beyond both the windup and full recovery. No synthesized
	# edge or retry is allowed: this must remain the same one physical press.
	await observe_recoil(client, attacker, victim_id, 150, "first strike")
	check(attacker.combat.attack_id == 1 and hit_count(attacker_id, victim_id) == 1, "Holding through recovery does not repeat hammer attack")
	check(observed_phases.has("windup") and observed_phases.has("cooldown"), "Client snapshots show committed windup and recovery")
	check(await until(func() -> bool:
		return is_equal_approx(client.world.bots[victim_id].remote_state.core, victim.combat.core), 180), "First-hit health converges exactly through snapshots")
	held = false
	place_pair(attacker, victim)
	await frames(45)
	var after_first := victim.combat.core
	held = true
	press_next = true
	if not await require(await until(func() -> bool: return attacker.combat.attack_id == 2, 120), "Second actual remote edge starts a new attack"):
		return
	check(attacker.combat.weapon_phase == "windup", "Second edge commits a fresh windup")
	held = false
	secondary = true
	if not await require(await until(func() -> bool: return hit_count(attacker_id, victim_id) == 2, 120), "Release and secondary do not cancel committed hammer swing"):
		return
	secondary = false
	check(authority_effects.back().zone == "top" and is_equal_approx(victim.combat.core, after_first - 38.0 * 0.95),
		"Second overhead strike applies exactly 38 raw damage through the top multiplier")
	await observe_recoil(client, attacker, victim_id, 120, "second strike")
	check(attacker.combat.attack_id == 2 and hit_count(attacker_id, victim_id) == 2, "Exactly two accepted edges produce exactly two hits")
	check(await until(func() -> bool:
		return is_equal_approx(client.world.bots[victim_id].remote_state.core, victim.combat.core), 180), "Second-hit health converges exactly")
	for delivered: Dictionary in received_effects:
		check(authority_effects.any(func(event: Dictionary) -> bool:
			return event.event_id == delivered.event_id and event.attack_id == delivered.attack_id and event.damage == delivered.damage),
			"Delivered hammer effect matches actual authority attack")
	if profile not in ["80", "150"]:
		check(received_effects.size() == 2, "Unimpaired ENet delivers both hammer effects")
	var retained_core := victim.combat.core
	var token := client.reconnect_token
	client.leave()
	if not await require(await until(func() -> bool: return server.players[attacker_id].peer == 0, 600), "Hammer disconnect reserves entity"):
		return
	check(client.join("127.0.0.1", port, token) == OK, "Hammer reconnect begins")
	if not await require(await until(func() -> bool:
		return client.local_entity == attacker_id and client.world != null and client.world.bots.has(victim_id), 600), "Hammer reconnect receives complete baseline"):
		return
	check(server.world.bots[attacker_id] == attacker and attacker.combat.attack_id == 2, "Reconnect retains hammer entity and attack history")
	check(client.world.bots[attacker_id].remote_state.weapon == "hammer" and is_equal_approx(client.world.bots[victim_id].remote_state.core, retained_core),
		"Reconnect baseline preserves weapon and prior damage")
	server.vote_forfeit()
	if not await require(await until(func() -> bool: return client.match_view.get("phase") == "intermission", 300), "Host forfeit ends first round"):
		return
	server.match_state.remaining = 0
	if not await require(await until(func() -> bool:
		return client.match_view.get("round") == 2 and client.match_view.get("phase") == "countdown", 300), "Hammer advances to second round"):
		return
	check(await until(func() -> bool:
		return client.world.bots[attacker_id].remote_state.weapon == "hammer" \
			and client.world.bots[attacker_id].remote_state.weapon_state == "idle" \
			and is_equal_approx(client.world.bots[victim_id].remote_state.core, victim.combat.stats.core) \
			and not client.world.bots[victim_id].remote_state.eliminated, 180), "Round reset retains hammer, repairs damage and clears attack phase")
	print("Hammer profile %s: attacks=2 hits=%d phases=%s delivered_effects=%d retained_core=%.2f" %
		[profile, authority_effects.size(), observed_phases.keys(), received_effects.size(), retained_core])
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
	print("HAMMER SESSION PASS" if failures == 0 else "HAMMER SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
