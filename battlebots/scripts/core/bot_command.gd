class_name BotCommand
extends RefCounted
## Local contract only; Developer A owns future network encoding and validation.

var sequence: int = 0
var throttle: float = 0.0
var steering: float = 0.0
var brake: bool = false
var nitro_held: bool = false
var jump_held: bool = false
## Cancels a charged jump on focus loss, menu suppression or input timeout.
var jump_cancel: bool = false
var primary_held: bool = false
var primary_pressed: bool = false
var secondary_held: bool = false
## Explicit auxiliary trigger; synthetic secondary cancellation must never fire it.
var auxiliary_held: bool = false
var recovery_pressed: bool = false
## Turret aim: world-space bearing (Godot Y rotation, 0 = -Z) and elevation of
## the direction from the turret toward the player's crosshair. Level intent
## only; the server slews within mechanical rates/stops and resolves every hit.
var aim_valid: bool = false
var aim_yaw: float = 0.0
var aim_pitch: float = 0.0

func is_valid() -> bool:
	return sequence >= 0 and is_finite(throttle) and is_finite(steering) \
		and absf(throttle) <= 1.0 and absf(steering) <= 1.0 \
		and is_finite(aim_yaw) and is_finite(aim_pitch) \
		and absf(aim_yaw) <= PI + 0.001 and absf(aim_pitch) <= PI * 0.5 + 0.001
