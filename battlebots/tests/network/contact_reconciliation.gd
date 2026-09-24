extends Node
const FreePort := preload("res://tests/fixtures/free_port.gd")
## Real ENet peers in separate physics worlds. Server-only setup; no test RPCs.
var failures := 0
var sessions: Array[MvpSession] = []
var server: MvpSession
var clients: Array[MvpSession] = []
var profile := OS.get_environment("BATTLEBOTS_NET_PROFILE")
var recover_next := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func make_session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	add_child(viewport)
	get_tree().set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var session := MvpSession.new()
	session.name = "Session"
	# Combat fixtures hold MvpBot references; a part pickup would replace them.
	session.pickups_enabled = false
	viewport.add_child(session)
	sessions.append(session)
	return session

func frame() -> void:
	for client: MvpSession in clients:
		var command := BotCommand.new()
		command.brake = true
		command.recovery_pressed = client.local_entity == recover_next
		client.submit_local(command)
	recover_next = 0
	await get_tree().physics_frame
	await get_tree().process_frame

func frames(count: int) -> void:
	for index: int in range(count):
		await frame()

func until(predicate: Callable, limit := 1200) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await frame()
	return false

func settling_ms(ticks: Array[int], last_bad: int, start_tick: int) -> float:
	if last_bad < 0:
		return 0.0
	if last_bad + 1 >= ticks.size():
		return INF # Observation ended before convergence; never report a pass.
	return maxi(0, ticks[last_bad + 1] - start_tick) * 1000.0 / 60

func run() -> void:
	server = make_session("Server")
	var port := FreePort.udp()
	check(server.host(port, false, 2) == OK, "Server binds")
	for index: int in range(2):
		var client := make_session("Client%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Client joins")
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)):
		check(false, "Two clients admitted")
		await finish()
		return
	clients[1].set_loadout(clients[1].registry.starter(true))
	await frames(10)
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.match_view.get("phase") == "active")):
		check(false, "Ready reaches active")
		await finish()
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
	await frames(90)
	await impulse_case()
	await weapon_case("lifter", 1, 0)
	await weapon_case("spinner", 0, 1)
	await ram_case()
	await recovery_case()
	await round_reset_case()
	await finish()

func impulse_case() -> void:
	var id := clients[0].local_entity
	var authoritative: MvpBot = server.world.bots[id]
	var predicted: MvpBot = clients[0].world.bots[id]
	var start_tick := Engine.get_physics_frames()
	var ticks: Array[int] = []
	# A single known impulse, followed by a half-second flight observation window.
	# Landings are measured separately; this clock cannot be extended by resting contacts.
	authoritative.body.apply_central_impulse(Vector3(3, 6, 0) * authoritative.body.mass)
	authoritative.body.angular_velocity = Vector3(4, 0, 0)
	var last_bad := -1
	var peak_position := 0.0
	var peak_angle := 0.0
	var errors: Array = []
	var error_at_target := Vector2.INF
	for index: int in range(30):
		await frame()
		ticks.append(Engine.get_physics_frames())
		var distance := predicted.presentation.global_position.distance_to(authoritative.body.global_position)
		var angle := rad_to_deg(predicted.presentation.global_basis.get_rotation_quaternion().angle_to(authoritative.body.global_basis.get_rotation_quaternion()))
		peak_position = maxf(peak_position, distance)
		peak_angle = maxf(peak_angle, angle)
		errors.append(Vector2(distance, angle))
		if ticks.back() - start_tick >= 15 and error_at_target == Vector2.INF:
			error_at_target = errors.back()
		if OS.get_environment("BATTLEBOTS_CONTACT_TRACE") == "1":
			print("frame=", index + 1, " server=", authoritative.body.global_position,
				" client=", predicted.presentation.global_position, " error=", Vector2(distance, angle),
				" ticks=", authoritative.server_tick - predicted.server_tick, " commands=", clients[0]._local_commands.size(),
				" snapshot_ground=", predicted.remote_state.grounded, " ground=", authoritative.body.grounded)
		if distance > 0.25 or angle > 10:
			last_bad = index
	var settle := settling_ms(ticks, last_bad, start_tick)
	print("Contact profile %s impulse: settle=%.1f ms peak=%.3f m/%.1f deg error_at_250ms=%s" %
		[profile, settle, peak_position, peak_angle, error_at_target])
	check(settle <= 250, "Impulse converges within 250 ms and stays within 0.25 m / 10 degrees")
	await frames(180)
	check(predicted.presentation.global_position.distance_to(authoritative.body.global_position) < 0.25, "Landing eventually converges")

func round_reset_case() -> void:
	var victim := clients[1].local_entity
	server.world.bots[victim].combat.eliminate("test")
	check(await until(func() -> bool: return clients[0].match_view.get("phase") == "intermission"), "Round ends")
	await frames(30)
	# Save a real old-round packet which is newer than the client's delayed snapshot.
	var old_packet := WireCodec.encode_bot(server.world.bots[victim], clients[0].world.bots[victim].remote_state.epoch)
	server.match_state.remaining = 0
	check(await until(func() -> bool: return clients[0].match_view.get("round") == 2), "Next round received")
	var received: int = clients[0].diagnostics.snapshots_received
	clients[0]._snapshot(old_packet)
	check(clients[0].diagnostics.snapshots_received == received, "Previous-round packet is rejected after reliable round transition")
	await frames(30)
	for client: MvpSession in clients:
		for id: int in server.world.bots:
			var bot: MvpBot = client.world.bots[id]
			check(not bot.remote_state.eliminated, "Round reset revives every observer")
			check(bot.presentation.global_position.distance_to(server.world.bots[id].body.global_position) < 0.1,
				"Reset reaches spawn on local and remote presentation")

func weapon_case(label: String, attacker_index: int, victim_index: int) -> void:
	server.world.reset_round()
	var attacker: MvpBot = server.world.bots[clients[attacker_index].local_entity]
	var victim: MvpBot = server.world.bots[clients[victim_index].local_entity]
	attacker.body.reset_pose = server.world.clear_spawn_pose(attacker, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var separation: float = (attacker.combat.stats.size.z + victim.combat.stats.size.z) * 0.5 + 0.05 * BotScale.FACTOR
	victim.body.reset_pose = server.world.clear_spawn_pose(victim, Transform3D(Basis.IDENTITY, Vector3(0, 0, -separation)))
	await frames(90)
	attacker.combat.charge = 1
	attacker.combat._previous_held = label == "lifter"
	attacker.input_age = 0
	var before := victim.combat.core
	var seen_hit := false
	var last_bad := -1
	var hit_frame := -1
	var peak := 0.0
	var client_bot: MvpBot = clients[victim_index].world.bots[victim.entity_id]
	var ticks: Array[int] = []
	for index: int in range(45):
		await frame()
		ticks.append(Engine.get_physics_frames())
		for event: Dictionary in server.world.weapons.events:
			if event.target == victim.entity_id:
				seen_hit = true
				hit_frame = index
		var distance := client_bot.presentation.global_position.distance_to(victim.body.global_position)
		var angle := rad_to_deg(client_bot.presentation.global_basis.get_rotation_quaternion().angle_to(victim.body.global_basis.get_rotation_quaternion()))
		if OS.get_environment("BATTLEBOTS_CONTACT_TRACE") == "1":
			print("weapon=", label, " frame=", index + 1, " server=", victim.body.global_position,
				" client=", client_bot.presentation.global_position, " error=", Vector2(distance, angle),
				" server_velocity=", victim.body.linear_velocity, " client_velocity=", client_bot.body.linear_velocity,
				" snapshot_ground=", client_bot.remote_state.grounded, " ground=", victim.body.grounded)
		peak = maxf(peak, distance)
		if distance > 0.25 or angle > 10:
			last_bad = index
	var settle := settling_ms(ticks, last_bad, ticks[maxi(0, hit_frame)])
	print("Contact profile %s %s: settle=%.1f ms peak=%.3f m" % [profile, label, settle, peak])
	check(seen_hit and victim.combat.core < before, "Actual %s hit and damage occurred" % label)
	check(hit_frame >= 0 and ticks.back() - ticks[maxi(0, hit_frame)] >= 30, "Observe at least 500 ms after the final weapon hit")
	check(settle <= 250, "%s correction settles after final attack" % label)
	await frames(180)

func ram_case() -> void:
	server.world.reset_round()
	var a: MvpBot = server.world.bots[clients[0].local_entity]
	var b: MvpBot = server.world.bots[clients[1].local_entity]
	a.body.reset_pose = server.world.clear_spawn_pose(a, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	# Preserve the original 1.9m approach gap at the same 8m/s collision speed.
	var separation: float = (a.combat.stats.size.z + b.combat.stats.size.z) * 0.5 + 1.9
	b.body.reset_pose = server.world.clear_spawn_pose(b, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -separation)))
	await frames(90)
	a.body.linear_velocity = Vector3(0, 0, -8)
	b.body.linear_velocity = Vector3(0, 0, 8)
	var impact_frame := -1
	var last_bad := -1
	var peak := 0.0
	var observed: MvpBot = clients[0].world.bots[a.entity_id]
	var ticks: Array[int] = []
	for index: int in range(90):
		await frame()
		ticks.append(Engine.get_physics_frames())
		# Ram events require physical body contact and >4 m/s closing speed;
		# unlike standing contacts, they cannot indefinitely move the settle clock.
		if not server.world.weapons.events.is_empty():
			impact_frame = index
		var distance := observed.presentation.global_position.distance_to(a.body.global_position)
		var angle := rad_to_deg(observed.presentation.global_basis.get_rotation_quaternion().angle_to(a.body.global_basis.get_rotation_quaternion()))
		if OS.get_environment("BATTLEBOTS_CONTACT_TRACE") == "1":
			print("ram frame=", index + 1, " impact=", impact_frame, " server=", a.body.global_position, " client=", observed.presentation.global_position,
				" error=", Vector2(distance, angle), " sv=", a.body.linear_velocity, " cv=", observed.body.linear_velocity, " ground=", a.body.grounded)
		peak = maxf(peak, distance)
		if distance > 0.25 or angle > 10:
			last_bad = index
	var settle := settling_ms(ticks, last_bad, ticks[maxi(0, impact_frame)])
	print("Contact profile %s head-on ram: settle=%.1f ms peak=%.3f m" % [profile, settle, peak])
	check(impact_frame >= 0 and a.combat.core < a.combat.stats.core, "Physical head-on ram and damage occurred")
	check(impact_frame >= 0 and ticks.back() - ticks[maxi(0, impact_frame)] >= 30, "Observe at least 500 ms after the final ram")
	check(settle <= 250, "Head-on ram correction settles after final impact")

func recovery_case() -> void:
	server.world.reset_round()
	var id := clients[0].local_entity
	var authoritative: MvpBot = server.world.bots[id]
	authoritative.body.reset_pose = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0, authoritative.combat.stats.size.y * 0.5 + 0.05, 0))
	await frames(160)
	check(authoritative.combat.can_recover(), "Flipped authoritative bot is eligible for recovery")
	recover_next = id
	check(await until(func() -> bool: return authoritative.combat.recovery_count > 0, 60), "Remote recovery command reaches authority")
	check(await until(func() -> bool: return authoritative.combat.recovery_remaining <= 0, 180), "Recovery torque ends")
	var observed: MvpBot = clients[0].world.bots[id]
	var last_bad := -1
	var start_tick := Engine.get_physics_frames()
	var ticks: Array[int] = []
	for index: int in range(60):
		await frame()
		ticks.append(Engine.get_physics_frames())
		var distance := observed.presentation.global_position.distance_to(authoritative.body.global_position)
		var angle := rad_to_deg(observed.presentation.global_basis.get_rotation_quaternion().angle_to(authoritative.body.global_basis.get_rotation_quaternion()))
		if OS.get_environment("BATTLEBOTS_CONTACT_TRACE") == "1":
			print("rec frame=", index + 1, " server=", authoritative.body.global_position, " client=", observed.presentation.global_position,
				" error=", Vector2(distance, angle), " sv=", authoritative.body.linear_velocity, " cv=", observed.body.linear_velocity, " ground=", authoritative.body.grounded, " cground=", observed.body.grounded)
		if distance > 0.25 or angle > 10:
			last_bad = index
	var settle := settling_ms(ticks, last_bad, start_tick)
	print("Contact profile %s recovery: settle=%.1f ms" % [profile, settle])
	check(authoritative.body.global_basis.y.dot(Vector3.UP) > 0.5, "Physical recovery restores wheel orientation")
	check(settle <= 250, "Client settles after recovery torque ends")

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("CONTACT NETWORK PASS" if failures == 0 else "CONTACT NETWORK FAIL")
	get_tree().quit(0 if failures == 0 else 1)
