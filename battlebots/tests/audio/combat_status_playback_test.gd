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

func view(tick: int, charge := 0.0) -> BotView:
	var result := BotView.new()
	result.entity_id = 1
	result.server_tick = tick
	result.zones = {"front": 100.0, "rear": 100.0, "left": 100.0, "right": 100.0}
	result.weapon_charge_fraction = charge
	result.weapon_state = &"active"
	return result

func run() -> void:
	AudioPreferences.ensure_buses()
	var audio := GameplayAudio.new()
	root.add_child(audio)
	audio.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	audio.caption_changed.connect(func(caption: String) -> void: captions.append(caption))
	var match_view := {"match_id": "status", "round": 1, "event_id": 1, "phase": "active", "remaining": 180.0}
	audio.observe_match(match_view)
	audio.observe_bot(view(1, 1.0), "vertical_spinner")
	check(cues.is_empty(), "Initial full speed does not invent a readiness edge")
	audio.observe_bot(view(2, 0.2), "vertical_spinner")
	audio.observe_bot(view(3, 1.0), "vertical_spinner")
	check(cues == ["weapon_ready"] and captions.back() == "Spinner at full speed", "New full-speed edge plays and captions")
	var damaged := view(4, 1.0)
	damaged.zones.front = 0.0
	damaged.zones.left = 0.0
	damaged.core_fraction = 0.2
	damaged.recovery_cooldown = 20.0
	audio.observe_bot(damaged, "vertical_spinner")
	check(cues.count("low_core") == 1 and cues.count("recovery") == 1 and cues.count("armor_break") == 1,
		"Simultaneous core, recovery and armor edges are not dropped by announcement throttle")
	for cue: String in ["low_core", "recovery", "armor_break"]:
		check(audio._announcements.any(func(player: AudioStreamPlayer) -> bool:
			return player.playing and player.stream == audio._bank.stream(cue)),
			"Concurrent warning remains on an active voice: " + cue)
	check(captions.back().contains("Core integrity low") and captions.back().contains("Recovery activated")
		and captions.back().to_lower().contains("front") and captions.back().to_lower().contains("left"),
		"Combined critical caption retains all simultaneous warning details")
	var critical_caption: String = captions.back()
	var rearm := view(5, 0.2)
	rearm.zones = damaged.zones.duplicate()
	rearm.core_fraction = 0.2
	rearm.recovery_cooldown = 19.0
	audio.observe_bot(rearm, "vertical_spinner")
	rearm.server_tick = 6
	rearm.weapon_charge_fraction = 1.0
	audio.observe_bot(rearm, "vertical_spinner")
	check(captions.back() == critical_caption and cues.count("weapon_ready") == 1, "Critical feedback suppresses a competing positive readiness cue")
	audio.observe_bot(damaged, "vertical_spinner")
	check(cues.count("armor_break") == 1, "Old ticks do not replay armor warning")
	audio.observe_bot(null)
	damaged.server_tick = 7
	audio.observe_bot(damaged, "vertical_spinner")
	check(cues.count("armor_break") == 1 and cues.count("low_core") == 1, "Fresh baseline after unavailable data is silent")
	match_view.round = 2
	match_view.event_id = 2
	audio.observe_match(match_view)
	audio.observe_bot(view(8), "vertical_spinner")
	var second_break := view(9)
	second_break.zones.front = 0.0
	audio.observe_bot(second_break, "vertical_spinner")
	check(cues.count("armor_break") == 2, "A new round re-arms its repaired armor")
	audio._process(2.1)
	audio.observe_bot(view(10, 0.0), "saw")
	audio.observe_bot(view(11, 1.0), "saw")
	var ready_count := cues.count("weapon_ready")
	audio.observe_bot(view(12, 0.0), "saw")
	audio.observe_bot(view(13, 1.0), "saw")
	check(cues.count("weapon_ready") == ready_count, "Rapid power toggles cannot spam readiness audio")
	audio._process(0.8)
	audio.observe_bot(view(14, 0.0), "saw")
	audio.observe_bot(view(15, 1.0), "saw")
	check(cues.count("weapon_ready") == ready_count + 1, "Later genuine power edge can sound again")
	check(audio.get_child_count() == 7, "Status cues use fixed four-effect/three-announcement pools")
	# Let the real mixer consume the rapid controlled transitions before teardown.
	await create_timer(0.6).timeout
	audio.reset()
	check(captions.back().is_empty(), "Leave clears combined status captions")
	audio.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("COMBAT STATUS PLAYBACK PASS" if failures == 0 else "COMBAT STATUS PLAYBACK FAIL")
	quit(0 if failures == 0 else 1)
