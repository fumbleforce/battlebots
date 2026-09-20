extends Node
## Isolated real-file repair regression. Never uses the player's loadouts path.
var failures := 0
var store: LoadoutStore

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	store = LoadoutStore.new(OS.get_environment("TEMP").path_join("battlebots-repair-%d.json" % OS.get_process_id()))
	_cleanup()
	var first := store.registry.starter()
	first.name = "First"
	var second := store.registry.starter(true)
	second.name = "Second"
	var bad_first := first.duplicate(true)
	bad_first.parts.weapon = "retired_weapon"
	var bad_second := second.duplicate(true)
	bad_second.content_hash = "unknown-version"
	var malformed: Array = ["opaque", {"unrecognized": [null, 3, false]}]
	_seed([bad_first, bad_second, malformed])
	var original := FileAccess.get_file_as_string(store.path)
	var expected: Array = store.load_saved().loadouts
	check(store.save(expected) == ERR_INVALID_DATA, "Whole-file save stays strict")
	check(store.save_build(first, 0, expected) == OK, "Repair first invalid build beside two invalid siblings")
	check(FileAccess.get_file_as_string(store.path + ".bak") == original, "Backup preserves original bytes")
	var raw := _raw()
	check(_same(raw[0], first) and _same(raw[1], bad_second) and _same(raw[2], malformed), "Repair touches only the chosen slot")
	check(store.save_build(second, 1, store.load_saved().loadouts) == OK, "Second invalid build can be repaired independently")
	check(_same(_raw()[2], malformed), "Sequential repair preserves malformed sibling")
	var inserted := first.duplicate(true)
	inserted.name = "Inserted"
	check(store.save_build(inserted, -1, store.load_saved().loadouts) == OK, "New valid build can coexist with malformed sibling")
	check(_same(_raw()[2], malformed) and _same(_raw()[3], inserted), "Append preserves order and siblings")
	_reject(bad_first, 0, store.load_saved().loadouts, ERR_INVALID_DATA, "Invalid replacement")
	_reject(second, 0, store.load_saved().loadouts, ERR_INVALID_DATA, "Duplicate name replacement")
	_reject(second, -1, store.load_saved().loadouts, ERR_INVALID_DATA, "Duplicate name append")
	_reject(first, -2, store.load_saved().loadouts, ERR_PARAMETER_RANGE_ERROR, "Negative index")
	_reject(first, 99, store.load_saved().loadouts, ERR_PARAMETER_RANGE_ERROR, "Missing slot")
	_reject(first, 0, expected, ERR_BUSY, "Stale snapshot")
	var twelve: Array = []
	for i: int in range(12):
		var item := first.duplicate(true)
		item.name = "Build %d" % i
		twelve.append(item)
	_seed(twelve)
	_reject(inserted, -1, store.load_saved().loadouts, ERR_PARAMETER_RANGE_ERROR, "Full capacity")
	# Raw legacy sibling stays raw while expected uses compatible migration.
	var legacy := second.duplicate(true)
	legacy.content_hash = LoadoutStore.REVISION_ONE_HASHES[0]
	_seed([bad_first, legacy], 0)
	check(store.save_build(first, 0, store.load_saved().loadouts) == OK, "Repair accepts schema-zero migrated baseline")
	check(_same(_raw()[1], legacy), "Repair never rewrites unrelated compatible legacy sibling")
	# Growth beyond the readable envelope limit must not commit an unreadable save.
	_seed([bad_first, "x".repeat(65000)])
	_reject(inserted, -1, store.load_saved().loadouts, ERR_PARAMETER_RANGE_ERROR, "Encoded size cap")
	_cleanup()
	check(store.save_build(first, -1, []) == OK, "First save initializes missing file")
	check(store.save_build(second, -1, [first]) == OK, "Next save accepts in-memory integer baseline and makes usable backup")
	var corrupt := FileAccess.open(store.path, FileAccess.WRITE)
	corrupt.store_string("interrupted")
	corrupt.close()
	var recovered := store.load_saved()
	check(recovered.restored_backup, "Corruption recovers prior backup for reading")
	_reject(inserted, -1, recovered.loadouts, ERR_FILE_CORRUPT, "Recovered backup cannot overwrite ambiguous primary")
	DirAccess.remove_absolute(store.path)
	_reject(inserted, -1, store.load_saved().loadouts, ERR_FILE_CORRUPT, "Orphan backup cannot be silently replaced")
	_cleanup()
	var broken := FileAccess.open(store.path, FileAccess.WRITE)
	broken.store_string("invalid JSON")
	broken.close()
	_reject(first, -1, [], ERR_FILE_CORRUPT, "Corruption without backup")
	_cleanup()
	print("LOADOUT REPAIR PASS" if failures == 0 else "LOADOUT REPAIR FAIL: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _seed(builds: Array, version := 1) -> void:
	var envelope := {"schema_version": version}
	envelope["builds" if version == 0 else "loadouts"] = builds
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()

func _raw() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(store.path)).loadouts

func _reject(draft: Dictionary, index: int, expected: Array, error: Error, label: String) -> void:
	var before: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp"]:
		before[suffix] = FileAccess.get_file_as_bytes(store.path + suffix) if FileAccess.file_exists(store.path + suffix) else null
	check(store.save_build(draft, index, expected) == error, label + " returns the expected error")
	for suffix: String in before:
		var after: Variant = FileAccess.get_file_as_bytes(store.path + suffix) if FileAccess.file_exists(store.path + suffix) else null
		check(before[suffix] == after, label + " leaves " + suffix + " bytes unchanged")

func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(store.path + suffix):
			DirAccess.remove_absolute(store.path + suffix)

func _same(actual: Variant, expected: Variant) -> bool:
	return actual == JSON.parse_string(JSON.stringify(expected))
