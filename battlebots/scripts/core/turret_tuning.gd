class_name TurretTuning
extends RefCounted
## Typed view of data/turret_weapons.json: Atlas turret servo and weapon
## tuning. Server combat and client presentation read the same file.
const PATH := "res://data/turret_weapons.json"
const REQUIRED := ["range", "damage", "knock", "recoil"]
const BARREL_FIELDS := ["interval", "heat", "jolt", "rock"]
const FAMILY_EXTRAS := {"flamer":["half_angle"], "tesla":["seek_angle", "chain_reach", "chain_share"],
	"railgun":["pierce_share", "charge_seconds", "charge_heat_per_second"]}

static var _loaded: TurretTuning

var yaw_rate: float
var pitch_rate: float
var volley_spacing: float
var rock_tilt_limit: float
var _families: Dictionary = {}

static func settings() -> TurretTuning:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid turret weapon configuration: " + PATH)
	return _loaded

## Returns null (and appends to problems) when any required value is missing;
## tuning never falls back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> TurretTuning:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary or not data.get("servo") is Dictionary or not data.get("families") is Dictionary:
		problems.append("needs servo and families objects")
		return null
	var result := TurretTuning.new()
	for field: String in ["yaw_rate", "pitch_rate", "volley_spacing", "rock_tilt_limit"]:
		if not _numeric(data.servo.get(field)):
			problems.append("lacks numeric servo.%s" % field)
			return null
		result.set(field, float(data.servo[field]))
	for family: String in AtlasGeometry.TURRET_FAMILIES:
		var entry: Variant = data.families.get(family)
		if not entry is Dictionary or not entry.get("barrels") is Dictionary or not entry.barrels.has("1"):
			problems.append("lacks families.%s with a barrels.1 table" % family)
			return null
		var parsed := {"barrels": {}}
		for field: String in REQUIRED + FAMILY_EXTRAS.get(family, []):
			if not _numeric(entry.get(field)):
				problems.append("lacks numeric families.%s.%s" % [family, field])
				return null
			parsed[field] = float(entry[field])
		for count: String in entry.barrels:
			var table: Variant = entry.barrels[count]
			for field: String in BARREL_FIELDS:
				if not table is Dictionary or not _numeric(table.get(field)):
					problems.append("lacks numeric families.%s.barrels.%s.%s" % [family, count, field])
					return null
			var row := {}
			for field: String in BARREL_FIELDS: row[field] = float(table[field])
			parsed.barrels[int(count)] = row
		result._families[family] = parsed
	return result

static func _numeric(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

## Family-level value, e.g. value("cannon", "range").
func value(family: String, field: String) -> float:
	return float(_families[family][field])

## Per-barrel-count value, falling back to the single-barrel row.
func barrel(family: String, barrels: int, field: String) -> float:
	var table: Dictionary = _families[family].barrels
	return float(table.get(barrels, table[1])[field])
