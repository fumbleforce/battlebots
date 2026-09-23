class_name ArmourLayout
extends RefCounted
## Per-plate armour, damage profiles and mass effects accepted for issue #19.
## Pure rules only: the catalogue, CombatState, CombatWorld and garage still use
## the legacy four-side package until the prototype task integrates this module.
## See docs/coordination/B_ARMOUR_WEAPON_DIRECTION.md. Values are tunable seeds.

const PLATES := ["front", "rear", "left", "right", "top", "underside"]
const COMPONENTS := ["drive_left", "drive_right", "weapon"]
# Per-plate mass is a quarter of the legacy package, so a migrated four-side
# layout keeps the exact mass, reduction and integrity it has today.
const CLASSES := {
	"none": {"mass": 0.0, "reduction": 0.0, "integrity": 0.0},
	"light": {"mass": 2.5, "reduction": 0.10, "integrity": 60.0},
	"standard": {"mass": 4.5, "reduction": 0.25, "integrity": 90.0},
	"heavy": {"mass": 6.25, "reduction": 0.40, "integrity": 120.0}}
const LEGACY_PACKAGES := {"light": "light", "standard_armor": "standard", "heavy": "heavy"}
## The bare chassis skin: an absent or destroyed plate still stops this much.
const BASELINE_REDUCTION := 0.05
## plate: multiplier on plate damage. core: multiplier on core damage.
## pierce: fraction of the plate's reduction that the hit ignores.
## drive: multiplier on damage dealt to drive components (legs, wheels, tracks).
const PROFILES := {
	"standard": {"plate": 1.0, "core": 1.0, "pierce": 0.0, "drive": 1.0},
	"piercing": {"plate": 0.4, "core": 1.0, "pierce": 0.6, "drive": 1.0},
	"explosive": {"plate": 1.6, "core": 0.5, "pierce": 0.0, "drive": 1.0},
	"cutting": {"plate": 1.2, "core": 0.8, "pierce": 0.0, "drive": 1.0},
	"sweeping": {"plate": 1.0, "core": 0.7, "pierce": 0.0, "drive": 1.5}}
## Existing weapons keep the legacy result except where the sketch names a role.
const WEAPON_PROFILES := {
	"vertical_spinner": "standard", "horizontal_spinner": "sweeping", "hammer": "standard",
	"saw": "cutting", "lifter": "standard", "minigun": "standard", "ram": "standard"}
const MAX_WEAPONS := 2
const MASS_LIMIT := 120.0
const POWER_LIMIT := 100.0
## Mass at which speed and impulse response are unchanged.
const REFERENCE_MASS := 100.0
const SPEED_PER_KG := 0.005
const SPEED_FACTOR_RANGE := Vector2(0.9, 1.1)
const IMPULSE_RESPONSE_RANGE := Vector2(0.7, 1.5)
## Ram damage keeps the legacy 4 m/s threshold and 2 damage per m/s above it.
const RAM_THRESHOLD := 4.0
const RAM_PER_SPEED := 2.0
const RAM_MASS_RATIO_RANGE := Vector2(0.5, 2.0)
const RAM_CAP := 24.0
const DRIVE_RAM := {"agile": 0.6, "standard_wheels": 0.8, "traction": 1.5, "walker": 0.5}

static func preset(armour_class: String, underside := false) -> Dictionary:
	var layout := {}
	for plate: String in PLATES:
		layout[plate] = armour_class
	if not underside:
		layout.underside = "none"
	return layout

static func default_layout() -> Dictionary:
	return preset("standard")

## Legacy packages cover four sides only; top and underside stay bare.
static func from_legacy_package(part_id: String) -> Dictionary:
	var layout := preset(LEGACY_PACKAGES.get(part_id, "standard"))
	layout.top = "none"
	return layout

static func valid(layout: Variant) -> bool:
	if not layout is Dictionary or layout.size() != PLATES.size():
		return false
	for plate: String in PLATES:
		var armour_class: Variant = layout.get(plate)
		if not armour_class is String or not CLASSES.has(armour_class):
			return false
	return true

static func mass(layout: Dictionary) -> float:
	var total := 0.0
	for plate: String in PLATES:
		total += float(CLASSES[layout[plate]].mass)
	return total

## Starting integrity for every plate zone; absent plates start at zero.
static func integrity(layout: Dictionary) -> Dictionary:
	var zones := {}
	for plate: String in PLATES:
		zones[plate] = float(CLASSES[layout[plate]].integrity)
	return zones

static func profile_for(kind: String) -> Dictionary:
	return PROFILES[WEAPON_PROFILES.get(kind, "standard")]

## Splits one hit into zone and core damage using the zone state at the start
## of the hit. Does not mutate anything; the caller clamps core and applies it.
static func route(layout: Dictionary, zones: Dictionary, zone: String, raw: float, profile: Dictionary) -> Dictionary:
	var result := {"zone": 0.0, "core": 0.0}
	if not is_finite(raw) or raw <= 0:
		return result
	if zone in COMPONENTS:
		var component_scale := float(profile.drive) if zone != "weapon" else 1.0
		result.zone = minf(float(zones.get(zone, 0.0)), raw * 0.75 * component_scale)
		result.core = raw * 0.25 * float(profile.core)
		return result
	if not zone in PLATES:
		return result
	var remaining := float(zones.get(zone, 0.0))
	var reduction := BASELINE_REDUCTION
	if remaining > 0 and layout.get(zone, "none") != "none":
		reduction = float(CLASSES[layout[zone]].reduction) * (1.0 - float(profile.pierce))
		result.zone = minf(remaining, raw * float(profile.plate))
	result.core = raw * float(profile.core) * (1.0 - reduction)
	return result

## Lighter builds gain top speed and heavier builds lose it, within the range.
static func top_speed_factor(total_mass: float) -> float:
	return clampf(1.0 + (REFERENCE_MASS - total_mass) * SPEED_PER_KG, SPEED_FACTOR_RANGE.x, SPEED_FACTOR_RANGE.y)

## Velocity-change multiplier for fixed-impulse sources: gun recoil and blast
## shockwaves move a light build further than a heavy one.
static func impulse_response(total_mass: float) -> float:
	return clampf(REFERENCE_MASS / maxf(total_mass, 1.0), IMPULSE_RESPONSE_RANGE.x, IMPULSE_RESPONSE_RANGE.y)

## Collision damage dealt by the attacker. Mass ratio and drive decide it:
## tracks are the unstoppable force; wheels and legs deal little.
static func ram_damage(closing_speed: float, attacker_mass: float, victim_mass: float, attacker_drive: String) -> float:
	if not is_finite(closing_speed) or closing_speed <= RAM_THRESHOLD:
		return 0.0
	var ratio := clampf(attacker_mass / maxf(victim_mass, 1.0), RAM_MASS_RATIO_RANGE.x, RAM_MASS_RATIO_RANGE.y)
	var raw := RAM_PER_SPEED * (closing_speed - RAM_THRESHOLD) * ratio * float(DRIVE_RAM.get(attacker_drive, 1.0))
	return minf(RAM_CAP, raw)

## Mass/power budget for the proposed schema: one armour layout and up to two
## weapons. `parts` is the catalogue by id; `selection` holds part ids for
## chassis, drive, utility and nitro/suspension perks, "weapons" as an array
## and "armour" as a plate layout.
static func budget(parts: Dictionary, selection: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	var total_mass := 0.0
	var total_power := 0.0
	for slot: String in ["chassis", "drive", "utility", "nitro", "suspension"]:
		var part: Dictionary = parts.get(selection.get(slot, ""), {})
		if part.get("category") != slot:
			reasons.append("Unknown or missing part in " + slot)
			continue
		total_mass += float(part.mass)
		total_power += float(part.power)
	var weapons: Variant = selection.get("weapons")
	if not weapons is Array or weapons.size() not in range(1, MAX_WEAPONS + 1):
		reasons.append("Select one or two weapons")
	else:
		for id: Variant in weapons:
			var part: Dictionary = parts.get(id, {}) if id is String else {}
			if part.get("category") != "weapon":
				reasons.append("Unknown weapon " + str(id))
				continue
			total_mass += float(part.mass)
			total_power += float(part.power)
	var layout: Variant = selection.get("armour")
	if not valid(layout):
		reasons.append("Invalid armour layout")
	else:
		total_mass += mass(layout)
	if total_mass > MASS_LIMIT:
		reasons.append("Mass exceeds %d kg" % MASS_LIMIT)
	if total_power > POWER_LIMIT:
		reasons.append("Installed power exceeds %d" % POWER_LIMIT)
	return {"mass": total_mass, "power": total_power, "reasons": reasons}
