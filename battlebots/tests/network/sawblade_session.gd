extends SceneTree
var failures: Array[String] = []
var sessions: Array[MvpSession] = []
var containers: Array[SubViewport] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var instance := MvpSession.new()
	instance.name = "Session"
	viewport.add_child(instance)
	containers.append(viewport)
	sessions.append(instance)
	return instance

func until(predicate: Callable, seconds := 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

func run() -> void:
	var server := session("Server")
	var first := session("First")
	var second := session("Second")
	var port := 34000 + OS.get_process_id() % 10000
	check(server.host(port, false, 2) == OK, "Duel server starts")
	first.join("127.0.0.1", port)
	second.join("127.0.0.1", port)
	if not await until(func(): return first.local_entity > 0 and second.local_entity > 0):
		check(false, "Two clients join")
		finish()
		return
	var draft := SawbladeConfig.starter(first.registry)
	draft.parts.drive = "walker"
	draft.parts.weapon = "hammer"
	draft.cosmetics.sawblade.exhaust = 3
	draft.cosmetics.sawblade.paint_primary = [0.1, 0.4, 0.2, 1.0]
	check(WireCodec.json_packet({"value":draft}).size() < 4096, "Appearance fits existing request budget")
	first.set_loadout(draft)
	second.set_loadout(SawbladeConfig.starter(second.registry))
	check(await until(func(): return server.players[first.local_entity].loadout.parts.drive == "walker"), "Server accepts walker build")
	first.set_ready(true)
	second.set_ready(true)
	if not await until(func(): return server.match_state.phase == "active" and first.world != null and first.world.bots.size() == 2):
		check(false, "Ready/countdown reaches active")
		finish()
		return
	var id := first.local_entity
	check(first.world.bots[id].loadout.cosmetics.sawblade == JSON.parse_string(JSON.stringify(draft.cosmetics.sawblade)), "Full selected appearance reaches client spawn")
	check(first.world.bots[id].body.walker and server.world.bots[id].body.walker, "Authority and predicted body use walking drive")
	var start: Vector3 = server.world.bots[id].body.global_position
	var start_pose: Transform3D = server.world.bots[id].body.global_transform
	for peer: MvpSession in sessions:
		var obstacle := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(4, 0.35, 2.4)
		collider.shape = shape
		obstacle.add_child(collider)
		peer.world.add_child(obstacle)
		obstacle.global_transform = start_pose
		obstacle.global_position = start_pose * Vector3(0, 0, -3.0)
		obstacle.global_position.y = 0.175
		if OS.get_environment("BATTLEBOTS_NET_PROFILE") == "80":
			peer.network_simulation.delay_ms = 40
			peer.network_simulation.jitter_ms = 10
	var attack := false
	var remote_attack := false
	var maximum_correction := 0.0
	var peak_height := 0.0
	for frame: int in 180:
		var command := BotCommand.new()
		command.throttle = 1.0 if frame < 90 else 0.0
		command.brake = frame >= 90
		command.primary_pressed = frame == 25
		command.primary_held = frame >= 25 and frame < 30
		first.submit_local(command)
		await physics_frame
		attack = attack or server.world.bots[id].combat.attack_id > 0
		if second.world != null and second.world.bots.has(id):
			remote_attack = remote_attack or second.world.bots[id].read_view().weapon_state in [&"windup", &"strike", &"cooldown"]
		maximum_correction = maxf(maximum_correction, first.diagnostics.correction_m)
		peak_height = maxf(peak_height, server.world.bots[id].body.global_position.y)
	check(attack and remote_attack, "Primary starts hammer attack and replicates its animation state")
	check(server.world.bots[id].body.global_position.distance_to(start) > 2, "Walking client commands move authoritative bot")
	check(peak_height > 1.22, "Network-controlled walker physically climbs fixture obstacle")
	check(first.world.bots[id].body.global_position.distance_to(server.world.bots[id].body.global_position) < 0.35, "Walker settles to authoritative pose")
	print("SAWBLADE NETWORK max correction=", maximum_correction)
	finish()

func finish() -> void:
	for instance: MvpSession in sessions: instance.leave()
	for viewport: SubViewport in containers: viewport.queue_free()
	await process_frame
	if failures.is_empty(): print("SAWBLADE SESSION PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
