extends SceneTree
var failures := 0
var audio: ContinuousGameplayAudio

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func record(id := 1, weapon := "vertical_spinner") -> Dictionary:
	return {"entity_id": id, "tick": 10, "position": Vector3(3, 0, 4),
		"pose": Transform3D.IDENTITY, "velocity": Vector3.ZERO, "angular": Vector3.ZERO,
		"drive_input": 0.0, "turn_input": 0.0, "grounded": true, "weapon": weapon,
		"charge": 0.0, "eliminated": false, "age": 0.0}

func voice(id: int, layer: String) -> AudioStreamPlayer3D:
	return audio._bots[id].get_node(layer)

func run() -> void:
	audio = ContinuousGameplayAudio.new()
	root.add_child(audio)
	audio.set_process(false)
	var r := record()
	audio.render([r], true)
	check(audio._pool.size() == 2 and audio.get_child_count() == 3, "Fixed two rigs and one ambience player")
	check(not voice(1, "drive").playing and not voice(1, "weapon").playing, "Idle stationary bot is silent")
	check(audio._arena.playing, "Accepted match starts arena ambience")
	r.drive_input = 0.8
	r.position = Vector3(8, 1, 2)
	audio.render([r], true)
	var motor := voice(1, "drive")
	check(motor.playing and audio._bots[1].global_position == r.position, "Motor follows physical demand at presentation position")
	var stream := motor.stream
	var rig: Node3D = audio._bots[1]
	audio.render([r], true)
	check(voice(1, "drive") == motor and motor.stream == stream and audio._bots[1] == rig, "Rendering reuses voices and streams")
	r.drive_input = 0.0
	r.velocity = Vector3(4, 0, 0)
	audio.render([r], true)
	check(voice(1, "skid").playing, "Grounded lateral motion creates sliding cue")
	r.grounded = false
	audio.render([r], true)
	check(not voice(1, "skid").playing, "Airborne lateral motion has no skid")
	r.velocity = Vector3(3, -20, 2)
	r.angular = Vector3(1, 2, 3)
	audio.render([r], true)
	check(not voice(1, "drive").playing, "Undriven airborne motion cannot create motor noise")
	r.drive_input = 0.5
	audio.render([r], true)
	check(voice(1, "drive").playing, "Airborne drive demand still powers motor")
	r.drive_input = 0.0
	r.velocity = Vector3.ZERO
	r.angular = Vector3.ZERO
	r.charge = 0.4
	audio.render([r], true)
	check(voice(1, "weapon").playing, "Spinner coast remains audible without drive demand")
	var low_pitch := voice(1, "weapon").pitch_scale
	r.charge = 0.9
	audio.render([r], true)
	check(voice(1, "weapon").pitch_scale > low_pitch, "Spinner charge changes pitch")
	for family in ["hammer", "lifter"]:
		r.weapon = family
		audio.render([r], true)
		check(not voice(1, "weapon").playing, family + " readiness does not make rotor noise")
	r.weapon = "saw"
	r.charge = 0.1
	audio.render([r], true)
	var saw_pitch := voice(1, "weapon").pitch_scale
	r.charge = 1.0
	audio.render([r], true)
	check(voice(1, "weapon").playing and voice(1, "weapon").pitch_scale == saw_pitch, "Saw uses binary power")
	var bus := AudioServer.get_bus_index("BBEffects")
	var bus_db := AudioServer.get_bus_volume_db(bus)
	audio.duck(0.2)
	check(audio._arena.volume_db == audio.ARENA_DB - 9.0, "Announcement ducks arena locally")
	audio._process(0.21)
	check(audio._arena.volume_db == audio.ARENA_DB and AudioServer.get_bus_volume_db(bus) == bus_db, "Duck restores without changing user bus")
	audio.render([r, record(2), record(3)], true)
	check(audio._bots.size() == 2 and audio._pool.size() == 2, "Extra bots cannot allocate voices")
	audio.render([r, r], true)
	check(audio._bots.is_empty(), "Duplicate IDs silence ambiguous records")
	for key in ["age", "charge", "pose", "position", "grounded", "entity_id", "weapon"]:
		var bad := record()
		bad[key] = null
		audio.render([bad], true)
		check(audio._bots.is_empty(), "Reject malformed " + key)
	for bad in [{"age": 0.251}, {"age": -1.0}, {"charge": NAN}, {"velocity": Vector3(INF, 0, 0)}, {"eliminated": true}]:
		var item := record()
		item.merge(bad, true)
		audio.render([item], true)
		check(audio._bots.is_empty(), "Reject stale, nonfinite or eliminated state")
	audio.render([r], true)
	var old := r.duplicate()
	old.tick = 9
	audio.render([old], true)
	check(audio._bots.is_empty(), "Backward accepted tick silences the layer")
	audio.render([r], true)
	audio._process(0.251)
	check(audio._bots.is_empty() and not audio._arena.playing, "Missing render refresh expires audio")
	audio.render([r], true)
	audio.render([], true)
	check(audio._bots.is_empty() and not audio._arena.playing, "Removed entities stop voices")
	audio.render([r], true)
	audio.render([r], false)
	check(audio._bots.is_empty() and not audio._arena.playing, "Menu transition stops all continuous audio")
	for pooled in audio._pool:
		for player in pooled.get_children():
			check(not player.playing, "No pooled voice leaks after silence")
	audio.render([r], true)
	check(voice(1, "weapon").playing and audio._arena.playing, "Resume restarts retained loop streams")
	audio.reset()
	audio.queue_free()
	audio = null
	await process_frame
	print("CONTINUOUS_GAMEPLAY_AUDIO_TEST: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
