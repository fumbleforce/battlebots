class_name GameplayAudio
extends Node
## Presentation-only: consumes authoritative events and detached views.
signal caption_changed(text: String)
signal cue_played(cue: String)
const EFFECT_VOICES := 4
const ANNOUNCEMENT_VOICES := 3
const CONTEXT_LIMIT := 16
const CAPTION_SECONDS := 2.0
const PHASES := ["lobby", "loading", "countdown", "active", "overtime", "intermission", "results"]
var _bank := GameplaySoundBank.new()
var _effects: Array[AudioStreamPlayer3D] = []
var _announcements: Array[AudioStreamPlayer] = []
var _crowd: AudioStreamPlayer
var _crowd_duck_until := 0.0
const CROWD_DB := -18.0
var _effect_cursor := 0
var _announcement_cursor := 0
var _clock := 0.0
var _next_effect := 0.0
var _next_announcement := 0.0
var _next_ready := 0.0
var _caption_until := 0.0
var _caption_priority := 0
var _caption_parts: Dictionary = {}
var _status := CombatAudioStatus.new()
var _match := ""
var _round := 0
var _phase := ""
var _phase_event := -1
var _practice := false
var _countdown := 6
# High-water IDs survive reset/rejoin, but memory remains capped.
var _event_watermarks: Dictionary = {}
var _retired_matches: Array[String] = []
var _bot_id := 0
var _bot_tick := -1
var _low_core := false
var _recovery_cooldown := 0.0

func _ready() -> void:
	add_to_group(&"gameplay_audio")
	for cue: String in ["crowd_round", "crowd_match"]:
		_bank.stream(cue)
	for index: int in EFFECT_VOICES:
		var player := AudioStreamPlayer3D.new()
		player.name = "Impact" + str(index)
		player.bus = "BBEffects"
		player.unit_size = 5.0
		player.max_distance = 75.0
		add_child(player)
		_effects.append(player)
	for index: int in ANNOUNCEMENT_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Announcement" + str(index)
		player.bus = "BBAnnouncements"
		add_child(player)
		_announcements.append(player)
	_crowd = AudioStreamPlayer.new()
	_crowd.name = "Crowd"
	_crowd.bus = "BBEffects"
	_crowd.volume_db = CROWD_DB
	add_child(_crowd)

func _process(delta: float) -> void:
	_clock += maxf(0.0, delta)
	if is_instance_valid(_crowd):
		_crowd.volume_db = CROWD_DB - (9.0 if _clock < _crowd_duck_until else 0.0)
	if _caption_priority > 0 and _clock >= _caption_until:
		_caption_priority = 0
		_caption_parts.clear()
		caption_changed.emit("")

func reset() -> void:
	for player: AudioStreamPlayer3D in _effects:
		player.stop()
	for player: AudioStreamPlayer in _announcements:
		player.stop()
	if is_instance_valid(_crowd):
		_crowd.stop()
	_crowd_duck_until = _clock
	# Practice is a new local world on every visit, with no unique match token.
	# Network watermarks remain across reconnects; practice starts a fresh epoch.
	if _practice:
		for context: String in _event_watermarks.keys():
			if context.begins_with(_match + "/"): _event_watermarks.erase(context)
	_match = ""
	_round = 0
	_phase = ""
	_phase_event = -1
	_practice = false
	_countdown = 6
	_next_effect = _clock
	_next_announcement = _clock
	_clear_bot()
	_caption_priority = 0
	_caption_parts.clear()
	caption_changed.emit("")

func _clear_bot() -> void:
	_status.reset()
	_bot_id = 0
	_bot_tick = -1
	_low_core = false
	_recovery_cooldown = 0.0
	_next_ready = _clock

func _integer(value: Variant, minimum: int) -> bool:
	return value is int and value >= minimum

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func observe_match(view: Dictionary, practice := false) -> void:
	if not view.get("phase") is String or view.phase not in PHASES:
		return
	if not view.get("match_id") is String or view.match_id.is_empty() or view.match_id.length() > 128 \
		or not _integer(view.get("round"), 0 if view.phase == "lobby" else 1) or not _integer(view.get("event_id"), 0) \
		or not _number(view.get("remaining")) or view.remaining < 0:
		return
	var new_match: String = view.match_id
	if new_match in _retired_matches:
		return
	if new_match == _match and (view.round < _round or view.event_id < _phase_event \
		or (view.event_id == _phase_event and (_phase != view.phase or _round != view.round))):
		return
	if view.phase == "lobby":
		if new_match == _match: reset()
		return
	var old_phase := _phase
	var initial := _match.is_empty() or new_match != _match
	if not _match.is_empty() and new_match != _match and not _practice:
		_retired_matches.append(_match)
		if _retired_matches.size() > CONTEXT_LIMIT: _retired_matches.pop_front()
	if initial or view.round != _round:
		_clear_bot()
		if is_instance_valid(_crowd): _crowd.stop()
		_countdown = 6
	_match = new_match
	_round = view.round
	_phase = view.phase
	_phase_event = view.event_id
	_practice = practice
	if _practice:
		return
	if _phase == "countdown":
		var remaining := ceili(float(view.remaining))
		if remaining in [1, 2, 3] and remaining < _countdown:
			_play("countdown", str(remaining), true, true)
		_countdown = mini(_countdown, remaining)
	elif not initial and old_phase != _phase:
		if _phase == "active" and old_phase == "countdown": _play("start", "Fight!", true, true)
		elif _phase == "intermission":
			_play("round_end", "Round complete", true, true)
			_play_crowd("crowd_round")
		elif _phase == "results":
			_play("results", "Match complete", true, true)
			_play_crowd("crowd_match")

func observe_bot(view: BotView, weapon := "") -> void:
	if view == null or _phase not in ["active", "overtime"] or view.entity_id <= 0 \
		or not is_finite(view.core_fraction) or view.core_fraction < 0.0 or view.core_fraction > 1.0 \
		or not is_finite(view.recovery_cooldown) or view.recovery_cooldown < 0.0 or view.server_tick < 0:
		_clear_bot()
		return
	if view.entity_id != _bot_id:
		_bot_id = view.entity_id
		_bot_tick = view.server_tick
		_low_core = view.core_fraction <= 0.25
		_recovery_cooldown = view.recovery_cooldown
		_status.observe(view, weapon)
		return # Joining an already damaged/recovering bot is not a new warning.
	if view.server_tick <= _bot_tick:
		return
	_bot_tick = view.server_tick
	var status_edges := _status.observe(view, weapon)
	if not view.eliminated:
		if view.core_fraction > 0.35:
			_low_core = false
		elif view.core_fraction <= 0.25 and not _low_core:
			_low_core = true
			_play("low_core", "Core integrity low", true, true, true)
		if view.recovery_cooldown > _recovery_cooldown + 1.0:
			_play("recovery", "Recovery activated", true, true, true)
	_recovery_cooldown = view.recovery_cooldown
	for edge: Dictionary in status_edges:
		if edge.cue == "armor_break":
			_play(edge.cue, edge.caption, true, true, true)
		elif _clock >= _next_ready and (_caption_priority < 2 or _clock >= _caption_until):
			# Critical warnings take precedence over positive readiness feedback.
			_play(edge.cue, edge.caption, true, true, false, 1)
			_next_ready = _clock + 0.75

func combat_event(event: Dictionary, local_entity: int) -> void:
	if _match.is_empty() or _phase not in ["active", "overtime"] \
		or not _integer(event.get("event_id"), 1) or not _integer(event.get("round"), 1) \
		or event.round != _round or not _integer(event.get("tick"), 0) \
		or not _integer(event.get("attacker"), 1) or not _integer(event.get("target"), 1) \
		or event.attacker == event.target or not _number(event.get("damage")) or event.damage < 0 \
		or not event.get("kind") is String or not event.get("position") is Vector3 \
		or not event.position.is_finite() or not event.get("normal") is Vector3 or not event.normal.is_finite():
		return
	if not _practice and event.get("match_id") != _match:
		return
	if _practice and event.has("match_id") and event.match_id != _match:
		return
	var kinds := {"hammer":"hammer", "vertical_spinner":"spinner", "horizontal_spinner":"spinner",
		"lifter":"lifter", "saw":"saw", "ram":"ram"}
	if not kinds.has(event.kind):
		return
	var context := "%s/%d" % [_match, _round]
	if event.event_id <= int(_event_watermarks.get(context, 0)):
		return
	_event_watermarks[context] = event.event_id
	if _event_watermarks.size() > CONTEXT_LIMIT:
		_event_watermarks.erase(_event_watermarks.keys()[0])
	var kind: String = kinds[event.kind]
	var caption := kind.capitalize() + " impact"
	if event.attacker == local_entity: caption = kind.capitalize() + " hit"
	elif event.target == local_entity: caption = "Hit by " + kind
	_play("impact_" + kind, caption, false, false, false, -1, event.position)

## A hammer that lands on the arena has no combat event; its shockwave still
## sounds like a hammer blow at the slam point.
func ground_slam(position: Vector3) -> void:
	if not position.is_finite(): return
	_play("impact_hammer", "Hammer slam", false, false, false, -1, position)

## Local credit pickups ring a short coin cue. Other players' pickups are silent.
func pickup_collected(event: Dictionary, local_entity: int) -> void:
	if event.get("entity") != local_entity or event.get("kind") != "credits":
		return
	var amount: Variant = event.get("amount")
	_play("credit_pickup", "+%d credits" % int(amount) if _integer(amount, 1) else "Credits collected",
		true, true, false, 1)

func _play_crowd(cue: String) -> void:
	if not is_instance_valid(_crowd):
		return
	var stream := _bank.stream(cue)
	if stream == null:
		return
	_crowd.stop()
	_crowd.stream = stream
	_crowd.volume_db = CROWD_DB - (9.0 if _clock < _crowd_duck_until else 0.0)
	_crowd.play()
	cue_played.emit(cue)

func _play(cue: String, caption: String, announcement: bool, transition := false,
	merge_caption := false, priority_override := -1, impact_position := Vector3.ZERO) -> void:
	var pool_size := _announcements.size() if announcement else _effects.size()
	# Match changes cannot be retried on a later view refresh. Let them preempt
	# a bounded announcement voice instead of losing them to warning throttling.
	if pool_size == 0 or (not transition and _clock < (_next_announcement if announcement else _next_effect)):
		return
	var stream := _bank.stream(cue)
	if stream == null:
		return
	if announcement:
		var player := _announcements[_announcement_cursor % pool_size]
		player.stop()
		player.stream = stream
		player.play()
		_announcement_cursor += 1
		if priority_override != 1:
			_next_announcement = _clock + 0.08
			_crowd_duck_until = maxf(_crowd_duck_until, _clock + stream.get_length() + 0.1)
			if is_instance_valid(_crowd): _crowd.volume_db = CROWD_DB - 9.0
	else:
		var player := _effects[_effect_cursor % pool_size]
		player.stop()
		player.global_position = impact_position
		player.stream = stream
		player.play()
		_effect_cursor += 1
		_next_effect = _clock + 0.035
	cue_played.emit(cue)
	var priority := priority_override if priority_override >= 0 else (2 if announcement else 1)
	if priority >= _caption_priority or _clock >= _caption_until:
		if not merge_caption or _caption_priority != priority or _clock >= _caption_until:
			_caption_parts.clear()
		if merge_caption:
			# Keep at most the latest core, recovery and armor warning. Unrelated
			# countdown/round text and repeated warnings cannot grow the caption.
			for prior: String in _caption_parts.keys():
				if prior not in ["low_core", "recovery", "armor_break"]:
					_caption_parts.erase(prior)
		_caption_parts[cue] = caption
		caption = " · ".join(_caption_parts.values())
		_caption_priority = priority
		_caption_until = _clock + CAPTION_SECONDS
		caption_changed.emit(caption)
