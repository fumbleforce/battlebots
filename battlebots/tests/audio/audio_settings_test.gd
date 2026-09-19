extends SceneTree
var failures := 0
var finished_values: Array[bool] = []
var published: Array[AudioPreferences] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)

func frames() -> void:
	await process_frame
	await process_frame

func run() -> void:
	var directory := "user://audio-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_absolute(directory) == OK, "Unique audio test directory created")
	var path := directory + "/settings.cfg"
	var original_layout := AudioServer.generate_bus_layout()
	var defaults := AudioPreferences.new()
	var missing := AudioPreferences.load_file(path)
	check(missing.load_error == OK and missing.master == defaults.master and not FileAccess.file_exists(path), "Missing file returns defaults without creating it")
	check(AudioPreferences.load_file("").load_error != OK and defaults.save_file("res://forbidden.cfg") != OK and defaults.save_file("user://../forbidden.cfg") != OK, "Invalid paths rejected before filesystem access")
	var prefs := AudioPreferences.new()
	prefs.master = 0.42
	prefs.music = 0.23
	prefs.effects = 0.64
	prefs.announcements = 0.91
	prefs.muted = true
	check(prefs.save_file(path) == OK, "Preferences save atomically")
	var loaded := AudioPreferences.load_file(path)
	for key: String in AudioPreferences.DEFAULTS:
		check(is_equal_approx(loaded.get(key), prefs.get(key)), "Saved gain round trips: " + key)
	check(loaded.muted and loaded.load_error == OK, "Mute flag round trips")
	var detached := prefs.copy()
	detached.music = 0.8
	check(prefs.music == 0.23, "Copy edits do not change caller preferences")
	var saved_text := FileAccess.get_file_as_string(path)
	prefs.master = NAN
	check(prefs.save_file(path) == ERR_INVALID_DATA and FileAccess.get_file_as_string(path) == saved_text, "NaN cannot overwrite valid saved settings")
	prefs.apply()
	check(is_equal_approx(AudioServer.get_bus_volume_linear(0), defaults.master), "Invalid in-memory gain applies finite fallback")
	prefs = loaded.copy()
	for invalid: Variant in [NAN, INF, -0.01, 1.01, "loud", true]:
		var config := ConfigFile.new()
		config.load(path)
		config.set_value("audio", "effects", invalid)
		check(config.save(path) == OK, "Invalid-value fixture saved")
		var before := FileAccess.get_file_as_string(path)
		var sanitized := AudioPreferences.load_file(path)
		check(sanitized.load_error != OK and sanitized.effects == defaults.effects and sanitized.master == defaults.master, "Invalid schema returns a complete default record")
		check(FileAccess.get_file_as_string(path) == before, "Invalid file is never changed on load")
		prefs.save_file(path)
	var unknown := ConfigFile.new()
	unknown.load(path)
	unknown.set_value("audio", "version", 99)
	unknown.save(path)
	check(AudioPreferences.load_file(path).load_error == ERR_FILE_UNRECOGNIZED, "Unknown version remains recoverable")
	prefs.save_file(path)
	AudioPreferences.ensure_buses()
	var count := AudioServer.bus_count
	AudioPreferences.ensure_buses()
	check(AudioServer.bus_count == count, "Bus creation is idempotent")
	prefs.apply()
	for key: String in AudioPreferences.BUSES:
		var bus := AudioServer.get_bus_index(AudioPreferences.BUSES[key])
		check(bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_linear(bus), prefs.get(key)), "Correct linear bus gain: " + key)
		if key != "master":
			check(AudioServer.get_bus_send(bus) == &"Master", "Category bus sends to Master")
	check(AudioServer.is_bus_mute(0), "Mute uses Master bus")
	prefs.muted = false
	prefs.apply()
	var panel := AudioSettingsPanel.new()
	root.add_child(panel)
	panel.position = Vector2(30, 30)
	panel.size = Vector2(484, 560)
	panel.finished.connect(func(saved: bool) -> void: finished_values.append(saved))
	panel.applied.connect(func(value: AudioPreferences) -> void: published.append(value))
	panel.open_for(prefs, path)
	await frames()
	check(panel.size.x <= 500 and panel.size.y <= 640, "Audio panel fits existing settings dimensions")
	check(root.gui_get_focus_owner() == panel.sliders.master, "Opening focuses Master slider")
	for control: Control in [panel.sliders.master, panel.sliders.music, panel.sliders.effects, panel.sliders.announcements, panel.mute_button, panel.save_button, panel.cancel_button, panel.defaults_button]:
		check(panel.get_global_rect().encloses(control.get_global_rect()), "Actual settings control fits panel")
		check(control.get_node(control.focus_next) is Control and control.get_node(control.focus_previous) is Control, "Keyboard focus links resolve")
	panel.sliders.music.value = 0.12
	panel.mute_button.button_pressed = true
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("BBMusic")), 0.12) and AudioServer.is_bus_mute(0), "Real controls preview gains and mute")
	panel.cancel_button.pressed.emit()
	check(not panel.visible and finished_values == [false] and published.is_empty(), "Cancel closes without publication")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("BBMusic")), prefs.music) and not AudioServer.is_bus_mute(0), "Cancel restores original bus gains and mute")
	panel.open_for(prefs, directory + "/missing/settings.cfg")
	panel.sliders.effects.value = 0.3
	panel.save_button.pressed.emit()
	check(panel.visible and panel.message.text.contains("Could not save") and finished_values.size() == 1 and published.is_empty(), "Failed save stays open without reporting success")
	panel.cancel()
	panel.open_for(prefs, path)
	panel.defaults_button.pressed.emit()
	check(is_equal_approx(AudioServer.get_bus_volume_linear(0), defaults.master), "Defaults preview immediately")
	panel.sliders.announcements.value = 0.37
	panel.save_button.pressed.emit()
	check(not panel.visible and published.size() == 1 and finished_values.back(), "Successful save publishes and closes once")
	check(is_equal_approx(AudioPreferences.load_file(path).announcements, 0.37) and prefs.announcements == 0.91, "Saved draft persisted without mutating caller object")
	panel.open_for(prefs, path)
	panel.sliders.master.value = 0.1
	panel.queue_free()
	await frames()
	check(is_equal_approx(AudioServer.get_bus_volume_linear(0), prefs.master), "Removing an open panel restores previewed audio")
	AudioServer.set_bus_layout(original_layout)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("AUDIO SETTINGS PASS" if failures == 0 else "AUDIO SETTINGS FAIL")
	quit(0 if failures == 0 else 1)
