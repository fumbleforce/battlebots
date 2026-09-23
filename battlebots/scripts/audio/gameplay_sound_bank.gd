class_name GameplaySoundBank
extends RefCounted
## Recorded heavy impacts with small procedural cues for the remaining events.
const SAMPLES := {
	"impact_ram": "res://assets/audio/combat/metal_collision.wav",
	"impact_hammer": "res://assets/audio/combat/hammer_crash.wav",
}
const RATE := 16000
const CUES := ["impact_hammer", "impact_spinner", "impact_lifter", "impact_saw", "impact_ram",
	"countdown", "start", "round_end", "results", "low_core", "recovery", "weapon_ready", "armor_break",
	"crowd_round", "crowd_match", "credit_pickup", "impact_crush"]
const LENGTHS := [0.28, 0.20, 0.26, 0.14, 0.18, 0.10, 0.32, 0.38, 0.50, 0.28, 0.34, 0.24, 0.30, 1.0, 1.5, 0.42, 1.6]
const PITCHES := [140.0, 510.0, 230.0, 950.0, 85.0, 660.0, 440.0, 440.0, 523.25, 260.0, 330.0, 740.0, 730.0, 165.0, 190.0, 1318.51, 60.0]
## Wall-pin crush: the supplied hammer and collision recordings slowed into a
## heavier register, under a sub-bass boom, crumpling-plate crackles and a
## groan of bending steel. Mixed at the recordings' rate and saturated.
const CRUSH_RATE := 48000
const CRUSH_PEAK := 0.74
const CRUSH_HAMMER_SPEED := 0.7
const CRUSH_COLLISION_SPEED := 0.82
const CRUSH_CRACKLES := 11
var _streams: Dictionary = {}

func stream(cue: String) -> AudioStreamWAV:
	var index := CUES.find(cue)
	if index < 0:
		return null
	if _streams.has(cue):
		return _streams[cue]
	if SAMPLES.has(cue):
		var recording := load(SAMPLES[cue]).duplicate() as AudioStreamWAV
		recording.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_streams[cue] = recording
		return recording
	if cue == "impact_crush":
		_streams[cue] = _crush(LENGTHS[index], PITCHES[index])
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
		elif cue == "credit_pickup":
			# Bright coin "pling": a short E6 tap rising to a ringing B6 bell.
			var second := time >= 0.055
			var note: float = pitch * (1.4983 if second else 1.0)
			var local_time := time - (0.055 if second else 0.0)
			var tap := minf(1.0, local_time / 0.002)
			var bell := sin(TAU * note * local_time) * 0.62 + sin(TAU * note * 2.76 * local_time) * 0.20 \
				+ sin(TAU * note * 5.40 * local_time) * 0.07
			value = bell * tap * exp(-local_time * (38.0 if not second else 9.0)) * 0.34
			# Fade the ring tail so the cue ends in silence instead of a click.
			value *= minf(1.0, (1.0 - progress) / 0.15)
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

func _crush(duration: float, boom_pitch: float) -> AudioStreamWAV:
	var hammer := load(SAMPLES.impact_hammer) as AudioStreamWAV
	var collision := load(SAMPLES.impact_ram) as AudioStreamWAV
	var count := int(CRUSH_RATE * duration)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var noise_state := 90113
	# Crumple onsets: dense at impact, thinning as the hull folds.
	var crackles: Array[Vector3] = []
	for crackle: int in range(CRUSH_CRACKLES):
		noise_state = (noise_state * 1664525 + 1013904223) & 0x7fffffff
		var onset := 0.02 + 0.9 * pow(float(crackle) / CRUSH_CRACKLES, 1.6) + (noise_state % 1000) * 0.00002
		noise_state = (noise_state * 1664525 + 1013904223) & 0x7fffffff
		crackles.append(Vector3(onset, 420.0 + (noise_state % 1100), 0.5 * pow(0.86, crackle)))
	var peak := 0.0
	for sample: int in range(count):
		var time := sample / float(CRUSH_RATE)
		noise_state = (noise_state * 1664525 + 1013904223) & 0x7fffffff
		var noise := noise_state / 1073741824.0 - 1.0
		var value := _sample_at(hammer, time * CRUSH_HAMMER_SPEED) * 0.8 			+ _sample_at(collision, time * CRUSH_COLLISION_SPEED) * 0.6
		# Falling sub-bass boom with a hard front.
		var boom_phase := TAU * (boom_pitch * time - 9.0 * time * time)
		value += sin(boom_phase) * 0.55 * minf(1.0, time / 0.004) * exp(-time * 3.2)
		for crackle: Vector3 in crackles:
			var local := time - crackle.x
			if local >= 0.0 and local < 0.12:
				var ring := sin(TAU * crackle.y * local) + 0.5 * sin(TAU * crackle.y * 2.37 * local)
				value += (noise * 0.7 + ring * 0.4) * crackle.z * exp(-local * 42.0)
		# Bending steel groans in behind the impact.
		var groan := sin(TAU * (92.0 * time + 1.8 * sin(TAU * 5.3 * time)))
		value += groan * 0.14 * smoothstep(0.08, 0.3, time) * exp(-time * 2.2)
		value = tanh(value * 1.6)
		mix[sample] = value
		peak = maxf(peak, absf(value))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var fade := int(CRUSH_RATE * 0.06)
	for sample: int in range(count):
		var envelope := minf(1.0, sample / (CRUSH_RATE * 0.001)) * minf(1.0, (count - 1 - sample) / float(fade))
		pcm.encode_s16(sample * 2, roundi(mix[sample] / peak * CRUSH_PEAK * envelope * 32767.0))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = CRUSH_RATE
	result.stereo = false
	result.data = pcm
	return result

## Linearly interpolated mono PCM16 value at a time in seconds (0 past the end).
static func _sample_at(stream: AudioStreamWAV, time: float) -> float:
	var position := time * stream.mix_rate
	var index := int(position)
	var frames := stream.data.size() / 2
	if index + 1 >= frames:
		return 0.0
	var a := stream.data.decode_s16(index * 2) / 32767.0
	var b := stream.data.decode_s16(index * 2 + 2) / 32767.0
	return lerpf(a, b, position - index)
