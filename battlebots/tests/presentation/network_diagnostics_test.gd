extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var panel: NetworkDiagnosticsPanel = load("res://scenes/ui/network_diagnostics_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var data := {"rtt_ms":80.5, "correction_m":0.125, "interpolation_ms":100.0,
		"snapshots_received":24, "rejected_inputs":7, "snapshot_bytes":420, "degraded":false,
		"reconnect_token":"DO_NOT_DISPLAY"}
	var context := {"build":"mvp-test", "mode":"2v2", "phase":"active", "physics_ms":0.85}
	var original := data.duplicate(true)
	var original_context := context.duplicate(true)
	panel.show_diagnostics("connected", data, context)
	check(panel.title_label.text == "CONNECTED" and panel.summary_label.text.contains("80.5 ms"), "Connected RTT is labeled")
	check(panel.details_label.text.contains("0.125 m") and panel.details_label.text.contains("100.0 ms"), "Client motion metrics display units")
	check(panel.details_label.text.contains("24") and panel.details_label.text.contains("since session node creation"), "Counter scope is explicit")
	check(not panel.details_label.text.contains("Rejected") and not panel.details_label.text.contains("snapshot packet"), "Client never shows server-only counters")
	check(not panel.details_label.text.contains("DO_NOT_DISPLAY"), "Unknown fields and secrets are not dumped")
	check(data == original and context == original_context, "Presentation does not mutate caller dictionaries")
	check(not panel.expanded and not panel.details_label.visible, "Details initially collapsed")
	var interactions: Array[int] = [0]
	panel.interaction_started.connect(func() -> void: interactions[0] += 1)
	panel.details_button.grab_focus()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter)
	enter = enter.duplicate()
	enter.pressed = false
	root.push_input(enter)
	await process_frame
	check(panel.expanded and panel.details_label.visible and interactions[0] == 1, "Keyboard expands details and notifies parent to release controls")
	panel.details_button.pressed.emit()
	check(not panel.expanded and not panel.details_label.visible, "Details collapse")
	check(panel.details_button.focus_mode == Control.FOCUS_ALL and panel.details_button.mouse_filter == Control.MOUSE_FILTER_STOP, "Only button accepts pointer and keyboard input")
	for node in [panel, panel.get_node("Margin"), panel.get_node("Margin/Content"), panel.title_label, panel.summary_label, panel.details_label]:
		check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Passive diagnostics must not intercept gameplay input")
	data.degraded = true
	panel.show_diagnostics("connected", data, context)
	check(panel.title_label.text == "CONNECTION DEGRADED" and panel.summary_label.text.contains("may pause"), "Explicit degraded flag presents warning")
	for malformed in [1, "true", null, [], {}]:
		data.degraded = malformed
		panel.show_diagnostics("connected", data, context)
		check(panel.title_label.text == "CONNECTED", "Only true boolean means degraded")
	data.degraded = true
	for phase in ["lobby", "loading", "countdown", "intermission", "results", "--"]:
		context.phase = phase
		panel.show_diagnostics("connected", data, context)
		check(panel.title_label.text == "CONNECTED" and panel.summary_label.text == "Waiting for match data", "Inactive phases cannot reuse degraded or RTT")
		check(not panel.details_label.text.contains("correction") and not panel.details_label.text.contains("Snapshots received"), "Inactive phases hide prior-match metrics")
	context.phase = "active"
	panel.show_diagnostics("hosting", data, context)
	check(panel.title_label.text == "HOSTING" and panel.details_label.text.contains("Rejected inputs: 7"), "Host displays authoritative rejection count")
	check(panel.details_label.text.contains("Largest snapshot packet: 420 B"), "Host packet metric is maximum bytes, not bandwidth")
	check(not panel.details_label.text.contains("correction") and not panel.summary_label.text.contains("RTT"), "Host never claims remote client measurements")
	for state in ["offline", "practice", "connecting", "unknown"]:
		panel.show_diagnostics(state, data, context)
		check(not panel.summary_label.text.contains("RTT") and not panel.details_label.text.contains("correction") and not panel.details_label.text.contains("Rejected"), "Inactive state hides stale measurements")
	var object := RefCounted.new()
	for value in [null, "0", true, -1, NAN, INF, -INF, [], {}, object]:
		var invalid := {"rtt_ms":value, "correction_m":value, "interpolation_ms":value, "snapshots_received":value}
		panel.show_diagnostics("connected", invalid, context)
		check(panel.summary_label.text == "Last RTT -- ms" and panel.details_label.text.contains("Last correction: -- m") and panel.details_label.text.contains("Snapshots received: --"), "Malformed metric stays unavailable")
	panel.show_diagnostics("connected", {}, {})
	check(not panel.title_label.text.contains("HEALTHY"), "Missing measurements do not imply health")
	panel.show_diagnostics("connected", {"rtt_ms":0, "correction_m":0}, context)
	check(panel.summary_label.text.contains("0.0 ms") and panel.details_label.text.contains("0.000 m"), "Explicit zero measurements remain valid")
	panel.show_diagnostics("offline", {}, {"build":"long\n".repeat(100), "mode":object, "phase":"lobby", "physics_ms":INF})
	check(panel.details_label.text.length() < 130 and panel.details_label.text.contains("Mode: --") and panel.details_label.text.contains("Local physics: -- ms"), "Context strings bounded and types validated")
	panel.queue_free()
	await process_frame
	if failures == 0:
		print("NETWORK DIAGNOSTICS PASS")
	quit(0 if failures == 0 else 1)
