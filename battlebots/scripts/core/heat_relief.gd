class_name HeatRelief
extends RefCounted
## Typed view of data/heat_relief.json: kill-spree heat venting and combos,
## arena cooling zones and coolant pickups (#67, #68). Server and client read
## the same file.
const SCRIPT := "res://scripts/core/heat_relief.gd"
const PATH := "res://data/heat_relief.json"
const FIELDS := {
	"spree":["window_seconds", "heat_per_kill", "heat_per_combo", "max_combo", "boost_seconds", "boost_multiplier"],
	"zones":["radius", "height", "cooling_per_second", "fraction"],
	"coolant":["heat", "fraction", "count", "respawn_seconds"]}

static var _loaded: HeatRelief

var _values: Dictionary = {}

static func settings() -> HeatRelief:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid heat relief configuration: " + PATH)
	return _loaded

static func from_json(source: String, problems: Array[String] = []) -> HeatRelief:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("is not a JSON object")
		return null
	# By path, not class name: a checkout launched with a stale editor class
	# cache does not know this class yet (#74).
	var result: HeatRelief = load(SCRIPT).new()
	for group: String in FIELDS:
		var entry: Variant = data.get(group)
		if not entry is Dictionary:
			problems.append("lacks the %s object" % group)
			return null
		var parsed := {}
		for field: String in FIELDS[group]:
			var value: Variant = entry.get(field)
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
				problems.append("lacks non-negative numeric %s.%s" % [group, field])
				return null
			parsed[field] = float(value)
		result._values[group] = parsed
	return result

func value(group: String, field: String) -> float:
	return float(_values[group][field])

## Heat vented by a kill that makes combo `combo` (1 = first kill).
func kill_vent(combo: int) -> float:
	return value("spree", "heat_per_kill") + value("spree", "heat_per_combo") * float(maxi(0, combo - 1))
