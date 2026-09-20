extends SceneTree
## Capture the engine's stereo mix, not only player configuration.
var failures := 0
var sequence := 0
var audio: GameplayAudio
var capture: AudioEffectCapture
var effects_bus := -1

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func event(position := Vector3(-3, 0, -4)) -> Dictionary:
	sequence += 1
	return {"match_id": "spatial-impact", "round": 1, "event_id": sequence, "tick": sequence,
		"attacker": 1, "target": 2, "kind": "hammer", "damage": 36.0,
		"position": position, "normal": Vector3.UP}

func shoot(item: Dictionary) -> void:
	audio._process(0.1)
	audio.combat_event(item, 1)

func energy(position: Vector3) -> Vector2:
	for player in audio._effects:
		player.stop()
	audio._crowd.stop()
	# Drain the previous event's pending audio-thread mix before clearing capture.
	await create_timer(0.12).timeout
	capture.clear_buffer()
	shoot(event(position))
	await create_timer(0.55).timeout
	var count := capture.get_frames_available()
	check(count > 1000, "Engine capture supplies mixed stereo samples")
	var samples := capture.get_buffer(count)
	var result := Vector2.ZERO
	for sample in samples:
		check(sample.is_finite(), "Mixed audio remains finite")
		result.x += sample.x * sample.x
		result.y += sample.y * sample.y
	return result

func run() -> void:
	AudioPreferences.ensure_buses()
	effects_bus = AudioServer.get_bus_index("BBEffects")
	AudioServer.set_bus_volume_db(effects_bus, 0.0)
	# Mute at the output bus only; the effect bus capture remains before Master.
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -80.0)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(effects_bus, capture)
	root.audio_listener_enable_3d = true
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.make_current()
	# A translated parent exposes erroneous local assignment of event positions.
	scene.position = Vector3(12, 0, 0)
	camera.global_position = Vector3.ZERO
	audio = GameplayAudio.new()
	scene.add_child(audio)
	audio.set_process(false)
	audio.observe_match({"match_id": "spatial-impact", "round": 1, "event_id": 1, "phase": "active", "remaining": 180.0})
	check(audio._effects.size() == 4 and audio.get_child_count() == 8, "Impact and announcement pools remain bounded")
	var ids: Array[int] = []
	for player in audio._effects:
		check(player is AudioStreamPlayer3D and player.bus == &"BBEffects", "Impacts use the spatial effects bus")
		ids.append(player.get_instance_id())
	for index in 10:
		var item := event(Vector3(index, 2, -5))
		shoot(item)
		var player: AudioStreamPlayer3D = audio._effects[index % 4]
		check(player.global_position == item.position, "Accepted event uses world position under translated parent")
	check(audio.get_child_count() == 8, "Repeated impacts allocate no extra players")
	for index in 4:
		check(audio._effects[index].get_instance_id() == ids[index], "Voice pool instances are reused")
	var cursor: int = audio._effect_cursor
	for bad in [{"position": Vector3(NAN, 0, 0)}, {"position": "wrong"}, {"event_id": 1}, {"round": 2}, {"match_id": "other"}, {"kind": "unknown"}]:
		var item := event()
		item.merge(bad, true)
		shoot(item)
		check(audio._effect_cursor == cursor, "Malformed or stale events cannot advance pool")
	var left := await energy(Vector3(-4, 0, -4))
	var right := await energy(Vector3(4, 0, -4))
	var near := await energy(Vector3(0, 0, -3))
	var far := await energy(Vector3(0, 0, -35))
	print("SPATIAL_IMPACT_CAPTURE left=%s right=%s near=%s far=%s" % [left, right, near, far])
	check(left.x + left.y > 0.00001 and right.x + right.y > 0.00001, "Captured impact signals are nonzero")
	check(left.x > left.y * 1.2, "Left impact has stronger captured left channel")
	check(right.y > right.x * 1.2, "Right impact has stronger captured right channel")
	check(near.x + near.y > (far.x + far.y) * 4.0, "Far impact is quieter in captured mix at unchanged voice gain")
	shoot(event())
	audio.reset()
	for player in audio._effects:
		check(not player.playing, "Reset stops all spatial impacts")
	AudioServer.remove_bus_effect(effects_bus, 0)
	scene.queue_free()
	audio = null
	capture = null
	await process_frame
	print("SPATIAL_IMPACT_AUDIO_PASS" if failures == 0 else "SPATIAL_IMPACT_AUDIO_FAIL")
	quit(0 if failures == 0 else 1)
