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
		if category.items[item_index].id == id:
			screen.get_node("%Items").get_child(item_index).pressed.emit()
			await settle()
			return
	check(false, "Missing test catalogue part " + id)

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
	await choose("chassis", "wide")
	await settle()
	var panel: GarageComparisonPanel = screen.comparison_panel
	check(profile.loadouts[0] == original and not profile.can_undo(), "Selecting candidate does not equip or change history")
	check(cell(panel.budgets, 5) == "103" and cell(panel.budgets, 6) == "108" and cell(panel.budgets, 7) == "+5", "Mass compares equipped/current/proposed delta")
	check(cell(panel.details, 1) == "260" and cell(panel.details, 2) == "300" and cell(panel.details, 3) == "+40", "Core uses candidate chassis")
	screen.get_node("%Action").pressed.emit()
	await settle()
	check(profile.loadouts[0].parts.chassis == "wide", "Equip applies selected part")
	check(cell(panel.budgets, 5) == "108" and cell(panel.budgets, 6) == "108" and cell(panel.budgets, 7) == "0", "Equip refreshes current and proposed")
	screen.undo_button.pressed.emit()
	await settle()
	check(profile.loadouts[0] == original and cell(panel.budgets, 5) == "103" and cell(panel.budgets, 6) == "108", "Undo restores equipped comparison while retaining candidate")
	for part: Array in [["chassis", "wide"], ["drive", "traction"], ["weapon", "horizontal_spinner"], ["utility", "battery_pack"]]:
		await choose(part[0], part[1])
		screen.get_node("%Action").pressed.emit()
		await settle()
	await choose("armor", "heavy")
	await settle()
	check(cell(panel.budgets, 5) == "119" and cell(panel.budgets, 6) == "126" and cell(panel.budgets, 7) == "+7", "Overbudget proposal retains verified totals")
	check(cell(panel.details, 1) == "300" and cell(panel.details, 2) == "—" and cell(panel.details, 3) == "—", "Invalid proposal has no invented derived stats or delta")
	check(screen.get_node("%SelDesc").text.contains("Mass exceeds 120 kg"), "Specific candidate error is visible")
	screen.get_node("%Action").pressed.emit()
	await settle()
	check(screen.get_node("%Save").disabled and cell(panel.budgets, 5) == "126", "Invalid equipped draft retains budget and disables Save")
	await choose("armor", "light")
	await settle()
	check(cell(panel.budgets, 6) == "111" and cell(panel.details, 1) == "—" and cell(panel.details, 2) == "300", "Repair candidate restores derived stats only for valid proposed build")
	screen.get_node("%Action").pressed.emit()
	await settle()
	screen.get_node("%TabPaint").pressed.emit()
	await settle()
	screen.get_node("%Items").get_child(1).pressed.emit()
	await settle()
	check(panel.title.text.contains("COSMETICS DO NOT CHANGE STATS"), "Paint explains cosmetic-only comparison")
	check(cell(panel.budgets, 5) == "111" and cell(panel.budgets, 6) == "111" and cell(panel.budgets, 7) == "0", "Paint preserves stats")
	check(profile.loadouts[0].cosmetics.paint == "cyan", "Selecting paint does not equip")
	await choose("chassis", "compact")
	await settle()
	for control: Control in [panel, panel.budgets, panel.title, screen.undo_button, screen.redo_button, screen.get_node("%Save"), screen.get_node("%Action")]:
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

