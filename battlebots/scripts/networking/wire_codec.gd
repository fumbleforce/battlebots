class_name WireCodec
extends RefCounted
const PROTOCOL := 13
const BUILD := "mvp-ab-35"
const SNAPSHOT_FIELDS := 43
const ZONES := ["front", "rear", "left", "right", "top", "underside", "drive_left", "drive_right", "weapon"]

static func snapshot_epoch(match_id: String, round_index: int) -> String:
	return "%s:%d" % [match_id, round_index]

static func command_to_array(command: BotCommand) -> Array:
	var flags := int(command.brake) | (int(command.primary_held) << 1) | (int(command.primary_pressed) << 2) | (int(command.secondary_held) << 3) | (int(command.recovery_pressed) << 4) | (int(command.auxiliary_held) << 5) | (int(command.nitro_held) << 6) | (int(command.jump_held) << 7) | (int(command.jump_cancel) << 8) | (int(command.aim_valid) << 9) | (int(command.crouch_held) << 10)
	return [command.sequence, command.throttle, command.steering, flags, command.aim_yaw, command.aim_pitch]

static func command_from_array(data: Variant) -> BotCommand:
	if not data is Array or data.size() != 6 or not data[0] is int or data[0] < 0 or data[0] > 2147483647:
		return null
	if (not data[1] is float and not data[1] is int) or (not data[2] is float and not data[2] is int) or not data[3] is int or data[3] < 0 or data[3] > 2047:
		return null
	if (not data[4] is float and not data[4] is int) or (not data[5] is float and not data[5] is int):
		return null
	var command := BotCommand.new()
	command.sequence = data[0]
	command.throttle = data[1]
	command.steering = data[2]
	command.brake = (data[3] & 1) != 0
	command.primary_held = (data[3] & 2) != 0
	command.primary_pressed = (data[3] & 4) != 0
	command.secondary_held = (data[3] & 8) != 0
	command.recovery_pressed = (data[3] & 16) != 0
	command.auxiliary_held = (data[3] & 32) != 0
	command.nitro_held = (data[3] & 64) != 0
	command.jump_held = (data[3] & 128) != 0
	command.jump_cancel = (data[3] & 256) != 0
	command.aim_valid = (data[3] & 512) != 0
	command.crouch_held = (data[3] & 1024) != 0
	command.aim_yaw = data[4]
	command.aim_pitch = data[5]
	return command if command.is_valid() else null

static func encode_bot(bot: MvpBot, epoch: String) -> PackedByteArray:
	var c := bot.combat
	# Baselines can be requested between reset_round() and the next Jolt step.
	# The new round owns its spawn pose, never the preceding round's motion.
	var resetting := bot.body.reset_pose is Transform3D
	var pose: Transform3D = bot.body.reset_pose if resetting else bot.body.global_transform
	var zones: Array = []
	for key: String in ZONES:
		zones.append(c.zones[key])
	return var_to_bytes([epoch, bot.server_tick, bot.entity_id, bot.last_sequence,
		pose, Vector3.ZERO if resetting else bot.body.linear_velocity,
		Vector3.ZERO if resetting else bot.body.angular_velocity,
		c.core, zones, c.overheated, c.heat, c.charge, c.weapon_phase, c.cooldown,
		c.can_recover(), c.recovery_remaining, c.recovery_cooldown,
		maxf(0, 10 - c.immobilized_seconds) if c.immobilized_seconds > 0 else 0.0,
		c.eliminated, c.elimination_reason, c.failure_reason, c.effective_damage,
		c.eliminations, c.assists, c.component_disables, c.recovery_count,
		0.0 if resetting else bot.body._drive_input, 0.0 if resetting else bot.body._turn_input,
		false if resetting else bot.body.grounded,
		c.secondary_charge, c.secondary_active, c.shot_sequence,
		c.last_shot_from, c.last_shot_to, c.last_shot_tick, c.gun_pitch,
		c.nitro_active, c.jump_charge, c.jump_cooldown, c.turret_yaw, c.grip_target, c.grip_point, c.tool_pose])

static func decode_bot(packet: PackedByteArray, stats: Dictionary) -> Dictionary:
	if packet.size() > 1200:
		return {}
	var values: Variant = bytes_to_var(packet)
	if not values is Array or values.size() != SNAPSHOT_FIELDS or not values[4] is Transform3D or not values[5] is Vector3 or not values[6] is Vector3:
		return {}
	if not values[4].is_finite() or not values[5].is_finite() or not values[6].is_finite():
		return {}
	if not (values[29] is float or values[29] is int) or not is_finite(float(values[29])) or values[29] < 0 or values[29] > 1:
		return {}
	if not values[30] is bool or not values[31] is int or values[31] < 0 or values[31] > 2147483647:
		return {}
	if not values[32] is Vector3 or not values[33] is Vector3 or not values[32].is_finite() or not values[33].is_finite():
		return {}
	if not values[34] is int or values[34] < -1 or values[34] > 2147483647 or values[32].distance_to(values[33]) > 150.0:
		return {}
	# Elevation: the mortar cradle reaches 80 degrees (AtlasGeometry.TURRET_PITCH_MAX_BY).
	if not (values[35] is float or values[35] is int) or not is_finite(float(values[35])) or absf(values[35]) > 1.45:
		return {}
	if not values[36] is bool or not (values[37] is float or values[37] is int) or not is_finite(float(values[37])) or values[37] < 0.0 or values[37] > 1.0:
		return {}
	if not (values[38] is float or values[38] is int) or not is_finite(float(values[38])) or values[38] < 0.0 or values[38] > 4.0:
		return {}
	if not (values[39] is float or values[39] is int) or not is_finite(float(values[39])) or absf(values[39]) > PI + 0.001:
		return {}
	if not values[40] is int or values[40] < 0 or values[40] > 2147483647 or not values[41] is Vector3 or not values[41].is_finite():
		return {}
	if not (values[42] is float or values[42] is int) or not is_finite(float(values[42])) or values[42] < 0.0 or values[42] > 1.0:
		return {}
	if not values[9] is bool or not (values[10] is float or values[10] is int) or not is_finite(float(values[10])) or values[10] < 0.0 or values[10] > CombatState.HEAT_LIMIT:
		return {}
	var zones := {}
	if not values[8] is Array or values[8].size() != ZONES.size():
		return {}
	for index: int in range(ZONES.size()):
		zones[ZONES[index]] = values[8][index]
	return {"epoch":values[0], "tick":values[1], "entity":values[2], "ack":values[3],
		"pose":values[4], "velocity":values[5], "angular":values[6], "core":values[7], "zones":zones,
		"core_max":stats.core, "plate_max":stats.plates, "weapon":stats.weapon,
		"overheated":values[9], "heat":values[10], "charge":values[11], "weapon_state":values[12], "cooldown":values[13],
		"recovery_available":values[14], "recovery_remaining":values[15], "recovery_cooldown":values[16],
		"immobilized_remaining":values[17], "eliminated":values[18], "elimination_reason":values[19], "failure":values[20],
		"damage":values[21], "eliminations":values[22], "assists":values[23], "component_disables":values[24], "recoveries":values[25],
		"drive_input":values[26], "turn_input":values[27], "grounded":values[28],
		"secondary_charge":values[29], "secondary_active":values[30], "shot_sequence":values[31],
		"last_shot_from":values[32], "last_shot_to":values[33], "last_shot_tick":values[34], "gun_pitch":values[35],
		"nitro_active":values[36], "jump_charge":values[37], "jump_cooldown":values[38], "turret_yaw":values[39],
		"grip_target":values[40], "grip_point":values[41], "tool_pose":values[42]}

static func read_json(packet: PackedByteArray, limit: int) -> Dictionary:
	if packet.size() > limit:
		return {}
	var parser := JSON.new()
	if parser.parse(packet.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

static func json_packet(value: Dictionary) -> PackedByteArray:
	return JSON.stringify(value).to_utf8_buffer()
