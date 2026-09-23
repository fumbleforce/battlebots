extends SceneTree
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

func find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child: Node in node.get_children():
		var found := find_scroll(child)
		if found != null:
			return found
	return null

func run() -> void:
	var extents: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
	if DisplayServer.get_name() == "headless":
		extents.append(Vector2i(3840, 2160))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var options := OptionButton.new()
	options.add_item("A long readable option")
	options.add_theme_font_size_override("font_size", 20)
	root.add_child(options)
	var popup_base := options.get_popup().get_theme_font_size("font_size")
	MenuTextScale.apply(options, 1.5)
	MenuTextScale.apply(options, 1.5)
	check(options.get_theme_font_size("font_size") == 30, "Repeated scaling does not compound")
	check(options.get_popup().get_theme_font_size("font_size") == roundi(popup_base * 1.5), "Popup choices scale too")
	MenuTextScale.apply(options, 1.0)
	check(options.get_theme_font_size("font_size") == 20, "Default size is restored")
	options.queue_free()
	var path := "user://menu-text-test-%d.cfg" % OS.get_process_id()
	var audio_original := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.hud_settings_path = path
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	game.open_settings()
	game.open_hud_settings()
	var base_option_size: int = game.hud_settings.text_scale_choice.get_theme_font_size("font_size")
	game.hud_settings.text_scale_choice.select(2)
	game.hud_settings.text_scale_choice.item_selected.emit(2)
	await frames()
	check(game._menu_text_scale == 1.5 and game.hud_preferences.text_scale == 1.0, "Draft affects presentation without publishing")
	check(game.hud_settings.text_scale_choice.get_theme_font_size("font_size") == roundi(base_option_size*1.5), "Accessibility controls enlarge themselves")
	check(game.hud_settings.sample_label.get_theme_font_size("font_size") == 30, "Sample is not scaled twice")
	for extent: Vector2i in extents:
		root.size = extent
		await frames()
		var scroll := find_scroll(game._hud_overlay)
		game.hud_settings.save_button.grab_focus()
		await frames()
		check(scroll != null and scroll.follow_focus, "Accessibility body scrolls with keyboard focus while actions remain outside")
		check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(game.hud_settings.get_global_rect()), "Whole enlarged category fits screen")
		check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(game.hud_settings.save_button.get_global_rect()), "Save stays visible at enlarged size")
		check(not game.gameplay_input_allowed(), "Enlarged settings remain modal")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://a-menu-text-settings-%d.png" % extent.x)
	game.hud_settings.cancel()
	await frames()
	check(game._menu_text_scale == 1.0 and game.hud_settings.text_scale_choice.get_theme_font_size("font_size") == base_option_size, "Cancel restores menu and settings text")
	check(not FileAccess.file_exists(path), "Cancelled preview does not save")
	game.open_hud_settings()
	game.hud_settings.text_scale_choice.select(2)
	game.hud_settings.text_scale_choice.item_selected.emit(2)
	game.hud_settings.save_and_close()
	await frames()
	check(HudPreferences.load_file(path).text_scale == 1.5, "Saved text preference persists")
	root.size = Vector2i(1280, 720)
	await frames()
	for entry: Button in [game.audio_settings_button, game.hud_settings_button]:
		check(entry.get_theme_font_size("font_size") == roundi(float(entry.get_meta("menu_base_font_size")) * 1.5), "A-owned settings entry scales")
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(entry.get_global_rect()), "Enlarged settings entry fits720p")
	game.open_audio_settings()
	await frames()
	check(game.audio_settings.save_button.get_theme_font_size("font_size") == roundi(float(game.audio_settings.save_button.get_meta("menu_base_font_size")) * 1.5), "Audio settings consume saved size")
	game.audio_settings.cancel()
	game.queue_free()
	await frames()
	var reloaded = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	reloaded.hud_settings_path = path
	reloaded.audio_settings_path = ""
	reloaded.get_node("Preview").settings_path = ""
	root.add_child(reloaded)
	await frames()
	check(reloaded._menu_text_scale == 1.5, "New game loads saved text size")
	check(reloaded.screen.has_method("apply_text_scale"), "Main menu supports the text preference")
	var play := reloaded.screen.get_node("%Play") as Button
	check(play.get_theme_font_size("font_size") == roundi(float(play.get_meta("menu_base_font_size")) * 1.5), "Reloaded main menu uses saved size")
	reloaded.show_screen("online")
	await frames()
	var create: Button = reloaded.screen.create_button
	check(create.get_theme_font_size("font_size") == roundi(float(create.get_meta("menu_base_font_size")) * 1.5), "Newly navigated online screen receives saved text size")
	reloaded.queue_free()
	await frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	audio_original.apply()
	print("MENU TEXT SETTINGS PASS" if failures == 0 else "MENU TEXT SETTINGS FAIL")
	quit(0 if failures == 0 else 1)
