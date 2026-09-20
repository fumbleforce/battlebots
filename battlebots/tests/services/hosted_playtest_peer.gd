extends SceneTree
## Independent real ENet client; credentials arrive through a private local file.
var session: MvpSession
var config := {}
var started := 0
var active_frames := 0
var finished := false
var initial_position := Vector3.ZERO
var movement := 0.0
var completed_match := ""
var result_record := {}
var rematch_id := ""
var forfeited_rounds := {}
var rematch_frames := 0
var local_team := -1

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
	session.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "joined":
			session.set_loadout(session.registry.starter())
			session.set_ready(true)
		elif kind == "error":
			finish("Session rejected or disconnected")
		elif kind == "results" and bool(config.get("duel_lifecycle", false)):
			result_record = details.duplicate(true)
			completed_match = str(details.get("match", {}).get("match_id", ""))
			session.vote_rematch())
	started = Time.get_ticks_msec()
	var error := session.join(str(config.address), int(config.port), "", str(config.admission_ticket))
	if error != OK:
		finish("ENet creation failed")
		return
	physics_frame.connect(drive)
	process_frame.connect(func() -> void:
		if not finished and Time.get_ticks_msec() - started > 60000:
			finish("Timed out before assigned match lifecycle completed"))

func drive() -> void:
	if finished or session.match_view.get("phase") != "active":
		return
	if not completed_match.is_empty() and str(session.match_view.get("match_id", "")) != completed_match:
		rematch_id = str(session.match_view.get("match_id", ""))
		rematch_frames += 1
		if rematch_frames >= 60:
			finish("")
		return
	if active_frames == 0:
		initial_position = session.world.bots[session.local_entity].body.global_position
		local_team = session.world.bots[session.local_entity].team
	active_frames += 1
	var command := BotCommand.new()
	command.throttle = 0.4 if active_frames < 180 else 0.0
	command.steering = 0.2
	command.primary_held = true
	session.submit_local(command)
	if active_frames >= 360:
		movement = maxf(movement, session.world.bots[session.local_entity].body.global_position.distance_to(initial_position))
		if not bool(config.get("duel_lifecycle", false)):
			finish("")
		elif bool(config.get("forfeit_peer", false)):
			var round_index := int(session.match_view.get("round", 0))
			if not forfeited_rounds.has(round_index):
				forfeited_rounds[round_index] = true
				session.vote_forfeit()

func finish(reason: String) -> void:
	if finished:
		return
	finished = true
	var moved := 0.0
	if session.world != null and session.world.bots.has(session.local_entity):
		moved = session.world.bots[session.local_entity].body.global_position.distance_to(initial_position)
	moved = maxf(moved, movement)
	var match_record: Dictionary = result_record.get("match", {})
	var duel_valid: bool = not bool(config.get("duel_lifecycle", false)) or (not completed_match.is_empty() \
		and not rematch_id.is_empty() and rematch_frames >= 60 \
		and match_record.get("rounds", []).size() == 2 and result_record.get("participants", {}).size() == 2 \
		and match_record.get("scores", []).max() == 2 and int(match_record.get("winner", -1)) >= 0)
	var success: bool = reason.is_empty() and active_frames >= 360 and session.local_entity > 0 \
		and session.diagnostics.snapshots_received > 0 and moved > 0.1 and duel_valid
	var result := {"valid":success, "reason":reason, "entity":session.local_entity,
		"active_frames":active_frames, "snapshots":session.diagnostics.snapshots_received,
		"moved_m":moved, "players":session.lobby_view.get("slots", []).size(),
		"results_received":not result_record.is_empty(), "rematch_active":rematch_frames >= 60,
		"completed_match":completed_match, "rematch_id":rematch_id,
		"completed_rounds":match_record.get("rounds", []).size(),
		"participants":result_record.get("participants", {}).size(),
		"scores":match_record.get("scores", []), "winner":match_record.get("winner", -1), "team":local_team}
	var file := FileAccess.open(str(config.output), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(result))
	file.close()
	session.leave()
	print("HOSTED PEER PASS" if success else "HOSTED PEER FAILED")
	quit(0 if success else 1)
