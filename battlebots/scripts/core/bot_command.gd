class_name BotCommand
extends RefCounted
## Local contract only; Developer A owns future network encoding and validation.

var sequence: int = 0
var throttle: float = 0.0
var steering: float = 0.0
var brake: bool = false
var primary_held: bool = false
var primary_pressed: bool = false
var secondary_held: bool = false
var recovery_pressed: bool = false

func is_valid() -> bool:
	return sequence >= 0 and is_finite(throttle) and is_finite(steering) \
		and absf(throttle) <= 1.0 and absf(steering) <= 1.0
