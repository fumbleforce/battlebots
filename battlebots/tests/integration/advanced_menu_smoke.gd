extends SceneTree
## Imported mode button -> advanced lobby -> authoritative FFA -> imported main menu.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for index: int in range(count):
		await process_frame

func run() -> void:
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	var router: Node = root.get_node("MenuRouter")
	router.goto("mode_select")
	await frames(3)
	var advanced: Button = game.screen.get_node("%Invite")
	check(not advanced.disabled and advanced.text == "5V5 / FFA PLAYTEST", "Mode screen exposes advanced playtest button")
	# A live session must be closed before replacing the persistent menu owner.
	var port := 31000 + OS.get_process_id() % 10000
	check(game.session.host(port, true, 2) == OK, "Fixture opens prior menu session")
	advanced.pressed.emit()
	advanced.pressed.emit()
	check(game.session.connection_state == "offline" and not game.preview.controls_enabled, "Advanced route releases existing session and controls")
	check(current_scene == game and game.is_inside_tree(), "Button defers scene replacement until input dispatch completes")
	await frames(5)
	var entered := current_scene != null and current_scene.scene_file_path == "res://scenes/app/mvp.tscn"
	check(entered and not is_instance_valid(game), "Advanced button safely replaces imported menu with game shell")
	if entered:
		var app = current_scene
		check(app.session.connection_state == "offline", "Advanced route opens host/join menu without starting practice")
		if app.preview == null:
			app._build_console()
		var index: int = app.player_count_choice.get_item_index(108)
		check(index >= 0, "Advanced menu exposes eight-player FFA")
		if index >= 0:
			app.player_count_choice.select(index)
			app.player_count_choice.item_selected.emit(index)
			app.port = port
			app.host_game()
			await frames(3)
			check(app.session.connection_state == "hosting", "Released port can host selected advanced mode")
			check(app.session.match_mode == "ffa" and app.session.player_capacity == 8, "Advanced selection configures authoritative FFA capacity")
			check(app.session.lobby_view.get("mode") == "ffa" and app.session.lobby_view.get("capacity") == 8, "FFA lobby publishes selected mode and capacity")
		app.return_to_main_menu()
		app.return_to_main_menu()
		check(current_scene == app and app.is_inside_tree(), "Return from advanced menu is deferred and idempotent")
		await frames(5)
		check(not is_instance_valid(app) and current_scene != null and current_scene.scene_file_path == ProjectSettings.get_setting("application/run/main_scene"), "Advanced menu returns to configured main menu")
		check(is_instance_valid(router.host) and router.current == "main", "Imported main menu rebinds its new persistent session")
	if is_instance_valid(router.session):
		router.session.leave()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await frames(3)
	print("ADVANCED MENU PASS" if failures == 0 else "ADVANCED MENU FAIL")
	quit(0 if failures == 0 else 1)
