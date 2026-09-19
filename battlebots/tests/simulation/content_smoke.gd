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
	for old_hash: String in LoadoutStore.REVISION_ONE_HASHES:
		var old_build := registry.starter()
		old_build.content_hash = old_hash
		var upgraded: Dictionary = store.migrate({"schema_version":1, "loadouts":[old_build]}).loadouts[0]
		check(registry.validate(upgraded).valid and upgraded.parts == old_build.parts and upgraded.name == old_build.name,
			"Compatible revision-one saves migrate without changing selected parts")
		check(old_build.content_hash == old_hash, "Migration does not mutate its source")
		old_build.parts.weapon = "unknown_weapon"
		check(store.migrate({"schema_version":1, "loadouts":[old_build]}).loadouts[0] == old_build,
			"Migration preserves unknown parts as invalid for explicit repair")
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
