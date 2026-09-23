extends Node
## Keeps source checkouts from running on stale imported assets.
##
## Godot re-imports changed models and textures only when the editor runs. A
## game launched straight from a checkout (`godot --path battlebots`) after a
## pull keeps loading the old copies in .godot/imported, so new art looks
## unchanged. This first autoload compares every tracked asset with the hash
## recorded at its last import; if any changed (or was never imported) it runs
## the headless import and relaunches the game with the same arguments.
##
## Skipped in the editor, in exported builds (no sources there), in headless
## runs (tests and servers import explicitly) and when
## BATTLEBOTS_SKIP_IMPORT_GUARD is set. Deliberately depends on no project
## classes: stale imports can break their compilation.
const SKIP_VARIABLE := "BATTLEBOTS_SKIP_IMPORT_GUARD"
## Set for the relaunched game so a failed repair can never loop.
const RELAUNCHED_VARIABLE := "BATTLEBOTS_IMPORT_GUARD_RELAUNCHED"
## Directories that hold no imported game assets.
const IGNORED_DIRECTORIES := [".godot", "exports", ".git"]

var _restarting := false

func _init() -> void:
	if not should_check():
		return
	var stale := stale_imports("res://")
	if stale.is_empty():
		return
	print("ImportGuard: %d changed asset(s) since the last import (first: %s); importing and restarting." % [stale.size(), stale[0].source])
	# The editor decides what to re-import from its own file cache, which a pull
	# can leave looking current. Removing the outdated copies forces a rebuild.
	for record: Dictionary in stale:
		for path: String in record.outputs:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var output: Array = []
	var project := ProjectSettings.globalize_path("res://")
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", project, "--editor", "--import", "--quit"], output, true)
	var remaining := stale_imports("res://")
	if code != 0 or not remaining.is_empty():
		push_error("ImportGuard: import did not refresh %d asset(s) (exit %d); open the project in the Godot editor once." % [remaining.size(), code])
		return
	OS.set_environment(RELAUNCHED_VARIABLE, "1")
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	_restarting = true

func _enter_tree() -> void:
	if _restarting:
		get_tree().quit.call_deferred()

static func should_check() -> bool:
	if Engine.is_editor_hint() or OS.has_feature("template") or OS.has_environment(SKIP_VARIABLE) \
			or OS.has_environment(RELAUNCHED_VARIABLE):
		return false
	return DisplayServer.get_name() != "headless"

## Source paths whose imported copy is missing or was made from other bytes.
static func stale_assets(directory: String) -> PackedStringArray:
	var sources := PackedStringArray()
	for record: Dictionary in stale_imports(directory): sources.append(record.source)
	return sources

## Stale imports as {source, outputs} (imported files and the import record).
## Only files modified after their import are hashed, so a clean start is cheap.
static func stale_imports(directory: String) -> Array[Dictionary]:
	var stale: Array[Dictionary] = []
	var entries := DirAccess.open(directory)
	# Godot never imports a directory marked with .gdignore (source art).
	if entries == null or FileAccess.file_exists(directory.path_join(".gdignore")):
		return stale
	entries.include_hidden = false
	for child: String in entries.get_directories():
		if child not in IGNORED_DIRECTORIES:
			stale.append_array(stale_imports(directory.path_join(child)))
	for file: String in entries.get_files():
		if file.get_extension() == "import":
			var record := _check(directory.path_join(file))
			if not record.is_empty(): stale.append(record)
	return stale

static func _check(import_path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		return {}
	var source: String = config.get_value("deps", "source_file", import_path.get_basename())
	var destinations: Variant = config.get_value("deps", "dest_files", [])
	# "keep"/"skip" importers produce nothing to go stale.
	if not destinations is Array or destinations.is_empty() or not FileAccess.file_exists(source):
		return {}
	# The import record sits beside the destinations: <name>-<32-hex hash>.md5,
	# also for multi-destination (compressed variant) textures.
	var hashed := RegEx.create_from_string("^(.*-[0-9a-f]{32})").search(str(destinations[0]))
	if hashed == null:
		return {}
	var record := hashed.get_string(1) + ".md5"
	var stale := {"source": source, "outputs": Array(destinations) + [record]}
	if not FileAccess.file_exists(record) or not FileAccess.file_exists(str(destinations[0])):
		return stale
	if FileAccess.get_modified_time(source) <= FileAccess.get_modified_time(record):
		return {}
	var recorded := ConfigFile.new()
	if recorded.load(record) != OK:
		return stale
	return stale if str(recorded.get_value("", "source_md5", "")) != FileAccess.get_md5(source) else {}
