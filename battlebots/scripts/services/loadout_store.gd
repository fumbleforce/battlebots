class_name LoadoutStore
extends RefCounted
## Local versioned JSON; backup remains usable if replacement is interrupted.
const REVISION_ONE_HASHES := [
	"6b1a855425fd079e8e3356722720f5631304df87fc839f30a5dbde2fae83b56e",
	"9749e90fa985e6bedc8259c150ff10115d5033e96894deea97c16f433110ee16",
]
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
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema_version": 1, "loadouts": loadouts}))
	file.flush()
	file.close()
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
		if FileAccess.get_file_as_bytes(candidate).size() > 65536:
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
			if not draft is Dictionary or draft.get("content_hash") not in REVISION_ONE_HASHES:
				continue
			# Revision two only adds a weapon; every prior part keeps its stats.
			# Upgrade known compatible saves locally, never loosen network checks.
			var upgraded: Dictionary = draft.duplicate(true)
			upgraded.content_hash = registry.content_hash
			if registry.validate(upgraded).valid:
				copy.loadouts[index] = upgraded
	return copy
