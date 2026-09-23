class_name TurretShotEffects
extends Node3D
## Accepted shot snapshots only: recoil, muzzle blast, a travelling shell or
## plasma bolt, a cosmetic arrival burst and procedural reports. Confirmed hit
## sparks and damage come from combat events; nothing here awards a hit.
const PROJECTILES := 6
const SMOKE := 10
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
var _smoke: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer3D] = []
static var _streams: Dictionary = {}

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
	if cannon:
		var smoke := StandardMaterial3D.new()
		smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke.albedo_color = Color(0.55, 0.52, 0.48, 0.45)
		smoke.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		for index: int in SMOKE:
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			var puff := MeshInstance3D.new()
			puff.mesh = quad
			puff.material_override = smoke.duplicate()
			_world(puff)
			_smoke.append({"node":puff, "age":10.0, "velocity":Vector3.ZERO})
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
	for index: int in (4 if kind == "cannon" else 0):
		var puff: Dictionary = _smoke[(shot_count * 4 + index) % SMOKE]
		puff.age = 0.0
		puff.node.global_position = from + direction * 0.2 * _scale
		var spread := Vector3(sin(index * 2.1), 0.4 + 0.2 * index, cos(index * 1.7)) * 0.6
		puff.velocity = (direction * (1.8 - index * 0.35) + spread) * _scale
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
		projectile.burst.visible = burst_age >= 0.0 and burst_age < 0.22 and projectile.age < 5.0
		if projectile.burst.visible:
			var radius := lerpf(0.15, 1.0 if kind == "cannon" else 0.6, burst_age / 0.22) * _scale
			projectile.burst.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius * 2.0), to)
			var material: StandardMaterial3D = projectile.burst.material_override
			material.albedo_color.a = 0.7 * (1.0 - burst_age / 0.22)
	for puff: Dictionary in _smoke:
		puff.age += delta
		puff.node.visible = puff.age < 1.6
		if puff.node.visible:
			puff.velocity = Vector3(puff.velocity) * exp(-delta * 2.2) + Vector3.UP * 0.25 * _scale * delta
			puff.node.global_position += Vector3(puff.velocity) * delta
			var grow := lerpf(0.35, 1.5, puff.age / 1.6) * _scale
			puff.node.scale = Vector3.ONE * grow
			var material: StandardMaterial3D = puff.node.material_override
			material.albedo_color.a = 0.45 * (1.0 - puff.age / 1.6)

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
	for puff: Dictionary in _smoke:
		puff.age = 10.0
		puff.node.hide()
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
