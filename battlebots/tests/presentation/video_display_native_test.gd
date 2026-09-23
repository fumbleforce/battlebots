extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count := 15) -> void:
	for i: int in count: await process_frame
func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Physical display test requires a native display")
		quit(1)
		return
	var initial := VideoPreferences.capture_display_state()
	var path := "user://display-native-%d.cfg" % OS.get_process_id()
	var original := VideoPreferences.capture()
	original.mode = "windowed"
	original.resolution = Vector2i(1280,720)
	original.apply()
	await frames()
	var frame := SettingsCategoryFrame.new()
	root.add_child(frame)
	var panel := VideoSettingsPanel.new()
	frame.add_child(panel)
	for mode: int in [1,2]:
		panel.open_for(original,path)
		panel.mode_choice.select(mode)
		panel.preview_changes()
		await frames()
		check(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN],"Real fullscreen switch applies")
		panel.deadline_ms = Time.get_ticks_msec()-1
		panel._process(0)
		await frames()
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED,"Timeout restores real window mode")
		check(DisplayServer.window_get_size() == Vector2i(1280,720),"Timeout restores real window size")
		check(not FileAccess.file_exists(path),"Unconfirmed physical preview never saves")
		panel.cancel()
	if DisplayServer.get_screen_count() > 1:
		var original_screen := DisplayServer.window_get_current_screen()
		var target_screen := (original_screen+1)%DisplayServer.get_screen_count()
		panel.open_for(original,path)
		panel.monitor_choice.select(target_screen+1)
		panel.preview_changes()
		await frames()
		check(DisplayServer.window_get_current_screen() == target_screen,"Monitor selection moves the real window")
		panel.cancel()
		await frames()
		check(DisplayServer.window_get_current_screen() == original_screen,"Cancel restores original monitor")
	panel.open_for(original,path)
	panel.resolution_choice.select(1)
	panel.vsync_button.button_pressed = not original.vsync
	panel.preview_changes()
	await frames()
	check(DisplayServer.window_get_size().x >= 1280,"Window resolution request applies within usable display")
	panel.cancel()
	await frames()
	check(DisplayServer.window_get_size() == Vector2i(1280,720),"Cancel restores physical resolution")
	check((DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED) == original.vsync,"Cancel restores physical V-Sync")
	panel.open_for(original,path)
	panel.vsync_button.button_pressed = not original.vsync
	panel.preview_changes()
	await frames()
	panel.confirm()
	check(FileAccess.file_exists(path) and VideoPreferences.load_file(path).vsync != original.vsync,"Confirmed physical preference persists")
	frame.queue_free()
	await frames(2)
	VideoPreferences.restore_display_state(initial)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("DISPLAY PLATFORM: ",DisplayServer.get_name()," screens=",DisplayServer.get_screen_count())
	print("VIDEO DISPLAY NATIVE PASS" if failures == 0 else "VIDEO DISPLAY NATIVE FAIL")
	quit(0 if failures == 0 else 1)
