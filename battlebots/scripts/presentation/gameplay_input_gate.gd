class_name GameplayInputGate
extends RefCounted
## Local intent filtering only. Authority/lifecycle checks remain with the session.
const ACTIONS: Array[StringName] = [&"drive_forward", &"drive_reverse",
	&"steer_left", &"steer_right", &"brake", &"nitro", &"jump", &"primary", &"secondary", &"recover"]
var _blocked: Dictionary = {}
var auxiliary_weapon := false
var toggle_primary: bool = false:
	set(value):
		if toggle_primary != value:
			toggle_primary = value
			require_release()
var _primary_latched := false
var _primary_was_down := false
var _cancel_pending := false

func _init() -> void:
	require_release()

func require_release() -> void:
	_primary_latched = false
	_primary_was_down = false
	_cancel_pending = true
	for action: StringName in ACTIONS:
		_blocked[action] = true

func sample(strengths: Dictionary, edges: Dictionary, enabled: bool) -> BotCommand:
	var command := BotCommand.new()
	if not enabled:
		require_release()
		command.brake = true
		command.secondary_held = true
		command.jump_cancel = true
		return command
	for action: StringName in ACTIONS:
		if float(strengths.get(action, 0.0)) <= 0.0:
			_blocked.erase(action)
	command.throttle = _strength(strengths, &"drive_forward") - _strength(strengths, &"drive_reverse")
	command.steering = _strength(strengths, &"steer_right") - _strength(strengths, &"steer_left")
	command.brake = _strength(strengths, &"brake") > 0.0
	command.nitro_held = _strength(strengths, &"nitro") > 0.0
	command.jump_held = _strength(strengths, &"jump") > 0.0
	command.jump_cancel = _cancel_pending or _blocked.has(&"jump")
	for action: StringName in [&"drive_forward", &"drive_reverse", &"steer_left", &"steer_right"]:
		command.brake = command.brake or _blocked.has(action)
	var primary_down := float(strengths.get(&"primary", 0.0)) > 0.0
	var primary_edge := primary_down and not _primary_was_down and bool(edges.get(&"primary", false))
	_primary_was_down = primary_down
	# Suppressed release of a charged lifter must cancel, never launch.
	var secondary_down := _strength(strengths, &"secondary") > 0.0
	command.auxiliary_held = secondary_down and auxiliary_weapon
	command.secondary_held = _cancel_pending or _blocked.has(&"primary") or secondary_down
	_cancel_pending = false
	if toggle_primary:
		if command.secondary_held and not command.auxiliary_held:
			_primary_latched = false
			if secondary_down and primary_down:
				_blocked[&"primary"] = true
		elif primary_edge and not _blocked.has(&"primary"):
			_primary_latched = not _primary_latched
			# Press weapons (hammer) consume the physical edge; continuous weapons
			# consume the independent held latch. Both clicks must remain edges.
			command.primary_pressed = true
		command.primary_held = _primary_latched
	else:
		command.primary_held = _strength(strengths, &"primary") > 0.0
		command.primary_pressed = command.primary_held and bool(edges.get(&"primary", false))
	command.recovery_pressed = not _blocked.has(&"recover") and bool(edges.get(&"recover", false))
	return command

func _strength(strengths: Dictionary, action: StringName) -> float:
	return 0.0 if _blocked.has(action) else float(strengths.get(action, 0.0))
