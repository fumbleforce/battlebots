class_name BotPhysics
extends RefCounted
## Typed view of data/bot_physics.json: heavy-machine heft, motor authority and
## impact tuning. Server simulation and client replay read the same file.
const PATH := "res://data/bot_physics.json"

static var _loaded: BotPhysics

# heft
var gravity_multiplier: float
var minimum_arena_gravity_scale: float
var rise_speed_cap_at_1g: float
# contact
var hull_friction: float
var bot_contact_friction: float
# motor
var acceleration_multiplier: float
var grip_multiplier: float
var yaw_acceleration_multiplier: float
var yaw_torque_grip_fraction: float
var rolling_resistance_multiplier: float
var brake_multiplier: float
# walker
var lift_headroom_acceleration: float
# impacts
var weapon_impulse_multiplier: float
var lifter_impulse_multiplier: float
## Flip angular speed (rad/s at 1 g) added to a launched target, scaled by
## launch_scale so the flip completes within heft's shorter hang time.
var lifter_flip_spin_at_1g: float
var minigun_impulse_multiplier: float
## Upward acceleration while a charging lifter holds a target; scaled by heft.
var lifter_hold_acceleration_at_1g: float
var ram_knockback_per_closing_speed: float
var ram_knockback_lift_fraction: float

const SECTIONS := {
	"heft": ["gravity_multiplier", "minimum_arena_gravity_scale", "rise_speed_cap_at_1g"],
	"contact": ["hull_friction", "bot_contact_friction"],
	"motor": ["acceleration_multiplier", "grip_multiplier", "yaw_acceleration_multiplier",
		"yaw_torque_grip_fraction", "rolling_resistance_multiplier", "brake_multiplier"],
	"walker": ["lift_headroom_acceleration"],
	"impacts": ["weapon_impulse_multiplier", "lifter_impulse_multiplier", "lifter_flip_spin_at_1g",
		"minigun_impulse_multiplier", "lifter_hold_acceleration_at_1g",
		"ram_knockback_per_closing_speed", "ram_knockback_lift_fraction"],
}

static func settings() -> BotPhysics:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid bot physics configuration: " + PATH)
	return _loaded

## Returns null (and appends to problems) when any section or numeric field is
## missing; tuning never falls back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> BotPhysics:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("not a JSON object")
		return null
	var result := BotPhysics.new()
	for section: String in SECTIONS:
		var values: Variant = data.get(section)
		for field: String in SECTIONS[section]:
			var value: Variant = values.get(field) if values is Dictionary else null
			if not (value is float or value is int) or not is_finite(float(value)):
				problems.append("lacks numeric %s.%s" % [section, field])
				return null
			result.set(field, float(value))
	return result

## Heft applies to Earth-gravity arenas; the Moon keeps its authored low gravity.
func heft_for(gravity_scale: float) -> float:
	return gravity_multiplier if gravity_scale >= minimum_arena_gravity_scale else 1.0

## Launch speeds scale by sqrt(heft) so apex height is unchanged by heft.
func launch_scale_for(gravity_scale: float) -> float:
	return sqrt(heft_for(gravity_scale))
