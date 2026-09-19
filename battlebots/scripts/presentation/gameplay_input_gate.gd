class_name GameplayInputGate
extends RefCounted
## Local intent filtering only. Authority/lifecycle checks remain with the session.
const ACTIONS: Array[StringName] = [&"drive_forward", &"drive_reverse",
	&"steer_left", &"steer_right", &"brake", &"primary", &"secondary", &"recover"]
var _blocked: Dictionary = {}

func _init() -> void:
	require_release()

func require_release() -> void:
	for action: StringName in ACTIONS:
		_blocked[action] = true

func sample(strengths: Dictionary, edges: Dictionary, enabled: bool) -> BotCommand:
	var command := BotCommand.new()
	if not enabled:
		require_release()
		command.brake = true
		command.secondary_held = true
		return command
	for action: StringName in ACTIONS:
		if float(strengths.get(action, 0.0)) <= 0.0:
			_blocked.erase(action)
	command.throttle = _strength(strengths, &"drive_forward") - _strength(strengths, &"drive_reverse")
	command.steering = _strength(strengths, &"steer_right") - _strength(strengths, &"steer_left")
	command.brake = _strength(strengths, &"brake") > 0.0
	for action: StringName in [&"drive_forward", &"drive_reverse", &"steer_left", &"steer_right"]:
		command.brake = command.brake or _blocked.has(action)
	command.primary_held = _strength(strengths, &"primary") > 0.0
	command.primary_pressed = command.primary_held and bool(edges.get(&"primary", false))
	# Suppressed release of a charged lifter must cancel, never launch.
	command.secondary_held = _blocked.has(&"primary") or _strength(strengths, &"secondary") > 0.0
	command.recovery_pressed = not _blocked.has(&"recover") and bool(edges.get(&"recover", false))
	return command

func _strength(strengths: Dictionary, action: StringName) -> float:
	return 0.0 if _blocked.has(action) else float(strengths.get(action, 0.0))
