class_name AudioPreferences
extends RefCounted
## Local linear gains; loading never modifies the source file or audio buses.
const DEFAULT_PATH := "user://audio.cfg"
const DEFAULTS := {"master":0.85, "music":0.65, "effects":0.85, "announcements":0.9}
const BUSES := {"master":"Master", "music":"BBMusic", "effects":"BBEffects", "announcements":"BBAnnouncements"}
var master := 0.85
var music := 0.65
var effects := 0.85
var announcements := 0.9
var muted := false
var load_error: Error = OK

static func ensure_buses() -> void:
	for label: String in ["BBMusic", "BBEffects", "BBAnnouncements"]:
		if AudioServer.get_bus_index(label) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, label)
		AudioServer.set_bus_send(AudioServer.get_bus_index(label), "Master")

func apply() -> void:
	ensure_buses()
	for key: String in BUSES:
		var value: float = get(key)
		AudioServer.set_bus_volume_linear(AudioServer.get_bus_index(BUSES[key]), clampf(value, 0.0, 1.0) if is_finite(value) else DEFAULTS[key])
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)

func copy() -> AudioPreferences:
	var result := AudioPreferences.new()
	for key: String in BUSES:
		result.set(key, get(key))
	result.muted = muted
	result.load_error = load_error
	return result

static func _valid_path(path: String) -> bool:
	if path.is_empty() or path.ends_with("/") or path.ends_with("\\"):
		return false
	for index: int in range(path.length()):
		if path.unicode_at(index) < 32:
			return false
	if not path.begins_with("user://") and (not path.is_absolute_path() or path.begins_with("res://")):
		return false
	return not ".." in path.replace("\\", "/").split("/")

static func _valid_gain(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 1

static func load_file(path: String) -> AudioPreferences:
	var result := AudioPreferences.new()
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
	var version: Variant = config.get_value("audio", "version", null)
	if not version is int or version != 1:
		result.load_error = ERR_FILE_UNRECOGNIZED
		return result
	for key: String in DEFAULTS:
		if not _valid_gain(config.get_value("audio", key, null)):
			result.load_error = ERR_INVALID_DATA
			return result
	var mute_value: Variant = config.get_value("audio", "muted", null)
	if not mute_value is bool:
		result.load_error = ERR_INVALID_DATA
		return result
	for key: String in DEFAULTS:
		result.set(key, float(config.get_value("audio", key)))
	result.muted = mute_value
	return result

func save_file(path: String) -> Error:
	if not _valid_path(path):
		return ERR_INVALID_PARAMETER
	for key: String in DEFAULTS:
		if not _valid_gain(get(key)):
			return ERR_INVALID_DATA
	var config := ConfigFile.new()
	config.set_value("audio", "version", 1)
	for key: String in DEFAULTS:
		config.set_value("audio", key, get(key))
	config.set_value("audio", "muted", muted)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error
