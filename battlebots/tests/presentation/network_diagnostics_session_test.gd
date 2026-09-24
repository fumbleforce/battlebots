extends SceneTree
const FreePort := preload("res://tests/fixtures/free_port.gd")
## B-owned integration fixture: actual ENet snapshots drive the read-only widget.
var failures := 0
var views: Array[SubViewport] = []
var peers: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable, limit := 1500) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await process_frame
	return false

func make_peer(label: String) -> Dictionary:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.handle_input_locally = true
	root.add_child(view)
	set_multiplayer(SceneMultiplayer.new(), view.get_path())
	var container := Node3D.new()
	container.name = "Fixture"
	var session := MvpSession.new()
	session.name = "Session"
	container.add_child(session)
	var source := SessionBotSource.new()
	source.name = "Source"
	source.session_path = NodePath("../Session")
	container.add_child(source)
	var preview = preload("res://scenes/ui/baseline_preview.tscn").instantiate()
	preview.name = "Preview"
	preview.source_path = NodePath("../Source")
	preview.settings_path = ""
	container.add_child(preview)
	view.add_child(container)
	preview.set_physics_process(false)
	preview.network_diagnostics.expanded = true
	var peer := {"session":session, "preview":preview, "view":view}
	views.append(view)
	peers.append(peer)
	return peer

func text_for(peer: Dictionary) -> String:
	peer.preview.refresh_diagnostics()
	var panel = peer.preview.network_diagnostics
	return "%s\n%s\n%s" % [panel.title_label.text, panel.summary_label.text, panel.details_label.text]

func run() -> void:
	var host := make_peer("Server")
	var client := make_peer("Client")
	var port := FreePort.udp()
	check(host.session.host(port, true, 2) == OK, "Diagnostic fixture binds real listen-server UDP")
	check(client.session.join("127.0.0.1", port) == OK, "Diagnostic fixture starts real client")
	var admitted := await until(func() -> bool: return client.session.local_entity > 0)
	check(admitted, "Diagnostic client admitted over ENet")
	if admitted:
		host.session.set_ready(true)
		client.session.set_ready(true)
		check(await until(func() -> bool: return client.session.match_view.get("phase") == "active"),
			"Diagnostic peers reach active match")
		check(await until(func() -> bool: return client.session.diagnostics.snapshots_received > 4),
			"Actual snapshots arrive while player input collector is disabled")
		var count: int = client.session.diagnostics.snapshots_received
		check(await until(func() -> bool: return client.session.diagnostics.snapshots_received > count + 4),
			"Idle player continues receiving snapshots")
		var host_before: Dictionary = host.session.diagnostics.duplicate(true)
		var client_before: Dictionary = client.session.diagnostics.duplicate(true)
		var host_text := text_for(host)
		var client_text := text_for(client)
		check(host_text.to_lower().contains("host"), "Live host is labelled as host")
		check(host_text.contains("Rejected inputs: %d" % host.session.diagnostics.rejected_inputs) \
			and host_text.contains("Largest snapshot packet: %d B" % host.session.diagnostics.snapshot_bytes),
			"Host display reads actual server-side counters")
		check(client_text.to_lower().contains("connected"), "Admitted client is labelled connected")
		check(host.session.diagnostics == host_before and client.session.diagnostics == client_before,
			"Refreshing presentation never mutates live diagnostic dictionaries")
		check(client_text.contains("Snapshots received: %d" % client.session.diagnostics.snapshots_received),
			"Client expanded details expose the current actual snapshot count")
		check(client_text.contains("Last RTT %.1f ms" % client.session.diagnostics.rtt_ms) \
			and client_text.contains("Last correction: %.3f m" % client.session.diagnostics.correction_m),
			"Client display uses the actual current transport measurements")
		check(client_text.contains(WireCodec.BUILD) and client_text.contains("Local physics:"),
			"Adapter supplies build identifier and explicitly local physics timing")
		client.preview.capture_controls()
		client.preview.input_gate.toggle_primary = true
		client.preview.input_gate.sample({}, {}, true)
		check(client.preview.input_gate.sample({"primary":1.0}, {"primary":true}, true).primary_held,
			"Fixture arms a toggled weapon before diagnostic interaction")
		client.preview.network_diagnostics.details_button.grab_focus()
		var was_expanded: bool = client.preview.network_diagnostics.expanded
		var accept_down := InputEventKey.new()
		accept_down.keycode = KEY_ENTER
		accept_down.pressed = true
		client.view.push_input(accept_down, true)
		var accept_up := InputEventKey.new()
		accept_up.keycode = KEY_ENTER
		accept_up.pressed = false
		client.view.push_input(accept_up, true)
		check(client.preview.network_diagnostics.expanded != was_expanded,
			"Keyboard accept reaches diagnostic detail button through its viewport")
		check(not client.preview.controls_enabled \
			and not client.preview.input_gate.sample({}, {}, true).primary_held,
			"Opening diagnostic details releases gameplay and clears weapon latch")
		client.preview.get_node("CanvasLayer").hide()
		client.preview.refresh_diagnostics()
		check(client.preview.network_diagnostics.is_visible_in_tree(),
			"Network status survives A hiding the gameplay CanvasLayer")
		client.preview.open_settings()
		client.preview.refresh_diagnostics()
		check(not client.preview.network_diagnostics.visible, "Settings suppress network overlay")
		client.preview.settings_panel.cancel()
		client.preview.refresh_diagnostics()
		check(client.preview.network_diagnostics.visible, "Closing settings restores network overlay")
		# Use the public unreliable-packet impairment fixture, never forge live metrics.
		host.session.network_simulation.loss = 1.0
		check(await until(func() -> bool: return client.session.diagnostics.get("degraded", false), 300),
			"Snapshot starvation produces actual degraded transport diagnostics")
		check(text_for(client).to_lower().contains("degraded"), "Actual degraded connection is visible")
		host.session.network_simulation.loss = 0.0
		check(await until(func() -> bool: return not client.session.diagnostics.get("degraded", true), 300),
			"Delivery recovery clears actual degraded flag")
		check(not text_for(client).to_lower().contains("degraded"), "Recovered connection clears stale warning")
	client.session.leave()
	var offline_text := text_for(client).to_lower()
	check(offline_text.contains("offline"), "Leave renders offline immediately")
	check(not offline_text.contains("rtt") and not offline_text.contains("correction"),
		"Offline presentation omits retained historical RTT and correction")
	check(client.session.join("127.0.0.1", port) == OK, "Same node can request a new connection")
	var connecting_text := text_for(client).to_lower()
	check(connecting_text.contains("connecting") and not connecting_text.contains("rtt") \
		and not connecting_text.contains("correction"), "Rejoin immediately hides previous connection telemetry")
	client.session.leave()
	await process_frame
	check(client.session.practice() == OK, "Same diagnostic peer can enter local practice")
	var practice_text := text_for(client).to_lower()
	check(practice_text.contains("practice"), "Practice identified as local play")
	check(not practice_text.contains("rtt") and not practice_text.contains("correction"),
		"Practice omits old remote transport measurements")
	for peer: Dictionary in peers:
		peer.session.leave()
	# Reverse destruction preserves nested InputMap snapshots without touching user files.
	for index: int in range(views.size() - 1, -1, -1):
		views[index].free()
	await process_frame
	print("NETWORK DIAGNOSTICS SESSION PASS" if failures == 0 else "NETWORK DIAGNOSTICS SESSION FAIL")
	quit(0 if failures == 0 else 1)
