extends SceneTree
## Actual practice composition, camera and public command/view integration.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 8) -> void:
	for index: int in range(count):
		await process_frame

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	check(not game.world_markers.visible and game.world_markers.markers.is_empty(), "Main menu has no world badges")
	game.start_practice()
	await frames(45)
	var local_id: int = game.session.local_entity
	var target: BotSource = game.session.practice_target()
	var target_id: int = target.read_view().entity_id
	check(game.world_markers.visible and game.world_markers.markers.size() == 2, "Actual practice supplies both world identities")
	check(game.world_markers.markers[local_id].text.contains("YOU") and game.world_markers.markers[target_id].text.contains("TARGET"), "Practice target does not need a lobby roster entry")
	var initial: Vector3 = game.world_markers.markers[local_id].global_position
	for step: int in range(90):
		var command := BotCommand.new()
		command.sequence = step
		command.throttle = -1.0
		game.session.submit_local(command)
		await physics_frame
	await frames()
	game._update_world_markers()
	var local: BotView = game.session.local_source().read_view()
	var badge: Label3D = game.world_markers.markers[local_id]
	check(badge.global_position.distance_to(initial) > 0.1, "Badge follows actual bot motion")
	check(is_equal_approx(badge.global_position.x, local.pose.origin.x) and is_equal_approx(badge.global_position.z, local.pose.origin.z) and badge.global_position.y > local.pose.origin.y, "Badge tracks the displayed pose above the bot")
	var base_size := badge.font_size
	var large = game.hud_preferences.copy()
	large.text_scale = 1.5
	large.palette = "deuteranopia"
	large.high_contrast = true
	game._apply_hud_preferences(large)
	await frames()
	check(badge.font_size == roundi(base_size * 1.5), "HUD accessibility also enlarges world labels")
	for extent: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = extent
		await frames()
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://a-world-markers-game-%d.png" % extent.x)
	game.preview.release_controls()
	await frames()
	check(not game.world_markers.visible, "Game menu suppresses world labels")
	game.open_settings()
	await frames()
	check(not game.world_markers.visible, "Settings suppress world labels")
	game.preview.settings_panel.cancel()
	game.restart_practice()
	await frames()
	check(game.world_markers.visible, "Resumed practice restores markers")
	game.return_to_main()
	await frames()
	check(not game.world_markers.visible and game.world_markers.markers.is_empty(), "Leave removes stale identities")
	game.queue_free()
	await frames()
	print("WORLD MARKERS GAME PASS" if failures == 0 else "WORLD MARKERS GAME FAIL")
	quit(0 if failures == 0 else 1)
