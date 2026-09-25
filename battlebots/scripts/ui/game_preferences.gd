extends RefCounted
## Local gameplay-presentation preferences (settings hub GAME page, #85).
## Loading never rewrites a bad file. No class_name: users preload this
## script by path so a stale editor class cache still starts (#65, #74).
const SCRIPT := "res://scripts/ui/game_preferences.gd"
const DEFAULT_PATH := "user://game.cfg"
const VERSION := 1
## Numbers on other bots, and on the local player's own bot.
var show_damage_numbers := true
var show_player_damage_numbers := true
## The speedometer dial above Integrity (#86).
var show_speedometer := true
## Its actual speed (km/h) above the share of top speed.
var show_speed_value := true
## The kill-spree banner announcing kills and the heat they vented (#87).
var show_spree_banner := true
var load_error: Error = OK

static func create() -> RefCounted:
	return load(SCRIPT).new()

func copy() -> RefCounted:
	var result := create()
	result.show_damage_numbers = show_damage_numbers
	result.show_player_damage_numbers = show_player_damage_numbers
	result.show_speedometer = show_speedometer
	result.show_speed_value = show_speed_value
	result.show_spree_banner = show_spree_banner
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

static func load_file(path: String = DEFAULT_PATH) -> RefCounted:
	var result := create()
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
	var version: Variant = config.get_value("game", "version", null)
	if not version is int or version != VERSION:
		result.load_error = ERR_FILE_UNRECOGNIZED
		return result
	var numbers: Variant = config.get_value("game", "show_damage_numbers", null)
	# Added after the first release of this file: absent means the default.
	var player_numbers: Variant = config.get_value("game", "show_player_damage_numbers", true)
	var speedometer: Variant = config.get_value("game", "show_speedometer", true)
	var speed_value: Variant = config.get_value("game", "show_speed_value", true)
	var spree: Variant = config.get_value("game", "show_spree_banner", true)
	if not numbers is bool or not player_numbers is bool or not speedometer is bool or not speed_value is bool or not spree is bool:
		result.load_error = ERR_INVALID_DATA
		return result
	result.show_damage_numbers = numbers
	result.show_player_damage_numbers = player_numbers
	result.show_speedometer = speedometer
	result.show_speed_value = speed_value
	result.show_spree_banner = spree
	return result

func save_file(path: String = DEFAULT_PATH) -> Error:
	if not _valid_path(path):
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("game", "version", VERSION)
	config.set_value("game", "show_damage_numbers", show_damage_numbers)
	config.set_value("game", "show_player_damage_numbers", show_player_damage_numbers)
	config.set_value("game", "show_speedometer", show_speedometer)
	config.set_value("game", "show_speed_value", show_speed_value)
	config.set_value("game", "show_spree_banner", show_spree_banner)
	var temporary := path + ".tmp"
	var error := config.save(temporary)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error
