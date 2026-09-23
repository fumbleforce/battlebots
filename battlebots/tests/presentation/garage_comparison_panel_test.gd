extends Node
## Actual Customize integration; only isolated in-memory profile drafts are edited.
var failures: Array[String] = []
var screen: Control
var profile: Node

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _ready() -> void:
	call_deferred("run")

func settle() -> void:
	for _frame in 5: await get_tree().process_frame

func choose(slot: String, id: String) -> void:
	screen.get_node("%TabParts").pressed.emit()
	await settle()
	var index := ContentRegistry.SLOTS.find(slot)
	screen.get_node("%Categories").get_child(index).pressed.emit()
	await settle()
	var category: Dictionary = profile.catalogue.parts[index]
	for item_index: int in category.items.size():
		if category.items[item_index].id == id and screen.choice_tile("parts", index, item_index) != null:
			screen.choice_tile("parts", index, item_index).pressed.emit()
			await settle()
			return
	check(false, "Customize does not list part " + id)

func cell(grid: GridContainer, index: int) -> String:
	return grid.get_child(index).text

func bounds(control: Control, label: String) -> void:
	var rect := control.get_global_rect()
	check(rect.position.x >= -1 and rect.position.y >= -1 and rect.end.x <= 1921 and rect.end.y <= 1081, label + " fits 1280x720 canvas")

func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	get_tree().root.content_scale_size = Vector2i(1920, 1080)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	profile = get_node("/root/PlayerProfile")
	var path := "user://comparison-panel-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	profile.reload()
	profile.active_bot = 0
	var original: Dictionary = profile.loadouts[0].duplicate(true)
	screen = load("res://ui/menus/screens/customize.tscn").instantiate()
	add_child(screen)
	await settle()
	await choose("drive", "agile")
	await settle()
	var panel: GarageComparisonPanel = screen.comparison_panel
	check(profile.loadouts[0].parts.drive == "agile" and profile.can_undo(), "Clicking a choice immediately edits the draft")
	check(cell(panel.budgets, 3) == "91", "Stats reflect the selected drive")
	check(cell(panel.details, 3) == "12", "Current speed uses the selected drive")
	screen.undo_button.pressed.emit()
	await settle()
	check(profile.loadouts[0] == original and cell(panel.budgets, 3) == "101", "Undo restores the current build stats")
	for part: Array in [["drive", "walker"], ["weapon", "horizontal_spinner"], ["utility", "cooling_pack"]]:
		await choose(part[0], part[1])
	await choose("armor", "light")
	check("heavy" not in screen._shown_items.map(func(index: int) -> String: return profile.catalogue.parts[ContentRegistry.SLOTS.find("armor")].items[index].id), "Customize omits armor that would exceed 120 kg")
	# Saved builds can still be over budget; the panel must report them without derived stats.
	var armor: Dictionary = profile.catalogue.parts[ContentRegistry.SLOTS.find("armor")]
	for item: Dictionary in armor.items:
		if item.id == "heavy": profile.equip("parts", armor, item)
	await settle()
	check(cell(panel.budgets, 3) == "123", "Over-budget draft immediately updates current mass")
	check(cell(panel.details, 1) == "—", "Invalid build has no invented derived stats")
	check(screen.get_node("%SelDesc").text.contains("Mass exceeds 120 kg"), "Specific current build error is visible")
	check(screen.get_node("%Save").disabled, "Invalid draft disables Save")
	await choose("armor", "light")
	await settle()
	check(cell(panel.budgets, 3) == "108" and cell(panel.details, 1) == "260", "Repair choice restores valid current stats")
	screen.get_node("%TabPaint").pressed.emit()
	await settle()
	screen.get_node("%Items").get_child(1).pressed.emit()
	await settle()
	check(panel.title.text == "CURRENT BUILD", "Stats show the current build")
	check(cell(panel.budgets, 3) == "108", "Paint preserves stats")
	check(profile.loadouts[0].cosmetics.paint != "cyan", "Selecting paint applies immediately")
	await choose("chassis", "balanced")
	await settle()
	for control: Control in [panel, panel.budgets, panel.title, screen.undo_button, screen.redo_button, screen.get_node("%Save")]:
		bounds(control, str(control.name))
	for label: Label in panel.budgets.get_children():
		bounds(label, label.text)
		check(label.get_global_rect().end.x <= panel.get_global_rect().end.x + 1, "Budget cell stays within comparison column: " + label.text)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("garage-comparison-panel.png"))
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"), "Preview/equip/undo never writes loadout store")
	screen.free()
	if failures.is_empty(): print("GARAGE COMPARISON PANEL PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
