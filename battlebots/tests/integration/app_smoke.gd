extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
func run() -> void:
	var app = preload("res://scenes/app/mvp.tscn").instantiate()
	root.add_child(app)
	if app.session.connection_state == "offline":
		app.session.practice()
	if app.preview == null:
		app._build_console()
	await frames(3)
	var session: MvpSession = app.session
	check(app.address.text.is_empty(), "Join never defaults to this computer")
	app.address.text = "  "
	app.join_game()
	check(session.connection_state == "practice" and "Enter the address" in app.notice,
		"Empty join explains the host address without leaving the current session")
	var npcs := 3 + session.practice_director.roamers.size()
	check(session.world.get_child_count() == 2 + npcs and session.world.bots.size() == 1 + npcs,
		"One arena, the player, three practice NPCs and the nimble roamers, no duplicate walls")
	check(session.world.arena.find_children("*", "StaticBody3D", true, false).size() == 9,
		"Published arena has one floor, four walls and four chamfers")
	var proxy: SessionBotSource = app.player_source
	var first := session.local_source()
	check(proxy.camera_anchor() == first.camera_anchor(), "Camera uses local bot presentation anchor")
	check(proxy.camera_exclusions().has(first.body.get_rid()), "Camera excludes local body")
	first.combat.core *= 0.5
	app.preview._process(0)
	check(app.preview.hud.rows.get_node("Core/Bar").value == 50, "HUD shows authoritative core damage")
	app.preview.rig.update_camera(1.0 / 60)
	check(app.preview.rig.global_position.distance_to(proxy.camera_anchor().global_position) < 0.01,
		"Orbit camera tracks live anchor")
	# Reset swaps the physical source while retaining the proxy and camera adapter.
	session.leave()
	session.practice(session.registry.starter(true))
	await frames(3)
	var lifter := session.local_source()
	check(lifter != first and proxy.camera_anchor() == lifter.camera_anchor(), "Proxy follows practice replacement")
	app.preview.set_physics_process(false)
	session._input_queue[session.local_entity].clear()
	lifter.combat.charge = 1
	lifter.combat._previous_held = true
	app.preview.open_settings()
	await frames(2)
	check(lifter.command.brake and lifter.command.secondary_held, "Opening settings sends explicit cancel")
	lifter.combat.tick(1.0 / 60, lifter.command, true)
	check(not lifter.combat.launch, "Opening settings never releases a charged lifter")
	var intent := BotCommand.new()
	intent.throttle = 1
	intent.primary_held = true
	proxy.submit_command(intent)
	await frames(2)
	check(lifter.command.throttle == 0 and not lifter.command.primary_held and lifter.command.secondary_held,
		"Modal ticks suppress movement and weapon intent")
	app.preview.settings_panel.cancel()
	app.preview.release_controls()
	await frames(3)
	check(lifter.command.brake and lifter.command.secondary_held, "Focus/menu release remains cancellation")
	# Without a gate, existing consumers retain the original forwarding contract.
	proxy.input_allowed = Callable()
	proxy.submit_command(intent)
	await frames(2)
	check(lifter.command.throttle == 1 and lifter.command.primary_held, "Ungated proxy forwards commands")
	session.leave()
	await frames(2)
	check(proxy.camera_anchor() == proxy and proxy.camera_exclusions().is_empty(), "Disconnected proxy remains safe")
	check(app.console_panel.visible and app.resume_button.disabled, "Disconnected session exposes controls without resume")
	app.queue_free()
	await process_frame
	print("APP INTEGRATION PASS" if failures == 0 else "APP INTEGRATION FAIL")
	quit(0 if failures == 0 else 1)
