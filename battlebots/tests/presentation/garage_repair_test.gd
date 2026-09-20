extends Node
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	var profile: Node = get_node("/root/PlayerProfile")
	var path := "user://garage-repair-test-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	var first: Dictionary = profile.registry.starter()
	first.name = "Old format"
	first.content_hash = "unknown-old-catalogue"
	first.extra = "unrecognized local field"
	var second: Dictionary = profile.registry.starter(true)
	second.name = "Missing weapon"
	second.parts.weapon = "retired_lifter"
	var raw := [first, second, "unreadable entry kept for repair"]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1, "loadouts":raw}))
	file.close()
	var initial := FileAccess.get_file_as_string(path)
	profile.reload()
	first = profile.loadouts[3].duplicate(true)
	second = profile.loadouts[4].duplicate(true)
	profile.active_bot = 3
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1920, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var screen: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	add_child(screen)
	for _frame: int in 3: await get_tree().process_frame
	check(screen.revalidate_button.visible and screen.get_node("%Save").disabled, "Unknown format offers explicit repair and blocks Save")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("garage-repair-invalid.png"))
	screen.revalidate_button.pressed.emit()
	check(profile.bots[3].valid and not screen.get_node("%Save").disabled, "Explicit metadata repair enables legal draft")
	check(profile.loadouts[3].parts == first.parts and profile.loadouts[3].cosmetics == first.cosmetics, "Repair preserves every chosen part and paint")
	check(FileAccess.get_file_as_string(path) == initial, "Revalidation does not write disk")
	screen.undo_button.pressed.emit()
	check(profile.loadouts[3] == first and screen.revalidate_button.visible, "Undo restores old version and unknown fields")
	screen.redo_button.pressed.emit()
	screen.get_node("%Save").pressed.emit()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(profile.registry.validate(saved.loadouts[0]).valid, "First repaired build can save while two siblings remain invalid")
	check(saved.loadouts[1] == second and saved.loadouts[2] == raw[2], "Invalid siblings remain unchanged")
	screen.queue_free()
	await get_tree().process_frame
	profile.active_bot = 4
	screen = load("res://ui/menus/screens/customize.tscn").instantiate()
	add_child(screen)
	var category: Dictionary = profile.catalogue.parts[2]
	var selected: Dictionary = {}
	for item: Dictionary in category.items:
		if item.id == "saw": selected = item
	profile.equip("parts", category, selected)
	check(profile.bots[4].valid, "Canonical replacement repairs unknown weapon")
	screen.get_node("%Save").pressed.emit()
	saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.loadouts[1].parts.weapon == "saw" and saved.loadouts[2] == raw[2], "Second repair succeeds without replacing malformed sibling")
	profile.undo_edit()
	check(not profile.bots[4].valid and saved.loadouts[1].parts.weapon == "saw", "Undo after Save remains draft-only")
	profile.redo_edit()
	for _frame: int in 4: await get_tree().process_frame
	check(screen.get_node("%Save").get_global_rect().end.y <= 1080, "Repair screen fits 720p")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("garage-repair.png"))
	screen.queue_free()
	await get_tree().process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	if failures.is_empty(): print("GARAGE REPAIR PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
