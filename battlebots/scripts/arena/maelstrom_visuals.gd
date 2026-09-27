extends Node3D
## Frozen Maelstrom presentation (#102). Never creates bodies, changes spawns or
## reads match state: it renders the shared data in maelstrom_ground.gd. The
## ice sheet follows the collision heights; the kit (art_source/maelstrom/
## build_kit.py) supplies crags, seracs, the wrecks of both fleets and the eye
## vortex. Beyond the rim cliffs the sea is frozen pack ice, shaded darker, walled
## in by colossal ice cliffs lost in the haze.

const GROUND = preload("res://scripts/arena/maelstrom_ground.gd")
const ICE = preload("res://assets/materials/arena/maelstrom_ice.gdshader")
const SURFACE = preload("res://assets/materials/arena/maelstrom_surface.gdshader")
const CLOTH = preload("res://assets/materials/arena/maelstrom_cloth.gdshader")
const CRYSTAL = preload("res://assets/materials/arena/maelstrom_crystal.gdshader")
const SKY = preload("res://assets/materials/arena/maelstrom_sky.gdshader")
const KIT := "res://assets/models/maelstrom/maelstrom_kit.glb"
const TEXTURES := "res://assets/textures/woodland/%s_%s_%s.jpg"
## The two fleets that met here. Slots named in FLEET_SLOTS take these colours.
const FLEETS := [
	{"name":"Ember Crown", "paint":Color(0.3, 0.035, 0.03), "trim":Color(0.42, 0.33, 0.19), "field":Color(0.24, 0.025, 0.022),
		"charge":Color(0.5, 0.38, 0.17), "border":Color(0.03, 0.02, 0.02), "emblem":0},
	{"name":"Jade Covenant", "paint":Color(0.05, 0.17, 0.13), "trim":Color(0.4, 0.42, 0.43), "field":Color(0.04, 0.13, 0.1),
		"charge":Color(0.52, 0.5, 0.44), "border":Color(0.02, 0.03, 0.03), "emblem":1},
]
const FLEET_SLOTS := ["paint", "trim", "sail", "banner", "cloth"]
const SHEET_RINGS := 110
const SHEET_SEGMENTS := 960
const SECTORS := 16
@export var arena_path: NodePath = NodePath("..")
var _kit: Dictionary = {}
var _materials: Dictionary = {}
var _snow: GPUParticles3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless":
		return
	_build.call_deferred()

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view := float(GROUND.settings().art.view_distance)
	if camera.far < view:
		camera.far = view
	if _snow:
		_snow.global_position = camera.global_position + Vector3(0, 6, 0)

func _build() -> void:
	_rng.seed = 102_2026
	var arena := get_node(arena_path)
	for wall: Node in arena.get_node("Walls").get_children():
		var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			mesh.hide()
	(arena.get_node("Markings") as Node3D).hide()
	_load_kit()
	_lighting(arena)
	_ice_sheet()
	_obstacles()
	_slabs()
	_rubble()
	_eye()
	_sea()
	_snowfall()
	set_process(true)

# --- Kit and materials -----------------------------------------------------

func _load_kit() -> void:
	var scene: Node = load(KIT).instantiate()
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		_kit[String(node.name)] = (node as MeshInstance3D).mesh
	scene.free()

static func scan(id: String, map: String, size := "1k") -> Texture2D:
	return load(TEXTURES % [id, map, size])

func _material(slot: String, fleet: int) -> Material:
	var key := slot + ("_%d" % fleet if slot in FLEET_SLOTS else "")
	if _materials.has(key):
		return _materials[key]
	var colours: Dictionary = FLEETS[clampi(fleet, 0, 1)]
	var mat := ShaderMaterial.new()
	match slot:
		"ice":
			mat.shader = CRYSTAL
		"sail", "banner":
			mat.shader = CLOTH
			mat.set_shader_parameter("sail", slot == "sail")
			mat.set_shader_parameter("emblem", colours.emblem)
			mat.set_shader_parameter("field", colours.field)
			mat.set_shader_parameter("charge", colours.charge)
			mat.set_shader_parameter("border", colours.border)
		_:
			mat.shader = SURFACE
			var kinds := {"wood":0, "deck":1, "paint":2, "trim":3, "iron":4, "rope":5, "skin":6, "cloth":7, "rock":8, "glass":9, "lantern":10}
			var base := {"wood":Color(0.12, 0.09, 0.07), "deck":Color(0.22, 0.19, 0.16), "paint":colours.paint, "trim":colours.trim,
				"iron":Color(0.13, 0.13, 0.14), "rope":Color(0.2, 0.18, 0.15), "skin":Color(0.36, 0.41, 0.46), "cloth":colours.field,
				"rock":Color(0.075, 0.08, 0.09), "glass":Color.BLACK, "lantern":Color.BLACK}
			mat.set_shader_parameter("kind", kinds.get(slot, 0))
			mat.set_shader_parameter("base_color", base.get(slot, Color.GRAY))
			var texture := "rock_face" if slot == "rock" else ("metal_plate" if slot in ["iron", "trim"] else ("weathered_planks" if slot == "deck" else "medieval_wood"))
			var size := "2k" if texture == "rock_face" else "1k"
			mat.set_shader_parameter("detail", scan(texture, "diff", size))
			mat.set_shader_parameter("detail_normal", scan(texture, "nor", size))
			mat.set_shader_parameter("detail_scale", 0.12 if slot == "rock" else 0.45)
	_set_ring(mat)
	_materials[key] = mat
	return mat

func _set_ring(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("maelstrom_rim", GROUND.settings().rim_radius)
	mat.set_shader_parameter("maelstrom_eye", GROUND.settings().eye_radius)

func _kit_instance(model: String, xform: Transform3D, fleet: int, parent: Node = self) -> MeshInstance3D:
	var mesh: Mesh = _kit[model]
	var visual := MeshInstance3D.new()
	visual.name = model.to_pascal_case()
	visual.mesh = mesh
	visual.transform = xform
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface)
		var slot := source.resource_name.trim_prefix("Maelstrom_") if source else "wood"
		visual.set_surface_override_material(surface, _material(slot, fleet))
	parent.add_child(visual)
	return visual

func _obstacles() -> void:
	var root := Node3D.new()
	root.name = "Wrecks"
	add_child(root)
	for item: Dictionary in GROUND.obstacles():
		_kit_instance(item.model, GROUND.obstacle_transform(item), maxi(int(item.faction), 0), root)

## Broken plates set into the faces of the upthrust slabs, below their driving
## surface, so the ramps read as fractured ice rather than boxes.
func _slabs() -> void:
	var cfg: RefCounted = GROUND.settings()
	var poses: Array[Transform3D] = []
	for slab: Dictionary in cfg.slabs:
		for sign: float in [1.0, -1.0]:
			var at := Vector2(float(slab.at[0]), float(slab.at[1])) * sign
			var yaw := float(slab.yaw) + (PI if sign < 0.0 else 0.0)
			var rise := Vector2(cos(yaw), sin(yaw))
			var across := Vector2(-rise.y, rise.x)
			var length := float(slab.length)
			var width := float(slab.width)
			var height := float(slab.height)
			var faces: Array = [[rise, across, width, length * 0.5, 1.0]]
			for side: float in [-1.0, 1.0]:
				faces.append([across * side, rise, length, width * 0.5, 0.0])
			for face: Array in faces:
				var normal: Vector2 = face[0]
				var along: Vector2 = face[1]
				var span: float = face[2]
				var count := int(span / 2.2)
				for n: int in count:
					var offset := (float(n) + 0.5) / count - 0.5
					var p := at + normal * (float(face[3]) - 0.45) + along * offset * span * 0.92
					# Local slab height at this point of the face.
					var u := (p - at).dot(rise)
					var top := height * (u + length * 0.5) / length - 0.25
					if top < 0.6:
						continue
					var s := minf(top / 3.4, 1.0) * _rng.randf_range(0.28, 0.4)
					var out := Vector3(normal.x, 0, normal.y)
					var stand := Basis(out.cross(Vector3.UP).normalized(), -PI * 0.5 + _rng.randf_range(-0.25, 0.25))
					var basis := (stand * Basis(Vector3.UP, _rng.randf() * TAU)).scaled(Vector3(s, s * 1.4, s))
					poses.append(Transform3D(basis, Vector3(p.x, GROUND.bowl_at(p.length()) + top * 0.5, p.y)))
	var plates := MultiMesh.new()
	plates.transform_format = MultiMesh.TRANSFORM_3D
	plates.mesh = _kit["ice_floe"]
	plates.instance_count = poses.size()
	for i: int in poses.size():
		plates.set_instance_transform(i, poses[i])
	var view := MultiMeshInstance3D.new()
	view.name = "SlabPlates"
	view.multimesh = plates
	view.material_override = _material("ice", 0)
	add_child(view)

## Loose chunks of broken ice strewn over the sheet: small enough for any bot to
## roll over, never on a start pad.
func _rubble() -> void:
	var cfg: RefCounted = GROUND.settings()
	var poses: Array[Transform3D] = []
	var tries := 0
	while poses.size() < 1400 and tries < 6000:
		tries += 1
		var angle := _rng.randf() * TAU
		var radius := sqrt(_rng.randf_range(pow(cfg.eye_radius + 3.0, 2.0), pow(cfg.rim_radius - 2.0, 2.0)))
		var p := Vector2(cos(angle), sin(angle)) * radius
		if not GROUND.on_ice(p.x, p.y) or _near_pad(p, cfg.pad_radius):
			continue
		var s := _rng.randf_range(0.04, 0.13)
		var tip := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.1, 1.0))
		poses.append(Transform3D((tip * Basis(Vector3.UP, _rng.randf() * TAU)).scaled(Vector3(s, s * 1.5, s)),
			Vector3(p.x, GROUND.surface_at(p.x, p.y) - s * 0.3, p.y)))
	var chunks := MultiMesh.new()
	chunks.transform_format = MultiMesh.TRANSFORM_3D
	chunks.mesh = _kit["ice_floe"]
	chunks.instance_count = poses.size()
	for i: int in poses.size():
		chunks.set_instance_transform(i, poses[i])
	var view := MultiMeshInstance3D.new()
	view.name = "IceRubble"
	view.multimesh = chunks
	view.material_override = _material("ice", 0)
	view.visibility_range_end = 140.0
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)

func _near_pad(p: Vector2, radius: float) -> bool:
	for pad: Vector2 in GROUND.pads():
		if pad.distance_to(p) < radius:
			return true
	return false

# --- The ice sheet -----------------------------------------------------------

## Visual height: the physical height map inside, the exact authored height at
## the jagged edges so the cliff tops stay crisp.
func _sheet_height(x: float, z: float, edge: bool) -> float:
	return GROUND.height_at(x, z) if edge else GROUND.surface_at(x, z)

func _ice_sheet() -> void:
	var cfg: RefCounted = GROUND.settings()
	var mat := ShaderMaterial.new()
	mat.shader = ICE
	_set_ring(mat)
	mat.set_shader_parameter("twist", float(cfg.ridge.twist))
	var root := Node3D.new()
	root.name = "IceSheet"
	add_child(root)
	var per := SHEET_SEGMENTS / SECTORS
	for sector: int in SECTORS:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		var columns := per + 1
		for i: int in columns:
			var angle := TAU * float(sector * per + i) / SHEET_SEGMENTS
			var dir := Vector2(cos(angle), sin(angle))
			var inner: float = GROUND.eye_at(angle) + 0.02
			var outer: float = GROUND.rim_at(angle) - 0.02
			for j: int in SHEET_RINGS + 1:
				var t := float(j) / SHEET_RINGS
				# Denser rings near the edges, where the cliffs are.
				var s := t * t * (3.0 - 2.0 * t) * 0.5 + t * 0.5
				var p := dir * lerpf(inner, outer, s)
				verts.append(Vector3(p.x, _sheet_height(p.x, p.y, j < 3 or j > SHEET_RINGS - 3), p.y))
		for i: int in columns:
			for j: int in SHEET_RINGS + 1:
				var a := verts[maxi(i - 1, 0) * (SHEET_RINGS + 1) + j]
				var b := verts[mini(i + 1, columns - 1) * (SHEET_RINGS + 1) + j]
				var d := verts[i * (SHEET_RINGS + 1) + maxi(j - 1, 0)]
				var e := verts[i * (SHEET_RINGS + 1) + mini(j + 1, SHEET_RINGS)]
				var n := (e - d).cross(b - a).normalized()
				normals.append(n if n.y > 0.0 else -n)
		for i: int in per:
			for j: int in SHEET_RINGS:
				var a := i * (SHEET_RINGS + 1) + j
				var b := a + SHEET_RINGS + 1
				indices.append_array([a, a + 1, b, b, a + 1, b + 1])
		_add_mesh(root, "Sector%d" % sector, verts, normals, indices, mat)
		_cliffs(root, sector, per, mat)

func _add_mesh(parent: Node, label: String, verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, mat: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	parent.add_child(visual)
	return visual

## Sheer ice cliffs from the rim down to the frozen sea, and down the eye into
## the dark: stepped, jutting and striated, seeded per column so neighbours meet.
func _cliffs(parent: Node, sector: int, per: int, mat: Material) -> void:
	var cfg: RefCounted = GROUND.settings()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var steps := [0.0, 0.05, 0.14, 0.27, 0.42, 0.58, 0.74, 0.88, 1.0]
	for side: int in 2:
		var bottom: float = cfg.sea_level - 3.0 if side == 0 else -34.0
		for i: int in per:
			var ring: Array = []
			for k: int in 2:
				var column_id := sector * per + i + k
				var angle := TAU * float(column_id) / SHEET_SEGMENTS
				var dir := Vector2(cos(angle), sin(angle))
				var edge: float = (GROUND.rim_at(angle) - 0.02) if side == 0 else (GROUND.eye_at(angle) + 0.02)
				var top := _sheet_height(dir.x * edge, dir.y * edge, true)
				var column: Array = []
				for row: int in steps.size():
					var f: float = steps[row]
					var h := hash(Vector3i(column_id, row, side)) % 1000 / 1000.0
					# Bulging ice and hanging curtains; the eye's walls lean inward.
					var jut := 0.0 if row == 0 else (h - 0.4) * 2.2 * (1.0 if side == 0 else -1.0)
					var lean := 0.0 if side == 0 else -f * 3.0
					var r := edge + jut + lean
					column.append(Vector3(dir.x * r, lerpf(top, bottom, f), dir.y * r))
				ring.append(column)
			for row: int in steps.size() - 1:
				var a: Vector3 = ring[0][row]
				var b: Vector3 = ring[1][row]
				var c: Vector3 = ring[1][row + 1]
				var d: Vector3 = ring[0][row + 1]
				if side == 0:
					tool.add_vertex(a); tool.add_vertex(b); tool.add_vertex(c)
					tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(d)
				else:
					tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(b)
					tool.add_vertex(a); tool.add_vertex(d); tool.add_vertex(c)
	tool.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = "Cliffs%d" % sector
	visual.mesh = tool.commit()
	visual.material_override = mat
	parent.add_child(visual)

# --- Eye, frozen sea and horizon ---------------------------------------------

func _eye() -> void:
	var vortex := _kit_instance("eye_vortex", Transform3D.IDENTITY, 0)
	vortex.name = "EyeVortex"
	var deep := _material("ice", 0).duplicate() as ShaderMaterial
	deep.set_shader_parameter("snow_amount", 0.4)
	deep.set_shader_parameter("abyss_top", -2.0)
	deep.set_shader_parameter("abyss_bottom", -22.0)
	vortex.material_override = deep

## Pack ice: the frozen sea around the maelstrom, rafted and ridged, relief
## only for the eye (collision is the flat sea_level plane under it).
func _sea_relief(x: float, z: float) -> float:
	return 0.9 * absf(sin(x * 0.045 + z * 0.021)) + 0.6 * absf(sin(z * 0.061 - x * 0.033)) \
		+ 0.35 * absf(sin(x * 0.13 + z * 0.17)) + 1.6 * maxf(0.0, sin(x * 0.011 - z * 0.017) - 0.7) * 3.0

func _sea() -> void:
	var cfg: RefCounted = GROUND.settings()
	var ice := ShaderMaterial.new()
	ice.shader = ICE
	_set_ring(ice)
	ice.set_shader_parameter("twist", float(cfg.ridge.twist))
	var radii: Array[float] = []
	var r: float = cfg.rim_radius - 8.0
	while r < 5000.0:
		radii.append(r)
		r += maxf(1.2, r * 0.035)
	var segments := 480
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i: int in segments:
		var angle := TAU * float(i) / segments
		for rr: float in radii:
			var x := cos(angle) * rr
			var z := sin(angle) * rr
			var y: float = cfg.sea_level + _sea_relief(x, z)
			verts.append(Vector3(x, y, z))
			var gx := _sea_relief(x + 0.5, z) - _sea_relief(x, z)
			var gz := _sea_relief(x, z + 0.5) - _sea_relief(x, z)
			normals.append(Vector3(-gx * 2.0, 1.0, -gz * 2.0).normalized())
	var count := radii.size()
	for i: int in segments:
		var n := (i + 1) % segments
		for j: int in count - 1:
			var a := i * count + j
			var b := n * count + j
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var sea := _add_mesh(self, "FrozenSea", verts, normals, indices, ice)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rubble heaped at the foot of the rim cliffs, and rafted plates beyond.
	var plates := MultiMesh.new()
	plates.transform_format = MultiMesh.TRANSFORM_3D
	plates.mesh = _kit["ice_floe"]
	plates.instance_count = 260
	for i: int in plates.instance_count:
		var angle := _rng.randf() * TAU
		var foot := i < 180
		var radius: float = GROUND.rim_at(angle) + (_rng.randf_range(1.0, 14.0) if foot else _rng.randf_range(20.0, 420.0))
		var s := _rng.randf_range(0.5, 1.6) if foot else _rng.randf_range(0.8, 2.6)
		var tip := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.3, 1.2) if foot else _rng.randf_range(0.15, 0.7))
		var at := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		at.y = cfg.sea_level + _sea_relief(at.x, at.z) - 0.4
		plates.set_instance_transform(i, Transform3D((tip * Basis(Vector3.UP, _rng.randf() * TAU)).scaled(Vector3(s, s, s)), at))
	var plate_view := MultiMeshInstance3D.new()
	plate_view.name = "PackIce"
	plate_view.multimesh = plates
	plate_view.material_override = _material("ice", 0)
	add_child(plate_view)
	# Icebergs locked into the sea ice.
	var bergs := Node3D.new()
	bergs.name = "Icebergs"
	add_child(bergs)
	for i: int in 22:
		var angle := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / 22.0
		var radius := _rng.randf_range(190.0, 520.0)
		var s := _rng.randf_range(3.0, 7.0)
		var tilt := Basis(Vector3(cos(angle), 0, sin(angle)).cross(Vector3.UP).normalized(), _rng.randf_range(-0.3, 0.15))
		var visual := _kit_instance("ice_shards_a" if i % 2 == 0 else "ice_shards_b", Transform3D((tilt * Basis(Vector3.UP, _rng.randf() * TAU)).scaled(Vector3.ONE * s),
			Vector3(cos(angle) * radius, cfg.sea_level - s * 0.8, sin(angle) * radius)), 0, bergs)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Black crags breaking through the pack ice.
	for i: int in 14:
		var angle := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / 14.0 + 0.2
		var radius := _rng.randf_range(300.0, 900.0)
		var s := _rng.randf_range(2.5, 5.5)
		var model: String = ["rock_spire_a", "rock_spire_b", "rock_crag"][i % 3]
		var visual := _kit_instance(model, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s),
			Vector3(cos(angle) * radius, cfg.sea_level - 2.0, sin(angle) * radius)), 0, bergs)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ice_walls()

## Colossal walls of glacier ice enclosing the frozen sea, fading into haze:
## bulging, striated faces hung with ice, their crests broken and jagged.
func _ice_walls() -> void:
	var cfg: RefCounted = GROUND.settings()
	var segments := 360
	var rows := 10
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	var grid: Array = []
	for i: int in segments + 1:
		var angle := TAU * float(i % segments) / segments
		var dir := Vector3(cos(angle), 0, sin(angle))
		var base := 760.0 + 140.0 * sin(angle * 3.0 + 0.4) + 60.0 * sin(angle * 7.0)
		var crest := 150.0 + 90.0 * absf(sin(angle * 5.0 + 1.1)) + 45.0 * absf(sin(angle * 13.0)) \
			+ 18.0 * float(hash(i % segments) % 1000) / 1000.0
		var column: Array = []
		for row: int in rows + 1:
			var f := float(row) / rows
			var bulge := 22.0 * sin(f * PI * 1.6 + angle * 9.0) * (1.0 - f) + float(hash(Vector2i(i % segments, row)) % 1000) / 1000.0 * 9.0
			column.append(dir * (base - bulge + f * 60.0) + Vector3(0, cfg.sea_level - 4.0 + crest * f, 0))
		grid.append(column)
	for i: int in segments:
		for row: int in rows:
			var a: Vector3 = grid[i][row]
			var b: Vector3 = grid[i + 1][row]
			var c: Vector3 = grid[i + 1][row + 1]
			var d: Vector3 = grid[i][row + 1]
			tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(b)
			tool.add_vertex(a); tool.add_vertex(d); tool.add_vertex(c)
	tool.generate_normals()
	var walls := MeshInstance3D.new()
	walls.name = "IceWalls"
	walls.mesh = tool.commit()
	var mat := _material("ice", 0).duplicate() as ShaderMaterial
	mat.set_shader_parameter("snow_amount", 1.2)
	mat.set_shader_parameter("surface", Color(0.13, 0.17, 0.21))
	mat.set_shader_parameter("core", Color(0.03, 0.045, 0.06))
	walls.material_override = mat
	walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(walls)
func _snowfall() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snowfall"
	_snow.amount = 8000
	_snow.lifetime = 7.0
	_snow.preprocess = 7.0
	_snow.visibility_aabb = AABB(Vector3(-90, -40, -90), Vector3(180, 80, 180))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(70, 20, 70)
	process.direction = Vector3(1, -0.3, 0.4)
	process.spread = 20.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 9.0
	process.gravity = Vector3(2.0, -2.2, 1.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 2.0
	process.scale_min = 0.5
	process.scale_max = 1.4
	_snow.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var flake := StandardMaterial3D.new()
	flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.albedo_color = Color(0.72, 0.78, 0.85, 0.75)
	flake.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Flakes that drift right up to the lens would fill the view: fade them out.
	flake.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	flake.distance_fade_min_distance = 1.5
	flake.distance_fade_max_distance = 5.0
	quad.material = flake
	_snow.draw_pass_1 = quad
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snow)

# --- Lighting --------------------------------------------------------------

## Overcast polar dusk: a cold moon behind the cloud deck, heavy freezing haze
## and drifting ground mist, the palette drained almost to blue-grey.
func _lighting(arena: Node) -> void:
	var cfg: Dictionary = GROUND.settings().art
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
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_color = Color(0.3, 0.38, 0.48)
	env.ambient_light_energy = float(cfg.ambient_energy)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.ssao_enabled = true
	env.ssao_radius = 2.4
	env.ssao_intensity = 2.6
	env.ssao_power = 1.5
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.38, 0.47)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.12
	env.fog_density = float(cfg.fog_density)
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.6
	env.fog_height = 1.5
	env.fog_height_density = 0.06
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.7, 0.78, 0.86)
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0
	world.environment = env
	var moon := arena.get_node("Sun") as DirectionalLight3D
	var elevation := deg_to_rad(34.0)
	var azimuth := deg_to_rad(70.0)
	var toward := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
	moon.transform = Transform3D(Basis.looking_at(-toward, Vector3.UP), Vector3.ZERO)
	moon.light_color = Color(0.66, 0.75, 0.9)
	moon.light_energy = float(cfg.sun_energy)
	moon.shadow_enabled = true
	moon.shadow_blur = 2.5
	moon.light_volumetric_fog_energy = 1.4
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 180.0