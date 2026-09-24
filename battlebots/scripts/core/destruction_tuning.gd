extends RefCounted
## Typed view of data/destruction.json (#72): wreck break-up styles, cut look
## and debris physics. Presentation only. No class_name: callers preload this
## script so checkouts with a stale editor class cache still resolve it.
const SCRIPT := "res://scripts/core/destruction_tuning.gd"
const PATH := "res://data/destruction.json"
const FIELDS := {
	"debris":["max_pieces", "rest_seconds", "sink_seconds", "linear_damp", "angular_damp", "friction", "bounce", "density", "hull_grid"],
	"cut":["heat_seconds", "glow_band", "tear_frequency", "soot"]}
const PART_FIELDS := ["hull_share", "hit_memory", "speed", "lift", "spin", "sever_heat"]
const PART_THRESHOLDS := ["component_thresholds", "armour_thresholds", "core_thresholds"]
const STYLE_FIELDS := ["pieces", "tear", "tunnel", "centre_pull", "speed", "lift", "spin", "heat"]
const MAX_PIECES := 5

static var _loaded: RefCounted

var _values: Dictionary = {}
var _styles: Dictionary = {}
var _kinds: Dictionary = {}
var default_style := ""
## Part loss (see parts in the JSON): numbers, descending HP thresholds and
## the kinds that sever with a cut.
var parts: Dictionary = {}
var thresholds: Dictionary = {}
var sever_kinds: Array[String] = []

static func settings() -> RefCounted:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid destruction configuration: " + PATH)
	return _loaded

## Returns null (and appends to problems) when anything is missing or out of
## range; tuning never falls back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> RefCounted:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("is not a JSON object")
		return null
	var result: RefCounted = load(SCRIPT).new()
	for group: String in FIELDS:
		var parsed := _numbers(data.get(group), FIELDS[group], group, problems)
		if parsed.is_empty():
			return null
		result._values[group] = parsed
	result.parts = _numbers(data.get("parts"), PART_FIELDS, "parts", problems)
	if result.parts.is_empty():
		return null
	for field: String in PART_THRESHOLDS:
		var values: Variant = data.parts.get(field)
		if not values is Array or values.is_empty():
			problems.append("parts.%s must be a non-empty array" % field)
			return null
		var parsed: Array[float] = []
		for value: Variant in values:
			if not (value is float or value is int) or float(value) < 0.0 or float(value) >= 1.0 \
					or (not parsed.is_empty() and float(value) >= parsed.back()):
				problems.append("parts.%s must descend within 0..1" % field)
				return null
			parsed.append(float(value))
		result.thresholds[field.trim_suffix("_thresholds")] = parsed
	if not data.parts.get("sever_kinds") is Array:
		problems.append("parts.sever_kinds must be an array of kinds")
		return null
	for kind: Variant in data.parts.sever_kinds:
		if not kind is String:
			problems.append("parts.sever_kinds must be an array of kinds")
			return null
		result.sever_kinds.append(kind)
	if not data.get("styles") is Dictionary or not data.get("kinds") is Dictionary:
		problems.append("needs styles and kinds objects")
		return null
	for style: String in data.styles:
		if style.begins_with("_"):
			continue
		var parsed := _numbers(data.styles[style], STYLE_FIELDS, "styles." + style, problems)
		if parsed.is_empty():
			return null
		if parsed.pieces < 1 or parsed.pieces > MAX_PIECES or parsed.pieces != roundf(parsed.pieces):
			problems.append("styles.%s.pieces must be a whole number 1..%d" % [style, MAX_PIECES])
			return null
		var split: Variant = data.styles[style].get("split_force")
		if split != null:
			if not (split is float or split is int) or float(split) < 0.0:
				problems.append("styles.%s.split_force must be non-negative" % style)
				return null
			parsed["split_force"] = float(split)
		result._styles[style] = parsed
	for kind: String in data.kinds:
		if kind.begins_with("_"):
			continue
		var style: Variant = data.kinds[kind]
		if not style is String or not result._styles.has(style):
			problems.append("kinds.%s names an unknown style" % kind)
			return null
		result._kinds[kind] = style
	if not result._kinds.has("default"):
		problems.append("kinds needs a default style")
		return null
	result.default_style = result._kinds.default
	return result

static func _numbers(entry: Variant, fields: Array, label: String, problems: Array[String]) -> Dictionary:
	if not entry is Dictionary:
		problems.append("lacks the %s object" % label)
		return {}
	var parsed := {}
	for field: String in fields:
		var value: Variant = entry.get(field)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
			problems.append("lacks non-negative numeric %s.%s" % [label, field])
			return {}
		parsed[field] = float(value)
	return parsed

func value(group: String, field: String) -> float:
	return float(_values[group][field])

## Break-up style for the kind of the killing blow (weapon id, "ram", ...).
func style_for(kind: String) -> Dictionary:
	return _styles[_kinds.get(kind, default_style)]

func style_name(kind: String) -> String:
	return _kinds.get(kind, default_style)
