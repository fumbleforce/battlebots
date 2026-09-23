class_name AtlasDriveRig
extends RefCounted
## Typed view of data/atlas_drive_rig.json, generated with atlas_drives.glb by
## tools/build-atlas-drives.py: large-wheel and hydraulic-leg dimensions in
## Atlas source metres. Presentation only; walker footholds stay in WalkerDrive.
const PATH := "res://data/atlas_drive_rig.json"

static var _loaded: AtlasDriveRig

# wheels
var wheel_radius: float
# legs
## Vertical slewing axis at (+-yaw_axis.x, pin_height, +-yaw_axis.y).
var yaw_axis: Vector2
var pin_height: float
var coxa_reach: float
var femur: float
var tibia: float
var ankle: float
## Highest ankle rise above the stance height the legs fold to.
var ankle_rise_limit: float
## Heading yaw stops in radians from straight fore/aft, positive outboard.
var coxa_yaw_min: float
var coxa_yaw_max: float
## Knee ram eyes, (X, Y) in the femur and tibia segment frames.
var knee_femur: Vector2
var knee_tibia: Vector2

const SCALARS := {
	"wheels": ["radius"],
	"legs": ["yaw_axis_x", "yaw_axis_z", "pin_height", "coxa_reach", "femur", "tibia", "ankle", "ankle_rise_limit",
		"coxa_yaw_min_degrees", "coxa_yaw_max_degrees"],
}
const PAIRS := ["knee_femur", "knee_tibia"]

static func settings() -> AtlasDriveRig:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid Atlas drive rig: " + PATH)
	return _loaded

## Returns null (and appends to problems) when any section or field is missing
## or non-numeric; the rig never falls back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> AtlasDriveRig:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("not a JSON object")
		return null
	var values := {}
	for section: String in SCALARS:
		var fields: Variant = data.get(section)
		for field: String in SCALARS[section]:
			var value: Variant = fields.get(field) if fields is Dictionary else null
			if not _number(value):
				problems.append("lacks numeric %s.%s" % [section, field])
				return null
			values[field] = float(value)
	var legs: Dictionary = data.legs
	for field: String in PAIRS:
		var pair: Variant = legs.get(field)
		if not pair is Array or pair.size() != 2 or not _number(pair[0]) or not _number(pair[1]):
			problems.append("lacks numeric pair legs.%s" % field)
			return null
		values[field] = Vector2(float(pair[0]), float(pair[1]))
	var result := AtlasDriveRig.new()
	result.wheel_radius = values.radius
	result.yaw_axis = Vector2(values.yaw_axis_x, values.yaw_axis_z)
	result.pin_height = values.pin_height
	result.coxa_reach = values.coxa_reach
	result.femur = values.femur
	result.tibia = values.tibia
	result.ankle = values.ankle
	result.ankle_rise_limit = values.ankle_rise_limit
	result.coxa_yaw_min = deg_to_rad(values.coxa_yaw_min_degrees)
	result.coxa_yaw_max = deg_to_rad(values.coxa_yaw_max_degrees)
	for field: String in PAIRS:
		result.set(field, values[field])
	return result

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
