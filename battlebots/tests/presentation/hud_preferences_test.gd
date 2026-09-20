extends SceneTree
var failures := 0

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)

func _initialize() -> void:
	var directory := "user://hud-prefs-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_absolute(directory) == OK, "Unique fixture directory")
	var path := directory + "/hud.cfg"
	var preferences := HudPreferences.new()
	check(HudPreferences.load_file(path).load_error == OK and not FileAccess.file_exists(path), "Missing file returns defaults without writing")
	for bad_path: String in ["", "res://hud.cfg", "user://../hud.cfg", "relative.cfg", "user://hud\n.cfg"]:
		check(preferences.save_file(bad_path) == ERR_INVALID_PARAMETER and HudPreferences.load_file(bad_path).load_error == ERR_INVALID_PARAMETER, "Unsafe paths rejected")
	preferences.text_scale = 1.5
	preferences.palette = "tritanopia"
	preferences.high_contrast = true
	check(preferences.save_file(path) == OK, "Valid preferences save")
	var loaded := HudPreferences.load_file(path)
	check(loaded.text_scale == 1.5 and loaded.palette == "tritanopia" and loaded.high_contrast and loaded.load_error == OK, "All values round trip")
	var detached := preferences.clone()
	detached.palette = "standard"
	check(preferences.palette == "tritanopia", "Clones are detached")
	var saved := FileAccess.get_file_as_string(path)
	for invalid: float in [NAN, INF, 0.5, 1.1, 1.51]:
		preferences.text_scale = invalid
		check(preferences.save_file(path) == ERR_INVALID_DATA and FileAccess.get_file_as_string(path) == saved, "Invalid draft cannot overwrite saved settings")
	preferences = loaded.copy()
	for key: String in ["text_scale", "palette", "high_contrast", "version"]:
		var invalid_values: Array = {"text_scale": [NAN, INF, true, "1.5", 1.1, 2.0], "palette": ["unknown", 4, true], "high_contrast": [1, "true"], "version": [true, 1.0, 99]}[key]
		for invalid: Variant in invalid_values:
			preferences.save_file(path)
			var config := ConfigFile.new()
			config.load(path)
			config.set_value("hud", key, invalid)
			config.save(path)
			var source := FileAccess.get_file_as_string(path)
			var rejected := HudPreferences.load_file(path)
			check(rejected.load_error != OK and rejected.text_scale == 1.0 and rejected.palette == "standard" and not rejected.high_contrast, "Malformed schema returns complete defaults")
			check(FileAccess.get_file_as_string(path) == source, "Bad source preserved")
	var oversized := FileAccess.open(path, FileAccess.WRITE)
	oversized.store_string("x".repeat(32769))
	oversized.close()
	check(HudPreferences.load_file(path).load_error == ERR_FILE_CORRUPT, "Oversized input rejected")
	preferences.save_file(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(preferences.save_file(path) != OK and FileAccess.get_file_as_string(path) == saved, "Temporary-file failure preserves previous save")
	DirAccess.remove_absolute(path + ".tmp")
	var target_directory := directory + "/target"
	DirAccess.make_dir_absolute(target_directory)
	check(preferences.save_file(target_directory) != OK and not FileAccess.file_exists(target_directory + ".tmp"), "Rename failure cleans temporary file")
	DirAccess.remove_absolute(target_directory)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("HUD PREFERENCES PASS" if failures == 0 else "HUD PREFERENCES FAIL")
	quit(0 if failures == 0 else 1)
