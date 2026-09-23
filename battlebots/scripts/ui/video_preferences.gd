class_name VideoPreferences
extends RefCounted
const DEFAULT_PATH := "user://video.cfg"
var mode := "windowed"
var resolution := Vector2i(1280, 720)
var vsync := true
var screen := -1
var graphics: Dictionary = GraphicsOptions.DEFAULTS.duplicate(true)
var load_error: Error = OK

func valid() -> bool:
	return GraphicsOptions.valid(graphics) and screen >= -1 and screen < 32 and mode in ["windowed", "borderless", "fullscreen"] and resolution.x >= 640 and resolution.y >= 480 and resolution.x <= 7680 and resolution.y <= 4320

func copy() -> VideoPreferences:
	var result := VideoPreferences.new()
	result.mode = mode
	result.resolution = resolution
	result.vsync = vsync
	result.screen = screen
	result.graphics = graphics.duplicate(true)
	result.load_error = load_error
	return result

static func capture() -> VideoPreferences:
	var result := VideoPreferences.new()
	if DisplayServer.get_name() == "headless":
		return result
	var current := DisplayServer.window_get_mode()
	result.mode = "fullscreen" if current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else ("borderless" if current == DisplayServer.WINDOW_MODE_FULLSCREEN else "windowed")
	result.resolution = DisplayServer.window_get_size()
	result.vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	return result

static func capture_display_state() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {}
	return {"mode":DisplayServer.window_get_mode(), "position":DisplayServer.window_get_position(),
		"size":DisplayServer.window_get_size(), "borderless":DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),
		"vsync":DisplayServer.window_get_vsync_mode(), "screen":DisplayServer.window_get_current_screen()}

static func restore_display_state(state: Dictionary) -> Error:
	if DisplayServer.get_name() == "headless":
		return ERR_UNAVAILABLE
	if not state.has_all(["mode", "position", "size", "borderless", "vsync"]):
		return ERR_INVALID_DATA
	if state.has("screen") and state.screen < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(state.screen)
	if DisplayServer.window_get_mode() != state.mode or DisplayServer.window_get_size() != state.size:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(state.size)
		DisplayServer.window_set_position(state.position)
		DisplayServer.window_set_mode(state.mode)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, state.borderless)
	if state.mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_position(state.position)
	DisplayServer.window_set_vsync_mode(state.vsync)
	return OK

func apply(vsync_only := false) -> Error:
	if not valid():
		return ERR_INVALID_DATA
	if DisplayServer.get_name() == "headless":
		return ERR_UNAVAILABLE
	if vsync_only:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		return OK
	if screen >= 0 and screen < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(screen)
	var target_mode := DisplayServer.WINDOW_MODE_WINDOWED if mode == "windowed" else (DisplayServer.WINDOW_MODE_FULLSCREEN if mode == "borderless" else DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	var current_mode := DisplayServer.window_get_mode()
	if current_mode != target_mode:
		DisplayServer.window_set_mode(target_mode)
		if target_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	if mode == "windowed":
		var usable := DisplayServer.screen_get_usable_rect()
		var fitted := Vector2i(mini(resolution.x, usable.size.x), mini(resolution.y, usable.size.y))
		if DisplayServer.window_get_size() != fitted:
			DisplayServer.window_set_size(fitted)
			DisplayServer.window_set_position(usable.position + (usable.size - fitted) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	return OK

func save_file(path: String) -> Error:
	if not valid() or not _valid_path(path):
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("video", "version", 2)
	config.set_value("video", "mode", mode)
	config.set_value("video", "resolution", resolution)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "screen", screen)
	config.set_value("video", "graphics", graphics)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error != OK: return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return error

static func load_file(path: String = DEFAULT_PATH) -> VideoPreferences:
	var result := VideoPreferences.new()
	if not _valid_path(path):
		result.load_error = ERR_INVALID_PARAMETER
		return result
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.load_error = FileAccess.get_open_error()
		return result
	if file.get_length() > 32768:
		result.load_error = ERR_FILE_CORRUPT
		return result
	var text := file.get_as_text()
	file.close()
	var config := ConfigFile.new()
	result.load_error = config.parse(text)
	if result.load_error != OK:
		return result
	var saved_mode: Variant = config.get_value("video", "mode")
	var saved_size: Variant = config.get_value("video", "resolution")
	var saved_vsync: Variant = config.get_value("video", "vsync")
	var version: Variant = config.get_value("video", "version", 0)
	if not version is int or not version in [1,2] or not saved_mode is String or not saved_size is Vector2i or not saved_vsync is bool:
		result.load_error = ERR_INVALID_DATA
		return result
	var candidate := VideoPreferences.new()
	candidate.mode = saved_mode
	candidate.resolution = saved_size
	candidate.vsync = saved_vsync
	if version == 2:
		var saved_graphics: Variant = config.get_value("video", "graphics", {})
		var saved_screen: Variant = config.get_value("video", "screen", -1)
		if not saved_graphics is Dictionary or not saved_screen is int:
			result.load_error = ERR_INVALID_DATA
			return result
		candidate.graphics = saved_graphics
		candidate.screen = saved_screen
	if not candidate.valid():
		result.load_error = ERR_INVALID_DATA
		return result
	return candidate

static func _valid_path(path: String) -> bool:
	if path.is_empty() or path.ends_with("/") or path.ends_with("\\"):
		return false
	if not path.begins_with("user://") and (not path.is_absolute_path() or path.begins_with("res://")):
		return false
	for index in range(path.length()):
		if path.unicode_at(index) < 32:
			return false
	return not ".." in path.replace("\\", "/").split("/")
