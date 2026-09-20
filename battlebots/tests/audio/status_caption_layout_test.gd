extends SceneTree
## Actual game composition and shaped multi-line captions at supported sizes.
var failures := 0
const CAPTION := "Core integrity low · Recovery activated · Armor breached: front, rear, left, right"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 8) -> void:
	for index in count:
		await process_frame

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	game.start_practice()
	await frames(30)
	game.set_process(false)
	var label: Label = game._audio_caption
	var combat: CombatHud = game.combat_hud
	var bot := BotView.new()
	bot.entity_id = 1
	bot.core_fraction = 0.1
	bot.immobilized_remaining = 4.2
	bot.zones = {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}
	for extent in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = extent
		for text_scale in [1.0, 1.5]:
			var preferences = game.hud_preferences.copy()
			preferences.text_scale = text_scale
			game._apply_hud_preferences(preferences)
			for practice in [false, true]:
				combat.render(bot, "T", bot, practice)
				game.match_hud.render({"phase": "active", "round": 999, "remaining": 180, "scores": [999, 999]}, practice, 0)
				game.practice_hud.hide()
				game.gameplay_audio.caption_changed.emit(CAPTION)
				await frames()
				var bounds := combat.caption_bounds()
				var occupied := label.get_global_rect()
				var actual_height := float(label.get_line_count() * label.get_line_height()) + maxf(0, label.get_line_count() - 1) * label.get_theme_constant("line_spacing")
				check(label.get_line_count() > 1 and label.get_visible_line_count() == label.get_line_count(), "Every shaped caption line is visible")
				check(actual_height <= bounds.size.y and label.size.y <= bounds.size.y + 0.1, "Caption text height fits allocated region at %s/%s: %s" % [extent, text_scale, str(actual_height) + " size " + str(label.size)])
				check(label.text == CAPTION and label.visible_characters == -1 and label.max_lines_visible == -1, "Caption preserves all critical messages without truncation")
				check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(occupied), "Caption stays inside viewport")
				for panel in combat.panels:
					check(not occupied.intersects(panel.get_global_rect()), "Caption avoids combat panels")
				for other in [combat.recovery_label, combat.warning_label, game.match_hud.get_node("Panel"), game.preview.network_diagnostics]:
					check(not occupied.intersects(other.get_global_rect()), "Caption avoids %s at %s/%s: caption %s, other %s" % [other.name, extent, text_scale, occupied, other.get_global_rect()])
				check(not game.practice_hud.visible, "Composition keeps redundant practice target readout hidden")
				if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("user://a-status-caption-%d-%d-%s.png" % [extent.x, roundi(text_scale * 100), practice])
	game.return_to_main()
	game.queue_free()
	await frames()
	print("STATUS_CAPTION_LAYOUT_PASS" if failures == 0 else "STATUS_CAPTION_LAYOUT_FAIL")
	quit(0 if failures == 0 else 1)
