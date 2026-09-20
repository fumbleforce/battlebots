extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var bank := GameplaySoundBank.new()
	var second := GameplaySoundBank.new()
	var roughness: Dictionary = {}
	for cue in ["weapon_ready", "armor_break"]:
		var sound := bank.stream(cue)
		check(sound != null and sound == bank.stream(cue), cue + " cached")
		check(sound.data == second.stream(cue).data, cue + " deterministic original PCM")
		check(sound.format == AudioStreamWAV.FORMAT_16_BITS and not sound.stereo \
			and sound.mix_rate == 16000 and sound.loop_mode == AudioStreamWAV.LOOP_DISABLED, cue + " mono one-shot format")
		var count := sound.data.size() / 2
		check(count == (3840 if cue == "weapon_ready" else 4800), cue + " bounded duration")
		var peak := 0.0
		var mean := 0.0
		var energy := 0.0
		var steps := 0.0
		var first_energy := 0.0
		var last_energy := 0.0
		var previous := 0.0
		for index in range(count):
			var value := sound.data.decode_s16(index * 2) / 32767.0
			peak = maxf(peak, absf(value))
			mean += value
			energy += value * value
			steps += (value - previous) * (value - previous)
			previous = value
			if index < count / 4: first_energy += value * value
			if index >= count * 3 / 4: last_energy += value * value
		check(peak > 0.15 and peak < 0.60, cue + " audible, bounded mixing peak")
		check(absf(mean / count) < 0.001, cue + " negligible DC")
		check(sqrt(energy / count) > 0.02, cue + " nonempty signal energy")
		check(first_energy > last_energy * 30.0, cue + " decays after transient")
		check(absi(sound.data.decode_s16(0)) < 10 and absi(sound.data.decode_s16(sound.data.size() - 2)) < 10, cue + " quiet endpoints avoid splice clicks")
		roughness[cue] = steps / energy
	check(roughness.armor_break > roughness.weapon_ready * 2.0, "Armor fracture has substantially more broadband transient energy than readiness tone")
	check(bank.stream("weapon_ready").data != bank.stream("armor_break").data, "Status cues are distinct")
	check(bank.stream("unknown_status") == null, "Unknown status has no fallback noise")
	print("STATUS_SOUND_BANK_PASS" if failures == 0 else "STATUS_SOUND_BANK_FAIL")
	quit(0 if failures == 0 else 1)
