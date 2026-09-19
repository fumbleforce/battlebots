class_name CameraPreferences
extends RefCounted
## B-owned local settings, isolated from A's future player-profile service.
const DEFAULT_PATH := "user://presentation_camera.cfg"
var sensitivity_x: float = 0.003
var sensitivity_y: float = 0.003
# Compatibility: reading returns X; assigning sets both axes.
var sensitivity: float:
	get:
		return sensitivity_x
	set(value):
		sensitivity_x = value
		sensitivity_y = value
var invert_y: bool = false
var auto_recenter: bool = true
var recenter_speed: float = 2.0
var load_error: Error = OK

static func from_rig(rig: BotOrbitCamera) -> CameraPreferences:
	var result := CameraPreferences.new()
	result.sensitivity_x = rig.sensitivity_x
	result.sensitivity_y = rig.sensitivity_y
	result.invert_y = rig.invert_y
	result.auto_recenter = rig.auto_recenter
	result.recenter_speed = rig.recenter_speed
	return result

func apply_to(rig: BotOrbitCamera) -> void:
	rig.sensitivity_x = sensitivity_x
	rig.sensitivity_y = sensitivity_y
	rig.invert_y = invert_y
	rig.auto_recenter = auto_recenter
	rig.recenter_speed = recenter_speed

static func load_file(path: String) -> CameraPreferences:
	var result := CameraPreferences.new()
	if path.is_empty() or not FileAccess.file_exists(path):
		return result
	var config := ConfigFile.new()
	result.load_error = config.load(path)
	if result.load_error != OK:
		return result
	var version: Variant = config.get_value("camera", "version", 0)
	if not (version is int) or version not in [1, 2]:
		result.load_error = ERR_FILE_UNRECOGNIZED
		return result
	if version == 1:
		result.sensitivity = _number(config.get_value("camera", "sensitivity", 0.003), 0.003, 0.0005, 0.02)
	else:
		result.sensitivity_x = _number(config.get_value("camera", "sensitivity_x", 0.003), 0.003, 0.0005, 0.02)
		result.sensitivity_y = _number(config.get_value("camera", "sensitivity_y", 0.003), 0.003, 0.0005, 0.02)
	result.recenter_speed = _number(config.get_value("camera", "recenter_speed", 2.0), 2.0, 0.1, 8.0)
	var invert: Variant = config.get_value("camera", "invert_y", false)
	var recenter: Variant = config.get_value("camera", "auto_recenter", true)
	result.invert_y = invert if invert is bool else false
	result.auto_recenter = recenter if recenter is bool else true
	return result

static func _number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)

func save_file(path: String) -> Error:
	if path.is_empty():
		return ERR_UNCONFIGURED
	var config := ConfigFile.new()
	config.set_value("camera", "version", 2)
	config.set_value("camera", "sensitivity_x", _number(sensitivity_x, 0.003, 0.0005, 0.02))
	config.set_value("camera", "sensitivity_y", _number(sensitivity_y, 0.003, 0.0005, 0.02))
	config.set_value("camera", "invert_y", invert_y)
	config.set_value("camera", "auto_recenter", auto_recenter)
	config.set_value("camera", "recenter_speed", _number(recenter_speed, 2.0, 0.1, 8.0))
	var temporary_path := path + ".tmp"
	var error := config.save(temporary_path)
	if error != OK:
		return error
	return DirAccess.rename_absolute(temporary_path, path)
