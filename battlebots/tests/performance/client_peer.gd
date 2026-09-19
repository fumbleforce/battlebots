extends SceneTree
## Independent headless client. Gameplay goes through ENet; files control measurement only.
const Relay = preload("res://tests/network/fixtures/udp_relay.gd")
const WEAPONS := ["vertical_spinner", "horizontal_spinner", "lifter", "hammer", "saw"]

class MeasuredSession extends MvpSession:
	var baseline_load_samples_s: Array[float] = []
	var arena_load_s := 0.0

	func _make_world() -> void:
		var begin_us := Time.get_ticks_usec()
		super._make_world()
		arena_load_s = float(Time.get_ticks_usec() - begin_us) / 1000000.0

	@rpc("authority", "call_remote", "reliable", 0)
	func _baseline(packet: PackedByteArray) -> void:
		var begin_us := Time.get_ticks_usec()
		super._baseline(packet)
		if world != null and not world.bots.is_empty():
			baseline_load_samples_s.append(float(Time.get_ticks_usec() - begin_us) / 1000000.0)

var session: MeasuredSession
var relay: Node
var output_dir := ""
var index := -1
var port := 0
var weapon := ""
var started_us := 0
var measurement_us := 0
var measurement_counters: Dictionary = {}
var measurement_snapshots := 0
var measurement_events := 0
var wire_window_samples: Array[Dictionary] = []
var last_wire_sample_us := 0
var wire_window_count := 0
var wire_window_last_s := 0.0
var wire_window_peak_up := 0.0
var wire_window_peak_down := 0.0
var combat_events := 0
var events_by_attacker: Dictionary = {}
var events_by_kind: Dictionary = {}
var commands_sent := 0
var active_seconds := 0.0
var load_samples_s: Array[float] = []
var loading_us := 0
var first_world_us := 0
var last_phase := ""
var last_status_us := 0
var ready_requested_us := 0
var loadout_sent := false
var rematch_voted := ""
var saw_active := false
var cooling := false
var previous_primary := false
var last_position := Vector3.ZERO
var stuck_seconds := 0.0
var escape_seconds := 0.0
var recovery_seconds := 0.0
var exiting := false
var fatal_reason := ""

func _initialize() -> void:
	start.call_deferred()

func start() -> void:
	started_us = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--output="): output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--index="): index = int(arg.trim_prefix("--index="))
	if not output_dir.is_absolute_path() or index < 0 or index > 9 or port < 1 or port > 65535:
		push_error("Required: --port=1..65535 --output=absolute-directory --index=0..9")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create performance output directory")
		quit(1)
		return
	weapon = WEAPONS[index % WEAPONS.size()]
	session = MeasuredSession.new()
	session.name = "Session"
	root.add_child(session)
	session.session_event.connect(on_session_event)
	session.combat_event.connect(func(event: Dictionary) -> void:
		combat_events += 1
		var key := str(event.get("attacker", 0))
		events_by_attacker[key] = int(events_by_attacker.get(key, 0)) + 1
		var kind := str(event.get("kind", "unknown"))
		events_by_kind[kind] = int(events_by_kind.get(kind, 0)) + 1)
	relay = Relay.new()
	relay.name = "Relay"
	root.add_child(relay)
	var error: Error = relay.start(0, port)
	if error != OK:
		finish("Relay bind failed: " + error_string(error))
		return
	process_frame.connect(poll)
	physics_frame.connect(drive)
	error = session.join("127.0.0.1", relay.bound_port)
	if error != OK:
		finish("ENet join failed: " + error_string(error))

func on_session_event(kind: String, details: Dictionary) -> void:
	if kind == "error" and not exiting:
		fatal_reason = str(details.get("message", "Session error"))

func counters() -> Dictionary:
	var result := {}
	for direction: String in ["uplink", "downlink"]:
		var data: Dictionary = relay.stats.get(direction, {})
		# One logical network hop per direction. Do not count relay forwarding twice.
		var suffix := "out" if direction == "uplink" else "in"
		var packets := int(data.get("packets_" + suffix, 0))
		var payload := int(data.get("bytes_" + suffix, 0))
		result[direction + "_packets"] = packets
		result[direction + "_payload_bytes"] = payload
		result[direction + "_wire_bytes"] = payload + 28 * packets
	return result

func poll() -> void:
	if exiting:
		return
	var now := Time.get_ticks_usec()
	if FileAccess.file_exists(output_dir.path_join("stop")):
		finish()
		return
	if not fatal_reason.is_empty():
		finish(fatal_reason)
		return
	if measurement_us == 0 and FileAccess.file_exists(output_dir.path_join("measure")):
		measurement_us = now
		measurement_counters = counters()
		measurement_snapshots = int(session.diagnostics.snapshots_received)
		measurement_events = combat_events
		last_wire_sample_us = now
		wire_window_samples.append({"at_us":now, "up":measurement_counters.uplink_wire_bytes, "down":measurement_counters.downlink_wire_bytes})
	if measurement_us > 0 and now - last_wire_sample_us >= 1000000:
		sample_wire_window(now)
	var phase := str(session.match_view.get("phase", "lobby"))
	if phase != last_phase:
		if phase == "loading":
			loading_us = now
			first_world_us = 0
		if phase == "active":
			saw_active = true
			cooling = false
			previous_primary = false
			stuck_seconds = 0
		last_phase = phase
	if loading_us > 0 and first_world_us == 0 and session.world != null and session.world.bots.size() == session.player_capacity:
		first_world_us = now
		load_samples_s.append(float(now - loading_us) / 1000000.0)
	if session.local_entity > 0 and session.connection_state == "connected":
		var local: Dictionary = {}
		for slot: Dictionary in session.lobby_view.get("slots", []):
			if int(slot.entity_id) == session.local_entity:
				local = slot
		if not local.is_empty() and phase == "lobby":
			if local.loadout.parts.weapon != weapon and not loadout_sent:
				var draft := session.registry.starter()
				draft.name = "Performance %02d %s" % [index, weapon]
				draft.parts.weapon = weapon
				session.set_loadout(draft)
				loadout_sent = true
			elif local.loadout.parts.weapon == weapon and not bool(local.ready) and now - ready_requested_us > 1000000:
				session.set_ready(true)
				ready_requested_us = now
		if phase == "results" and rematch_voted != str(session.match_view.get("match_id", "")):
			rematch_voted = str(session.match_view.match_id)
			session.vote_rematch()
	if not saw_active and now - started_us > 120000000:
		finish("No active match within 120 seconds")
		return
	if now - last_status_us >= 1000000:
		last_status_us = now
		write_json("client-%d-status.json" % index, report())

func drive() -> void:
	if exiting or session == null or session.connection_state != "connected":
		return
	var command := BotCommand.new()
	var active: bool = session.match_view.get("phase") in ["active", "overtime"]
	if not active or session.world == null or not session.world.bots.has(session.local_entity):
		command.brake = true
		session.submit_local(command)
		return
	active_seconds += 1.0 / 60.0
	var bot: MvpBot = session.world.bots[session.local_entity]
	var state: Dictionary = bot.remote_state
	if state.is_empty() or bool(state.get("eliminated", false)):
		command.brake = true
		session.submit_local(command)
		return
	var pose: Transform3D = state.pose
	var target := Vector3.ZERO
	var target_pose := Transform3D.IDENTITY
	var target_weapon_active := false
	var closest := INF
	for other: MvpBot in session.world.bots.values():
		if other.team == bot.team or other.remote_state.is_empty() or other.remote_state.get("eliminated", false):
			continue
		var enemy: Transform3D = other.remote_state.pose
		var distance := pose.origin.distance_squared_to(enemy.origin)
		if distance < closest:
			closest = distance
			target = enemy.origin
			target_pose = enemy
			target_weapon_active = other.remote_state.get("weapon_state") in ["active", "windup", "strike"]
	if closest == INF:
		command.brake = true
		session.submit_local(command)
		return
	var displacement := target - pose.origin
	displacement.y = 0
	var local_target := pose.basis.inverse() * displacement
	var angle := atan2(local_target.x, -local_target.z)
	var distance := displacement.length()
	var drive_angle := angle
	# The saw needs maintained contact, not a charged head-on collision. Approach
	# the flank of a powered enemy when there is still room, then aim at its hull.
	if weapon == "saw" and target_weapon_active and distance > 3.1:
		var enemy_to_self := (pose.origin - target).normalized()
		if enemy_to_self.dot(-target_pose.basis.z) > 0.35:
			var side := 1.0 if index % 2 == 0 else -1.0
			var approach := target + target_pose.basis.x * side * 2.6 + target_pose.basis.z * 0.6
			var local_approach := pose.basis.inverse() * (approach - pose.origin)
			drive_angle = atan2(local_approach.x, -local_approach.z)
	command.steering = clampf(drive_angle * 1.4, -1, 1)
	var reach := 2.5 if weapon == "saw" else (2.0 if weapon == "hammer" else 2.15)
	command.throttle = clampf((distance - reach) * 0.75, -0.35, 1.0) if absf(drive_angle) < 1.2 else 0.05
	command.brake = absf(distance - reach) < 0.14 and absf(drive_angle) < 0.12
	if pose.origin.distance_to(last_position) < 0.002 and command.throttle > 0.3:
		stuck_seconds += 1.0 / 60
	else:
		stuck_seconds = maxf(0, stuck_seconds - 2.0 / 60)
	last_position = pose.origin
	if stuck_seconds > 2.0:
		escape_seconds = 1.1
		stuck_seconds = 0
	if escape_seconds > 0:
		escape_seconds -= 1.0 / 60
		command.throttle = -0.7
		command.steering = 0.8 if index % 2 == 0 else -0.8
		command.brake = false
	elif maxf(absf(pose.origin.x), absf(pose.origin.z)) > 23.0:
		var inward := pose.basis.inverse() * -pose.origin
		command.steering = clampf(atan2(inward.x, -inward.z) * 1.4, -1, 1)
		command.throttle = 0.5
		command.brake = false
	var battery := float(state.get("battery", 0))
	var heat := float(state.get("heat", 0))
	if battery < 25 or heat > 80:
		cooling = true
	elif battery > 60 and heat < 35:
		cooling = false
	var aligned := absf(angle) < 0.65
	if not cooling:
		if weapon == "hammer":
			command.primary_held = aligned and distance < 2.6 and fmod(active_seconds + index * 0.23, 2.1) < 0.25
		elif weapon == "lifter":
			command.primary_held = fmod(active_seconds + index * 0.31, 2.4) < 1.5
		elif weapon == "saw":
			# Instant activation means powering up across the arena only wastes the
			# battery and thermal headroom needed for the actual sustained cut.
			command.primary_held = aligned and distance < 3.0
		else:
			command.primary_held = distance < 8.0
	command.primary_pressed = command.primary_held and not previous_primary
	previous_primary = command.primary_held
	recovery_seconds = maxf(0, recovery_seconds - 1.0 / 60)
	if bool(state.get("recovery_available", false)) and recovery_seconds <= 0:
		command.recovery_pressed = true
		recovery_seconds = 1
	session.submit_local(command)
	commands_sent += 1

func sample_wire_window(now: int) -> void:
	var current := counters()
	last_wire_sample_us = now
	wire_window_samples.append({"at_us":now, "up":current.uplink_wire_bytes, "down":current.downlink_wire_bytes})
	if wire_window_samples.size() > 11:
		wire_window_samples.pop_front()
	if wire_window_samples.size() < 11:
		return
	var oldest: Dictionary = wire_window_samples.front()
	wire_window_last_s = float(now - int(oldest.at_us)) / 1000000.0
	if wire_window_last_s < 10.0:
		return
	wire_window_count += 1
	wire_window_peak_up = maxf(wire_window_peak_up, float(int(current.uplink_wire_bytes) - int(oldest.up)) / wire_window_last_s)
	wire_window_peak_down = maxf(wire_window_peak_down, float(int(current.downlink_wire_bytes) - int(oldest.down)) / wire_window_last_s)

func report() -> Dictionary:
	var now := Time.get_ticks_usec()
	var total := counters() if relay != null else {}
	var measured := {}
	var elapsed := float(now - measurement_us) / 1000000.0 if measurement_us > 0 else 0.0
	for key: String in total:
		measured[key] = int(total[key]) - int(measurement_counters.get(key, total[key]))
	measured["uplink_wire_bytes_per_s"] = float(measured.get("uplink_wire_bytes", 0)) / elapsed if elapsed > 0 else 0.0
	measured["downlink_wire_bytes_per_s"] = float(measured.get("downlink_wire_bytes", 0)) / elapsed if elapsed > 0 else 0.0
	var reasons: Array[String] = []
	if not fatal_reason.is_empty(): reasons.append(fatal_reason)
	if elapsed <= 0: reasons.append("No measured interval")
	if session == null or session.local_entity <= 0: reasons.append("No admitted player entity")
	if session == null or session.connection_state != "connected": reasons.append("Client is not connected")
	if session == null or int(session.diagnostics.snapshots_received) - measurement_snapshots <= 0: reasons.append("No snapshots received during measurement")
	if commands_sent <= 0: reasons.append("No active gameplay commands submitted")
	return {"schema":1, "kind":"headless_client", "index":index, "pid":OS.get_process_id(), "weapon":weapon,
		"valid":reasons.is_empty(), "validation_reasons":reasons,
		"entity":session.local_entity if session != null else 0, "phase":session.match_view.get("phase", "lobby") if session != null else "startup",
		"match_id":session.match_view.get("match_id", "") if session != null else "", "connection_state":session.connection_state if session != null else "offline",
		"uptime_s":float(now - started_us) / 1000000.0, "measured_s":elapsed, "commands_sent":commands_sent,
		"snapshots_received":session.diagnostics.snapshots_received if session != null else 0,
		"measured_snapshots":int(session.diagnostics.snapshots_received) - measurement_snapshots if measurement_us > 0 else 0,
		"combat_events":combat_events, "measured_combat_events":combat_events - measurement_events if measurement_us > 0 else 0,
		"events_by_attacker":events_by_attacker, "events_by_kind":events_by_kind,
		"rtt_ms":session.diagnostics.rtt_ms if session != null else 0,
		"arena_load_s":session.arena_load_s if session != null else 0.0,
		"arena_load_definition":"Local _make_world construction including AuthorityWorld ready/arena instantiation; headless, excludes network and rendering",
		"load_samples_s":session.baseline_load_samples_s if session != null else [],
		"loading_to_world_samples_s":load_samples_s,
		"load_definition":"Receiving nonempty baseline through local bot-world construction; cached/headless, excludes network transit, asset download and rendering",
		"memory_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"traffic_total":total, "traffic_measured":measured, "udp_ip_overhead_bytes_per_packet":28,
		"traffic_window_10s":{"target_seconds":10, "sample_spacing_seconds":1, "samples_retained":wire_window_samples.size(), "sample_limit":11,
			"completed_windows":wire_window_count, "last_window_seconds":wire_window_last_s,
			"peak_uplink_wire_bytes_per_s":wire_window_peak_up, "peak_downlink_wire_bytes_per_s":wire_window_peak_down,
			"definition":"Rolling ten sampling intervals, wall-time denominator, at least ten seconds; diagnostic peaks, not mean bandwidth gate"},
		"relay_stats":relay.stats if relay != null else {}, "fatal_reason":fatal_reason, "finished":exiting}

func write_json(filename: String, data: Dictionary) -> bool:
	var final_path := output_dir.path_join(filename)
	var temporary := final_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write client report: " + temporary)
		quit(1)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	var error := DirAccess.rename_absolute(temporary, final_path)
	if error != OK:
		push_error("Cannot replace client report: " + error_string(error))
		quit(1)
		return false
	return true

func finish(reason := "") -> void:
	if exiting:
		return
	exiting = true
	if not reason.is_empty():
		fatal_reason = reason
	if not write_json("client-%d.json" % index, report()):
		return
	if session != null:
		session.leave()
	if relay != null:
		relay.stop()
	quit(0 if fatal_reason.is_empty() else 1)
