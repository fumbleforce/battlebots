extends SceneTree
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	var registry := ContentRegistry.new()
	var draft := registry.atlas()
	var result := registry.validate(draft)
	check(result.valid and result.stats.mass == 103 and result.stats.power == 70,
		"Atlas starter uses the ordinary mass/power budgets")
	check(result.valid and result.stats.nitro and result.stats.charged_jump,
		"Atlas includes the upstream independent Nitro and charged-jump slots")
	for old_id: String in ["compact", "balanced", "wide", "scorpion_hex"]:
		check(registry.parts.has(old_id), "Previous chassis remains available: " + old_id)
	for weapon: String in ["saw", "hammer", "lifter", "vertical_spinner", "horizontal_spinner", "minigun"]:
		for utility: String in ["recovery_assist", "cooling_pack", "battery_pack", "minigun_pod"]:
			var variant := draft.duplicate(true)
			variant.parts.weapon = weapon
			variant.parts.utility = utility
			variant.parts.armor = "light"
			check(registry.validate(variant).valid == not (weapon == "minigun" and utility == "minigun_pod"),
				"Every mounted primary/utility fits; duplicate guns do not: " + weapon + "/" + utility)
	for drive: String in ["agile", "standard_wheels", "walker"]:
		var invalid := draft.duplicate(true)
		invalid.parts.drive = drive
		check(not registry.validate(invalid).valid, "Unmodelled drive swaps are rejected: " + drive)
	var unknown := draft.duplicate(true)
	unknown.parts.utility = "external_model.glb"
	check(not registry.validate(unknown).valid, "Atlas never accepts arbitrary external modules")
	var store := LoadoutStore.new()
	for old: Dictionary in [SawbladeConfig.starter(registry), registry.scorpion()]:
		old.schema_version = 1
		old.parts.erase("nitro")
		old.parts.erase("suspension")
		old.content_hash = LoadoutStore.REVISION_EIGHT_HASHES[0]
		old.cosmetics.sawblade.paint_primary = [0.25, 0.4, 0.6, 1.0]
		var migrated: Dictionary = store.migrate({"schema_version":1, "loadouts":[old]}).loadouts[0]
		var expected: Dictionary = old.parts.duplicate(true)
		expected.nitro = "nitro_off"
		expected.suspension = "jump_off"
		check(registry.validate(migrated).valid and migrated.parts == expected and migrated.cosmetics == old.cosmetics,
			"Revision-eight saved machines retain every selected part and paint channel")
		check(old.content_hash == LoadoutStore.REVISION_EIGHT_HASHES[0], "Migration never mutates its input")
	var previous := registry.scorpion()
	previous.parts.nitro = "nitro_off"
	previous.content_hash = LoadoutStore.REVISION_NINE_HASHES[0]
	var upgraded: Dictionary = store.migrate({"schema_version":1, "loadouts":[previous]}).loadouts[0]
	check(registry.validate(upgraded).valid and upgraded.parts == previous.parts and upgraded.cosmetics == previous.cosmetics,
		"Published revision-nine perk choices survive Atlas migration unchanged")
	for distance: float in [0.0, 0.4, 1.52, 2.1, 3.0, 4.0, 5.3]:
		var frame := AtlasGeometry.track_transform(distance, 0.94)
		check(absf(AtlasGeometry.track_distance(frame.origin) - distance) < 0.0001,
			"Authored track positions round-trip through the continuous loop")
		check(frame.origin.distance_to(AtlasGeometry.track_transform(distance + AtlasGeometry.TRACK_LENGTH, 0.94).origin) < 0.0001,
			"Tracks close continuously around their physical wheels")
	if failures.is_empty(): print("ATLAS CATALOGUE PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
