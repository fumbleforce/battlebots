class_name BotDestructionVisual
extends Node3D
## Confirmed core destruction only. All trajectories are cosmetic and world-space.
const CLOUD := preload("res://scripts/presentation/destruction_cloud.gdshader")
const RING := preload("res://scripts/presentation/destruction_ring.gdshader")
const WRECK := preload("res://scripts/presentation/destruction_wreck.gdshader")
const MAX_BURSTS := 2
const SPARKS := 64
const PANELS := 8
const DURATION := 4.2
const GROUP := &"bot_destruction_visuals"

var burst_count := 0
var active := false
var effect_age := 0.0
var burst_root: Node3D
var _observed := false
var _eliminated := false
var _wrecked := false
var _size := Vector3(1.6, 0.5, 2.0)
var _geometry_scale := 1.0
var _surfaces: Array[Dictionary] = []
var _wreck_material: ShaderMaterial
var _fire_material: ShaderMaterial
var _smoke_material: ShaderMaterial
var _ring_material: ShaderMaterial
var _fire: Array[MeshInstance3D] = []
var _smoke: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _flash: OmniLight3D
var _sparks: MultiMeshInstance3D
var _panels: MultiMeshInstance3D
var _spark_paths: Array[Dictionary] = []
var _panel_paths: Array[Dictionary] = []
var _detachable: Array[MeshInstance3D] = []
var _detached_sources: Array[MeshInstance3D] = []
var _chunks: Array[MeshInstance3D] = []
var _chunk_paths: Array[Dictionary] = []

func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)

func configure(visual_root: Node3D, size: Vector3, excluded_meshes: Array = []) -> void:
	reset_observation()
	_surfaces.clear()
	_detachable.clear()
	_geometry_scale = BotScale.from_size(size)
	_size = size / _geometry_scale
	if is_instance_valid(_flash):
		_flash.omni_range = 9.0 * _geometry_scale
		_flash.position.y = 0.7 * _geometry_scale
	_wreck_material = ShaderMaterial.new()
	_wreck_material.shader = WRECK
	for mesh: MeshInstance3D in visual_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree() and str(mesh.name).begins_with("Detach_"):
			_detachable.append(mesh)
		if mesh.is_visible_in_tree() and mesh not in excluded_meshes and not is_ancestor_of(mesh):
			_surfaces.append({"mesh": mesh, "original": mesh.material_overlay})
	# Authored weapon and drive assemblies are the most recognizable flying pieces.
	_detachable.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return _chunk_priority(a.name) < _chunk_priority(b.name))

func _chunk_priority(label: String) -> int:
	return 0 if label.begins_with("Detach_Weapon") else (1 if label.begins_with("Detach_Drive") else 2)

func observe(view: BotView) -> void:
	if view == null:
		reset_observation()
		return
	if not is_finite(view.core_fraction) or view.core_fraction < 0.0 or view.core_fraction > 1.0 or not view.pose.is_finite(): return
	var destroyed := view.eliminated and view.core_fraction <= 0.0
	_set_wreck(destroyed)
	if not view.eliminated: clear_effects()
	if _observed and not _eliminated and destroyed:
		_explode(view.pose.origin, view.entity_id)
	_observed = true
	_eliminated = view.eliminated

func reset_observation() -> void:
	clear_effects()
	_set_wreck(false)
	_observed = false
	_eliminated = false

func _set_wreck(enabled: bool) -> void:
	if _wrecked == enabled: return
	_wrecked = enabled
	if not enabled:
		for source: MeshInstance3D in _detached_sources:
			if is_instance_valid(source): source.show()
		_detached_sources.clear()
	for surface: Dictionary in _surfaces:
		if is_instance_valid(surface.mesh):
			surface.mesh.material_overlay = _wreck_material if enabled else surface.original

func _exit_tree() -> void:
	_set_wreck(false)

func clear_effects() -> void:
	active = false
	effect_age = 0.0
	set_process(false)
	if is_instance_valid(burst_root): burst_root.hide()
	if is_instance_valid(_flash): _flash.light_energy = 0.0

func _explode(origin: Vector3, identity: int) -> void:
	var others: Array[Node] = []
	for effect: Node in get_tree().get_nodes_in_group(GROUP):
		if effect != self and effect.active: others.append(effect)
	# Reserve a bounded client budget, including simultaneous larger-mode knockouts.
	while others.size() >= MAX_BURSTS:
		var oldest: Node = others[0]
		for effect: Node in others:
			if effect.effect_age > oldest.effect_age: oldest = effect
		oldest.clear_effects()
		others.erase(oldest)
	if burst_root == null: _build_burst()
	burst_count += 1
	effect_age = 0.0
	active = true
	get_tree().call_group(&"combat_impact_visuals", &"trim_fragments")
	burst_root.global_transform = Transform3D(Basis.IDENTITY, origin)
	burst_root.show()
	var random := RandomNumberGenerator.new()
	random.seed = identity * 7919 + burst_count * 104729
	_spark_paths.clear()
	for index: int in SPARKS:
		var angle := random.randf_range(0.0, TAU)
		var direction := Vector3(cos(angle), random.randf_range(0.2, 1.1), sin(angle)).normalized()
		_spark_paths.append({"velocity": direction * random.randf_range(5.0, 13.0),
			"life": random.randf_range(0.45, 1.35)})
	_panel_paths.clear()
	_launch_authored_chunks(origin, random)
	for index: int in PANELS - _chunk_paths.size():
		var angle := TAU * float(index) / PANELS + random.randf_range(-0.2, 0.2)
		_panel_paths.append({"origin": Vector3(cos(angle) * _size.x * 0.35, 0.1, sin(angle) * _size.z * 0.35),
			"velocity": Vector3(cos(angle) * random.randf_range(3.0, 5.0), random.randf_range(3.5, 6.5), sin(angle) * random.randf_range(3.0, 5.0)),
			"spin": Vector3(random.randf_range(-5, 5), random.randf_range(-5, 5), random.randf_range(-5, 5)),
			"scale": Vector3(random.randf_range(0.12, 0.3), 0.035, random.randf_range(0.18, 0.4))})
	set_process(true)
	_update_burst()

func _build_burst() -> void:
	burst_root = Node3D.new()
	burst_root.name = "DestructionBurst"
	add_child(burst_root)
	burst_root.top_level = true
	_fire_material = ShaderMaterial.new()
	_fire_material.shader = CLOUD
	_smoke_material = ShaderMaterial.new()
	_smoke_material.shader = CLOUD
	_smoke_material.set_shader_parameter("smoke", true)
	for index: int in 9:
		var puff := _cloud(_fire_material)
		puff.set_instance_shader_parameter("seed", float(index) * 0.73)
		_fire.append(puff)
	for index: int in 10:
		var puff := _cloud(_smoke_material)
		puff.set_instance_shader_parameter("seed", float(index) * 1.31 + 10.0)
		_smoke.append(puff)
	_ring = MeshInstance3D.new()
	var ring_mesh := PlaneMesh.new()
	ring_mesh.size = Vector2.ONE * 2.0
	_ring.mesh = ring_mesh
	_ring_material = ShaderMaterial.new()
	_ring_material.shader = RING
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst_root.add_child(_ring)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.42, 0.08)
	_flash.omni_range = 9.0 * _geometry_scale
	_flash.omni_attenuation = 1.4
	_flash.shadow_enabled = false
	_flash.position.y = 0.7 * _geometry_scale
	burst_root.add_child(_flash)
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.vertex_color_use_as_albedo = true
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.28, 0.025)
	spark_material.emission_energy_multiplier = 3.5
	_sparks = _multimesh(SPARKS, spark_material)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.21, 0.24, 0.27)
	metal.metallic = 0.75
	metal.roughness = 0.45
	metal.vertex_color_use_as_albedo = true
	_panels = _multimesh(PANELS, metal)
	for index: int in PANELS:
		var chunk := MeshInstance3D.new()
		chunk.name = "DetachedAssembly%d" % index
		chunk.hide()
		burst_root.add_child(chunk)
		_chunks.append(chunk)

func _launch_authored_chunks(origin: Vector3, random: RandomNumberGenerator) -> void:
	_chunk_paths.clear()
	for chunk: MeshInstance3D in _chunks: chunk.hide()
	for source: MeshInstance3D in _detachable:
		if _chunk_paths.size() >= PANELS: break
		if not is_instance_valid(source) or not source.is_visible_in_tree(): continue
		var chunk := _chunks[_chunk_paths.size()]
		chunk.mesh = source.mesh
		chunk.material_override = source.material_override
		chunk.material_overlay = _wreck_material
		for surface: int in source.mesh.get_surface_count():
			chunk.set_surface_override_material(surface, source.get_surface_override_material(surface))
		var pose := source.global_transform
		pose.origin -= origin
		var outward := Vector3(pose.origin.x, 0, pose.origin.z).normalized()
		if outward.length_squared() < 0.1: outward = Vector3.FORWARD.rotated(Vector3.UP, random.randf_range(0, TAU))
		_chunk_paths.append({"pose":pose, "velocity":(outward * random.randf_range(1.3, 2.5) + Vector3.UP * random.randf_range(2.5, 4.0)) * _geometry_scale,
			"spin":Vector3(random.randf_range(-3,3), random.randf_range(-3,3), random.randf_range(-3,3))})
		chunk.show()
		source.hide()
		_detached_sources.append(source)
	_panels.multimesh.visible_instance_count = PANELS - _chunk_paths.size()

func _cloud(material: Material) -> MeshInstance3D:
	var puff := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0
	puff.mesh = quad
	puff.material_override = material
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst_root.add_child(puff)
	return puff

func _multimesh(count: int, material: Material) -> MultiMeshInstance3D:
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = material
	batch.multimesh.mesh = box
	batch.multimesh.instance_count = count
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst_root.add_child(batch)
	return batch

func _process(delta: float) -> void:
	if not active or not is_finite(delta): return
	effect_age += maxf(delta, 0.0)
	if effect_age >= DURATION:
		clear_effects()
		return
	_update_burst()

func _update_burst() -> void:
	var t := effect_age
	_fire_material.set_shader_parameter("age", t)
	_smoke_material.set_shader_parameter("age", t)
	_ring_material.set_shader_parameter("age", t)
	_flash.light_energy = 9.0 * exp(-t * 8.0) + 1.5 * exp(-t * 3.0)
	_flash.visible = t < 1.5
	_ring.visible = t < 0.55
	_ring.position.y = -_size.y * 0.35 * _geometry_scale
	_ring.scale = Vector3.ONE * (0.6 + t * 12.0) * _geometry_scale
	for index: int in _fire.size():
		var puff := _fire[index]
		puff.visible = t < 1.05
		var angle := float(index) * 2.39996
		var spread := (1.0 - exp(-t * 7.0)) * (0.35 + float(index % 3) * 0.35)
		puff.position = Vector3(cos(angle) * spread, 0.25 + t * (0.9 + float(index % 3) * 0.45), sin(angle) * spread) * _geometry_scale
		puff.scale = Vector3.ONE * (0.15 + (1.0 - exp(-t * 12.0)) * (0.6 + float(index % 3) * 0.16)) * _geometry_scale
	for index: int in _smoke.size():
		var puff := _smoke[index]
		puff.visible = t > 0.12
		var angle := float(index) * 2.39996
		var spread := (0.15 + t * 0.42) * (0.7 + float(index % 3) * 0.3)
		puff.position = Vector3(cos(angle) * spread, 0.4 + t * (0.7 + float(index % 4) * 0.23), sin(angle) * spread) * _geometry_scale
		puff.scale = Vector3.ONE * (0.35 + t * 0.47 + float(index % 3) * 0.13) * _geometry_scale
	_sparks.visible = t < 1.35
	for index: int in _spark_paths.size():
		if not _sparks.visible: break
		var path: Dictionary = _spark_paths[index]
		var fade := clampf(1.0 - t / float(path.life), 0.0, 1.0)
		var velocity: Vector3 = path.velocity + Vector3.DOWN * 5.0 * t
		var location: Vector3 = path.velocity * t + Vector3.DOWN * 2.5 * t * t
		var basis := Basis.looking_at(velocity.normalized(), Vector3.UP)
		basis = basis.scaled(Vector3(0.022, 0.022, 0.18 + velocity.length() * 0.025) * maxf(fade, 0.0001) * _geometry_scale)
		_sparks.multimesh.set_instance_transform(index, Transform3D(basis, location * _geometry_scale))
		_sparks.multimesh.set_instance_color(index, Color(1.0, 0.35 + fade * 0.55, 0.06 + fade * 0.35))
	_panels.visible = t < 2.1
	for index: int in _panel_paths.size():
		if not _panels.visible: break
		var path: Dictionary = _panel_paths[index]
		var fade := 1.0 - smoothstep(1.5, 2.1, t)
		var location: Vector3 = path.origin + path.velocity * t + Vector3.DOWN * 4.9 * t * t
		# Ballistic pieces disappear naturally behind terrain. Never invent a floor
		# at the blast height: a robot may be destroyed while airborne or inverted.
		var basis := Basis.from_euler(path.spin * t).scaled(path.scale * maxf(fade, 0.0001) * _geometry_scale)
		_panels.multimesh.set_instance_transform(index, Transform3D(basis, location * _geometry_scale))
		_panels.multimesh.set_instance_color(index, Color(1.0, 0.6 + t * 0.2, 0.4 + t * 0.25))
	for index: int in _chunk_paths.size():
		var chunk := _chunks[index]
		chunk.visible = t < 3.5
		if not chunk.visible: continue
		var path: Dictionary = _chunk_paths[index]
		var pose: Transform3D = path.pose
		pose.origin += path.velocity * t + Vector3.DOWN * 4.9 * t * t
		# Keep imported material, scale and exact world orientation at the break.
		pose.basis = Basis.from_euler(path.spin * t) * pose.basis
		pose.basis = pose.basis.scaled(Vector3.ONE * maxf(0.0001, 1.0 - smoothstep(2.7, 3.5, t)))
		chunk.transform = pose
