extends SceneTree
## Proposed per-plate armour rules (#19): layouts, legacy parity with the live
## CombatState, damage profiles, mass effects and the two-weapon budget.
var failures := 0
var registry := ContentRegistry.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.000001, "%s: expected %.6f, got %.6f" % [message, expected, actual])

func run() -> void:
	layouts()
	legacy_parity()
	exposed_faces()
	profiles()
	mass_effects()
	weapon_budget()
	print("ARMOUR LAYOUT PASS" if failures == 0 else "ARMOUR LAYOUT FAIL")
	quit(0 if failures == 0 else 1)

func layouts() -> void:
	var standard := ArmourLayout.default_layout()
	check(ArmourLayout.valid(standard), "Default layout is valid")
	check(standard.top == "standard" and standard.underside == "none", "Default covers five faces; underside is optional")
	near(ArmourLayout.mass(standard), 22.5, "Five standard plates")
	near(ArmourLayout.mass(ArmourLayout.preset("heavy", true)), 37.5, "Six heavy plates")
	near(ArmourLayout.mass(ArmourLayout.preset("light")), 12.5, "Five light plates")
	var custom := ArmourLayout.preset("heavy")
	custom.front = "none"
	near(ArmourLayout.mass(custom), 25.0, "Dropping the front plate saves its mass")
	check(ArmourLayout.integrity(custom).front == 0.0 and ArmourLayout.integrity(custom).rear == 120.0, "Absent plates start at zero integrity")
	check(not ArmourLayout.valid({"front": "light"}), "Missing plates are rejected")
	var bad := ArmourLayout.default_layout()
	bad.top = "titanium"
	check(not ArmourLayout.valid(bad), "Unknown armour classes are rejected")
	check(not ArmourLayout.valid("standard"), "Non-dictionary layouts are rejected")
	check(ArmourLayout.preset("light").front == "light" and ArmourLayout.default_layout().front == "standard", "Presets return detached layouts")

## A migrated legacy package must deal exactly the damage the live rules deal.
func legacy_parity() -> void:
	for package: String in ArmourLayout.LEGACY_PACKAGES:
		var draft := registry.starter()
		draft.parts.armor = package
		var result := registry.validate(draft)
		check(result.valid, "Legacy %s starter validates" % package)
		var layout := ArmourLayout.from_legacy_package(package)
		near(ArmourLayout.mass(layout), float(registry.parts[package].mass), "%s migrates at identical mass" % package)
		var state := CombatState.new(result.stats)
		var zones := ArmourLayout.integrity(layout)
		var core: float = result.stats.core
		var profile := ArmourLayout.profile_for("hammer")
		for hit: Array in [["front", 38.0], ["left", 45.0], ["top", 20.0], ["underside", 12.0], ["drive_left", 30.0], ["weapon", 40.0], ["front", 10.0]]:
			zones.merge({"drive_left": state.zones.drive_left, "drive_right": state.zones.drive_right, "weapon": state.zones.weapon}, true)
			var routed := ArmourLayout.route(layout, zones, hit[0], hit[1], profile)
			var before: float = state.core
			state.damage(hit[0], hit[1])
			near(before - state.core, minf(core, routed.core), "%s %s core parity" % [package, hit[0]])
			core -= minf(core, routed.core)
			if zones.has(hit[0]) and state.zones.has(hit[0]):
				zones[hit[0]] -= routed.zone
				near(zones[hit[0]], state.zones[hit[0]], "%s %s zone parity" % [package, hit[0]])

func exposed_faces() -> void:
	var layout := ArmourLayout.default_layout()
	var profile := ArmourLayout.profile_for("hammer")
	var zones := ArmourLayout.integrity(layout)
	near(ArmourLayout.route(layout, zones, "underside", 40, profile).core, 38, "Bare underside keeps the 5% chassis baseline")
	near(ArmourLayout.route(layout, zones, "top", 40, profile).core, 30, "A top plate now protects the core")
	zones.front = 0.0
	var destroyed := ArmourLayout.route(layout, zones, "front", 40, profile)
	near(destroyed.core, 38, "A destroyed plate falls back to the baseline")
	near(destroyed.zone, 0, "A destroyed plate takes no further damage")
	zones = ArmourLayout.integrity(layout)
	near(ArmourLayout.route(layout, zones, "front", 200, profile).zone, 90, "Plate damage is clamped to remaining integrity")
	near(ArmourLayout.route(layout, zones, "front", -5, profile).core, 0, "Negative damage is ignored")
	near(ArmourLayout.route(layout, zones, "front", NAN, profile).core, 0, "Non-finite damage is ignored")
	near(ArmourLayout.route(layout, zones, "turret", 40, profile).core, 0, "Unknown zones deal nothing")

func profiles() -> void:
	var layout := ArmourLayout.preset("heavy")
	var zones := ArmourLayout.integrity(layout)
	var standard := ArmourLayout.route(layout, zones, "front", 40, ArmourLayout.PROFILES.standard)
	var piercing := ArmourLayout.route(layout, zones, "front", 40, ArmourLayout.PROFILES.piercing)
	var explosive := ArmourLayout.route(layout, zones, "front", 40, ArmourLayout.PROFILES.explosive)
	check(piercing.core > standard.core and piercing.zone < standard.zone, "Piercing favours the core over the plate")
	check(explosive.zone > standard.zone and explosive.core < standard.core, "Explosive strips plates but spares the core")
	near(piercing.core, 40 * (1 - 0.4 * 0.4), "Piercing ignores 60% of heavy reduction")
	near(explosive.zone, 64, "Explosive deals 160% to the plate")
	var walker_hit := ArmourLayout.route(layout, {"drive_left": 100.0}, "drive_left", 40, ArmourLayout.profile_for("horizontal_spinner"))
	var saw_hit := ArmourLayout.route(layout, {"drive_left": 100.0}, "drive_left", 40, ArmourLayout.profile_for("vertical_spinner"))
	check(walker_hit.zone > saw_hit.zone, "The horizontal spinner shreds drive components such as legs")
	near(ArmourLayout.route(layout, {"weapon": 140.0}, "weapon", 40, ArmourLayout.profile_for("horizontal_spinner")).zone, 30, "The drive bonus does not apply to the weapon zone")
	check(ArmourLayout.profile_for("unknown") == ArmourLayout.PROFILES.standard, "Unlisted weapons use the standard profile")
	for kind: String in ArmourLayout.WEAPON_PROFILES:
		check(ArmourLayout.PROFILES.has(ArmourLayout.WEAPON_PROFILES[kind]), "%s names a defined profile" % kind)

func mass_effects() -> void:
	near(ArmourLayout.top_speed_factor(100), 1.0, "Reference mass keeps drive speed")
	check(ArmourLayout.top_speed_factor(85) > 1.0 and ArmourLayout.top_speed_factor(118) < 1.0, "Light builds are faster, heavy builds slower")
	near(ArmourLayout.top_speed_factor(0), 1.1, "Speed bonus is capped")
	near(ArmourLayout.top_speed_factor(500), 0.9, "Speed penalty is capped")
	check(ArmourLayout.impulse_response(80) > ArmourLayout.impulse_response(118), "Light builds are pushed further by recoil and blasts")
	near(ArmourLayout.impulse_response(0), 1.5, "Impulse response is capped for degenerate mass")
	near(ArmourLayout.ram_damage(4, 120, 90, "traction"), 0, "No ram damage at the legacy threshold")
	near(ArmourLayout.ram_damage(8, 100, 100, "unknown"), 8, "Equal masses keep the legacy ram slope")
	check(ArmourLayout.ram_damage(8, 118, 90, "traction") > ArmourLayout.ram_damage(8, 90, 118, "agile"), "Heavy tracks out-ram light wheels")
	check(ArmourLayout.ram_damage(8, 100, 100, "walker") < ArmourLayout.ram_damage(8, 100, 100, "standard_wheels"), "Legs deal the least collision damage")
	near(ArmourLayout.ram_damage(40, 120, 60, "traction"), ArmourLayout.RAM_CAP, "Ram damage is capped")

func weapon_budget() -> void:
	var selection := {"chassis": "balanced", "drive": "standard_wheels", "utility": "recovery_assist",
		"nitro": "nitro_boost", "suspension": "charged_jump",
		"weapons": ["lifter", "hammer"], "armour": ArmourLayout.default_layout()}
	var result := ArmourLayout.budget(registry.parts, selection)
	check(result.reasons.has("Mass exceeds 120 kg"), "Ramp + hammer with five standard plates is over the mass limit")
	near(result.power, 100, "Ramp + hammer on standard wheels fills the power budget exactly")
	selection.armour = ArmourLayout.preset("light")
	result = ArmourLayout.budget(registry.parts, selection)
	check(result.reasons.is_empty(), "Trading down to light plates makes ramp + hammer legal: %s" % [result.reasons])
	near(result.mass, 115.5, "Ramp + hammer light build mass")
	selection.weapons = ["vertical_spinner", "horizontal_spinner"]
	check(ArmourLayout.budget(registry.parts, selection).reasons.has("Installed power exceeds 100"), "Two spinners exceed the power budget")
	selection.weapons = ["hammer"]
	check(ArmourLayout.budget(registry.parts, selection).reasons.is_empty(), "A single weapon remains legal")
	selection.weapons = []
	check(ArmourLayout.budget(registry.parts, selection).reasons.has("Select one or two weapons"), "At least one weapon is required")
	selection.weapons = ["hammer", "saw", "lifter"]
	check(ArmourLayout.budget(registry.parts, selection).reasons.has("Select one or two weapons"), "At most two weapons fit")
	selection.weapons = ["hammer", "heavy"]
	check(ArmourLayout.budget(registry.parts, selection).reasons.has("Unknown weapon heavy"), "Non-weapon parts cannot fill a weapon socket")
