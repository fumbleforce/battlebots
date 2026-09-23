class_name CombatImpactVisual
extends Node3D
## Disposable confirmed-contact decoration. No collision, gameplay state or event inference.
const MAX_SPARKS := 64
const MAX_FRAGMENTS := 20
const MAX_BURSTS := 10
const MAX_SHOCKWAVES := 4
const BURST_LIFETIME := 1.2
const SHOCKWAVE_LIFETIME := 0.85
const RING_DURATION := 0.5
## One hammer swing makes one ring. A ground slam waits briefly so a late bot-hit
## event from the same swing can claim the ring on the struck bot instead.
const ONE_RING_WINDOW := 0.8
const SLAM_GRACE := 0.15
const KINDS := ["vertical_spinner", "horizontal_spinner", "saw", "hammer", "lifter", "ram"]
const GOLDEN_ANGLE := 2.39996323
var _sparks: Array[Dictionary] = []
var _fragments: Array[Dictionary] = []
var _serial := 0
var _spark_mesh: BoxMesh
var _fragment_mesh: BoxMesh
## Pooled GPU spark showers and hammer rings live under one container so the
## box spark/fragment pools keep their own bounded child budget.
var _burst_root: Node3D
var _bursts: Array[Dictionary] = []
var _shockwaves: Array[Dictionary] = []
var _clock := 0.0
var _ring_times: Dictionary = {}
var _pending_slams: Array[Dictionary] = []
static var _spark_process: ParticleProcessMaterial
static var _dust_process: ParticleProcessMaterial
static var _streak_mesh: BoxMesh
static var _puff_mesh: QuadMesh
static var _ring_mesh: QuadMesh
static var _instances := 0

func _enter_tree() -> void:
	_instances += 1

func _exit_tree() -> void:
	_instances -= 1
	if _instances == 0:
		_spark_process = null
		_dust_process = null
		_streak_mesh = null
		_puff_mesh = null
		_ring_mesh = null

func _ready() -> void:
	add_to_group(&"combat_impact_visuals")
	_burst_root = Node3D.new()
	_burst_root.name = "Bursts"
	add_child(_burst_root)

## `source` is the attacking entity id (0 = unknown, never deduplicated).
func spawn_impact(position: Vector3, normal: Vector3, kind: String, damage: float, source := 0) -> void:
	if not position.is_finite() or not normal.is_finite() or not is_finite(damage) or damage < 0 or kind not in KINDS:
		return
	# Scale before normalization so finite, unusually large normals cannot overflow.
	var extent := maxf(absf(normal.x), maxf(absf(normal.y), absf(normal.z)))
	var outward := (normal / extent).normalized() if extent > 0.000001 else Vector3.UP
	var tangent := outward.cross(Vector3.UP if absf(outward.y) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent := outward.cross(tangent)
	var spark_total := 6 + int(ceil(minf(damage, 50.0) * 0.2))
	var fragment_total := clampi(int(ceil(minf(damage, 40.0) / 8.0)), 1, 5) if damage > 0 else 0
	for index: int in spark_total:
		_emit(_sparks, MAX_SPARKS, false, position, outward, tangent, bitangent, index, spark_total)
	for index: int in fragment_total:
		_emit(_fragments, MAX_FRAGMENTS, true, position, outward, tangent, bitangent, index, fragment_total)
	trim_fragments()
	var frame := Basis(tangent, outward, tangent.cross(outward)).orthonormalized()
	_spawn_burst(position, frame, kind, damage)
	if kind == "hammer" and _claim_ring(source):
		# Event normals point away from the victim centre; lay the ring on the
		# actual struck face instead.
		var surface := _struck_surface(position, outward)
		_spawn_shockwave(surface.position, _frame_for(surface.normal), damage)

## Hammer head met the arena floor (or another world surface) with no bot hit.
## Presentation only: no damage, no event and no network traffic.
func spawn_ground_slam(position: Vector3, normal: Vector3, strength := 0.8, source := 0) -> void:
	if not position.is_finite() or not normal.is_finite() or not is_finite(strength) or strength <= 0.0: return
	if source > 0:
		if _rang_recently(source): return
		for pending: Dictionary in _pending_slams:
			if pending.source == source: return
		_pending_slams.append({"source":source, "position":position, "normal":normal,
			"strength":strength, "due":_clock + SLAM_GRACE})
		return
	_slam_now(position, normal, strength)

func pending_slam_count() -> int:
	return _pending_slams.size()

func _rang_recently(source: int) -> bool:
	return source > 0 and _ring_times.has(source) and _clock - float(_ring_times[source]) < ONE_RING_WINDOW

## True when this attacker may show a ring now; records it and drops its pending slam.
func _claim_ring(source: int) -> bool:
	if source <= 0: return true
	if _rang_recently(source): return false
	_ring_times[source] = _clock
	_pending_slams = _pending_slams.filter(func(pending: Dictionary) -> bool: return pending.source != source)
	return true

func _slam_now(position: Vector3, normal: Vector3, strength: float) -> void:
	var up := normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
	var frame := _frame_for(up)
	var damage := clampf(strength, 0.0, 1.0) * 45.0
	_spawn_burst(position, frame, "hammer", damage)
	_spawn_shockwave(position, frame, damage)

static func _frame_for(normal: Vector3) -> Basis:
	var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(tangent, normal, tangent.cross(normal)).orthonormalized()

## Short read-only ray through the reported contact to find the real face normal.
func _struck_surface(position: Vector3, outward: Vector3) -> Dictionary:
	var result := {"position":position, "normal":outward}
	if not is_inside_tree(): return result
	var space := get_world_3d().direct_space_state
	if space == null: return result
	var ray := PhysicsRayQueryParameters3D.create(position + outward * 0.8, position - outward * 0.8,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or not (hit.normal as Vector3).is_finite() or (hit.position as Vector3).distance_to(position) > 0.9:
		return result
	result.position = hit.position
	result.normal = (hit.normal as Vector3).normalized()
	return result

func trim_fragments() -> void:
	# Destruction panels share the existing twenty-piece client debris budget.
	var budget := MAX_FRAGMENTS
	for effect: Node in get_tree().get_nodes_in_group(&"bot_destruction_visuals"):
		if effect.active and effect.effect_age < 2.1: budget -= 8
	for particle: Dictionary in _fragments:
		if not particle.active: continue
		if budget > 0:
			budget -= 1
		else:
			particle.active = false
			particle.mesh.hide()

func spark_count() -> int:
	return _active_count(_sparks)

func fragment_count() -> int:
	return _active_count(_fragments)

func burst_count() -> int:
	return _active_count(_bursts)

func shockwave_count() -> int:
	return _active_count(_shockwaves)

func _active_count(pool: Array[Dictionary]) -> int:
	var count := 0
	for particle: Dictionary in pool:
		if particle.active: count += 1
	return count

func clear_effects() -> void:
	for pool: Array[Dictionary] in [_sparks, _fragments]:
		for particle: Dictionary in pool:
			particle.active = false
			particle.mesh.hide()
	for burst: Dictionary in _bursts: _retire_burst(burst)
	for wave: Dictionary in _shockwaves: _retire_shockwave(wave)
	_pending_slams.clear()
	_ring_times.clear()

func _acquire(pool: Array[Dictionary], capacity: int, fragment: bool) -> Dictionary:
	for particle: Dictionary in pool:
		if not particle.active: return particle
	if pool.size() < capacity:
		var node := MeshInstance3D.new()
		node.name = ("Fragment" if fragment else "Spark") + str(pool.size())
		node.mesh = _shared_mesh(fragment)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.top_level = true
		var particle := {"mesh": node, "active": false, "age": 0.0, "lifetime": 0.0,
			"origin": Vector3.ZERO, "velocity": Vector3.ZERO, "spin": Vector3.ZERO,
			"basis": Basis.IDENTITY, "serial": 0, "fragment": fragment}
		pool.append(particle)
		return particle
	var oldest: Dictionary = pool[0]
	for particle: Dictionary in pool:
		if particle.serial < oldest.serial: oldest = particle
	return oldest

func _emit(pool: Array[Dictionary], capacity: int, fragment: bool, origin: Vector3,
		outward: Vector3, tangent: Vector3, bitangent: Vector3, index: int, total: int) -> void:
	var particle := _acquire(pool, capacity, fragment)
	var phase := float(index) * GOLDEN_ANGLE
	var spread := 0.25 + 0.6 * float(index + 1) / float(total)
	var direction := (outward + (tangent * cos(phase) + bitangent * sin(phase)) * spread).normalized()
	_serial += 1
	particle.serial = _serial
	particle.active = true
	particle.age = 0.0
	particle.lifetime = (0.95 + float(index % 3) * 0.2) if fragment else (0.28 + float(index % 4) * 0.06)
	particle.origin = origin
	particle.velocity = direction * ((0.9 + float(index % 3) * 0.3) if fragment else (2.2 + float(index % 4) * 0.35))
	particle.spin = Vector3(3.0 + index, 2.0, 1.5) if fragment else Vector3.ZERO
	particle.basis = Basis.looking_at(direction, tangent)
	particle.mesh.global_transform = Transform3D(particle.basis, origin)
	particle.mesh.show()

func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	_clock += delta
	_release_slams()
	_advance_bursts(delta)
	for pool: Array[Dictionary] in [_sparks, _fragments]:
		for particle: Dictionary in pool:
			if not particle.active: continue
			particle.age += delta
			if particle.age >= particle.lifetime:
				particle.active = false
				particle.mesh.hide()
				continue
			var age: float = particle.age
			var gravity := Vector3.DOWN * (3.5 if particle.fragment else 1.8)
			var at: Vector3 = particle.origin + particle.velocity * age + gravity * (0.5 * age * age)
			var rotation: Basis = particle.basis * Basis.from_euler(particle.spin * age)
			# Shrink only near expiry; opaque tiny meshes avoid blended screen flashes.
			var shrink := minf(1.0, (particle.lifetime - age) / 0.15)
			particle.mesh.global_transform = Transform3D(rotation.scaled(Vector3.ONE * shrink), at)

func _shared_mesh(fragment: bool) -> BoxMesh:
	if fragment and _fragment_mesh != null: return _fragment_mesh
	if not fragment and _spark_mesh != null: return _spark_mesh
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.065, 0.035, 0.08) if fragment else Vector3(0.035, 0.035, 0.18)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.4, 0.43) if fragment else Color(1.0, 0.85, 0.4)
	material.metallic = 0.65 if fragment else 0.0
	material.roughness = 0.7
	if not fragment:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	if fragment: _fragment_mesh = mesh
	else: _spark_mesh = mesh
	return mesh

## Hot streak shower for every confirmed hit. Heavier hits throw more, faster
## sparks and a brief contact flash; grinding saws skew toward dense showers.
func _spawn_burst(origin: Vector3, frame: Basis, kind: String, damage: float) -> void:
	var burst := _oldest_or_new(_bursts, MAX_BURSTS, _make_burst)
	var weight := clampf(0.6 + minf(damage, 60.0) / 50.0, 0.6, 1.0)
	if kind in ["saw", "horizontal_spinner", "vertical_spinner", "hammer"]: weight = minf(1.0, weight + 0.25)
	_serial += 1
	burst.serial = _serial
	burst.active = true
	burst.age = 0.0
	burst.weight = weight
	var sparks: GPUParticles3D = burst.sparks
	sparks.global_transform = Transform3D(frame, origin)
	sparks.amount_ratio = weight
	sparks.speed_scale = 0.85 + weight * 0.3
	sparks.show()
	sparks.restart()
	var flash: OmniLight3D = burst.flash
	flash.global_position = origin + frame.y * 0.12
	flash.light_energy = 3.2 * weight
	flash.show()

func _spawn_shockwave(origin: Vector3, frame: Basis, damage: float) -> void:
	var wave := _oldest_or_new(_shockwaves, MAX_SHOCKWAVES, _make_shockwave)
	var strength := clampf(0.55 + minf(damage, 60.0) / 60.0, 0.55, 1.0)
	_serial += 1
	wave.serial = _serial
	wave.active = true
	wave.age = 0.0
	wave.strength = strength
	wave.radius = lerpf(2.6, 4.4, strength)
	# The ring lies across the struck surface; lift it clear to avoid z-fighting.
	wave.origin = Transform3D(frame, origin + frame.y * 0.04)
	var ring: MeshInstance3D = wave.ring
	ring.global_transform = wave.origin.scaled_local(Vector3.ONE * 0.1)
	ring.set_instance_shader_parameter(&"progress", 0.0)
	ring.set_instance_shader_parameter(&"strength", strength)
	ring.show()
	var dust: GPUParticles3D = wave.dust
	dust.global_transform = wave.origin
	dust.amount_ratio = strength
	dust.show()
	dust.restart()
	# Cameras apply their own distance falloff; distant observers just see the ring.
	get_tree().call_group(&"bot_orbit_cameras", &"add_impact_shake", origin, strength)

func _release_slams() -> void:
	var due: Array[Dictionary] = []
	for pending: Dictionary in _pending_slams:
		if _clock >= pending.due: due.append(pending)
	for pending: Dictionary in due:
		_pending_slams.erase(pending)
		if _claim_ring(pending.source): _slam_now(pending.position, pending.normal, pending.strength)

func _advance_bursts(delta: float) -> void:
	for burst: Dictionary in _bursts:
		if not burst.active: continue
		burst.age += delta
		if burst.age >= BURST_LIFETIME:
			_retire_burst(burst)
			continue
		var flash: OmniLight3D = burst.flash
		flash.light_energy = 3.2 * burst.weight * maxf(0.0, 1.0 - burst.age / 0.14)
		flash.visible = flash.light_energy > 0.01
	for wave: Dictionary in _shockwaves:
		if not wave.active: continue
		wave.age += delta
		if wave.age >= SHOCKWAVE_LIFETIME:
			_retire_shockwave(wave)
			continue
		var ring: MeshInstance3D = wave.ring
		ring.visible = wave.age < RING_DURATION
		if not ring.visible: continue
		ring.global_transform = wave.origin.scaled_local(Vector3.ONE * wave.radius * 2.0)
		ring.set_instance_shader_parameter(&"progress", wave.age / RING_DURATION)

## Hiding also removes in-flight particles from view on round/phase resets;
## the next restart() clears them before reuse.
func _retire_burst(burst: Dictionary) -> void:
	burst.active = false
	burst.sparks.emitting = false
	burst.sparks.hide()
	burst.flash.hide()

func _retire_shockwave(wave: Dictionary) -> void:
	wave.active = false
	wave.ring.hide()
	wave.dust.emitting = false
	wave.dust.hide()

func _oldest_or_new(pool: Array[Dictionary], capacity: int, factory: Callable) -> Dictionary:
	for entry: Dictionary in pool:
		if not entry.active: return entry
	if pool.size() < capacity:
		var created: Dictionary = factory.call(pool.size())
		pool.append(created)
		return created
	var oldest: Dictionary = pool[0]
	for entry: Dictionary in pool:
		if entry.serial < oldest.serial: oldest = entry
	return oldest

func _make_burst(index: int) -> Dictionary:
	var sparks := _one_shot_emitter("SparkBurst" + str(index), 240, 0.85, _spark_material(), _streak())
	var flash := OmniLight3D.new()
	flash.name = "SparkFlash" + str(index)
	flash.light_color = Color(1.0, 0.7, 0.38)
	flash.omni_range = 2.6
	flash.shadow_enabled = false
	flash.hide()
	_burst_root.add_child(flash)
	flash.top_level = true
	return {"sparks":sparks, "flash":flash, "active":false, "age":0.0, "weight":0.0, "serial":0}

func _make_shockwave(index: int) -> Dictionary:
	var ring := MeshInstance3D.new()
	ring.name = "Shockwave" + str(index)
	ring.mesh = _ring()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.hide()
	_burst_root.add_child(ring)
	ring.top_level = true
	var dust := _one_shot_emitter("ShockDust" + str(index), 40, 0.75, _dust_material(), _puff())
	dust.explosiveness = 1.0
	return {"ring":ring, "dust":dust, "active":false, "age":0.0, "strength":0.0,
		"radius":1.0, "origin":Transform3D.IDENTITY, "serial":0}

func _one_shot_emitter(label: String, amount: int, lifetime: float,
		motion: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = label
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 0.92
	emitter.randomness = 0.4
	emitter.emitting = false
	emitter.visible = false
	emitter.local_coords = false
	emitter.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 7, 12))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.process_material = motion
	emitter.draw_pass_1 = mesh
	_burst_root.add_child(emitter)
	emitter.top_level = true
	return emitter

static func _spark_material() -> ParticleProcessMaterial:
	if _spark_process != null: return _spark_process
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.12
	# Local Y is the struck surface's outward normal.
	motion.direction = Vector3.UP
	motion.spread = 80.0
	motion.initial_velocity_min = 3.0
	motion.initial_velocity_max = 14.0
	motion.gravity = Vector3(0, -11.0, 0)
	motion.damping_min = 1.0
	motion.damping_max = 3.0
	motion.particle_flag_align_y = true
	motion.scale_min = 0.55
	motion.scale_max = 1.25
	motion.scale_curve = _curve([Vector2(0, 1), Vector2(0.7, 0.8), Vector2(1, 0)])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(4.0, 3.4, 2.4), Color(3.4, 1.9, 0.6),
		Color(2.0, 0.7, 0.15), Color(0.6, 0.12, 0.03)])
	var ramp := GradientTexture1D.new()
	ramp.use_hdr = true
	ramp.gradient = gradient
	motion.color_ramp = ramp
	_spark_process = motion
	return motion

static func _dust_material() -> ParticleProcessMaterial:
	if _dust_process != null: return _dust_process
	var motion := ParticleProcessMaterial.new()
	# A flat ring blown outward along the struck surface reads as the blast front.
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = 0.35
	motion.emission_ring_inner_radius = 0.2
	motion.emission_ring_height = 0.05
	motion.direction = Vector3.UP
	motion.spread = 12.0
	motion.initial_velocity_min = 0.2
	motion.initial_velocity_max = 0.7
	motion.radial_velocity_min = 10.0
	motion.radial_velocity_max = 13.0
	motion.damping_min = 11.0
	motion.damping_max = 14.0
	motion.gravity = Vector3(0, 0.25, 0)
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.scale_min = 0.8
	motion.scale_max = 1.3
	motion.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.35, 0.8), Vector2(1, 1.0)])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.1, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color(0.62, 0.56, 0.48, 0.0), Color(0.62, 0.56, 0.48, 0.34),
		Color(0.55, 0.51, 0.46, 0.2), Color(0.5, 0.48, 0.45, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	_dust_process = motion
	return motion

static func _streak() -> BoxMesh:
	if _streak_mesh != null: return _streak_mesh
	_streak_mesh = BoxMesh.new()
	# Long along Y, which align_y points down the spark's velocity.
	_streak_mesh.size = Vector3(0.028, 0.3, 0.028)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	_streak_mesh.material = material
	return _streak_mesh

static func _puff() -> QuadMesh:
	if _puff_mesh != null: return _puff_mesh
	_puff_mesh = QuadMesh.new()
	_puff_mesh.size = Vector2.ONE * 0.9
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
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
	_puff_mesh.material = material
	return _puff_mesh

static func _ring() -> QuadMesh:
	if _ring_mesh != null: return _ring_mesh
	_ring_mesh = QuadMesh.new()
	_ring_mesh.size = Vector2.ONE
	_ring_mesh.orientation = PlaneMesh.FACE_Y
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/impact_shockwave.gdshader")
	_ring_mesh.material = material
	return _ring_mesh

static func _curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	for point: Vector2 in points: curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
