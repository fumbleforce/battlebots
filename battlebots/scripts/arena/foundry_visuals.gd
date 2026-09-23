extends Node3D
## Presentation only. Never creates bodies, changes spawns, or processes frames.
## Repeated architecture is batched by material into MultiMeshes.

const STEEL = preload("res://assets/materials/arena/foundry_steel.gdshader")
const FLOOR = preload("res://assets/materials/arena/foundry_floor.gdshader")
const STEEL_SCAN = preload("res://assets/textures/arena/foundry_steel_albedo.png")
var _batches: Dictionary = {}
var _materials: Dictionary = {}
var _side := Transform3D.IDENTITY
@export var arena_path: NodePath = NodePath("..")

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_build()

func _material(key: String, color: Color, emission: float = 0.0) -> Material:
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	if emission > 0.0:
		var lit := StandardMaterial3D.new()
		lit.albedo_color = color
		lit.emission_enabled = true
		lit.emission = color
		lit.emission_energy_multiplier = emission
		mat = lit
	else:
		var metal := ShaderMaterial.new()
		metal.shader = STEEL
		metal.set_shader_parameter("paint_color", color)
		metal.set_shader_parameter("hazard", key == "hazard")
		metal.set_shader_parameter("steel_texture", STEEL_SCAN)
		mat = metal
	_materials[key] = mat
	return mat

func _box(key: String, at: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	if not _batches.has(key):
		_batches[key] = []
	var pose := Transform3D(Basis.from_euler(rotation).scaled_local(size), at)
	_batches[key].append(_side * pose)

func _beam(key: String, a: Vector3, b: Vector3, width: float) -> void:
	var direction := b - a
	var axis := direction.normalized()
	var right := axis.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < 0.1:
		right = axis.cross(Vector3.UP).normalized()
	var basis := Basis(right, axis, right.cross(axis)).scaled_local(Vector3(width, direction.length(), width))
	if not _batches.has(key):
		_batches[key] = []
	_batches[key].append(_side * Transform3D(basis, (a+b)*0.5))

func _text(words: String, at: Vector3, size: int, pixel: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = true
	label.transform = _side * Transform3D(Basis.IDENTITY, at)
	add_child(label)
	return label

func _build() -> void:
	_material("steel", Color("343d42"))
	_material("dark", Color("171e24"))
	_material("concrete", Color("777367"))
	_material("rust", Color("643b29"))
	_material("red", Color("973e2e"))
	_material("hazard", Color.WHITE)
	_material("seat", Color("5b3528"))
	_material("crowd_coal", Color("353a3e"))
	_material("crowd_ochre", Color("726450"))
	_material("crowd_slate", Color("3a505b"))
	_material("crowd_head", Color("8a7361"))
	_material("white", Color("fff0cf"), 5.0)
	_material("amber", Color("ff9b37"), 2.3)
	_material("cyan", Color("52bfd5"), 1.5)
	_material("redlight", Color("ff3d22"), 2.0)
	var arena := get_node(arena_path)
	var floor_mesh := arena.get_node_or_null("Floor/Mesh") as MeshInstance3D
	if floor_mesh:
		var floor_mat := ShaderMaterial.new()
		floor_mat.shader = FLOOR
		floor_mat.set_shader_parameter("steel_texture", STEEL_SCAN)
		floor_mat.set_shader_parameter("arena_half_extent", ArenaBounds.FOUNDRY_HALF)
		floor_mesh.material_override = floor_mat
	for wall: Node in arena.get_node("Walls").get_children():
		var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			mesh.material_override = _materials.concrete
			if String(wall.name).begins_with("Corner"):
				var corner := _materials.concrete.duplicate() as ShaderMaterial
				corner.set_shader_parameter("hazard", true)
				corner.set_shader_parameter("banded", true)
				mesh.material_override = corner
	(arena.get_node("Markings") as Node3D).hide()
	_lighting(arena)
	# Two full-sized gallery bays per face: seats, people and machinery keep
	# their authored scale while the combat bowl doubles in width.
	for side: int in range(8):
		var rotation := Basis(Vector3.UP, side * PI / 4.0)
		for bay: int in range(2):
			_side = Transform3D(rotation, rotation * Vector3((bay * 2 - 1) * 10.355339, 0, -25))
			_wall(side * 2 + bay)
	_side = Transform3D.IDENTITY
	_roof()
	_floor_identity()
	_flush()
	# Capture actual arena lighting for lacquer and bare-metal bot reflections.
	# Static architecture uses a single bounded capture; combat lights stay direct.
	var probe := ReflectionProbe.new()
	probe.name = "CombatFloorReflections"
	probe.position = Vector3(0, 5, 0)
	probe.size = Vector3(104, 16, 104)
	probe.origin_offset = Vector3(0, 2, 0)
	probe.max_distance = 140
	probe.interior = true
	probe.box_projection = true
	probe.intensity = 0.8
	add_child(probe)

func _wall(side: int) -> void:
	const HALF_SIDE := 10.355339
	# Eight equal bays, tangent to the playable octagon's 25 m inradius.
	_box("dark", Vector3(0, 1.4, -25.08), Vector3(20.71, 2.75, 0.14))
	for i: int in range(6):
		var x := -8.63 + i * 3.452
		_box("concrete", Vector3(x, 0.6, -24.98), Vector3(3.38, 1.16, 0.08))
		_box("hazard", Vector3(x, 2.14, -24.98), Vector3(3.38, 1.3, 0.08))
		_box("steel", Vector3(x, 1.26, -24.96), Vector3(3.4, 0.12, 0.025))
		for dx: float in [-1.48, 1.48]:
			for y: float in [0.18, 1.02, 1.65, 2.63]:
				_box("steel", Vector3(x+dx, y, -24.94), Vector3(0.09, 0.09, 0.045))
	_box("steel", Vector3(0, 3.06, -25.18), Vector3(20.9, 0.22, 0.35))
	_box("amber", Vector3(0, 2.91, -24.96), Vector3(20.5, 0.035, 0.025))
	for i: int in range(43):
		_box("steel", Vector3(-10.35+i*0.493, 5.45, -25.23), Vector3(0.018, 4.6, 0.018))
	for i: int in range(10):
		_box("steel", Vector3(0, 3.2+i*0.5, -25.23), Vector3(20.71, 0.018, 0.018))
	for y: float in [5.5, 7.9]:
		_box("steel", Vector3(0, y, -25.3), Vector3(20.71, 0.12, 0.14))
	for x: float in [-HALF_SIDE, HALF_SIDE]:
		_box("steel", Vector3(x, 8.5, -25.55), Vector3(0.24, 17, 0.54))
		for z: float in [-25.25, -25.85]:
			_box("steel", Vector3(x, 8.5, z), Vector3(0.64, 17, 0.10))
		_box("rust", Vector3(x, 3.5, -25.1), Vector3(0.78, 0.75, 0.2))
		_box("redlight", Vector3(x, 8.25, -25.18), Vector3(0.13, 0.3, 0.12))
		_beam("steel", Vector3(x, 12.2, -25.6), Vector3(x*0.48, 16.7, -25.6), 0.2)
	_box("dark", Vector3(0, 8.0, -33.8), Vector3(28.5, 26.5, 0.5))
	for tier: int in range(5):
		var y := 3.0+tier*0.8
		var z := -27.4-tier*1.15
		var span := 21.6+tier*0.8
		_box("dark", Vector3(0, y-0.25, z), Vector3(span, 0.5, 1.3))
		_box("steel", Vector3(0, y+0.03, z+0.55), Vector3(span, 0.08, 0.10))
		for seat: int in range(26):
			var x := -10.25+seat*0.82
			if absf(x) < 2.9:
				continue
			_box("seat", Vector3(x, y+0.3, z), Vector3(0.6, 0.12, 0.55))
			_box("seat", Vector3(x, y+0.59, z-0.24), Vector3(0.6, 0.55, 0.1))
			var seat_id := seat*13+tier*7+side*19
			if seat_id % 7 != 0:
				var shirt: String = ["crowd_coal", "crowd_ochre", "crowd_slate"][seat_id % 3]
				var lean := sin(float(seat_id))*0.08
				_box(shirt, Vector3(x, y+0.74, z+0.04), Vector3(0.39, 0.60, 0.29), Vector3(lean, lean, 0))
				_box("crowd_head", Vector3(x+lean*0.2, y+1.12, z+0.06), Vector3(0.23, 0.27, 0.23))
		for x: float in [-2.8, 2.8]:
			_box("amber", Vector3(x, y+0.04, z+0.57), Vector3(0.12, 0.045, 0.04))
	# Recessed shutter, original venue identity and numbered portals.
	_box("dark", Vector3(0, 5.1, -27.0), Vector3(5.7, 4.2, 0.3))
	for i: int in range(15):
		_box("steel", Vector3(0, 3.25+i*0.25, -26.8), Vector3(4.8, 0.2, 0.12))
	for x: float in [-2.6, 2.6]:
		_box("hazard", Vector3(x, 5.0, -26.65), Vector3(0.4, 4.2, 0.25))
	_box("rust", Vector3(0, 7.35, -26.7), Vector3(5.8, 0.5, 0.5))
	_box("cyan" if side % 2 == 0 else "amber", Vector3(0, 7.38, -26.42), Vector3(4.8, 0.06, 0.035))
	_text("GATE  /  %02d" % (side+1), Vector3(0, 6.5, -26.64), 64, 0.010, Color("d6d1bc"))
	for x: float in [-7.5, 7.5]:
		_box("red", Vector3(x, 10.4, -25.95), Vector3(2.8, 4.8, 0.12))
		_box("steel", Vector3(x, 12.88, -25.9), Vector3(3.0, 0.17, 0.25))
		_text("F / %02d" % (side+1), Vector3(x, 11.0, -25.85), 100, 0.008, Color("ddd3b8"))
		_text("HEAVY METAL\nCOMBAT DIVISION", Vector3(x, 9.65, -25.84), 32, 0.008, Color("c6b798"))
	_box("dark", Vector3(0, 10.5, -26.0), Vector3(11, 3.2, 0.4))
	_text("F O U N D R Y", Vector3(0, 10.9, -25.76), 128, 0.010, Color("f0dcc0"))
	_text("O C T A G O N   /   %02d" % (side+1), Vector3(0, 9.55, -25.75), 40, 0.009, Color("de9c53"))
	_services()
	for x: float in [-7.5, 7.5]:
		_box("dark", Vector3(x, 13.5, -24.6), Vector3(2.7, 0.9, 0.7))
		for lamp: int in range(3):
			_box("white", Vector3(x-0.8+lamp*0.8, 13.5, -24.22), Vector3(0.6, 0.52, 0.035))
		var light := SpotLight3D.new()
		add_child(light)
		light.position = _side * Vector3(x, 13.1, -24.0)
		light.look_at(_side * Vector3(x*0.7, 0, -13.0))
		light.light_color = Color("ffdfb0") if side % 2 == 0 else Color("a9cfe9")
		light.light_energy = 1.7
		light.spot_range = 32.0
		light.spot_angle = 42.0
		light.spot_attenuation = 1.1
		light.light_volumetric_fog_energy = 0.5
		light.shadow_enabled = false
	var gallery_light := OmniLight3D.new()
	add_child(gallery_light)
	gallery_light.position = _side * Vector3(0, 9, -29)
	gallery_light.light_color = Color("ffbd79")
	gallery_light.light_energy = 1.1
	gallery_light.omni_range = 12.0
	gallery_light.light_volumetric_fog_energy = 0.1

func _pipe(at: Vector3, radius: float, length: float, rotation: Vector3, key: String) -> void:
	var pipe := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.material = _materials[key]
	pipe.mesh = mesh
	pipe.transform = _side * Transform3D(Basis.from_euler(rotation), at)
	pipe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pipe)

func _services() -> void:
	for y: float in [14.65, 15.25]:
		_pipe(Vector3(0, y, -26.4), 0.18, 21.7, Vector3(0, 0, PI/2), "rust")
		for x: float in [-9, -6, -3, 0, 3, 6, 9]:
			_pipe(Vector3(x, y, -26.4), 0.23, 0.12, Vector3(0, 0, PI/2), "steel")
	for x: float in [-7.0, 7.0]:
		_box("steel", Vector3(x, 6.6, -27), Vector3(2.2, 2.2, 0.45))
		_pipe(Vector3(x, 6.6, -26.7), 0.96, 0.24, Vector3(PI/2, 0, 0), "dark")
		_pipe(Vector3(x, 6.6, -26.48), 0.17, 0.3, Vector3(PI/2, 0, 0), "steel")
		for blade: int in range(8):
			var angle := blade*TAU/8.0
			_box("steel", Vector3(x+sin(angle)*0.54, 6.6+cos(angle)*0.54, -26.54),
				Vector3(0.3, 0.74, 0.07), Vector3(0, 0, -angle+0.3))
	for y: float in [3.8, 4.5]:
		_box("steel", Vector3(0, y, -26.6), Vector3(21.5, 0.055, 0.055))
	for i: int in range(12):
		_box("steel", Vector3(-10.4+i*1.89, 3.8, -26.6), Vector3(0.055, 1.5, 0.055))

func _roof() -> void:
	_box("dark", Vector3(0, 20.4, 0), Vector3(120, 0.35, 120))
	# Radial roof trusses converge on a suspended octagonal crown.
	for side: int in range(8):
		_side = Transform3D(Basis(Vector3.UP, side*PI/4.0), Vector3.ZERO)
		for y: float in [16.8, 19.1]:
			_box("steel", Vector3(0, y, -51.0), Vector3(43.6, 0.23, 0.25))
		for i: int in range(12):
			var x := -21.6+i*3.6
			_beam("steel", Vector3(x, 16.8, -51), Vector3(x+3.6, 19.1, -51), 0.14)
			_beam("steel", Vector3(x, 19.1, -51), Vector3(x+3.6, 16.8, -51), 0.14)
		for y: float in [17, 19]:
			_beam("steel", Vector3(0, y, -51), Vector3(0, y, -16), 0.22)
		for i: int in range(10):
			var z := -51.0+i*3.5
			_beam("steel", Vector3(0, 17, z), Vector3(0, 19, z+3.5), 0.13)
			_beam("steel", Vector3(0, 19, z), Vector3(0, 17, z+3.5), 0.13)
		# The crown follows the enlarged floor; fixtures retain human dimensions.
		_side.origin = _side.basis * Vector3(0, 0, -8)
		_box("steel", Vector3(0, 14.0, -8), Vector3(13.5, 0.38, 0.45))
		_box("amber", Vector3(0, 13.77, -7.88), Vector3(13.0, 0.04, 0.07))
		_beam("dark", Vector3(0, 14, -8), Vector3(0, 20.3, -8), 0.055)
		_box("dark", Vector3(0, 13.72, -8), Vector3(2.8, 0.22, 0.95))
		for x: float in [-0.9, 0, 0.9]:
			_box("white", Vector3(x, 13.58, -8), Vector3(0.7, 0.035, 0.65))
		var key := SpotLight3D.new()
		add_child(key)
		key.position = _side * Vector3(0, 13.4, -8)
		key.look_at(_side * Vector3(0, 0, -5))
		key.light_color = Color("ffe5c6")
		key.light_energy = 2.0
		key.spot_range = 40
		key.spot_angle = 62
		key.spot_attenuation = 0.65
		key.shadow_enabled = side % 2 == 0
		key.light_volumetric_fog_energy = 0.65
	_side = Transform3D.IDENTITY

func _floor_identity() -> void:
	var crest := _text("F / 01", Vector3(0, 0.027, 0), 180, 0.022, Color("b8aa89"))
	crest.rotation_degrees.x = -90
	var subtitle := _text("THE FOUNDRY", Vector3(0, 0.029, 2.0), 64, 0.018, Color("8d8573"))
	subtitle.rotation_degrees.x = -90
	for side: int in range(2):
		var rotation := Basis(Vector3.UP, side*PI)
		_side = Transform3D(rotation, rotation * Vector3(0, 0, 19))
		for x: float in [-12, 12]:
			_box("cyan" if side == 0 else "amber", Vector3(x, 0.014, 21.4), Vector3(3.6, 0.018, 0.055))
			for offset: float in [-1.8, 1.8]:
				_box("steel", Vector3(x+offset, 0.012, 20.5), Vector3(0.045, 0.015, 1.8))
	_side = Transform3D.IDENTITY

func _lighting(arena: Node) -> void:
	var world := arena.get_node("WorldEnvironment") as WorldEnvironment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101923")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a8bfd2")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.fog_enabled = true
	env.fog_light_color = Color("71818b")
	env.fog_light_energy = 0.45
	env.fog_density = 0.0015
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.65, 0.69, 0.72)
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_ambient_inject = 0.25
	world.environment = env
	var sun := arena.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-68, -24, 0)
	sun.light_color = Color("ffe0b8")
	sun.light_energy = 0.55
	sun.directional_shadow_max_distance = 150.0
	# Roof is scenic; the key light simulates the distributed overhead fixtures.

func _flush() -> void:
	for key: String in _batches:
		var mesh: PrimitiveMesh
		if key.begins_with("crowd_"):
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.5
			capsule.height = 1.0
			capsule.radial_segments = 8
			capsule.rings = 2
			mesh = capsule
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			mesh = box
		mesh.material = _materials[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = _batches[key].size()
		for index: int in range(multi.instance_count):
			multi.set_instance_transform(index, _batches[key][index])
		var visual := MultiMeshInstance3D.new()
		visual.name = key.capitalize() + "Batch"
		visual.multimesh = multi
		# Only the existing perimeter and robots cast the key light's shadows.
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	_batches.clear()
