extends Node
## Real-file recovery checks, isolated from the player's profile.
var failures := 0
var store: LoadoutStore
var archives: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	store = LoadoutStore.new(OS.get_environment("TEMP").path_join("battlebots-recovery-%d.json" % OS.get_process_id()))
	_cleanup()
	var backup := "{\n \"schema_version\": 0, \"builds\": [\"malformed\", {\"name\":\"Unknown\",\"parts\":{\"weapon\":\"retired\"}}]\n}\n"
	_write("", "interrupted bytes\r\n")
	_write(".bak", backup)
	var before := _snapshot()
	var inspected := store.inspect_recovery()
	check(inspected.available, "Readable legacy backup is offered")
	check(inspected.loadouts.size() == 2 and inspected.loadouts[0] == "malformed", "Invalid individual records remain visible")
	check(before == _snapshot(), "Inspection leaves both files unchanged")
	var restored := store.restore_backup(inspected.token)
	check(restored.error == OK, "Explicit restore succeeds")
	archives.append(restored.preserved_path)
	check(not restored.preserved_path.is_empty(), "Existing unreadable primary is archived")
	check(FileAccess.get_file_as_bytes(restored.preserved_path) == before.primary, "Archive retains exact original bytes")
	check(FileAccess.get_file_as_bytes(store.path) == before.backup, "Restored primary retains exact backup bytes")
	check(FileAccess.get_file_as_bytes(store.path + ".bak") == before.backup, "Backup is never overwritten")
	check(not store.inspect_recovery().available, "Readable primary with invalid builds is not replaceable")
	_reject(inspected.token, "Repeated confirmation")
	_reject({}, "Missing confirmation")
	DirAccess.remove_absolute(store.path)
	inspected = store.inspect_recovery()
	check(inspected.available, "Missing primary permits explicit backup restoration")
	_write("", "new corruption")
	_reject(inspected.token, "Primary existence changed")
	inspected = store.inspect_recovery()
	_write("", "new corruption changed")
	_reject(inspected.token, "Primary bytes changed")
	inspected = store.inspect_recovery()
	_write(".bak", backup + " ")
	_reject(inspected.token, "Backup bytes changed")
	inspected = store.inspect_recovery()
	DirAccess.remove_absolute(store.path + ".bak")
	_reject(inspected.token, "Backup removed")
	_write(".bak", backup)
	DirAccess.remove_absolute(store.path)
	inspected = store.inspect_recovery()
	restored = store.restore_backup(inspected.token)
	check(restored.error == OK and restored.preserved_path.is_empty(), "Absent primary restores without a spurious archive")
	_write("", "bad")
	for invalid: String in ["broken", "[]", '{"schema_version": 7, "loadouts": []}', '{"schema_version":1,"loadouts":' + JSON.stringify(range(13)) + '}', " ".repeat(65537)]:
		_write(".bak", invalid)
		check(not store.inspect_recovery().available, "Malformed, unsupported or oversized backup refused")
		_reject(inspected.token, "Invalid backup")
	_write(".bak", backup)
	_write("", "x".repeat(65537))
	inspected = store.inspect_recovery()
	check(inspected.available, "Oversized unreadable primary can be recovered")
	restored = store.restore_backup(inspected.token)
	check(restored.error == OK, "Oversized primary recovery succeeds")
	archives.append(restored.preserved_path)
	check(FileAccess.get_file_as_bytes(restored.preserved_path).size() == 65537, "Oversized primary archive is complete")
	DirAccess.remove_absolute(store.path)
	DirAccess.make_dir_absolute(store.path)
	check(not store.inspect_recovery().available, "Directory at primary path cannot be recovered")
	DirAccess.remove_absolute(store.path)
	_cleanup()
	print("LOADOUT RECOVERY PASS" if failures == 0 else "LOADOUT RECOVERY FAIL: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _write(suffix: String, content: String) -> void:
	var file := FileAccess.open(store.path + suffix, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _snapshot() -> Dictionary:
	return {"primary": FileAccess.get_file_as_bytes(store.path) if FileAccess.file_exists(store.path) else null,
		"backup": FileAccess.get_file_as_bytes(store.path + ".bak") if FileAccess.file_exists(store.path + ".bak") else null}

func _reject(token: Dictionary, label: String) -> void:
	var before := _snapshot()
	check(store.restore_backup(token).error != OK, label + " refuses restore")
	check(before == _snapshot(), label + " leaves both files unchanged")

func _cleanup() -> void:
	for candidate: String in [store.path, store.path + ".bak"] + archives:
		if not candidate.is_empty() and FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)
