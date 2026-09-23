extends SceneTree

var failures: Array[String] = []
const PATH := "user://input_preferences_test.json"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

func run() -> void:
	var original := InputPreferences.snapshot_input_map()
	var prefs := InputPreferences.new()
	for action in InputPreferences.ACTIONS:
		check(InputMap.action_has_event(action, prefs.bindings[action]), "Default matches project: %s" % action)
	check(not prefs.try_bind(&"primary", key(KEY_ESCAPE)).is_empty(), "Escape reserved")
	check(not prefs.try_bind(&"primary", key(KEY_TAB)).is_empty(), "Tab reserved")
	check(not prefs.try_bind(&"primary", key(KEY_W)).is_empty(), "Duplicate rejected")
	var chord := key(KEY_F)
	chord.ctrl_pressed = true
	check(not prefs.try_bind(&"primary", chord).is_empty(), "Chord rejected")
	chord.ctrl_pressed = false
	chord.echo = true
	check(not prefs.try_bind(&"primary", chord).is_empty(), "Echo rejected")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_LEFT
	check(not prefs.try_bind(&"primary", wheel).is_empty(), "Wheel held action rejected")
	check(prefs.try_bind(&"camera_zoom_in", wheel).is_empty(), "Wheel zoom accepted")
	check(prefs.try_bind(&"primary", key(KEY_F)).is_empty(), "Physical key accepted")
	var copied := prefs.clone()
	copied.bindings[&"primary"].physical_keycode = KEY_G
	check(prefs.bindings[&"primary"].physical_keycode == KEY_F, "Clone detached")
	prefs.toggle_primary = true
	check(prefs.save_file(PATH) == OK, "Save succeeds")
	var loaded := InputPreferences.load_file(PATH)
	check(loaded.load_error == OK and loaded.toggle_primary, "Roundtrip mode")
	check(loaded.bindings[&"primary"].physical_keycode == KEY_F, "Roundtrip binding")
	var saved_text := FileAccess.get_file_as_string(PATH)
	var legacy: Dictionary = JSON.parse_string(saved_text)
	legacy.version = 1
	legacy.bindings.erase("nitro")
	legacy.bindings.erase("jump")
	# Version-1 files predate the part shortcuts and had camera on C.
	for action: String in ["dev_weapon", "dev_body", "dev_drive"]: legacy.bindings.erase(action)
	legacy.bindings.camera_toggle = {"kind":"key", "code":KEY_C}
	legacy.bindings.brake = {"kind":"key", "code":KEY_SPACE}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	loaded = InputPreferences.load_file(PATH)
	check(loaded.load_error == OK and loaded.bindings[&"brake"].physical_keycode == KEY_X
		and loaded.bindings[&"jump"].physical_keycode == KEY_SPACE
		and loaded.bindings[&"nitro"].physical_keycode == KEY_SHIFT
		and loaded.bindings[&"dev_body"].physical_keycode == KEY_B,
		"Legacy controls migrate brake (via B) to X, reserve Space/Shift for perks and give B to the body shortcut")
	legacy.bindings.brake = {"kind":"key", "code":KEY_B}
	legacy.bindings.primary = {"kind":"key", "code":KEY_SPACE}
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	loaded = InputPreferences.load_file(PATH)
	check(loaded.load_error == OK and loaded.bindings[&"primary"].physical_keycode == KEY_V,
		"Legacy custom Space action moves to a free key")
	# Version 2 (#64): old defaults brake B / camera C move to X / T and the
	# local part shortcuts take V/B/C; a customised key keeps its action.
	var v2: Dictionary = JSON.parse_string(saved_text)
	v2.version = 2
	for action: String in ["dev_weapon", "dev_body", "dev_drive"]: v2.bindings.erase(action)
	v2.bindings.brake = {"kind":"key", "code":KEY_B}
	v2.bindings.camera_toggle = {"kind":"key", "code":KEY_C}
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(v2))
	file.close()
	loaded = InputPreferences.load_file(PATH)
	check(loaded.load_error == OK and loaded.bindings[&"brake"].physical_keycode == KEY_X
		and loaded.bindings[&"camera_toggle"].physical_keycode == KEY_T
		and loaded.bindings[&"dev_weapon"].physical_keycode == KEY_V
		and loaded.bindings[&"dev_body"].physical_keycode == KEY_B
		and loaded.bindings[&"dev_drive"].physical_keycode == KEY_C, "Version-2 defaults gain the V/B/C part shortcuts")
	v2.bindings.recover = {"kind":"key", "code":KEY_V}
	v2.bindings.brake = {"kind":"key", "code":KEY_X}
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(v2))
	file.close()
	loaded = InputPreferences.load_file(PATH)
	check(loaded.load_error == OK and loaded.bindings[&"recover"].physical_keycode == KEY_V
		and loaded.bindings[&"dev_weapon"].physical_keycode == KEY_N, "A customised V keeps its action; the weapon shortcut takes a spare key")
	check(InputPreferences.new().try_bind(&"dev_body", _key(KEY_G)) == "" , "Part shortcuts are rebindable")
	var malformed: Dictionary = JSON.parse_string(saved_text)
	malformed.bindings.drive_forward = malformed.bindings.drive_reverse.duplicate()
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed))
	file.close()
	loaded = InputPreferences.load_file(PATH)
	check(loaded.load_error != OK and loaded.bindings[&"drive_forward"].physical_keycode == KEY_W and not loaded.toggle_primary, "Duplicate map returns complete defaults")
	malformed = JSON.parse_string(saved_text)
	malformed.bindings.primary.code = 1e30
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed))
	file.close()
	check(InputPreferences.load_file(PATH).load_error != OK, "Out of range code rejected before conversion")
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{"version":999}')
	file.close()
	loaded = InputPreferences.load_file(PATH)
	check(loaded.load_error != OK and not loaded.toggle_primary and loaded.bindings[&"primary"] is InputEventMouseButton, "Unknown schema returns full defaults")
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{broken')
	file.close()
	check(InputPreferences.load_file(PATH).load_error != OK, "Corrupt JSON rejected")
	var ui_events := InputMap.action_get_events(&"ui_accept")
	var pause_events := InputMap.action_get_events(&"pause")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event(&"primary", pad)
	prefs.apply_to_input_map()
	check(InputMap.action_has_event(&"primary", pad), "Controller preserved")
	check(InputMap.action_get_events(&"ui_accept") == ui_events and InputMap.action_get_events(&"pause") == pause_events, "Menu input unchanged")
	var press := key(KEY_F)
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame
	check(Input.is_action_pressed(&"primary"), "Physical event maps to primary")
	InputPreferences.restore_input_map(original)
	check(not Input.is_action_pressed(&"primary"), "Restoration releases old action")
	for action in original:
		check(InputMap.action_get_events(action).size() == original[action].size(), "Restored count: %s" % action)
		for event in original[action]:
			check(InputMap.action_has_event(action, event), "Restored event: %s" % action)
	DirAccess.remove_absolute(PATH)
	if failures.is_empty():
		print("INPUT PREFERENCES PASS")
	quit(0 if failures.is_empty() else 1)

func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event
