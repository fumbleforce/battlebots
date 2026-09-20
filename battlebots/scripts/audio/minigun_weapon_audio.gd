class_name MinigunWeaponAudio
extends Node3D
## Weapon-owned voices. Accepted visual snapshots never feed back into authority.
const REPORT_VOICES := 4
const RATE := 24000
var reports: Array[AudioStreamPlayer3D] = []
var motor: AudioStreamPlayer3D
var played_count := 0
var motor_level := 0.0
var _tick := -1
var _baseline_tick := -1
var _sequence := -1
var _stale := 0.0
var _armed := false
var _shot_quiet := 0.0
var playback_enabled := true

func _ready() -> void:
	add_to_group(&"bot_action_audio")
	AudioPreferences.ensure_buses()
	var report := _report_stream()
	for index: int in REPORT_VOICES:
		var player := _voice("Report%d" % index, report, -8.5)
		reports.append(player)
	motor = _voice("BarrelMotor", _motor_stream(), -35.0)

func _voice(label: String, stream: AudioStreamWAV, gain: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = label
	player.stream = stream
	player.bus = &"BBEffects"
	player.volume_db = gain
	player.unit_size = 5.0
	player.max_distance = 52.0
	add_child(player)
	player.top_level = true
	return player

func observe(view: BotView, spool: float, at: Vector3, delta: float) -> void:
	if motor == null: return
	if not playback_enabled or view.entity_id <= 0 or view.eliminated or not at.is_finite():
		reset()
		return
	if _tick < 0 or view.server_tick < _tick or view.shot_sequence < _sequence:
		reset()
		_baseline_tick = view.server_tick
		_tick = view.server_tick
		_sequence = view.shot_sequence
		return
	_stale = 0.0 if view.server_tick > _tick else _stale + maxf(delta, 0.0)
	_tick = view.server_tick
	_sequence = view.shot_sequence
	_armed = view.server_tick > _baseline_tick and _stale < 0.25
	_shot_quiet = maxf(0.0, _shot_quiet - maxf(delta, 0.0))
	var target := clampf(spool, 0.0, 1.0) if _armed else 0.0
	motor_level = lerpf(motor_level, target, 1.0 - exp(-maxf(delta, 0.0) * 18.0))
	motor.global_position = at
	motor.pitch_scale = lerpf(0.48, 1.35, motor_level)
	motor.volume_db = linear_to_db(maxf(0.0001, motor_level)) - 20.0
	if motor_level > 0.025 and _armed:
		if not motor.playing: motor.play()
	else:
		motor.stop()

func fire(at: Vector3) -> void:
	if not playback_enabled or not _armed or _shot_quiet > 0.0 or not at.is_finite() or reports.is_empty(): return
	var player := reports[played_count % REPORT_VOICES]
	player.stop()
	player.global_position = at
	player.pitch_scale = 0.98 + float(played_count % 5) * 0.01
	player.play()
	played_count += 1
	# A delayed snapshot may contain several shots; one current report is enough.
	_shot_quiet = 0.040

func set_playback_enabled(enabled: bool) -> void:
	if playback_enabled == enabled: return
	playback_enabled = enabled
	reset()

func reset() -> void:
	_tick = -1
	_baseline_tick = -1
	_sequence = -1
	_stale = 0.0
	_armed = false
	_shot_quiet = 0.0
	motor_level = 0.0
	if motor != null: motor.stop()
	for player: AudioStreamPlayer3D in reports: player.stop()

static func _stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index: int in samples.size():
		pcm.encode_s16(index * 2, roundi(clampf(samples[index], -0.82, 0.82) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	return stream

static func _report_stream() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(roundi(RATE * 0.16))
	var state := 0x41f7
	var low := 0.0
	var high := 0.0
	for index: int in samples.size():
		var t := index / float(RATE)
		state = (state * 1664525 + 1013904223) & 0x7fffffff
		var noise := state / 1073741824.0 - 1.0
		low += (noise - low) * 0.72
		high += (noise - high) * 0.075
		# Short powder crack, falling chamber thump, and bolt/carrier ring.
		var crack := (low - high) * exp(-t * 66.0) * 0.78
		var chamber := sin(TAU * (112.0 * t - 90.0 * t * t)) * exp(-t * 39.0) * 0.42
		var mechanism := (sin(TAU * 1437.0 * t) * 0.14 + sin(TAU * 2381.0 * t) * 0.08) * exp(-t * 50.0)
		var carrier := maxf(0.0, 1.0 - absf(t - 0.052) / 0.008) * (low - high) * 0.15
		var edges := smoothstep(0.0, 0.0008, t) * (1.0 - smoothstep(0.12, 0.16 - 1.0 / RATE, t))
		samples[index] = (crack + chamber + mechanism + carrier) * edges * 0.84
	return _stream(samples, false)

static func _motor_stream() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(RATE)
	# Integer harmonics form a seamless one-second gear/motor loop; no random
	# splice or exposed saw sample. Playback pitch follows the accepted spool.
	for index: int in samples.size():
		var t := index / float(RATE)
		var gear := sin(TAU * 176.0 * t) * 0.32 + sin(TAU * 352.0 * t + 0.4) * 0.12
		gear += sin(TAU * 704.0 * t + 1.2) * 0.065 + sin(TAU * 1232.0 * t) * 0.032
		var bearings := sin(TAU * 1511.0 * t + 0.7) * 0.025 + sin(TAU * 1877.0 * t) * 0.018
		samples[index] = (gear + bearings) * (0.82 + 0.18 * cos(TAU * 24.0 * t))
	return _stream(samples, true)
