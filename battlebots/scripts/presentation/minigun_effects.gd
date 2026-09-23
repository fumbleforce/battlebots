class_name MinigunEffects
extends Node3D
## Accepted shot snapshots only; muzzle/tracer/casing presentation never awards hits.
const TRACERS := 8
const CASINGS := 16
const RINGS := 6
const RING_LIFETIME := 0.2
## Barrel heat for smoke: each shot adds heat, which cools over a few seconds.
const SHOT_HEAT := 0.07
const COOLING := 0.35
var rotor: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var light: OmniLight3D
var shot_count := 0
var gun_mount: Node3D
var weapon_audio: MinigunWeaponAudio
var _mount_rest := Transform3D.IDENTITY
var _seen := -1
var _tick := -1
var _scale := 1.0
var _flash_age := 1.0
var _tracers: Array[Dictionary] = []
var _casings: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _ring_serial := 0
var smoke: GPUParticles3D
var barrel_heat := 0.0
var _since_shot := 10.0
## Authoritative projectile spawn: ScorpionGeometry muzzle plus the body gun offset,
## applied to the current visual pose so effects start at the barrel end.
var _hull_size := Vector3.ZERO
var _gun_offset := Vector3.ZERO

func configure(barrels: Node3D, socket: Node3D, geometry_scale: float, mount: Node3D = null) -> void:
	rotor = barrels
	muzzle = socket
	_scale = geometry_scale
	gun_mount = mount
	if gun_mount != null: _mount_rest = gun_mount.transform
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.75, 0.25)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.45, 0.055)
	hot.emission_energy_multiplier = 7.0
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("bf9342")
	brass.metallic = 0.85
	brass.roughness = 0.26
	for index: int in TRACERS:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.009 * _scale
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 1.0
		mesh.radial_segments = 6
		var node := _mesh(mesh, hot)
		_tracers.append({"node":node, "age":1.0})
	for index: int in CASINGS:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.012 * _scale
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.052 * _scale
		mesh.radial_segments = 8
		var node := _mesh(mesh, brass)
		_casings.append({"node":node, "age":2.0, "velocity":Vector3.ZERO, "spin":Vector3.ZERO})
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.08 * _scale
	cone.height = 0.4 * _scale
	cone.radial_segments = 7
	flash = _mesh(cone, hot)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.52, 0.14)
	light.omni_range = 2.8 * _scale
	light.light_energy = 0.0
	add_child(light)
	light.top_level = true
	weapon_audio = MinigunWeaponAudio.new()
	add_child(weapon_audio)
	var ring_mesh := QuadMesh.new()
	ring_mesh.size = Vector2.ONE
	ring_mesh.orientation = PlaneMesh.FACE_Y
	var ring_material := ShaderMaterial.new()
	ring_material.shader = preload("res://scripts/presentation/impact_shockwave.gdshader")
	ring_mesh.material = ring_material
	for index: int in RINGS:
		var ring := MeshInstance3D.new()
		ring.name = "MuzzleRing" + str(index)
		ring.mesh = ring_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.top_level = true
		ring.hide()
		_rings.append({"node":ring, "age":1.0, "origin":Transform3D.IDENTITY, "reach":0.7})
	smoke = _barrel_smoke()

func set_shot_geometry(hull_size: Vector3, gun_offset: Vector3) -> void:
	_hull_size = hull_size
	_gun_offset = gun_offset

## Where the projectile leaves the barrel now. Snapshot origins trail a moving
## bot and fall back to the breech at point-blank range.
func shot_origin(pose: Transform3D, pitch: float, fallback: Vector3) -> Vector3:
	if _hull_size == Vector3.ZERO or not pose.is_finite() or not is_finite(pitch): return fallback
	return pose * (ScorpionGeometry.gun_muzzle(_hull_size, pitch) + _gun_offset)

func _mesh(shape: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = true
	node.hide()
	return node

func show_state(view: BotView, delta: float, primary := false) -> void:
	if gun_mount != null:
		var rotation := Basis(Vector3.RIGHT, view.gun_pitch)
		var pivot := ScorpionGeometry.GUN_PIVOT
		gun_mount.transform = Transform3D(rotation, pivot - rotation * pivot) * _mount_rest
	var spool := view.weapon_charge_fraction if primary else view.secondary_charge
	if is_instance_valid(rotor) and not view.eliminated:
		rotor.rotate_z(-delta * spool * 65.0)
	var baseline := _seen < 0 or view.server_tick < _tick or view.shot_sequence < _seen
	if baseline: clear_effects()
	var motor_origin := gun_mount.global_position if gun_mount != null else muzzle.global_position
	weapon_audio.observe(view, spool, motor_origin, delta)
	if baseline:
		_seen = view.shot_sequence
	elif view.shot_sequence > _seen:
		_seen = view.shot_sequence
		if not view.eliminated and view.last_shot_tick >= 0 and view.last_shot_tick <= view.server_tick \
			and view.server_tick - view.last_shot_tick <= 12:
			_fire(shot_origin(view.pose, view.gun_pitch, view.last_shot_from), view.last_shot_to, view.pose, view.last_shot_from)
	_tick = view.server_tick
	if view.eliminated: clear_effects()
	_flash_age += delta
	_advance_rings(delta)
	_advance_smoke(delta, view.eliminated)
	flash.visible = _flash_age < 0.045
	light.light_energy = maxf(0.0, 1.0 - _flash_age / 0.045) * 3.5
	for tracer: Dictionary in _tracers:
		tracer.age += delta
		tracer.node.visible = tracer.age < 0.065
	for casing: Dictionary in _casings:
		casing.age += delta
		casing.node.visible = casing.age < 0.75
		if casing.node.visible:
			casing.velocity.y -= 9.8 * delta
			casing.node.global_position += Vector3(casing.velocity) * delta
			casing.node.rotation += Vector3(casing.spin) * delta

## `from` is the visual barrel end; audio stays on the accepted report origin.
func _fire(from: Vector3, to: Vector3, pose: Transform3D, report_from: Vector3) -> void:
	var direction := to - from
	if direction.length_squared() < 0.0001: return
	var distance := direction.length()
	direction /= distance
	var right := direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	var frame := Basis(right, direction, right.cross(direction))
	var tracer: Dictionary = _tracers[shot_count % TRACERS]
	tracer.age = 0.0
	tracer.node.global_transform = Transform3D(frame.scaled_local(Vector3(1, distance, 1)), (from + to) * 0.5)
	flash.global_transform = Transform3D(frame, from + direction * 0.12 * _scale)
	light.global_position = from
	_flash_age = 0.0
	_spawn_ring(from, frame, 0.9, 0.7)
	barrel_heat = minf(1.0, barrel_heat + SHOT_HEAT)
	_since_shot = 0.0
	var casing: Dictionary = _casings[shot_count % CASINGS]
	casing.age = 0.0
	casing.node.global_transform = Transform3D(pose.basis, from + pose.basis.z * 0.45 * _scale)
	casing.velocity = (pose.basis.x * 1.3 + Vector3.UP * 0.8) * _scale
	casing.spin = Vector3(9, 15, 4)
	shot_count += 1
	weapon_audio.fire(report_from)

func clear_effects() -> void:
	if weapon_audio != null: weapon_audio.reset()
	_flash_age = 1.0
	for tracer: Dictionary in _tracers: tracer.age = 1.0
	for casing: Dictionary in _casings: casing.age = 2.0
	if is_instance_valid(flash): flash.hide()
	if is_instance_valid(light): light.light_energy = 0.0
	for ring: Dictionary in _rings:
		ring.age = 1.0
		if is_instance_valid(ring.node): ring.node.hide()
	barrel_heat = 0.0
	_since_shot = 10.0
	if is_instance_valid(smoke):
		smoke.emitting = false
		smoke.restart()
		smoke.emitting = false

func ring_count() -> int:
	var count := 0
	for ring: Dictionary in _rings:
		if ring.age < RING_LIFETIME: count += 1
	return count

## Pressure ring across the barrel axis (frame.y is the shot direction).
func _spawn_ring(origin: Vector3, frame: Basis, reach: float, strength: float) -> void:
	var ring: Dictionary = _rings[_ring_serial % RINGS]
	_ring_serial += 1
	ring.age = 0.0
	ring.reach = reach
	ring.origin = Transform3D(frame, origin)
	var node: MeshInstance3D = ring.node
	node.set_instance_shader_parameter(&"strength", strength)
	node.set_instance_shader_parameter(&"progress", 0.0)
	node.global_transform = ring.origin.scaled_local(Vector3.ONE * 0.05 * _scale)
	node.show()

func _advance_rings(delta: float) -> void:
	for ring: Dictionary in _rings:
		if ring.age >= RING_LIFETIME: continue
		ring.age += delta
		var node: MeshInstance3D = ring.node
		if ring.age >= RING_LIFETIME:
			node.hide()
			continue
		var progress: float = ring.age / RING_LIFETIME
		node.set_instance_shader_parameter(&"progress", progress)
		node.global_transform = (ring.origin as Transform3D).scaled_local(Vector3.ONE * lerpf(0.12, float(ring.reach), progress) * _scale)

## Thin smoke from the barrel tip; it thickens once the trigger is released.
func _advance_smoke(delta: float, eliminated: bool) -> void:
	_since_shot += delta
	barrel_heat = maxf(0.0, barrel_heat - COOLING * delta * (0.4 if _since_shot < 0.2 else 1.0))
	if not is_instance_valid(smoke) or not is_instance_valid(muzzle): return
	smoke.global_position = muzzle.global_position
	var after_fire := 1.0 if _since_shot > 0.15 else 0.35
	smoke.amount_ratio = clampf(barrel_heat * after_fire * 1.4, 0.0, 1.0)
	smoke.emitting = not eliminated and barrel_heat > 0.04

func _barrel_smoke() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "BarrelSmoke"
	emitter.amount = 48
	emitter.lifetime = 1.6
	emitter.local_coords = false
	emitter.emitting = false
	emitter.fixed_fps = 30
	emitter.interpolate = true
	emitter.visibility_aabb = AABB(Vector3(-3, -1, -3) * _scale, Vector3(6, 6, 6) * _scale)
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.03 * _scale
	motion.direction = Vector3.UP
	motion.spread = 18.0
	motion.initial_velocity_min = 0.08 * _scale
	motion.initial_velocity_max = 0.18 * _scale
	motion.gravity = Vector3(0.02, 0.16, 0.0) * _scale
	motion.damping_min = 0.2
	motion.damping_max = 0.4
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -30.0
	motion.angular_velocity_max = 30.0
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.4
	motion.turbulence_noise_scale = 2.0
	motion.turbulence_influence_min = 0.04
	motion.turbulence_influence_max = 0.1
	motion.scale_min = 0.05 * _scale
	motion.scale_max = 0.09 * _scale
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.2))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	motion.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	fade.colors = PackedColorArray([Color(0.7, 0.7, 0.7, 0.0), Color(0.62, 0.62, 0.62, 0.38),
		Color(0.55, 0.55, 0.56, 0.2), Color(0.5, 0.5, 0.52, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	motion.color_ramp = ramp
	emitter.process_material = motion
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.gradient = falloff
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = soft
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	puff.material = material
	emitter.draw_pass_1 = puff
	add_child(emitter)
	emitter.top_level = true
	return emitter
