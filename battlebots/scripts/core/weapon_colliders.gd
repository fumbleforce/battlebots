class_name WeaponColliders
extends RefCounted
## Typed view of data/weapon_colliders.json (#112): the solid shape of each
## primary melee weapon at rest. MvpBot adds it to the bot body on every peer,
## so driving into a saw or a fork is an ordinary collision. Pure geometry: no
## scene loading, rendering or camera dependency.
const SCRIPT := "res://scripts/core/weapon_colliders.gd"
const WEAPON_MOUNTS = preload("res://scripts/core/weapon_mounts.gd")
const PATH := "res://data/weapon_colliders.json"
const MOUNTS := ["canonical", "atlas", "bracken", "sawblade"]
## Numeric fields each shape needs; a disc also needs radius or radius_share.
const NUMBERS := {"box":[], "disc":["thickness"], "wedge":["width"]}
const VECTORS := {"box":["centre", "size"], "disc":["centre"], "wedge":[]}
const OPTIONAL := ["pitch_degrees", "width_share", "radius", "radius_share"]

static var _loaded: WeaponColliders

var _mounts: Dictionary = {}

static func settings() -> WeaponColliders:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid weapon collider configuration: " + PATH)
	return _loaded

## Returns null (and appends to problems) when an entry is malformed; shapes
## never fall back to silent defaults.
static func from_json(source: String, problems: Array[String] = []) -> WeaponColliders:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("is not a JSON object")
		return null
	# By path, not class name: a checkout launched with a stale editor class
	# cache does not know this class yet (#74).
	var result: WeaponColliders = load(SCRIPT).new()
	for mount: String in MOUNTS:
		var entries: Variant = data.get(mount)
		if not entries is Dictionary:
			problems.append("lacks the %s object" % mount)
			return null
		result._mounts[mount] = {}
		for weapon: String in entries:
			if weapon.begins_with("_"):
				continue
			var entry: Variant = entries[weapon]
			var problem := _problem(entry)
			if not problem.is_empty():
				problems.append("%s.%s %s" % [mount, weapon, problem])
				return null
			result._mounts[mount][weapon] = entry
	return result

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _numbers(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(_number)

static func _problem(entry: Variant) -> String:
	if not entry is Dictionary or not NUMBERS.has(entry.get("shape")):
		return "needs a box, disc or wedge shape"
	for field: String in NUMBERS[entry.shape]:
		if not _number(entry.get(field)): return "lacks numeric " + field
	for field: String in VECTORS[entry.shape]:
		if not _numbers(entry.get(field), 3): return "lacks the three numbers of " + field
	for field: String in OPTIONAL:
		if entry.has(field) and not _number(entry[field]): return "has a non-numeric " + field
	if entry.shape == "disc":
		if not entry.get("axis") in ["x", "y"]: return "needs axis x or y"
		if not entry.has("radius") and not entry.has("radius_share"): return "lacks radius or radius_share"
	if entry.shape == "wedge":
		var profile: Variant = entry.get("profile")
		if not profile is Array or profile.size() < 3 or not profile.all(func(point: Variant) -> bool: return _numbers(point, 2)):
			return "needs a profile of at least three [y, z] points"
	return ""

## The rest-pose collider of a build's primary weapon in the body frame:
## {shape, transform, solid_when_active}, or {} for a weapon without one.
func collider(loadout: Dictionary, stats: Dictionary) -> Dictionary:
	var size: Vector3 = stats.size
	var linear := BotScale.from_size(size)
	# Front tools sit on the body's tool coupler (#108): Atlas-frame points map
	# through the mount frame and lengths scale with it (identity on the Atlas).
	var coupler: Transform3D = stats.get("tool_mount", Transform3D.IDENTITY)
	var tool_scale: float = WEAPON_MOUNTS.scale_of(coupler)
	match AtlasGeometry.tool_kind(loadout):
		"ram":
			var volume := AtlasGeometry.ram_volume(size, 0.0)
			return _solid(_box(volume[1] * tool_scale), Transform3D(Basis.IDENTITY, coupler * (volume[0] as Transform3D).origin))
		"spear":
			# The whole fork, from the hull's front face to the tine tips.
			var back := -size.z * 0.5
			var height := AtlasGeometry.SPEAR_Y
			var tip := coupler * (Vector3(0.0, (height.x + height.y) * 0.5, AtlasGeometry.SPEAR_TIP_Z) * linear)
			return _solid(_box(Vector3(AtlasGeometry.SPEAR_HALF_WIDTH * 2.0 * linear * tool_scale, (height.y - height.x) * linear * tool_scale, back - tip.z)),
				Transform3D(Basis.IDENTITY, Vector3(tip.x, tip.y, (back + tip.z) * 0.5)))
		"grinder":
			return _solid(_disc(AtlasGeometry.GRINDER_REACH * linear * tool_scale, AtlasGeometry.GRINDER_HALF_WIDTH * 2.0 * linear * tool_scale),
				Transform3D(Basis(Vector3.BACK, PI * 0.5), coupler * AtlasGeometry.grinder_drum(size, 0.0)))
	# The part, not its kind: the Ramp follows the lifter rules with its own shape.
	var weapon: String = loadout.parts.weapon
	if weapon == "saw":
		# Every body carries the Sawblade's blade (#109): the disc CombatWorld sweeps.
		var blade := SawbladeGeometry.saw_scale(loadout, size)
		return _solid(_disc(SawbladeGeometry.SAW_RADIUS * blade.z, SawbladeGeometry.SAW_THICKNESS * blade.x),
			Transform3D(Basis(Vector3.BACK, PI * 0.5), SawbladeGeometry.saw_axle(loadout, size)))
	var scorpion := ScorpionGeometry.enabled(loadout)
	if scorpion and weapon == "hammer":
		return _solid(_box(ScorpionGeometry.HEAD_SIZE * linear), ScorpionGeometry.hammer_transform(size, 0.0))
	var mount := "canonical"
	if AtlasGeometry.bracken_enabled(loadout): mount = "bracken"
	elif AtlasGeometry.enabled(loadout): mount = "atlas"
	elif SawbladeConfig.body(loadout): mount = "sawblade"
	# The Ramp is the Sawblade's plate on every body (#108).
	var ramp := weapon == "ramp"
	if ramp: mount = "sawblade"
	if not _mounts[mount].has(weapon): mount = "canonical"
	var entry: Dictionary = _mounts[mount].get(weapon, {})
	if entry.is_empty():
		return {}
	# Authored point -> body frame: point * scale + origin.
	var scale := Vector3.ONE * linear
	var origin := Vector3(0.0, 0.0, -size.z * 0.5)
	if ramp:
		# Hinged where SawbladeGeometry places it: on the Sawblade body that is
		# the authored spot (the hull's underside at y 0).
		scale = SawbladeGeometry.ramp_scale(loadout, size)
		origin = SawbladeGeometry.ramp_hinge(loadout, size) - SawbladeGeometry.RAMP_HINGE * scale
	elif mount == "sawblade":
		scale = SawbladeGeometry.scale_for(size)
		origin = Vector3.DOWN * size.y * 0.5
	else:
		if scorpion: origin += ScorpionGeometry.fallback_socket(size)
		if weapon == "hammer": origin += NimbleBots.hammer_socket(loadout)
	var shape: Shape3D
	var transform := Transform3D.IDENTITY
	match entry.shape:
		"box":
			var dimensions := _vector(entry.size) * scale
			if entry.has("width_share"): dimensions.x = float(entry.width_share) * size.x
			shape = _box(dimensions)
			transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(entry.get("pitch_degrees", 0.0)))), _vector(entry.centre) * scale + origin)
		"disc":
			var upright: bool = entry.axis == "y"
			var radius := float(entry.radius_share) * size.x if entry.has("radius_share") else float(entry.radius) * scale.z
			shape = _disc(radius, float(entry.thickness) * (scale.y if upright else scale.x))
			transform = Transform3D(Basis.IDENTITY if upright else Basis(Vector3.BACK, PI * 0.5), _vector(entry.centre) * scale + origin)
		"wedge":
			var hull := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for point: Array in entry.profile:
				for side: float in [-0.5, 0.5]:
					points.append(Vector3(side * float(entry.width), point[0], point[1]) * scale + origin)
			hull.points = points
			shape = hull
	return _solid(shape, transform, entry.get("solid_when_active", false) == true)

static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func _box(size: Vector3) -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = size
	return box

static func _disc(radius: float, thickness: float) -> CylinderShape3D:
	var disc := CylinderShape3D.new()
	disc.radius = radius
	disc.height = thickness
	return disc

static func _solid(shape: Shape3D, transform: Transform3D, solid_when_active := false) -> Dictionary:
	return {"shape":shape, "transform":transform, "solid_when_active":solid_when_active}
