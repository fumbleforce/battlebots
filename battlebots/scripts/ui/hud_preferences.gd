class_name HudPreferences
extends RefCounted
## Local HUD presentation only; loading is bounded and never rewrites a bad file.
const DEFAULT_PATH := "user://hud.cfg"
const TEXT_SCALES := [1.0, 1.25, 1.5]
const PALETTES := ["standard", "deuteranopia", "protanopia", "tritanopia"]
var text_scale := 1.0
var palette := "standard"
var high_contrast := false
var load_error: Error = OK

func copy() -> HudPreferences:
	var result := HudPreferences.new()
	result.text_scale = text_scale
	result.palette = palette
	result.high_contrast = high_contrast
	result.load_error = load_error
	return result

func clone() -> HudPreferences:
	return copy()

static func _valid_path(path: String) -> bool:
	if path.is_empty() or path.ends_with("/") or path.ends_with("\\"):
		return false
	for index: int in range(path.length()):
		if path.unicode_at(index) < 32:
			return false
	if not path.begins_with("user://") and (not path.is_absolute_path() or path.begins_with("res://")):
		return false
	return not ".." in path.replace("\\", "/").split("/")

static func _valid_scale(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) in TEXT_SCALES

static func load_file(path: String = DEFAULT_PATH) -> HudPreferences:
	var result := HudPreferences.new()
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
		file.close()
		result.load_error = ERR_FILE_CORRUPT
		return result
	var content := file.get_as_text()
	file.close()
	var config := ConfigFile.new()
	result.load_error = config.parse(content)
	if result.load_error != OK:
		return result
	var version: Variant = config.get_value("hud", "version", null)
	if not version is int or version != 1:
		result.load_error = ERR_FILE_UNRECOGNIZED
		return result
	var scale_value: Variant = config.get_value("hud", "text_scale", null)
	var palette_value: Variant = config.get_value("hud", "palette", null)
	var contrast_value: Variant = config.get_value("hud", "high_contrast", null)
	if not _valid_scale(scale_value) or not palette_value is String or not palette_value in PALETTES or not contrast_value is bool:
		result.load_error = ERR_INVALID_DATA
		return result
	result.text_scale = float(scale_value)
	result.palette = palette_value
	result.high_contrast = contrast_value
	return result

func save_file(path: String = DEFAULT_PATH) -> Error:
	if not _valid_path(path):
		return ERR_INVALID_PARAMETER
	if not _valid_scale(text_scale) or not palette in PALETTES:
		return ERR_INVALID_DATA
	var config := ConfigFile.new()
	config.set_value("hud", "version", 1)
	config.set_value("hud", "text_scale", text_scale)
	config.set_value("hud", "palette", palette)
	config.set_value("hud", "high_contrast", high_contrast)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error
