class_name TurretHarpoonEffects
extends Node3D
## Harpoon presentation from accepted views only; the tether itself is the
## replicated grip (BotView.grip_target / grip_point).
## - Fire: the loaded head leaves the tube (HarpoonHead hides), a barbed bolt
##   flies out paying out cable behind it, with a pneumatic thoonk.
## - Tethered: the bolt sits in the anchor on the victim; the cable sags when
##   slack and snaps taut, humming, while the winch reels.
## - Released or snapped: a whip-crack twang and the cable whips back in.
const RATE := 24000
const BOLT_SPEED := 95.0
const SEGMENTS := 20
const RETRACT_SECONDS := 0.35
var kind := "harpoon"
var muzzles: Array[Node3D] = []
var recoils: Array[Node3D] = []
var shot_count := 0
var playback_enabled := true
var _scale := 1.0
var _seen := -1
var _tick := -1
var _time := 0.0
## The loaded head in the launch tube (atlas_turret.glb HarpoonHead).
var _loaded: Node3D
var _bolt: MeshInstance3D
var _segments: Array[MeshInstance3D] = []
var _flight_from := Vector3.ZERO
var _flight_to := Vector3.ZERO
var _flight_age := 10.0
var _flight := 0.0
var _tethered := false
var _struck := true
var _anchor := Vector3.ZERO
var _tension := 0.0
var _retract_age := 10.0
var _retract_from := Vector3.ZERO
var _sparks: GPUParticles3D
var _launch: AudioStreamPlayer3D
var _clang: AudioStreamPlayer3D
var _twang: AudioStreamPlayer3D
var _winch: AudioStreamPlayer3D
static var _streams: Dictionary = {}

## recoil_nodes carries the loaded HarpoonHead (hidden while the bolt is out).
func configure(_weapon: String, muzzle_nodes: Array[Node3D], recoil_nodes: Array[Node3D], geometry_scale: float) -> void:
	muzzles = muzzle_nodes
	recoils = recoil_nodes
	_loaded = recoil_nodes[0] if not recoil_nodes.is_empty() else null
	_scale = geometry_scale
	add_to_group(&"bot_action_audio")
	AudioPreferences.ensure_buses()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.63, 0.62)
	steel.metallic = 0.95
	steel.roughness = 0.3
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.045 * _scale
	head.height = 0.55 * _scale
	head.radial_segments = 10
	_bolt = _world(head, steel)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.026 * _scale
	shaft.bottom_radius = 0.026 * _scale
	shaft.height = 0.9 * _scale
	shaft.radial_segments = 8
	var shaft_node := MeshInstance3D.new()
	shaft_node.mesh = shaft
	shaft_node.material_override = steel
	shaft_node.position = Vector3(0, -0.6 * _scale, 0)
	_bolt.add_child(shaft_node)
	for index: int in 4:
		var barb := BoxMesh.new()
		barb.size = Vector3(0.012, 0.22, 0.07) * _scale
		var fin := MeshInstance3D.new()
		fin.mesh = barb
		fin.material_override = steel
		fin.rotation = Vector3(0, index * PI * 0.5, 0)
		fin.position = Vector3(0, -0.18 * _scale, 0) + Basis(Vector3.UP, index * PI * 0.5) * Vector3(0, 0, 0.06 * _scale)
		fin.rotate_object_local(Vector3.RIGHT, -0.5)
		_bolt.add_child(fin)
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.09, 0.1, 0.1)
	cable.metallic = 0.6
	cable.roughness = 0.45
	for index: int in SEGMENTS:
		var rope := CylinderMesh.new()
		rope.top_radius = 0.022 * _scale
		rope.bottom_radius = 0.022 * _scale
		rope.height = 1.0
		rope.radial_segments = 6
		_segments.append(_world(rope, cable))
	_sparks = GPUParticles3D.new()
	_sparks.amount = 50
	_sparks.lifetime = 0.6
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.local_coords = false
	var motion := ParticleProcessMaterial.new()
	motion.spread = 70.0
	motion.initial_velocity_min = 2.0 * _scale
	motion.initial_velocity_max = 5.0 * _scale
	motion.gravity = Vector3(0, -9.0, 0)
	motion.scale_min = 0.5
	motion.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.9, 0.6), Color(1.0, 0.4, 0.1, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	_sparks.process_material = motion
	var spark := QuadMesh.new()
	spark.size = Vector2(0.03, 0.03) * _scale
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.albedo_color = Color(3.0, 3.0, 3.0)
	spark.material = glow
	_sparks.draw_pass_1 = spark
	add_child(_sparks)
	_sparks.top_level = true
	_launch = _voice("HarpoonLaunch", _stream("harpoon_launch"), 0.0, 12.0, 140.0)
	_clang = _voice("HarpoonClang", _stream("harpoon_clang"), 0.0, 12.0, 120.0)
	_twang = _voice("HarpoonTwang", _stream("harpoon_twang"), -2.0, 10.0, 100.0)
	_winch = _voice("HarpoonWinch", _stream("harpoon_winch"), -6.0, 10.0, 90.0)

func _world(shape: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	add_child(node)
	node.top_level = true
	node.hide()
	return node

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

func show_state(view: BotView, delta: float) -> void:
	_time += delta
	var baseline := _seen < 0 or view.server_tick < _tick or view.shot_sequence < _seen
	if baseline:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick
	elif view.shot_sequence > _seen:
		_seen = view.shot_sequence
		if not view.eliminated and view.last_shot_tick >= 0 and view.server_tick - view.last_shot_tick <= 12:
			_fire(view.last_shot_from, view.last_shot_to)
	_tick = view.server_tick
	var muzzle := _muzzle_point()
	var tethered := view.grip_target != 0 and not view.eliminated
	if tethered and not _struck and _flight_age >= _flight:
		_struck = true
		_strike(view.grip_point)
	if _tethered and not tethered:
		_retract_age = 0.0
		_retract_from = _anchor
		_play(_twang, _anchor)
	_tethered = tethered
	if tethered: _anchor = view.grip_point
	var reeling := tethered and view.secondary_active
	_tension = move_toward(_tension, 1.0 if reeling else 0.0, delta * (6.0 if reeling else 2.0))
	_flight_age += delta
	_retract_age += delta
	var out := false
	if _flight_age < _flight:
		# Bolt in flight, cable paying out behind it.
		var at := _flight_from.lerp(_flight_to, _flight_age / _flight)
		_place_bolt(at, (_flight_to - _flight_from).normalized())
		_draw_cable(muzzle, at, 0.02)
		out = true
	elif tethered:
		# The bolt rides its anchor on the victim.
		_place_bolt(_anchor, (_anchor - muzzle).normalized())
		_draw_cable(muzzle, _anchor, lerpf(0.06, 0.0, _tension))
		out = true
	elif _retract_age < RETRACT_SECONDS:
		var t := _retract_age / RETRACT_SECONDS
		var at := _retract_from.lerp(muzzle, t * t)
		_place_bolt(at, (_retract_from - muzzle).normalized())
		_draw_cable(muzzle, at, 0.1 * (1.0 - t))
		out = true
	elif _flight_age < _flight + RETRACT_SECONDS and _flight > 0.0:
		# A miss: the cable whips the empty bolt back to the tube.
		var t := (_flight_age - _flight) / RETRACT_SECONDS
		var at := _flight_to.lerp(muzzle, t * t)
		_place_bolt(at, (_flight_to - muzzle).normalized())
		_draw_cable(muzzle, at, 0.1 * (1.0 - t))
		out = true
	if not out:
		_bolt.hide()
		for segment: MeshInstance3D in _segments: segment.hide()
	if _loaded != null:
		# The next bolt is loaded once the tube has reloaded.
		_loaded.visible = not out and view.secondary_charge >= 0.999
	if _winch != null:
		if reeling and playback_enabled and not view.eliminated:
			if not _winch.playing: _winch.play()
			_winch.global_position = muzzle
			_winch.pitch_scale = 0.9 + 0.1 * sin(_time * 3.0)
		elif _winch.playing:
			_winch.stop()
	if view.eliminated:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick

func _muzzle_point() -> Vector3:
	var muzzle: Node3D = muzzles[0] if not muzzles.is_empty() else null
	return muzzle.global_position if muzzle != null else global_position

func _fire(from: Vector3, to: Vector3) -> void:
	shot_count += 1
	_flight_from = from
	_flight_to = to
	_flight_age = 0.0
	_flight = maxf(from.distance_to(to) / BOLT_SPEED, 0.03)
	_struck = false
	_retract_age = 10.0
	_play(_launch, from)

func _strike(at: Vector3) -> void:
	_sparks.global_position = at
	_sparks.restart()
	_sparks.emitting = true
	_play(_clang, at)

func _place_bolt(at: Vector3, direction: Vector3) -> void:
	if direction.is_zero_approx(): direction = Vector3.FORWARD
	var right := direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	# CylinderMesh points +Y: the tip leads along the flight direction.
	_bolt.global_transform = Transform3D(Basis(right, direction, right.cross(direction)), at)
	_bolt.visible = true

## Cable from the muzzle to the bolt; sag is the midspan droop as a share of
## the span (taut while reeling, slack otherwise).
func _draw_cable(from: Vector3, to: Vector3, sag: float) -> void:
	var span := from.distance_to(to)
	var points: Array[Vector3] = []
	for index: int in SEGMENTS + 1:
		var t := float(index) / SEGMENTS
		var hum := sin(_time * 90.0 + t * 20.0) * 0.015 * _scale * _tension * sin(t * PI)
		points.append(from.lerp(to, t) + Vector3.DOWN * (4.0 * t * (1.0 - t) * sag * span) + Vector3.UP * hum)
	for index: int in SEGMENTS:
		var a := points[index]
		var b := points[index + 1]
		var length := a.distance_to(b)
		if length < 0.0001:
			_segments[index].hide()
			continue
		var up := (b - a) / length
		var right := up.cross(Vector3.UP).normalized()
		if right.is_zero_approx(): right = Vector3.RIGHT
		_segments[index].global_transform = Transform3D(Basis(right, up, right.cross(up)).scaled_local(Vector3(1, length, 1)), (a + b) * 0.5)
		_segments[index].visible = true

func _play(voice: AudioStreamPlayer3D, at: Vector3) -> void:
	if not playback_enabled or voice == null: return
	voice.stop()
	voice.global_position = at
	voice.pitch_scale = 0.95 + float(shot_count % 4) * 0.03
	voice.play()

func set_playback_enabled(enabled: bool) -> void:
	playback_enabled = enabled
	if not enabled:
		for voice: AudioStreamPlayer3D in [_launch, _clang, _twang, _winch]:
			if voice != null: voice.stop()

func clear_effects() -> void:
	_seen = -1
	_tick = -1
	_flight_age = 10.0
	_flight = 0.0
	_retract_age = 10.0
	_tethered = false
	_tension = 0.0
	if _bolt != null: _bolt.hide()
	for segment: MeshInstance3D in _segments: segment.hide()
	if _loaded != null: _loaded.visible = true
	for voice: AudioStreamPlayer3D in [_launch, _clang, _twang, _winch]:
		if voice != null: voice.stop()

## Procedural first-pass sounds.
static func _stream(label: String) -> AudioStreamWAV:
	if _streams.has(label): return _streams[label]
	var looped := label == "harpoon_winch"
	var length: float = {"harpoon_launch":1.0, "harpoon_clang":0.9, "harpoon_twang":0.8, "harpoon_winch":1.0}.get(label, 1.0)
	var samples := PackedFloat32Array()
	samples.resize(roundi(RATE * length))
	var state := hash(label) & 0x7fffffff
	var low := 0.0
	var high := 0.0
	var phase := 0.0
	var peak := 0.0001
	for index: int in samples.size():
		var t := index / float(RATE)
		state = (state * 1664525 + 1013904223) & 0x7fffffff
		var noise := state / 1073741824.0 - 1.0
		low += (noise - low) * 0.06
		high += (noise - high) * 0.015
		var value := 0.0
		match label:
			"harpoon_launch":
				# Pneumatic thoonk: a saturated low pop, a hard gas blast and the
				# cable zipping off the drum as a falling buzzing whirr.
				phase += TAU * lerpf(80.0, 36.0, minf(1.0, t / 0.2)) / RATE
				var pop := tanh(sin(phase) * 3.0) * exp(-t * 9.0) * 1.3
				var gas := (noise - high) * exp(-t * 30.0) * 0.9 + low * exp(-t * 12.0) * 2.2
				var whirr := signf(sin(TAU * lerpf(210.0, 90.0, minf(1.0, t / 0.8)) * t)) * 0.12 * exp(-t * 3.5) * float(t > 0.04)
				value = tanh((pop + gas + whirr) * 1.6)
			"harpoon_clang":
				# Barbed steel punching into armour: a hard crunch and a clang ring.
				phase += TAU * lerpf(110.0, 55.0, minf(1.0, t / 0.15)) / RATE
				var thud := tanh(sin(phase) * 2.5) * exp(-t * 12.0)
				var ring := (sin(TAU * 820.0 * t) * 0.5 + sin(TAU * 1370.0 * t) * 0.35 + sin(TAU * 2240.0 * t) * 0.2) * exp(-t * 7.0) * 0.5
				value = tanh((thud + ring + (noise - high) * exp(-t * 50.0) * 0.8) * 1.5)
			"harpoon_twang":
				# Cable parting: a whip crack and a falling metallic twang.
				var crack := (noise - high) * exp(-t * 80.0) * 1.2
				var twang := sin(TAU * lerpf(260.0, 120.0, minf(1.0, t / 0.6)) * t) * exp(-t * 5.0) * 0.8
				value = tanh((crack + twang + low * exp(-t * 10.0) * 1.2) * 1.4)
			"harpoon_winch":
				# Straining geared winch: a low motor drone, gear whine and ratchet.
				var drone := signf(sin(TAU * 55.0 * t)) * 0.35 + sin(TAU * 110.0 * t) * 0.3
				var whine := sin(TAU * 440.0 * t) * 0.08
				var ratchet := (noise - high) * float(fmod(t * 12.0, 1.0) < 0.12) * 0.5
				value = tanh((drone + whine + ratchet + low * 1.2) * 1.2)
		var edges := 1.0 if looped else smoothstep(0.0, 0.001, t) * (1.0 - smoothstep(length - 0.05, length, t))
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
