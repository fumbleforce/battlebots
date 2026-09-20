extends Node3D
## Real native mixer and commanded Jolt walking, with silent lifecycle baselines.
var failures: Array[String] = []
var session: MvpSession
var capture: AudioEffectCapture
var bus := -1
var capture_bus := -1
var other_bus := -1
var landings: Array[Dictionary] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count: int, throttle := 0.0) -> void:
	for index: int in count:
		var command := BotCommand.new()
		command.throttle = throttle
		command.brake = throttle == 0.0
		session.submit_local(command)
		await get_tree().physics_frame
		await get_tree().process_frame

func mixed_energy() -> Vector2:
	var result := Vector2.ZERO
	for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
		check(sample.is_finite(), "Native footfall mix remains finite")
		result += sample * sample
	return result

func sample_checks() -> void:
	var recording := load(ScorpionFootfallAudio.SAMPLE) as AudioStreamWAV
	check(recording.format == AudioStreamWAV.FORMAT_16_BITS and not recording.stereo \
		and recording.mix_rate == 48000 and recording.data.size() == 48000,
		"Footfall keeps the selected half-second mono 48k PCM recording")
	var peak := 0
	var onset := -1
	for frame: int in recording.data.size() / 2:
		var value := absi(recording.data.decode_s16(frame * 2))
		peak = maxi(peak, value)
		if onset < 0 and value > 12000: onset = frame
	check(peak >= 19659 and peak <= 19661, "Footfall retains 0.60 peak headroom without clipping")
	check(onset > 0 and onset < 1440, "Heavy plant onset aligns within 30ms of foot contact")
	check(recording.data.decode_s16(0) == 0 and recording.data.decode_s16(recording.data.size()-2) == 0,
		"Footfall endpoints have click-free fades")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run Scorpion footfall integration with native rendering/audio")
		get_tree().quit(1)
		return
	sample_checks()
	AudioPreferences.ensure_buses()
	bus = AudioServer.get_bus_index("BBEffects")
	AudioServer.set_bus_volume_db(bus, 0.0)
	capture_bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(capture_bus, -80.0)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 8.0
	# Master capture receives the Effects bus after its user-controlled gain.
	AudioServer.add_bus_effect(capture_bus, capture)
	get_viewport().audio_listener_enable_3d = true
	session = MvpSession.new()
	add_child(session)
	check(session.practice(session.registry.scorpion()) == OK, "Native Scorpion practice starts")
	var player := session.local_source() as MvpBot
	var legs := player.scorpion_visual.walker_legs
	var sound := legs.footfall_audio
	# NPC guns keep their normal authority and animation, but their unrelated
	# reports must not contaminate this isolated footfall pan/volume measurement.
	AudioServer.add_bus()
	other_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(other_bus, &"FootfallTestOtherVoices")
	AudioServer.set_bus_mute(other_bus, true)
	for voice: AudioStreamPlayer3D in session.world.find_children("*", "AudioStreamPlayer3D", true, false):
		if voice not in sound.players: voice.bus = &"FootfallTestOtherVoices"
	legs.planted.connect(func(at: Vector3, contacts: int) -> void: landings.append({"at":at,"contacts":contacts}))
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = player.spawn_pose.origin + Vector3(0, 5, 10)
	camera.look_at(player.spawn_pose.origin + Vector3.UP)
	camera.make_current()
	await frames(90)
	check(sound.played_count == 0 and landings.is_empty(), "Spawning and idle suspension settling invent no footsteps")
	check(sound.players.size() == 2 and sound.get_child_count() == 2, "Each Scorpion owns exactly two reusable spatial voices")
	for voice: AudioStreamPlayer3D in sound.players:
		check(voice.bus == &"BBEffects" and voice.volume_db == -9.0 and not voice.playing,
			"Idle footfall voices respect the effects bus and mix level")
	capture.clear_buffer()
	var start := player.body.global_position
	await frames(150, 0.75)
	var energy := mixed_energy()
	check(player.body.global_position.distance_to(start) > 2.0, "Normal drive commands move the live walker")
	check(sound.played_count >= 3 and energy.x + energy.y > 0.01, "Completed live leg plants produce actual native stereo mix")
	check(landings.any(func(item: Dictionary) -> bool: return item.contacts == 3) \
		and landings.all(func(item: Dictionary) -> bool: return item.contacts >= 1 and item.contacts <= 3),
		"Simultaneous grounded tripod plants combine into one impact, excluding feet without terrain contact")
	check(sound.get_child_count() == 2, "Sustained walking does not allocate more audio voices")
	await frames(90)
	var stopped_count := sound.played_count
	await frames(35)
	check(sound.played_count == stopped_count, "Stationary planted feet stay silent after the last step")
	# Restart during a genuine lifted step, including an immediate second reset at
	# the same pose: neither may mistake foot baseline restoration for landing.
	for index: int in 90:
		await frames(1, 0.75)
		if legs.legs.any(func(leg: Dictionary) -> bool: return leg.time < 1.0): break
	var before_reset := sound.played_count
	check(session.restart_practice() == OK, "Practice restarts during a live step")
	check(sound.players.all(func(voice: AudioStreamPlayer3D) -> bool: return not voice.playing), "Restart immediately stops pending footfall tails")
	await frames(60)
	check(sound.played_count == before_reset, "Restart neither completes old steps nor emits spawn plants")
	check(session.restart_practice() == OK, "Same-position restart succeeds")
	await frames(45)
	check(sound.played_count == before_reset, "Same-position reset remains silent")
	# Garage and absent terrain are presentation fixtures, using the real solver.
	legs.terrain = false
	await frames(50, 0.6)
	check(sound.played_count == before_reset, "Garage-style terrain-disabled movement remains silent")
	legs.terrain = true
	legs.reset_feet()
	await frames(45)
	var before_teleport := sound.played_count
	player.body.reset_pose = Transform3D(Basis.IDENTITY, player.body.global_position + Vector3(9, 0, 0))
	await frames(3)
	check(sound.played_count == before_teleport, "Teleport rebaselines feet without an impact")
	# The same recorded voices used by a remote visual remain fully positional.
	legs.set_process(false)
	sound.reset()
	await get_tree().create_timer(0.6).timeout
	capture.clear_buffer()
	sound.advance(1.0)
	sound.plant(camera.global_position + camera.global_basis * Vector3(-4, -1, -4))
	await get_tree().create_timer(0.55).timeout
	var left := mixed_energy()
	capture.clear_buffer()
	sound.advance(1.0)
	sound.plant(camera.global_position + camera.global_basis * Vector3(4, -1, -4))
	await get_tree().create_timer(0.55).timeout
	var right := mixed_energy()
	check(left.x > left.y * 1.2 and right.y > right.x * 1.2, "Native captured footfalls pan toward their planted world position")
	AudioServer.set_bus_volume_linear(bus, 0.0)
	await get_tree().create_timer(0.1).timeout
	capture.clear_buffer()
	sound.advance(1.0)
	sound.plant(camera.global_position + camera.global_basis * Vector3(0, 0, -3))
	await get_tree().create_timer(0.55).timeout
	check(mixed_energy().length_squared() < 0.000001, "Effects volume zero silences actual footfall mixer output")
	AudioServer.set_bus_volume_linear(bus, 1.0)
	print("SCORPION FOOTFALL CAPTURE walking=%s left=%s right=%s plants=%d" % [energy,left,right,sound.played_count])
	session.leave()
	await get_tree().process_frame
	check(not is_instance_valid(sound), "Leaving releases the footfall voices with the bot")
	AudioServer.remove_bus_effect(capture_bus, 0)
	AudioServer.remove_bus(other_bus)
	session.queue_free()
	await get_tree().process_frame
	for failure: String in failures: push_error(failure)
	print("SCORPION FOOTFALL PASS" if failures.is_empty() else "SCORPION FOOTFALL FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
