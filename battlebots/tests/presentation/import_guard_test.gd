extends SceneTree
## ImportGuard staleness detection on fixture files: an unchanged asset is
## fresh, changed bytes, a missing record or a missing import are stale, and
## keep-type imports never are. The relaunch itself needs a native window and
## is verified by hand (see docs/coordination/IMPORT_GUARD.md).
const ImportGuard := preload("res://scripts/core/import_guard.gd")
const HASH := "0123456789abcdef0123456789abcdef"
const DIRECTORY := "user://import_guard_fixture"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func clear(path: String) -> void:
	var entries := DirAccess.open(path)
	if entries == null: return
	for child: String in entries.get_directories(): clear(path.path_join(child))
	for file: String in entries.get_files(): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

func asset(name: String, contents: String, recorded := true, imported := true) -> void:
	var source := DIRECTORY.path_join(name)
	var destination := DIRECTORY.path_join("imported/%s-%s.ctex" % [name, HASH])
	write(source, contents)
	write(source + ".import", '[remap]\n\nimporter="texture"\n\n[deps]\n\nsource_file="%s"\ndest_files=["%s"]\n' % [source, destination])
	if imported: write(destination, "imported")
	if recorded:
		write(DIRECTORY.path_join("imported/%s-%s.md5" % [name, HASH]), 'source_md5="%s"\ndest_md5="x"\n' % contents.md5_text())

func run() -> void:
	clear(DIRECTORY)
	DirAccess.make_dir_recursive_absolute(DIRECTORY.path_join("imported"))
	check(not ImportGuard.should_check(), "Headless runs never re-import or relaunch")
	asset("fresh.png", "same bytes")
	check(ImportGuard.stale_assets(DIRECTORY).is_empty(), "An unchanged asset is fresh")
	asset("changed.png", "old bytes")
	# A pull rewrites the source after its import: newer file, different hash.
	OS.delay_msec(1100)
	write(DIRECTORY.path_join("changed.png"), "new bytes")
	asset("unrecorded.png", "never imported", false)
	asset("missing.png", "import removed", true, false)
	write(DIRECTORY.path_join("kept.txt.import"), '[remap]\n\nimporter="keep"\n')
	var stale := ImportGuard.stale_assets(DIRECTORY)
	check(stale.has(DIRECTORY.path_join("changed.png")), "Changed bytes are stale")
	check(stale.has(DIRECTORY.path_join("unrecorded.png")), "An asset without an import record is stale")
	check(stale.has(DIRECTORY.path_join("missing.png")), "A missing imported copy is stale")
	check(not stale.has(DIRECTORY.path_join("fresh.png")) and not stale.has(DIRECTORY.path_join("kept.txt")),
		"Fresh assets and keep-type imports are not reported")
	# Touching a file without changing it (checkout, copy) is not a change.
	OS.delay_msec(1100)
	write(DIRECTORY.path_join("fresh.png"), "same bytes")
	check(not ImportGuard.stale_assets(DIRECTORY).has(DIRECTORY.path_join("fresh.png")), "A touched but identical asset stays fresh")
	check(ImportGuard.stale_assets("res://").is_empty(), "This checkout's imports are current after the test's import step")
	for failure: String in failures: push_error(failure)
	print("IMPORT GUARD PASS" if failures.is_empty() else "IMPORT GUARD FAIL")
	quit(0 if failures.is_empty() else 1)
