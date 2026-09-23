class_name CombatState
extends RefCounted
## Pure authoritative combat state. Presentation consumes detached snapshots.
var stats: Dictionary
var core: float
var zones: Dictionary = {}
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
## Hit stagger: seconds left and the share of drive/steer/grip control it removes.
var stagger_seconds := 0.0
var stagger_depth := 0.0
const STAGGER_RECOVERY := 0.3
var _previous_held := false
var _heat_active := false
var _cooling_this_tick := 0.0
var _hammer_windup := 0.0
const MINIGUN_SPINUP := 0.6
const MINIGUN_CADENCE := 1.0 / 12.0
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
## Atlas roof turret. Yaw is chassis-relative; elevation reuses gun_pitch and
## shots reuse the gun shot fields (the turret excludes both miniguns).
## Tuning: data/turret_weapons.json via TurretTuning.
var turret_yaw := 0.0
var _rail_charge := 0.0
var _turret_was_held := false
var _volley_left := 0
var _volley_timer := 0.0
## Grip: a replicated hold on another bot (harpoon tether, spear impalement).
## grip_target is its entity id (0 = none) and grip_point the world anchor;
## CombatWorld forms, moves and breaks it. grip_local is the anchor in the
## victim's frame and never leaves the server.
var grip_target := 0
var grip_point := Vector3.ZERO
var grip_local := Vector3.ZERO
var grip_seconds := 0.0
## Which weapon holds the grip ("harpoon" or "spear"); server only.
var grip_mode := ""
## Front tool pose, replicated 0..1: spear carriage lift or grinder arm raise.
## Ram punch and spear thrust extension ride in charge; grinder spin too.
var tool_pose := 0.0
var _tool_timer := 0.0

func _init(derived: Dictionary) -> void:
	stats = derived.duplicate(true)
	core = stats.core
	# One zone per body face, holding the HP of the armour covering it (0 = bare).
	for face: String in stats.plates:
		zones[face] = float(stats.plates[face])
	zones.merge({"drive_left":100.0, "drive_right":100.0, "weapon":140.0})

## A fresh hit extends and deepens an ongoing stagger; it never shortens it.
func stagger(seconds: float, depth: float) -> void:
	if eliminated or not is_finite(seconds) or not is_finite(depth) or seconds <= 0.0: return
	stagger_seconds = maxf(stagger_seconds, seconds)
	stagger_depth = clampf(maxf(stagger_depth, depth), 0.0, 1.0)

## Remaining drive control, easing back to full over the last STAGGER_RECOVERY seconds.
func stagger_factor() -> float:
	return 1.0 - stagger_depth * clampf(stagger_seconds / STAGGER_RECOVERY, 0.0, 1.0)

func drive_scale() -> float:
	var pods := int(zones.drive_left > 0) + int(zones.drive_right > 0)
	return float(pods) * 0.5

const HEAT_LIMIT := 100.0
const HEAT_RESUME := 50.0
const NITRO_HEAT_RATE := 14.0
const JUMP_HEAT := 20.0
const RECOVERY_HEAT := 30.0

func _add_heat(amount: float) -> void:
	_heat_active = true
	heat = minf(HEAT_LIMIT, heat + _cooling_this_tick + amount)
	_cooling_this_tick = 0.0
	if heat >= HEAT_LIMIT:
		overheated = true

func _nitro_requested(command: BotCommand) -> bool:
	return stats.get("nitro", false) and command.nitro_held and command.throttle > 0.05 \
		and not command.brake and not command.jump_cancel and not overheated and drive_scale() > 0.0

func _enforce_heat_lock() -> void:
	if not overheated:
		return
	# Already committed discrete attacks complete, including a final launch/shot.
	if not strike and not launch and _hammer_windup <= 0.0:
		charge = 0.0
		weapon_phase = "disabled" if zones.weapon <= 0.0 else "overheated"
	secondary_charge = 0.0
	secondary_active = false
	nitro_active = false

func tick_perks(delta: float, command: BotCommand, active: bool, grounded: bool) -> void:
	jump_release_speed = 0.0
	nitro_active = false
	if not active or eliminated or command.jump_cancel:
		jump_charge = 0.0
		_jump_was_held = false
		return
	jump_cooldown = maxf(0.0, jump_cooldown - delta)
	if _nitro_requested(command):
		nitro_active = true
		_add_heat(NITRO_HEAT_RATE * delta)
	if stats.get("charged_jump", false):
		if command.jump_held and grounded and jump_cooldown <= 0.0 and not overheated:
			jump_charge = minf(1.0, jump_charge + delta / 1.2)
		elif not command.jump_held:
			if _jump_was_held and jump_charge > 0.0 and grounded and not overheated and jump_cooldown <= 0.0:
				_add_heat(JUMP_HEAT)
				jump_release_speed = lerpf(3.5, 7.5, jump_charge)
				jump_cooldown = 4.0
			jump_charge = 0.0
		elif not grounded or overheated:
			jump_charge = 0.0
		_jump_was_held = command.jump_held
	_enforce_heat_lock()

func can_recover() -> bool:
	return not eliminated and inverted_seconds >= 2.0 and recovery_cooldown <= 0.0 and not overheated

func tick(delta: float, command: BotCommand, active: bool) -> void:
	gun_shot = false
	stagger_seconds = maxf(0.0, stagger_seconds - delta)
	if stagger_seconds <= 0.0: stagger_depth = 0.0
	secondary_active = false
	_heat_active = false
	_cooling_this_tick = 0.0
	if active and not eliminated and overheated and heat <= HEAT_RESUME:
		overheated = false
	_tick_primary(delta, command, active)
	if not active or eliminated:
		secondary_charge = 0.0
		_gun_cooldown = 0.0
		_volley_left = 0
		_rail_charge = 0.0
		_turret_was_held = false
		release_grip()
		return
	if is_turret():
		_tick_turret(delta, command.auxiliary_held)
	elif stats.get("secondary_weapon", "") == "minigun":
		_tick_minigun(delta, command.auxiliary_held, true)
	# Perks follow weapons in MvpBot.step. A later perk activation reverses this
	# tentative cooling before adding heat, including a warm jump release.
	if not _heat_active:
		_cooling_this_tick = minf(heat, float(stats.cooling) * delta)
		heat -= _cooling_this_tick
	_enforce_heat_lock()

func is_turret() -> bool:
	return stats.get("secondary_weapon", "") in AtlasGeometry.TURRET_FAMILIES

func _secondary_brake(command: BotCommand) -> bool:
	return command.secondary_held and not (stats.get("secondary_weapon", "") != "" and command.auxiliary_held)

## One shot per reload (cannon) or cadence pulse (plasma).
func _tick_turret(delta: float, held: bool) -> void:
	if stats.secondary_weapon in AtlasGeometry.TURRET_SPECIALS:
		_tick_special_turret(delta, held)
		_turret_was_held = held
		return
	var tuning := TurretTuning.settings()
	var family: String = stats.secondary_weapon
	var cannon := family == "cannon"
	var barrels := maxi(1, int(stats.get("turret_barrels", 1)))
	var interval := tuning.barrel(family, barrels, "interval")
	var shot_heat := tuning.barrel(family, barrels, "heat")
	_gun_cooldown = maxf(0.0, _gun_cooldown - delta)
	if _gun_cooldown < 0.000001:
		_gun_cooldown = 0.0
	var eligible: bool = zones.weapon > 0.0 and not overheated
	if not eligible:
		_volley_left = 0
	if held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0.0 else "overheated"
	if cannon and _volley_left > 0:
		# A committed volley keeps rippling through its barrels once started.
		_volley_timer -= delta
		if _volley_timer <= 0.000001:
			_fire_turret_shot(shot_heat)
			_volley_left = _volley_left - 1 if gun_shot else 0
			_volley_timer = tuning.volley_spacing
			if _volley_left == 0:
				_gun_cooldown = interval
	elif held and eligible and _gun_cooldown <= 0.0:
		_fire_turret_shot(shot_heat)
		if cannon and gun_shot:
			_volley_left = barrels - 1
			_volley_timer = tuning.volley_spacing
			if _volley_left == 0:
				_gun_cooldown = interval
		elif gun_shot:
			_gun_cooldown = interval
	if held and eligible:
		_heat_active = true
	if zones.weapon <= 0.0:
		_gun_cooldown = interval
	var loading := 1.0 if _volley_left > 0 else 1.0 - _gun_cooldown / interval
	secondary_charge = 0.0 if zones.weapon <= 0.0 or overheated else clampf(loading, 0.0, 1.0)
	secondary_active = gun_shot if cannon else held and eligible and not overheated

func _tick_special_turret(delta: float, held: bool) -> void:
	var tuning := TurretTuning.settings()
	var family: String = stats.secondary_weapon
	var interval := tuning.barrel(family, 1, "interval")
	var shot_heat := tuning.barrel(family, 1, "heat")
	_gun_cooldown = maxf(0.0, _gun_cooldown - delta)
	if _gun_cooldown < 0.000001:
		_gun_cooldown = 0.0
	var eligible: bool = zones.weapon > 0.0 and not overheated
	if held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0.0 else "overheated"
	if held and eligible:
		_heat_active = true
	match family:
		"flamer":
			if held and eligible and _gun_cooldown <= 0.0:
				_fire_turret_shot(shot_heat)
				_gun_cooldown = interval
			secondary_active = held and eligible
			secondary_charge = 0.0 if not eligible else 1.0
		"tesla":
			if held and eligible and _gun_cooldown <= 0.0:
				_fire_turret_shot(shot_heat)
				_gun_cooldown = interval
			secondary_active = gun_shot
			secondary_charge = 0.0 if not eligible else 1.0 - _gun_cooldown / interval
		"railgun":
			if held and eligible and _gun_cooldown <= 0.0:
				_rail_charge = minf(1.0, _rail_charge + delta / tuning.value("railgun", "charge_seconds"))
				_add_heat(tuning.value("railgun", "charge_heat_per_second") * delta)
			elif not held and _turret_was_held and _rail_charge >= 1.0 and eligible:
				# Release a full charge; an early release simply discharges.
				_fire_turret_shot(shot_heat)
				_gun_cooldown = interval
			if not held or not eligible:
				_rail_charge = 0.0
			secondary_active = held and eligible and _gun_cooldown <= 0.0
			secondary_charge = _rail_charge if _gun_cooldown <= 0.0 else 1.0 - _gun_cooldown / interval
		"mortar":
			# One lobbed shell per reload; the world flies and detonates it.
			if held and eligible and _gun_cooldown <= 0.0:
				_fire_turret_shot(shot_heat)
				_gun_cooldown = interval
			secondary_active = gun_shot
			secondary_charge = 0.0 if not eligible else 1.0 - _gun_cooldown / interval
		"harpoon":
			# Press to fire; while the tether holds, keep holding to reel the
			# target in. A fresh press cuts the cable. Reloads after either.
			var pressed := held and not _turret_was_held
			if grip_target != 0 and grip_mode == "harpoon":
				if pressed:
					release_grip()
					_gun_cooldown = interval
				elif held and eligible:
					_add_heat(tuning.value("harpoon", "reel_heat_per_second") * delta)
			elif pressed and eligible and _gun_cooldown <= 0.0 and grip_target == 0:
				_fire_turret_shot(shot_heat)
				_gun_cooldown = interval
			var tethered := grip_target != 0 and grip_mode == "harpoon"
			if zones.weapon <= 0.0 and tethered:
				release_grip()
				tethered = false
			secondary_active = tethered and held and eligible
			secondary_charge = 0.0 if not eligible else (1.0 if tethered else 1.0 - _gun_cooldown / interval)

## Drops any hold on another bot (the world also calls this when it breaks).
func release_grip() -> void:
	grip_target = 0
	grip_point = Vector3.ZERO
	grip_local = Vector3.ZERO
	grip_seconds = 0.0
	grip_mode = ""

## One shot, paid in shared heat. The world resolves it along barrel
## (sequence - 1) % barrels.
func _fire_turret_shot(shot_heat: float) -> void:
	_add_heat(shot_heat)
	gun_shot = true
	shot_sequence += 1

func _tick_primary(delta: float, command: BotCommand, active: bool) -> void:
	launch = false
	strike = false
	failure_reason = ""
	if not active or eliminated:
		charge = 0.0
		_hammer_windup = 0.0
		_previous_held = false
		tool_pose = 0.0
		_tool_timer = 0.0
		weapon_phase = "disabled" if eliminated else "idle"
		return
	if stats.weapon != "hammer":
		cooldown = maxf(0, cooldown - delta)
	recovery_cooldown = maxf(0, recovery_cooldown - delta)
	recovery_remaining = maxf(0, recovery_remaining - delta)
	if recovery_remaining < 0.000001:
		recovery_remaining = 0.0
	if command.recovery_pressed:
		if can_recover():
			_add_heat(RECOVERY_HEAT)
			recovery_remaining = stats.recovery_seconds
			recovery_cooldown = 20.0
			recovery_count += 1
		else:
			failure_reason = "overheated" if overheated else "recovery_unavailable"
	if stats.weapon == "minigun":
		_tick_minigun(delta, command.primary_held and not _secondary_brake(command), false)
		return
	if stats.weapon == "hammer":
		_tick_hammer(delta, command)
		return
	if stats.weapon == "saw":
		_tick_saw(delta, command)
		return
	if stats.weapon in AtlasGeometry.TOOL_PARTS:
		_tick_tool(delta, command)
		return
	var eligible: bool = zones.weapon > 0 and not overheated and cooldown <= 0
	var powered: bool = eligible and command.primary_held and not _secondary_brake(command)
	var spinner: bool = stats.weapon in ["vertical_spinner", "horizontal_spinner"]
	var heat_rate := 12.0 if spinner else 4.0
	var spinup := 2.0 if stats.weapon == "horizontal_spinner" else (1.5 if spinner else 1.0)
	if command.primary_held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0 else ("overheated" if overheated else "cooldown")
	if powered:
		_add_heat(heat_rate * delta)
		charge = minf(1, charge + delta / spinup)
	# Preserve #38's partial release threshold and charge-scaled launch.
	if stats.weapon == "lifter" and _previous_held and not command.primary_held and not _secondary_brake(command) and eligible \
			and charge >= BotPhysics.settings().lifter_min_release_charge:
		_add_heat(18.0)
		cooldown = 3.0
		attack_id += 1
		launch = true
	if not powered:
		charge = move_toward(charge, 0.0, delta * (4.0 if _secondary_brake(command) else 1.0))
	if zones.weapon <= 0:
		charge = 0.0
	weapon_phase = "disabled" if zones.weapon <= 0 else ("launch" if launch else ("overheated" if overheated else (
		"cooldown" if cooldown > 0 else ("active" if powered else "idle"))))
	_previous_held = command.primary_held

## Atlas front tools (data/front_tools.json). Ram and spear: a press fires a
## committed punch/thrust (strike while it extends, charge = extension). The
## spear then holds what it impaled while primary is held, lifting it
## (tool_pose). Grinder: primary spins the drum (charge), secondary raises the
## arms (tool_pose).
func _tick_tool(delta: float, command: BotCommand) -> void:
	var tuning := FrontToolTuning.settings()
	var tool: String = AtlasGeometry.TOOL_PARTS[stats.weapon]
	var eligible: bool = zones.weapon > 0.0 and not overheated
	var trigger := command.primary_held and not _secondary_brake(command)
	var pressed := trigger and not _previous_held
	var powered := false
	if tool == "grinder":
		powered = eligible and trigger
		var spinup := tuning.value("grinder", "spinup_seconds")
		if powered:
			_add_heat(tuning.value("grinder", "heat_per_second") * delta)
			charge = minf(1.0, charge + delta / spinup)
		else:
			charge = move_toward(charge, 0.0, delta / spinup * 0.7)
		if trigger and not eligible:
			failure_reason = "disabled" if zones.weapon <= 0.0 else "overheated"
		var raise := 1.0 if _secondary_brake(command) and zones.weapon > 0.0 else 0.0
		tool_pose = move_toward(tool_pose, raise, delta / tuning.value("grinder", "raise_seconds"))
	else:
		var ram := tool == "ram"
		var seconds := tuning.value(tool, "punch_seconds" if ram else "thrust_seconds")
		if pressed and _tool_timer <= 0.0 and grip_mode != "spear":
			if not eligible or cooldown > 0.0:
				failure_reason = "disabled" if zones.weapon <= 0.0 else ("overheated" if overheated else "cooldown")
			else:
				attack_id += 1
				_tool_timer = seconds
				cooldown = tuning.value(tool, "punch_cooldown" if ram else "cooldown")
				_add_heat(tuning.value(tool, "punch_heat" if ram else "thrust_heat"))
		charge = 0.0
		if _tool_timer > 0.0:
			_tool_timer = maxf(0.0, _tool_timer - delta)
			if _tool_timer < 0.000001: _tool_timer = 0.0
			strike = true
			# Out fast and back: the extension peaks mid-stroke.
			charge = sin(PI * clampf(1.0 - _tool_timer / seconds, 0.0, 1.0))
			if _tool_timer <= 0.0: charge = 0.0
		if not ram:
			var holding := grip_target != 0 and grip_mode == "spear"
			powered = holding and trigger
			if powered:
				_add_heat(tuning.value("spear", "hold_heat_per_second") * delta)
			tool_pose = move_toward(tool_pose, 1.0 if powered else 0.0, delta / tuning.value("spear", "lift_seconds"))
	if zones.weapon <= 0.0:
		charge = 0.0
	weapon_phase = "disabled" if zones.weapon <= 0.0 else ("strike" if strike else ("overheated" if overheated else (
		"active" if powered else ("cooldown" if cooldown > 0.0 else "idle"))))
	_previous_held = trigger

func _tick_saw(delta: float, command: BotCommand) -> void:
	var eligible: bool = zones.weapon > 0.0 and not overheated and cooldown <= 0.0
	var powered := eligible and command.primary_held and not _secondary_brake(command)
	if command.primary_held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0.0 else ("overheated" if overheated else "cooldown")
	if powered:
		_add_heat(14.0 * delta)
		powered = not overheated
	charge = 1.0 if powered else 0.0
	weapon_phase = "disabled" if zones.weapon <= 0.0 else ("overheated" if overheated else (
		"cooldown" if cooldown > 0.0 else ("active" if powered else "idle")))

func _tick_hammer(delta: float, command: BotCommand) -> void:
	# A press during cooldown is discarded even when this tick finishes it.
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
		else:
			attack_id += 1
			_hammer_windup = 0.35
	if _hammer_windup > 0.0:
		_hammer_windup = maxf(0.0, _hammer_windup - delta)
		charge = clampf(1.0 - _hammer_windup / 0.35, 0.0, 1.0)
		_heat_active = true
		if _hammer_windup < 0.000001:
			_hammer_windup = 0.0
			charge = 1.0
			strike = true
			cooldown = 1.4
			_add_heat(20.0)
	else:
		charge = 0.0
	weapon_phase = "disabled" if zones.weapon <= 0 else ("strike" if strike else (
		"windup" if _hammer_windup > 0.0 else ("overheated" if overheated else ("cooldown" if cooldown > 0.0 else "idle"))))

func _tick_minigun(delta: float, held: bool, auxiliary: bool) -> void:
	var spool := secondary_charge if auxiliary else charge
	var eligible: bool = zones.weapon > 0.0 and not overheated
	var powered := held and eligible
	_gun_cooldown = maxf(0.0, _gun_cooldown - delta)
	if held and not eligible:
		failure_reason = "disabled" if zones.weapon <= 0.0 else "overheated"
	if powered:
		_add_heat(3.0 * delta)
		spool = minf(1.0, spool + delta / MINIGUN_SPINUP)
		if overheated:
			powered = false
		elif spool >= 1.0 - 0.000001 and _gun_cooldown <= 0.000001:
			_add_heat(MINIGUN_SHOT_HEAT)
			gun_shot = true
			shot_sequence += 1
			_gun_cooldown = MINIGUN_CADENCE
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

## armour_share is the part of a hit an intact plate may stop; the rest always
## reaches the core (wall pins crush through armour).
func damage(zone: String, raw: float, armour_share := 1.0) -> int:
	if eliminated or not is_finite(raw) or raw <= 0:
		return 0
	var core_damage := 0.0
	var component_damage := 0.0
	if stats.plates.has(zone):
		# Intact armour fully shields its face; only damage beyond its remaining
		# HP reaches the core. A bare face passes every hit to the core.
		component_damage = minf(zones[zone], raw * clampf(armour_share, 0.0, 1.0))
		core_damage = raw - component_damage
	elif zone in ["drive_left", "drive_right", "weapon"]:
		core_damage = raw * 0.25
		component_damage = minf(zones[zone], raw * 0.75)
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
	stagger_seconds = 0.0
	stagger_depth = 0.0

func snapshot() -> Dictionary:
	return {"core":core, "core_max":stats.core, "zones":zones.duplicate(),
		"plate_max":stats.plates.duplicate(), "overheated":overheated,
		"heat":heat, "charge":charge, "weapon":stats.weapon, "weapon_state":weapon_phase,
		"secondary_charge":secondary_charge, "secondary_active":secondary_active,
		"shot_sequence":shot_sequence, "last_shot_from":last_shot_from,
		"last_shot_to":last_shot_to, "last_shot_tick":last_shot_tick,
		"gun_pitch":gun_pitch, "turret_yaw":turret_yaw, "grip_target":grip_target, "grip_point":grip_point, "tool_pose":tool_pose,
		"nitro_active":nitro_active, "jump_charge":jump_charge, "jump_cooldown":jump_cooldown,
		"cooldown":cooldown, "recovery_available":can_recover(), "recovery_remaining":recovery_remaining,
		"recovery_cooldown":recovery_cooldown, "immobilized_remaining":maxf(0, 10 - immobilized_seconds) if immobilized_seconds > 0 else 0.0,
		"eliminated":eliminated, "elimination_reason":elimination_reason, "failure":failure_reason,
		"damage":effective_damage, "eliminations":eliminations, "assists":assists,
		"component_disables":component_disables, "recoveries":recovery_count}
