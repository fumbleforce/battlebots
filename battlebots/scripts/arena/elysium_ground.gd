extends Node3D
## Deterministic Elysium battlefield (#115): marble islands floating in heaven
## above a sea of clouds. The raised Sanctum in the middle carries the rotunda;
## the broad Halo ring around it holds every start; four railless bridges cross
## the chasm between them, and cloud wells are punched through the Halo.
## Everything that collides derives from data/elysium_arena.json, so the server
## and every client build the same world without loading any art. There are no
## walls: off the islands the height map drops to void_depth, and a bot that
## drops below kill_y (mvp_bot.gd) falls to its death.
## Everything is mirrored through the centre, so both teams face identical ground.

const CONFIG := "res://data/elysium_arena.json"
const STEP := 1.0
const ARENA_SPAWNS = preload("res://scripts/core/arena_spawns.gd")
## Collision primitives: a column's plinth and the entablature over a colonnade.
const PLINTH := Vector3(3.2, 0.9, 3.2)
const BEAM := Vector2(3.0, 1.8)
## Triumphal arch piers (width along the span, depth along the passage) and attic height.
const PIER := Vector2(4.5, 5.5)
const ATTIC := 4.0
## Obelisk shaft half-widths at the base and top, and its pedestal.
const OBELISK := Vector2(1.9, 1.1)
const PEDESTAL := Vector3(5.6, 1.6, 5.6)
const COLUMN_RADIUS := 1.15
const STUMP_RADIUS := 1.35
const RAIL_DEPTH := 0.9
## Balustrade segments are chords at most this long (m).
const RAIL_CHORD := 4.0

class Layout extends RefCounted:
	var half: float
	var kill_y: float
	var sink_depth: float
	var void_depth: float
	var sanctum: Dictionary
	var halo: Dictionary
	var bridges: Dictionary
	var wells: Array = []
	var mounds: Array = []
	var pad_radius: float
	var pad_blend: float
	var rotunda: Dictionary
	var structures: Array = []
	var art: Dictionary

static var _layout: Layout
static var _heights := PackedFloat32Array()
static var _sdf := PackedFloat32Array()
static var _pads := PackedVector2Array()
static var _structures: Array[Dictionary] = []
static var _wells: Array[Dictionary] = []
static var _mounds: Array[Dictionary] = []
static var _bridge_angles := PackedFloat32Array()
## Start pads bucketed by PAD_CELL-metre cells for nearest-pad queries.
static var _pad_cells: Dictionary = {}
const PAD_CELL := 32.0

static func settings() -> Layout:
	if _layout == null:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		assert(data is Dictionary, "Invalid Elysium configuration: " + CONFIG)
		var parsed := Layout.new()
		for key: String in ["half", "kill_y", "sink_depth", "void_depth", "pad_radius", "pad_blend"]:
			parsed.set(key, float(data[key]))
		parsed.sanctum = data.sanctum
		parsed.halo = data.halo
		parsed.bridges = data.bridges
		parsed.wells = data.wells
		parsed.mounds = data.mounds
		parsed.rotunda = data.rotunda
		parsed.structures = data.structures
		parsed.art = data.art
		assert(float(data.grid_step) == STEP, "Elysium grid step must be %s" % STEP)
		assert(int(parsed.rotunda.columns) % 2 == 0, "Rotunda columns must be even for point symmetry")
		assert(float(parsed.halo.outer) + float(parsed.halo.jag) < parsed.half - 4.0, "Elysium Halo must fit its grid")
		assert(float(parsed.sanctum.radius) + float(parsed.sanctum.jag) < float(parsed.halo.inner) - float(parsed.halo.jag) - 6.0, "Elysium needs a chasm round the Sanctum")
		assert(parsed.kill_y < 0.0 and parsed.kill_y > parsed.void_depth, "Elysium kill height lies between the islands and the void")
		_layout = parsed
	return _layout

static func grid_size() -> int:
	return roundi(settings().half * 2.0 / STEP) + 1

# --- Island shapes -----------------------------------------------------------
# Edges wobble with even harmonics of the bearing only, so a point and its
# mirror (bearing + PI) always share an edge radius.

static func sanctum_radius(angle: float) -> float:
	var cfg := settings()
	return float(cfg.sanctum.radius) + float(cfg.sanctum.jag) * (0.6 * sin(angle * 6.0 + 0.4) + 0.4 * sin(angle * 14.0 + 1.3))

static func halo_inner(angle: float) -> float:
	var cfg := settings()
	return float(cfg.halo.inner) + float(cfg.halo.jag) * (0.55 * sin(angle * 4.0 + 1.0) + 0.45 * sin(angle * 10.0 + 2.0))

static func halo_outer(angle: float) -> float:
	var cfg := settings()
	return float(cfg.halo.outer) + float(cfg.halo.jag) * (0.55 * sin(angle * 6.0 + 0.2) + 0.3 * sin(angle * 16.0 + 2.2) + 0.15 * sin(angle * 34.0 + 0.7))

## Bridge bearings, authored and mirrored.
static func bridge_angles() -> PackedFloat32Array:
	if _bridge_angles.is_empty():
		for angle: Variant in settings().bridges.angles:
			_bridge_angles.append(float(angle))
			_bridge_angles.append(float(angle) + PI)
	return _bridge_angles

## Every authored point with its mirror.
static func _mirrored(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in list:
		for sign: float in [1.0, -1.0]:
			var copy := entry.duplicate()
			copy.at = Vector2(float(entry.at[0]), float(entry.at[1])) * sign
			out.append(copy)
	return out

static func wells() -> Array[Dictionary]:
	if _wells.is_empty():
		_wells = _mirrored(settings().wells)
	return _wells

static func mounds() -> Array[Dictionary]:
	if _mounds.is_empty():
		_mounds = _mirrored(settings().mounds)
	return _mounds

## Signed distance (m, negative inside) to the edge of the Sanctum, the Halo
## (less its wells) and the bridges. Radial, so only approximately Euclidean.
static func sanctum_sdf(p: Vector2) -> float:
	return p.length() - sanctum_radius(p.angle())

static func halo_sdf(p: Vector2) -> float:
	var r := p.length()
	var angle := p.angle()
	var d := maxf(halo_inner(angle) - r, r - halo_outer(angle))
	for well: Dictionary in wells():
		d = maxf(d, float(well.radius) - p.distance_to(well.at))
	return d

## Distance along and across the nearest bridge, and how far inside it.
static func bridge_sdf(p: Vector2) -> float:
	var cfg := settings()
	var best := INF
	var overlap := float(cfg.bridges.overlap)
	for angle: float in bridge_angles():
		var dir := Vector2(cos(angle), sin(angle))
		var along := p.dot(dir)
		var across := absf(p.dot(Vector2(-dir.y, dir.x)))
		var d := maxf(across - float(cfg.bridges.width) * 0.5,
			maxf(sanctum_radius(angle) - overlap - along, along - halo_inner(angle) - overlap))
		best = minf(best, d)
	return best

## Start pads are always solid ground.
static func pad_sdf(p: Vector2) -> float:
	return nearest_pad(p) - settings().pad_radius

## Distance (m) to the nearest start pad, exact within PAD_CELL metres (INF beyond).
static func nearest_pad(p: Vector2) -> float:
	if _pad_cells.is_empty():
		for pad: Vector2 in pads():
			var key := Vector2i(floori(pad.x / PAD_CELL), floori(pad.y / PAD_CELL))
			if not _pad_cells.has(key):
				_pad_cells[key] = PackedVector2Array()
			_pad_cells[key].append(pad)
	var cell := Vector2i(floori(p.x / PAD_CELL), floori(p.y / PAD_CELL))
	var best := INF
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var bucket: Variant = _pad_cells.get(cell + Vector2i(dx, dz))
			if bucket != null:
				for pad: Vector2 in bucket:
					best = minf(best, p.distance_squared_to(pad))
	return sqrt(best) if best <= PAD_CELL * PAD_CELL else INF

static func land_sdf(x: float, z: float) -> float:
	var p := Vector2(x, z)
	return minf(minf(sanctum_sdf(p), halo_sdf(p)), minf(bridge_sdf(p), pad_sdf(p)))

## True where a point stands on solid island (not over the chasm, a well or the sky).
static func on_land(x: float, z: float) -> bool:
	return land_sdf(x, z) <= 0.0

## Start pads: every team and free-for-all start, and the Practice Duel places
## (player, far Atlas, the monowheel block and the shuttle's run), mirrored.
static func pads() -> PackedVector2Array:
	if _pads.is_empty():
		var spawns := ARENA_SPAWNS.settings()
		var points := spawns.points("elysium")
		var c3 := spawns.duel_centre_for("elysium")
		var centre := Vector2(c3.x, c3.z)
		var reach := ArenaBounds.half_extent("elysium") * spawns.duel_monowheel_side_for("elysium")
		for offset: Vector2 in [Vector2.ZERO, Vector2(0, -reach), Vector2(-reach, 0), Vector2(reach, 0), Vector2(reach, -spawns.duel_shuttle_travel),
				Vector2(reach, spawns.duel_shuttle_travel)]:
			points.append(centre + offset)
			points.append(-(centre + offset))
		_pads = points
	return _pads

# --- Heights -----------------------------------------------------------------

## Height of the Halo's lawns: gentle rolling (cosines are even, so mirrors
## match) and raised gardens, easing flat on the start pads.
static func halo_height(x: float, z: float) -> float:
	var cfg := settings()
	var p := Vector2(x, z)
	var h := float(cfg.halo.roll) * (cos(x * 0.045 + z * 0.031) * cos(z * 0.052 - x * 0.037) + 0.5 * cos(x * 0.11 - z * 0.083))
	for mound: Dictionary in mounds():
		var t := 1.0 - smoothstep(0.0, float(mound.radius), p.distance_to(mound.at))
		h += float(mound.height) * t * t * (3.0 - 2.0 * t)
	assert(cfg.pad_radius + cfg.pad_blend <= PAD_CELL)
	return h * smoothstep(cfg.pad_radius, cfg.pad_radius + cfg.pad_blend, nearest_pad(p))

static func sanctum_height(r: float) -> float:
	var cfg := settings()
	var dais := 1.0 - smoothstep(float(cfg.sanctum.dais_radius), float(cfg.sanctum.dais_radius) + float(cfg.sanctum.dais_blend), r)
	return float(cfg.sanctum.height) + float(cfg.sanctum.dais_height) * dais

static func height_at(x: float, z: float) -> float:
	return _sample(x, z).x

## Height and land signed distance at a point.
static func _sample(x: float, z: float) -> Vector2:
	var cfg := settings()
	var p := Vector2(x, z)
	var sanctum := sanctum_sdf(p)
	if sanctum <= 0.0:
		return Vector2(sanctum_height(p.length()), minf(sanctum, land_sdf(x, z)))
	var halo := minf(halo_sdf(p), pad_sdf(p))
	if halo <= 0.0:
		return Vector2(halo_height(x, z), minf(halo, minf(sanctum, bridge_sdf(p))))
	var bridge := bridge_sdf(p)
	if bridge <= 0.0:
		# A straight ramp from the Sanctum's edge down to the Halo's.
		var angle := p.angle()
		var from := sanctum_radius(angle)
		var t := clampf((p.length() - from) / maxf(halo_inner(angle) - from, 1.0), 0.0, 1.0)
		return Vector2(lerpf(sanctum_height(from), halo_height(x, z), t), minf(bridge, minf(sanctum, halo)))
	return Vector2(cfg.void_depth, minf(bridge, minf(sanctum, halo)))

## The authoritative height grid, computed once per process.
static func grid_heights() -> PackedFloat32Array:
	if _heights.is_empty():
		var n := grid_size()
		var half := settings().half
		var heights := PackedFloat32Array()
		var sdf := PackedFloat32Array()
		heights.resize(n * n)
		sdf.resize(n * n)
		for z: int in range(n):
			for x: int in range(n):
				var sample := _sample(-half + x * STEP, -half + z * STEP)
				heights[z * n + x] = sample.x
				sdf[z * n + x] = sample.y
		_heights = heights
		_sdf = sdf
	return _heights

## land_sdf on the same grid (presentation builds its island edges from it).
static func grid_sdf() -> PackedFloat32Array:
	grid_heights()
	return _sdf

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

# --- Architecture ------------------------------------------------------------

## Every structure, the rotunda and the authored ones with their mirrors:
## {name, type, base: Transform3D on the ground, parts: Array of collision
## primitives {shape: "box"|"cylinder"|"hull", xform (shape centre, arena
## frame), size | radius + height | points}} plus type parameters for the art.
static func structures() -> Array[Dictionary]:
	if not _structures.is_empty():
		return _structures
	var cfg := settings()
	var out: Array[Dictionary] = []
	out.append(_rotunda())
	var index := 0
	for entry: Dictionary in cfg.structures:
		for sign: float in [1.0, -1.0]:
			var item := {"name":"%s%d" % [String(entry.type).to_pascal_case(), index], "type":String(entry.type),
				"height":float(entry.height), "parts":[]}
			index += 1
			match String(entry.type):
				"colonnade":
					_colonnade(item, Vector2(float(entry.from[0]), float(entry.from[1])) * sign, Vector2(float(entry.to[0]), float(entry.to[1])) * sign, int(entry.count))
				"arch":
					_arch(item, Vector2(float(entry.at[0]), float(entry.at[1])) * sign, float(entry.yaw) + (PI if sign < 0.0 else 0.0), float(entry.span))
				"obelisk":
					_obelisk(item, Vector2(float(entry.at[0]), float(entry.at[1])) * sign)
				"stump":
					_stump(item, Vector2(float(entry.at[0]), float(entry.at[1])) * sign)
				"balustrade":
					_balustrade(item, float(entry.arc[0]) + (PI if sign < 0.0 else 0.0), float(entry.arc[1]) + (PI if sign < 0.0 else 0.0), float(entry.radius))
			out.append(item)
	_structures = out
	return out

static func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y), p.y)

static func _box(item: Dictionary, size: Vector3, centre: Vector3, yaw := 0.0) -> void:
	item.parts.append({"shape":"box", "size":size, "xform":Transform3D(Basis(Vector3.UP, yaw), centre)})

static func _cylinder(item: Dictionary, radius: float, height: float, base: Vector3) -> void:
	item.parts.append({"shape":"cylinder", "radius":radius, "height":height, "xform":Transform3D(Basis.IDENTITY, base + Vector3.UP * height * 0.5)})

static func _rotunda() -> Dictionary:
	var cfg := settings().rotunda
	var floor_y := sanctum_height(0.0)
	var item := {"name":"Rotunda", "type":"rotunda", "base":Transform3D(Basis.IDENTITY, Vector3(0, floor_y, 0)), "parts":[],
		"columns":int(cfg.columns), "radius":float(cfg.radius), "column_radius":float(cfg.column_radius), "height":float(cfg.height),
		"entablature":float(cfg.entablature), "dome_rise":float(cfg.dome_rise)}
	var count := int(cfg.columns)
	var radius := float(cfg.radius)
	var height := float(cfg.height)
	for i: int in count:
		var a := TAU * (float(i) + 0.5) / count
		_cylinder(item, float(cfg.column_radius), height, Vector3(cos(a) * radius, floor_y, sin(a) * radius))
	# The ring entablature: one chord per bay, over the column tops.
	var top := floor_y + height
	var chord := 2.0 * (radius + 1.5) * sin(PI / count) + 0.6
	for i: int in count:
		var a := TAU * float(i) / count
		_box(item, Vector3(chord, float(cfg.entablature), 3.4), Vector3(cos(a) * radius, top + float(cfg.entablature) * 0.5, sin(a) * radius), PI * 0.5 - a)
	# The dome, a hull over the entablature.
	var points := PackedVector3Array()
	var dome_r := radius + 1.5
	var rise := float(cfg.dome_rise)
	var base_y := top + float(cfg.entablature)
	for ring: int in 5:
		var t := float(ring) / 5.0
		var rr := dome_r * cos(t * PI * 0.5)
		for s: int in 16:
			var a := TAU * float(s) / 16.0
			points.append(Vector3(cos(a) * rr, base_y + rise * sin(t * PI * 0.5), sin(a) * rr))
	points.append(Vector3(0, base_y + rise, 0))
	item.parts.append({"shape":"hull", "points":points, "xform":Transform3D.IDENTITY})
	return item

static func _colonnade(item: Dictionary, from: Vector2, to: Vector2, count: int) -> void:
	var height := float(item.height)
	var dir := (to - from).normalized()
	var yaw := atan2(-dir.y, dir.x)
	var low := INF
	var columns: Array[Vector3] = []
	for i: int in count:
		var p := from.lerp(to, float(i) / float(maxi(count - 1, 1)))
		var base := _ground(p)
		columns.append(base)
		low = minf(low, base.y)
	var top := INF
	for base: Vector3 in columns:
		_box(item, PLINTH, base + Vector3.UP * (PLINTH.y * 0.5 - 0.3))
		_cylinder(item, COLUMN_RADIUS, height, base)
		top = minf(top, base.y + height)
	var mid := (from + to) * 0.5
	_box(item, Vector3(from.distance_to(to) + PLINTH.x, BEAM.y, BEAM.x), Vector3(mid.x, top + BEAM.y * 0.5, mid.y), yaw)
	item.base = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, low, mid.y))
	item.columns = columns
	item.top = top

static func _arch(item: Dictionary, at: Vector2, yaw: float, span: float) -> void:
	var height := float(item.height)
	var basis := Basis(Vector3.UP, yaw)
	var base := _ground(at)
	for side: float in [-1.0, 1.0]:
		var offset := basis * Vector3(side * (span + PIER.x) * 0.5, 0, 0)
		var foot := _ground(at + Vector2(offset.x, offset.z))
		var bottom := minf(foot.y, base.y) - 0.5
		_box(item, Vector3(PIER.x, height - ATTIC - bottom + base.y, PIER.y), Vector3(foot.x, (bottom + base.y + height - ATTIC) * 0.5, foot.z), yaw)
	_box(item, Vector3(span + PIER.x * 2.0, ATTIC, PIER.y), base + Vector3.UP * (height - ATTIC * 0.5), yaw)
	item.base = Transform3D(basis, base)
	item.span = span

static func _obelisk(item: Dictionary, at: Vector2) -> void:
	var height := float(item.height)
	var base := _ground(at)
	_box(item, PEDESTAL, base + Vector3.UP * (PEDESTAL.y * 0.5 - 0.4))
	var points := PackedVector3Array()
	var shaft := height - 2.0
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		points.append(base + Vector3(corner.x * OBELISK.x, PEDESTAL.y - 0.4, corner.y * OBELISK.x))
		points.append(base + Vector3(corner.x * OBELISK.y, shaft, corner.y * OBELISK.y))
	points.append(base + Vector3(0, height, 0))
	item.parts.append({"shape":"hull", "points":points, "xform":Transform3D.IDENTITY})
	item.base = Transform3D(Basis.IDENTITY, base)

static func _stump(item: Dictionary, at: Vector2) -> void:
	var base := _ground(at)
	_box(item, PLINTH, base + Vector3.UP * (PLINTH.y * 0.5 - 0.3))
	_cylinder(item, STUMP_RADIUS, float(item.height), base)
	item.base = Transform3D(Basis.IDENTITY, base)

static func _balustrade(item: Dictionary, from: float, to: float, radius: float) -> void:
	var height := float(item.height)
	var segments := maxi(1, ceili(radius * (to - from) / RAIL_CHORD))
	var posts: Array[Vector3] = []
	for i: int in segments + 1:
		var a := lerpf(from, to, float(i) / segments)
		posts.append(_ground(Vector2(cos(a), sin(a)) * radius))
	for i: int in segments:
		var a: Vector3 = posts[i]
		var b: Vector3 = posts[i + 1]
		var mid := (a + b) * 0.5
		var along := Vector2(b.x - a.x, b.z - a.z)
		_box(item, Vector3(along.length() + RAIL_DEPTH, height, RAIL_DEPTH), Vector3(mid.x, mid.y + height * 0.5, mid.z), atan2(-along.y, along.x))
	item.base = Transform3D(Basis.IDENTITY, posts[0])
	item.posts = posts

# --- Scene -------------------------------------------------------------------

func _enter_tree() -> void:
	ArenaBounds.resize_shell(self, settings().half)
	ARENA_SPAWNS.settings().place_markers(self, "elysium")
	# Open edges: no walls and no catch slab. The sky takes what falls.
	for wall: Node3D in get_node("Walls").get_children():
		(wall.get_node("Collision") as CollisionShape3D).disabled = true
	(get_node("Floor/Collision") as CollisionShape3D).disabled = true

func _ready() -> void:
	var slab := get_node_or_null("Floor/Mesh") as MeshInstance3D
	if slab:
		slab.hide()
	var ground := StaticBody3D.new()
	ground.name = "ElysiumIslands"
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
	root.name = "ElysiumStructures"
	add_child(root)
	for item: Dictionary in structures():
		var body := StaticBody3D.new()
		body.name = item.name
		body.collision_layer = 1
		body.collision_mask = 2
		for part: Dictionary in item.parts:
			var collision := CollisionShape3D.new()
			match String(part.shape):
				"box":
					var box := BoxShape3D.new()
					box.size = part.size
					collision.shape = box
				"cylinder":
					var cylinder := CylinderShape3D.new()
					cylinder.radius = part.radius
					cylinder.height = part.height
					collision.shape = cylinder
				"hull":
					var hull := ConvexPolygonShape3D.new()
					hull.points = part.points
					collision.shape = hull
			collision.transform = part.xform
			body.add_child(collision)
		body.set_meta(&"elysium_structure", item.name)
		root.add_child(body)
