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

func check_health(game: Node, view: BotView) -> void:
	var marker: Label3D = game.world_markers.markers[view.entity_id]
	var bar := marker.get_node("HealthBar") as Sprite3D
	check(bar != null and bar.is_visible_in_tree(), "Actual practice shows health for local bot and target")
	if bar == null: return
	var width := roundi(view.core_fraction * 124)
	check(bar.fixed_size and bar.offset.y < 0, "Health bar has fixed screen size and sits below name")
	check(bar.get_meta("green_width") == width, "Green fill matches detached authoritative core fraction")
	var pixels := bar.texture.get_image()
	check(pixels.get_size() == Vector2i(128, 12), "Health texture retains its fixed dimensions")
	# The headless renderer retains the initial texture image after update().
	# Native readback verifies the rendered colors; both paths verify fill metadata.
	if DisplayServer.get_name() != "headless":
		if width > 0: check(pixels.get_pixel(2, 6).is_equal_approx(BotWorldMarkers.HEALTH_GREEN), "Remaining health is green")
		if width < 124: check(pixels.get_pixel(2 + width, 6).is_equal_approx(BotWorldMarkers.HEALTH_RED), "Lost health is red")

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
	check(game.world_markers.markers[local_id].text.is_empty() and game.world_markers.markers[target_id].text.contains("TARGET"), "Practice retains target identity without a redundant local floating tag")
	check(not game.world_markers.markers[local_id].get_node("Leader").visible and game.world_markers.markers[target_id].get_node("Leader").visible, "Only target retains the floating identity stem")
	check_health(game, game.session.local_source().read_view())
	check_health(game, target.read_view())
	var initial: Vector3 = game.world_markers.markers[local_id].global_position
	# Isolate fixture commands from the live keyboard adapter's neutral commands.
	game.preview.set_physics_process(false)
	for step: int in range(90):
		var command := BotCommand.new()
		command.sequence = step
		command.throttle = -1.0
		game.session.submit_local(command)
		await physics_frame
	game.preview.set_physics_process(true)
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
	# Exercise the real authoritative producer, then let normal game rendering consume views.
	var target_bot := target as MvpBot
	var local_bot := game.session.local_source() as MvpBot
	check(target_bot != null and local_bot != null, "Practice exposes real combat bots")
	for actual: MvpBot in [target_bot, local_bot]:
		var label: Label3D = game.world_markers.markers[actual.entity_id]
		var rear_top: float = 1.57 * actual.combat.stats.size.z / 2.6 - actual.combat.stats.size.y * 0.5
		check(label.global_position.y > actual.read_view().pose.origin.y + rear_top,
			"Actual practice badge clears its enlarged authored rear pack")
	target_bot.combat.damage("top", target_bot.combat.stats.core * 0.5 / 0.95)
	local_bot.combat.damage("top", local_bot.combat.stats.core * 0.25 / 0.95)
	await frames()
	check(is_equal_approx(target.read_view().core_fraction, 0.5), "Practice target damage reaches detached view")
	check(is_equal_approx(local_bot.read_view().core_fraction, 0.75), "Local damage reaches detached view")
	check_health(game, target.read_view())
	check_health(game, local_bot.read_view())
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
	game.settings_hub.back_button.pressed.emit()
	game.restart_practice()
	await frames()
	check(game.world_markers.visible, "Resumed practice restores markers")
	var restored_target: BotView = game.session.practice_target().read_view()
	var restored_local: BotView = game.session.local_source().read_view()
	check(restored_target.core_fraction == 1.0 and restored_local.core_fraction == 1.0, "Practice reset restores authoritative health")
	check_health(game, restored_target)
	check_health(game, restored_local)
	game.return_to_main()
	await frames()
	check(not game.world_markers.visible and game.world_markers.markers.is_empty(), "Leave removes stale identities")
	game.queue_free()
	await frames()
	print("WORLD MARKERS GAME PASS" if failures == 0 else "WORLD MARKERS GAME FAIL")
	quit(0 if failures == 0 else 1)
