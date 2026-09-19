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
var recent_attackers: Dictionary = {}
var _previous_held := false
var _inactive := 0.0
var _hammer_windup := 0.0

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

func can_recover() -> bool:
	return not eliminated and inverted_seconds >= 2.0 and recovery_cooldown <= 0.0 and battery >= 30.0

func tick(delta: float, command: BotCommand, active: bool) -> void:
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
	var powered: bool = eligible and command.primary_held and not command.secondary_held
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
	if stats.weapon == "lifter" and _previous_held and not command.primary_held and not command.secondary_held and eligible and charge >= 1.0:
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
		charge = move_toward(charge, 0.0, delta * (4.0 if command.secondary_held else 1.0))
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
	var powered := eligible and command.primary_held and not command.secondary_held
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
	elif _hammer_windup <= 0.0 and command.primary_pressed and not command.secondary_held:
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
	weapon_phase = "disabled"

func snapshot() -> Dictionary:
	return {"core":core, "core_max":stats.core, "zones":zones.duplicate(),
		"plate_max":stats.plate_integrity, "battery":battery, "battery_max":stats.battery,
		"heat":heat, "charge":charge, "weapon":stats.weapon, "weapon_state":weapon_phase,
		"cooldown":cooldown, "recovery_available":can_recover(), "recovery_remaining":recovery_remaining,
		"recovery_cooldown":recovery_cooldown, "immobilized_remaining":maxf(0, 10 - immobilized_seconds) if immobilized_seconds > 0 else 0.0,
		"eliminated":eliminated, "elimination_reason":elimination_reason, "failure":failure_reason,
		"damage":effective_damage, "eliminations":eliminations, "assists":assists,
		"component_disables":component_disables, "recoveries":recovery_count}
