extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var bank := GameplayLoopBank.new()
	var other := GameplayLoopBank.new()
	var signatures: Array[int] = []
	for cue: String in GameplayLoopBank.CUES:
		var sound := bank.stream(cue)
		check(sound != null and sound == bank.stream(cue), cue + " cache reuses stream")
		check(sound != other.stream(cue) and sound.data == other.stream(cue).data, cue + " independent banks provide identical private PCM")
		check(sound.format == AudioStreamWAV.FORMAT_16_BITS and not sound.stereo \
			and sound.mix_rate == (48000 if cue == "saw" else 16000), cue + " PCM format")
		var count := sound.data.size() / 2
		check(count == (50880 if cue == "saw" else 32000) and sound.loop_mode == AudioStreamWAV.LOOP_FORWARD \
			and sound.loop_begin == 0 and sound.loop_end == count, cue + " full loop uses sample-frame bounds")
		if cue == "saw":
			var source := load("res://assets/audio/combat/heavy_saw_loop.wav") as AudioStreamWAV
			check(sound != source and sound.data == source.data, "Saw loop uses a private copy of the adapted recording")
			check(is_equal_approx(sound.get_length(), 1.06), "Saw keeps the crossfaded recording length")
		var peak := 0.0
		var mean := 0.0
		var energy := 0.0
		var max_step := 0.0
		var max_bend := 0.0
		var samples := PackedFloat32Array()
		for index: int in range(count):
			var value := sound.data.decode_s16(index * 2) / 32767.0
			samples.append(value)
			peak = maxf(peak, absf(value))
			mean += value
			energy += value * value
			if index > 0:
				max_step = maxf(max_step, absf(value - samples[index - 1]))
			if index > 1:
				max_bend = maxf(max_bend, absf(value - 2.0 * samples[index - 1] + samples[index - 2]))
		check(peak >= 0.10 and peak <= 0.39, cue + " audible peak leaves mixing headroom")
		check(absf(mean / count) < 0.00001, cue + " negligible DC offset")
		check(sqrt(energy / count) > 0.02 and sqrt(energy / count) < 0.25, cue + " useful sustained energy")
		# The seam must behave like normal adjacent samples, including slope changes.
		check(absf(samples[0] - samples[-1]) <= max_step * 1.02 + 0.0001, cue + " no boundary jump")
		check(absf(samples[0] - 2.0 * samples[-1] + samples[-2]) <= max_bend * 1.02 + 0.0001, cue + " incoming boundary slope")
		check(absf(samples[1] - 2.0 * samples[0] + samples[-1]) <= max_bend * 1.02 + 0.0001, cue + " outgoing boundary slope")
		var signature := hash(sound.data)
		check(not signatures.has(signature), cue + " has distinct texture")
		signatures.append(signature)
	check(bank.stream("missing") == null and bank.stream("") == null, "unknown cues are silent")
	if failures == 0:
		print("GAMEPLAY_LOOP_BANK_PASS")
	quit(0 if failures == 0 else 1)
