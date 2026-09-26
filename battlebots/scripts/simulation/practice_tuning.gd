extends RefCounted
## Practice Duel tuning (#84): session-only overrides for the player's bot,
## edited live from the Esc menu and never saved. The offline AuthorityWorld
## owns one per tuned entity and hands it to that bot's CombatState each tick;
## CombatWorld and CombatState read it only through scale(), armour_share(),
## stagger() and heat_enabled, so an untuned bot (and every online or LAN bot)
## plays exactly as before.
##
## Values are absolute. Rate, damage, range, knockback, recoil and AoE apply as
## a scale of the weapon's default; piercing and stagger (strength, % of top
## speed and drive control removed) replace the default. Camera recoil (#91) is
## presentation only: the own-shot camera kick, read by the local preview.
## Loaded by path, not class name: a stale editor class cache must not break it.
const COMBAT_WORLD = preload("res://scripts/weapons/combat_world.gd")
const COMBAT_STATE = preload("res://scripts/simulation/combat_state.gd")
const FRONT_TOOL_TUNING = preload("res://scripts/core/front_tool_tuning.gd")
const CAMERA_RECOIL = preload("res://scripts/core/camera_recoil.gd")
## Drive force behind MvpBot's default acceleration (acceleration = force / mass).
const DRIVE_FORCE := 8.0 * 103.0
## Stagger duration (s) for a weapon that has none by default but is given a strength.
const DEFAULT_STAGGER_SECONDS := 0.3
## Weapon fields in panel order, with their labels and units.
const WEAPON_FIELDS := [
	["rate", "Fire rate", "/s"], ["damage", "Damage", ""], ["range", "Range", "m"],
	["knockback", "Knockback", "×mass"], ["recoil", "Recoil", ""], ["weight", "Weight", "kg"],
	["pierce", "Piercing", "%"], ["aoe", "Area of effect", "m"], ["stagger", "Stagger", "%"],
	["camera_recoil", "Camera recoil", ""]]
## Fields whose override replaces the default instead of scaling it.
const ABSOLUTE := ["pierce", "stagger", "weight", "aoe", "camera_recoil"]

var heat_enabled := true
## Off: a charged jump can be repeated as soon as the bot lands.
var jump_cooldown_enabled := true
## "Allow auto fire" per weapon slot: holding the button repeats press-fired
## weapons (hammer, ram, spear, harpoon) and fires release-fired ones (lifter,
## railgun) as soon as they are fully charged.
var auto_fire := {"primary":false, "secondary":false}
## Debug views (#93), presentation only: draw every shot's path and what each
## impact reached. CombatWorld records marks for this bot while a view is on;
## the preview's PracticeDebugDraw drains them and keeps each on screen for
## debug_linger seconds.
const DEFAULT_DEBUG_LINGER := 5.0
## Marks kept while nothing drains them (no preview, e.g. headless tests).
const MAX_DEBUG_MARKS := 512
## Zones struck through a component rather than armour.
const COMPONENT_ZONES := ["weapon", "drive_left", "drive_right"]
var debug_trajectories := false
var debug_impacts := false
## Wireframes of the other bots' collision shapes and armour zones (drawn from
## the live bots, nothing recorded).
var debug_hitboxes := false
var debug_linger := DEFAULT_DEBUG_LINGER
## {type:"path", points:PackedVector3Array} or {type:"impact", position,
## radius}; radius 0 marks a weapon without an area of effect.
var debug_marks: Array[Dictionary] = []
## slot ("primary"/"secondary") -> {id, title, defaults:{field:value}, values:{field:value}}.
var weapons: Dictionary = {}
## Body defaults and overrides: core, weight, speed, acceleration and grip (m/s²
## as applied), turn (rad/s), jump
## (full-charge take-off speed), nitro (boost multiplier on acceleration and top
## speed), plates {face:value}.
var body_defaults: Dictionary = {}
var body: Dictionary = {}
var _weapon_ids := ["", ""]
var _chassis := ""
var _drive := ""
var _utility := ""
var _state: RefCounted
var _body_dirty := false

## Keeps the tuned bot in step with the overrides. Called by AuthorityWorld
## before the bot steps; a fresh CombatState (restart, respawn, part swap)
## starts from the overridden health and armour.
func apply(bot: MvpBot, registry: ContentRegistry) -> void:
	var state := bot.combat
	var stats := state.stats
	var ids := [str(stats.weapon), _secondary_id(bot)]
	var chassis := str(bot.loadout.parts.get("chassis", ""))
	var drive := str(bot.loadout.parts.get("drive", ""))
	if chassis != _chassis or drive != _drive:
		# A new body or drive (a pickup, or the panel's pickers) has its own plates,
		# weight and handling: start it untuned.
		_chassis = chassis
		_drive = drive
		body_defaults.clear()
		body.clear()
		_weapon_ids = ["", ""]
		weapons.clear()
	if ids != _weapon_ids:
		_configure(bot, registry, ids)
	var fresh := state != _state
	_state = state
	state.practice_tuning = self
	_utility = str(bot.loadout.parts.get("utility", ""))
	if not jump_cooldown_enabled:
		state.jump_cooldown = 0.0
	if body.has("core"):
		stats.core = float(body.core)
		if fresh or _body_dirty: state.core = float(body.core)
	for face: String in body.get("plates", {}):
		if stats.plates.has(face):
			stats.plates[face] = float(body.plates[face])
			if fresh or _body_dirty: state.zones[face] = float(body.plates[face])
	_body_dirty = false
	var mass := total_mass()
	if mass > 0.0 and not is_equal_approx(bot.body.mass, mass):
		bot.body.inertia *= mass / bot.body.mass
		bot.body.mass = mass
	# Acceleration and grip are shown as applied (after the BotPhysics multipliers):
	# the tyres cap the drive force at grip, so raising acceleration past it needs grip too.
	var physics := BotPhysics.settings()
	bot.body.drive_acceleration = float(body.acceleration) / physics.acceleration_multiplier if body.has("acceleration") else DRIVE_FORCE / bot.body.mass
	bot.body.grip_acceleration = float(body.get("grip", body_defaults.grip)) / physics.grip_multiplier
	bot.body.turn_speed = float(body.get("turn", body_defaults.turn))
	bot.body.nitro_boost_scale = float(body.get("nitro", body_defaults.nitro)) / physics.nitro_top_speed_multiplier
	# Max speed is shown as driven too (after the motor multiplier), matching the HUD speedometer.
	bot.body.top_speed = float(body.speed) / physics.top_speed_multiplier if body.has("speed") \
		else float(stats.drive_speed) * physics.top_speed_factor(bot.body.mass)

## Chassis, drive, armour and perks together; the weapons' own weight is separate.
func total_mass() -> float:
	var mass := float(body.get("weight", body_defaults.get("weight", 0.0)))
	for slot: String in weapons:
		mass += value(slot, "weight")
	return mass

func _secondary_id(bot: MvpBot) -> String:
	var stats := bot.combat.stats
	if stats.get("secondary_weapon", "") == "":
		return ""
	return str(bot.loadout.parts.get("utility", ""))

func _configure(bot: MvpBot, registry: ContentRegistry, ids: Array) -> void:
	var stats := bot.combat.stats
	for index: int in 2:
		var slot: String = ["primary", "secondary"][index]
		if ids[index] == _weapon_ids[index] and weapons.has(slot):
			continue
		weapons.erase(slot)
		if ids[index].is_empty():
			continue
		var defaults := _primary_defaults(ids[index]) if index == 0 else _secondary_defaults(stats)
		defaults.weight = float(registry.parts.get(ids[index], {}).get("mass", 0.0))
		# Every weapon can be given a splash (only the mortar has one by default).
		if not defaults.has("aoe"): defaults.aoe = 0.0
		weapons[slot] = {"id":ids[index], "title":str(ids[index]).replace("_", " ").to_upper(),
			"defaults":defaults, "values":{}}
	_weapon_ids = ids.duplicate()
	if body_defaults.is_empty():
		# Read once per body, before any override writes into the stats.
		var weapon_mass := 0.0
		for slot: String in weapons:
			weapon_mass += float(weapons[slot].defaults.weight)
		body_defaults = {"core":float(stats.core), "weight":float(stats.mass) - weapon_mass,
			"speed":float(stats.speed) * BotPhysics.settings().top_speed_multiplier, "acceleration":DRIVE_FORCE / float(stats.mass) * BotPhysics.settings().acceleration_multiplier,
			"grip":bot.body.grip_acceleration * BotPhysics.settings().grip_multiplier, "turn":bot.body.turn_speed,
			"jump":COMBAT_STATE.JUMP_MAX_SPEED, "nitro":BotPhysics.settings().nitro_top_speed_multiplier,
			"plates":stats.plates.duplicate()}

## Default stagger strength in percent (the weapon's STAGGER depth).
static func _stagger_strength(kind: String) -> float:
	return float(COMBAT_WORLD.STAGGER.get(kind, [0.0, 0.0])[1]) * 100.0

func _primary_defaults(id: String) -> Dictionary:
	var tools := FRONT_TOOL_TUNING.settings()
	match id:
		"vertical_spinner":
			return {"rate":1.0 / COMBAT_WORLD.SPINNER_HIT_INTERVAL, "damage":COMBAT_WORLD.VERTICAL_SPINNER_DAMAGE,
				"knockback":COMBAT_WORLD.VERTICAL_SPINNER_KNOCKBACK, "recoil":COMBAT_WORLD.HIT_RECOIL, "pierce":0.0, "stagger":0.0}
		"horizontal_spinner":
			return {"rate":1.0 / COMBAT_WORLD.SPINNER_HIT_INTERVAL, "damage":COMBAT_WORLD.HORIZONTAL_SPINNER_DAMAGE,
				"knockback":COMBAT_WORLD.HORIZONTAL_SPINNER_KNOCKBACK, "recoil":COMBAT_WORLD.HORIZONTAL_SPINNER_RECOIL, "pierce":0.0, "stagger":0.0}
		"hammer":
			return {"rate":1.0 / COMBAT_STATE.HAMMER_COOLDOWN, "damage":COMBAT_WORLD.HAMMER_DAMAGE,
				"knockback":COMBAT_WORLD.HAMMER_KNOCKBACK, "recoil":COMBAT_WORLD.HIT_RECOIL, "pierce":0.0, "stagger":0.0}
		"saw":
			return {"rate":1.0 / COMBAT_WORLD.SAW_CADENCE, "damage":COMBAT_WORLD.SAW_DAMAGE, "pierce":0.0,
				"stagger":_stagger_strength("saw")}
		"lifter":
			return {"rate":1.0 / COMBAT_STATE.LIFTER_COOLDOWN, "damage":COMBAT_WORLD.LIFTER_DAMAGE,
				"knockback":COMBAT_WORLD.LIFTER_KNOCKBACK, "recoil":COMBAT_WORLD.HIT_RECOIL, "pierce":0.0, "stagger":0.0}
		"minigun":
			return _minigun_defaults()
		"battering_ram":
			return {"rate":1.0 / tools.value("ram", "punch_cooldown"), "damage":tools.value("ram", "punch_damage"),
				"knockback":tools.value("ram", "punch_speed"), "recoil":COMBAT_WORLD.RAM_PUNCH_RECOIL, "pierce":0.0,
				"stagger":_stagger_strength("ram_punch")}
		"spear_fork":
			return {"rate":1.0 / tools.value("spear", "cooldown"), "damage":tools.value("spear", "thrust_damage"),
				"knockback":COMBAT_WORLD.SPEAR_KNOCKBACK, "recoil":COMBAT_WORLD.SPEAR_RECOIL,
				"pierce":(1.0 - tools.value("spear", "armour_share")) * 100.0, "stagger":_stagger_strength("spear")}
		"grinder_drum":
			return {"rate":1.0 / tools.value("grinder", "cadence"), "damage":tools.value("grinder", "damage"),
				"knockback":tools.value("grinder", "pull"), "pierce":0.0, "stagger":_stagger_strength("grinder")}
	return {"pierce":0.0, "stagger":0.0}

func _minigun_defaults() -> Dictionary:
	return {"rate":1.0 / COMBAT_STATE.MINIGUN_CADENCE, "damage":COMBAT_WORLD.MINIGUN_DAMAGE,
		"range":COMBAT_WORLD.MINIGUN_RANGE, "knockback":COMBAT_WORLD.MINIGUN_KNOCKBACK,
		"recoil":COMBAT_WORLD.MINIGUN_RECOIL, "pierce":0.0, "stagger":_stagger_strength("minigun"),
		"camera_recoil":CAMERA_RECOIL.per_shot("minigun", "")}

func _secondary_defaults(stats: Dictionary) -> Dictionary:
	var family: String = stats.secondary_weapon
	if family == "minigun":
		return _minigun_defaults()
	var turret := TurretTuning.settings()
	var barrels := maxi(1, int(stats.get("turret_barrels", 1)))
	var defaults := {"rate":1.0 / turret.barrel(family, barrels, "interval"), "damage":turret.value(family, "damage"),
		"knockback":turret.value(family, "knock"), "recoil":turret.barrel(family, barrels, "jolt"),
		"pierce":0.0, "stagger":_stagger_strength(family),
		"camera_recoil":CAMERA_RECOIL.per_shot(family, str(stats.get("turret_model", "")))}
	# The mortar's reach comes from its ballistics; its blast is the only true area.
	if family == "mortar":
		defaults.aoe = turret.value("mortar", "blast_radius")
	else:
		defaults.range = turret.value(family, "range")
	return defaults

## Which tuned weapon dealt a hit of this kind: "primary", "secondary" or ""
## (rams, wall pins and other hull contact belong to no weapon).
func slot_of(stats: Dictionary, kind: String) -> String:
	if kind == "minigun":
		return "primary" if stats.weapon == "minigun" else "secondary"
	if kind == stats.get("secondary_weapon", "") and kind != "":
		return "secondary"
	if kind == stats.weapon or kind in ["ram_punch", "spear", "grinder"]:
		return "primary"
	return ""

func has_field(slot: String, field: String) -> bool:
	return weapons.has(slot) and weapons[slot].defaults.has(field)

func value(slot: String, field: String) -> float:
	if not has_field(slot, field):
		return 0.0
	return float(weapons[slot].values.get(field, weapons[slot].defaults[field]))

func set_value(slot: String, field: String, amount: float) -> void:
	if not has_field(slot, field) or not is_finite(amount) or amount < 0.0:
		return
	if field in ["pierce", "stagger"]:
		amount = minf(amount, 100.0)
	weapons[slot].values[field] = amount

## Drops one weapon override, back to the weapon's default.
func clear_value(slot: String, field: String) -> void:
	if weapons.has(slot):
		weapons[slot].values.erase(field)

## Override over default for a scaled field; 1 when untuned or not applicable.
func scale(slot: String, field: String) -> float:
	if not has_field(slot, field) or not weapons[slot].values.has(field):
		return 1.0
	var base := float(weapons[slot].defaults[field])
	return 1.0 if base <= 0.0 else float(weapons[slot].values[field]) / base

## Only positive defaults can be scaled; absolute fields are always editable.
func editable(slot: String, field: String) -> bool:
	return has_field(slot, field) and (field in ABSOLUTE or float(weapons[slot].defaults[field]) > 0.0)

## Camera kick per shot for the weapon firing `kind`; fallback when untuned.
func camera_recoil(stats: Dictionary, kind: String, fallback: float) -> float:
	var slot := slot_of(stats, kind)
	if not has_field(slot, "camera_recoil"):
		return fallback
	return value(slot, "camera_recoil")

## The part of a hit an intact plate may stop: 1 - piercing.
func armour_share(slot: String, share: float) -> float:
	if not has_field(slot, "pierce") or not weapons[slot].values.has("pierce"):
		return share
	return clampf(1.0 - float(weapons[slot].values.pierce) / 100.0, 0.0, 1.0)

## [seconds, depth] of hit stagger after any override; [] for none. The
## override is the strength (depth, in percent); the duration stays the weapon's.
func stagger(slot: String, fallback: Array) -> Array:
	if not has_field(slot, "stagger") or not weapons[slot].values.has("stagger"):
		return fallback
	var depth := clampf(float(weapons[slot].values.stagger) / 100.0, 0.0, 1.0)
	if depth <= 0.0:
		return []
	return [fallback[0] if not fallback.is_empty() else DEFAULT_STAGGER_SECONDS, depth]

func body_value(field: String, face := "") -> float:
	if field == "plates":
		return float(body.get("plates", {}).get(face, body_defaults.get("plates", {}).get(face, 0.0)))
	return float(body.get(field, body_defaults.get(field, 0.0)))

## Health and armour also take effect at once, as the bot's current value.
func set_body(field: String, amount: float, face := "") -> void:
	if not is_finite(amount) or amount < 0.0 or (field != "plates" and not body_defaults.has(field)):
		return
	if field in ["core", "weight", "speed", "acceleration", "grip", "turn", "jump", "nitro"] and amount <= 0.0:
		return
	if field == "plates":
		if not body_defaults.get("plates", {}).has(face):
			return
		if not body.has("plates"): body.plates = {}
		body.plates[face] = amount
	else:
		body[field] = amount
	_body_dirty = true

## One body value back to its default. Health and armour also refill at once;
## weight, speed and acceleration return to their derived values.
func clear_body(field: String, face := "") -> void:
	if field == "core":
		set_body("core", float(body_defaults.get("core", 0.0)))
	elif field == "plates":
		set_body("plates", float(body_defaults.get("plates", {}).get(face, 0.0)), face)
	else:
		body.erase(field)

## Restores every default and turns heat and the jump cooldown back on.
func reset() -> void:
	for slot: String in weapons:
		weapons[slot].values.clear()
	if body.has("core") or body.has("plates"):
		body = {"core":body_defaults.core, "plates":body_defaults.plates.duplicate()}
		_body_dirty = true
	else:
		body.clear()
	heat_enabled = true
	jump_cooldown_enabled = true
	auto_fire = {"primary":false, "secondary":false}

## A shot's flight path, while trajectories are shown.
func debug_path(points: PackedVector3Array) -> void:
	if debug_trajectories and points.size() >= 2:
		_debug_mark({"type":"path", "points":points})

## What an impact reached: a sphere of radius, or the point itself for 0.
## layer is what a bot hit there took it on (hit_layer), "" for none; for an
## area (radius > 0), "damage" when it damaged something.
func debug_impact(position: Vector3, radius := 0.0, layer := "") -> void:
	if debug_impacts:
		_debug_mark({"type":"impact", "position":position, "radius":maxf(radius, 0.0), "layer":layer})

## What a hit on this zone of a bot lands on first: "armour" (a fitted plate
## not yet broken), "component" (the weapon or a drive pod still working) or
## "core". Shared by the debug impact marks and the hitbox view.
static func hit_layer(combat: RefCounted, zone: String) -> String:
	if float(combat.stats.plates.get(zone, 0.0)) > 0.0 and float(combat.zones.get(zone, 0.0)) > 0.0:
		return "armour"
	if zone in COMPONENT_ZONES and float(combat.zones.get(zone, 0.0)) > 0.0:
		return "component"
	return "core"

func _debug_mark(mark: Dictionary) -> void:
	if debug_marks.size() >= MAX_DEBUG_MARKS:
		debug_marks.pop_front()
	debug_marks.append(mark)

## Hands over the marks recorded since the last call.
func take_debug_marks() -> Array[Dictionary]:
	var marks := debug_marks
	debug_marks = []
	return marks

## The tuned bot's chassis part id.
func chassis() -> String:
	return _chassis

func drive() -> String:
	return _drive

## Charged-jump take-off speed over its default (1 = untuned).
func jump_scale() -> float:
	if not body.has("jump"):
		return 1.0
	return float(body.jump) / COMBAT_STATE.JUMP_MAX_SPEED

## The tuned bot's utility (Weapon 2) part id.
func utility() -> String:
	return _utility

## Radius of a tuned splash for a hit of this kind, 0 for none. The mortar
## keeps its own blast, whose radius tunes through scale("aoe"); the hammer
## blasts where its head lands (CombatWorld._hammer_blasts), hit or miss.
func splash_radius(slot: String, kind: String) -> float:
	if kind in ["mortar", "hammer"] or not has_field(slot, "aoe"):
		return 0.0
	return value(slot, "aoe")
