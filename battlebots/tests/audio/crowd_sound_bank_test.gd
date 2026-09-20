extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var bank := GameplaySoundBank.new()
	var independent := GameplaySoundBank.new()
	var bytes := 0
	for cue in ["crowd_round", "crowd_match"]:
		var sound := bank.stream(cue)
		check(sound == bank.stream(cue) and sound.data == independent.stream(cue).data, cue + " cached deterministic original texture")
		check(sound.format == AudioStreamWAV.FORMAT_16_BITS and sound.mix_rate == 16000 \
			and not sound.stereo and sound.loop_mode == AudioStreamWAV.LOOP_DISABLED, cue + " mono one-shot")
		var count := sound.data.size() / 2
		check(count == (16000 if cue == "crowd_round" else 24000), cue + " bounded one/one-and-half second reaction")
		bytes += sound.data.size()
		var peak := 0.0
		var mean := 0.0
		var energy := 0.0
		var beginning := 0.0
		var middle := 0.0
		var ending := 0.0
		var changes := 0
		var previous := 0.0
		for index in range(count):
			var value := sound.data.decode_s16(index * 2) / 32767.0
			peak = maxf(peak, absf(value))
			mean += value
			energy += value * value
			if index < count / 20: beginning += value * value
			if index >= count / 4 and index < count * 3 / 10: middle += value * value
			if index >= count * 19 / 20: ending += value * value
			if value * previous < 0.0: changes += 1
			previous = value
		check(peak > 0.05 and peak < 0.50, cue + " audible bounded mix level")
		check(absf(mean / count) < 0.001, cue + " negligible DC")
		check(sqrt(energy / count) > 0.015, cue + " sustained reaction energy")
		check(middle > beginning * 8.0 and middle > ending * 8.0, cue + " smooth onset and decaying tail")
		check(changes > count / 10, cue + " breathy broadband texture")
		check(absi(sound.data.decode_s16(0)) < 100 and absi(sound.data.decode_s16(sound.data.size() - 2)) < 100, cue + " quiet endpoints")
	check(bank.stream("crowd_round").data != bank.stream("crowd_match").data.slice(0, 32000), "Match reaction is distinct, not an extended round copy")
	for iteration in range(50):
		bank.stream("crowd_round")
		bank.stream("crowd_match")
		bank.stream("invalid_crowd_" + str(iteration))
	check(bank._streams.size() == 2 and bytes == 80000, "Repeated/unknown requests retain only two bounded PCM streams")
	print("CROWD_SOUND_BANK_PASS" if failures == 0 else "CROWD_SOUND_BANK_FAIL")
	quit(0 if failures == 0 else 1)
