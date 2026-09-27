extends Node3D
## Deterministic Frozen Maelstrom battlefield (#102): a ring of ice frozen
## mid-spin around a bottomless eye, tilting down toward it from a low rim over
## the thin ice of the frozen sea, with broad frozen swells, spiral pressure ridges, upthrust ice
## slabs, basalt crags, seracs and the wrecks of two fleets. Everything that collides derives from data/maelstrom_arena.json and
## the model hulls in data/maelstrom_hulls.json (art_source/maelstrom/), so the
## server and every client build the same world without loading any art. There
## are no walls: a bot that drops below kill_y (mvp_bot.gd) or leaves the ring
## (AuthorityWorld, outside_ring) is eliminated.
## Everything is mirrored through the centre, so both teams face identical ground.

const CONFIG := "res://data/maelstrom_arena.json"
const HULLS := "res://data/maelstrom_hulls.json"
const STEP := 1.0
const ARENA_SPAWNS = preload("res://scripts/core/arena_spawns.gd")
## Reason recorded on a bot the maelstrom swallowed.
const FALL_REASON := "maelstrom"

class Layout extends RefCounted:
	var half: float
	var rim_radius: float
	var rim_jag: float
	var rim_teeth: int
	var eye_radius: float
	var eye_jag: float
	var eye_teeth: int
	var eye_depth: float
	var kill_y: float
	var sink_depth: float
	var pad_radius: float
	var pad_blend: float
	var bowl: Dictionary
	var swell: Dictionary
	var ridge: Dictionary
	var slabs: Array = []
	var obstacles: Array = []
	var art: Dictionary

static var _layout: Layout
static var _heights := PackedFloat32Array()
static var _pads := PackedVector2Array()
static var _pad_heights := PackedFloat32Array()
## Metres over which neighbouring landings' heights blend (soft minimum) at a
## landing's edge; it widens by a metre per metre out into the blend.
const PAD_SOFTNESS := 1.2
static var _obstacles: Array[Dictionary] = []
static var _hulls: Dictionary = {}
static var _breakables: Array[Dictionary] = []
## Breakable props (ArenaProps, #102) register with this meta: {kind, name, at, radius}.
const PROP_META := &"arena_prop"
## Keep-out radius (m) around each obstacle model when scattering breakables.
const CLEAR := {"rock_spire_a":13.0, "rock_spire_b":11.0, "rock_crag":14.0, "ice_shards_a":7.5, "ice_shards_b":8.5,
	"wreck_bow":16.0, "wreck_stern":15.0, "wreck_deck":15.0, "wreck_keel":16.0, "wreck_mast":6.0}
## Breakable prop kinds: model, collision radius (m).
const BREAKABLE := {"icicle":["icicle_cluster", 1.8], "barrel":["barrel", 0.5], "crate":["crate", 0.9]}
## Each frame of a capsized keel is its own breakable rib (radius m).
const RIB_RADIUS := 6.0

static func settings() -> Layout:
	if _layout == null:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		assert(data is Dictionary, "Invalid Frozen Maelstrom configuration: " + CONFIG)
		var parsed := Layout.new()
		for key: String in ["half", "rim_radius", "rim_jag", "eye_radius", "eye_jag",
				"eye_depth", "kill_y", "sink_depth", "pad_radius", "pad_blend"]:
			parsed.set(key, float(data[key]))
		parsed.rim_teeth = int(data.rim_teeth)
		parsed.eye_teeth = int(data.eye_teeth)
		parsed.bowl = data.bowl
		parsed.swell = data.swell
		parsed.ridge = data.ridge
		parsed.slabs = data.slabs
		parsed.obstacles = data.obstacles
		parsed.art = data.art
		# Even tooth counts keep the jagged edges point-symmetric.
		assert(parsed.rim_teeth % 2 == 0 and parsed.eye_teeth % 2 == 0, "Maelstrom edge teeth must be even")
		assert(parsed.eye_radius > 0.0 and parsed.rim_radius + parsed.rim_jag < parsed.half - 2.0, "Maelstrom ring must fit its grid")
		assert(parsed.kill_y < -float(parsed.bowl.funnel_depth) and parsed.kill_y > parsed.eye_depth, "Maelstrom kill height lies between the eye lip and the eye's depth")
		_layout = parsed
	return _layout

static func grid_size() -> int:
	return roundi(settings().half * 2.0 / STEP) + 1

# --- Shared terrain --------------------------------------------------------

## A sharp triangle wave in 0..1 with period 1.
static func _tri(t: float) -> float:
	return absf(fposmod(t, 1.0) * 2.0 - 1.0)

## Radius of the jagged outer rim at an angle. Only even harmonics, so the rim
## at angle + PI equals the rim at angle (point symmetry).
static func rim_at(angle: float) -> float:
	var cfg := settings()
	# Broken, irregular ice: layered even harmonics plus uneven small teeth.
	var teeth := _tri(angle / TAU * cfg.rim_teeth + 0.8 * sin(angle * 6.0) + 0.4 * sin(angle * 22.0))
	return cfg.rim_radius + 1.6 * sin(angle * 6.0 + 0.7) + 1.1 * sin(angle * 14.0 + 2.1) + 0.8 * sin(angle * 26.0 + 4.0) \
		+ 0.5 * sin(angle * 46.0 + 1.3) + cfg.rim_jag * (teeth - 0.5) * (0.5 + 0.5 * sin(angle * 10.0 + 0.3))

## Radius of the eye's broken lip at an angle.
static func eye_at(angle: float) -> float:
	var cfg := settings()
	var teeth := _tri(angle / TAU * cfg.eye_teeth + 0.6 * sin(angle * 4.0))
	return cfg.eye_radius + 0.7 * sin(angle * 6.0 + 1.0) + 0.45 * sin(angle * 18.0 + 2.0) + cfg.eye_jag * (teeth - 0.5) * (0.5 + 0.5 * sin(angle * 8.0))

## True where a point stands on the ice ring (not over the eye or the open sea).
static func on_ice(x: float, z: float) -> bool:
	var r := Vector2(x, z).length()
	var angle := atan2(z, x)
	return r <= rim_at(angle) and r >= eye_at(angle)

## Level pads: every team and free-for-all start, and the Practice Duel places
## (player, far Atlas, the monowheel block and the shuttle's run), mirrored.
static func pads() -> PackedVector2Array:
	if _pads.is_empty():
		var spawns := ARENA_SPAWNS.settings()
		var points := spawns.points("maelstrom")
		var c3 := spawns.duel_centre_for("maelstrom")
		var centre := Vector2(c3.x, c3.z)
		var reach := ArenaBounds.half_extent("maelstrom") * spawns.duel_monowheel_side_for("maelstrom")
		for offset: Vector2 in [Vector2.ZERO, Vector2(0, -reach), Vector2(-reach, 0), Vector2(reach, 0), Vector2(reach, -spawns.duel_shuttle_travel),
				Vector2(reach, spawns.duel_shuttle_travel)]:
			points.append(centre + offset)
			points.append(-(centre + offset))
		_pads = points
		_pad_heights = _group_heights(points)
	return _pads

## Landing height per pad: the cone's height at its centre; pads whose level
## cores overlap (chained) share their mean, so no step runs through a core.
static func _group_heights(points: PackedVector2Array) -> PackedFloat32Array:
	var group := range(points.size())
	var changed := true
	while changed:
		changed = false
		for i: int in points.size():
			for j: int in points.size():
				if points[i].distance_to(points[j]) < 2.0 * settings().pad_radius and group[j] < group[i]:
					group[i] = group[j]
					changed = true
	var heights := PackedFloat32Array()
	for i: int in points.size():
		var sum := 0.0
		var count := 0
		for j: int in points.size():
			if group[j] == group[i]:
				sum += bowl_at(points[j].length())
				count += 1
		heights.append(sum / count)
	return heights

## Distance across the nearest of the two spiral ridge crests at (r, angle).
static func _ridge_distance(r: float, angle: float) -> float:
	var cfg := settings()
	var twist := float(cfg.ridge.twist)
	var along := log(maxf(r, 0.001) / cfg.eye_radius) / twist + float(cfg.ridge.phase)
	var off := wrapf(angle - along, -PI * 0.5, PI * 0.5)
	return absf(off) * r / sqrt(1.0 + twist * twist)

static func _slab(p: Vector2, slab: Dictionary, sign: float) -> float:
	var at := Vector2(float(slab.at[0]), float(slab.at[1])) * sign
	var yaw := float(slab.yaw) + (PI if sign < 0.0 else 0.0)
	var rise := Vector2(cos(yaw), sin(yaw))
	var q := p - at
	var u := q.dot(rise)
	var v := q.dot(Vector2(-rise.y, rise.x))
	var length := float(slab.length)
	if absf(u) > length * 0.5 or absf(v) > float(slab.width) * 0.5:
		return 0.0
	return float(slab.height) * (u + length * 0.5) / length

## The whirlpool's profile: an inverted cone, one straight slope from the rim
## down to the eye (tilt metres over the ring), dropping away more steeply over
## the last stretch into the eye (funnel_depth metres by funnel_outer).
static func bowl_at(r: float, _angle: float = 0.0) -> float:
	var cfg := settings()
	var t := clampf((r - cfg.eye_radius) / (cfg.rim_radius - cfg.eye_radius), 0.0, 1.0)
	var near := 1.0 - clampf((r - cfg.eye_radius) / (float(cfg.bowl.funnel_outer) - cfg.eye_radius), 0.0, 1.0)
	return float(cfg.bowl.tilt) * t - float(cfg.bowl.funnel_depth) * near * near

## Height of the thin sea ice around the maelstrom: just under the rim at every
## angle (the frozen sea keeps the whirlpool's warp), easing far out to the
## level between the lanes' low rim and the flanks' high rim (sea_far).
static func sea_level(angle: float, r: float = 0.0) -> float:
	var cfg := settings()
	var under_rim := bowl_at(cfg.rim_radius, angle) - float(cfg.bowl.sea_below_rim)
	return lerpf(under_rim, sea_far(), smoothstep(cfg.rim_radius + 20.0, cfg.rim_radius + 240.0, r))

static func sea_far() -> float:
	return bowl_at(settings().rim_radius, PI * 0.25) - float(settings().bowl.sea_below_rim)

## True once a point has left the ring over the frozen sea (beyond the margin).
static func outside_ring(x: float, z: float) -> bool:
	return Vector2(x, z).length() > rim_at(atan2(z, x)) + float(settings().bowl.exit_margin)

static func height_at(x: float, z: float) -> float:
	var cfg := settings()
	var p := Vector2(x, z)
	var r := p.length()
	var angle := atan2(z, x)
	var eye := eye_at(angle)
	var rim := rim_at(angle)
	if r > rim:
		return sea_level(angle, r)
	if r < eye:
		return cfg.eye_depth
	# Creased ice facets: absolute waves are even in p, so mirrors match.
	var h := 0.16 * absf(sin(x * 0.071 + z * 0.043)) + 0.12 * absf(sin(z * 0.089 - x * 0.052)) \
		+ 0.07 * absf(sin(x * 0.19 + z * 0.23))
	var ridge := float(cfg.ridge.height) * maxf(0.0, 1.0 - _ridge_distance(r, angle) / float(cfg.ridge.half_width))
	# Serrated crests with breaks every ~37 m: lanes through the ridges.
	var lane := fposmod(r / 37.0, 1.0)
	ridge *= (0.7 + 0.3 * _tri(r * 0.11)) * smoothstep(0.08, 0.3, lane) * (1.0 - smoothstep(0.8, 1.0, lane))
	ridge *= smoothstep(eye + 10.0, eye + 34.0, r) * (1.0 - smoothstep(rim - 18.0, rim - 6.0, r))
	h += ridge
	# Broad frozen swells wheeling with the spin (sin of twice the phase is
	# unchanged by the mirror's half turn).
	var phase := angle - log(maxf(r, 0.001) / cfg.eye_radius) / float(cfg.ridge.twist)
	h += float(cfg.swell.height) * sin(phase * 2.0) * smoothstep(eye + 8.0, eye + 38.0, r) * (1.0 - smoothstep(rim - 34.0, rim - 6.0, r))
	# Start pads are small level landings cut into the cone, each at the cone's height
	# at its centre.
	# Soft minimum over the pads: continuous everywhere, and inside a landing its
	# own height (others are metres further away, so their share vanishes).
	var all := pads()
	var near := INF
	for pad: Vector2 in all:
		near = minf(near, p.distance_to(pad))
	var share := 0.0
	var sum := 0.0
	var softness := PAD_SOFTNESS + maxf(0.0, near - cfg.pad_radius)
	for i: int in all.size():
		var w := exp(-(p.distance_to(all[i]) - near) / softness)
		share += w
		sum += w * _pad_heights[i]
	var target := sum / share
	var weight := 1.0 - smoothstep(cfg.pad_radius, cfg.pad_radius + cfg.pad_blend, near)
	var base := bowl_at(r, angle)
	h = lerpf(base + h, target, weight)
	for slab: Dictionary in cfg.slabs:
		for sign: float in [1.0, -1.0]:
			var rise := _slab(p, slab, sign)
			# Raised from the ice around it, so the low end meets it flush.
			h += rise
	return h

## The authoritative height grid, computed once per process.
static func grid_heights() -> PackedFloat32Array:
	if _heights.is_empty():
		var n := grid_size()
		var half := settings().half
		var heights := PackedFloat32Array()
		heights.resize(n * n)
		for z: int in range(n):
			for x: int in range(n):
				heights[z * n + x] = height_at(-half + x * STEP, -half + z * STEP)
		_heights = heights
	return _heights

## Height of the physical (linearly interpolated) height map at a point.
static func surface_at(x: float, z: float) -> float:
	var half := settings().half
	var n := grid_size()
	var fx := clampf((x + half) / STEP, 0.0, n - 1.000001)
	var fz := clampf((z + half) / STEP, 0.0, n - 1.000001)
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h := grid_heights()
	var a := h[iz * n + ix]
	var b := h[iz * n + ix + 1]
	var c := h[(iz + 1) * n + ix]
	var d := h[(iz + 1) * n + ix + 1]
	return a + (b - a) * tx + (c - a) * tz if tx + tz < 1.0 else d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)

# --- Obstacles -------------------------------------------------------------

## Convex hulls per model in the model's frame (exported by build_kit.py).
static func hulls(model: String) -> Array:
	if _hulls.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(HULLS))
		assert(data is Dictionary, "Invalid Frozen Maelstrom hulls: " + HULLS)
		_hulls = data
	return _hulls.get(model, [])

## Every obstacle, authored and mirrored: {name, model, at, yaw, faction}.
## Faction -1 is neutral (rock and ice); a mirrored wreck belongs to the other fleet.
static func obstacles() -> Array[Dictionary]:
	if _obstacles.is_empty():
		var out: Array[Dictionary] = []
		var index := 0
		for entry: Dictionary in settings().obstacles:
			for sign: float in [1.0, -1.0]:
				var x := float(entry.at[0]) * sign
				var z := float(entry.at[1]) * sign
				var faction := int(entry.get("faction", -1))
				if faction >= 0 and sign < 0.0:
					faction = 1 - faction
				out.append({"name":"%s_%d" % [String(entry.model).to_pascal_case(), index], "model":String(entry.model),
					"at":Vector3(x, height_at(x, z), z), "yaw":float(entry.yaw) + (PI if sign < 0.0 else 0.0), "faction":faction})
				index += 1
		_obstacles = out
	return _obstacles

## Small breakable props, authored for one half and mirrored: icicle clusters
## strewn over the ice and barrels and crates spilled around each wreck (none on
## a start pad or inside another obstacle), and every rib of each capsized keel.
static func breakables() -> Array[Dictionary]:
	if not _breakables.is_empty():
		return _breakables
	var cfg := settings()
	var rng := RandomNumberGenerator.new()
	rng.seed = 102
	var candidates: Array = []
	for entry: Dictionary in cfg.obstacles:
		if String(entry.model).begins_with("wreck_"):
			var centre := Vector2(float(entry.at[0]), float(entry.at[1]))
			for n: int in 5:
				var a := rng.randf() * TAU
				var d := float(CLEAR[entry.model]) + rng.randf_range(1.0, 6.0)
				candidates.append(["barrel" if n % 2 == 0 else "crate", centre + Vector2(cos(a), sin(a)) * d])
	for n: int in 40:
		var a := rng.randf() * TAU
		candidates.append(["icicle", Vector2(cos(a), sin(a)) * rng.randf_range(cfg.eye_radius + 10.0, cfg.rim_radius - 8.0)])
	var out: Array[Dictionary] = []
	var placed: Array[Vector2] = []
	for candidate: Array in candidates:
		var p: Vector2 = candidate[1]
		if not _clear_for_prop(p, placed):
			continue
		var yaw := rng.randf() * TAU
		for sign: float in [1.0, -1.0]:
			var at := p * sign
			placed.append(at)
			var spec: Array = BREAKABLE[candidate[0]]
			out.append({"kind":candidate[0], "model":spec[0], "radius":spec[1], "yaw":yaw + (PI if sign < 0.0 else 0.0),
				"name":"%s%d" % [String(candidate[0]).capitalize(), out.size()], "at":Vector3(at.x, height_at(at.x, at.y), at.y)})
	for item: Dictionary in obstacles():
		if item.model != "wreck_keel":
			continue
		var offsets: Array = hulls("_keel_ribs")
		for i: int in offsets.size():
			var at: Vector3 = item.at + Basis(Vector3.UP, float(item.yaw)) * Vector3(0, 0, float(offsets[i]))
			at.y = item.at.y
			out.append({"kind":"rib", "model":"keel_rib_%d" % i, "radius":RIB_RADIUS, "yaw":item.yaw,
				"name":"Rib%d" % out.size(), "at":at})
	_breakables = out
	return out

static func _clear_for_prop(p: Vector2, placed: Array[Vector2]) -> bool:
	var cfg := settings()
	var r := p.length()
	if r < cfg.eye_radius + 8.0 or r > cfg.rim_radius - 6.0:
		return false
	for pad: Vector2 in pads():
		if p.distance_to(pad) < cfg.pad_radius + 4.0:
			return false
	for item: Dictionary in obstacles():
		if p.distance_to(Vector2(item.at.x, item.at.z)) < float(CLEAR[item.model]):
			return false
	for slab: Dictionary in cfg.slabs:
		for sign: float in [1.0, -1.0]:
			if p.distance_to(Vector2(float(slab.at[0]), float(slab.at[1])) * sign) < float(slab.length) * 0.6:
				return false
	for other: Vector2 in placed:
		if p.distance_to(other) < 4.0 or p.distance_to(-other) < 4.0:
			return false
	return p.distance_to(-p) > 8.0

static func obstacle_transform(item: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(item.yaw)), item.at)

# --- Scene -----------------------------------------------------------------

func _enter_tree() -> void:
	ArenaBounds.resize_shell(self, settings().half)
	ARENA_SPAWNS.settings().place_markers(self, "maelstrom")
	# Open edges: no walls and no catch slab. The maelstrom takes what falls.
	for wall: Node3D in get_node("Walls").get_children():
		(wall.get_node("Collision") as CollisionShape3D).disabled = true
	(get_node("Floor/Collision") as CollisionShape3D).disabled = true

func _ready() -> void:
	var slab := get_node_or_null("Floor/Mesh") as MeshInstance3D
	if slab:
		slab.hide()
	var ground := StaticBody3D.new()
	ground.name = "MaelstromIce"
	ground.collision_layer = 1
	ground.collision_mask = 2
	var collider := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = grid_size()
	shape.map_depth = grid_size()
	shape.map_data = grid_heights()
	collider.shape = shape
	collider.scale = Vector3(STEP, 1, STEP)
	ground.add_child(collider)
	add_child(ground)
	var root := Node3D.new()
	root.name = "MaelstromObstacles"
	add_child(root)
	for item: Dictionary in obstacles():
		var body := StaticBody3D.new()
		body.name = item.name
		body.collision_layer = 1
		body.collision_mask = 2
		body.transform = obstacle_transform(item)
		for points: Array in hulls(item.model):
			var hull := ConvexPolygonShape3D.new()
			var packed := PackedVector3Array()
			for point: Array in points:
				packed.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
			hull.points = packed
			var collision := CollisionShape3D.new()
			collision.shape = hull
			body.add_child(collision)
		body.set_meta(&"maelstrom_obstacle", item)
		if String(item.model).begins_with("ice_shards"):
			# Seracs are breakable (ArenaProps kind serac, name prefix IceShards).
			body.set_meta(PROP_META, {"kind":"serac", "name":item.name, "at":item.at, "radius":6.0})
		root.add_child(body)
	var breaks := Node3D.new()
	breaks.name = "MaelstromBreakables"
	add_child(breaks)
	for item: Dictionary in breakables():
		var body := StaticBody3D.new()
		body.name = item.name
		body.collision_layer = 1
		body.collision_mask = 2
		body.transform = obstacle_transform(item)
		for points: Array in hulls(item.model):
			var hull := ConvexPolygonShape3D.new()
			var packed := PackedVector3Array()
			for point: Array in points:
				packed.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
			hull.points = packed
			var collision := CollisionShape3D.new()
			collision.shape = hull
			body.add_child(collision)
		body.set_meta(PROP_META, item)
		breaks.add_child(body)
