extends Node
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func settle() -> void:
	for _frame: int in 8: await get_tree().process_frame

func scaled(control: Control, factor: float) -> bool:
	return control.has_meta("menu_base_font_size") and control.get_theme_font_size("font_size") == roundi(float(control.get_meta("menu_base_font_size")) * factor)

## Control rect in physical window pixels: canvas-layer transform plus the root's canvas_items stretch.
func window_rect(control: Control) -> Rect2:
	return control.get_viewport().get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)

func run() -> void:
	# The real game's MP3 playback runs on an audio thread, so let teardown advance
	# at the game's render cadence instead of exiting after a few unthrottled ms.
	Engine.max_fps = 60
	get_window().size = Vector2i(1280, 720)
	var path := "user://b-menu-text-game-%d.cfg" % Time.get_ticks_usec()
	var audio_original := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var game: Node = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.hud_settings_path = path
	game.audio_settings_path = ""
	game.video_settings_path = ""
	game.get_node("Preview").settings_path = ""
	add_child(game)
	await settle()
	game.show_screen("customize")
	game.open_settings()
	game.open_hud_settings()
	get_window().size = Vector2i(3840, 2160)
	await settle()
	game.hud_settings.text_scale_choice.select(2)
	game.hud_settings.text_scale_choice.item_selected.emit(2)
	await settle()
	check(scaled(game.screen.get_node("%Save"), 1.5), "Live preference reaches Customize")
	check(scaled(game.preview.settings_panel.invert, 1.5), "Live preference reaches camera settings")
	check(scaled(game.preview.settings_panel.input_panel.mode, 1.5), "Live preference reaches input settings")
	game.hud_settings.cancel()
	await settle()
	check(scaled(game.screen.get_node("%Save"), 1.0) and scaled(game.preview.settings_panel.invert, 1.0), "Cancel restores B menus and control text")
	check(not FileAccess.file_exists(path), "Cancelled preview does not persist")
	game.open_hud_settings()
	game.hud_settings.text_scale_choice.select(2)
	game.hud_settings.text_scale_choice.item_selected.emit(2)
	game.hud_settings.save_and_close()
	await settle()
	check(HudPreferences.load_file(path).text_scale == 1.5, "Explicit Save persists shared preference")
	get_window().size = Vector2i(1280, 720)
	await settle()
	for entry: Button in [game.audio_settings_button, game.hud_settings_button]:
		check(Rect2(0, 0, 1280, 720).encloses(window_rect(entry)), "Settings hub entries remain visible after resize")
	game.queue_free()
	await settle()
	game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.hud_settings_path = path
	game.audio_settings_path = ""
	game.video_settings_path = ""
	game.get_node("Preview").settings_path = ""
	add_child(game)
	await settle()
	for screen_name: String in ["garage", "customize"]:
		game.show_screen(screen_name)
		await settle()
		check(scaled(game.screen.get_node("%Title"), 1.5), screen_name + " receives saved preference on navigation")
		for extent: Vector2i in [Vector2i(1280,720), Vector2i(2560,1080), Vector2i(1280,1024)]:
			get_window().size = extent
			await settle()
			for control: Node in game.screen.find_children("*", "Control", true, false):
				if (control is BaseButton or control is Label) and control.is_visible_in_tree():
					var rect: Rect2 = window_rect(control)
					check(Rect2(Vector2(-1,-1), Vector2(extent) + Vector2(2,2)).encloses(rect), screen_name + " composed responsive bounds " + str(control.name))
	get_window().size = Vector2i(1280,720)
	await settle()
	game.open_settings()
	game._open_settings_category("camera")
	await settle()
	var settings: CameraSettingsPanel = game.preview.settings_panel
	check(scaled(settings.invert, 1.5), "New game loads saved camera text size")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("themed-camera-text-150.png"))
	settings.controls_button.pressed.emit()
	await settle()
	check(scaled(settings.input_panel.mode, 1.5), "New controls page inherits saved text size")
	check(not game.gameplay_input_allowed(), "Enlarged controls preserve gameplay input suppression")
	check(settings.input_panel.is_visible_in_tree(), "Controls open through the real settings navigation")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("themed-controls-text-150.png"))
	for control: Node in settings.find_children("*", "Control", true, false):
		if control is ScrollContainer: check(false, "Control settings must not require scrolling")
		if control is BaseButton and control.is_visible_in_tree():
			check(Rect2(0, 0, 1280, 720).encloses(window_rect(control)), "Themed composed controls fit720p: " + str(control.name))
	game.queue_free()
	await settle()
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	audio_original.apply()
	if failures.is_empty(): print("B MENU TEXT GAME PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
