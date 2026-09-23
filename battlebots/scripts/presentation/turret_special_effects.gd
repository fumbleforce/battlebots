class_name TurretSpecialEffects
extends Node3D
## Presentation for the special turret families. Accepted views only; nothing
## here awards a hit (confirmed hits come from combat events).
## - flamer: a roaring fire jet while firing, smoke above it, a flickering glow.
## - tesla: a jagged, re-striking lightning arc to each discharge endpoint.
## - railgun: rails glow and whine while charging; release draws a searing beam.
const RATE := 24000
var kind := ""
var muzzles: Array[Node3D] = []
var recoils: Array[Node3D] = []
var shot_count := 0
var playback_enabled := true
var _scale := 1.0
var _seen := -1
var _tick := -1
var _time := 0.0
var _flame: GPUParticles3D
var _flame_smoke: GPUParticles3D
var _flame_light: OmniLight3D
var _roar: AudioStreamPlayer3D
var _roar_level := 0.0
var _arc_segments: Array[MeshInstance3D] = []
var _arc_from := Vector3.ZERO
var _arc_to := Vector3.ZERO
var _arc_age := 10.0
var _arc_light: OmniLight3D
var _beam_core: MeshInstance3D
var _beam_glow: MeshInstance3D
var _beam_age := 10.0
var _charge_light: OmniLight3D
var _whine: AudioStreamPlayer3D
var _impact_light: OmniLight3D
var _impact_age := 10.0
var _sparks: GPUParticles3D
var _voices: Array[AudioStreamPlayer3D] = []
static var _streams: Dictionary = {}

func configure(weapon: String, muzzle_nodes: Array[Node3D], recoil_nodes: Array[Node3D], geometry_scale: float) -> void:
	kind = weapon
	muzzles = muzzle_nodes
	recoils = recoil_nodes
	_scale = geometry_scale
	add_to_group(&"bot_action_audio")
	AudioPreferences.ensure_buses()
	_impact_light = _omni(Color(0.7, 0.8, 1.0) if kind != "flamer" else Color(1.0, 0.55, 0.2), 6.0 * _scale)
	_sparks = _particles(60, 0.8, Color(0.9, 0.95, 1.0) if kind != "flamer" else Color(1.0, 0.8, 0.4), Color(0.4, 0.5, 1.0) if kind != "flamer" else Color(1.0, 0.3, 0.05), 0.02, 5.0)
	match kind:
		"flamer":
			_flame = _fire_jet()
			_flame_smoke = _smoke_jet()
			_flame_light = _omni(Color(1.0, 0.55, 0.18), 9.0 * _scale)
			_roar = _voice("FlameRoar", _stream("flame_roar"), -2.0, 12.0, 120.0)
			_voices.append(_voice("FlameIgnite", _stream("flame_ignite"), 0.0, 12.0, 120.0))
		"tesla":
			var material := _glow(Color(0.75, 0.85, 1.0), 10.0)
			for index: int in 18:
				var segment := MeshInstance3D.new()
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = 0.018 * _scale
				cylinder.bottom_radius = 0.018 * _scale
				cylinder.height = 1.0
				cylinder.radial_segments = 5
				segment.mesh = cylinder
				segment.material_override = material
				_world(segment)
				_arc_segments.append(segment)
			_arc_light = _omni(Color(0.6, 0.75, 1.0), 10.0 * _scale)
			for index: int in 3:
				_voices.append(_voice("TeslaZap%d" % index, _stream("tesla"), 0.0, 12.0, 130.0))
		"railgun":
			var core := CylinderMesh.new()
			core.top_radius = 0.05 * _scale
			core.bottom_radius = 0.05 * _scale
			core.height = 1.0
			core.radial_segments = 8
			_beam_core = _mesh(core, _glow(Color(0.95, 0.98, 1.0), 16.0))
			var glow := CylinderMesh.new()
			glow.top_radius = 0.22 * _scale
			glow.bottom_radius = 0.22 * _scale
			glow.height = 1.0
			glow.radial_segments = 10
			_beam_glow = _mesh(glow, _glow(Color(0.45, 0.65, 1.0, 0.6), 4.0))
			_charge_light = _omni(Color(0.5, 0.7, 1.0), 6.0 * _scale)
			_whine = _voice("RailWhine", _stream("rail_whine"), -6.0, 10.0, 110.0)
			for index: int in 2:
				_voices.append(_voice("RailReport%d" % index, _stream("railgun"), 2.0, 16.0, 200.0))

func _world(node: MeshInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = true
	node.hide()

func _mesh(shape: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	_world(node)
	return node

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r * energy * 0.25, color.g * energy * 0.25, color.b * energy * 0.25, color.a)
	return material

func _omni(color: Color, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = reach
	light.light_energy = 0.0
	add_child(light)
	light.top_level = true
	return light

func _voice(label: String, stream: AudioStreamWAV, gain: float, unit: float, reach: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = label
	voice.stream = stream
	voice.bus = &"BBEffects"
	voice.volume_db = gain
	voice.unit_size = unit
	voice.max_distance = reach
	add_child(voice)
	voice.top_level = true
	return voice

func _particles(amount: int, lifetime: float, hot: Color, cool: Color, size: float, speed: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 0.95
	emitter.emitting = false
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-8, -8, -8) * _scale, Vector3(16, 16, 16) * _scale)
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 80.0
	motion.initial_velocity_min = speed * 0.3 * _scale
	motion.initial_velocity_max = speed * _scale
	motion.gravity = Vector3(0, -9.8, 0)
	motion.scale_min = 0.5
	motion.scale_max = 1.2
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([Color(hot, 1.0), Color(cool, 0.8), Color(cool.darkened(0.6), 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size * _scale
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(2.5, 2.5, 2.5, 1.0)
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	emitter.top_level = true
	return emitter

## Continuous fire jet: fast soft fire billows that widen, flash yellow-white
## at the nozzle and burn out orange-red toward the reach.
func _fire_jet() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = 160
	emitter.lifetime = 0.6
	emitter.emitting = false
	emitter.local_coords = false
	emitter.fixed_fps = 60
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-12, -8, -24) * _scale, Vector3(24, 16, 30) * _scale)
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.FORWARD
	motion.spread = 9.0
	motion.initial_velocity_min = 26.0
	motion.initial_velocity_max = 32.0
	motion.damping_min = 4.0
	motion.damping_max = 8.0
	motion.gravity = Vector3(0, 3.0, 0)
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -120.0
	motion.angular_velocity_max = 120.0
	# Narrow at the nozzle, billowing wide toward the reach.
	motion.scale_min = 0.24 * _scale
	motion.scale_max = 0.34 * _scale
	motion.scale_curve = TurretShotEffects._curve([Vector2(0, 0.12), Vector2(0.45, 0.8), Vector2(1, 1.5)])
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 1.2
	motion.turbulence_noise_scale = 1.4
	motion.turbulence_influence_min = 0.05
	motion.turbulence_influence_max = 0.15
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.35, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color(0.7, 0.8, 1.0, 0.6), Color(1.0, 0.8, 0.35, 0.9),
		Color(1.0, 0.5, 0.1, 0.9), Color(0.95, 0.28, 0.05, 0.6), Color(0.4, 0.08, 0.02, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.9, 0.9, 0.9, 1.0)
	material.albedo_texture = TurretShotEffects._soft_texture()
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	emitter.top_level = true
	return emitter

func _smoke_jet() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = 40
	emitter.lifetime = 1.8
	emitter.emitting = false
	emitter.local_coords = false
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-12, -8, -24) * _scale, Vector3(24, 18, 30) * _scale)
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.FORWARD
	motion.spread = 12.0
	motion.initial_velocity_min = 14.0
	motion.initial_velocity_max = 20.0
	motion.damping_min = 6.0
	motion.damping_max = 9.0
	motion.gravity = Vector3(0, 1.4, 0) * _scale
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.scale_min = 0.6 * _scale
	motion.scale_max = 1.0 * _scale
	motion.scale_curve = TurretShotEffects._curve([Vector2(0, 0.3), Vector2(0.5, 1.0), Vector2(1, 1.5)])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material: ShaderMaterial = TurretShotEffects._smoke_material(true).duplicate()
	material.set_shader_parameter("shadow_color", Color(0.08, 0.07, 0.06))
	material.set_shader_parameter("lit_color", Color(0.22, 0.2, 0.18))
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	emitter.top_level = true
	return emitter

func show_state(view: BotView, delta: float) -> void:
	_time += delta
	var baseline := _seen < 0 or view.server_tick < _tick or view.shot_sequence < _seen
	var fired := false
	if baseline:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick
	elif view.shot_sequence > _seen:
		_seen = view.shot_sequence
		if not view.eliminated and view.last_shot_tick >= 0 and view.server_tick - view.last_shot_tick <= 12:
			fired = true
			_fire(view.last_shot_from, view.last_shot_to)
	_tick = view.server_tick
	var muzzle: Node3D = muzzles[0] if not muzzles.is_empty() else null
	var active := view.secondary_active and not view.eliminated
	match kind:
		"flamer":
			_advance_flamer(muzzle, active, delta)
		"railgun":
			_advance_railgun(muzzle, view, delta)
	_advance_shared(delta)
	if view.eliminated:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick

func _fire(from: Vector3, to: Vector3) -> void:
	shot_count += 1
	match kind:
		"flamer":
			pass
		"tesla":
			_arc_from = from
			_arc_to = to
			_arc_age = 0.0
			_arc_light.global_position = (from + to) * 0.5
			_restrike()
			_burst(to, 0.8)
			_play(from)
		"railgun":
			_beam_age = 0.0
			_orient_beam(_beam_core, from, to)
			_orient_beam(_beam_glow, from, to)
			_burst(to, 1.4)
			_play(from)

func _play(at: Vector3) -> void:
	if not playback_enabled or _voices.is_empty(): return
	var voice := _voices[shot_count % _voices.size()]
	voice.stop()
	voice.global_position = at
	voice.pitch_scale = 0.95 + float(shot_count % 5) * 0.025
	voice.play()

func _burst(at: Vector3, strength: float) -> void:
	_impact_age = 0.0
	_impact_light.global_position = at + Vector3.UP * 0.5 * _scale
	_impact_light.light_energy = 8.0 * strength
	_sparks.global_position = at
	_sparks.restart()
	_sparks.emitting = true

func _orient_beam(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var direction := to - from
	var length := maxf(direction.length(), 0.01)
	var up := direction / length
	var right := up.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	node.global_transform = Transform3D(Basis(right, up, right.cross(up)).scaled_local(Vector3(1, length, 1)), (from + to) * 0.5)
	node.visible = true

## Lightning: a jagged polyline between the ends, displaced perpendicular to
## the arc, re-randomised a few times during its short life.
func _restrike() -> void:
	var direction := _arc_to - _arc_from
	var length := direction.length()
	if length < 0.01:
		for segment: MeshInstance3D in _arc_segments: segment.hide()
		return
	var axis := direction / length
	var side := axis.cross(Vector3.UP).normalized()
	if side.is_zero_approx(): side = Vector3.RIGHT
	var lift := side.cross(axis)
	var points: Array[Vector3] = [_arc_from]
	var count := _arc_segments.size()
	for index: int in range(1, count):
		var t := float(index) / count
		var sway := sin(t * PI) * minf(length * 0.08, 1.2 * _scale)
		points.append(_arc_from + direction * t + side * randf_range(-sway, sway) + lift * randf_range(-sway, sway))
	points.append(_arc_to)
	for index: int in count:
		var a := points[index]
		var b := points[index + 1]
		var span := b - a
		var up := span.normalized()
		var right := up.cross(Vector3.UP).normalized()
		if right.is_zero_approx(): right = Vector3.RIGHT
		_arc_segments[index].global_transform = Transform3D(Basis(right, up, right.cross(up)).scaled_local(Vector3(1, span.length(), 1)), (a + b) * 0.5)
		_arc_segments[index].visible = true

func _advance_flamer(muzzle: Node3D, active: bool, delta: float) -> void:
	if muzzle != null:
		var basis := muzzle.global_basis.orthonormalized()
		var at := muzzle.global_position
		_flame.global_transform = Transform3D(basis, at)
		_flame_smoke.global_transform = Transform3D(basis, at - basis.z * 1.5 * _scale)
		_flame_light.global_position = at - basis.z * 3.0 * _scale
	if active and not _flame.emitting and playback_enabled and not _voices.is_empty():
		_voices[0].global_position = _flame.global_position
		_voices[0].play()
	_flame.emitting = active
	_flame_smoke.emitting = active
	var flicker := 0.75 + 0.25 * sin(_time * 37.0) * sin(_time * 23.0 + 1.1)
	_flame_light.light_energy = (7.0 * flicker) if active else 0.0
	_roar_level = move_toward(_roar_level, 1.0 if active else 0.0, delta * (8.0 if active else 3.0))
	if _roar != null:
		_roar.global_position = _flame.global_position
		if _roar_level > 0.01 and playback_enabled:
			if not _roar.playing: _roar.play()
			_roar.volume_db = linear_to_db(_roar_level) - 2.0
		elif _roar.playing:
			_roar.stop()

func _advance_railgun(muzzle: Node3D, view: BotView, delta: float) -> void:
	var charging := view.secondary_active and view.secondary_charge > 0.02 and not view.eliminated
	var level := view.secondary_charge if charging else 0.0
	if muzzle != null:
		_charge_light.global_position = muzzle.global_position
	_charge_light.light_energy = level * level * 6.0 * (0.85 + 0.15 * sin(_time * 60.0))
	if _whine != null:
		if charging and playback_enabled:
			if not _whine.playing: _whine.play()
			_whine.pitch_scale = lerpf(0.6, 1.8, level)
			_whine.volume_db = lerpf(-18.0, -4.0, level)
		elif _whine.playing:
			_whine.stop()

func _advance_shared(delta: float) -> void:
	_impact_age += delta
	if _impact_light != null:
		_impact_light.light_energy = maxf(0.0, _impact_light.light_energy - delta * 30.0)
	if kind == "tesla":
		_arc_age += delta
		var alive := _arc_age < 0.2
		if alive and fmod(_arc_age, 0.045) < delta: _restrike()
		for segment: MeshInstance3D in _arc_segments:
			segment.visible = alive and segment.visible
		_arc_light.light_energy = (9.0 * (1.0 - _arc_age / 0.2) * randf_range(0.6, 1.0)) if alive else 0.0
	if kind == "railgun":
		_beam_age += delta
		var alive := _beam_age < 0.45
		_beam_core.visible = alive and _beam_age < 0.18
		_beam_glow.visible = alive
		if alive:
			var fade := 1.0 - _beam_age / 0.45
			(_beam_glow.material_override as StandardMaterial3D).albedo_color.a = 0.6 * fade
			var width := lerpf(1.0, 2.2, _beam_age / 0.45)
			_beam_glow.scale = Vector3(width, _beam_glow.scale.y, width)

func set_playback_enabled(enabled: bool) -> void:
	playback_enabled = enabled
	if not enabled:
		for voice: AudioStreamPlayer3D in _voices: voice.stop()
		if _roar != null: _roar.stop()
		if _whine != null: _whine.stop()

func clear_effects() -> void:
	_seen = -1
	_tick = -1
	_arc_age = 10.0
	_beam_age = 10.0
	for segment: MeshInstance3D in _arc_segments: segment.hide()
	if _beam_core != null:
		_beam_core.hide()
		_beam_glow.hide()
	if _flame != null:
		_flame.emitting = false
		_flame_smoke.emitting = false
		_flame_light.light_energy = 0.0
	if _roar != null: _roar.stop()
	if _whine != null: _whine.stop()
	if _charge_light != null: _charge_light.light_energy = 0.0
	if _arc_light != null: _arc_light.light_energy = 0.0
	if _impact_light != null: _impact_light.light_energy = 0.0
	for voice: AudioStreamPlayer3D in _voices: voice.stop()

## Procedural first-pass sounds (A may replace them with recorded assets).
static func _stream(label: String) -> AudioStreamWAV:
	if _streams.has(label): return _streams[label]
	var looped := label in ["flame_roar", "rail_whine"]
	var length: float = {"flame_roar":2.0, "flame_ignite":0.8, "tesla":0.7, "railgun":2.0, "rail_whine":1.0}.get(label, 1.0)
	var samples := PackedFloat32Array()
	samples.resize(roundi(RATE * length))
	var state := hash(label) & 0x7fffffff
	var low := 0.0
	var high := 0.0
	var rumble := 0.0
	var gate := 0.0
	var phase := 0.0
	var peak := 0.0001
	for index: int in samples.size():
		var t := index / float(RATE)
		state = (state * 1664525 + 1013904223) & 0x7fffffff
		var noise := state / 1073741824.0 - 1.0
		low += (noise - low) * 0.08
		high += (noise - high) * 0.02
		rumble += (noise - rumble) * 0.012
		if (state & 0x3ff) < 8: gate = 1.0
		gate *= 0.996
		var value := 0.0
		match label:
			"flame_roar":
				# Seamless roaring torch: low rumble, turbulent body, crackle.
				var swell := 0.8 + 0.2 * sin(TAU * 3.0 * t) * sin(TAU * 1.0 * t)
				value = (rumble * 6.0 + low * 1.6 + (low - high) * gate * 0.6) * swell
			"flame_ignite":
				phase += TAU * lerpf(90.0, 40.0, minf(1.0, t / 0.3)) / RATE
				value = tanh(sin(phase) * 2.0) * exp(-t * 6.0) + low * exp(-t * 4.0) * 2.5
			"tesla":
				# Hard electrical crack with a buzzing 120 Hz arc and crackle.
				phase += TAU * 120.0 / RATE
				var buzz := signf(sin(phase)) * 0.4 * exp(-t * 7.0)
				value = (noise - high) * exp(-t * 60.0) * 1.2 + buzz + (low - high) * gate * exp(-t * 4.0) * 1.2 + tanh(sin(phase * 0.5) * 3.0) * exp(-t * 12.0) * 0.6
			"rail_whine":
				# Rising capacitor whine (pitch follows charge at runtime).
				value = sin(TAU * 440.0 * t) * 0.35 + sin(TAU * 880.0 * t) * 0.15 + sin(TAU * 1320.0 * t) * 0.08
			"railgun":
				# Supersonic crack, deep electromagnetic thoom and a zinging tail.
				phase += TAU * lerpf(70.0, 30.0, minf(1.0, t / 0.5)) / RATE
				var crack := (noise - high) * exp(-t * 180.0) * 1.6
				var thoom := tanh(sin(phase) * 3.0) * exp(-t * 3.0) * 1.3
				var zing := sin(TAU * lerpf(2400.0, 300.0, minf(1.0, t / 0.8)) * t) * exp(-t * 4.0) * 0.25
				value = tanh((crack + thoom + low * exp(-t * 5.0) * 2.5 + rumble * exp(-t * 1.4) * 4.0 + zing) * 1.7)
		var edges := 1.0 if looped else smoothstep(0.0, 0.001, t) * (1.0 - smoothstep(length - 0.06, length, t))
		samples[index] = value * edges
		peak = maxf(peak, absf(samples[index]))
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index: int in samples.size():
		pcm.encode_s16(index * 2, roundi(clampf(samples[index] / peak * 0.85, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	_streams[label] = stream
	return stream
