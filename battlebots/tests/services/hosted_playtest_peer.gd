extends SceneTree
## Independent real ENet client; credentials arrive through a private local file.
var session: MvpSession
var config := {}
var started := 0
var active_frames := 0
var finished := false
var initial_position := Vector3.ZERO

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	var path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--peer-config="):
			path = argument.trim_prefix("--peer-config=")
	if not path.is_absolute_path():
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		quit(2)
		return
	config = parsed
	var game := Node.new()
	game.name = "MenuGame"
	root.add_child(game)
	session = MvpSession.new()
	session.name = "Session"
	game.add_child(session)
	session.session_event.connect(func(kind: String, _details: Dictionary) -> void:
		if kind == "joined":
			session.set_loadout(session.registry.starter())
			session.set_ready(true)
		elif kind == "error":
			finish("Session rejected or disconnected"))
	started = Time.get_ticks_msec()
	var error := session.join(str(config.address), int(config.port), "", str(config.admission_ticket))
	if error != OK:
		finish("ENet creation failed")
		return
	physics_frame.connect(drive)
	process_frame.connect(func() -> void:
		if not finished and Time.get_ticks_msec() - started > 60000:
			finish("Timed out before active gameplay"))

func drive() -> void:
	if finished or session.match_view.get("phase") != "active":
		return
	if active_frames == 0:
		initial_position = session.world.bots[session.local_entity].body.global_position
	active_frames += 1
	var command := BotCommand.new()
	command.throttle = 0.4 if active_frames < 180 else 0.0
	command.steering = 0.2
	command.primary_held = true
	session.submit_local(command)
	if active_frames >= 360:
		finish("")

func finish(reason: String) -> void:
	if finished:
		return
	finished = true
	var moved := 0.0
	if session.world != null and session.world.bots.has(session.local_entity):
		moved = session.world.bots[session.local_entity].body.global_position.distance_to(initial_position)
	var success: bool = reason.is_empty() and active_frames >= 360 and session.local_entity > 0 \
		and session.diagnostics.snapshots_received > 0 and moved > 0.1
	var result := {"valid":success, "reason":reason, "entity":session.local_entity,
		"active_frames":active_frames, "snapshots":session.diagnostics.snapshots_received,
		"moved_m":moved, "players":session.lobby_view.get("slots", []).size()}
	var file := FileAccess.open(str(config.output), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(result))
	file.close()
	session.leave()
	print("HOSTED PEER PASS" if success else "HOSTED PEER FAILED")
	quit(0 if success else 1)
