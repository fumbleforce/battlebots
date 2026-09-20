class_name LoadoutStore
extends RefCounted
## Local versioned JSON; backup remains usable if replacement is interrupted.
const REVISION_ONE_HASHES := [
	"6b1a855425fd079e8e3356722720f5631304df87fc839f30a5dbde2fae83b56e",
	"9749e90fa985e6bedc8259c150ff10115d5033e96894deea97c16f433110ee16",
]
const REVISION_TWO_HASHES := ["db17ced752e95309a2535da0fe5d8c6aded0ff2ab70f80ffe1e2581893b69c29"]
const REVISION_THREE_HASHES := ["4145fa8eff0fef9e4336ef5dc8f5698a16f8cb5bb277cdbf02cb313eafa37819"]
const MAX_SAVE_BYTES := 65536
var registry := ContentRegistry.new()
var path: String

func _init(save_path := "user://loadouts.json") -> void:
	path = save_path

func save(loadouts: Array) -> Error:
	if loadouts.size() > 12:
		return ERR_PARAMETER_RANGE_ERROR
	var names: Array = []
	for draft: Variant in loadouts:
		if not draft is Dictionary or not registry.validate(draft).valid or names.has(draft.name):
			return ERR_INVALID_DATA
		names.append(draft.name)
	return _write(loadouts)

## Replace one explicitly repaired slot (or append at -1), preserving other raw records.
## expected is the last load_saved().loadouts snapshot, including invalid records.
func save_build(draft: Dictionary, index: int, expected: Array) -> Error:
	# JSON stores numbers without GDScript's int/float distinction.
	var baseline: Array = JSON.parse_string(JSON.stringify(expected))
	var current := load_saved()
	if not current.errors.is_empty() or current.restored_backup:
		return ERR_FILE_CORRUPT
	if current.loadouts != baseline:
		return ERR_BUSY
	var raw: Array = []
	if FileAccess.file_exists(path):
		var source := FileAccess.open(path, FileAccess.READ)
		if source == null:
			return FileAccess.get_open_error()
		if source.get_length() > MAX_SAVE_BYTES:
			return ERR_PARAMETER_RANGE_ERROR
		var parser := JSON.new()
		var parse_error := parser.parse(source.get_as_text())
		source.close()
		if parse_error != OK or not parser.data is Dictionary:
			return ERR_FILE_CORRUPT
		var envelope: Dictionary = parser.data
		var migrated := migrate(envelope)
		if migrated.get("schema_version") != 1 or not migrated.get("loadouts") is Array:
			return ERR_FILE_CORRUPT
		if migrated.loadouts != baseline:
			return ERR_BUSY
		raw = envelope.get("builds", []) if envelope.get("schema_version") == 0 else envelope.loadouts
	elif not expected.is_empty():
		return ERR_BUSY
	if index < -1 or index >= raw.size() or (index == -1 and raw.size() >= 12):
		return ERR_PARAMETER_RANGE_ERROR
	if not registry.validate(draft).valid:
		return ERR_INVALID_DATA
	for sibling_index: int in range(raw.size()):
		if sibling_index != index and raw[sibling_index] is Dictionary and raw[sibling_index].get("name") == draft.name:
			return ERR_INVALID_DATA
	if index == -1:
		raw.append(draft.duplicate(true))
	else:
		raw[index] = draft.duplicate(true)
	return _write(raw)

func _write(loadouts: Array) -> Error:
	var encoded := JSON.stringify({"schema_version": 1, "loadouts": loadouts})
	if encoded.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return ERR_PARAMETER_RANGE_ERROR
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	if FileAccess.file_exists(path):
		var copied := DirAccess.copy_absolute(path, path + ".bak")
		if copied != OK:
			return copied
	return DirAccess.rename_absolute(path + ".tmp", path)

func load_saved() -> Dictionary:
	var errors: PackedStringArray = []
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		if FileAccess.get_file_as_bytes(candidate).size() > MAX_SAVE_BYTES:
			errors.append("Save exceeds size limit")
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(FileAccess.get_file_as_string(candidate))
		var parsed: Variant = parser.data if parse_error == OK else null
		if not parsed is Dictionary:
			errors.append("Corrupt save: " + candidate.get_file())
			continue
		parsed = migrate(parsed)
		if parsed.get("schema_version") != 1 or not parsed.get("loadouts") is Array or parsed.loadouts.size() > 12:
			errors.append("Unsupported save schema")
			continue
		var builds: Array = parsed.loadouts
		var invalid: Dictionary = {}
		for i: int in range(builds.size()):
			if not builds[i] is Dictionary:
				invalid[i] = ["Malformed loadout"]
			else:
				var result := registry.validate(builds[i])
				if not result.valid:
					invalid[i] = result.reasons
		return {"loadouts": builds, "invalid": invalid, "errors": errors,
			"restored_backup": candidate.ends_with(".bak")}
	return {"loadouts": [], "invalid": {}, "errors": errors, "restored_backup": false}

func migrate(data: Dictionary) -> Dictionary:
	# Schema 0 used a `builds` envelope; part IDs/stats are never silently replaced.
	var copy := data.duplicate(true)
	if copy.get("schema_version") == 0 and copy.get("builds") is Array:
		copy = {"schema_version": 1, "loadouts": copy.builds}
	if copy.get("schema_version") == 1 and copy.get("loadouts") is Array:
		for index: int in range(copy.loadouts.size()):
			var draft: Variant = copy.loadouts[index]
			if not draft is Dictionary or draft.get("content_hash") not in REVISION_ONE_HASHES + REVISION_TWO_HASHES + REVISION_THREE_HASHES:
				continue
			# Revisions two through four only add weapons; prior parts keep their stats.
			# Upgrade known compatible saves locally, never loosen network checks.
			var upgraded: Dictionary = draft.duplicate(true)
			upgraded.content_hash = registry.content_hash
			if registry.validate(upgraded).valid:
				copy.loadouts[index] = upgraded
	return copy
