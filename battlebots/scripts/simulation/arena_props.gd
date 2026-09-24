extends RefCounted
## Authoritative destructible arena props (#71). The server damages props
## through CombatWorld and breaks them; every peer then drops the same
## colliders, so cover and driving lines stay identical everywhere. State
## replicates as a revisioned snapshot (MvpSession baseline and reliable
## update) and resets each round. Tuning: data/arena_props.json. No
## class_name: callers preload this script (stale editor class caches, #74).
const SCRIPT := "res://scripts/simulation/arena_props.gd"
const PATH := "res://data/arena_props.json"
const GROUND := preload("res://scripts/arena/woodland_ground.gd")
const OBSTACLE_META := &"woodland_obstacle"
## Body-frame bounds on a replicated break record (m).
const RECORD_POINT_MAX := 400.0
const RECORD_KIND_MAX := 24
const MAX_PROPS := 512

static var _settings: Dictionary = {}

## name -> {body, kind, hp, max, at, radius, layer, mask}
var props: Dictionary = {}
## name -> {kind (the breaking blow), point, axis}
var destroyed: Dictionary = {}
var revision := 0
var _names: Dictionary = {}

static func settings() -> Dictionary:
	if _settings.is_empty():
		var problems: Array[String] = []
		_settings = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(not _settings.is_empty(), "Invalid arena prop configuration: " + PATH)
	return _settings

## Validated tuning, or {} (with problems) when anything is missing.
static func from_json(source: String, problems: Array[String] = []) -> Dictionary:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("is not a JSON object")
		return {}
	var result := {"kinds":{}, "multipliers":{}, "melee":{}, "ram":{}}
	if not data.get("kinds") is Dictionary or data.kinds.is_empty():
		problems.append("needs a kinds object")
		return {}
	for kind: String in data.kinds:
		if kind.begins_with("_"): continue
		var entry: Variant = data.kinds[kind]
		if not entry is Dictionary or not _positive(entry.get("hp")) or not entry.get("names") is Array or entry.names.is_empty():
			problems.append("kinds.%s needs positive hp and a names list" % kind)
			return {}
		result.kinds[kind] = {"hp":float(entry.hp), "names":entry.names.duplicate()}
	if not data.get("multipliers") is Dictionary:
		problems.append("needs a multipliers object")
		return {}
	for weapon: String in data.multipliers:
		if weapon.begins_with("_"): continue
		var table: Variant = data.multipliers[weapon]
		if not table is Dictionary:
			problems.append("multipliers.%s must map prop kinds to numbers" % weapon)
			return {}
		for kind: String in table:
			if not _number(table[kind]):
				problems.append("multipliers.%s.%s must be a non-negative number" % [weapon, kind])
				return {}
		result.multipliers[weapon] = table.duplicate()
	var melee: Variant = data.get("melee")
	if not melee is Dictionary or not _positive(melee.get("reach")):
		problems.append("melee needs a positive reach")
		return {}
	result.melee.reach = float(melee.reach)
	for weapon: String in melee:
		if weapon.begins_with("_") or weapon == "reach": continue
		var entry: Variant = melee[weapon]
		if not entry is Dictionary or not (_positive(entry.get("dps")) or _positive(entry.get("hit"))) \
				or (entry.has("cooldown") and not _positive(entry.cooldown)):
			problems.append("melee.%s needs a positive dps or hit (and positive cooldown when given)" % weapon)
			return {}
		result.melee[weapon] = entry.duplicate()
	var ram: Variant = data.get("ram")
	if not ram is Dictionary:
		problems.append("needs a ram object")
		return {}
	for field: String in ["min_closing_speed", "damage_per_speed", "reference_mass", "cooldown"]:
		if not _number(ram.get(field)):
			problems.append("ram.%s must be a non-negative number" % field)
			return {}
		result.ram[field] = float(ram[field])
	return result

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0

static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0

## Registers every destructible obstacle of a freshly built arena.
func configure(arena: Node) -> void:
	props.clear()
	destroyed.clear()
	_names.clear()
	revision += 1
	if arena == null:
		return
	var kinds: Dictionary = settings().kinds
	for body: Node in arena.find_children("*", "StaticBody3D", true, false):
		if not body.has_meta(OBSTACLE_META) or props.size() >= MAX_PROPS:
			continue
		var item: Dictionary = body.get_meta(OBSTACLE_META)
		var rule: Dictionary = kinds.get(item.get("kind", ""), {})
		if rule.is_empty() or not rule.names.any(func(prefix: String) -> bool: return str(item.name).begins_with(prefix)):
			continue
		body.collision_layer |= BaselineConfig.PROP_LAYER
		props[item.name] = {"body":body, "kind":item.kind, "hp":rule.hp, "max":rule.hp, "at":item.at,
			"radius":GROUND.footprint(item), "layer":body.collision_layer, "mask":body.collision_mask}
		_names[body.get_instance_id()] = item.name

## Prop name for a physics collider id, or "" when it is not a live prop.
func prop_at(collider_id: int) -> String:
	var name: String = _names.get(collider_id, "")
	return name if not name.is_empty() and not destroyed.has(name) else ""

func multiplier(weapon: String, kind: String) -> float:
	return float(settings().multipliers.get(weapon, {}).get(kind, 1.0))

## Applies a weapon hit. Returns the raw energy left after breaking the prop
## (>= 0), or a negative value when the prop still stands.
func damage(name: String, raw: float, weapon: String, point: Vector3, axis: Vector3) -> float:
	if not props.has(name) or destroyed.has(name) or not is_finite(raw) or raw <= 0.0:
		return -1.0
	var prop: Dictionary = props[name]
	var scale := multiplier(weapon, prop.kind)
	if scale <= 0.0:
		return -1.0
	var dealt := raw * scale
	if dealt < prop.hp:
		prop.hp -= dealt
		return -1.0
	var leftover: float = (dealt - prop.hp) / scale
	prop.hp = 0.0
	var direction := axis.normalized() if axis.length_squared() > 0.000001 else Vector3.UP
	destroyed[name] = {"kind":weapon, "point":point, "axis":direction}
	_set_solid(name, false)
	revision += 1
	return leftover

## Live props whose footprint lies within radius of a point, with distances.
func within(point: Vector3, radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for name: String in props:
		if destroyed.has(name):
			continue
		var prop: Dictionary = props[name]
		var at: Vector3 = prop.at
		var flat := Vector2(point.x - at.x, point.z - at.z).length()
		var distance := maxf(0.0, flat - float(prop.radius))
		if distance <= radius:
			found.append({"name":name, "distance":distance})
	return found

func reset_round() -> void:
	var changed := not destroyed.is_empty()
	for name: String in props:
		props[name].hp = props[name].max
		if destroyed.has(name):
			_set_solid(name, true)
	destroyed.clear()
	if changed:
		revision += 1

func _set_solid(name: String, solid: bool) -> void:
	var prop: Dictionary = props[name]
	var body: CollisionObject3D = prop.body
	if not is_instance_valid(body):
		return
	body.collision_layer = prop.layer if solid else 0
	body.collision_mask = prop.mask if solid else 0

## Public state: {revision, destroyed: {name: [kind, point, axis]}}.
func snapshot() -> Dictionary:
	var records := {}
	for name: String in destroyed:
		var record: Dictionary = destroyed[name]
		records[name] = [record.kind, record.point, record.axis]
	return {"revision":revision, "destroyed":records}

## Adopts the server's state on a client. Returns whether anything changed.
func accept(state: Variant) -> bool:
	if not state is Dictionary or not state.get("destroyed") is Dictionary or not state.get("revision") is int:
		return false
	var next := {}
	for name: Variant in state.destroyed:
		var record: Variant = state.destroyed[name]
		if not name is String or not props.has(name) or not record is Array or record.size() != 3:
			return false
		if not record[0] is String or record[0].length() > RECORD_KIND_MAX or not record[1] is Vector3 or not record[1].is_finite() \
				or record[1].length() > RECORD_POINT_MAX or not record[2] is Vector3 or not record[2].is_finite():
			return false
		next[name] = {"kind":record[0], "point":record[1], "axis":record[2]}
	var changed := false
	for name: String in destroyed.keys():
		if not next.has(name):
			destroyed.erase(name)
			props[name].hp = props[name].max
			_set_solid(name, true)
			changed = true
	for name: String in next:
		if not destroyed.has(name):
			destroyed[name] = next[name]
			props[name].hp = 0.0
			_set_solid(name, false)
			changed = true
	revision = state.revision
	return changed
