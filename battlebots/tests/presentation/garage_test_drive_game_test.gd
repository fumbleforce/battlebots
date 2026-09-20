extends Node
var failures: Array[String] = []
func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func frames() -> void:
	for frame: int in 8: await get_tree().process_frame

func run() -> void:
	Engine.max_fps = 60
	get_window().size = Vector2i(1280, 720)
	var profile := get_node("/root/PlayerProfile")
	var original_path: String = profile.save_path
	var path := "user://test-drive-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	profile.reload()
	check(profile.save_active("Saved test vehicle") == OK, "Seed fixture save succeeds")
	var saved_bytes := FileAccess.get_file_as_bytes(path)
	profile.rename_draft("Unsaved test vehicle")
	var weapon: Dictionary = profile.catalogue.parts[2]
	for category: Dictionary in profile.catalogue.parts:
		if category.slot == "weapon": weapon = category
	for item: Dictionary in weapon.items:
		if item.id == "lifter": profile.equip("parts", weapon, item)
	var paint: Dictionary = profile.catalogue.paint[0]
	for item: Dictionary in paint.items:
		if item.id == "red": profile.equip("paint", paint, item)
	var draft: Dictionary = profile.active_loadout()
	var history: Dictionary = profile._undo_history.duplicate(true)
	check(not draft.is_empty() and draft.name == "Unsaved test vehicle", "Fixture has legal unsaved name, parts and paint")
	var audio_original := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var game: Node = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.hud_settings_path = ""
	game.audio_settings_path = ""
	game.video_settings_path = ""
	game.get_node("Preview").settings_path = ""
	add_child(game)
	await frames()
	for origin: String in ["garage", "customize"]:
		MenuRouter.goto(origin, false)
		await frames()
		var entry: Button = game._test_drive_entry
		check(is_instance_valid(entry) and not entry.disabled, origin + " exposes enabled Test Drive")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			game.screen.apply_text_scale(1.5)
			await frames()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("test-drive-game-" + origin + ".png"))
		game.screen.recovery_panel.open(profile)
		game.start_practice(origin)
		check(game.session.connection_state == "offline", "Recovery modal guards direct entry")
		game.screen.recovery_panel.hide()
		game.open_settings()
		game.start_practice(origin)
		check(game.session.connection_state == "offline", "Settings guards direct entry")
		game.settings_hub.back_button.pressed.emit()
		await frames()
		entry.pressed.emit()
		await frames()
		check(game.session.connection_state == "practice", origin + " starts real practice")
		var bot: MvpBot = game.session.local_source()
		check(bot != null and bot.loadout == draft, "Practice bot uses full unsaved loadout")
		check(game.session.arena_id == preload("res://scripts/arena/arena_scenery.gd").load_choice(), "Test drive honors selected practice arena")
		check(game.preview.controls_enabled and not game.menu_host.visible, "Entry transitions to driving")
		var shortcut := InputEventKey.new()
		shortcut.keycode = KEY_Z
		shortcut.physical_keycode = KEY_Z
		shortcut.ctrl_pressed = true
		shortcut.pressed = true
		Input.parse_input_event(shortcut)
		await frames()
		shortcut = shortcut.duplicate()
		shortcut.pressed = false
		Input.parse_input_event(shortcut)
		await frames()
		check(profile.active_loadout() == draft and profile._undo_history == history, "Hidden build shortcuts cannot edit draft during driving")
		var pause_events: Array[InputEvent] = InputMap.action_get_events("pause")
		InputMap.action_erase_events("pause")
		shortcut = InputEventKey.new()
		shortcut.keycode = KEY_ESCAPE
		shortcut.physical_keycode = KEY_ESCAPE
		shortcut.pressed = true
		Input.parse_input_event(shortcut)
		await frames()
		shortcut = shortcut.duplicate()
		shortcut.pressed = false
		Input.parse_input_event(shortcut)
		for event: InputEvent in pause_events: InputMap.action_add_event("pause", event)
		check(not game.menu_host.visible and game.session.connection_state == "practice", "Hidden menu cannot navigate on unbound Escape")
		game.restart_practice()
		check(bot != null and game.session.local_source() == bot and bot.loadout == draft, "Restart retains exact draft and bot identity")
		check(FileAccess.get_file_as_bytes(path) == saved_bytes, "Entry/restart do not save draft")
		game.preview.release_controls()
		await frames()
		game.open_settings()
		await frames()
		game.settings_hub.back_button.pressed.emit()
		await frames()
		check(not game.menu_host.visible and game.preview.pause_menu.visible and not game.preview.controls_enabled, "In-practice settings returns to pause without reviving hidden workshop")
		check(game.preview.return_button.text == "BACK TO BUILD", "Pause explains return destination")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("test-drive-game-pause.png"))
		game.preview.return_button.pressed.emit()
		await frames()
		check(MenuRouter.current == origin and game.menu_host.visible, "Return restores originating build screen")
		check(game.screen.can_process(), "Returned workshop accepts input again")
		check(game.session.connection_state == "offline" and not game.preview.controls_enabled, "Return leaves practice and releases gameplay input")
		check(profile.active_loadout() == draft and profile._undo_history == history, "Return preserves draft and undo history")
		check(FileAccess.get_file_as_bytes(path) == saved_bytes, "Return does not persist edits")
	profile.loadouts[profile.active_bot].parts.weapon = "unknown"
	profile.inventory_changed.emit()
	await frames()
	check(game._test_drive_entry.disabled, "Invalid draft disables Test Drive")
	game._test_drive_entry.pressed.emit()
	check(game.session.connection_state == "offline", "Invalid entry signal cannot bypass validation")
	profile.loadouts[profile.active_bot] = draft.duplicate(true)
	profile.inventory_changed.emit()
	await frames()
	check(game.session.host(33000 + OS.get_process_id() % 10000, true, 2) == OK, "Fixture starts real existing LAN session")
	await frames()
	game.start_practice("customize")
	check(game.session.connection_state == "hosting", "Test Drive cannot replace live session")
	game.return_to_main()
	await frames()
	game.start_practice()
	await frames()
	check(game.preview.return_button.text == game._default_return_text, "Ordinary Practice retains main-menu return label")
	game.return_to_main()
	await frames()
	check(MenuRouter.current == "main", "Ordinary Practice returns to main")
	game.queue_free()
	await frames()
	audio_original.apply()
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	profile.save_path = original_path
	if failures.is_empty(): print("GARAGE TEST DRIVE GAME PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
