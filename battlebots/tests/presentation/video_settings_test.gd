extends SceneTree
var failures := 0
var applied_values: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var path := "user://video-test-%d.cfg" % OS.get_process_id()
	var preferences := VideoPreferences.new()
	check(preferences.apply() == ERR_UNAVAILABLE, "Headless does not claim a display switch")
	check(preferences.save_file(path) == OK, "Valid video preferences persist")
	check(VideoPreferences.load_file(path).resolution == preferences.resolution, "Preferences round trip")
	var panel := VideoSettingsPanel.new()
	root.add_child(panel)
	panel.capture_display = func() -> VideoPreferences: return preferences.copy()
	panel.apply_display = func(value: VideoPreferences) -> Error:
		applied_values.append(value.copy())
		return OK
	panel.open_for(preferences, path)
	panel.mode_choice.select(1)
	panel.preview_changes()
	check(panel.deadline_ms > 0 and panel.keep_button.visible, "Preview starts keep/revert confirmation")
	check(VideoPreferences.load_file(path).mode == "windowed", "Unconfirmed preview never persists")
	panel.deadline_ms = Time.get_ticks_msec() - 1
	panel._process(0)
	check(panel.deadline_ms == 0 and applied_values.back().mode == "windowed", "Expired preview restores actual display through adapter")
	panel.mode_choice.select(2)
	panel.preview_changes()
	panel.cancel()
	check(applied_values.back().mode == "windowed" and not panel.visible, "Cancel restores before closing")
	panel.open_for(preferences, path)
	panel.mode_choice.select(1)
	panel.preview_changes()
	panel.confirm()
	check(VideoPreferences.load_file(path).mode == "borderless" and not panel.visible, "Keep persists tested preferences")
	panel.open_for(preferences, "user://missing-video-directory/settings.cfg")
	panel.mode_choice.select(2)
	panel.preview_changes()
	panel.confirm()
	check(panel.visible and panel.deadline_ms == 0 and applied_values.back().mode == "windowed", "Save failure restores display and stays open")
	panel.reset_defaults()
	check(panel.mode_choice.selected == 0, "Defaults remain an editable draft")
	var original_state := {"mode":DisplayServer.WINDOW_MODE_MAXIMIZED, "position":Vector2i(85,45), "size":Vector2i(1536,864), "borderless":true, "vsync":DisplayServer.VSYNC_ADAPTIVE}
	var restored: Array = []
	panel.capture_state = func() -> Dictionary: return original_state.duplicate(true)
	panel.restore_state = func(state: Dictionary) -> Error:
		restored.append(state)
		return OK
	panel.open_for(preferences, path)
	panel.vsync_button.button_pressed = false
	panel.preview_changes()
	panel.cancel()
	check(restored.size() == 1 and restored[0] == original_state, "Rollback adapter preserves physical mode, size, position, borderless flag and exact VSync enum")
	check(panel._original.resolution == preferences.resolution, "Physical capture never replaces saved windowed resolution")
	var malformed := ConfigFile.new()
	malformed.set_value("video", "version", 1)
	malformed.set_value("video", "mode", "unknown")
	malformed.set_value("video", "resolution", Vector2i(1,1))
	malformed.set_value("video", "vsync", true)
	malformed.save(path)
	check(VideoPreferences.load_file(path).load_error != OK, "Invalid persisted settings rejected")
	panel.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Headless transaction adapter; no physical display switching")
	print("VIDEO SETTINGS PASS" if failures == 0 else "VIDEO SETTINGS FAIL")
	quit(0 if failures == 0 else 1)
