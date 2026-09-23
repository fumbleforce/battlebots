class_name ScorpionDieselExhaust
extends Node3D
## Presentation-only engine load. World-space smoke survives movement and shutdown.
const PARTICLES_PER_STACK := 128
const LIFETIME := 3.6
const IDLE_DENSITY := 0.075
const FOG_LIMIT := 16
const FOG_LIFETIME := 1.8
var fog_puffs: Array[Dictionary] = []
var _fog_cursor := 0
var _fog_clock := 0.0
const OUTLETS := ["ExhaustLeft", "ExhaustRight"]
var emitters: Array[GPUParticles3D] = []
var engine_load := 0.0
var emission_density := 0.0
var engine_running := false
var reset_count := 0
var _outlets: Array[Node3D] = []
var _scale := 1.0
var _initialized := false
var _last_pose := Transform3D.IDENTITY
var _last_tick := -1
var _elapsed := 0.0
static var _smoke_material: ShaderMaterial
static var _instances := 0

func _enter_tree() -> void:
	_instances += 1

func _exit_tree() -> void:
	_instances -= 1
	if _instances == 0: _smoke_material = null

func configure(nodes: Dictionary, geometry_scale: float) -> void:
	_scale = geometry_scale
	for outlet_name: String in OUTLETS:
		# The imported open pipe lip is the only emission origin; no duplicate
		# attachment coordinates that can drift away from the authored mesh.
		if not nodes.has(outlet_name): continue
		_outlets.append(nodes[outlet_name])
		var emitter := _make_emitter()
		emitter.name = outlet_name + "Plume"
		add_child(emitter)
		emitter.top_level = true
		emitters.append(emitter)
	reset_observation()

func _make_emitter() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = PARTICLES_PER_STACK
	emitter.amount_ratio = 0.0
	emitter.lifetime = LIFETIME
	emitter.emitting = false
	emitter.local_coords = false
	emitter.fixed_fps = 30
	emitter.interpolate = true
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.visibility_aabb = AABB(Vector3(-5, -2, -5) * _scale, Vector3(10, 9, 10) * _scale)
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.027 * _scale
	motion.direction = Vector3.UP
	motion.spread = 16.0
	motion.initial_velocity_min = 0.44 * _scale
	motion.initial_velocity_max = 0.68 * _scale
	# Buoyancy stays world-up as the chassis pitches over the arena surface.
	motion.gravity = Vector3(0.055, 0.22, 0.025) * _scale
	motion.damping_min = 0.13
	motion.damping_max = 0.22
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -24.0
	motion.angular_velocity_max = 24.0
	motion.scale_min = 0.72 * _scale
	motion.scale_max = 1.0 * _scale
	motion.scale_curve = _curve([Vector2(0, 0.12), Vector2(0.12, 0.39), Vector2(0.5, 0.78), Vector2(1, 1.12)])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.025, 0.18, 0.58, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.94),
		Color(1, 1, 1, 0.86), Color(1, 1, 1, 0.50), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	# A weak curl disrupts overlapping cards without throwing the plume away
	# from its pressure jet. Two bounded systems share the same smoke shader.
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.35
	motion.turbulence_noise_scale = 2.8
	motion.turbulence_influence_min = 0.025
	motion.turbulence_influence_max = 0.075
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material()
	emitter.draw_pass_1 = quad
	return emitter

static func _curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 1.5
	for point: Vector2 in points: curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture

static func _material() -> ShaderMaterial:
	if _smoke_material != null: return _smoke_material
	_smoke_material = ShaderMaterial.new()
	_smoke_material.shader = preload("res://scripts/presentation/scorpion_diesel_smoke.gdshader")
	var noise := FastNoiseLite.new()
	noise.seed = 76341
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.027
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	_smoke_material.set_shader_parameter("smoke_noise", texture)
	return _smoke_material

func show_state(view: BotView, pose: Transform3D, delta: float, runtime: bool) -> void:
	if not runtime:
		if _initialized or engine_running: reset_observation()
		return
	if delta <= 0.0: return
	var discontinuity := _initialized and (pose.origin.distance_to(_last_pose.origin) > 1.5 * _scale
		or delta > 0.35 or (view.server_tick >= 0 and view.server_tick < _last_tick))
	if discontinuity: reset_observation()
	var target_load := 0.0
	if _initialized and not view.eliminated:
		var travel := pose.origin - _last_pose.origin
		travel.y = 0.0
		var old_forward := -_last_pose.basis.z
		var forward := -pose.basis.z
		old_forward.y = 0.0
		forward.y = 0.0
		var turn_rate := 0.0
		if old_forward.length_squared() > 0.01 and forward.length_squared() > 0.01:
			turn_rate = absf(old_forward.signed_angle_to(forward, Vector3.UP)) / delta
		target_load = clampf(travel.length() / delta / (1.15 * _scale) + turn_rate * 0.36, 0.0, 1.0)
	_initialized = true
	_last_pose = pose
	_last_tick = view.server_tick
	_elapsed += minf(delta, 0.1)
	engine_running = not view.eliminated
	engine_load = lerpf(engine_load, target_load, 1.0 - exp(-delta * (5.0 if target_load > engine_load else 1.45)))
	emission_density = lerpf(IDLE_DENSITY, 1.0, smoothstep(0.02, 0.80, engine_load)) if engine_running else 0.0
	_fog_clock += minf(delta,0.1)
	var deposit := engine_running and engine_load > 0.22 and _fog_clock >= 0.32
	if deposit: _fog_clock = 0.0
	for index: int in emitters.size():
		var emitter := emitters[index]
		var outlet := _outlets[index]
		# Top-level unit basis prevents parent scale from being applied twice.
		emitter.global_transform = Transform3D(Basis.IDENTITY, outlet.global_position)
		var motion := emitter.process_material as ParticleProcessMaterial
		motion.direction = outlet.global_basis.y.normalized()
		motion.initial_velocity_min = lerpf(0.29, 0.47, engine_load) * _scale
		motion.initial_velocity_max = lerpf(0.42, 0.72, engine_load) * _scale
		var pulse := 0.80 + 0.20 * sin(_elapsed * lerpf(32.0, 51.0, engine_load) + index * PI)
		emitter.amount_ratio = emission_density * pulse
		emitter.emitting = engine_running
		if deposit: _deposit_fog(outlet.global_position, motion.direction)

# Lit volume cores complement the detailed soft particles. Both use world-space
# history; local fog can be disabled by GraphicsRuntime without hiding particles.
func _deposit_fog(at: Vector3, direction: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus": return
	var puff: Dictionary
	if fog_puffs.size() < FOG_LIMIT:
		var volume := FogVolume.new()
		volume.name = "DieselVolume%d" % fog_puffs.size()
		volume.top_level = true
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/presentation/scorpion_exhaust_fog.gdshader")
		volume.material = material
		add_child(volume)
		puff = {"volume":volume,"age":0.0,"origin":at,"direction":direction,"load":engine_load}
		fog_puffs.append(puff)
	else:
		puff = fog_puffs[_fog_cursor]
		_fog_cursor = (_fog_cursor+1)%FOG_LIMIT
	puff.age = 0.0
	puff.origin = at
	puff.direction = direction
	puff.load = engine_load
	puff.volume.global_position = at
	puff.volume.size = Vector3.ONE*.2*_scale
	puff.volume.visible = true
	puff.volume.material.set_shader_parameter("density",0.0)

func _process(delta: float) -> void:
	_update_fog(delta)

func _update_fog(delta: float) -> void:
	for puff: Dictionary in fog_puffs:
		puff.age += delta
		if puff.age >= FOG_LIFETIME:
			puff.volume.hide()
			continue
		var age: float = puff.age
		var expansion := (.2+age*.3)*_scale
		puff.volume.size = Vector3(expansion,expansion*1.3,expansion)
		puff.volume.global_position = puff.origin+puff.direction*age*.42*_scale+Vector3(.0275,.11,.0125)*age*age*_scale
		var fade := smoothstep(0.0,.15,age)*(1.0-smoothstep(.3,FOG_LIFETIME,age))
		puff.volume.material.set_shader_parameter("density",.22*puff.load*fade)
		puff.volume.material.set_shader_parameter("age",age)

## Explicit round reset also handles respawning at exactly the previous pose.
## Elimination deliberately does not call this: its old plume should dissipate.
func reset_observation() -> void:
	engine_load = 0.0
	emission_density = 0.0
	engine_running = false
	_initialized = false
	_last_tick = -1
	_elapsed = 0.0
	reset_count += 1
	_fog_clock = 0.0
	for puff: Dictionary in fog_puffs:
		puff.age = FOG_LIFETIME
		puff.volume.hide()
	for emitter: GPUParticles3D in emitters:
		emitter.emitting = false
		emitter.amount_ratio = 0.0
		emitter.restart()
		emitter.emitting = false
