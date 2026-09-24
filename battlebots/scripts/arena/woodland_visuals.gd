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
## Views span the 240 m bowl and the valley; see #34 for the camera handoff.
const VIEW_DISTANCE := 12000.0
const SKY_ENERGY := 1.6
const WOOD = preload("res://assets/materials/arena/woodland_wood.gdshader")
const IRON = preload("res://assets/materials/arena/woodland_iron.gdshader")
const CANVAS = preload("res://assets/materials/arena/woodland_canvas.gdshader")
const BANNER = preload("res://assets/materials/arena/woodland_banner.gdshader")
const CROWD = preload("res://assets/materials/arena/woodland_crowd.gdshader")
const TERRAIN = preload("res://assets/materials/arena/woodland_terrain.gdshader")
const MASKS = preload("res://assets/textures/woodland/ground_masks.png")
const ROCK = preload("res://assets/materials/arena/woodland_rock.gdshader")
const SCREEN = preload("res://assets/materials/arena/woodland_screen.gdshader")
const TIMBER = preload("res://assets/materials/arena/woodland_timber.gdshader")
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
## Destructible props (#71): obstacle name -> [[batch key or MultiMeshInstance3D, index]].
## _owner names the obstacle whose pieces _add is recording.
var _owned: Dictionary = {}
var _owner := ""
var _batch_nodes: Dictionary = {}
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
				_owner = item.name
				_owned[_owner] = []
				_barricade(item.length)
				_owner = ""
			"ramp":
				# The Blender model rises toward -Z; the collision wedge toward +Z.
				_structure("jump_ramp", Transform3D(Basis(Vector3.UP, float(item.yaw) + PI), item.at))
			"bunker":
				var size: Vector3 = item.size
				var model := "bunker_large" if size.x > 13.0 else ("bunker_medium" if size.x > 10.0 else "bunker_small")
				_structure(model, Transform3D(Basis(Vector3.UP, item.yaw), item.at))
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
	# A 0.25 m grid displaced on the GPU from the physical heights (uploaded as a
	# float texture) and the baked rut mask; see woodland_terrain.gdshader.
	var ground := arena.get_node("WoodlandTerrain") as Node3D
	var heights: PackedFloat32Array = ground.get_meta(&"heights")
	var height_image := Image.create_from_data(GROUND.GRID, GROUND.GRID, false, Image.FORMAT_RF, heights.to_byte_array())
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2.0, HALF * 2.0)
	plane.subdivide_width = int(HALF * 8.0) - 1
	plane.subdivide_depth = int(HALF * 8.0) - 1
	# Displacement happens in the shader; keep culling bounds generous.
	plane.custom_aabb = AABB(Vector3(-HALF, -4.0, -HALF), Vector3(HALF * 2.0, 20.0, HALF * 2.0))
	var terrain := ShaderMaterial.new()
	terrain.shader = TERRAIN
	terrain.set_shader_parameter("height_tex", ImageTexture.create_from_image(height_image))
	terrain.set_shader_parameter("masks", MASKS)
	terrain.set_shader_parameter("lump_tex", FLORA.lump_texture())
	terrain.set_shader_parameter("arena_half", HALF)
	terrain.set_shader_parameter("grid", float(GROUND.GRID))
	for layer: Array in [["mud", "muddy_tracks"], ["rocky", "brown_mud_rocks_01"], ["ground", "forest_ground_04"],
			["grass", "sparse_grass"], ["rock", "rock_boulder_dry"]]:
		for map: String in ["diff", "nor", "arm"]:
			terrain.set_shader_parameter(layer[0] + "_" + map, scan(layer[1], map))
	# 30 m chunks with three detail levels by camera distance (0.25 m near,
	# 0.75 m mid, 2 m far). The shader displaces from world position, so levels
	# line up; a short skirt hides T-junction cracks. Shadows come from one
	# coarse shadow-only copy instead of the full-detail surface in every cascade.
	var root := Node3D.new()
	root.name = "TerrainSurface"
	add_child(root)
	const CHUNK := 30.0
	var levels := [[0.25, 0.0, 40.0], [0.75, 40.0, 150.0], [2.0, 150.0, 0.0]]
	var meshes: Array[Mesh] = []
	for level: Array in levels:
		var chunk := PlaneMesh.new()
		chunk.size = Vector2(CHUNK, CHUNK)
		chunk.subdivide_width = int(CHUNK / float(level[0])) - 1
		chunk.subdivide_depth = int(CHUNK / float(level[0])) - 1
		chunk.custom_aabb = AABB(Vector3(-CHUNK * 0.5, -4.0, -CHUNK * 0.5), Vector3(CHUNK, 20.0, CHUNK))
		chunk.material = terrain
		meshes.append(chunk)
	var count := int(HALF * 2.0 / CHUNK)
	for cz: int in range(count):
		for cx: int in range(count):
			var centre := Vector3(-HALF + (cx + 0.5) * CHUNK, 0.0, -HALF + (cz + 0.5) * CHUNK)
			if GROUND.octagon_distance(Vector2(centre.x, centre.z)) < -CHUNK * 0.75:
				continue
			for index: int in levels.size():
				var level: Array = levels[index]
				var part := MeshInstance3D.new()
				part.name = "Chunk%d_%d_L%d" % [cx, cz, index]
				part.mesh = meshes[index]
				part.position = centre
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				part.visibility_range_begin = level[1]
				part.visibility_range_end = level[2]
				part.visibility_range_begin_margin = 4.0
				part.visibility_range_end_margin = 4.0
				root.add_child(part)
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(HALF * 2.0, HALF * 2.0)
	shadow_plane.subdivide_width = int(HALF) - 1
	shadow_plane.subdivide_depth = int(HALF) - 1
	shadow_plane.custom_aabb = AABB(Vector3(-HALF, -4.0, -HALF), Vector3(HALF * 2.0, 20.0, HALF * 2.0))
	shadow_plane.material = terrain
	var shadow := MeshInstance3D.new()
	shadow.name = "ShadowProxy"
	shadow.mesh = shadow_plane
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	root.add_child(shadow)

# --- Materials -----------------------------------------------------------

const SCAN_RESOLUTION := {"muddy_tracks":"2k", "brown_mud_rocks_01":"2k", "forest_ground_04":"2k", "rock_face":"2k",
	"rock_boulder_dry":"2k", "weathered_planks":"1k", "medieval_wood":"1k", "pine_bark":"1k", "concrete_wall_008":"1k",
	"rusty_metal_02":"1k", "metal_plate":"1k", "sparse_grass":"1k"}

## A CC0 photoscanned map; see assets/textures/woodland/CREDITS.md.
static func scan(id: String, map: String) -> Texture2D:
	return load("res://assets/textures/woodland/%s_%s_%s.jpg" % [id, map, SCAN_RESOLUTION[id]])

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
	var hazard_paint := StandardMaterial3D.new()
	hazard_paint.albedo_color = Color(0.78, 0.55, 0.07)
	hazard_paint.roughness = 0.75
	_materials.hazard_paint = hazard_paint
	var slit := StandardMaterial3D.new()
	slit.albedo_color = Color(0.015, 0.014, 0.013)
	slit.roughness = 1.0
	_materials.dark_slit = slit
	for key: String in ["plank", "timber", "rail", "deck", "log"]:
		var wood := _materials[key] as ShaderMaterial
		wood.set_shader_parameter("grain_diff", scan("medieval_wood", "diff"))
		wood.set_shader_parameter("grain_nor", scan("medieval_wood", "nor"))
	for key: String in ["iron", "rusty", "steel"]:
		var metal := _materials[key] as ShaderMaterial
		metal.set_shader_parameter("plate_diff", scan("metal_plate", "diff"))
		metal.set_shader_parameter("plate_nor", scan("metal_plate", "nor"))
		metal.set_shader_parameter("plate_arm", scan("metal_plate", "arm"))
		metal.set_shader_parameter("rust_diff", scan("rusty_metal_02", "diff"))
	var concrete := _materials.concrete as ShaderMaterial
	for map: String in ["diff", "nor", "arm"]:
		concrete.set_shader_parameter("scan_" + map, scan("concrete_wall_008", map))
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
	if not _owner.is_empty():
		_owned[_owner].append([key, _batches[key].poses.size() - 1])

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

var _modules: Dictionary = {}

func _module(name: String, pose: Transform3D, prefix: String = "palisade_") -> void:
	var key := prefix + name
	if not _modules.has(key):
		_modules[key] = []
	_modules[key].append(_side * pose)

## Instance the Blender palisade modules with the scanned timber materials.
func _flush_modules() -> void:
	var grain := {"grain_diff":scan("weathered_planks", "diff"), "grain_nor":scan("weathered_planks", "nor"), "grain_arm":scan("weathered_planks", "arm")}
	var slots := {}
	for slot: Array in [["timber", Color(0.78, 0.74, 0.7), 0.35], ["plank", Color(1.0, 0.95, 0.88), 0.6]]:
		var m := ShaderMaterial.new()
		m.shader = TIMBER
		for k: String in grain:
			m.set_shader_parameter(k, grain[k])
		m.set_shader_parameter("tone", slot[1])
		m.set_shader_parameter("weathering", slot[2])
		slots[slot[0]] = m
	slots["iron"] = _materials.iron
	slots["canvas"] = _materials.canvas
	slots["lamp"] = _materials.lamp
	var valance := StandardMaterial3D.new()
	valance.vertex_color_use_as_albedo = true
	valance.albedo_color = Color(0.9, 0.6, 0.35)
	valance.roughness = 0.9
	slots["shirt"] = valance
	for name: String in _modules:
		var scene: Node = load("res://assets/models/woodland/%s.gltf" % name).instantiate()
		var mesh := (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.duplicate() as Mesh
		scene.free()
		for surface: int in range(mesh.get_surface_count()):
			var source := mesh.surface_get_material(surface)
			if source and slots.has(source.resource_name):
				mesh.surface_set_material(surface, slots[source.resource_name])
		# One instance per module, not an arena-wide MultiMesh: each piece is
		# frustum-culled on its own and uses the importer's automatic LODs.
		var poses: Array = _modules[name]
		var group := Node3D.new()
		group.name = "Palisade_" + name
		add_child(group)
		for i: int in range(poses.size()):
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.transform = poses[i]
			group.add_child(visual)
	_modules.clear()

func _flush() -> void:
	_flush_modules()
	_flush_fans()
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
		# Only structural pieces cast; hardware (bolts, lamp rims, cylinders,
		# bowls) is too small to read in shadow but costs every cascade.
		var casts := parts[0] in ["plank", "timber", "rail", "deck", "log", "canvas", "concrete", "steel"] and parts[1] in ["box", "pyr"]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
		_batch_nodes[key] = visual
	_batches.clear()
	for name: String in _owned:
		for piece: Array in _owned[name]:
			if piece[0] is String: piece[0] = _batch_nodes.get(piece[0])

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

var _face_index := 0

func _face(side: int) -> void:
	_face_index = side
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
	_module("post", Transform3D(Basis(Vector3.UP, (_rng.randi() % 4) * PI * 0.5), Vector3(x, 0.0, W - 0.58)) * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.58)))
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
	_module("corner_post", Transform3D(Basis.IDENTITY, Vector3(x, 0.0, W)))

func _bay(a: float, b: float, bannered: bool) -> void:
	# Blender-built bay module (art_source/woodland/build_palisade.py).
	var centre := (a + b) * 0.5
	_module("bay_bannered" if bannered else "bay_braced", Transform3D(Basis.IDENTITY, Vector3(centre, 0.0, W)))
	if bannered:
		_banner(centre, _team_color(Vector3(centre, 0, W)))

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
	# The walkway itself is part of the Blender stands module.
	var width := x1 - x0
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

var _fans: Dictionary = {"fan_seated":[], "fan_standing":[]}

## A spectator figure (build_stands.py) facing the arena, coloured per instance.
func _person(at: Vector3, height: float, seated: bool = false) -> void:
	var world := _side * at
	var palette := [Color(0.1, 0.11, 0.12), Color(0.3, 0.26, 0.2), Color(0.2, 0.23, 0.18), Color(0.36, 0.34, 0.31),
		Color(0.19, 0.15, 0.12), Color(0.38, 0.14, 0.09), Color(0.13, 0.17, 0.25), Color(0.45, 0.42, 0.36), Color(0.55, 0.52, 0.46)]
	var shirt: Color = palette[_rng.randi() % palette.size()]
	if _rng.randf() < 0.3:
		shirt = (CYAN if _rng.randf() < (0.75 if world.z > 0 else 0.25) else ORANGE) * 0.95
	shirt.a = _rng.randf()
	var trousers: Color = [Color(0.08, 0.09, 0.11), Color(0.16, 0.14, 0.12), Color(0.11, 0.14, 0.2), Color(0.25, 0.23, 0.2)][_rng.randi() % 4]
	trousers.a = (_rng.randi() % 4) / 4.0 + 0.1
	var s := height * _rng.randf_range(0.95, 1.05)
	var pose := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.25, 0.25)).scaled(Vector3(s * _rng.randf_range(0.9, 1.12), s, s)), at + Vector3(0, -0.02 if seated else 0.0, 0))
	# Bucket by face and a third of its length so each batch can be culled
	# and switch to the low-detail figure by distance.
	var third := clampi(int((at.x + FACE) / (FACE * 2.0 / 3.0)), 0, 2)
	_fans["fan_seated" if seated else "fan_standing"].append([_side * pose, shirt, trousers, _face_index * 3 + third])

func _crowd_mesh(name: String, parts: Dictionary) -> Mesh:
	var scene: Node = load("res://assets/models/woodland/stadium_%s.gltf" % name).instantiate()
	var mesh := (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.duplicate() as Mesh
	scene.free()
	for surface: int in range(mesh.get_surface_count()):
		var mat := ShaderMaterial.new()
		mat.shader = CROWD
		var source := mesh.surface_get_material(surface)
		mat.set_shader_parameter("part", parts.get(source.resource_name if source else "shirt", 0))
		mesh.surface_set_material(surface, mat)
	return mesh

## Spectators in batches of a third of a face: full figures within 75 m of the
## camera, 50-triangle blocks beyond.
func _flush_fans() -> void:
	var parts := {"shirt":0, "trousers":1, "skin":2, "hair":3}
	const NEAR := 75.0
	for name: String in _fans:
		var list: Array = _fans[name]
		if list.is_empty():
			continue
		var meshes := [_crowd_mesh(name, parts), _crowd_mesh(name + "_low", parts)]
		var buckets: Dictionary = {}
		for entry: Array in list:
			if not buckets.has(entry[3]):
				buckets[entry[3]] = []
			buckets[entry[3]].append(entry)
		for key: int in buckets:
			var group: Array = buckets[key]
			var centre := Vector3.ZERO
			for entry: Array in group:
				centre += (entry[0] as Transform3D).origin
			centre /= group.size()
			for level: int in 2:
				var multi := MultiMesh.new()
				multi.transform_format = MultiMesh.TRANSFORM_3D
				multi.use_colors = true
				multi.use_custom_data = true
				multi.mesh = meshes[level]
				multi.instance_count = group.size()
				for i: int in range(group.size()):
					var pose: Transform3D = group[i][0]
					multi.set_instance_transform(i, Transform3D(pose.basis, pose.origin - centre))
					multi.set_instance_color(i, group[i][1])
					multi.set_instance_custom_data(i, group[i][2])
				var visual := MultiMeshInstance3D.new()
				visual.name = "Crowd_%s_%d_L%d" % [name, key, level]
				visual.multimesh = multi
				visual.position = centre
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if level == 0:
					visual.visibility_range_end = NEAR
				else:
					visual.visibility_range_begin = NEAR
				visual.visibility_range_begin_margin = 5.0
				visual.visibility_range_end_margin = 5.0
				add_child(visual)
		list.clear()

func _stands(side: int) -> void:
	# Blender stands module (build_stands.py); face 0 has the scoreboard, no canopy.
	_module("stands_open" if side == 0 else "stands_canopy", Transform3D(Basis.IDENTITY, Vector3(0, 0, W)), "stadium_")
	var front := W - 5.5
	for k: int in range(TIERS):
		var z := front - 0.92 * (k + 0.5)
		var top := DECK + 0.5 * (k + 1)
		var half := (-z) * 0.41421356 - 4.5
		var x := -half + 0.4
		while x < half - 0.3:
			if _rng.randf() < 0.82 and not (side == 0 and absf(x) < 27.0 and k > 6):
				_person(Vector3(x + _rng.randf_range(-0.06, 0.06), top, z + 0.05), 1.0, true)
			x += _rng.randf_range(0.56, 0.7)

# --- Corner floodlight towers -------------------------------------------

func _tower() -> void:
	var c := Vector3(0, 0, -TOWER_RADIUS)
	var h := TOWER_HEIGHT
	_module("tower", Transform3D(Basis.IDENTITY, c), "stadium_")
	var head := c + Vector3(0, h + 3.2, 2.6)
	var aim := Basis(Vector3.RIGHT, deg_to_rad(22.0))
	var light := SpotLight3D.new()
	add_child(light)
	light.position = _side * (head + aim.z * 1.2)
	light.look_at(_side * Vector3(0, 0, -40.0), Vector3.UP)
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 6.0
	light.light_size = 2.0
	light.spot_range = 120.0
	light.spot_angle = 30.0
	light.spot_attenuation = 0.8
	light.shadow_enabled = false
	# Daylight floodlights: no fog scattering, fade out with distance.
	light.light_volumetric_fog_energy = 0.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 140.0
	light.distance_fade_length = 40.0
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
	_module("scoreboard", Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), "stadium_")
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

## Blender-built obstacle model (art_source/woodland/build_structures.py) with
## the scanned materials assigned by its slot names.
func _structure(model: String, pose: Transform3D) -> void:
	var scene: Node = load("res://assets/models/woodland/%s.gltf" % model).instantiate()
	var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var visual := MeshInstance3D.new()
	visual.name = model.capitalize().replace(" ", "")
	visual.mesh = source.mesh
	scene.free()
	var slots := {"concrete":_materials.concrete, "steel":_materials.steel, "rust":_materials.rusty,
		"slot":_materials.dark_slit, "hazard":_materials.hazard_paint}
	for surface: int in range(visual.mesh.get_surface_count()):
		var name := visual.mesh.surface_get_material(surface).resource_name if visual.mesh.surface_get_material(surface) else ""
		if slots.has(name):
			visual.set_surface_override_material(surface, slots[name])
	visual.transform = pose
	add_child(visual)

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
	# Scanned granite: every colliding boulder, plus a field of small loose rocks
	# (visual only, low enough for giant tracks to roll over) around the features.
	var groups: Dictionary = {}
	for model: String in GROUND.BOULDER_MODELS:
		groups[model] = []
	for item: Dictionary in GROUND.obstacles():
		if item.kind != "boulder":
			continue
		var pose := GROUND.boulder_pose(item)
		groups[pose.model].append(Transform3D(pose.basis, item.at - Vector3(0, pose.sink, 0)))
		_owned[item.name] = [[pose.model, groups[pose.model].size() - 1]]
	for model: String in groups:
		var poses: Array = groups[model]
		if poses.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = GROUND.scan_mesh(model)
		multi.instance_count = poses.size()
		for i: int in range(poses.size()):
			multi.set_instance_transform(i, poses[i])
		var visual := MultiMeshInstance3D.new()
		visual.name = "Granite_" + model
		visual.multimesh = multi
		add_child(visual)
		for name: String in _owned:
			for piece: Array in _owned[name]:
				if piece[0] is String and piece[0] == model: piece[0] = visual

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
	# CC0 HDRI sky (assets/textures/woodland/CREDITS.md). The key light below is
	# aimed along the photographed sun, so the visible sun, shadows and sky light agree.
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/woodland/woodland_sky_4k.hdr")
	sky_mat.energy_multiplier = SKY_ENERGY
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Lower flat fill; SSAO/SSIL supply contact darkening and warm bounce.
	env.ambient_light_energy = 0.42
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 12.0
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssao_light_affect = 0.25
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 1.2
	# Natural film grade: slightly lifted contrast, restrained saturation.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.16
	env.adjustment_saturation = 0.95
	env.ssr_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.68, 0.76)
	env.fog_light_energy = 0.9
	env.fog_sun_scatter = 0.3
	env.fog_density = 0.00016
	env.fog_height = 2.0
	env.fog_height_density = 0.01
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0007
	env.volumetric_fog_albedo = Color(0.86, 0.8, 0.7)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	world.environment = env
	var sun := arena.get_node("Sun") as DirectionalLight3D
	# Panorama u 0.5997 / elevation 37.8 deg: Godot maps u to atan(x, z) / TAU.
	var azimuth := 0.5997 * TAU
	var elevation := deg_to_rad(37.84)
	var toward_sun := Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation))
	sun.transform = Transform3D(Basis.looking_at(-toward_sun, Vector3.UP), Vector3.ZERO)
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 2.0
	# Filtered soft shadows: a non-zero angular size would switch to PCSS
	# blocker searches (~0.6 ms at 1440p) for a barely visible difference.
	sun.light_angular_distance = 0.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.8
	# Two cascades over 120 m look the same as four from the chase camera and
	# halve the shadow passes (~1.2 ms in a 12-bot brawl at 1440p).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_fade_start = 0.85
	sun.light_volumetric_fog_energy = 1.2

## The batched instances drawing a destructible prop (#71), as
## [[MultiMeshInstance3D, instance index]]; empty for anything else.
func prop_instances(name: String) -> Array:
	return _owned.get(name, []).filter(func(piece: Array) -> bool: return piece[0] is MultiMeshInstance3D)
