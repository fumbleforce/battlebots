extends Node3D
## Deterministic Woodland battlefield for giant bots: a 240 m octagon with a
## central cliff-ringed mesa, raised rock terraces, granite outcrops, pine
## groves, steel-and-concrete jump ramps, bunkers, a turret plinth and log
## barricades. Everything that collides derives from the seeded functions
## below, so server and clients build the same world. No UI, camera, preference
## or global random state. Presentation reads the same data.

const HALF := ArenaBounds.WOODLAND_HALF
const STEP := 1.0
const GRID := 241 # (GRID - 1) * STEP == 2 * HALF
const WALL_HEIGHT := 16.0
const TRUNK_RADIUS := 0.62
const HULL_POINTS := 96
const CUTS := 9
const SCALE := HALF / 50.0 # Shell spawn markers scale with the octagon.

# Central mesa: practice duels happen on its level top; four ramps face the
# team lanes and the gates, cliffs fill the sectors between them.
const MESA_TOP := 7.0
const MESA_RADIUS := 29.0
const MESA_CLIFF := 2.4
const MESA_RAMP := 17.0
## Ramps are wide enough for the roaming giant (#45) to climb on and off.
const MESA_RAMP_ARC := 0.55
# Everything below is authored for the west half and mirrored through the
# centre, so both teams face identical ground.
const TERRACES := [
	{"at":Vector2(-88, -32), "radius":15.0, "height":3.4, "ramp":0.0},
	{"at":Vector2(-82, 46), "radius":9.0, "height":2.4, "ramp":-0.4},
]
const OUTCROPS := [
	{"at":Vector2(-32, -48), "size":2.3, "recipe":0, "seed":11},
	{"at":Vector2(-58, 30), "size":1.8, "recipe":1, "seed":23},
	{"at":Vector2(-20, 64), "size":1.4, "recipe":2, "seed":41},
	{"at":Vector2(-104, 22), "size":1.5, "recipe":2, "seed":53},
]
const RECIPES := [
	[[Vector3(0, 0, 0), Vector3(3.3, 3.0, 2.8), 0.3], [Vector3(2.9, 0, 1.3), Vector3(2.0, 1.8, 1.7), 1.2],
		[Vector3(-2.5, 0, 1.9), Vector3(1.6, 1.25, 1.4), 2.1], [Vector3(1.0, 0, -2.6), Vector3(1.8, 1.5, 1.5), 0.7],
		[Vector3(-3.0, 0, -1.4), Vector3(1.1, 0.8, 1.0), 2.8]],
	[[Vector3(0, 0, 0), Vector3(2.5, 2.2, 2.2), 1.9], [Vector3(-2.2, 0, 1.0), Vector3(1.5, 1.2, 1.3), 0.4],
		[Vector3(1.9, 0, -1.6), Vector3(1.3, 1.0, 1.15), 2.6]],
	[[Vector3(0, 0, 0), Vector3(2.2, 1.7, 1.9), 0.9], [Vector3(1.9, 0, 0.8), Vector3(1.2, 0.9, 1.0), 2.2]],
]
const GROVES := [
	{"at":Vector2(-40, -58), "radius":7.0, "count":4, "seed":101},
	{"at":Vector2(-100, -60), "radius":8.0, "count":5, "seed":103},
	{"at":Vector2(-62, 40), "radius":6.0, "count":3, "seed":107},
	{"at":Vector2(-92, -34), "radius":7.0, "count":4, "seed":109},
	{"at":Vector2(-76, 80), "radius":5.0, "count":3, "seed":113},
]
# Steel-plated concrete jump ramps: base centre, yaw of the rising direction.
const RAMPS := [
	{"at":Vector2(-58, -6), "yaw":PI * 0.5},
	{"at":Vector2(-38, 84), "yaw":PI},
]
const RAMP_LENGTH := 15.0
const RAMP_WIDTH := 8.0
const RAMP_HEIGHT := 5.5
# Riveted concrete bunkers: centre, yaw, size.
const BUNKERS := [
	{"at":Vector2(-48, -76), "yaw":-0.3, "size":Vector3(15, 5.2, 8)},
	{"at":Vector2(-44, 62), "yaw":0.6, "size":Vector3(12, 4.6, 7)},
	{"at":Vector2(-50, -32), "yaw":0.9, "size":Vector3(9, 4.0, 6)},
]
# Round turret plinth on its own rock base.
const PLINTHS := [{"at":Vector2(-82, -2), "radius":5.2, "height":3.4}]
const BARRICADES := [
	{"at":Vector2(-36, 44), "yaw":0.3, "length":14.0},
	{"at":Vector2(-66, -50), "yaw":1.1, "length":12.0},
]
const LOG_RADIUS := 0.75
## Decimated CC0 granite scans (art_source/woodland/build_boulders.py). The same
## low mesh is rendered and, as a convex hull, collides on server and clients.
const BOULDER_MODELS := ["granite_boulder_a", "granite_boulder_b", "granite_boulder_c", "granite_boulder_d", "granite_boulder_e"]
static var _obstacles: Array[Dictionary] = []
static var _scan_meshes: Dictionary = {}

# --- Shared terrain --------------------------------------------------------

static func spawn_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for z: float in [-38.0, 38.0]:
		for x: float in [-24.0, -12.0, 0.0, 12.0, 24.0]:
			points.append(Vector2(x, z) * SCALE)
	for k: int in range(8):
		points.append(Vector2(sin(k * PI / 4.0), cos(k * PI / 4.0)) * 40.0 * SCALE)
	return points

const HEIGHT_CACHE := "res://assets/textures/woodland/terrain_heights.res"

## The authoritative height grid. Computing it is ~1 s of GDScript, so a baked
## copy (tools/bake_woodland_cache.gd) is used when present; the Woodland test
## checks the bake still equals height_at() exactly, so the two cannot drift.
static func grid_heights(use_cache := true) -> PackedFloat32Array:
	if use_cache and ResourceLoader.exists(HEIGHT_CACHE):
		var baked: Resource = load(HEIGHT_CACHE)
		var data: PackedFloat32Array = baked.get_meta(&"heights", PackedFloat32Array())
		if data.size() == GRID * GRID:
			return data
	var heights := PackedFloat32Array()
	heights.resize(GRID * GRID)
	for z: int in range(GRID):
		for x: int in range(GRID):
			heights[z * GRID + x] = height_at(-HALF + x * STEP, -HALF + z * STEP)
	return heights

static func octagon_distance(p: Vector2) -> float:
	return HALF - maxf(maxf(absf(p.x), absf(p.y)), (absf(p.x) + absf(p.y)) * 0.70710678)

## Radial reach of the mesa slope at an angle: steep cliffs except the ramps.
static func mesa_slope(angle: float) -> float:
	var ramp := 0.0
	for k: int in range(4):
		var d := absf(wrapf(angle - k * PI * 0.5, -PI, PI))
		ramp = maxf(ramp, 1.0 - smoothstep(MESA_RAMP_ARC * 0.5, MESA_RAMP_ARC, d))
	return lerpf(MESA_CLIFF, MESA_RAMP, ramp)

static func _terrace(p: Vector2, terrace: Dictionary, sign: float) -> float:
	var centre: Vector2 = terrace.at
	var q := p - centre * sign
	var radius: float = terrace.radius
	# Angles are measured in the terrace's own frame so mirrors match exactly.
	var local := atan2(q.y, q.x) - (PI if sign < 0.0 else 0.0)
	var ramp := 1.0 - smoothstep(0.18, 0.34, absf(wrapf(local - float(terrace.ramp), -PI, PI)))
	var reach := lerpf(2.2, 12.0, ramp)
	# A slightly irregular rim reads as weathered rock, not a cylinder.
	var rim := radius + sin(local * 5.0 + radius) * 1.2
	return float(terrace.height) * (1.0 - smoothstep(rim, rim + reach, q.length()))

static func _rolling(x: float, z: float) -> float:
	return 0.5 + sin(x * 0.047 + 1.3) * cos(z * 0.039 - 0.7) * 0.8 + sin(x * 0.11 + z * 0.083) * 0.3 \
		+ cos(x * 0.023 - z * 0.031) * 0.5 + sin(z * 0.19 - x * 0.07) * 0.15 + sin(x * 0.29 + z * 0.21) * 0.08

static func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	# Averaging each point with its mirror keeps the two team halves identical.
	var h := (_rolling(x, z) + _rolling(-x, -z)) * 0.5
	var level := 1.0
	for spawn: Vector2 in spawn_points():
		level *= smoothstep(13.0, 20.0, p.distance_to(spawn))
	level *= smoothstep(4.0, 12.0, octagon_distance(p))
	h *= level
	for outcrop: Dictionary in OUTCROPS:
		var size: float = outcrop.size
		var centre: Vector2 = outcrop.at
		for sign: float in [1.0, -1.0]:
			h += (1.0 - smoothstep(size * 3.0, size * 6.5, p.distance_to(centre * sign))) * size * 0.4 * level
	var pads := 1.0
	for spawn: Vector2 in spawn_points():
		pads *= smoothstep(13.0, 20.0, p.distance_to(spawn))
	for terrace: Dictionary in TERRACES:
		for sign: float in [1.0, -1.0]:
			h = maxf(h, _terrace(p, terrace, sign) * pads)
	var r := p.length()
	var mesa := MESA_TOP * (1.0 - smoothstep(MESA_RADIUS, MESA_RADIUS + mesa_slope(atan2(p.y, p.x)), r))
	# The mesa top is level for practice; its foot keeps the surrounding roll.
	h = maxf(h * smoothstep(MESA_RADIUS, MESA_RADIUS + 10.0, r), mesa)
	return h

# --- Boulders -------------------------------------------------------------

## Low-frequency boulder surface, shared by collision hulls and render meshes.
static func boulder_radius(direction: Vector3, seed: int) -> float:
	var n := 0.0
	var s := float(seed)
	n += sin(direction.x*2.3+s*1.7)*cos(direction.z*2.1-s*0.9)*0.16
	n += sin(direction.y*3.1+direction.x*1.4+s*0.37)*0.10
	n += cos(direction.z*4.3-direction.y*2.2+s*2.9)*0.06
	return 1.0 + n

static func scan_mesh(model: String) -> Mesh:
	if not _scan_meshes.has(model):
		var scene: Node = load("res://assets/models/woodland/%s.gltf" % model).instantiate()
		var found: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
		_scan_meshes[model] = (found[0] as MeshInstance3D).mesh
		scene.free()
	return _scan_meshes[model]

## Scan variant and placement basis for a boulder item: horizontal scale fits the
## authored radii, height follows within 30% so the scan keeps its character.
static func boulder_pose(item: Dictionary) -> Dictionary:
	var model: String = BOULDER_MODELS[int(item.seed) % BOULDER_MODELS.size()]
	var box := scan_mesh(model).get_aabb()
	var radii: Vector3 = item.radii
	var horizontal := (radii.x + radii.z) / maxf((box.size.x + box.size.z) * 0.5, 0.01)
	var vertical := clampf(radii.y / maxf(box.size.y, 0.01), horizontal * 0.7, horizontal * 1.3)
	var basis := Basis(Vector3.UP, float(item.yaw)).scaled_local(Vector3(horizontal, vertical, horizontal))
	# Sink the footing a little so no scan edge floats on uneven ground.
	return {"model":model, "basis":basis, "sink":box.size.y * vertical * 0.06}

static func scan_hull(item: Dictionary) -> PackedVector3Array:
	var pose := boulder_pose(item)
	var basis: Basis = pose.basis
	var points := PackedVector3Array()
	var vertices: PackedVector3Array = scan_mesh(pose.model).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v: Vector3 in vertices:
		points.append(basis * v - Vector3(0, pose.sink, 0))
	return points

static func boulder_points(radii: Vector3, yaw: float, seed: int, count: int = HULL_POINTS) -> PackedVector3Array:
	var points := PackedVector3Array()
	var golden := PI*(3.0-sqrt(5.0))
	for i: int in range(count):
		var y := 1.0-2.0*(i+0.5)/count
		var ring := sqrt(1.0-y*y)
		points.append(boulder_vertex(Vector3(cos(golden*i)*ring, y, sin(golden*i)*ring), radii, yaw, seed))
	return points

## A unit direction on the boulder's local ellipsoid. Seeded cleavage planes
## shear it into flat granite facets; the base is buried in the ground.
static func boulder_vertex(direction: Vector3, radii: Vector3, yaw: float, seed: int) -> Vector3:
	var p := direction*boulder_radius(direction, seed)
	for k: int in range(CUTS):
		var a := float(seed)*12.9898+k*78.233
		var n := Vector3(sin(a)*1.7, 0.35+absf(sin(a*1.31))*0.9, cos(a*0.77)*1.7).normalized()
		var over := p.dot(n)-(0.66+absf(sin(a*2.11))*0.2)
		if over > 0.0:
			p -= n*over
	p = Vector3(p.x*radii.x, p.y*radii.y*0.8, p.z*radii.z)
	return Basis(Vector3.UP, yaw)*p+Vector3(0, -radii.y*0.1, 0)

# --- Obstacle list --------------------------------------------------------

static func _ground(at: Vector2) -> Vector3:
	return Vector3(at.x, height_at(at.x, at.y), at.y)

## Everything a client or server needs to rebuild identical obstacles.
static func obstacles() -> Array[Dictionary]:
	if not _obstacles.is_empty():
		return _obstacles
	var out: Array[Dictionary] = []
	var index := 0
	# Cliff boulders crown the mesa rim and armour its flanks between ramps.
	var golden := 2.39996
	for n: int in range(26):
		var angle := n * PI / 26.0 + 0.05
		if mesa_slope(angle) > MESA_CLIFF + 1.0:
			continue
		for sign: float in [1.0, -1.0]:
			var a := angle + (PI if sign < 0.0 else 0.0) + sin(n * 3.1) * 0.03
			var radius := MESA_RADIUS + 1.0 + sin(n * golden) * 1.4
			var at := Vector2(cos(a), sin(a)) * radius
			var size := 2.2 + absf(sin(n * 1.7)) * 2.6
			var tall := MESA_TOP + 0.4 + absf(sin(n * 2.3)) * 2.8
			out.append({"kind":"boulder", "at":Vector3(at.x, 0.0, at.y), "radii":Vector3(size, tall, size * (0.6 + absf(sin(n * 0.9)) * 0.5)),
				"yaw":a + PI * 0.5 + sin(n * 5.0) * 0.5, "seed":300 + n, "name":"MesaRock%d_%d" % [n, 0 if sign > 0.0 else 1]})
			if n % 2 == 0:
				var talus := Vector2(cos(a + 0.05), sin(a + 0.05)) * (radius + size * 0.9)
				out.append({"kind":"boulder", "at":_ground(talus), "radii":Vector3(size * 0.5, size * 0.45, size * 0.45),
					"yaw":a, "seed":400 + n, "name":"MesaTalus%d_%d" % [n, 0 if sign > 0.0 else 1]})
	for outcrop: Dictionary in OUTCROPS:
		var size: float = outcrop.size
		var centre: Vector2 = outcrop.at
		for sign: float in [1.0, -1.0]:
			var number := 0
			for boulder: Array in RECIPES[outcrop.recipe]:
				var offset: Vector3 = boulder[0]
				offset *= size * sign
				var radii: Vector3 = boulder[1]
				var at := centre * sign + Vector2(offset.x, offset.z)
				out.append({"kind":"boulder", "at":_ground(at), "radii":radii * size,
					"yaw":float(boulder[2]) + (PI if sign < 0.0 else 0.0), "seed":int(outcrop.seed) * 10 + number,
					"name":"Boulder%d_%d" % [index, number]})
				number += 1
			index += 1
	# Terrace rims: a few big blocks on the cliff edge, away from the ramp.
	for terrace: Dictionary in TERRACES:
		var centre: Vector2 = terrace.at
		var radius: float = terrace.radius
		for sign: float in [1.0, -1.0]:
			for n: int in range(4):
				var a := float(terrace.ramp) + (PI if sign < 0.0 else 0.0) + PI * 0.55 + n * PI * 0.3
				var at := centre * sign + Vector2(cos(a), sin(a)) * (radius + 1.0)
				var size := 2.2 + n * 0.3
				out.append({"kind":"boulder", "at":Vector3(at.x, 0.0, at.y), "radii":Vector3(size * 1.2, float(terrace.height) + 1.4, size),
					"yaw":a, "seed":500 + index * 4 + n, "name":"TerraceRock%d_%d" % [index, n]})
			index += 1
	for grove: Dictionary in GROVES:
		var radius: float = grove.radius
		var count: int = grove.count
		var centre: Vector2 = grove.at
		for sign: float in [1.0, -1.0]:
			for n: int in range(count):
				var a: float = n * golden + float(grove.seed)
				var at: Vector2 = (centre + Vector2(cos(a), sin(a)) * radius * sqrt((n + 0.5) / count)) * sign
				out.append({"kind":"tree", "at":_ground(at), "seed":int(grove.seed) * 10 + n, "name":"Trunk%d_%d" % [index, n]})
			index += 1
	for ramp: Dictionary in RAMPS:
		var centre: Vector2 = ramp.at
		for sign: float in [1.0, -1.0]:
			out.append({"kind":"ramp", "at":_ground(centre * sign), "yaw":float(ramp.yaw) + (PI if sign < 0.0 else 0.0), "name":"JumpRamp%d" % index})
			index += 1
	for bunker: Dictionary in BUNKERS:
		var centre: Vector2 = bunker.at
		for sign: float in [1.0, -1.0]:
			out.append({"kind":"bunker", "at":_ground(centre * sign), "yaw":float(bunker.yaw) + (PI if sign < 0.0 else 0.0),
				"size":bunker.size, "name":"Bunker%d" % index})
			index += 1
	for plinth: Dictionary in PLINTHS:
		var centre: Vector2 = plinth.at
		for sign: float in [1.0, -1.0]:
			out.append({"kind":"plinth", "at":_ground(centre * sign), "radius":plinth.radius, "height":plinth.height, "name":"Plinth%d" % index})
			index += 1
	for barricade: Dictionary in BARRICADES:
		var centre: Vector2 = barricade.at
		for sign: float in [1.0, -1.0]:
			out.append({"kind":"barricade", "at":_ground(centre * sign), "yaw":float(barricade.yaw) + (PI if sign < 0.0 else 0.0),
				"length":barricade.length, "name":"Barricade%d" % index})
			index += 1
	_obstacles = out
	return out

static func footprint(item: Dictionary) -> float:
	match item.kind:
		"tree": return TRUNK_RADIUS
		"boulder": return maxf(item.radii.x, item.radii.z) * 1.1
		"barricade": return float(item.length) * 0.5 + LOG_RADIUS
		"ramp": return RAMP_LENGTH * 0.6
		"bunker": return Vector2(item.size.x, item.size.z).length() * 0.5
		"plinth": return float(item.radius) + 2.5
	return 0.0

static func blocks(point: Vector3, margin: float) -> bool:
	for item: Dictionary in obstacles():
		if Vector2(point.x - item.at.x, point.z - item.at.z).length() < footprint(item) + margin:
			return true
	return false

## Wedge in its local frame: rises along +Z from the ground to RAMP_HEIGHT,
## then a short level lip before the drop.
static func ramp_points() -> PackedVector3Array:
	var w := RAMP_WIDTH * 0.5
	var l := RAMP_LENGTH * 0.5
	var points := PackedVector3Array()
	for x: float in [-w, w]:
		points.append(Vector3(x, -0.6, -l - 0.6))
		points.append(Vector3(x, -0.6, l))
		points.append(Vector3(x, RAMP_HEIGHT, l - 1.6))
		points.append(Vector3(x, RAMP_HEIGHT, l))
	return points

func _enter_tree() -> void:
	# Woodland keeps the shell's walls and spawns, at its own scale and height.
	ArenaBounds.resize_shell(self, HALF)
	for wall: Node3D in get_node("Walls").get_children():
		var collision: CollisionShape3D = wall.get_node("Collision")
		var box := collision.shape as BoxShape3D
		box.size.y = WALL_HEIGHT
		wall.position.y = WALL_HEIGHT * 0.5
		var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			(mesh.mesh as BoxMesh).size = box.size

func _ready() -> void:
	# The terrain replaces the slab's top; keep the slab below as a catch surface.
	get_node("Floor").position.y = -2.0
	var old_mesh := get_node_or_null("Floor/Mesh") as MeshInstance3D
	if old_mesh:
		old_mesh.hide()
	var heights := grid_heights()
	var ground := StaticBody3D.new()
	ground.name = "WoodlandTerrain"
	ground.collision_layer = 1
	ground.collision_mask = 2
	var collider := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = GRID
	shape.map_depth = GRID
	shape.map_data = heights
	collider.shape = shape
	collider.scale = Vector3(STEP, 1, STEP)
	ground.add_child(collider)
	ground.set_meta(&"heights", heights)
	add_child(ground)
	var root := Node3D.new()
	root.name = "WoodlandObstacles"
	add_child(root)
	for item: Dictionary in obstacles():
		var body := StaticBody3D.new()
		body.name = item.name
		body.collision_layer = 1
		body.collision_mask = 2
		body.position = item.at
		match item.kind:
			"boulder":
				var hull := ConvexPolygonShape3D.new()
				hull.points = scan_hull(item)
				_shape(body, hull, Transform3D.IDENTITY)
			"tree":
				var trunk := CylinderShape3D.new()
				trunk.radius = TRUNK_RADIUS
				trunk.height = 14.0
				_shape(body, trunk, Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 0)))
			"barricade":
				body.rotation.y = item.yaw
				var log := CylinderShape3D.new()
				log.radius = LOG_RADIUS
				log.height = item.length
				var lie := Basis(Vector3.BACK, PI / 2.0)
				for at: Vector3 in [Vector3(0, LOG_RADIUS - 0.2, -LOG_RADIUS), Vector3(0, LOG_RADIUS - 0.2, LOG_RADIUS),
						Vector3(0, LOG_RADIUS * 2.55 - 0.2, 0)]:
					_shape(body, log, Transform3D(lie, at))
			"ramp":
				body.rotation.y = item.yaw
				var wedge := ConvexPolygonShape3D.new()
				wedge.points = ramp_points()
				_shape(body, wedge, Transform3D.IDENTITY)
			"bunker":
				body.rotation.y = item.yaw
				var box := BoxShape3D.new()
				box.size = item.size + Vector3(0, 1.0, 0)
				_shape(body, box, Transform3D(Basis.IDENTITY, Vector3(0, item.size.y * 0.5 - 0.5, 0)))
			"plinth":
				var drum := CylinderShape3D.new()
				drum.radius = item.radius
				drum.height = float(item.height) + 1.0
				_shape(body, drum, Transform3D(Basis.IDENTITY, Vector3(0, float(item.height) * 0.5 - 0.5, 0)))
		body.set_meta(&"woodland_obstacle", item)
		root.add_child(body)

func _shape(body: StaticBody3D, shape: Shape3D, pose: Transform3D) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = pose
	body.add_child(collision)
