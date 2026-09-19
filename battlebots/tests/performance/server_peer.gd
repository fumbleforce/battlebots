extends SceneTree
## Dedicated-process performance fixture. Gameplay follows production session rules.
## TIME_PHYSICS_PROCESS is a roughly one-second maximum in Godot 4.7.2,
## not one independent tick sample (main/main.cpp:4679-4680,4757-4761).
const WEAPONS := ["vertical_spinner", "horizontal_spinner", "lifter", "hammer", "saw"]
const START_TIMEOUT_SECONDS := 90.0

class TimingHistogram extends RefCounted:
	# Fixed storage prevents benchmark sampling from causing apparent soak leaks.
	const BIN_USEC := 10
	const BIN_COUNT := 100001
	var bins := PackedInt64Array()
	var count := 0
	var total_usec := 0
	var maximum_usec := 0
	var overflow := 0

	func _init() -> void:
		bins.resize(BIN_COUNT)
		bins.fill(0)

	func add(usec: int) -> void:
		var index := ceili(float(usec) / BIN_USEC)
		if index >= BIN_COUNT:
			overflow += 1
		index = mini(index, BIN_COUNT - 1)
		bins[index] += 1
		count += 1
		total_usec += usec
		maximum_usec = maxi(maximum_usec, usec)

	func summary() -> Dictionary:
		var cumulative := 0
		var percentile := 0.0
		var wanted := ceili(count * 0.95)
		for index: int in range(BIN_COUNT):
			cumulative += bins[index]
			if count > 0 and cumulative >= wanted:
				percentile = float(index * BIN_USEC) / 1000.0
				if index == BIN_COUNT - 1 and overflow > 0:
					percentile = maximum_usec / 1000.0
				break
		return {"samples":count, "mean_ms":float(total_usec) / maxi(1, count) / 1000.0,
			"p95_upper_bound_ms":percentile, "max_ms":maximum_usec / 1000.0,
			"histogram_resolution_ms":0.01, "histogram_overflow":overflow}

class TimedSession extends MvpSession:
	var observed: Callable

	func _physics_process(delta: float) -> void:
		var active_before := match_state.phase in ["active", "overtime"]
		var started := Time.get_ticks_usec()
		super._physics_process(delta)
		var elapsed := Time.get_ticks_usec() - started
		if observed.is_valid():
			observed.call(elapsed, active_before)

var session: TimedSession
var output := ""
var port := 24567
var seconds := 60.0
var warmup := 15.0
var started_usec := 0
var first_active_usec := 0
var measure_started_usec := 0
var measure_finished_usec := 0
var measuring := false
var finishing := false
var ready := false
var last_status_usec := 0
var physics_at_start := 0
var physics_at_finish := 0
var max_live := 0
var measured_max_live := 0
var current_live := 0
var connected_count := 0
var all_ten_known := false
var all_ten_active_seen := false
var active_ticks := 0
var measured_active_ticks := 0
var measured_ten_live_ticks := 0
var measured_under_ten_connected_ticks := 0
var callbacks := TimingHistogram.new()
var active_callbacks := TimingHistogram.new()
var ten_live_callbacks := TimingHistogram.new()
var engine_windows := TimingHistogram.new()
var event_counts := {}
var measured_events := {}
var authored_events := {}
var measured_authored_events := {}
var activation_ticks := {}
var measured_activation_ticks := {}
var unknown_kind_events := 0
var measured_unknown_kind_events := 0
var results_count := 0
var measured_results_count := 0
var rematches_count := 0
var measured_rematches_count := 0
var match_starts := 0
var last_match_id := ""
var last_result_match_id := ""
var session_errors: Array[String] = []
var failures: Array[String] = []
var engine_samples := 0
var monitor_zero_samples := 0
var object_baseline := {}
var object_final := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not parse_arguments():
		quit(2)
		return
	for weapon: String in WEAPONS:
		event_counts[weapon] = 0
		measured_events[weapon] = 0
		authored_events[weapon] = 0
		measured_authored_events[weapon] = 0
		activation_ticks[weapon] = 0
		measured_activation_ticks[weapon] = 0
	started_usec = Time.get_ticks_usec()
	session = TimedSession.new()
	session.name = "Session"
	session.observed = observe_tick
	root.add_child(session)
	session.combat_event.connect(observe_combat_event)
	session.session_event.connect(observe_session_event)
	var error := session.host(port, false, 10)
	ready = error == OK
	if not ready:
		failures.append("Dedicated server could not bind UDP port: " + error_string(error))
		await finish()
		return
	write_status()
	while not finishing:
		await process_frame
		var now := Time.get_ticks_usec()
		if FileAccess.file_exists(output.path_join("stop")):
			failures.append("External stop arrived before measured duration completed")
			break
		if first_active_usec == 0 and elapsed_since(started_usec, now) >= START_TIMEOUT_SECONDS:
			failures.append("Ten connected live players did not reach active within 90 seconds")
			break
		if not measuring and first_active_usec > 0 and elapsed_since(first_active_usec, now) >= warmup:
			begin_measurement(now)
		if measuring and elapsed_since(measure_started_usec, now) >= seconds:
			break
		if now - last_status_usec >= 1000000:
			if measuring:
				var monitor := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
				engine_windows.add(roundi(monitor * 1000000.0))
				engine_samples += 1
				monitor_zero_samples += int(monitor <= 0.0)
			write_status()
	await finish()

func parse_arguments() -> bool:
	var args := OS.get_cmdline_user_args()
	var values := {}
	var index := 0
	while index < args.size():
		var arg: String = args[index]
		if arg.begins_with("--"):
			var separator := arg.find("=")
			if separator > 0:
				values[arg.substr(2, separator - 2)] = arg.substr(separator + 1)
			elif index + 1 < args.size():
				values[arg.substr(2)] = args[index + 1]
				index += 1
		index += 1
	output = str(values.get("output", ""))
	port = str(values.get("port", "24567")).to_int()
	seconds = str(values.get("seconds", "60")).to_float()
	warmup = str(values.get("warmup", "15")).to_float()
	if not output.is_absolute_path() or port < 1024 or port > 65535 or not is_finite(seconds) or seconds <= 0.0 or not is_finite(warmup) or warmup < 0.0:
		push_error("Expected --output=<absolute directory>, valid --port, positive --seconds and nonnegative --warmup")
		return false
	var error := DirAccess.make_dir_recursive_absolute(output)
	if error != OK:
		push_error("Cannot create performance output directory: " + error_string(error))
		return false
	if FileAccess.file_exists(output.path_join("measure")) or FileAccess.file_exists(output.path_join("stop")):
		push_error("Performance fixture requires a fresh directory without lifecycle markers")
		return false
	return true

func elapsed_since(start: int, now: int) -> float:
	return (now - start) / 1000000.0 if start > 0 else 0.0

func begin_measurement(now: int) -> void:
	measure_started_usec = now
	physics_at_start = Engine.get_physics_frames()
	object_baseline = object_counts()
	measuring = true
	atomic_json("measure", {"started_unix_seconds":Time.get_unix_time_from_system(), "seconds":seconds, "warmup":warmup})
	write_status()

func observe_tick(usec: int, was_active: bool) -> void:
	if finishing or not ready or not is_instance_valid(session.world):
		return
	current_live = 0
	connected_count = 0
	for player: Dictionary in session.players.values():
		connected_count += int(int(player.get("peer", 0)) > 0)
	for bot: MvpBot in session.world.bots.values():
		current_live += int(not bot.combat.eliminated)
		var weapon: String = bot.combat.stats.weapon
		if was_active and not bot.combat.eliminated and (bot.combat.weapon_phase in ["active", "windup", "strike", "launch"]):
			activation_ticks[weapon] = int(activation_ticks.get(weapon, 0)) + 1
			if measuring:
				measured_activation_ticks[weapon] = int(measured_activation_ticks.get(weapon, 0)) + 1
	max_live = maxi(max_live, current_live)
	all_ten_known = all_ten_known or (session.players.size() == 10 and session.world.bots.size() == 10)
	var ten_active := was_active and current_live == 10 and connected_count == 10
	if ten_active:
		all_ten_active_seen = true
		if first_active_usec == 0:
			first_active_usec = Time.get_ticks_usec()
	active_ticks += int(was_active)
	var match_id := str(session.match_state.match_id)
	if not match_id.is_empty() and match_id != last_match_id:
		match_starts += 1
		if not last_match_id.is_empty() and last_result_match_id == last_match_id:
			rematches_count += 1
			measured_rematches_count += int(measuring)
		last_match_id = match_id
	if not measuring:
		return
	callbacks.add(usec)
	measured_under_ten_connected_ticks += int(connected_count != 10)
	measured_max_live = maxi(measured_max_live, current_live)
	measured_active_ticks += int(was_active)
	if was_active:
		active_callbacks.add(usec)
	if ten_active:
		ten_live_callbacks.add(usec)
		measured_ten_live_ticks += 1

func observe_combat_event(event: Dictionary) -> void:
	var id := int(event.get("attacker", 0))
	if not is_instance_valid(session.world) or not session.world.bots.has(id):
		return
	var weapon: String = session.world.bots[id].combat.stats.weapon
	event_counts[weapon] = int(event_counts.get(weapon, 0)) + 1
	if measuring:
		measured_events[weapon] = int(measured_events.get(weapon, 0)) + 1
	# Only the authoritative discriminator proves weapon hits rather than rams.
	var kind := str(event.get("kind", ""))
	if kind in WEAPONS:
		if kind != weapon and not failures.has("Authoritative combat kind differs from attacker weapon"):
			failures.append("Authoritative combat kind differs from attacker weapon")
		authored_events[kind] = int(authored_events.get(kind, 0)) + 1
		if measuring:
			measured_authored_events[kind] = int(measured_authored_events.get(kind, 0)) + 1
	elif kind != "ram":
		unknown_kind_events += 1
		measured_unknown_kind_events += int(measuring)

func observe_session_event(kind: String, details: Dictionary) -> void:
	if kind == "results":
		results_count += 1
		measured_results_count += int(measuring)
		last_result_match_id = str(details.get("match", {}).get("match_id", session.match_state.match_id))
	elif kind == "error":
		var message := str(details.get("message", "Unknown session error"))
		if session_errors.size() < 32:
			session_errors.append(message)

func object_counts() -> Dictionary:
	return {"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"orphans_debug_only":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"static_bytes_debug_only":Performance.get_monitor(Performance.MEMORY_STATIC)}

func status() -> Dictionary:
	var now := Time.get_ticks_usec()
	var end := measure_finished_usec if measure_finished_usec > 0 else now
	return {"ready":ready, "measuring":measuring, "finished":finishing,
		"elapsed":elapsed_since(measure_started_usec, end), "uptime_seconds":elapsed_since(started_usec, now),
		"warmup_elapsed_seconds":elapsed_since(first_active_usec, now), "warmup_seconds":warmup, "requested_seconds":seconds,
		"phase":session.match_state.phase, "round":session.match_state.round_index, "match_id":session.match_state.match_id,
		"connected":connected_count, "known_players":session.players.size(), "live":current_live,
		"all_ten_known":all_ten_known, "all_ten_active_seen":all_ten_active_seen, "max_live":max_live,
		"measured_max_live":measured_max_live, "active_ticks":active_ticks,
		"measured_active_ticks":measured_active_ticks, "measured_ten_live_ticks":measured_ten_live_ticks,
		"measured_under_ten_connected_ticks":measured_under_ten_connected_ticks,
		"combat_events_by_attacker_weapon":event_counts.duplicate(), "measured_combat_events_by_attacker_weapon":measured_events.duplicate(),
		"authored_weapon_events":authored_events.duplicate(), "measured_authored_weapon_events":measured_authored_events.duplicate(),
		"unclassified_combat_events":unknown_kind_events, "measured_unclassified_combat_events":measured_unknown_kind_events,
		"weapon_activation_ticks":activation_ticks.duplicate(), "measured_weapon_activation_ticks":measured_activation_ticks.duplicate(),
		"results":results_count, "rematches":rematches_count, "match_starts":match_starts,
		"measured_results":measured_results_count, "measured_rematches":measured_rematches_count,
		"session_errors":session_errors.duplicate(), "validity_reasons":failures.duplicate()}

func write_status() -> void:
	last_status_usec = Time.get_ticks_usec()
	atomic_json("server-status.json", status())

func atomic_json(filename: String, data: Dictionary) -> bool:
	var target := output.path_join(filename)
	var temporary := target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		record_io_failure("Cannot write " + filename)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, target)
	if error != OK:
		record_io_failure("Cannot publish " + filename + ": " + error_string(error))
		return false
	return true

func record_io_failure(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
		push_error(message)

func finish() -> void:
	finishing = true
	measure_finished_usec = Time.get_ticks_usec()
	physics_at_finish = Engine.get_physics_frames()
	measuring = false
	object_final = object_counts()
	var report := status()
	var elapsed := elapsed_since(measure_started_usec, measure_finished_usec)
	if measure_started_usec == 0:
		failures.append("Measurement never started")
	elif elapsed + 0.001 < seconds:
		failures.append("Measured duration ended early")
	if callbacks.count == 0:
		failures.append("No measured server physics callbacks")
	if not all_ten_active_seen:
		failures.append("Ten live connected players were never simultaneously active")
	if measured_under_ten_connected_ticks > 0:
		failures.append("Measured interval lost one or more of the ten connected players")
	var coverage: Array[String] = []
	for weapon: String in WEAPONS:
		if int(measured_authored_events.get(weapon, 0)) == 0:
			coverage.append("No classified measured authored contact event for " + weapon)
	if measured_ten_live_ticks == 0:
		coverage.append("Measured interval contains no ten-live-player active ticks")
	if elapsed < 3600.0:
		coverage.append("Run is shorter than the required sixty measured minutes")
	if measured_results_count < 2 or measured_rematches_count < 1:
		coverage.append("Measured interval does not demonstrate repeated completed matches and rematch")
	report["validity_reasons"] = failures.duplicate()
	report["valid"] = failures.is_empty() and session_errors.is_empty()
	report["validation_reasons"] = failures.duplicate() + session_errors.duplicate()
	report["measured_s"] = elapsed
	report["weapon_events"] = measured_authored_events.duplicate()
	report["completed_matches"] = measured_results_count
	report["coverage_reasons"] = coverage
	report["completed"] = measure_started_usec > 0 and elapsed + 0.001 >= seconds
	report["build"] = WireCodec.BUILD
	report["content_hash"] = session.registry.content_hash
	report["godot"] = Engine.get_version_info().get("string", "")
	report["physics_ticks"] = maxi(0, physics_at_finish - physics_at_start) if measure_started_usec > 0 else 0
	report["physics_hz"] = float(report.physics_ticks) / elapsed if elapsed > 0.0 else 0.0
	report["session_callback_ms"] = callbacks.summary()
	report["callback_p95_ms"] = report.session_callback_ms.p95_upper_bound_ms
	report["active_session_callback_ms"] = active_callbacks.summary()
	report["ten_live_session_callback_ms"] = ten_live_callbacks.summary()
	report["engine_physics_window_max_ms"] = engine_windows.summary()
	report["engine_monitor_sample_count"] = engine_samples
	report["engine_monitor_zero_samples"] = monitor_zero_samples
	report["full_physics_tick_p95_ms"] = null
	report["object_baseline"] = object_baseline
	report["object_final"] = object_final
	report["measurement_definitions"] = {
		"session_callback":"Exact wall microseconds around MvpSession._physics_process; includes authority, swept queries, synchronous event observers and outgoing RPC serialization; excludes engine Jolt step and input polling outside callback.",
		"histograms":"Fixed allocation before warm-up; 0.01ms bins report percentile upper bounds, overflow explicitly counted.",
		"engine_physics_window_max":"TIME_PHYSICS_PROCESS sampled once per status second; Godot 4.7.2 publishes prior approximately one-second maximum including physics engine step. Distribution is sampled window maxima, not per-tick p95. Boundary windows may overlap warm-up.",
		"physics_hz":"Engine physics-frame count divided by actual measured wall seconds, across normal match phases.",
		"combat_events":"By-attacker-weapon counters may include rams; authored counters require authoritative kind=<canonical weapon ID>, and kind=ram is excluded.",
		"memory":"Godot debug allocation/object counters are diagnostic only. Launcher must measure per-process OS memory for soak acceptance.",
		"timers":"Production round/countdown/intermission/results timers are unchanged. No restored health, invulnerability or forced match outcome."}
	report["limitations"] = ["Full engine per-tick simulation p95 is not exposed by the sampled monitor.",
		"This headless fixture does not certify rendered frame time or visual effects.",
		"Hardware, OS memory, UDP protocol overhead and client measurements must be joined with launcher/client reports."]
	atomic_json("server.json", report)
	write_status()
	atomic_json("stop", {"valid":report.valid, "completed":report.completed})
	print("PERFORMANCE SERVER FINISHED: " + output)
	var leave_at := Time.get_ticks_usec() + 1000000
	while Time.get_ticks_usec() < leave_at:
		await process_frame
	session.leave()
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() and session_errors.is_empty() else 1)
