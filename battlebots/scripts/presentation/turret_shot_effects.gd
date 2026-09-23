class_name TurretShotEffects
extends Node3D
## Accepted shot snapshots only: recoil, muzzle blast, a travelling shell or
## plasma bolt, a cosmetic arrival burst and procedural reports. Confirmed hit
## sparks and damage come from combat events; nothing here awards a hit.
const PROJECTILES := 6
const BLASTS := 2
const FOG_PUFFS := 6
const FOG_LIFETIME := 2.6
const RATE := 24000
const SPEED := {"cannon":240.0, "plasma":110.0}
## Recoil travel in model (source) metres and its return time.
const RECOIL_TRAVEL := 0.10
const RECOIL_RETURN := 0.45
var kind := ""
var muzzle: Node3D
var recoil: Node3D
var shot_count := 0
var playback_enabled := true
var _scale := 1.0
var _recoil_rest := Transform3D.IDENTITY
var _recoil_age := 1.0
var _seen := -1
var _tick := -1
var _flash: MeshInstance3D
var _flash_age := 1.0
var _light: OmniLight3D
var _projectiles: Array[Dictionary] = []
var _blasts: Array[GPUParticles3D] = []
var _fog: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer3D] = []
static var _streams: Dictionary = {}
static var _smoke_materials: Dictionary = {}

func configure(weapon: String, muzzle_node: Node3D, recoil_node: Node3D, geometry_scale: float) -> void:
	kind = weapon
	muzzle = muzzle_node
	recoil = recoil_node
	_scale = geometry_scale
	if recoil != null: _recoil_rest = recoil.transform
	var cannon := kind == "cannon"
	var hot := _glow(Color(1.0, 0.62, 0.22) if cannon else Color(0.35, 0.85, 1.0), 6.0 if cannon else 9.0)
	var core := _glow(Color(1.0, 0.9, 0.7) if cannon else Color(0.85, 0.97, 1.0), 12.0)
	for index: int in PROJECTILES:
		var head := MeshInstance3D.new()
		if cannon:
			var shell := CapsuleMesh.new()
			shell.radius = 0.035 * _scale
			shell.height = 0.32 * _scale
			head.mesh = shell
		else:
			var bolt := SphereMesh.new()
			bolt.radius = 0.07 * _scale
			bolt.height = 0.14 * _scale
			head.mesh = bolt
		head.material_override = core
		var trail := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = (0.012 if cannon else 0.035) * _scale
		cylinder.bottom_radius = cylinder.top_radius * 0.3
		cylinder.height = 1.0
		cylinder.radial_segments = 8
		trail.mesh = cylinder
		trail.material_override = hot
		var burst := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		burst.mesh = sphere
		burst.material_override = _glow(Color(1.0, 0.55, 0.2, 0.7) if cannon else Color(0.4, 0.9, 1.0, 0.7), 4.0)
		for node: MeshInstance3D in [head, trail, burst]: _world(node)
		_projectiles.append({"head":head, "trail":trail, "burst":burst, "from":Vector3.ZERO,
			"to":Vector3.ZERO, "age":10.0, "flight":0.0})
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = (0.16 if cannon else 0.10) * _scale
	cone.height = (0.75 if cannon else 0.30) * _scale
	cone.radial_segments = 9
	_flash = MeshInstance3D.new()
	_flash.mesh = cone
	_flash.material_override = hot
	_world(_flash)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25) if cannon else Color(0.35, 0.8, 1.0)
	_light.omni_range = (4.5 if cannon else 3.0) * _scale
	_light.light_energy = 0.0
	add_child(_light)
	_light.top_level = true
	# Lit, depth-softened billowing cards (the #31 plume technique) in a
	# pooled one-shot burst per shot, plus volumetric fog cores on Forward+.
	for index: int in BLASTS:
		var blast := _make_blast(cannon)
		blast.name = "MuzzleSmoke%d" % index
		add_child(blast)
		blast.top_level = true
		_blasts.append(blast)
	add_to_group(&"bot_action_audio")
	AudioPreferences.ensure_buses()
	var stream := _report(kind)
	for index: int in 3:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "TurretReport%d" % index
		voice.stream = stream
		voice.bus = &"BBEffects"
		voice.volume_db = -3.0 if cannon else -8.0
		voice.unit_size = 10.0 if cannon else 6.0
		voice.max_distance = 140.0 if cannon else 90.0
		add_child(voice)
		voice.top_level = true
		_voices.append(voice)

func _make_blast(cannon: bool) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = 40 if cannon else 12
	emitter.lifetime = 2.6 if cannon else 1.1
	emitter.one_shot = true
	emitter.explosiveness = 0.92
	emitter.emitting = false
	emitter.local_coords = false
	emitter.fixed_fps = 30
	emitter.interpolate = true
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-4, -2, -6) * _scale, Vector3(8, 6, 8) * _scale)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.12 * _scale
	# Local -Z is the barrel: a forward jet plus the brake's sideways vents.
	motion.direction = Vector3.FORWARD
	motion.spread = 70.0 if cannon else 25.0
	motion.initial_velocity_min = (0.8 if cannon else 0.5) * _scale
	motion.initial_velocity_max = (3.2 if cannon else 1.4) * _scale
	motion.damping_min = 2.0
	motion.damping_max = 3.5
	motion.gravity = Vector3(0.05, 0.16, 0.0) * _scale
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -30.0
	motion.angular_velocity_max = 30.0
	motion.scale_min = (0.9 if cannon else 0.3) * _scale
	motion.scale_max = (1.4 if cannon else 0.5) * _scale
	motion.scale_curve = _curve([Vector2(0, 0.25), Vector2(0.15, 0.7), Vector2(0.6, 1.1), Vector2(1, 1.45)])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.04, 0.3, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.6
	motion.turbulence_noise_scale = 2.0
	motion.turbulence_influence_min = 0.03
	motion.turbulence_influence_max = 0.09
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _smoke_material(cannon)
	emitter.draw_pass_1 = quad
	return emitter

static func _curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 1.5
	for point: Vector2 in points: curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture

static func _smoke_material(cannon: bool) -> ShaderMaterial:
	if _smoke_materials.has(cannon): return _smoke_materials[cannon]
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/turret_blast_smoke.gdshader")
	var noise := FastNoiseLite.new()
	noise.seed = 36036
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.027
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	material.set_shader_parameter("smoke_noise", texture)
	if not cannon:
		# Plasma leaves thin ionised vapour, not propellant smoke.
		material.set_shader_parameter("shadow_color", Color(0.32, 0.42, 0.48))
		material.set_shader_parameter("lit_color", Color(0.62, 0.78, 0.86))
		material.set_shader_parameter("opacity", 0.45)
	_smoke_materials[cannon] = material
	return material

func _deposit_fog(at: Vector3, direction: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus": return
	for step: int in 3:
		var puff: Dictionary
		if _fog.size() < FOG_PUFFS:
			var volume := FogVolume.new()
			volume.name = "MuzzleFog%d" % _fog.size()
			var material := ShaderMaterial.new()
			material.shader = preload("res://scripts/presentation/turret_blast_fog.gdshader")
			volume.material = material
			add_child(volume)
			volume.top_level = true
			puff = {"volume":volume, "age":FOG_LIFETIME, "origin":Vector3.ZERO, "direction":Vector3.ZERO}
			_fog.append(puff)
		else:
			puff = _fog[(shot_count * 3 + step) % FOG_PUFFS]
		puff.age = 0.0
		puff.origin = at + direction * (0.25 + step * 0.45) * _scale
		puff.direction = direction
		puff.volume.visible = true

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r * energy * 0.25, color.g * energy * 0.25, color.b * energy * 0.25, color.a)
	return material

func _world(node: MeshInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = true
	node.hide()

func show_state(view: BotView, delta: float) -> void:
	var baseline := _seen < 0 or view.server_tick < _tick or view.shot_sequence < _seen
	if baseline:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick
	elif view.shot_sequence > _seen:
		_seen = view.shot_sequence
		# One visible shot per accepted snapshot; late/stale records stay silent.
		if not view.eliminated and view.last_shot_tick >= 0 and view.last_shot_tick <= view.server_tick \
			and view.server_tick - view.last_shot_tick <= 12:
			_fire(view.last_shot_from, view.last_shot_to)
	_tick = view.server_tick
	if view.eliminated:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick
	_advance(delta)

func _fire(from: Vector3, to: Vector3) -> void:
	var direction := to - from
	if direction.length_squared() < 0.0001 or not from.is_finite() or not to.is_finite(): return
	var distance := direction.length()
	direction /= distance
	var projectile: Dictionary = _projectiles[shot_count % PROJECTILES]
	projectile.from = from
	projectile.to = to
	projectile.age = 0.0
	projectile.flight = distance / float(SPEED.get(kind, 150.0))
	_flash.global_transform = Transform3D(_frame(direction), from + direction * _flash.mesh.height * 0.5)
	_flash_age = 0.0
	_light.global_position = from
	_recoil_age = 0.0
	if not _blasts.is_empty():
		var blast := _blasts[shot_count % _blasts.size()]
		# Orient local -Z along the barrel at the muzzle, then fire one burst.
		blast.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT), from)
		blast.restart()
		blast.emitting = true
	if kind == "cannon":
		_deposit_fog(from, direction)
	if playback_enabled and not _voices.is_empty():
		var voice := _voices[shot_count % _voices.size()]
		voice.stop()
		voice.global_position = from
		voice.pitch_scale = 0.97 + float(shot_count % 4) * 0.02
		voice.play()
	shot_count += 1

func _frame(direction: Vector3) -> Basis:
	var right := direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	return Basis(right, direction, right.cross(direction))

func _advance(delta: float) -> void:
	_flash_age += delta
	var flash_time := 0.07 if kind == "cannon" else 0.05
	_flash.visible = _flash_age < flash_time
	_light.light_energy = maxf(0.0, 1.0 - _flash_age / (flash_time * 2.0)) * (6.0 if kind == "cannon" else 3.0)
	_recoil_age += delta
	if recoil != null:
		# Fast rearward kick, eased return into battery.
		var t := clampf(_recoil_age / RECOIL_RETURN, 0.0, 1.0)
		var travel := RECOIL_TRAVEL * (1.0 - t) * (1.0 - t) if kind == "cannon" else 0.0
		recoil.transform = _recoil_rest.translated_local(Vector3(0, 0, travel))
	for projectile: Dictionary in _projectiles:
		projectile.age += delta
		var flight: float = projectile.flight
		var travelling: bool = projectile.age < flight
		var from: Vector3 = projectile.from
		var to: Vector3 = projectile.to
		projectile.head.visible = travelling
		projectile.trail.visible = travelling
		if travelling:
			var direction := (to - from).normalized()
			var at := from.lerp(to, projectile.age / maxf(flight, 0.0001))
			projectile.head.global_transform = Transform3D(_frame(direction), at)
			var tail := at - direction * minf(at.distance_to(from), (6.0 if kind == "cannon" else 2.5) * _scale)
			var length := maxf(0.01, at.distance_to(tail))
			projectile.trail.global_transform = Transform3D(_frame(direction).scaled_local(Vector3(1, length, 1)), (at + tail) * 0.5)
		var burst_age: float = projectile.age - flight
		# A brief, small arrival flash only; confirmed hits add their own sparks.
		projectile.burst.visible = burst_age >= 0.0 and burst_age < 0.08 and projectile.age < 5.0
		if projectile.burst.visible:
			var radius := lerpf(0.08, 0.3 if kind == "cannon" else 0.2, burst_age / 0.08) * _scale
			projectile.burst.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius * 2.0), to)
			var material: StandardMaterial3D = projectile.burst.material_override
			material.albedo_color.a = 0.8 * (1.0 - burst_age / 0.08)
	for puff: Dictionary in _fog:
		puff.age += delta
		if puff.age >= FOG_LIFETIME:
			puff.volume.hide()
			continue
		var age: float = puff.age
		var size := (0.5 + age * 0.9) * _scale
		puff.volume.size = Vector3(size, size * 0.85, size)
		puff.volume.global_position = puff.origin + Vector3(puff.direction) * (1.0 - exp(-age * 3.0)) * 0.9 * _scale + Vector3.UP * 0.18 * age * _scale
		var fade := smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.4, FOG_LIFETIME, age))
		var material := puff.volume.material as ShaderMaterial
		material.set_shader_parameter("density", 0.55 * fade)
		material.set_shader_parameter("age", age)

func set_playback_enabled(enabled: bool) -> void:
	playback_enabled = enabled
	if not enabled:
		for voice: AudioStreamPlayer3D in _voices: voice.stop()

## Also forgets the shot baseline: the next accepted view is silent.
func clear_effects() -> void:
	_seen = -1
	_tick = -1
	_flash_age = 1.0
	_recoil_age = 1.0
	if recoil != null: recoil.transform = _recoil_rest
	for projectile: Dictionary in _projectiles:
		projectile.age = 10.0
		for key: String in ["head", "trail", "burst"]: projectile[key].hide()
	for blast: GPUParticles3D in _blasts:
		blast.emitting = false
		blast.restart()
		blast.emitting = false
	for puff: Dictionary in _fog:
		puff.age = FOG_LIFETIME
		puff.volume.hide()
	if _flash != null: _flash.hide()
	if _light != null: _light.light_energy = 0.0
	for voice: AudioStreamPlayer3D in _voices: voice.stop()

## First-pass procedural reports (A may replace them with recorded assets).
static func _report(weapon: String) -> AudioStreamWAV:
	if _streams.has(weapon): return _streams[weapon]
	var cannon := weapon == "cannon"
	var samples := PackedFloat32Array()
	samples.resize(roundi(RATE * (1.1 if cannon else 0.38)))
	var state := 0x5a17 if cannon else 0x2c91
	var low := 0.0
	var high := 0.0
	var phase := 0.0
	for index: int in samples.size():
		var t := index / float(RATE)
		state = (state * 1664525 + 1013904223) & 0x7fffffff
		var noise := state / 1073741824.0 - 1.0
		low += (noise - low) * (0.10 if cannon else 0.5)
		high += (noise - high) * 0.02
		var value := 0.0
		if cannon:
			# Muzzle crack, low blast body and a falling chamber boom.
			var crack := (noise - high) * exp(-t * 90.0) * 0.8
			var blast := low * exp(-t * 7.0) * 2.4
			phase += TAU * (62.0 - 30.0 * minf(t, 0.6)) / RATE
			var boom := sin(phase) * exp(-t * 4.5) * 0.7
			value = crack + blast + boom
		else:
			# Descending capacitor discharge with a crackling edge.
			var frequency := lerpf(1500.0, 240.0, minf(1.0, t / 0.3))
			phase += TAU * frequency / RATE
			var tone := (sin(phase) + 0.35 * sin(phase * 2.01)) * exp(-t * 9.0) * 0.5
			var crackle := (low - high) * exp(-t * 24.0) * 0.45
			value = tone + crackle
		var edges := smoothstep(0.0, 0.001, t) * (1.0 - smoothstep(samples.size() / float(RATE) - 0.05, samples.size() / float(RATE), t))
		samples[index] = clampf(value * edges, -0.85, 0.85)
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index: int in samples.size():
		pcm.encode_s16(index * 2, roundi(samples[index] * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	_streams[weapon] = stream
	return stream
