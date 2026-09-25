extends RefCounted
## Typed view of data/damage_numbers.json: floating damage numbers (#85).
## Presentation only. No class_name: users preload this script by path so a
## checkout with a stale editor class cache still starts (#65, #74).
const SCRIPT := "res://scripts/core/damage_number_tuning.gd"
const PATH := "res://data/damage_numbers.json"
const FIELDS := {
	"motion":["spread", "up", "gravity", "drag"],
	"timing":["lifetime_seconds", "pop_seconds", "pop_scale", "fade_seconds"],
	"text":["font_size", "outline_size", "screen_fraction", "min_height", "max_height",
		"small_scale", "big_scale", "big_damage", "min_damage", "max_live"]}
## Number colour per part of a hit (CombatState.last_split), plus the outline.
const PARTS := ["armour", "core", "pierce"]
const COLORS := ["armour", "core", "pierce", "outline"]

static var _loaded: RefCounted

var _values: Dictionary = {}
var _colors: Dictionary = {}

static func settings() -> RefCounted:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid damage number configuration: " + PATH)
	return _loaded

static func from_json(source: String, problems: Array[String] = []) -> RefCounted:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("is not a JSON object")
		return null
	var result: RefCounted = load(SCRIPT).new()
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
	var colors: Variant = data.get("colors")
	if not colors is Dictionary:
		problems.append("lacks the colors object")
		return null
	for key: String in COLORS:
		var value: Variant = colors.get(key)
		if not value is String or not Color.html_is_valid(value):
			problems.append("lacks an HTML colour colors.%s" % key)
			return null
		result._colors[key] = Color.html(value)
	if result.value("timing", "lifetime_seconds") <= 0.0 or result.value("text", "font_size") < 1.0 \
		or result.value("text", "max_live") < 1.0 or result.value("text", "big_damage") <= 0.0:
		problems.append("needs positive lifetime, font size, live cap and big_damage")
		return null
	return result

func value(group: String, field: String) -> float:
	return float(_values[group][field])

func color(key: String) -> Color:
	return _colors[key]
