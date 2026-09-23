class_name GamepadInput
extends RefCounted
## Presentation-only controller orbit; ordinary BotCommands carry all gameplay.
const CONFIG_PATH := "res://data/controller_input.json"
const LOOK_ACTIONS: Array[StringName] = [&"camera_look_left", &"camera_look_right", &"camera_look_up", &"camera_look_down"]
const GUIDE: Array[String] = [
	"Left stick · drive / steer", "Right stick · aim / orbit",
	"RT · primary weapon", "LT · secondary weapon",
	"LB · brake", "RB · Nitro",
	"A / south · charge jump", "X / west · recover",
	"Right stick press · recenter", "D-pad up / down · zoom",
	"Left stick press · crouch", "View / Back · scoreboard",
	"Start · menu", "D-pad / A / B · menus",
]
var look_pixels_per_second: float
var max_look_delta_seconds: float
var _look_released := false

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	look_pixels_per_second = float(data.look_pixels_per_second)
	max_look_delta_seconds = float(data.max_look_delta_seconds)
	assert(is_finite(look_pixels_per_second) and look_pixels_per_second > 0.0)
	assert(is_finite(max_look_delta_seconds) and max_look_delta_seconds > 0.0)

func require_release() -> void:
	_look_released = false

func look_delta(stick: Vector2, delta: float, enabled: bool) -> Vector2:
	if not enabled:
		require_release()
		return Vector2.ZERO
	if stick.is_zero_approx():
		_look_released = true
	if not _look_released or not stick.is_finite() or not is_finite(delta):
		return Vector2.ZERO
	return stick.limit_length() * look_pixels_per_second * clampf(delta, 0.0, max_look_delta_seconds)
