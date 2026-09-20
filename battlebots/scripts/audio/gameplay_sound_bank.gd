class_name GameplaySoundBank
extends RefCounted
## Original, deliberately small procedural first-pass sounds. No imported samples.
const RATE := 16000
const CUES := ["impact_hammer", "impact_spinner", "impact_lifter", "impact_saw", "impact_ram",
	"countdown", "start", "round_end", "results", "low_core", "recovery", "weapon_ready", "armor_break",
	"crowd_round", "crowd_match"]
const LENGTHS := [0.28, 0.20, 0.26, 0.14, 0.18, 0.10, 0.32, 0.38, 0.50, 0.28, 0.34, 0.24, 0.30, 1.0, 1.5]
const PITCHES := [140.0, 510.0, 230.0, 950.0, 85.0, 660.0, 440.0, 440.0, 523.25, 260.0, 330.0, 740.0, 730.0, 165.0, 190.0]
var _streams: Dictionary = {}

func stream(cue: String) -> AudioStreamWAV:
	var index := CUES.find(cue)
	if index < 0:
		return null
	if _streams.has(cue):
		return _streams[cue]
	var duration: float = LENGTHS[index]
	var pitch: float = PITCHES[index]
	var count := int(RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var noise_state := 1259 + index * 877
	var crowd_low := 0.0
	var crowd_high := 0.0
	for sample: int in range(count):
		var time := sample / float(RATE)
		var progress := sample / float(count)
		var attack := minf(1.0, time / 0.003)
		var envelope := attack * pow(1.0 - progress, 2.0)
		noise_state = (noise_state * 1664525 + 1013904223) & 0x7fffffff
		var noise := noise_state / 1073741824.0 - 1.0
		var value: float
		if index < 5:
			# Inharmonic ringing plus a brief noisy contact transient.
			var ring := sin(TAU * pitch * time) * 0.50 + sin(TAU * pitch * 2.71 * time) * 0.22
			var rasp := noise * (0.15 if cue == "impact_saw" else 0.32) * exp(-time * 28.0)
			if cue == "impact_spinner":
				ring *= 0.65 + 0.35 * sin(TAU * 45.0 * time)
			elif cue == "impact_lifter":
				ring = sin(TAU * (pitch * time + 350.0 * time * time)) * 0.6
			elif cue == "impact_saw":
				ring = (sin(TAU * pitch * time) + 0.3 * sin(TAU * pitch * 3.0 * time)) * 0.40
			value = (ring + rasp) * envelope * 0.55
		elif cue in ["crowd_round", "crowd_match"]:
			# A nonlinguistic group swell: detuned voices over a breathy noise bed.
			# Separate low-pass states form a broad band-pass with little bass/DC.
			crowd_low += (noise - crowd_low) * 0.55
			crowd_high += (noise - crowd_high) * 0.055
			var chorus := 0.0
			for voice: int in range(12):
				var fundamental := pitch + voice * 11.73
				var bend := 13.0 * time * time / duration
				var phase := TAU * (fundamental * time + bend) + voice * 2.39
				var flutter := 0.65 + 0.35 * sin(TAU * (3.1 + voice * 0.17) * time + voice)
				chorus += (sin(phase) * 0.5 + sin(phase * 3.0) * 0.3 + sin(phase * 5.0) * 0.2) * flutter / 12.0
			var swell := smoothstep(0.0, 0.14, progress) * pow(1.0 - progress, 0.85)
			var breath := (crowd_low - crowd_high) * (0.65 + 0.15 * sin(TAU * 6.7 * time))
			value = (chorus + breath) * swell * (0.48 if cue == "crowd_match" else 0.40)
		elif cue == "armor_break":
			# A short fracture crack followed by irregular metallic resonances.
			var crack := noise * 0.78 * exp(-time * 65.0)
			var shards := sin(TAU * pitch * time) * 0.23 * exp(-time * 11.0) \
				+ sin(TAU * 1907.0 * time) * 0.19 * exp(-time * 17.0) \
				+ sin(TAU * 3181.0 * time) * 0.11 * exp(-time * 24.0)
			value = (crack + shards) * envelope * 0.55
		elif cue == "weapon_ready":
			# A consonant, compact confirmation, distinct from damage transients.
			value = (sin(TAU * pitch * time) * 0.75 \
				+ sin(TAU * pitch * 1.5 * time) * 0.25) * envelope * 0.32
		else:
			var phase: float = pitch * time
			if cue in ["start", "recovery"]:
				phase += 350.0 * time * time
			elif cue == "round_end":
				phase -= 240.0 * time * time
			elif cue == "results":
				phase += 200.0 * time * time
			value = sin(TAU * phase) * envelope * 0.36
			if cue == "low_core":
				value *= 1.0 if fmod(time, 0.14) < 0.085 else 0.0
		pcm.encode_s16(sample * 2, roundi(clampf(value, -0.75, 0.75) * 32767.0))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = RATE
	result.stereo = false
	result.data = pcm
	_streams[cue] = result
	return result
