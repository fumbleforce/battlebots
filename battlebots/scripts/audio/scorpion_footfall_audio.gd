class_name ScorpionFootfallAudio
extends Node3D
## Cosmetic terrain contact only. One voice per landing tripod, never per leg.
const SAMPLE := "res://assets/audio/combat/scorpion_footfall.wav"
const VOICES := 2
const RESET_QUIET := 0.35
var players: Array[AudioStreamPlayer3D] = []
var played_count := 0
var playback_enabled := true
var _quiet := RESET_QUIET

func _enter_tree() -> void:
	add_to_group(&"bot_action_audio")

func set_playback_enabled(enabled: bool) -> void:
	if playback_enabled == enabled: return
	playback_enabled = enabled
	reset()

func _ready() -> void:
	AudioPreferences.ensure_buses()
	var recording := load(SAMPLE).duplicate() as AudioStreamWAV
	recording.loop_mode = AudioStreamWAV.LOOP_DISABLED
	for index: int in VOICES:
		var player := AudioStreamPlayer3D.new()
		player.name = "Footfall%d" % index
		player.stream = recording
		player.bus = &"BBEffects"
		player.volume_db = -9.0
		player.unit_size = 5.0
		player.max_distance = 45.0
		add_child(player)
		player.top_level = true
		players.append(player)

func advance(delta: float) -> void:
	_quiet = maxf(0.0, _quiet - maxf(0.0, delta))

func plant(at: Vector3) -> bool:
	if not playback_enabled or _quiet > 0.0 or not at.is_finite() or players.is_empty(): return false
	var player := players[played_count % VOICES]
	player.stop()
	player.global_position = at
	player.play()
	played_count += 1
	_quiet = 0.12
	return true

func reset() -> void:
	_quiet = RESET_QUIET
	for player: AudioStreamPlayer3D in players: player.stop()
