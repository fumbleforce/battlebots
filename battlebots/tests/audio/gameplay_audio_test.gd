extends SceneTree
var failures := 0
var audio: GameplayAudio
var cues: Array[String] = []
var captions: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func match_view(phase := "active", round_number := 1, event := 3, seconds := 180.0, id := "audio-match") -> Dictionary:
	return {"match_id":id, "round":round_number, "event_id":event, "phase":phase, "remaining":seconds}

func hit(id := 1, kind := "hammer", round_number := 1, match_id := "audio-match") -> Dictionary:
	return {"match_id":match_id, "round":round_number, "event_id":id, "tick":id * 3,
		"attacker":1, "target":2, "kind":kind, "damage":36,
		"position":Vector3.ZERO, "normal":Vector3.UP}

func bot(tick: int, core := 1.0, cooldown := 0.0) -> BotView:
	var view := BotView.new()
	view.entity_id = 1
	view.server_tick = tick
	view.core_fraction = core
	view.recovery_cooldown = cooldown
	return view

func advance(seconds := 0.1) -> void:
	# Logical time controls throttle deterministically; real players remain in tree.
	audio._process(seconds)

func count(cue: String) -> int:
	return cues.count(cue)

func sound_bank() -> void:
	var bank := GameplaySoundBank.new()
	var signatures: Array[int] = []
	for cue: String in GameplaySoundBank.CUES:
		var stream := bank.stream(cue)
		check(stream != null and stream == bank.stream(cue), cue + " is cached")
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo \
			and stream.mix_rate == 16000 and stream.data.size() > 3000, cue + " has finite-length original PCM")
		var peak := 0
		for index: int in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(index)))
		check(peak > 1000 and peak <= 24576, cue + " is audible, bounded and unclipped")
		check(absi(stream.data.decode_s16(0)) < 100 and absi(stream.data.decode_s16(stream.data.size() - 2)) < 100,
			cue + " envelope has quiet endpoints")
		check(not signatures.has(hash(stream.data)), cue + " has a distinct waveform")
		signatures.append(hash(stream.data))
	check(bank.stream("unknown") == null, "Unknown sounds cannot allocate players or PCM")

func run() -> void:
	sound_bank()
	AudioPreferences.ensure_buses()
	audio = GameplayAudio.new()
	root.add_child(audio)
	audio.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	audio.caption_changed.connect(func(text: String) -> void: captions.append(text))
	check(audio.get_child_count() == 6, "Fixed four-effect/two-announcement player pools")
	for child: AudioStreamPlayer in audio.get_children():
		check(child.bus in [&"BBEffects", &"BBAnnouncements"], "Real player uses configured gameplay bus")
	audio.observe_match(match_view())
	check(cues.is_empty(), "Joining an active match does not announce a fake start")
	audio.combat_event(hit(), 1)
	check(cues == ["impact_hammer"] and captions.back() == "Hammer hit", "Authoritative local hit plays and captions")
	check(audio.get_children().any(func(player: AudioStreamPlayer) -> bool: return player.playing), "Actual AudioStreamPlayer playback started")
	advance()
	audio.combat_event(hit(), 1)
	audio.combat_event(hit(0), 1)
	check(cues.size() == 1, "Duplicate and invalid IDs remain silent")
	audio.combat_event(hit(3, "saw"), 2)
	advance()
	audio.combat_event(hit(2, "lifter"), 1)
	check(cues.size() == 2 and captions.back() == "Hit by saw", "Reordered old IDs cannot replay earlier hits")
	for field: String in ["damage", "position", "normal", "kind", "event_id", "round", "tick", "attacker"]:
		var invalid := hit(4)
		invalid[field] = NAN if field == "damage" else (Vector3(INF, 0, 0) if field in ["position", "normal"] else [])
		audio.combat_event(invalid, 1)
	check(cues.size() == 2, "Malformed/NaN/infinite event fields cannot play")
	audio.combat_event(hit(4, "hammer", 2), 1)
	audio.combat_event(hit(4, "hammer", 1, "wrong-match"), 1)
	check(cues.size() == 2, "Other round and match events cannot play")
	audio.observe_match(match_view("intermission", 1, 4, 15.0))
	check(count("round_end") == 1, "Round transition announces once")
	advance()
	audio.observe_match(match_view("intermission", 1, 4, 14.0))
	audio.observe_match(match_view("active", 1, 3))
	audio.combat_event(hit(5), 1)
	check(count("round_end") == 1 and cues.size() == 3, "Refresh/stale phase/hits after round end stay silent")
	audio.observe_match(match_view("countdown", 2, 5, 3.0))
	advance()
	audio.observe_match(match_view("countdown", 2, 5, 3.0))
	audio.observe_match(match_view("countdown", 2, 5, 2.0))
	advance()
	audio.observe_match(match_view("countdown", 2, 5, 3.0))
	audio.observe_match(match_view("countdown", 2, 5, 1.0))
	check(count("countdown") == 3, "Countdown only announces descending 3,2,1 once")
	advance()
	audio.observe_match(match_view("active", 2, 6))
	check(count("start") == 1, "Actual countdown completion announces fight")
	audio.combat_event(hit(1, "ram", 2), 1)
	check(count("impact_ram") == 1, "Fresh round permits reset event ID")
	advance()
	audio.observe_bot(bot(100, 0.2, 10.0))
	check(count("low_core") == 0 and count("recovery") == 0, "Initial damaged/recovering view stays quiet")
	audio.observe_bot(bot(101, 0.4, 9.0))
	audio.observe_bot(bot(102, 0.2, 8.0))
	check(count("low_core") == 1, "Healthy-to-low crossing announces")
	advance()
	audio.observe_bot(bot(103, 0.3, 7.0))
	audio.observe_bot(bot(104, 0.2, 6.0))
	audio.observe_bot(bot(99, 0.8, 0.0))
	audio.observe_bot(bot(105, 0.2, 5.0))
	check(count("low_core") == 1, "Hysteresis and stale ticks prevent warning spam")
	audio.observe_bot(bot(106, 0.2, 20.0))
	check(count("recovery") == 1, "New authoritative recovery cooldown edge announces")
	advance()
	audio.observe_bot(bot(106, 0.2, 20.0))
	audio.observe_bot(bot(107, 0.2, 19.0))
	check(count("recovery") == 1, "Recovery refresh/decrement does not replay")
	advance()
	audio.observe_bot(bot(108, 0.4, 18.0))
	audio.observe_bot(bot(109, 0.2, 17.0))
	check(count("low_core") == 2, "Repair above hysteresis rearms a later genuine low-core crossing")
	var before := cues.size()
	for index: int in range(2, 100): audio.combat_event(hit(index, "saw", 2), 1)
	check(cues.size() <= before + 1, "Same-frame burst is throttled")
	for index: int in range(100, 130):
		advance(0.04)
		audio.combat_event(hit(index, "vertical_spinner", 2), 1)
	check(audio.get_child_count() == 6, "Sustained effects reuse bounded voices")
	await create_timer(2.2).timeout
	check(captions.back() == "", "Caption expires through real process frames")
	audio.reset()
	check(audio.get_children().all(func(player: AudioStreamPlayer) -> bool: return not player.playing), "Leaving stops every voice")
	before = cues.size()
	audio.combat_event(hit(130, "saw", 2), 1)
	audio.observe_match(match_view("active", 2, 6))
	audio.combat_event(hit(129, "saw", 2), 1)
	check(cues.size() == before, "Reset/rejoin cannot replay already observed events")
	audio.observe_match(match_view("active", 1, 3, 180.0, "new-match"))
	audio.observe_match(match_view("active", 2, 6))
	audio.combat_event(hit(130, "saw", 2), 1)
	check(cues.size() == before, "Retired match cannot replace the current match")
	audio.reset()
	audio.observe_match(match_view("active", 1, 1, 0.0, "practice"), true)
	var practice_hit := hit(1)
	practice_hit.erase("match_id")
	audio.combat_event(practice_hit, 1)
	check(cues.size() == before + 1, "Practice supports authoritative events without network match ID")
	audio.reset()
	audio.combat_event(practice_hit, 1)
	check(cues.size() == before + 1, "Late practice event after leaving stays silent")
	audio.observe_match(match_view("active", 1, 1, 0.0, "practice"), true)
	audio.combat_event(practice_hit, 1)
	check(cues.size() == before + 2, "A new local practice world can restart its event IDs")
	audio.observe_match(match_view("active", 1, 3, 180.0, "results-match"))
	advance()
	audio.observe_match(match_view("results", 1, 4, 20.0, "results-match"))
	check(count("results") == 1, "Live-to-results transition announces completion")
	advance()
	audio.observe_match(match_view("results", 1, 4, 19.0, "results-match"))
	audio.reset()
	audio.observe_match(match_view("results", 1, 4, 18.0, "results-match"))
	check(count("results") == 1, "Results refresh and initial rejoin never replay completion")
	audio.reset()
	var starts_before := count("start")
	var ends_before := count("round_end")
	var results_before := count("results")
	audio.observe_match(match_view("countdown", 1, 1, 1.0, "fast-transitions"))
	audio.observe_match(match_view("active", 1, 2, 180.0, "fast-transitions"))
	audio.observe_match(match_view("intermission", 1, 3, 15.0, "fast-transitions"))
	audio.observe_match(match_view("countdown", 2, 4, 1.0, "fast-transitions"))
	audio.observe_match(match_view("active", 2, 5, 180.0, "fast-transitions"))
	audio.observe_match(match_view("results", 2, 6, 20.0, "fast-transitions"))
	check(count("start") == starts_before + 2 and count("round_end") == ends_before + 1 \
		and count("results") == results_before + 1 and captions.back() == "Match complete",
		"Rapid actual phase changes cannot lose critical cues or final caption to announcement throttle")
	check(audio.get_child_count() == 6, "Rapid transitions still use the bounded voice pools")
	audio.reset()
	for index: int in range(30):
		audio.observe_match(match_view("active", 1, 3, 180.0, "bounded-%d" % index))
		advance()
		audio.combat_event(hit(1, "hammer", 1, "bounded-%d" % index), 1)
	check(audio._event_watermarks.size() <= 16 and audio._retired_matches.size() <= 16,
		"Many rematches keep dedup/context storage bounded")
	audio.reset()
	audio.queue_free()
	await process_frame
	# The audio mixer releases stopped playback references on its next mix cycle.
	await create_timer(0.15).timeout
	print("GAMEPLAY AUDIO PASS" if failures == 0 else "GAMEPLAY AUDIO FAIL")
	quit(0 if failures == 0 else 1)
