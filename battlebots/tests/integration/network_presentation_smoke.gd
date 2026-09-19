extends SceneTree
var failures := 0
var views: Array[SubViewport] = []
var apps: Array[Node] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count: int) -> void:
	for index: int in range(count):
		await process_frame
func until(predicate: Callable, limit := 1500) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await process_frame
	return false
func make_app(label: String) -> Node:
	var view := SubViewport.new()
	view.name = label
	view.own_world_3d = true
	root.add_child(view)
	set_multiplayer(SceneMultiplayer.new(), view.get_path())
	var app = preload("res://scenes/app/mvp.tscn").instantiate()
	view.add_child(app)
	app.session.leave()
	views.append(view)
	apps.append(app)
	return app
func run() -> void:
	var port := 28000 + OS.get_process_id() % 10000
	var host = make_app("Server")
	host.port = port
	host.host_game()
	check(host.session.connection_state == "hosting", "Menu host binds requested UDP port")
	# Test dedicated four-client admission after exercising the listen-host action.
	host.session.leave()
	check(host.session.host(port, false) == OK, "Integrated server binds")
	var clients: Array[Node] = []
	for index: int in range(4):
		var app = make_app("Client%d" % index)
		app._build_console()
		app.preview.set_physics_process(false)
		clients.append(app)
		app.port = port
		app.address.text = " 127.0.0.1 "
		app.join_game()
		check(app.session.connection_state == "connecting", "Menu join trims address and uses requested UDP port")
	check(await until(func() -> bool: return clients.all(func(app: Node) -> bool: return app.session.local_entity > 0)), "Four clients admitted")
	for app: Node in clients:
		app.session.set_ready(true)
	check(await until(func() -> bool: return clients.all(func(app: Node) -> bool: return app.session.match_view.get("phase") == "active")), "Four presentation clients reach active")
	for app: Node in clients:
		check(app.player_source.camera_anchor() == app.session.local_source().camera_anchor(), "Network baseline binds proxy camera")
		check(app.preview.rig.source == app.player_source, "B camera uses session proxy")
	var driver = clients[0]
	var entity: int = driver.session.local_entity
	var before: Vector3 = host.session.world.bots[entity].body.global_position
	driver.player_source.input_allowed = Callable()
	for frame: int in range(90):
		var command := BotCommand.new()
		command.throttle = 1
		driver.player_source.submit_command(command)
		await process_frame
	check(host.session.world.bots[entity].body.global_position.distance_to(before) > 1,
		"B-facing proxy moves only its owned server bot over real UDP")
	host.session.world.bots[entity].combat.core *= 0.5
	check(await until(func() -> bool: return driver.player_source.read_view().core_fraction < 0.6, 300), "Authoritative damage reaches presentation proxy")
	driver.preview._process(0)
	check(driver.preview.hud.rows.get_node("Core/Bar").value <= 60, "Network HUD reflects server health")
	driver.session.leave()
	await frames(3)
	check(driver.console_panel.visible and driver.resume_button.disabled, "Network leave exposes session controls")
	for app: Node in apps:
		app.session.leave()
	for view: SubViewport in views:
		view.queue_free()
	await process_frame
	print("PRESENTATION NETWORK PASS" if failures == 0 else "PRESENTATION NETWORK FAIL")
	quit(0 if failures == 0 else 1)
