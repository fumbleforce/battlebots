class_name CombatState
extends RefCounted
## Pure authoritative combat state. Presentation consumes detached snapshots.
var stats: Dictionary
var core: float
var zones: Dictionary = {}
var battery: float
var heat := 0.0
var charge := 0.0
var overheated := false
var cooldown := 0.0
var recovery_cooldown := 0.0
var recovery_remaining := 0.0
var inverted_seconds := 0.0
var immobilized_seconds := 0.0
var driven_distance := 0.0
var eliminated := false
var elimination_reason := ""
var weapon_phase := "idle"
var failure_reason := ""
var attack_id := 0
var launch := false
var strike := false
var effective_damage := 0
var eliminations := 0
var assists := 0
var component_disables := 0
var recovery_count := 0
var nitro_active := false
var jump_charge := 0.0
var jump_cooldown := 0.0
var jump_release_speed := 0.0
var _jump_was_held := false
var recent_attackers: Dictionary = {}
var _previous_held := false
var _inactive := 0.0
var _hammer_windup := 0.0
const MINIGUN_SPINUP := 0.6
const MINIGUN_CADENCE := 1.0 / 12.0
const MINIGUN_SHOT_COST := 0.8
const MINIGUN_SHOT_HEAT := 1.4
var secondary_charge := 0.0
var secondary_active := false
var gun_shot := false
var shot_sequence := 0
var last_shot_from := Vector3.ZERO
var last_shot_to := Vector3.ZERO
var last_shot_tick := -1
var gun_pitch := 0.0
var _gun_cooldown := 0.0

func _init(derived: Dictionary) -> void:
	stats = derived.duplicate(true)
	core = stats.core
	battery = stats.battery
	for zone: String in ["front", "rear", "left", "right"]:
		zones[zone] = stats.plate_integrity
	zones.merge({"drive_left":100.0, "drive_right":100.0, "weapon":140.0})

func drive_scale() -> float:
	var pods := int(zones.drive_left > 0) + int(zones.drive_right > 0)
	return float(pods) * 0.5

func tick_perks(delta: float, command: BotCommand, active: bool, grounded: bool) -> void:
	jump_release_speed = 0.0
	nitro_active = false
	if not active or eliminated or command.jump_cancel:
		jump_charge = 0.0
		_jump_was_held = false
		return
	jump_cooldown = maxf(0.0, jump_cooldown - delta)
	if stats.get("nitro", false) and command.nitro_held and command.throttle > 0.05 and not command.brake and battery >= 14.0 * delta and drive_scale() > 0.0:
		nitro_active = true
		battery -= 14.0 * delta
	if not stats.get("charged_jump", false):
		return
	if command.jump_held and grounded and jump_cooldown <= 0.0 and battery >= 20.0:
		jump_charge = minf(1.0, jump_charge + delta / 1.2)
	elif not command.jump_held:
		if _jump_was_held and jump_charge > 0.0 and grounded and battery >= 20.0 and jump_cooldown <= 0.0:
			battery -= 20.0
			jump_release_speed = lerpf(3.5, 7.5, jump_charge)
			jump_cooldown = 4.0
		jump_charge = 0.0
	elif not grounded:
		jump_charge = 0.0
	_jump_was_held = command.jump_held

func can_recover() -> bool:
	return not eliminated and inverted_seconds >= 2.0 and recovery_cooldown <= 0.0 and battery >= 30.0

func tick(delta: float, command: BotCommand, active: bool) -> void:
	gun_shot = false
	secondary_active = false
	var previous_heat := heat
	var previous_battery := battery
	_tick_primary(delta, command, active)
	if not active or eliminated:
		secondary_charge = 0.0
		_gun_cooldown = 0.0
		return
	if stats.get("secondary_weapon", "") == "minigun":
		# The primary's idle branch cannot cool/recharge while the gun is powered.
		# Preserve its genuine activation costs/heat, then pay the gun separately.
		if command.auxiliary_held and zones.weapon > 0 and not overheated \
				and minf(battery, previous_battery) >= 2.0 * delta:
			battery = minf(battery, previous_battery)
			heat = maxf(heat, previous_heat)
		_tick_minigun(delta, command.auxiliary_held, true, false)

func _secondary_brake(command: BotCommand) -> bool:
	return command.secondary_held and not (stats.get("secondary_weapon", "") == "minigun" and command.auxiliary_held)

func _tick_primary(delta: float, command: BotCommand, active: bool) -> void:
	launch = false
	strike = false
	failure_reason = ""
	if not active or eliminated:
		charge = 0.0
		_hammer_windup = 0.0
		_previous_held = false
		weapon_phase = "disabled" if eliminated else "idle"
		return
	if stats.weapon != "hammer":
		cooldown = maxf(0, cooldown - delta)
	recovery_cooldown = maxf(0, recovery_cooldown - delta)
	var recovery_was_active := recovery_remaining > 0.000001
	recovery_remaining = maxf(0, recovery_remaining - delta)
	if command.recovery_pressed:
		if can_recover():
			battery -= 30
			recovery_remaining = stats.recovery_seconds
			recovery_cooldown = 20.0
			recovery_count += 1
			_inactive = 0.0
		else:
			failure_reason = "recovery_unavailable"
	if overheated and heat <= 50:
		overheated = false
	if stats.weapon == "minigun":
		_tick_minigun(delta, command.primary_held and not _secondary_brake(command), false, recovery_was_active)
		return
	if stats.weapon == "hammer":
		if recovery_remaining < 0.000001:
			recovery_remaining = 0.0
		_tick_hammer(delta, command, recovery_was_active)
		return
	if stats.weapon == "saw":
		if recovery_remaining < 0.000001:
			recovery_remaining = 0.0
		_tick_saw(delta, command, recovery_was_active)
		return
	var eligible: bool = zones.weapon > 0 and not overheated and cooldown <= 0
	var powered: bool = eligible and command.primary_held and not _secondary_brake(command)
	var spinner: bool = stats.weapon in ["vertical_spinner", "horizontal_spinner"]
	var cost := 10.0 if spinner else 6.0
	var heat_rate := 12.0 if spinner else 4.0
	var spinup := 2.0 if stats.weapon == "horizontal_spinner" else (1.5 if spinner else 1.0)
	if powered and battery < cost * delta:
		powered = false
		failure_reason = "battery_empty"
	if command.primary_held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0 else ("overheated" if overheated else "cooldown")
	if powered:
		battery = maxf(0, battery - cost * delta)
		heat = minf(100, heat + heat_rate * delta)
		charge = minf(1, charge + delta / spinup)
		_inactive = 0.0
	else:
		heat = maxf(0, heat - float(stats.cooling) * delta)
		if recovery_remaining > 0:
			_inactive = 0
		else:
			_inactive += delta
			if _inactive >= 1.0:
				battery = minf(stats.battery, battery + 8 * delta)
	if stats.weapon == "lifter" and _previous_held and not command.primary_held and not _secondary_brake(command) and eligible and charge >= 1.0:
		if battery >= 20:
			battery -= 20
			heat = minf(100, heat + 18)
			cooldown = 3.0
			attack_id += 1
			launch = true
			_inactive = 0
		else:
			failure_reason = "battery_empty"
	if not powered:
		charge = move_toward(charge, 0.0, delta * (4.0 if _secondary_brake(command) else 1.0))
	if heat >= 100:
		overheated = true
		charge = 0.0
	if zones.weapon <= 0:
		charge = 0.0
	weapon_phase = "disabled" if zones.weapon <= 0 else ("overheated" if overheated else (
		"launch" if launch else ("cooldown" if cooldown > 0 else ("active" if powered else "idle"))))
	_previous_held = command.primary_held

func _tick_saw(delta: float, command: BotCommand, recovery_was_active: bool) -> void:
	var eligible: bool = zones.weapon > 0.0 and not overheated and cooldown <= 0.0
	var powered := eligible and command.primary_held and not _secondary_brake(command)
	if command.primary_held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0.0 else ("overheated" if overheated else "cooldown")
	if powered and (battery <= 0.0 or battery < 9.0 * delta):
		powered = false
		failure_reason = "battery_empty"
	if powered:
		battery = maxf(0.0, battery - 9.0 * delta)
		heat = minf(100.0, heat + 14.0 * delta)
		_inactive = 0.0
		if battery < 0.000001:
			battery = 0.0
			powered = false
			failure_reason = "battery_empty"
	else:
		heat = maxf(0.0, heat - float(stats.cooling) * delta)
		if recovery_was_active or recovery_remaining > 0.0:
			_inactive = 0.0
		else:
			var previous := _inactive
			_inactive += delta
			var recharge_seconds := maxf(0.0, _inactive - 1.0) - maxf(0.0, previous - 1.0)
			battery = minf(stats.battery, battery + 8.0 * recharge_seconds)
	if heat >= 100.0:
		overheated = true
		powered = false
	charge = 1.0 if powered else 0.0
	weapon_phase = "disabled" if zones.weapon <= 0.0 else ("overheated" if overheated else (
		"cooldown" if cooldown > 0.0 else ("active" if powered else "idle")))

func _tick_hammer(delta: float, command: BotCommand, recovery_was_active: bool) -> void:
	# Input applies at the start of a physics tick. A press during recovery is
	# discarded even if that recovery reaches zero at the end of this tick.
	var recovering := cooldown > 0.0
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown < 0.000001:
		cooldown = 0.0
	if zones.weapon <= 0:
		_hammer_windup = 0.0
		charge = 0.0
		if command.primary_pressed:
			failure_reason = "disabled"
	elif _hammer_windup <= 0.0 and command.primary_pressed and not _secondary_brake(command):
		if recovering or overheated:
			failure_reason = "overheated" if overheated else "cooldown"
		elif battery < 16.0:
			failure_reason = "battery_empty"
		else:
			battery -= 16.0
			attack_id += 1
			_hammer_windup = 0.35
	if _hammer_windup > 0.0:
		_hammer_windup = maxf(0.0, _hammer_windup - delta)
		charge = clampf(1.0 - _hammer_windup / 0.35, 0.0, 1.0)
		_inactive = 0.0
		if _hammer_windup < 0.000001:
			_hammer_windup = 0.0
			charge = 1.0
			strike = true
			cooldown = 1.4
			heat = minf(100.0, heat + 20.0)
			overheated = heat >= 100.0
	else:
		charge = 0.0
		heat = maxf(0.0, heat - float(stats.cooling) * delta)
		if recovery_was_active or recovery_remaining > 0.0:
			_inactive = 0.0
		else:
			# Recharge only the portion after the full one-second inactivity wait.
			var previous := _inactive
			_inactive += delta
			var recharge_seconds := maxf(0.0, _inactive - 1.0) - maxf(0.0, previous - 1.0)
			battery = minf(stats.battery, battery + 8.0 * recharge_seconds)
	weapon_phase = "disabled" if zones.weapon <= 0 else ("strike" if strike else (
		"windup" if _hammer_windup > 0.0 else ("overheated" if overheated else ("cooldown" if cooldown > 0.0 else "idle"))))

func _tick_minigun(delta: float, held: bool, auxiliary: bool, recovery_was_active: bool) -> void:
	var spool := secondary_charge if auxiliary else charge
	var eligible: bool = zones.weapon > 0.0 and not overheated
	var powered := held and eligible
	var motor_cost := 2.0 * delta
	_gun_cooldown = maxf(0.0, _gun_cooldown - delta)
	if powered and battery < motor_cost:
		powered = false
		failure_reason = "battery_empty"
	if held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0.0 else "overheated"
	if powered:
		battery = maxf(0.0, battery - motor_cost)
		heat = minf(100.0, heat + 3.0 * delta)
		spool = minf(1.0, spool + delta / MINIGUN_SPINUP)
		_inactive = 0.0
		if heat >= 100.0:
			overheated = true
			powered = false
		elif spool >= 1.0 - 0.000001 and _gun_cooldown <= 0.000001:
			if battery >= MINIGUN_SHOT_COST:
				battery -= MINIGUN_SHOT_COST
				heat = minf(100.0, heat + MINIGUN_SHOT_HEAT)
				gun_shot = true
				shot_sequence += 1
				_gun_cooldown = MINIGUN_CADENCE
				overheated = heat >= 100.0
			else:
				powered = false
				failure_reason = "battery_empty"
	else:
		if not auxiliary:
			heat = maxf(0.0, heat - float(stats.cooling) * delta)
			if recovery_was_active or recovery_remaining > 0.0:
				_inactive = 0.0
			else:
				var previous := _inactive
				_inactive += delta
				var recharge_seconds := maxf(0.0, _inactive - 1.0) - maxf(0.0, previous - 1.0)
				battery = minf(stats.battery, battery + 8.0 * recharge_seconds)
	if not powered:
		spool = move_toward(spool, 0.0, delta * 2.0)
	if zones.weapon <= 0.0 or overheated:
		spool = 0.0
	if auxiliary:
		secondary_charge = spool
		secondary_active = powered and not overheated and spool >= 1.0 - 0.000001
	else:
		charge = spool
		weapon_phase = "disabled" if zones.weapon <= 0 else ("overheated" if overheated else (
			"active" if powered and spool >= 1.0 - 0.000001 else ("spooling" if powered else "idle")))

func mobility(delta: float, wheel_contact: bool, upside_down: bool, self_driven_distance: float) -> void:
	if eliminated:
		return
	inverted_seconds = inverted_seconds + delta if upside_down and not wheel_contact else 0.0
	if drive_scale() == 0.0 or inverted_seconds >= 5.0 or immobilized_seconds > 0:
		immobilized_seconds += delta
		if wheel_contact and drive_scale() > 0:
			driven_distance += self_driven_distance
		if driven_distance >= 0.5:
			immobilized_seconds = 0
			driven_distance = 0
		elif immobilized_seconds >= 10.0:
			eliminate("immobilized")
	else:
		driven_distance = 0

func damage(zone: String, raw: float) -> int:
	if eliminated or not is_finite(raw) or raw <= 0:
		return 0
	var core_damage := 0.0
	var component_damage := 0.0
	if zone in ["front", "rear", "left", "right"]:
		core_damage = raw * (1.0 - float(stats.reduction) if zones[zone] > 0 else 1.0)
		component_damage = minf(zones[zone], raw)
	elif zone in ["drive_left", "drive_right", "weapon"]:
		core_damage = raw * 0.25
		component_damage = minf(zones[zone], raw * 0.75)
	elif zone in ["top", "underside"]:
		core_damage = raw * 0.95
	else:
		return 0
	if zones.has(zone):
		zones[zone] = maxf(0, float(zones[zone]) - component_damage)
	core_damage = minf(core, core_damage)
	core -= core_damage
	if core <= 0:
		eliminate("core")
	return roundi(core_damage + component_damage)

func eliminate(reason: String) -> void:
	eliminated = true
	elimination_reason = reason
	strike = false
	_hammer_windup = 0.0
	charge = 0
	secondary_charge = 0.0
	secondary_active = false
	gun_shot = false
	_gun_cooldown = 0.0
	gun_pitch = 0.0
	weapon_phase = "disabled"
	nitro_active = false
	jump_charge = 0.0
	jump_release_speed = 0.0

func snapshot() -> Dictionary:
	return {"core":core, "core_max":stats.core, "zones":zones.duplicate(),
		"plate_max":stats.plate_integrity, "battery":battery, "battery_max":stats.battery,
		"heat":heat, "charge":charge, "weapon":stats.weapon, "weapon_state":weapon_phase,
		"secondary_charge":secondary_charge, "secondary_active":secondary_active,
		"shot_sequence":shot_sequence, "last_shot_from":last_shot_from,
		"last_shot_to":last_shot_to, "last_shot_tick":last_shot_tick,
		"gun_pitch":gun_pitch,
		"nitro_active":nitro_active, "jump_charge":jump_charge, "jump_cooldown":jump_cooldown,
		"cooldown":cooldown, "recovery_available":can_recover(), "recovery_remaining":recovery_remaining,
		"recovery_cooldown":recovery_cooldown, "immobilized_remaining":maxf(0, 10 - immobilized_seconds) if immobilized_seconds > 0 else 0.0,
		"eliminated":eliminated, "elimination_reason":elimination_reason, "failure":failure_reason,
		"damage":effective_damage, "eliminations":eliminations, "assists":assists,
		"component_disables":component_disables, "recoveries":recovery_count}
