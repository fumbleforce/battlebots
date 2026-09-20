class_name GameplayLoopBank
extends RefCounted
## Recorded saw loop and procedural industrial textures; playback follows accepted state.
const RATE := 16000
const SECONDS := 2
const CUES := ["drive", "skid", "spinner", "saw", "arena"]
const PEAKS := [0.38, 0.28, 0.34, 0.30, 0.14]
var _streams: Dictionary = {}

func stream(cue: String) -> AudioStreamWAV:
	var index := CUES.find(cue)
	if index < 0:
		return null
	if _streams.has(cue):
		return _streams[cue]
	if cue == "saw":
		var recording := load("res://assets/audio/combat/heavy_saw_loop.wav").duplicate() as AudioStreamWAV
		recording.loop_mode = AudioStreamWAV.LOOP_FORWARD
		recording.loop_begin = 0
		recording.loop_end = recording.data.size() / 2 # Prepared mono PCM16, sample units.
		_streams[cue] = recording
		return recording
	var count := RATE * SECONDS
	var samples := PackedFloat32Array()
	samples.resize(count)
	var partials := _partials(cue)
	var peak := 0.0
	var mean := 0.0
	for sample: int in range(count):
		var time := sample / float(RATE)
		var value := 0.0
		for partial: Vector3 in partials:
			value += sin(TAU * partial.x * time + partial.z) * partial.y
		# Integer-frequency modulation preserves the exact two-second period.
		if cue == "drive":
			value *= 0.86 + 0.14 * cos(TAU * 12.0 * time)
		elif cue == "spinner":
			value *= 0.80 + 0.20 * cos(TAU * 24.0 * time)
		elif cue == "saw":
			value *= 0.74 + 0.26 * cos(TAU * 37.0 * time)
		elif cue == "arena":
			value *= 0.88 + 0.12 * cos(TAU * 0.5 * time)
		samples[sample] = value
		mean += value
	mean /= count
	for value: float in samples:
		peak = maxf(peak, absf(value - mean))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var gain: float = PEAKS[index] / maxf(peak, 0.000001)
	for sample: int in range(count):
		pcm.encode_s16(sample * 2, roundi((samples[sample] - mean) * gain * 32767.0))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = RATE
	result.stereo = false
	result.loop_mode = AudioStreamWAV.LOOP_FORWARD
	result.loop_begin = 0
	result.loop_end = count
	result.data = pcm
	_streams[cue] = result
	return result

func _partials(cue: String) -> Array[Vector3]:
	# x = Hz, y = amplitude, z = phase. Every frequency completes whole cycles.
	var result: Array[Vector3] = []
	match cue:
		"drive":
			result = [Vector3(72, 0.65, 0), Vector3(144, 0.24, 0.4), Vector3(288, 0.12, 1.1), Vector3(432, 0.06, 2)]
		"spinner":
			result = [Vector3(180, 0.5, 0), Vector3(360, 0.24, 0.6), Vector3(720, 0.09, 1.2), Vector3(1138, 0.035, 2)]
		"saw":
			result = [Vector3(410, 0.42, 0), Vector3(820, 0.22, 0.3), Vector3(1230, 0.13, 1.2), Vector3(2050, 0.06, 2)]
	# Fixed-seed, band-limited harmonic beds avoid a non-periodic noise splice.
	var seed_value := 1979 + CUES.find(cue) * 997
	var total := 32 if cue == "skid" else 16
	for index: int in range(total):
		seed_value = (seed_value * 1664525 + 1013904223) & 0x7fffffff
		var fraction := seed_value / 2147483648.0
		var frequency := 0.0
		var amplitude := 0.0
		if cue == "skid":
			frequency = 240.0 + index * 101.0 + floor(fraction * 70.0)
			amplitude = 0.065 / (1.0 + index * 0.025)
		elif cue == "arena":
			frequency = 41.0 + index * 31.0 + floor(fraction * 19.0)
			amplitude = 0.045 / (1.0 + index * 0.12)
		else:
			frequency = 311.0 + index * 83.0 + floor(fraction * 47.0)
			amplitude = 0.007
		result.append(Vector3(frequency, amplitude, fraction * TAU))
	return result
