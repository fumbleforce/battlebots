class_name AtlasToolVisual
extends Node3D
## Presentation of the Atlas MX front tools (atlas_tools.glb): drives the
## authored moving groups from accepted views and plays their mechanical
## sounds. Nothing here awards a hit (combat events do).
## - Ram: RamPunch extends with the punch (charge), with a hydraulic slam.
## - Spear: SpearTines thrust (charge), SpearCarriage lifts (tool_pose).
## - Grinder: GrinderArms raise (tool_pose), GrinderDrum spins with charge,
##   throwing sparks while it grinds and roaring with spin.
const MODEL := "res://assets/models/atlas_runtime/atlas_tools.glb"
const GROUPS := {"ram":"ToolRam", "spear":"ToolSpear", "grinder":"ToolGrinder"}
const RATE := 24000
## Drum speed at full spin (rad/s) and the pose easing rate.
const DRUM_SPEED := 38.0
const EASE := 22.0
var tool := ""
var playback_enabled := true
var _nodes: Dictionary = {}
var _rest: Dictionary = {}
var _drum_angle := 0.0
var _extension := 0.0
var _pose := 0.0
var _attack := -1
var _sparks: GPUParticles3D
var _roar: AudioStreamPlayer3D
var _slam: AudioStreamPlayer3D
var _hydraulic: AudioStreamPlayer3D
static var _streams: Dictionary = {}

## Builds only the fitted tool; the others are freed.
func assemble(kind: String) -> void:
	tool = kind
	var model: Node3D = load(MODEL).instantiate()
	model.name = "AtlasToolsModel"
	add_child(model)
	for label: String in GROUPS:
		var group := model.find_child(GROUPS[label], true, false)
		if group != null and label != tool: group.free()
	for node: Node in model.find_children("*", "Node3D", true, false):
		_nodes[str(node.name)] = node
		_rest[str(node.name)] = (node as Node3D).transform
	add_to_group(&"bot_action_audio")
	AudioPreferences.ensure_buses()
	_slam = _voice("ToolSlam", _stream("tool_slam"), 0.0)
	_hydraulic = _voice("ToolHydraulic", _stream("tool_hydraulic"), -6.0)
	if tool == "grinder":
		_roar = _voice("GrinderRoar", _stream("grinder_roar"), -4.0)
		_sparks = _spark_spray()

func _voice(label: String, stream: AudioStreamWAV, gain: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = label
	voice.stream = stream
	voice.bus = &"BBEffects"
	voice.volume_db = gain
	voice.unit_size = 10.0
	voice.max_distance = 110.0
	add_child(voice)
	return voice

func _spark_spray() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = 80
	emitter.lifetime = 0.5
	emitter.emitting = false
	emitter.local_coords = false
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3(0, 1, 0.4)
	motion.spread = 35.0
	motion.initial_velocity_min = 4.0
	motion.initial_velocity_max = 9.0
	motion.gravity = Vector3(0, -14, 0)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.9, 0.6), Color(1.0, 0.35, 0.05, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.vertex_color_use_as_albedo = true
	glow.albedo_color = Color(3, 3, 3)
	quad.material = glow
	emitter.draw_pass_1 = quad
	add_child(emitter)
	return emitter

func show_state(view: BotView, delta: float) -> void:
	var rate := 1.0 - exp(-maxf(delta, 0.0) * EASE)
	_extension = lerpf(_extension, view.weapon_charge_fraction if tool != "grinder" else 0.0, rate)
	_pose = lerpf(_pose, view.tool_pose, rate)
	var striking := view.weapon_state == &"strike"
	if striking and _attack < 0:
		_attack = 1
		_play(_slam if tool == "ram" else _hydraulic)
		if tool == "spear": _play(_slam, 0.8)
	elif not striking:
		_attack = -1
	match tool:
		"ram":
			_place("RamPunch", Vector3(0, 0, -AtlasGeometry.RAM_PUNCH * _extension))
		"spear":
			_place("SpearCarriage", Vector3(0, AtlasGeometry.SPEAR_LIFT * _pose, 0))
			_place("SpearTines", Vector3(0, 0, -AtlasGeometry.SPEAR_THRUST * _extension))
		"grinder":
			var arms: Node3D = _nodes.get("GrinderArms")
			if arms != null:
				arms.transform = _rest.GrinderArms * Transform3D(Basis(Vector3.RIGHT, AtlasGeometry.GRINDER_RAISE * _pose))
			var spin := 0.0 if view.eliminated else view.weapon_charge_fraction
			_drum_angle = wrapf(_drum_angle - spin * DRUM_SPEED * delta, -PI, PI)
			var drum: Node3D = _nodes.get("GrinderDrum")
			if drum != null:
				drum.transform = _rest.GrinderDrum * Transform3D(Basis(Vector3.RIGHT, _drum_angle))
				if _sparks != null:
					# Sparks spray off the drum's leading underside while it spins hard.
					var reach := AtlasGeometry.GRINDER_REACH * global_basis.get_scale().x
					_sparks.global_position = drum.global_position - global_basis.y.normalized() * reach * 0.6 \
						- global_basis.z.normalized() * reach * 0.8
					_sparks.emitting = spin > 0.6 and view.weapon_state == &"active"
			if _roar != null:
				if spin > 0.05 and playback_enabled:
					if not _roar.playing: _roar.play()
					_roar.pitch_scale = lerpf(0.5, 1.2, spin)
					_roar.volume_db = lerpf(-20.0, -2.0, spin)
				elif _roar.playing:
					_roar.stop()

func _place(label: String, offset: Vector3) -> void:
	var node: Node3D = _nodes.get(label)
	if node != null:
		node.transform = _rest[label].translated_local(offset)

func _play(voice: AudioStreamPlayer3D, pitch := 1.0) -> void:
	if voice == null or not playback_enabled: return
	voice.stop()
	voice.pitch_scale = pitch
	voice.play()

func set_playback_enabled(enabled: bool) -> void:
	playback_enabled = enabled
	if not enabled:
		for voice: AudioStreamPlayer3D in [_roar, _slam, _hydraulic]:
			if voice != null: voice.stop()

func clear_effects() -> void:
	_attack = -1
	if _sparks != null: _sparks.emitting = false
	for voice: AudioStreamPlayer3D in [_roar, _slam, _hydraulic]:
		if voice != null: voice.stop()

## Procedural first-pass sounds (WEAPON_FEEL.md: weight below 150 Hz).
static func _stream(label: String) -> AudioStreamWAV:
	if _streams.has(label): return _streams[label]
	var looped := label == "grinder_roar"
	var length: float = {"tool_slam":0.9, "tool_hydraulic":0.6, "grinder_roar":1.0}.get(label, 1.0)
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
		low += (noise - low) * 0.05
		high += (noise - high) * 0.015
		var value := 0.0
		match label:
			"tool_slam":
				# Hydraulic ram slam: gas hiss attack, a saturated 70->30 Hz thud
				# and a heavy steel clank.
				phase += TAU * lerpf(70.0, 30.0, minf(1.0, t / 0.25)) / RATE
				var thud := tanh(sin(phase) * 3.0) * exp(-t * 7.0) * 1.3
				var clank := (sin(TAU * 610.0 * t) * 0.5 + sin(TAU * 980.0 * t) * 0.3) * exp(-t * 14.0) * 0.4
				value = tanh(((noise - high) * exp(-t * 60.0) * 0.8 + thud + clank + low * exp(-t * 8.0) * 2.0) * 1.6)
			"tool_hydraulic":
				# Short hydraulic stroke: valve hiss over a rising pump whine.
				var whine := sin(TAU * lerpf(180.0, 320.0, t / length) * t) * 0.3 * sin(PI * t / length)
				value = tanh(((low - high) * 1.5 * sin(PI * t / length) + whine) * 1.4)
			"grinder_roar":
				# Seamless grinding roar: a low motor drone, spike chatter at the
				# tooth-pass rate and gritty metal scrape.
				var drone := sin(TAU * 60.0 * t) * 0.5 + signf(sin(TAU * 120.0 * t)) * 0.18
				var chatter := (noise - high) * (0.5 + 0.5 * signf(sin(TAU * 36.0 * t))) * 0.5
				value = tanh((drone + chatter + low * 1.5) * 1.3)
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
