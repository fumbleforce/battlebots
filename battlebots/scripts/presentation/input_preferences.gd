class_name InputPreferences
extends RefCounted
## Local keyboard/mouse preferences. Never writes project settings or controller bindings.

const DEFAULT_PATH := "user://presentation_input.cfg"
const ACTIONS: Array[StringName] = [&"drive_forward", &"drive_reverse", &"steer_left", &"steer_right", &"brake", &"primary", &"secondary", &"recover", &"camera_recenter", &"camera_zoom_in", &"camera_zoom_out", &"camera_toggle", &"ping", &"scoreboard"]
const LABELS := {&"drive_forward": "Drive forward", &"drive_reverse": "Drive reverse", &"steer_left": "Steer left", &"steer_right": "Steer right", &"brake": "Brake", &"primary": "Primary weapon", &"secondary": "Lower / cancel weapon", &"recover": "Recover", &"camera_recenter": "Recenter camera", &"camera_zoom_in": "Zoom in", &"camera_zoom_out": "Zoom out", &"camera_toggle": "Camera view (planned)", &"ping": "Ping (planned)", &"scoreboard": "Scoreboard"}
const KEYS := {&"drive_forward": KEY_W, &"drive_reverse": KEY_S, &"steer_left": KEY_A, &"steer_right": KEY_D, &"brake": KEY_SPACE, &"recover": KEY_R, &"camera_toggle": KEY_C, &"ping": KEY_Q, &"scoreboard": KEY_TAB}
const MOUSE := {&"primary": MOUSE_BUTTON_LEFT, &"secondary": MOUSE_BUTTON_RIGHT, &"camera_recenter": MOUSE_BUTTON_MIDDLE, &"camera_zoom_in": MOUSE_BUTTON_WHEEL_UP, &"camera_zoom_out": MOUSE_BUTTON_WHEEL_DOWN}
var bindings: Dictionary = {}
var toggle_primary := false
var load_error: Error = OK

func _init() -> void:
	for action in KEYS:
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[action]
		bindings[action] = event
	for action in MOUSE:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE[action]
		bindings[action] = event

func clone() -> InputPreferences:
	var result := InputPreferences.new()
	result.bindings = bindings.duplicate(true)
	for action in bindings:
		result.bindings[action] = bindings[action].duplicate()
	result.toggle_primary = toggle_primary
	result.load_error = load_error
	return result

func try_bind(action: StringName, event: InputEvent) -> String:
	if not ACTIONS.has(action):
		return "Unknown action."
	var reason := _validate_event(action, event)
	if not reason.is_empty():
		return reason
	var normalized := _normalize(event)
	for other in bindings:
		if other != action and _identity(bindings[other]) == _identity(normalized):
			return "Already assigned to %s." % LABELS[other]
	bindings[action] = normalized
	return ""

func label_for(action: StringName) -> String:
	if not bindings.has(action):
		return "Unbound"
	var event: InputEvent = bindings[action]
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode)
	return {1: "Left mouse", 2: "Right mouse", 3: "Middle mouse", 4: "Wheel up", 5: "Wheel down", 6: "Wheel left", 7: "Wheel right", 8: "Mouse 4", 9: "Mouse 5"}.get(event.button_index, "Mouse %d" % event.button_index)

static func _validate_event(action: StringName, event: InputEvent) -> String:
	if not (event is InputEventKey or event is InputEventMouseButton):
		return "Use a keyboard key or mouse button."
	if event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return "Key combinations are not supported."
	if event is InputEventKey:
		if event.echo:
			return "Release the key before assigning it."
		var code: int = event.physical_keycode
		if code <= 0 or code > KEY_SPECIAL + 255 or (code >= 128 and code < KEY_SPECIAL):
			return "Use a physical keyboard key."
		if code in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK] or (code == KEY_TAB and action != &"scoreboard"):
			return "That key is reserved for menu navigation."
	else:
		if event.button_index < MOUSE_BUTTON_LEFT or event.button_index > MOUSE_BUTTON_XBUTTON2:
			return "Unsupported mouse button."
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT] and action not in [&"camera_zoom_in", &"camera_zoom_out"]:
			return "Mouse wheel can only control camera zoom."
	return ""

static func _normalize(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var result := InputEventKey.new()
		result.physical_keycode = event.physical_keycode
		return result
	var result := InputEventMouseButton.new()
	result.button_index = event.button_index
	return result

static func _identity(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key:%d" % event.physical_keycode
	return "mouse:%d" % event.button_index

static func load_file(path: String = DEFAULT_PATH) -> InputPreferences:
	var result := InputPreferences.new()
	if path.is_empty() or not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.load_error = FileAccess.get_open_error()
		return result
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		result.load_error = ERR_PARSE_ERROR
		return result
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version") != 1 or not data.get("toggle_primary") is bool or not data.get("bindings") is Dictionary:
		result.load_error = ERR_FILE_UNRECOGNIZED
		return result
	var saved: Dictionary = data.bindings
	if saved.size() != ACTIONS.size():
		result.load_error = ERR_INVALID_DATA
		return result
	var decoded := {}
	var identities := {}
	for action in ACTIONS:
		var item: Variant = saved.get(String(action))
		if not item is Dictionary or item.size() != 2 or not item.get("code") is float or not is_finite(item.code) or item.code != floor(item.code) or item.code <= 0 or item.code > KEY_SPECIAL + 255:
			result.load_error = ERR_INVALID_DATA
			return result
		var event: InputEvent
		if item.get("kind") == "key":
			event = InputEventKey.new()
			event.physical_keycode = int(item.code)
		elif item.get("kind") == "mouse":
			event = InputEventMouseButton.new()
			event.button_index = int(item.code)
		else:
			result.load_error = ERR_INVALID_DATA
			return result
		if not _validate_event(action, event).is_empty() or identities.has(_identity(event)):
			result.load_error = ERR_INVALID_DATA
			return result
		identities[_identity(event)] = true
		decoded[action] = event
	result.bindings = decoded
	result.toggle_primary = data.toggle_primary
	return result

func save_file(path: String = DEFAULT_PATH) -> Error:
	if path.is_empty():
		return ERR_UNCONFIGURED
	var data := {"version": 1, "toggle_primary": toggle_primary, "bindings": {}}
	var identities := {}
	if bindings.size() != ACTIONS.size():
		return ERR_INVALID_DATA
	for action in ACTIONS:
		var event: InputEvent = bindings.get(action)
		if not _validate_event(action, event).is_empty() or identities.has(_identity(event)):
			return ERR_INVALID_DATA
		identities[_identity(event)] = true
		data.bindings[String(action)] = {"kind": "key" if event is InputEventKey else "mouse", "code": event.physical_keycode if event is InputEventKey else event.button_index}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)

func apply_to_input_map() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			continue
		Input.action_release(action)
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				InputMap.action_erase_event(action, event)
		InputMap.action_add_event(action, bindings[action].duplicate())

static func snapshot_input_map() -> Dictionary:
	var result := {}
	for action in ACTIONS:
		if InputMap.has_action(action):
			var events: Array[InputEvent] = []
			for event in InputMap.action_get_events(action):
				events.append(event.duplicate())
			result[action] = events
	return result

static func restore_input_map(snapshot: Dictionary) -> void:
	for action in ACTIONS:
		if not snapshot.has(action) or not InputMap.has_action(action):
			continue
		Input.action_release(action)
		InputMap.action_erase_events(action)
		for event in snapshot[action]:
			InputMap.action_add_event(action, event)
