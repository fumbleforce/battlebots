class_name NimbleBots
extends RefCounted
## The four factory-sealed quick bots (#61): locked loadouts and gait tuning
## from data/nimble_bots.json. Server simulation, client prediction, menus and
## presentation read the same validated record.
const PATH := "res://data/nimble_bots.json"
const GAITS := ["stride", "roll", "hop", "skate"]
## Loadout slots a nimble chassis fixes; perks (nitro/suspension) stay free.
const LOCKED_SLOTS := ["drive", "weapon", "utility"]
const SUPPORT_FIELDS := ["spring", "damping", "lift_headroom", "upright_gain", "upright_damping",
	"upright_torque_limit", "lean_response"]
const PRACTICE_FIELDS := ["home_radius_fraction", "patrol_radius", "patrol_points", "patrol_throttle", "engage_distance"]
const BOT_FIELDS := ["ride_height", "reach", "max_step", "turn_speed", "lateral_response", "coast_acceleration"]
const GAIT_FIELDS := {
	"stride": ["step_length", "pivot_steps_per_radian", "speed_surge", "bob", "sway_degrees", "lift_headroom"],
	"roll": ["lean_scale", "max_lean_degrees", "pitch_per_acceleration", "max_pitch_degrees", "pivot_fraction", "full_turn_speed"],
	"hop": ["hop_speed", "stance_seconds", "carry", "air_turn_rate", "air_acceleration", "landing_headroom"],
	"skate": ["stroke_seconds", "push_seconds", "push_drive", "glide_drive", "lean_scale", "max_lean_degrees", "crouch"],
}
## Catalogue order of the showcase presets.
const ORDER := ["strider_09", "monowheel_07", "pogo_03", "skater_12"]

static var _loaded: Dictionary = {}

static func data() -> Dictionary:
	if _loaded.is_empty():
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(not _loaded.is_empty(), "Invalid nimble bot configuration: " + PATH)
	return _loaded

## Returns {} (and appends to problems) when a required field is missing or
## not numeric; tuning never falls back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> Dictionary:
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary or not parsed.get("support") is Dictionary or not parsed.get("bots") is Dictionary:
		problems.append("needs support and bots objects")
		return {}
	for field: String in SUPPORT_FIELDS:
		if not _number(parsed.support.get(field)): problems.append("lacks numeric support.%s" % field)
	var practice: Variant = parsed.get("practice")
	for field: String in PRACTICE_FIELDS:
		if not practice is Dictionary or not _number(practice.get(field)): problems.append("lacks numeric practice.%s" % field)
	if not practice is Dictionary or not practice.get("arenas") is Array:
		problems.append("lacks practice.arenas")
	for chassis: String in ORDER:
		var bot: Variant = parsed.bots.get(chassis)
		if not bot is Dictionary:
			problems.append("lacks bots.%s" % chassis)
			continue
		if bot.get("gait") not in GAITS: problems.append("%s has an unknown gait" % chassis)
		for field: String in BOT_FIELDS:
			if not _number(bot.get(field)): problems.append("lacks numeric %s.%s" % [chassis, field])
		var tuning: Variant = bot.get(bot.get("gait", ""))
		for field: String in GAIT_FIELDS.get(bot.get("gait", ""), []):
			if not tuning is Dictionary or not _number(tuning.get(field)):
				problems.append("lacks numeric %s.%s.%s" % [chassis, bot.get("gait", ""), field])
		var footholds: Variant = bot.get("footholds")
		if not footholds is Array or footholds.size() < 2:
			problems.append("%s needs at least two footholds" % chassis)
		var parts: Variant = bot.get("parts")
		for slot: String in LOCKED_SLOTS:
			if not parts is Dictionary or not parts.get(slot) is String:
				problems.append("%s lacks its locked %s" % [chassis, slot])
		if parts is Dictionary and parts.get("weapon") == "minigun" and not _vector(bot.get("gun_pivot")):
			problems.append("%s needs gun_pivot for its minigun" % chassis)
		if parts is Dictionary and parts.get("weapon") == "hammer" and not _vector(bot.get("hammer_socket")):
			problems.append("%s needs hammer_socket for its hammer" % chassis)
	return {} if not problems.is_empty() else parsed

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(_number)

static func support() -> Dictionary:
	return data().support

static func practice() -> Dictionary:
	return data().practice

static func enabled(draft: Dictionary) -> bool:
	var parts: Variant = draft.get("parts")
	return parts is Dictionary and data().bots.has(parts.get("chassis", ""))

## Tuning record for a draft's nimble chassis, or {} for any other bot.
static func spec(draft: Dictionary) -> Dictionary:
	return data().bots.get(draft.get("parts", {}).get("chassis", ""), {}) if enabled(draft) else {}

static func is_chassis(id: String) -> bool:
	return data().bots.has(id)

## True for a nimble chassis or its dedicated drive: never offered in Customize,
## never dropped as a match pickup.
static func locked_part(id: String) -> bool:
	if is_chassis(id): return true
	for chassis: String in data().bots:
		if data().bots[chassis].parts.drive == id: return true
	return false

## Validation reasons for a draft on a nimble chassis ([] for other bots).
static func reasons(draft: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var parts: Variant = draft.get("parts")
	if not parts is Dictionary: return found
	var bot: Dictionary = data().bots.get(parts.get("chassis", ""), {})
	if bot.is_empty():
		for chassis: String in data().bots:
			if parts.get("drive") == data().bots[chassis].parts.drive:
				found.append("That drive is built into the %s" % data().bots[chassis].name)
		return found
	for slot: String in LOCKED_SLOTS:
		if parts.get(slot) != bot.parts[slot]:
			found.append("%s is a sealed factory build; its drive, weapon and utility cannot change yet" % bot.name)
			break
	var cosmetics: Variant = draft.get("cosmetics")
	if cosmetics is Dictionary and cosmetics.size() != 1:
		found.append("%s has fixed livery and carries no armour pieces" % bot.name)
	return found

## Canonical loadout for a nimble chassis.
static func preset(registry: ContentRegistry, chassis: String) -> Dictionary:
	var bot: Dictionary = data().bots[chassis]
	var draft := registry.starter()
	draft.name = bot.name
	draft.parts = {"chassis":chassis, "drive":bot.parts.drive, "weapon":bot.parts.weapon,
		"utility":bot.parts.utility, "nitro":"nitro_boost", "suspension":"charged_jump"}
	draft.cosmetics = {"paint":bot.paint}
	return draft

static func presets(registry: ContentRegistry) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chassis: String in ORDER: result.append(preset(registry, chassis))
	return result

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

## Offset from the shared Scorpion gun frame (ScorpionGeometry.GUN_PIVOT at the
## hull's scale) to this bot's authored gun pivot, in game metres.
static func gun_offset(draft: Dictionary, size: Vector3) -> Vector3:
	var bot := spec(draft)
	if bot.is_empty() or not bot.has("gun_pivot"): return Vector3.ZERO
	return vector(bot.gun_pivot) - ScorpionGeometry.GUN_PIVOT * BotScale.from_size(size)

## Hammer pivot offset from the generic hull-front pivot, in game metres.
static func hammer_socket(draft: Dictionary) -> Vector3:
	var bot := spec(draft)
	return vector(bot.hammer_socket) if bot.has("hammer_socket") else Vector3.ZERO
