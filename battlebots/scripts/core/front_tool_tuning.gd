class_name FrontToolTuning
extends RefCounted
## Typed view of data/front_tools.json: Atlas MX front tool tuning (ram,
## spear/forklift, grinder). Server combat and presentation read one file.
const SCRIPT := "res://scripts/core/front_tool_tuning.gd"
const PATH := "res://data/front_tools.json"
const FIELDS := {
	"ram":["front_cone", "damage_multiplier", "knock_multiplier", "self_share", "punch_seconds",
		"punch_damage", "punch_speed", "punch_lift", "punch_cooldown", "punch_heat"],
	"spear":["thrust_seconds", "thrust_damage", "armour_share", "cooldown", "thrust_heat", "stiffness",
		"damping", "max_acceleration", "reaction_share", "lift_seconds", "strain_distance",
		"max_hold_seconds", "release_speed", "hold_heat_per_second"],
	"grinder":["spinup_seconds", "heat_per_second", "cadence", "damage", "plate_multiplier", "pull", "raise_seconds"]}

static var _loaded: FrontToolTuning

var _values: Dictionary = {}

static func settings() -> FrontToolTuning:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid front tool configuration: " + PATH)
	return _loaded

## Returns null (and appends to problems) when any value is missing; tuning
## never falls back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> FrontToolTuning:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("is not a JSON object")
		return null
	# By path, not class name: a checkout launched with a stale editor class
	# cache does not know this class yet (#74).
	var result: FrontToolTuning = load(SCRIPT).new()
	for tool: String in FIELDS:
		var entry: Variant = data.get(tool)
		if not entry is Dictionary:
			problems.append("lacks the %s object" % tool)
			return null
		var parsed := {}
		for field: String in FIELDS[tool]:
			var value: Variant = entry.get(field)
			if not (value is float or value is int) or not is_finite(float(value)):
				problems.append("lacks numeric %s.%s" % [tool, field])
				return null
			parsed[field] = float(value)
		result._values[tool] = parsed
	return result

## value("ram", "punch_damage").
func value(tool: String, field: String) -> float:
	return float(_values[tool][field])
