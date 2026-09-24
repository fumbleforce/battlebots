extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func frames(count := 4) -> void:
	for index: int in count:
		await process_frame
func run() -> void:
	root.size = Vector2i(1280,720)
	var game: Node3D = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	check(game.menu_host.visible and not game.preview.controls_enabled,"Default supplied main menu is visible without gameplay capture")
	check(game.screen.has_node("%Play"),"Supplied Play button is mounted")
	check(game.menu_host.size.is_equal_approx(Vector2(1920,1080)),"Design keeps logical viewport dimensions")
	var router: Node = root.get_node("MenuRouter")
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	root.push_input(escape)
	await frames()
	check(game.menu_host.visible and not game.preview.controls_enabled, "Escape cannot capture controls behind main menu")
	var play: Button = game.screen.get_node("%Play")
	var click := InputEventMouseButton.new()
	# push_input takes window pixels; map the logical canvas centre through the root stretch transform.
	click.position = root.get_final_transform() * play.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	await frames()
	check(router.current == "mode_select", "Scaled supplied Play button receives real mouse clicks")
	check(not router.SCREENS.has("shop"), "Removed catalogue screen is not routable")
	for key: String in ["main","mode_select","garage","arena_select","lobby","loading","customize"]:
		router.goto(key,false)
		await frames(6)
		check(is_instance_valid(game.screen) and game.screen.get_script() != null,"Menu screen loads with script: " + key)
		check(game.screen.size.is_equal_approx(Vector2(1920,1080)),"Screen fits logical viewport: " + key)
		if key == "loading":
			root.push_input(escape)
			await frames()
			check(game.menu_host.visible and not game.preview.controls_enabled, "Escape cannot capture controls behind loading")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://menu-kit-" + key + ".png")
	router.goto("main",false)
	await frames()
	game.screen.get_node("%Settings").pressed.emit()
	await frames()
	check(game.settings_hub.visible and not game.menu_host.visible,"Supplied Settings opens real preferences")
	game.settings_hub.back_button.pressed.emit()
	await frames()
	check(game.menu_host.visible and not game.preview.controls_enabled,"Settings returns to menu without starting gameplay")
	var profile: Node = root.get_node("PlayerProfile")
	profile.active_bot = 1
	router.start_practice()
	await frames(12)
	check(game.session.connection_state == "practice" and not game.menu_host.visible,"Menu starts actual Practice")
	check(game.session.local_source() != null,"Practice has a physical bot")
	if game.session.local_source() != null:
		check(game.session.local_source().combat.stats.weapon == "lifter","Selected Controller reaches actual physics assembly")
	check(game.gameplay_input_allowed(),"Gameplay controls enabled after menu transition")
	game.session.leave()
	game.session.session_event.emit("error", {"message":"Server disconnected; match incomplete"})
	await frames()
	check(game.menu_host.visible and game.screen.get_node("%StatusSub").text.contains("match incomplete"),
		"Session error survives transition from arena into replacement lobby")
	game.return_to_main()
	await frames()
	check(game.session.connection_state == "offline" and game.menu_host.visible,"Explicit return closes session and restores supplied menu")
	game.queue_free()
	await frames()
	print("MENU KIT PASS" if failures == 0 else "MENU KIT FAIL")
	quit(0 if failures == 0 else 1)
