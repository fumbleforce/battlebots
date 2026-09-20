extends SceneTree
var failures := 0
var cues: Array[String] = []
var captions: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func match_view(phase: String, event: int, round_number := 1, id := "crowd") -> Dictionary:
	return {"match_id": id, "round": round_number, "event_id": event, "phase": phase, "remaining": 15.0}

func run() -> void:
	AudioPreferences.ensure_buses()
	var effects := AudioServer.get_bus_index("BBEffects")
	AudioServer.set_bus_volume_db(effects, -11.0)
	var audio := GameplayAudio.new()
	root.add_child(audio)
	audio.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	audio.caption_changed.connect(func(caption: String) -> void: captions.append(caption))
	var crowd := audio._crowd
	audio.observe_match(match_view("results", 5))
	check(not crowd.playing and cues.is_empty(), "Initial results/rejoin has no fake crowd reaction")
	audio.reset()
	audio.observe_match(match_view("active", 1))
	audio.observe_match(match_view("intermission", 2))
	check(crowd.playing and crowd.stream == audio._bank.stream("crowd_round")
		and cues.count("crowd_round") == 1, "Genuine round outcome plays bounded round reaction")
	check(crowd.bus == &"BBEffects" and crowd.volume_db < audio.CROWD_DB, "Crowd uses effects volume and ducks under announcement")
	check(captions.back() == "Round complete", "Crowd does not overwrite the meaningful outcome caption")
	audio._process(0.6)
	check(crowd.volume_db == audio.CROWD_DB and AudioServer.get_bus_volume_db(effects) == -11.0, "Local duck restores without changing user bus gain")
	audio.observe_match(match_view("intermission", 2))
	audio.observe_match(match_view("active", 1))
	check(cues.count("crowd_round") == 1, "Repeated and stale phases cannot replay crowd")
	audio.observe_match(match_view("countdown", 3, 2))
	check(not crowd.playing, "Next round stops the preceding reaction")
	audio.observe_match(match_view("active", 4, 2))
	audio.observe_match(match_view("results", 5, 2))
	check(crowd.playing and crowd.stream == audio._bank.stream("crowd_match")
		and cues.count("crowd_match") == 1 and captions.back() == "Match complete", "Final outcome uses distinct match reaction and preserves caption")
	audio.observe_match(match_view("results", 5, 2))
	check(audio._crowd == crowd and audio.get_child_count() == 8 and cues.count("crowd_match") == 1, "Results refresh reuses single crowd voice without replay")
	audio.observe_match(match_view("active", 1, 1, "another-match"))
	check(not crowd.playing, "New match cannot retain old crowd playback")
	audio.observe_match(match_view("results", 5, 2))
	check(not crowd.playing, "Retired match cannot trigger crowd")
	audio.reset()
	audio.observe_match(match_view("active", 1, 1, "practice"), true)
	audio.observe_match(match_view("results", 2, 1, "practice"), true)
	check(not crowd.playing, "Practice does not invent a competitive crowd outcome")
	await create_timer(0.6).timeout
	audio.reset()
	check(not crowd.playing and captions.back().is_empty(), "Leave clears reaction and captions")
	audio.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("CROWD AUDIO PASS" if failures == 0 else "CROWD AUDIO FAIL")
	quit(0 if failures == 0 else 1)
