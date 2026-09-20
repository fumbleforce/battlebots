extends SceneTree
## Controlled authority state over real ENet; not natural combat acceptance.
var failures := 0
var viewports: Array[SubViewport] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func make_session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	viewports.append(viewport)
	var session := MvpSession.new()
	session.name = "Session"
	viewport.add_child(session)
	return session

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(1))
	var host := make_session("AudioHost")
	var client := make_session("AudioClient")
	check(host.audio_views().is_empty(), "Offline session has no audio records")
	check(host.practice() == OK, "Practice starts")
	var records := host.audio_views()
	check(records.size() == 4, "All three practice NPC audio records are independent of the admitted roster")
	for record: Dictionary in records:
		check(record.velocity == Vector3.ZERO and record.angular == Vector3.ZERO
			and record.drive_input == 0.0 and record.turn_input == 0.0
			and not record.grounded, "Pending spawn reset publishes neutral physical motion")
		check(not record.weapon.is_empty() and record.age == 0.0, "Authority supplies weapon family and fresh age")
	records[0].charge = -44.0
	check(host.audio_views()[0].charge >= 0.0, "Audio records cannot mutate combat state")
	host.leave()
	check(host.audio_views().is_empty(), "Leaving clears audio data")
	var port := 43000 + OS.get_process_id() % 9000
	check(host.host(port, true, 2) == OK and client.join("127.0.0.1", port) == OK, "Real duel transport starts")
	if not await until(func() -> bool: return client.local_entity > 0 and client.lobby_view.get("slots", []).size() == 2):
		check(false, "Real duel admission completes")
	else:
		host.set_ready(true)
		client.set_ready(true)
		if not await until(func() -> bool: return client.match_view.get("phase") == "active" and client.audio_views().size() == 2):
			check(false, "Accepted duel snapshots expose both audio sources")
		else:
			var bot: MvpBot = client.world.bots[client.local_entity]
			bot.body.linear_velocity = Vector3(99, 98, 97)
			bot.body._drive_input = -0.91
			var record: Dictionary = client.audio_views().filter(func(value: Dictionary) -> bool: return value.entity_id == client.local_entity)[0]
			check(record.velocity == bot.remote_state.velocity and record.drive_input == bot.remote_state.drive_input
				and record.velocity != bot.body.linear_velocity, "Local audio follows server data despite divergent prediction")
			check(record.position == bot.read_view().pose.origin and record.pose == bot.remote_state.pose, "Spatial placement and physical pose have separate sources")
			bot.remote_state.arrival = client._time - 0.8
			record = client.audio_views().filter(func(value: Dictionary) -> bool: return value.entity_id == client.local_entity)[0]
			check(is_equal_approx(record.age, 0.8), "Age tracks accepted snapshot arrival")
			client._last_snapshot_tick.erase(client.local_entity)
			check(client.audio_views().size() == 1, "Body without accepted baseline cannot publish default sound state")
			client._last_snapshot_tick[client.local_entity] = bot.server_tick
			bot.remote_state.epoch = "invalid-epoch"
			check(client.audio_views().size() == 1, "Retired epoch cannot publish sound state")
	host.leave()
	client.leave()
	check(client.audio_views().is_empty(), "Client leave removes stale sound state")
	for viewport: SubViewport in viewports: viewport.queue_free()
	await process_frame
	print("AUDIO SESSION PASS" if failures == 0 else "AUDIO SESSION FAIL")
	quit(0 if failures == 0 else 1)
