class_name ContinuousGameplayAudio
extends Node3D
## Bounded presentation audio from detached, accepted physical state.
const MAX_BOTS := 2
const MAX_AGE := 0.25
const ARENA_DB := -25.0
const FAMILIES := ["vertical_spinner", "horizontal_spinner", "saw", "hammer", "lifter"]
var _bank := GameplayLoopBank.new()
var _pool: Array[Node3D] = []
var _bots: Dictionary = {}
var _arena: AudioStreamPlayer
var _duck_remaining := 0.0

func _ready() -> void:
	AudioPreferences.ensure_buses()
	for cue in ["drive", "skid", "spinner", "saw", "arena"]:
		_bank.stream(cue)
	_arena = AudioStreamPlayer.new()
	_arena.bus = "BBEffects"
	_arena.stream = _bank.stream("arena")
	_arena.volume_db = ARENA_DB
	add_child(_arena)
	for index in MAX_BOTS:
		var rig := Node3D.new()
		rig.name = "BotAudio%d" % index
		add_child(rig)
		for layer in ["drive", "skid", "weapon"]:
			var voice := AudioStreamPlayer3D.new()
			voice.name = layer
			voice.bus = "BBEffects"
			voice.max_distance = 45.0
			voice.unit_size = 5.0
			voice.max_db = -6.0
			rig.add_child(voice)
		_pool.append(rig)

func render(records: Array[Dictionary], active: bool) -> void:
	if not is_node_ready():
		return
	if not active:
		reset()
		return
	var counts: Dictionary = {}
	for record in records:
		var id: Variant = record.get("entity_id")
		if id is int:
			counts[id] = int(counts.get(id, 0)) + 1
	var accepted: Dictionary = {}
	for record in records:
		if not _valid(record):
			continue
		var id: int = record.entity_id
		if counts[id] != 1 or accepted.size() >= MAX_BOTS:
			continue
		if _bots.has(id) and int(record.tick) < int(_bots[id].get_meta("tick", -1)):
			continue
		accepted[id] = record
	for id in _bots.keys():
		if not accepted.has(id):
			_release(id)
	for id in accepted:
		var record: Dictionary = accepted[id]
		var rig: Node3D
		if _bots.has(id):
			rig = _bots[id]
		else:
			for candidate in _pool:
				if candidate not in _bots.values():
					rig = candidate
					break
			_bots[id] = rig
		rig.global_position = record.position
		rig.set_meta("tick", record.tick)
		rig.set_meta("age", float(record.age))
		var speed := Vector2(record.velocity.x, record.velocity.z).length()
		var demand := maxf(absf(record.drive_input), absf(record.turn_input))
		var movement := clampf(maxf(speed / 10.0, absf(record.angular.y) / 4.0), 0.0, 1.0)
		var motor := maxf(demand, movement * 0.65 if record.grounded else 0.0)
		_layer(rig, "drive", "drive", motor, 0.7 + motor * 0.85, -16.0)
		var right: Vector3 = record.pose.basis.x.normalized()
		var lateral := absf(record.velocity.dot(right))
		var skid := clampf((lateral - 0.8) / 5.0, 0.0, 1.0) if record.grounded else 0.0
		_layer(rig, "skid", "skid", skid, 0.85 + skid * 0.3, -20.0)
		var rotor := float(record.charge) if record.weapon in ["vertical_spinner", "horizontal_spinner"] else 0.0
		if record.weapon == "saw":
			rotor = 1.0 if float(record.charge) > 0.0 else 0.0
			# Keep the recording's heavy pitch; compensate its lower RMS vs synthesis.
			_layer(rig, "weapon", "saw", rotor, 1.0, -14.0)
		else:
			_layer(rig, "weapon", "spinner", rotor, 0.55 + rotor * 0.95, -18.0)
	if not accepted.is_empty():
		if not _arena.playing:
			_arena.play()
	else:
		_arena.stop()

func _process(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	_duck_remaining = maxf(0.0, _duck_remaining - delta)
	if is_instance_valid(_arena):
		_arena.volume_db = ARENA_DB - (9.0 if _duck_remaining > 0.0 else 0.0)
	for id in _bots.keys():
		var rig: Node3D = _bots[id]
		var age := float(rig.get_meta("age", 0.0)) + delta
		rig.set_meta("age", age)
		if age > MAX_AGE:
			_release(id)
	if _bots.is_empty() and is_instance_valid(_arena):
		_arena.stop()

func duck(seconds := 2.0) -> void:
	if is_finite(seconds) and seconds > 0.0:
		_duck_remaining = maxf(_duck_remaining, minf(seconds, 10.0))
		if is_instance_valid(_arena):
			_arena.volume_db = ARENA_DB - 9.0

func reset() -> void:
	for id in _bots.keys():
		_release(id)
	_duck_remaining = 0.0
	if is_instance_valid(_arena):
		_arena.stop()
		_arena.volume_db = ARENA_DB

func _release(id: int) -> void:
	var rig: Node3D = _bots[id]
	for voice in rig.get_children():
		voice.stop()
	rig.remove_meta("tick")
	rig.remove_meta("age")
	_bots.erase(id)

func _layer(rig: Node3D, layer: String, cue: String, amount: float, pitch: float, decibels: float) -> void:
	var voice := rig.get_node(layer) as AudioStreamPlayer3D
	if amount <= 0.01:
		voice.stop()
		return
	var stream := _bank.stream(cue)
	if voice.stream != stream:
		voice.stop()
		voice.stream = stream
	voice.volume_db = decibels + linear_to_db(amount)
	voice.pitch_scale = pitch
	if not voice.playing:
		voice.play()

func _valid(record: Dictionary) -> bool:
	if not record.get("entity_id") is int or int(record.entity_id) <= 0 \
		or not record.get("tick") is int or int(record.tick) < 0:
		return false
	for key in ["position", "velocity", "angular"]:
		if not record.get(key) is Vector3 or not record[key].is_finite():
			return false
	if not record.get("pose") is Transform3D or not record.pose.is_finite() \
		or absf(record.pose.basis.determinant()) < 0.00001:
		return false
	for key in ["drive_input", "turn_input", "charge", "age"]:
		if not (record.get(key) is float or record.get(key) is int) or not is_finite(float(record[key])):
			return false
	return absf(record.drive_input) <= 1.0 and absf(record.turn_input) <= 1.0 \
		and float(record.charge) >= 0.0 and float(record.charge) <= 1.0 \
		and float(record.age) >= 0.0 and float(record.age) <= MAX_AGE \
		and record.get("grounded") is bool and record.get("eliminated") is bool \
		and not record.eliminated and record.get("weapon") in FAMILIES
