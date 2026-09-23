extends Node3D
## Woodland presentation only. Never creates bodies, changes spawns or reads
## match state; it renders the shared data in woodland_ground.gd. The palisade
## is built for giant bots, while walkways, stands and spectators stay human
## scale above it. Repeated construction is batched by material and mesh into
## MultiMeshes; each face is authored once in a local frame whose inner wall
## plane is z = W and rotated around the octagon.

const GROUND = preload("res://scripts/arena/woodland_ground.gd")
const FLORA = preload("res://scripts/arena/woodland_flora.gd")
const NATURE = preload("res://scripts/arena/woodland_nature.gd")
const SKY = preload("res://assets/materials/arena/woodland_sky.gdshader")
## Views span the 240 m bowl and the valley; see #34 for the camera handoff.
const VIEW_DISTANCE := 1600.0
const WOOD = preload("res://assets/materials/arena/woodland_wood.gdshader")
const IRON = preload("res://assets/materials/arena/woodland_iron.gdshader")
const CANVAS = preload("res://assets/materials/arena/woodland_canvas.gdshader")
const BANNER = preload("res://assets/materials/arena/woodland_banner.gdshader")
const CROWD = preload("res://assets/materials/arena/woodland_crowd.gdshader")
const DIRT = preload("res://assets/materials/arena/woodland_dirt.gdshader")
const ROCK = preload("res://assets/materials/arena/woodland_rock.gdshader")
const SCREEN = preload("res://assets/materials/arena/woodland_screen.gdshader")
const CONCRETE = preload("res://assets/materials/arena/woodland_concrete.gdshader")
const FLAME = preload("res://assets/materials/arena/woodland_flame.gdshader")
const HALF := GROUND.HALF
const W := -HALF # Inner wall plane in the face frame; equals the collision plane.
const FACE := HALF * 0.41421356 # Half an octagon face.
const BAYS := 12
const BUMPER := 3.15 # Top of the three stacked impact beams.
const DECK := 14.6 # Walkway on top of the palisade.
const TIERS := 12
const CYAN := Color(0.07, 0.42, 0.62)
const ORANGE := Color(0.82, 0.3, 0.05)
const TOWER_RADIUS := 134.5
const TOWER_HEIGHT := 44.0
@export var arena_path: NodePath = NodePath("..")
var _batches: Dictionary = {}
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _side := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless":
		return
	# The arena root builds its terrain after this child is ready.
	_build.call_deferred()

func _process(_delta: float) -> void:
	# The shared orbit camera defaults to a Foundry-sized far plane. Until an
	# arena view distance is published to it, extend whichever camera views
	# this arena so the far walls and valley are not clipped.
	var camera := get_viewport().get_camera_3d()
	if camera and camera.far < VIEW_DISTANCE:
		camera.far = VIEW_DISTANCE

func _build() -> void:
	_rng.seed = 7_2026
	_make_materials()
	var arena := get_node(arena_path)
	for wall: Node in arena.get_node("Walls").get_children():
		var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			mesh.hide()
	(arena.get_node("Markings") as Node3D).hide()
	_lighting(arena)
	_terrain(arena)
	for side: int in range(8):
		_side = Transform3D(Basis(Vector3.UP, side * PI / 4.0), Vector3.ZERO)
		_face(side)
	for corner: int in range(8):
		_side = Transform3D(Basis(Vector3.UP, corner * PI / 4.0 + PI / 8.0), Vector3.ZERO)
		_tower()
	_side = Transform3D.IDENTITY
	_scoreboard()
	for item: Dictionary in GROUND.obstacles():
		match item.kind:
			"barricade":
				_side = Transform3D(Basis(Vector3.UP, item.yaw), item.at)
				_barricade(item.length)
			"ramp":
				_side = Transform3D(Basis(Vector3.UP, item.yaw), item.at)
				_jump_ramp()
			"bunker":
				_side = Transform3D(Basis(Vector3.UP, item.yaw), item.at)
				_bunker(item.size)
			"plinth":
				_side = Transform3D(Basis.IDENTITY, item.at)
				_plinth(item.radius, item.height)
	_side = Transform3D.IDENTITY
	var flora := FLORA.new()
	flora.name = "Flora"
	add_child(flora)
	var nature := NATURE.new()
	nature.name = "Surroundings"
	nature.flora = flora
	add_child(nature)
	nature.build()
	_flush()
	_outcrops()
	flora.build_interior(arena.get_node("WoodlandTerrain").get_meta(&"heights"))
	set_process(true)
	var probe := ReflectionProbe.new()
	probe.name = "ClearingReflections"
	probe.position = Vector3(0, 12, 0)
	probe.size = Vector3(250, 50, 250)
	probe.origin_offset = Vector3(0, -8, 0)
	probe.max_distance = 600
	probe.box_projection = true
	probe.intensity = 1.0
	add_child(probe)

# --- Terrain and water ---------------------------------------------------

func _terrain(arena: Node) -> void:
	# Twice the collision resolution: the heights are bilinear samples of the
	# physical grid, and the dirt shader cuts the tank ruts in the vertex stage.
	var ground := arena.get_node("WoodlandTerrain") as Node3D
	var heights: PackedFloat32Array = ground.get_meta(&"heights")
	var grid := GROUND.GRID
	var res := (grid - 1) * 2 + 1
	var step := GROUND.STEP * 0.5
	var samples := PackedFloat32Array()
	samples.resize(res * res)
	for z: int in range(res):
		for x: int in range(res):
			var gx := x >> 1
			var gz := z >> 1
			var fx := (x & 1) * 0.5
			var fz := (z & 1) * 0.5
			var x1 := mini(gx + 1, grid - 1)
			var z1 := mini(gz + 1, grid - 1)
			samples[z * res + x] = lerpf(lerpf(heights[gz * grid + gx], heights[gz * grid + x1], fx),
				lerpf(heights[z1 * grid + gx], heights[z1 * grid + x1], fx), fz)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(res * res)
	normals.resize(res * res)
	for z: int in range(res):
		for x: int in range(res):
			var i := z * res + x
			vertices[i] = Vector3(-HALF + x * step, samples[i], -HALF + z * step)
			var hl := samples[z * res + maxi(x - 1, 0)]
			var hr := samples[z * res + mini(x + 1, res - 1)]
			var hd := samples[maxi(z - 1, 0) * res + x]
			var hu := samples[mini(z + 1, res - 1) * res + x]
			normals[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	var indices := PackedInt32Array()
	indices.resize((res - 1) * (res - 1) * 6)
	var k := 0
	for z: int in range(res - 1):
		for x: int in range(res - 1):
			var a := z * res + x
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + res
			indices[k + 3] = a + 1
			indices[k + 4] = a + res + 1
			indices[k + 5] = a + res
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var dirt := ShaderMaterial.new()
	dirt.shader = DIRT
	var clusters := PackedVector4Array()
	for outcrop: Dictionary in GROUND.OUTCROPS:
		for sign: float in [1.0, -1.0]:
			var at: Vector2 = outcrop.at
			clusters.append(Vector4(at.x * sign, at.y * sign, float(outcrop.size) * 4.0, 0))
	dirt.set_shader_parameter("clusters", clusters)
	dirt.set_shader_parameter("arena_half_extent", HALF)
	mesh.surface_set_material(0, dirt)
	var visual := MeshInstance3D.new()
	visual.name = "TerrainSurface"
	visual.mesh = mesh
	add_child(visual)

# --- Materials -----------------------------------------------------------

func _shader(key: String, shader: Shader, params: Dictionary) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for name: String in params:
		mat.set_shader_parameter(name, params[name])
	_materials[key] = mat

func _make_materials() -> void:
	_shader("plank", WOOD, {"fresh_color":Color(0.47, 0.33, 0.21), "aged_color":Color(0.45, 0.42, 0.38),
		"weathering":0.6, "pith_offset":1.0, "moss":0.35})
	_shader("timber", WOOD, {"fresh_color":Color(0.37, 0.25, 0.15), "aged_color":Color(0.36, 0.33, 0.29),
		"weathering":0.4, "tar":0.5, "pith_offset":0.15, "hewn":1.0, "ring_density":14.0, "moss":0.25})
	_shader("rail", WOOD, {"fresh_color":Color(0.43, 0.3, 0.19), "aged_color":Color(0.42, 0.39, 0.35),
		"weathering":0.5, "tar":0.2, "pith_offset":0.3, "hewn":0.6, "ring_density":16.0, "moss":0.15, "mud_height":0.2})
	_shader("deck", WOOD, {"fresh_color":Color(0.46, 0.33, 0.22), "aged_color":Color(0.47, 0.44, 0.4),
		"weathering":0.75, "pith_offset":1.0, "moss":0.1, "mud_height":0.0})
	_shader("log", WOOD, {"fresh_color":Color(0.42, 0.3, 0.2), "aged_color":Color(0.4, 0.37, 0.33),
		"weathering":0.55, "pith_offset":0.0, "ring_density":16.0, "moss":0.4})
	_shader("iron", IRON, {})
	_shader("rusty", IRON, {"rust_amount":0.8})
	# Diamond-plate decks are scuffed matte, so the low sun cannot flare off them.
	_shader("steel", IRON, {"iron_color":Color(0.3, 0.3, 0.29), "rust_amount":0.15, "roughness_floor":0.68})
	_shader("canvas", CANVAS, {})
	_shader("banner", BANNER, {})
	_shader("crowd", CROWD, {})
	_shader("rock", ROCK, {})
	_shader("concrete", CONCRETE, {})
	_shader("flame", FLAME, {})
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.85, 0.62, 0.08)
	paint.roughness = 0.7
	paint.vertex_color_use_as_albedo = true
	_materials.hazard = paint
	var slit := StandardMaterial3D.new()
	slit.albedo_color = Color(0.015, 0.014, 0.013)
	slit.roughness = 1.0
	_materials.dark_slit = slit
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.93, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.72)
	lamp.emission_energy_multiplier = 5.0
	_materials.lamp = lamp
	var lantern := lamp.duplicate() as StandardMaterial3D
	lantern.emission = Color(1.0, 0.62, 0.28)
	lantern.albedo_color = Color(1.0, 0.7, 0.4)
	lantern.emission_energy_multiplier = 1.8
	_materials.lantern = lantern
	var screen := ShaderMaterial.new()
	screen.shader = SCREEN
	_materials.screen = screen

func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"box":
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			mesh = box
		"cyl":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 1.0
			cyl.radial_segments = 14
			cyl.rings = 1
			mesh = cyl
		"bolt":
			var bolt := CylinderMesh.new()
			bolt.top_radius = 0.42
			bolt.bottom_radius = 0.5
			bolt.height = 1.0
			bolt.radial_segments = 6
			bolt.rings = 0
			mesh = bolt
		"pyr":
			var pyr := CylinderMesh.new()
			pyr.top_radius = 0.0
			pyr.bottom_radius = 0.7071
			pyr.height = 1.0
			pyr.radial_segments = 4
			pyr.rings = 0
			mesh = pyr
		"body":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.5
			capsule.height = 1.0
			capsule.radial_segments = 6
			capsule.rings = 1
			mesh = capsule
		"head":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 6
			sphere.rings = 3
			mesh = sphere
		"flame":
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			quad.center_offset = Vector3(0, 0.5, 0)
			mesh = quad
		"drum":
			var drum := CylinderMesh.new()
			drum.top_radius = 0.5
			drum.bottom_radius = 0.5
			drum.height = 1.0
			drum.radial_segments = 32
			drum.rings = 1
			mesh = drum
		"bowl":
			var bowl := CylinderMesh.new()
			bowl.top_radius = 0.5
			bowl.bottom_radius = 0.3
			bowl.height = 1.0
			bowl.radial_segments = 12
			bowl.rings = 1
			mesh = bowl
		"banner":
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE
			plane.subdivide_width = 6
			plane.subdivide_depth = 16
			mesh = plane
	_meshes[kind] = mesh
	return mesh

# --- Batching ------------------------------------------------------------

func _add(mat: String, kind: String, pose: Transform3D, color: Color = Color.WHITE) -> void:
	var key := mat + "/" + kind
	if not _batches.has(key):
		_batches[key] = {"poses":[], "colors":[]}
	_batches[key].poses.append(_side * pose)
	_batches[key].colors.append(color)

func _box(mat: String, at: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO, color: Color = Color.WHITE, kind: String = "box") -> void:
	_add(mat, kind, Transform3D(Basis.from_euler(rotation).scaled_local(size), at), color)

func _beam(mat: String, a: Vector3, b: Vector3, section: Vector2, color: Color = Color.WHITE, kind: String = "box", hint: Vector3 = Vector3.BACK) -> void:
	var span := b - a
	var axis := span.normalized()
	var x := axis.cross(hint).normalized()
	if x.length_squared() < 0.01:
		x = axis.cross(Vector3.RIGHT).normalized()
	var z := x.cross(axis)
	_add(mat, kind, Transform3D(Basis(x, axis, z).scaled_local(Vector3(section.x, span.length(), section.y)), (a + b) * 0.5), color)

func _log(mat: String, a: Vector3, b: Vector3, radius: float, color: Color = Color.WHITE) -> void:
	_beam(mat, a, b, Vector2(radius * 2.0, radius * 2.0), color, "cyl")

func _bolt(at: Vector3, radius: float = 0.035, normal: Vector3 = Vector3.BACK) -> void:
	_beam("iron", at - normal * 0.01, at + normal * 0.03, Vector2(radius * 2.0, radius * 2.0), Color.WHITE, "bolt", Vector3.UP)

func _tint(spread: float = 0.12) -> Color:
	var v := 1.0 + _rng.randf_range(-spread, spread)
	var warm := _rng.randf_range(-0.04, 0.04)
	return Color(v + warm, v, v - warm)

func _team_color(local: Vector3) -> Color:
	var world := _side * local
	return CYAN if world.z > 0.0 else ORANGE

func _flush() -> void:
	for key: String in _batches:
		var parts := key.split("/")
		var batch: Dictionary = _batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _mesh(parts[1])
		multi.instance_count = batch.poses.size()
		for index: int in range(multi.instance_count):
			multi.set_instance_transform(index, batch.poses[index])
			multi.set_instance_color(index, batch.colors[index])
		var visual := MultiMeshInstance3D.new()
		visual.name = (parts[0] + "_" + parts[1]).capitalize().replace(" ", "") + "Batch"
		visual.multimesh = multi
		visual.material_override = _materials[parts[0]]
		# Small hardware, crowd and cloth do not need to cast the sun's shadow.
		var casts := parts[0] in ["plank", "timber", "rail", "deck", "log", "canvas", "concrete", "iron", "rusty", "steel"] and parts[1] != "bolt"
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	_batches.clear()

func _text(words: String, at: Vector3, size: int, pixel: float, color: Color, outline: int = 0) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = outline
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.shaded = false
	label.double_sided = false
	label.transform = _side * Transform3D(Basis.IDENTITY, at)
	add_child(label)
	return label

# --- Palisade ------------------------------------------------------------

func _face(side: int) -> void:
	var bay_width := FACE * 2.0 / BAYS
	# Faces 2 and 6 are the east/west gates; face 0 carries the scoreboard.
	var gate := side == 2 or side == 6
	for i: int in range(BAYS + 1):
		var x := -FACE + i * bay_width
		if i == 0:
			_corner_post(x)
		elif i < BAYS and i % 3 == 0 and not (gate and i == BAYS / 2):
			_buttress(x, side, i)
		elif i < BAYS:
			_post(x)
		if i == BAYS:
			continue
		var a := x + 0.58
		var b := x + bay_width - 0.58
		if gate and (i == BAYS / 2 - 1 or i == BAYS / 2):
			_gate(a, b, side, i == BAYS / 2)
		else:
			_bay(a, b, i % 3 == 1)
		_walkway(x, x + bay_width)
	_stands(side)

func _post(x: float) -> void:
	var tint := _tint(0.08)
	_box("timber", Vector3(x, (DECK + 1.8) * 0.5, W - 0.58), Vector3(1.15, DECK + 1.8, 1.15), Vector3.ZERO, tint)
	for y: float in [BUMPER + 0.1, 8.0, 13.4]:
		_box("iron", Vector3(x, y, W - 0.58), Vector3(1.23, 0.26, 1.23))
		for dx: float in [-0.32, 0.32]:
			_bolt(Vector3(x + dx, y, W + 0.02), 0.075)
	_box("rusty", Vector3(x, DECK + 2.2, W - 0.58), Vector3(1.3, 0.8, 1.3), Vector3(0, PI / 4.0, 0), Color.WHITE, "pyr")
	# Iron lantern bracket; the glass glows warmly.
	_box("iron", Vector3(x, 11.2, W + 0.15), Vector3(0.1, 0.1, 0.75))
	_box("iron", Vector3(x, 10.6, W + 0.5), Vector3(0.44, 0.7, 0.44))
	_box("lantern", Vector3(x, 10.6, W + 0.5), Vector3(0.32, 0.52, 0.46))

func _buttress(x: float, side: int, index: int) -> void:
	# Concrete pier banded with riveted steel, crowned by a fire brazier.
	var top := DECK + 4.2
	var z := W - 1.35
	_box("concrete", Vector3(x, top * 0.5 - 0.5, z), Vector3(3.2, top + 1.0, 2.7), Vector3.ZERO, _tint(0.05))
	_box("concrete", Vector3(x, 1.2, z + 0.1), Vector3(3.8, 2.4, 2.9), Vector3.ZERO, _tint(0.05))
	for y: float in [2.6, 7.6, 12.2, top - 0.4]:
		_box("iron", Vector3(x, y, z), Vector3(3.3, 0.5, 2.8))
		for dx: float in [-1.3, -0.65, 0.0, 0.65, 1.3]:
			for dy: float in [-0.14, 0.14]:
				_bolt(Vector3(x + dx, y + dy, W + 0.02), 0.05)
	for dx: float in [-1.52, 1.52]:
		_box("rusty", Vector3(x + dx, top * 0.5, W + 0.0), Vector3(0.22, top, 0.22))
	_box("iron", Vector3(x, top + 0.3, z), Vector3(3.5, 0.3, 3.0))
	_box("iron", Vector3(x, top + 0.9, z), Vector3(0.5, 0.9, 0.5))
	_add("rusty", "bowl", Transform3D(Basis.IDENTITY.scaled(Vector3(2.4, 1.0, 2.4)), Vector3(x, top + 1.8, z)))
	for n: int in range(3):
		var yaw := n * PI / 3.0
		_add("flame", "flame", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.7, 3.0, 1.0)), Vector3(x, top + 2.1, z)))
	if (side + index) % 2 == 0:
		var fire := OmniLight3D.new()
		fire.set_script(preload("res://scripts/arena/woodland_fire_light.gd"))
		fire.position = _side * Vector3(x, top + 3.2, z + 1.0)
		fire.light_color = Color(1.0, 0.55, 0.2)
		fire.light_energy = 3.0
		fire.omni_range = 18.0
		fire.shadow_enabled = false
		fire.light_volumetric_fog_energy = 0.4
		add_child(fire)

func _corner_post(x: float) -> void:
	_log("log", Vector3(x, -1.0, W - 0.95), Vector3(x, DECK + 3.0, W - 0.95), 0.92, _tint(0.06))
	for y: float in [2.0, 8.0, 13.4, DECK + 2.2]:
		_log("iron", Vector3(x, y - 0.13, W - 0.95), Vector3(x, y + 0.13, W - 0.95), 0.96)

func _bay(a: float, b: float, bannered: bool) -> void:
	var width := b - a
	var centre := (a + b) * 0.5
	# Impact zone: three stacked hewn beams bolted through forged straps.
	for row: int in range(3):
		var y := 0.525 + row * 1.05
		_box("timber", Vector3(centre, y, W - 0.42 - _rng.randf_range(0.0, 0.03)), Vector3(width + 0.1, 1.02, 0.8),
			Vector3(0, 0, _rng.randf_range(-0.003, 0.003)), _tint(0.1))
	for dx: float in [-width * 0.32, 0.0, width * 0.32]:
		_box("iron", Vector3(centre + dx, BUMPER * 0.5, W - 0.012), Vector3(0.32, BUMPER - 0.1, 0.045))
		for y: float in [0.52, 1.57, 2.62]:
			_bolt(Vector3(centre + dx, y, W + 0.01), 0.07)
	_box("rail", Vector3(centre, BUMPER + 0.07, W - 0.8), Vector3(width + 0.1, 0.14, 1.6), Vector3.ZERO, _tint(0.05))
	# Dark backing so plank gaps read as shadow, not open sky.
	_box("timber", Vector3(centre, (BUMPER + DECK) * 0.5, W - 1.62), Vector3(width + 0.6, DECK - BUMPER, 0.1), Vector3.ZERO, Color(0.35, 0.33, 0.3))
	var count := int(width / 0.56)
	var pitch := width / count
	for n: int in range(count):
		var x := a + (n + 0.5) * pitch
		var top := DECK - 0.35 + _rng.randf_range(-0.25, 0.1)
		var tint := _tint(0.16)
		if _rng.randf() < 0.07:
			tint = Color(1.18, 1.02, 0.86) # A recently replaced board.
		elif _rng.randf() < 0.1:
			tint = Color(0.72, 0.7, 0.68)
		_box("plank", Vector3(x, (BUMPER + top) * 0.5, W - 1.45 + _rng.randf_range(-0.025, 0.025)),
			Vector3(pitch - 0.04, top - BUMPER, 0.15), Vector3(0, 0, _rng.randf_range(-0.005, 0.005)), tint)
		if n % 3 == 1:
			for y: float in [8.0, 13.4]:
				_bolt(Vector3(x, y, W - 0.86), 0.045)
	for y: float in [8.0, 13.4]:
		_box("rail", Vector3(centre, y, W - 1.1), Vector3(width + 0.04, 0.56, 0.46), Vector3.ZERO, _tint(0.08))
	if bannered:
		_banner(centre, _team_color(Vector3(centre, 0, W)))
	else:
		# Diagonal cross bracing, halved at the crossing like carpentry.
		var low := BUMPER + 0.35
		var high := 7.6
		_beam("rail", Vector3(a + 0.4, low, W - 1.02), Vector3(b - 0.4, high, W - 1.02), Vector2(0.44, 0.28), _tint(0.08))
		_beam("rail", Vector3(a + 0.4, high, W - 1.06), Vector3(b - 0.4, low, W - 1.06), Vector2(0.44, 0.28), _tint(0.08))
		_bolt(Vector3(centre, (low + high) * 0.5, W - 0.9), 0.09)

func _banner(x: float, color: Color) -> void:
	var top := 13.1
	var height := 9.0
	_log("iron", Vector3(x - 2.5, 13.85, W - 0.78), Vector3(x + 2.5, 13.85, W - 0.78), 0.07)
	for dx: float in [-2.1, 2.1]:
		_box("iron", Vector3(x + dx, 13.7, W - 0.8), Vector3(0.08, 0.4, 0.16))
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN).scaled_local(Vector3(4.2, 1.0, height))
	_add("banner", "banner", Transform3D(basis, Vector3(x, top - height * 0.5 + 0.5, W - 0.8)), color)

func _gate(a: float, b: float, side: int, right: bool) -> void:
	# Two bays form one tank gate: a single braced leaf in each bay.
	var centre := (a + b) * 0.5
	var leaf := b - a
	var height := 12.0
	var boards := 11
	for n: int in range(boards):
		var bx := a + (n + 0.5) * leaf / boards
		_box("timber", Vector3(bx, height * 0.5, W - 0.3), Vector3(leaf / boards - 0.03, height, 0.34), Vector3.ZERO, _tint(0.12) * Color(0.85, 0.85, 0.85))
	for y: float in [1.6, 6.0, 10.4]:
		_box("rail", Vector3(centre, y, W - 0.06), Vector3(leaf - 0.2, 0.55, 0.18), Vector3.ZERO, _tint(0.06))
		var hinge := b if right else a
		_box("iron", Vector3((centre + hinge) * 0.5, y, W + 0.05), Vector3(leaf * 0.6, 0.22, 0.05))
		for n: int in range(6):
			_bolt(Vector3(lerpf(centre, hinge, n / 5.0), y, W + 0.07), 0.055)
	_beam("rail", Vector3(a + 0.5, 2.0, W - 0.05), Vector3(b - 0.5, 5.6, W - 0.05), Vector2(0.4, 0.16), _tint(0.06))
	_beam("rail", Vector3(a + 0.5, 6.4, W - 0.05), Vector3(b - 0.5, 10.0, W - 0.05), Vector2(0.4, 0.16), _tint(0.06))
	# Lintel beam over the pair and a carved gate board.
	_box("timber", Vector3(centre, height + 0.8, W - 0.7), Vector3(leaf + 1.2, 1.6, 1.4), Vector3.ZERO, _tint(0.05))
	_box("timber", Vector3(centre, DECK - 0.4, W - 1.3), Vector3(leaf + 0.6, DECK - height - 1.2, 0.3), Vector3.ZERO, _tint(0.05))
	if right:
		var label := _text("GATE  " + ("EAST" if side == 6 else "WEST"), Vector3(a - 0.6, height + 0.82, W + 0.01), 120, 0.02, Color(0.93, 0.86, 0.7))
		label.shaded = true

func _walkway(x0: float, x1: float) -> void:
	var width := x1 - x0
	var centre := (x0 + x1) * 0.5
	_box("deck", Vector3(centre, DECK - 0.1, W - 2.8), Vector3(width, 0.2, 5.4), Vector3.ZERO, _tint(0.06))
	_box("timber", Vector3(centre, DECK - 0.5, W - 0.3), Vector3(width, 0.9, 0.5), Vector3.ZERO, _tint(0.06))
	for n: int in range(6):
		var x := x0 + (n + 0.5) * width / 6.0
		_box("rail", Vector3(x, DECK + 0.55, W - 0.45), Vector3(0.12, 1.1, 0.12), Vector3.ZERO, _tint(0.08))
	_box("rail", Vector3(centre, DECK + 1.08, W - 0.45), Vector3(width, 0.1, 0.18), Vector3.ZERO, _tint(0.05))
	_box("rail", Vector3(centre, DECK + 0.6, W - 0.45), Vector3(width, 0.08, 0.07), Vector3.ZERO, _tint(0.05))
	# Standing spectators crowd the rail above the giants.
	for row: int in range(3):
		var z := W - 0.9 - row * 0.62
		var n := 0.0
		while n < width:
			var x := x0 + n + _rng.randf_range(0.0, 0.25)
			n += _rng.randf_range(0.55, 0.85)
			if _rng.randf() < 0.2 + row * 0.2:
				continue
			_person(Vector3(x, DECK, z), _rng.randf_range(0.93, 1.07))

func _person(at: Vector3, height: float, seated: bool = false) -> void:
	# Faces the arena (+z in the face frame). Instance alpha carries a shared
	# per-person phase so every part of one spectator moves together.
	var world := _side * at
	var palette := [Color(0.1, 0.11, 0.12), Color(0.3, 0.26, 0.2), Color(0.2, 0.23, 0.18), Color(0.36, 0.34, 0.31),
		Color(0.19, 0.15, 0.12), Color(0.38, 0.14, 0.09), Color(0.13, 0.17, 0.25), Color(0.45, 0.42, 0.36)]
	var shirt: Color = palette[_rng.randi() % palette.size()]
	var fan := _rng.randf() < 0.28
	if fan:
		shirt = (CYAN if _rng.randf() < (0.7 if world.z > 0 else 0.3) else ORANGE) * 0.9
	var trousers: Color = [Color(0.08, 0.09, 0.11), Color(0.16, 0.14, 0.12), Color(0.11, 0.14, 0.2)][_rng.randi() % 3]
	var skin: Color = [Color(0.62, 0.45, 0.34), Color(0.45, 0.31, 0.22), Color(0.28, 0.19, 0.13), Color(0.7, 0.54, 0.43)][_rng.randi() % 4]
	var phase := _rng.randf()
	shirt.a = phase
	trousers.a = phase
	skin.a = phase
	var s := height
	var hip := at.y + (0.46 if seated else 0.86 * s)
	if seated:
		_add("crowd", "box", Transform3D(Basis.IDENTITY.scaled(Vector3(0.36, 0.14, 0.44)), Vector3(at.x, hip + 0.02, at.z + 0.2)), trousers)
		_add("crowd", "box", Transform3D(Basis.IDENTITY.scaled(Vector3(0.32, 0.44, 0.13)), Vector3(at.x, hip - 0.24, at.z + 0.4)), trousers)
	else:
		_add("crowd", "box", Transform3D(Basis.IDENTITY.scaled(Vector3(0.34, 0.86 * s, 0.2)), Vector3(at.x, at.y + 0.43 * s, at.z)), trousers)
	var torso := 0.64 * s
	_add("crowd", "body", Transform3D(Basis.IDENTITY.scaled(Vector3(0.46, torso, 0.28)), Vector3(at.x, hip + torso * 0.5, at.z)), shirt)
	for side: float in [-1.0, 1.0]:
		var raised := fan and _rng.randf() < 0.35
		var arm := Basis(Vector3.BACK, side * (-0.25 if raised else 0.12)).scaled(Vector3(0.12, 0.58 * s, 0.12))
		var shoulder := Vector3(at.x + side * 0.26, hip + torso * 0.86, at.z)
		var reach := Vector3(side * 0.07, 0.29 * s, 0) if raised else Vector3(side * 0.03, -0.27 * s, 0)
		_add("crowd", "body", Transform3D(arm, shoulder + reach), shirt)
	_add("crowd", "head", Transform3D(Basis.IDENTITY.scaled(Vector3(0.22, 0.26, 0.23)), Vector3(at.x, hip + torso + 0.14, at.z)), skin)
	if _rng.randf() < 0.3:
		var cap := (CYAN if world.z > 0 else ORANGE) if fan else trousers
		cap.a = phase
		_add("crowd", "box", Transform3D(Basis.IDENTITY.scaled(Vector3(0.25, 0.08, 0.27)), Vector3(at.x, hip + torso + 0.26, at.z + 0.02)), cap)

func _stands(side: int) -> void:
	# Stepped timber terraces rise outward behind the walkway.
	var front := W - 5.5
	for k: int in range(TIERS):
		var depth := 0.92
		var z := front - depth * (k + 0.5)
		var top := DECK + 0.5 * (k + 1)
		var half := (-z) * 0.41421356 - 4.5
		_box("timber", Vector3(0, (DECK + top) * 0.5, z), Vector3(half * 2.0, top - DECK, depth), Vector3.ZERO, Color(0.7, 0.68, 0.65))
		_box("deck", Vector3(0, top + 0.02, z + 0.1), Vector3(half * 2.0, 0.05, 0.7), Vector3.ZERO, _tint(0.05))
		_box("plank", Vector3(0, top + 0.42, z - 0.12), Vector3(half * 2.0, 0.06, 0.34), Vector3.ZERO, _tint(0.05))
		var x := -half + 0.4
		while x < half - 0.3:
			if _rng.randf() < 0.82 and not (side == 0 and absf(x) < 27.0 and k > 6):
				_person(Vector3(x + _rng.randf_range(-0.06, 0.06), top, z - 0.1), _rng.randf_range(0.92, 1.08), true)
			x += _rng.randf_range(0.56, 0.7)
	var back := front - 0.92 * TIERS - 0.2
	var back_half := (-back) * 0.41421356 - 4.0
	var roof := DECK + 0.5 * TIERS + 3.2
	_box("timber", Vector3(0, (DECK + roof + 1.5) * 0.5, back), Vector3(back_half * 2.0, roof + 1.5 - DECK, 0.35), Vector3.ZERO, Color(0.75, 0.72, 0.68))
	for k: int in range(int(back_half * 2.0 / 6.0) + 1):
		_box("timber", Vector3(-back_half + k * 6.0, (DECK + roof) * 0.5, back - 0.3), Vector3(0.5, roof - DECK, 0.5), Vector3.ZERO, _tint(0.06))
	# Canvas tents shade the middle of each stand.
	if side == 0:
		return
	var eave := roof - 1.0
	for bay: int in range(-4, 5):
		var x0 := bay * 6.0
		for x: float in [x0 - 3.0, x0 + 3.0]:
			_box("rail", Vector3(x, (DECK + eave) * 0.5, front + 0.2), Vector3(0.24, eave - DECK, 0.24), Vector3.ZERO, _tint(0.06))
			_beam("rail", Vector3(x, eave, front + 0.2), Vector3(x, roof, back), Vector2(0.2, 0.26), _tint(0.06), "box", Vector3.RIGHT)
		_box("rail", Vector3(x0, eave, front + 0.2), Vector3(6.2, 0.24, 0.22), Vector3.ZERO, _tint(0.05))
		var span := front - back + 0.8
		var pitch := atan2(1.4, 3.0)
		for half: float in [-1.0, 1.0]:
			_box("canvas", Vector3(x0 + half * 1.5, (eave + roof) * 0.5 + 0.7, (front + back) * 0.5 + 0.4), Vector3(Vector2(3.0, 1.4).length() + 0.1, 0.03, span),
				Vector3(0, 0, -half * pitch), Color(0.92, 0.88, 0.8))
		_box("rail", Vector3(x0, (eave + roof) * 0.5 + 1.4, (front + back) * 0.5), Vector3(0.16, 0.16, span), Vector3.ZERO, _tint(0.05))
		_box("canvas", Vector3(x0, eave - 0.3, front + 0.34), Vector3(6.0, 0.6, 0.02), Vector3.ZERO, _team_color(Vector3(x0, 0, front)) * 1.6)

# --- Corner floodlight towers -------------------------------------------

func _tower() -> void:
	var c := Vector3(0, 0, -TOWER_RADIUS)
	var h := TOWER_HEIGHT
	var legs := [Vector3(-2.6, 0, -2.6), Vector3(2.6, 0, -2.6), Vector3(-2.6, 0, 2.6), Vector3(2.6, 0, 2.6)]
	for leg: Vector3 in legs:
		_box("timber", c + leg + Vector3(0, h * 0.5 - 1.0, 0), Vector3(1.0, h + 2.0, 1.0), Vector3.ZERO, _tint(0.06))
		_box("rusty", c + leg + Vector3(0, 0.3, 0), Vector3(1.5, 1.2, 1.5))
	var faces := [[legs[0], legs[1]], [legs[2], legs[3]], [legs[0], legs[2]], [legs[1], legs[3]]]
	var levels := 8
	for level: int in range(levels):
		var y0 := 1.5 + level * (h - 1.5) / levels
		var y1 := y0 + (h - 1.5) / levels
		for pair: Array in faces:
			var p: Vector3 = pair[0]
			var q: Vector3 = pair[1]
			var hint := Vector3.BACK if absf(p.z - q.z) < 0.1 else Vector3.RIGHT
			var mid := (p + q) * 0.5
			var push := Vector3(signf(mid.x) * 0.12 if absf(mid.x) > 1.0 else 0.0, 0, signf(mid.z) * 0.12 if absf(mid.z) > 1.0 else 0.0)
			_beam("rail", c + p + push + Vector3(0, y0, 0), c + q + push + Vector3(0, y1, 0), Vector2(0.36, 0.26), _tint(0.08), "box", hint)
			_beam("rail", c + q + push * 2.0 + Vector3(0, y0, 0), c + p + push * 2.0 + Vector3(0, y1, 0), Vector2(0.36, 0.26), _tint(0.08), "box", hint)
			_beam("rail", c + p + push + Vector3(0, y1, 0), c + q + push + Vector3(0, y1, 0), Vector2(0.45, 0.45), _tint(0.08), "box", hint)
	_box("deck", c + Vector3(0, h, 0), Vector3(7.0, 0.3, 7.0), Vector3.ZERO, _tint(0.05))
	for s: float in [-1.0, 1.0]:
		_box("rail", c + Vector3(s * 3.4, h + 1.1, 0), Vector3(0.12, 0.12, 6.8))
		_box("rail", c + Vector3(0, h + 1.1, s * 3.4), Vector3(6.8, 0.12, 0.12))
	var head := c + Vector3(0, h + 3.2, 2.6)
	var aim := Basis(Vector3.RIGHT, deg_to_rad(22.0))
	_add("iron", "box", Transform3D(aim.scaled_local(Vector3(7.2, 4.6, 0.5)), head - aim.z * 0.3))
	for row: int in range(2):
		for col: int in range(3):
			var lamp := head + aim * Vector3(-2.3 + col * 2.3, -1.1 + row * 2.2, 0.0)
			_add("iron", "cyl", Transform3D(aim * Basis(Vector3.RIGHT, PI / 2.0).scaled_local(Vector3(1.9, 0.8, 1.9)), lamp + aim.z * 0.3))
			_add("lamp", "cyl", Transform3D(aim * Basis(Vector3.RIGHT, PI / 2.0).scaled_local(Vector3(1.6, 0.05, 1.6)), lamp + aim.z * 0.72))
	_box("rusty", c + Vector3(0, h + 7.0, 0.8), Vector3(8.6, 2.8, 8.6), Vector3(0, PI / 4.0, 0), Color.WHITE, "pyr")
	var light := SpotLight3D.new()
	add_child(light)
	light.position = _side * (head + aim.z * 1.2)
	light.look_at(_side * Vector3(0, 0, -40.0), Vector3.UP)
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 6.0
	light.light_size = 2.0
	light.spot_range = 180.0
	light.spot_angle = 30.0
	light.spot_attenuation = 0.8
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.3
	# Long team pennant down the tower's inner face.
	var colour := _team_color(c)
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN).scaled_local(Vector3(3.4, 1.0, 16.0))
	_add("banner", "banner", Transform3D(basis, c + Vector3(0, 28.0, 3.2)), colour)
	_log("iron", c + Vector3(-2.0, 36.2, 3.15), c + Vector3(2.0, 36.2, 3.15), 0.08)

# --- Scoreboard ----------------------------------------------------------

func _scoreboard() -> void:
	# A timber-framed video board rising behind the north stand.
	var z := W - 20.0
	var h := 56.0
	for x: float in [-25.0, 25.0]:
		for dz: float in [-2.0, 2.0]:
			_box("timber", Vector3(x, h * 0.5, z + dz), Vector3(1.3, h, 1.3), Vector3.ZERO, _tint(0.05))
		for level: int in range(10):
			var y := 1.0 + level * 5.2
			_beam("rail", Vector3(x, y, z - 2.0), Vector3(x, y + 5.2, z + 2.0), Vector2(0.4, 0.3), _tint(0.06), "box", Vector3.RIGHT)
			_box("rail", Vector3(x, y + 5.2, z), Vector3(0.5, 0.5, 4.6), Vector3.ZERO, _tint(0.06))
	_box("timber", Vector3(0, h - 1.0, z), Vector3(52.0, 1.6, 5.0), Vector3.ZERO, _tint(0.05))
	_box("timber", Vector3(0, 27.2, z), Vector3(52.0, 1.6, 5.0), Vector3.ZERO, _tint(0.05))
	_box("iron", Vector3(0, 41.0, z - 0.8), Vector3(48.0, 26.0, 1.0))
	_box("rusty", Vector3(0, h + 1.2, z), Vector3(56.0, 3.2, 8.0))
	for x: float in [-18.0, -6.0, 6.0, 18.0]:
		_box("iron", Vector3(x, h + 0.3, z + 2.8), Vector3(2.4, 1.4, 1.2))
		_box("lamp", Vector3(x, h - 0.3, z + 3.2), Vector3(2.0, 0.16, 0.8))
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(46.0, 24.0)
	screen.mesh = quad
	screen.material_override = _materials.screen
	screen.position = Vector3(0, 41.0, z - 0.25)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(screen)
	_text("CYAN", Vector3(-11.5, 37.0, z - 0.2), 150, 0.026, Color(0.75, 0.95, 1.0), 12)
	_text("ORANGE", Vector3(11.5, 37.0, z - 0.2), 150, 0.026, Color(1.0, 0.86, 0.7), 12)
	_text("VS", Vector3(0, 42.0, z - 0.2), 130, 0.026, Color(1, 1, 1), 10)
	_text("WOODLAND  ARENA", Vector3(0, 49.5, z - 0.2), 80, 0.026, Color(0.95, 0.9, 0.78), 8)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 40.0, z + 6.0)
	glow.light_color = Color(0.7, 0.75, 0.9)
	glow.light_energy = 2.0
	glow.omni_range = 30.0
	glow.light_volumetric_fog_energy = 0.0
	add_child(glow)
	for x: float in [-25.0, 25.0]:
		var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN).scaled_local(Vector3(3.6, 1.0, 18.0))
		_add("banner", "banner", Transform3D(basis, Vector3(x, 38.0, z + 2.8)), CYAN if x < 0 else ORANGE)

# --- Bridges and barricades ---------------------------------------------

func _jump_ramp() -> void:
	# Local frame: rises along +Z to the lip, matching GROUND.ramp_points().
	var w := GROUND.RAMP_WIDTH * 0.5
	var l := GROUND.RAMP_LENGTH * 0.5
	var h := GROUND.RAMP_HEIGHT
	var run := GROUND.RAMP_LENGTH - 1.0
	var slope := atan2(h + 0.6, run)
	var deck := Vector2(run, h + 0.6).length()
	var mid := Vector3(0, (h - 0.6) * 0.5, (-l - 0.6 + l - 1.6) * 0.5)
	var basis := Basis(Vector3.RIGHT, -slope)
	# Steel deck plates with anti-slip ribs, over concrete cheeks.
	for n: int in range(4):
		var along := -deck * 0.5 + (n + 0.5) * deck / 4.0
		_add("steel", "box", Transform3D(basis.scaled_local(Vector3(w * 2.0 - 0.2, 0.12, deck / 4.0 - 0.05)), mid + basis * Vector3(0, 0.02, along)))
	for n: int in range(18):
		var along := -deck * 0.5 + (n + 0.5) * deck / 18.0
		_add("iron", "box", Transform3D(basis.scaled_local(Vector3(w * 2.0 - 0.5, 0.06, 0.1)), mid + basis * Vector3(0, 0.1, along)))
	for x: float in [-w + 0.25, w - 0.25]:
		_add("concrete", "box", Transform3D(basis.scaled_local(Vector3(0.5, 0.9, deck)), mid + basis * Vector3(x - mid.x, -0.4, 0)))
		for n: int in range(7):
			_bolt(mid + basis * Vector3(x * 0.92, 0.1, -deck * 0.45 + n * deck * 0.15), 0.06, basis.y)
	# The lip: a concrete pier with a yellow-black hazard edge.
	_box("concrete", Vector3(0, (h - 0.8) * 0.5, l - 0.8), Vector3(w * 2.0, h + 0.8, 1.6), Vector3.ZERO, _tint(0.05))
	_box("iron", Vector3(0, h + 0.03, l - 0.8), Vector3(w * 2.0 + 0.1, 0.1, 1.7))
	for n: int in range(8):
		_add("hazard", "box", Transform3D(Basis(Vector3.FORWARD, 0.6).scaled_local(Vector3(0.45, 1.6, 0.04)), Vector3(-w + 0.5 + n * (w * 2.0 - 1.0) / 7.0, h - 0.8, l + 0.02)),
			Color(0.85, 0.62, 0.08) if n % 2 == 0 else Color(0.05, 0.05, 0.05))
	# Concrete wing walls under the deck.
	for x: float in [-w - 0.2, w + 0.2]:
		for n: int in range(3):
			var z := -l + 2.5 + n * 4.2
			var height := (z + l + 0.6) / run * (h + 0.6) - 0.6
			_box("concrete", Vector3(x, height * 0.5 - 0.3, z), Vector3(0.6, height + 0.6, 1.2), Vector3.ZERO, _tint(0.05))

func _bunker(size: Vector3) -> void:
	# Chamfered concrete block wrapped in riveted steel, with a firing slit.
	_box("concrete", Vector3(0, size.y * 0.5 - 0.5, 0), size + Vector3(0, 1.0, 0), Vector3.ZERO, _tint(0.05))
	_box("concrete", Vector3(0, size.y + 0.25, 0), Vector3(size.x - 0.8, 0.5, size.z - 0.8), Vector3.ZERO, _tint(0.05))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box("iron", Vector3(sx * size.x * 0.5, size.y * 0.5, sz * size.z * 0.5), Vector3(0.5, size.y + 0.1, 0.5))
	for face: float in [-1.0, 1.0]:
		var z := face * (size.z * 0.5 + 0.03)
		_box("dark_slit", Vector3(0, size.y * 0.72, z), Vector3(size.x * 0.55, 0.45, 0.1))
		for y: float in [0.6, size.y - 0.5]:
			_box("iron", Vector3(0, y, z), Vector3(size.x - 0.6, 0.35, 0.06))
			var count := int(size.x / 0.8)
			for n: int in range(count):
				_bolt(Vector3(-size.x * 0.5 + 0.4 + n * (size.x - 0.8) / maxf(count - 1, 1), y, z + face * 0.03), 0.05, Vector3(0, 0, face))
		for n: int in range(3):
			_box("rusty", Vector3(-size.x * 0.3 + n * size.x * 0.3, size.y * 0.35, z + face * 0.02), Vector3(1.2, 1.2, 0.05))
	_box("rusty", Vector3(size.x * 0.2, size.y + 0.55, 0), Vector3(1.4, 0.15, 1.4))

func _plinth(radius: float, height: float) -> void:
	# Concrete drum on a rock base, with steel bands and a turret ring deck.
	_add("concrete", "drum", Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 2.0, height + 1.0, radius * 2.0)), Vector3(0, height * 0.5 - 0.5, 0)), _tint(0.05))
	for y: float in [0.8, height - 0.3]:
		_add("iron", "drum", Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 2.0 + 0.12, 0.35, radius * 2.0 + 0.12)), Vector3(0, y, 0)))
	_add("iron", "drum", Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 1.5, 0.3, radius * 1.5)), Vector3(0, height + 0.15, 0)))
	_add("rusty", "drum", Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 1.1, 0.6, radius * 1.1)), Vector3(0, height + 0.5, 0)))
	for n: int in range(16):
		var a := n * TAU / 16.0
		_bolt(Vector3(cos(a) * (radius + 0.07), height - 0.3, sin(a) * (radius + 0.07)), 0.07, Vector3(cos(a), 0, sin(a)))

func _barricade(length: float) -> void:
	var r := GROUND.LOG_RADIUS
	for at: Vector3 in [Vector3(0, r - 0.2, -r), Vector3(0, r - 0.2, r), Vector3(0, r * 2.55 - 0.2, 0)]:
		var jitter := _rng.randf_range(-0.4, 0.4)
		_log("log", at + Vector3(-length * 0.5 + jitter, 0, 0), at + Vector3(length * 0.5 + jitter, 0, 0), r, _tint(0.1))
	for x: float in [-length * 0.36, length * 0.36]:
		for s: float in [-1.0, 1.0]:
			_beam("log", Vector3(x, -0.4, s * (r * 2.3)), Vector3(x, 3.4, s * (r * 1.4)), Vector2(0.4, 0.4), _tint(0.08), "cyl")
		_box("iron", Vector3(x, r * 1.6, 0), Vector3(0.25, r * 3.3, r * 2.6))

# --- Outcrops ------------------------------------------------------------

func _outcrops() -> void:
	var rock := _materials.rock as Material
	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.9
	detail.fractal_octaves = 4
	var sphere := _icosphere(4)
	for item: Dictionary in GROUND.obstacles():
		if item.kind != "boulder":
			continue
		detail.seed = item.seed
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var verts := PackedVector3Array()
		for direction: Vector3 in sphere.vertices:
			var p: Vector3 = GROUND.boulder_vertex(direction, item.radii, item.yaw, item.seed)
			var n := detail.get_noise_3dv(p * 1.0)
			var crack := absf(detail.get_noise_3dv(p * 2.3 + Vector3(9, 3, 1)))
			# Fine relief only pushes inward, so the collision hull stays an envelope.
			p -= direction.normalized() * (0.04 + n * 0.018 + (0.12 - minf(crack, 0.12)) * 0.12)
			verts.append(p)
		for index: int in sphere.indices:
			tool.add_vertex(verts[index])
		tool.index()
		tool.generate_normals()
		var visual := MeshInstance3D.new()
		visual.name = String(item.name)
		visual.mesh = tool.commit()
		visual.material_override = rock
		visual.position = item.at
		add_child(visual)

func _icosphere(subdivisions: int) -> Dictionary:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vertices: Array[Vector3] = []
	for v: Vector3 in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		vertices.append(v.normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for level: int in range(subdivisions):
		var cache := {}
		var next: Array = []
		for f: Array in faces:
			var m := []
			for e: int in range(3):
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					vertices.append(((vertices[a] + vertices[b]) * 0.5).normalized())
					cache[key] = vertices.size() - 1
				m.append(cache[key])
			next.append_array([[f[0], m[0], m[2]], [f[1], m[1], m[0]], [f[2], m[2], m[1]], [m[0], m[1], m[2]]])
		faces = next
	var indices := PackedInt32Array()
	for f: Array in faces:
		# Godot's front faces wind clockwise.
		indices.append_array([f[0], f[2], f[1]])
	return {"vertices":vertices, "indices":indices}

# --- Lighting ------------------------------------------------------------

func _lighting(arena: Node) -> void:
	var world := arena.get_node("WorldEnvironment") as WorldEnvironment
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssr_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.74, 0.76)
	env.fog_light_energy = 0.9
	env.fog_sun_scatter = 0.3
	env.fog_density = 0.00028
	env.fog_height = 2.0
	env.fog_height_density = 0.01
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.15
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color(0.86, 0.8, 0.7)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0
	world.environment = env
	var sun := arena.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-36, 205, 0)
	sun.light_color = Color(1.0, 0.87, 0.7)
	sun.light_energy = 1.65
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 190.0
	sun.light_volumetric_fog_energy = 1.2
