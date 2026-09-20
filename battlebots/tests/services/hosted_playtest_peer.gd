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
var reconnect_started := false
var reconnect_verified := false
var reconnect_token_rotated := false
var reconnect_health_retained := false
var reconnect_elapsed_ms := 0
var reconnect_barrier_passed := false
var reconnect_joined := false

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
			if bool(details.get("reconnected", false)):
				reconnect_joined = true
				return
			session.set_loadout(session.registry.starter())
			session.set_ready(true)
		elif kind == "error":
			if reconnect_started and not reconnect_verified and bool(details.get("reconnect_available", false)):
				return
			var detail := str(details.get("message", "Session rejected or disconnected"))
			for credential: String in [str(config.get("admission_ticket", "")), session.reconnect_token]:
				if not credential.is_empty():
					detail = detail.replace(credential, "[hidden]")
			finish(detail.left(240))
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
	if bool(config.get("reconnect_check", false)) and not reconnect_barrier_passed:
		if not FileAccess.file_exists(str(config.reconnect_ready)) and session.bot_views().size() == 2:
			var ready := FileAccess.open(str(config.reconnect_ready), FileAccess.WRITE)
			ready.store_string("ready")
			ready.close()
		if bool(config.get("reconnect_peer", false)):
			if not reconnect_started and FileAccess.file_exists(str(config.observer_ready)):
				reconnect_started = true
				verify_reconnect.call_deferred()
		else:
			reconnect_barrier_passed = FileAccess.file_exists(str(config.reconnect_done))
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

func verify_reconnect() -> void:
	var entity := session.local_entity
	var match_id := str(session.match_view.match_id)
	var round_index := int(session.match_view.round)
	var token := session.reconnect_token
	var before := session.local_source().read_view()
	var began := Time.get_ticks_msec()
	# Real ENet disconnection handshake; no injected session event or server mutation.
	session.multiplayer.multiplayer_peer.disconnect_peer(1)
	while not finished and not session.can_reconnect() and Time.get_ticks_msec() - began < 8000:
		await process_frame
	if finished:
		return
	if not session.can_reconnect() or session.reconnect() != OK:
		finish("Transport loss did not permit same-session reconnect")
		return
	while not finished and Time.get_ticks_msec() - began < 19000:
		if reconnect_joined and session.local_entity == entity and session.bot_views().size() == 2:
			break
		await process_frame
	if finished:
		return
	reconnect_elapsed_ms = Time.get_ticks_msec() - began
	reconnect_token_rotated = not token.is_empty() and not session.reconnect_token.is_empty() and token != session.reconnect_token
	var after: BotView = session.local_source().read_view() if session.local_source() != null else null
	reconnect_health_retained = after != null and is_equal_approx(before.core_fraction, after.core_fraction) and before.zones == after.zones
	reconnect_verified = reconnect_joined and session.local_entity == entity and session.bot_views().size() == 2 \
		and str(session.match_view.get("match_id", "")) == match_id and int(session.match_view.get("round", 0)) == round_index \
		and reconnect_elapsed_ms < 20000 and reconnect_token_rotated and reconnect_health_retained
	if not reconnect_verified:
		finish("Reconnect identity, baseline, token rotation or health retention failed")
		return
	var done := FileAccess.open(str(config.reconnect_done), FileAccess.WRITE)
	done.store_string("reconnected")
	done.close()
	reconnect_barrier_passed = true

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
		and session.diagnostics.snapshots_received > 0 and moved > 0.1 and duel_valid \
		and (not bool(config.get("reconnect_check", false)) or reconnect_barrier_passed)
	var result := {"valid":success, "reason":reason, "entity":session.local_entity,
		"active_frames":active_frames, "snapshots":session.diagnostics.snapshots_received,
		"reconnect_barrier_passed":reconnect_barrier_passed, "reconnect_verified":reconnect_verified,
		"reconnect_token_rotated":reconnect_token_rotated, "reconnect_health_retained":reconnect_health_retained,
		"reconnect_elapsed_ms":reconnect_elapsed_ms,
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
