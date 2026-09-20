extends SceneTree
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var registry := ContentRegistry.new()
	var striker := registry.starter()
	var result := registry.validate(striker)
	check(result.valid and result.stats.mass == 103.0 and result.stats.power == 75.0, "Striker derived stats")
	for chassis: String in ["compact", "balanced", "wide"]:
		var sizes := {"compact": Vector3(1.2, 0.5, 1.5), "balanced": Vector3(1.6, 0.5, 2.0), "wide": Vector3(1.8, 0.5, 2.2)}
		var scaled := striker.duplicate(true)
		scaled.parts.chassis = chassis
		check(registry.validate(scaled).stats.size.is_equal_approx(sizes[chassis] * 3.0), "Every canonical hull is exactly three times larger")
	result = registry.validate(registry.starter(true))
	check(result.valid and result.stats.mass == 108.0, "Controller derived stats")
	var bad := striker.duplicate(true)
	bad.parts.weapon = "res://arbitrary.tscn"
	check(not registry.validate(bad).valid, "Reject arbitrary/unknown parts")
	bad = striker.duplicate(true)
	bad.parts.drive = "balanced"
	check(not registry.validate(bad).valid, "Reject incompatible duplicate")
	bad = striker.duplicate(true)
	bad.parts.erase("armor")
	check(not registry.validate(bad).valid, "Reject missing parts")
	bad = striker.duplicate(true)
	bad.parts = {"chassis":"wide", "drive":"traction", "weapon":"vertical_spinner", "armor":"heavy", "utility":"battery_pack"}
	check(not registry.validate(bad).valid, "Reject overweight")
	bad = striker.duplicate(true)
	bad.mass = 1
	check(not registry.validate(bad).valid, "Reject client-supplied stats")
	bad = striker.duplicate(true)
	bad.content_hash = "old"
	check(not registry.validate(bad).valid, "Reject version mismatch")
	# Every current combo is below power cap; use an injected authoring fixture to test the gate.
	registry.parts.vertical_spinner.power = 101
	check(not registry.validate(striker).valid, "Reject excess power")
	registry = ContentRegistry.new()
	var path := "user://test-loadouts-%d.json" % OS.get_process_id()
	var store := LoadoutStore.new(path)
	var saved_sawblade := SawbladeConfig.starter(registry)
	saved_sawblade.name = "Painted heavy walker"
	saved_sawblade.parts.drive = "walker"
	saved_sawblade.parts.weapon = "hammer"
	saved_sawblade.cosmetics.sawblade.exhaust = 3
	saved_sawblade.cosmetics.sawblade.paint_primary = [0.3, 0.1, 0.7, 1.0]
	saved_sawblade.content_hash = LoadoutStore.REVISION_SIX_HASHES[0]
	check(not registry.validate(saved_sawblade).valid, "Old-size peers remain incompatible before local save migration")
	var resized_save: Dictionary = store.migrate({"schema_version": 1, "loadouts": [saved_sawblade]}).loadouts[0]
	check(registry.validate(resized_save).valid and resized_save.parts == saved_sawblade.parts
		and resized_save.cosmetics == saved_sawblade.cosmetics and resized_save.name == saved_sawblade.name,
		"Revision-six saved machine migrates size while preserving all selected parts and appearance")
	for old_hash: String in LoadoutStore.REVISION_ONE_HASHES + LoadoutStore.REVISION_TWO_HASHES + LoadoutStore.REVISION_THREE_HASHES + LoadoutStore.REVISION_FOUR_HASHES + LoadoutStore.REVISION_FIVE_HASHES + LoadoutStore.REVISION_SIX_HASHES:
		var old_build := registry.starter()
		old_build.content_hash = old_hash
		var upgraded: Dictionary = store.migrate({"schema_version":1, "loadouts":[old_build]}).loadouts[0]
		check(registry.validate(upgraded).valid and upgraded.parts == old_build.parts and upgraded.name == old_build.name,
			"Compatible older saves migrate without changing selected parts")
		check(old_build.content_hash == old_hash, "Migration does not mutate its source")
		old_build.parts.weapon = "unknown_weapon"
		check(store.migrate({"schema_version":1, "loadouts":[old_build]}).loadouts[0] == old_build,
			"Migration preserves unknown parts as invalid for explicit repair")
	var horizontal := registry.starter()
	horizontal.parts.weapon = "horizontal_spinner"
	horizontal.content_hash = LoadoutStore.REVISION_TWO_HASHES[0]
	var migrated_horizontal: Dictionary = store.migrate({"schema_version": 1, "loadouts": [horizontal]}).loadouts[0]
	check(registry.validate(migrated_horizontal).valid and migrated_horizontal.parts == horizontal.parts,
		"Revision-two horizontal builds survive addition of hammer")
	var hammer := registry.duelist()
	hammer.content_hash = LoadoutStore.REVISION_THREE_HASHES[0]
	var migrated_hammer: Dictionary = store.migrate({"schema_version": 1, "loadouts": [hammer]}).loadouts[0]
	check(registry.validate(migrated_hammer).valid and migrated_hammer.parts == hammer.parts,
		"Revision-three Duelist builds survive addition of saw")
	var unknown_version := registry.starter()
	unknown_version.content_hash = "unrecognized-version"
	check(store.migrate({"schema_version":1, "loadouts":[unknown_version]}).loadouts[0] == unknown_version,
		"Unknown content revisions are never silently accepted")
	var builds: Array = []
	for i: int in range(12):
		var draft := registry.starter(i % 2 == 1)
		draft.name = "Build %d" % i
		builds.append(draft)
	check(store.save(builds) == OK, "Save twelve builds")
	check(store.load_saved().loadouts.size() == 12, "Load twelve builds")
	check(store.save(builds) == OK, "Atomic replace and backup")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("interrupted")
	file.close()
	check(store.load_saved().restored_backup, "Corrupt primary falls back to backup")
	check(store.migrate({"schema_version":0, "builds":builds}).loadouts == builds, "Migration preserves builds")
	builds.append(registry.starter())
	check(store.save(builds) != OK, "Enforce twelve slots")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("CONTENT PASS" if failures == 0 else "CONTENT FAIL")
	quit(0 if failures == 0 else 1)
