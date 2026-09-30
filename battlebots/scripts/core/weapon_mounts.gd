extends RefCounted
## Typed view of data/weapon_mounts.json (#108): where a body other than the
## Atlas MX carries the roof turret, the front tools and the auxiliary gun.
## Server combat and presentation read the same record. Referenced by path
## (preload), never by a class name, so a stale editor class cache cannot miss it.
const PATH := "res://data/weapon_mounts.json"
const BODIES := ["sawblade", "scorpion", "box"]
## Samples per depression table: one every AtlasGeometry.TURRET_DEPRESSION_STEP degrees.
const DEPRESSION_SAMPLES := 72

static var _loaded: Dictionary = {}

static func data() -> Dictionary:
	if _loaded.is_empty():
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(not _loaded.is_empty(), "Invalid weapon mount configuration: " + PATH)
	return _loaded

## Returns {} (and appends to problems) when a required value is missing;
## mounts never fall back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> Dictionary:
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary or not parsed.get("bodies") is Dictionary or not parsed.get("depression") is Dictionary:
		problems.append("needs bodies and depression objects")
		return {}
	for body: String in BODIES:
		var entry: Variant = parsed.bodies.get(body)
		if not entry is Dictionary:
			problems.append("lacks bodies.%s" % body)
			continue
		for mount: String in ["turret", "tool"]:
			var record: Variant = entry.get(mount)
			if not record is Dictionary or not _vector(record.get("offset")) or not _number(record.get("scale")) or float(record.scale) <= 0.0:
				problems.append("%s.%s needs an offset and a positive scale" % [body, mount])
		if entry.get("tool") is Dictionary and (not _number(entry.tool.get("coupler")) or float(entry.tool.coupler) < 0.0):
			problems.append("%s.tool needs a coupler length" % body)
		if entry.get("turret") is Dictionary and (not _number(entry.turret.get("riser")) or float(entry.turret.riser) < 0.0):
			problems.append("%s.turret needs a riser height" % body)
		if entry.has("art_length") and (not _number(entry.art_length) or float(entry.art_length) <= 0.0):
			problems.append("%s.art_length must be a positive length" % body)
		if not _vector(entry.get("gun")):
			problems.append("%s.gun needs an offset" % body)
		var tables: Variant = parsed.depression.get(body, {})
		if not tables is Dictionary:
			problems.append("depression.%s is not an object" % body)
			continue
		for model: String in tables:
			var table: Variant = tables[model]
			if not table is Array or table.size() != DEPRESSION_SAMPLES or not table.all(_number):
				problems.append("depression.%s.%s needs %d numbers" % [body, model, DEPRESSION_SAMPLES])
	return {} if not problems.is_empty() else parsed

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(_number)

## Mount record of a draft's body, or "" for the bodies the weapons were
## authored on (Atlas MX, Bracken) and the sealed nimble bots.
static func body(draft: Dictionary) -> String:
	if AtlasGeometry.enabled(draft) or NimbleBots.enabled(draft): return ""
	if ScorpionGeometry.enabled(draft): return "scorpion"
	return "sawblade" if SawbladeConfig.enabled(draft) else "box"

## Maps the Atlas turret frame onto this draft's turret race, at game scale:
## apply it to AtlasGeometry.turret_breech/turret_muzzle results.
static func turret(draft: Dictionary, size: Vector3) -> Transform3D:
	return _frame(draft, "turret", size)

## Maps the Atlas front tool frame onto this draft's tool coupler, at game scale.
static func tool(draft: Dictionary, size: Vector3) -> Transform3D:
	return _frame(draft, "tool", size)

static func _frame(draft: Dictionary, mount: String, size: Vector3) -> Transform3D:
	var key := body(draft)
	if key.is_empty(): return Transform3D.IDENTITY
	var record: Dictionary = data().bodies[key][mount]
	var offset: Array = record.offset
	var linear := BotScale.from_size(size)
	var frame := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(record.scale)),
		Vector3(offset[0], offset[1], offset[2]) * linear)
	# Art stretched to the hull (SawbladeGeometry.scale_for) carries its mounts
	# along: they grow about the hull's underside, where the art stands.
	var art_length := float(data().bodies[key].get("art_length", 0.0))
	if art_length > 0.0:
		var stretch := size.z / (art_length * linear)
		var underside := Vector3.UP * size.y * 0.5
		frame = Transform3D(frame.basis.scaled(Vector3.ONE * stretch), (frame.origin + underside) * stretch - underside)
	return frame

## Height of the pedestal under the turret ring, in turret source metres.
static func turret_riser(draft: Dictionary) -> float:
	var key := body(draft)
	return float(data().bodies[key].turret.riser) if not key.is_empty() else 0.0

## Length of the rails behind the front tool's back plate, in tool source metres.
static func tool_coupler(draft: Dictionary) -> float:
	var key := body(draft)
	return float(data().bodies[key].tool.coupler) if not key.is_empty() else 0.0

## Uniform scale of a mount frame.
static func scale_of(frame: Transform3D) -> float:
	return frame.basis.x.x

## Offset of the gun frame (ScorpionGeometry.GUN_PIVOT) on this body, in hull
## source metres; zero for bodies without a mount record.
static func gun(draft: Dictionary) -> Vector3:
	var key := body(draft)
	if key.is_empty(): return Vector3.ZERO
	var offset: Array = data().bodies[key].gun
	return Vector3(offset[0], offset[1], offset[2])

## Measured depression table (degrees per 5 degrees of yaw) for a turret model
## on this draft's body, or [] to use the Atlas tables.
static func depression(draft: Dictionary, model: String) -> Array:
	var key := body(draft)
	if key.is_empty() or model.is_empty(): return []
	var tables: Dictionary = data().depression.get(key, {})
	return tables.get(model, tables.get(AtlasGeometry.family(model), []))
