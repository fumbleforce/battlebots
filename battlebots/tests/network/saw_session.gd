extends "res://tests/network/contact_reconciliation.gd"
## Real ENet sustained cutting; simulator affects input/snapshots, not control UDP.
var held := false
var secondary := false
var authority_effects: Array[Dictionary] = []
var received_effects: Array[Dictionary] = []
var victim_id := 0
var sample_cut_presentation := false
var cut_sample_ticks: Array[int] = []
var peak_cut_position := 0.0
var peak_cut_angle := 0.0

func frame() -> void:
	if is_instance_valid(server) and server.local_entity > 0:
		var idle := BotCommand.new()
		idle.brake = true
		server.submit_local(idle)
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.brake = true
		command.primary_held = held
		command.secondary_held = secondary
		client.submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame
	if sample_cut_presentation:
		for client: MvpSession in clients:
			var authoritative: MvpBot = server.world.bots[client.local_entity]
			if authoritative.combat.weapon_phase != "active":
				continue
			var predicted: MvpBot = client.world.bots[client.local_entity]
			cut_sample_ticks.append(server.world.tick)
			peak_cut_position = maxf(peak_cut_position, predicted.presentation.global_position.distance_to(authoritative.body.global_position))
			peak_cut_angle = maxf(peak_cut_angle, rad_to_deg(predicted.presentation.global_basis.get_rotation_quaternion().angle_to(authoritative.body.global_basis.get_rotation_quaternion())))

func require(ok: bool, message: String) -> bool:
	check(ok, message)
	if not ok:
		await finish()
	return ok

func record_hit(event: Dictionary) -> void:
	var recorded := event.duplicate(true)
	if server.world.bots.has(victim_id):
		recorded["core_after"] = server.world.bots[victim_id].combat.core
		recorded["rear_after"] = server.world.bots[victim_id].combat.zones.rear
	authority_effects.append(recorded)

func run() -> void:
	server = make_session("SawHost")
	var port := FreePort.udp()
	if not await require(server.host(port, true, 2) == OK, "Saw listen host binds"):
		return
	var draft := server.registry.starter()
	draft.name = "Saw Striker"
	draft.parts.weapon = "saw"
	if not await require(server.registry.validate(draft).valid, "Canonical saw build is legal"):
		return
	# The host victim fits the 80 HP rear pack armour so each cut is shielded by
	# the rear plate and the replicated rear zone is present in BotView.
	var armoured := server.registry.starter()
	var pieces := SawbladeConfig.defaults()
	pieces.armor_rear = 1
	armoured.cosmetics = {"paint":"cyan", "sawblade":pieces}
	server.set_loadout(armoured)
	if not await require(server.players[server.local_entity].loadout.cosmetics.has("sawblade"), "Host victim fits rear armour"):
		return
	var client := make_session("SawClient")
	clients.append(client)
	client.combat_event.connect(func(event: Dictionary) -> void: received_effects.append(event.duplicate(true)))
	server.combat_event.connect(record_hit)
	if not await require(client.join("127.0.0.1", port) == OK, "Saw client begins real ENet join"):
		return
	if not await require(await until(func() -> bool: return client.local_entity > 0, 600), "Saw client admitted"):
		return
	client.set_loadout(draft)
	var attacker_id := client.local_entity
	victim_id = server.local_entity
	if not await require(await until(func() -> bool:
		return server.players[attacker_id].loadout.parts.weapon == "saw", 300), "Real client loadout request admits saw"):
		return
	client.set_ready(true)
	server.set_ready(true)
	if not await require(await until(func() -> bool:
		return client.match_view.get("phase") == "active" and server.match_state.phase == "active", 900), "Saw duel reaches active"):
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
	victim.body.reset_pose = server.world.clear_spawn_pose(victim, Transform3D(Basis.IDENTITY, Vector3(0, 0, -2.6 * BotScale.FACTOR)))
	await frames(45)
	var initial_core := victim.combat.core
	var initial_rear: float = victim.combat.zones.rear
	var attacker_start := attacker.body.global_position
	var victim_start := victim.body.global_position
	check(client.world.bots[attacker_id].remote_state.weapon == "saw", "Saw identity reaches active baseline")
	held = true
	if not await require(await until(func() -> bool: return attacker.combat.weapon_phase == "active", 120), "Actual remote held input activates saw"):
		return
	var first_active_tick := server.world.tick
	sample_cut_presentation = true
	check(is_equal_approx(attacker.combat.charge, 1), "Saw reaches full active state without charging delay")
	check(authority_effects.is_empty() and is_equal_approx(victim.combat.core, initial_core), "Starting contact has no immediate damage")
	if not await require(await until(func() -> bool: return authority_effects.size() >= 3, 180), "Sustained real contact produces three cuts"):
		return
	held = false
	check(int(authority_effects[0].tick) - first_active_tick in [19, 20], "First cut waits a full 20-tick cadence including activation boundary")
	for index: int in range(1, 3):
		check(int(authority_effects[index].tick) - int(authority_effects[index - 1].tick) == 20, "Maintained saw contact cuts exactly every 20 server ticks")
	check(client.world.bots[attacker_id].remote_state.weapon_state == "active" and is_equal_approx(client.world.bots[attacker_id].remote_state.charge, 1),
		"Snapshots publish active saw phase and full charge")
	if not await require(await until(func() -> bool: return attacker.combat.weapon_phase == "idle", 120), "Remote release stops saw authority"):
		return
	var released_count := authority_effects.size()
	await frames(60)
	check(authority_effects.size() == released_count, "Released saw cannot accumulate further contact damage")
	check(attacker.body.global_position.distance_to(attacker_start) < 0.02 and victim.body.global_position.distance_to(victim_start) < 0.02,
		"Standing saw contact does not add authored knockback")
	held = true
	if not await require(await until(func() -> bool: return attacker.combat.weapon_phase == "active", 120), "Restart held input reaches saw authority"):
		return
	var restart_tick := server.world.tick
	check(authority_effects.size() == released_count, "Restart does not reuse partial prior contact time")
	if not await require(await until(func() -> bool: return authority_effects.size() > released_count, 120), "Restarted contact cuts again"):
		return
	check(int(authority_effects[released_count].tick) - restart_tick in [19, 20], "Restart requires a fresh full contact cadence")
	secondary = true
	if not await require(await until(func() -> bool: return attacker.combat.weapon_phase == "idle", 120), "Secondary stops held saw"):
		return
	var stopped_count := authority_effects.size()
	await frames(60)
	check(authority_effects.size() == stopped_count, "Secondary prevents further cuts while primary remains held")
	sample_cut_presentation = false
	check(cut_sample_ticks.size() >= 30, "Observe local presentation through at least 500 ms of active cutting")
	check(peak_cut_position <= 0.25 and peak_cut_angle <= 10, "Active saw contact keeps local presentation within 0.25 m / 10 degrees")
	held = false
	secondary = false
	for index: int in range(authority_effects.size()):
		var event: Dictionary = authority_effects[index]
		check(event.attacker == attacker_id and event.target == victim_id and event.zone == "rear", "Every cut strikes the intended rear armor")
		check(is_equal_approx(initial_rear, 80.0) and is_equal_approx(event.core_after, initial_core)
			and is_equal_approx(event.rear_after, initial_rear - 6.0 * (index + 1)), "Each cut applies exactly 6 raw to the rear plate, which fully shields the core")
		if index > 0:
			check(event.event_id > authority_effects[index - 1].event_id and event.attack_id > authority_effects[index - 1].attack_id,
				"Each actual saw cut advances authoritative effect and attack identity")
	check(await until(func() -> bool:
		return is_equal_approx(client.world.bots[victim_id].remote_state.core, victim.combat.core) \
			and is_equal_approx(client.world.bots[victim_id].remote_state.zones.rear, victim.combat.zones.rear), 180),
		"Observer core and rear integrity converge exactly")
	var delivered_ids: Array[int] = []
	for delivered: Dictionary in received_effects:
		check(not delivered_ids.has(int(delivered.event_id)), "Observer emits each delivered effect once")
		delivered_ids.append(int(delivered.event_id))
		check(authority_effects.any(func(event: Dictionary) -> bool:
			return event.event_id == delivered.event_id and event.attack_id == delivered.attack_id and event.damage == delivered.damage),
			"Observer effect identity and damage match an actual cut")
	if profile not in ["80", "150"]:
		check(received_effects.size() == authority_effects.size(), "Unimpaired observer receives every cut effect")
	var retained_core := victim.combat.core
	var retained_rear: float = victim.combat.zones.rear
	var token := client.reconnect_token
	client.leave()
	if not await require(await until(func() -> bool: return server.players[attacker_id].peer == 0, 600), "Saw disconnect reserves entity"):
		return
	check(client.join("127.0.0.1", port, token) == OK, "Saw reconnect starts")
	if not await require(await until(func() -> bool:
		return client.local_entity == attacker_id and client.world != null and client.world.bots.has(victim_id), 600), "Saw reconnect receives complete baseline"):
		return
	check(server.world.bots[attacker_id] == attacker and client.world.bots[attacker_id].remote_state.weapon == "saw", "Reconnect keeps original saw entity/loadout")
	check(is_equal_approx(client.world.bots[victim_id].remote_state.core, retained_core)
		and is_equal_approx(client.world.bots[victim_id].remote_state.zones.rear, retained_rear), "Reconnect baseline preserves core and armor damage")
	server.vote_forfeit()
	if not await require(await until(func() -> bool: return client.match_view.get("phase") == "intermission", 300), "Saw first round finishes"):
		return
	server.match_state.remaining = 0
	if not await require(await until(func() -> bool:
		return client.match_view.get("round") == 2 and client.match_view.get("phase") == "countdown", 300), "Saw enters round two"):
		return
	check(await until(func() -> bool:
		return client.world.bots[attacker_id].remote_state.weapon == "saw" \
			and client.world.bots[attacker_id].remote_state.weapon_state == "idle" \
			and is_equal_approx(client.world.bots[victim_id].remote_state.core, initial_core) \
			and is_equal_approx(client.world.bots[victim_id].remote_state.zones.rear, initial_rear), 180),
		"Round reset retains saw, stops cutting and restores armor/core")
	print("Saw profile %s: cuts=%d ticks=%s core=%.2f rear=%.2f effects=%d" %
		[profile, authority_effects.size(), authority_effects.map(func(event: Dictionary) -> int: return event.tick),
		retained_core, retained_rear, received_effects.size()])
	print("Saw profile %s active presentation: samples=%d peak=%.3f m/%.1f deg" %
		[profile, cut_sample_ticks.size(), peak_cut_position, peak_cut_angle])
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
	print("SAW SESSION PASS" if failures == 0 else "SAW SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
