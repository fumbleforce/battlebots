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

func open_category(slot: String) -> int:
	screen.get_node("%TabParts").pressed.emit()
	await settle()
	var index: int = profile.catalogue.parts.map(func(cat: Dictionary) -> String: return cat.slot).find(slot)
	screen.get_node("%Categories").get_child(index).pressed.emit()
	await settle()
	return index

func choose(slot: String, id: String) -> void:
	var index: int = await open_category(slot)
	var category: Dictionary = profile.catalogue.parts[index]
	for item_index: int in category.items.size():
		if category.items[item_index].id == id and screen.choice_tile("parts", index, item_index) != null:
			screen.choice_tile("parts", index, item_index).pressed.emit()
			await settle()
			return
	check(false, "Customize does not list part " + id)

## Armour pieces are the PARTS > ARMOR section choices (module index per body area).
func choose_armor(section: String, choice: int) -> void:
	await open_category("armor")
	var modules: Array = profile.catalogue.decals
	for module: int in modules.size():
		if modules[module].slot == section and screen.choice_tile("decals", module, choice) != null:
			screen.choice_tile("decals", module, choice).pressed.emit()
			await settle()
			return
	check(false, "Customize does not list armour %s %d" % [section, choice])

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
	check(cell(panel.budgets, 3) == "79", "Stats reflect the selected drive")
	check(cell(panel.details, 3) == "13.2", "Current speed uses the selected drive, scaled up for a light 79 kg build")
	screen.undo_button.pressed.emit()
	await settle()
	check(profile.loadouts[0] == original and cell(panel.budgets, 3) == "89", "Undo restores the current build stats")
	for part: Array in [["drive", "walker"], ["weapon", "horizontal_spinner"], ["utility", "cooling_pack"]]:
		await choose(part[0], part[1])
	await choose_armor("armor_front", 1)
	await choose_armor("armor_rear", 1)
	check(cell(panel.budgets, 2) == "Mass (kg)" and cell(panel.budgets, 3) == "116", "Armour pieces add their mass")
	check(cell(panel.details, 3) == "3.7", "116 kg walker loses top speed")
	# Heavy side skirts take the build past 120 kg: still legal, just slower.
	await choose_armor("armor_side", 2)
	check(cell(panel.budgets, 3) == "122" and cell(panel.details, 1) == "240", "Heavy draft stays valid with derived stats")
	check(cell(panel.details, 3) == "3.6" and not screen.get_node("%Save").disabled, "Heavier draft is slower but saveable")
	# A quad-cannon turret needs the Atlas roof and overdraws the power cap; the panel reports it without derived stats.
	var utility: Dictionary = profile.catalogue.parts[profile.catalogue.parts.map(func(cat: Dictionary) -> String: return cat.slot).find("utility")]
	for item: Dictionary in utility.items:
		if item.id == "turret_cannon_quad": profile.equip("parts", utility, item)
	await settle()
	check(cell(panel.budgets, 3) == "146" and cell(panel.budgets, 5) == "115", "Invalid draft immediately updates current budgets")
	check(cell(panel.details, 1) == "—", "Invalid build has no invented derived stats")
	check(screen.get_node("%SelDesc").text.contains("Installed power exceeds 100"), "Specific current build error is visible")
	check(screen.get_node("%Save").disabled, "Invalid draft disables Save")
	await choose("utility", "cooling_pack")
	await choose_armor("armor_side", 1)
	await settle()
	check(cell(panel.budgets, 3) == "116" and cell(panel.details, 1) == "240", "Repair choice restores valid current stats")
	var armor_row: Array = range(panel.details.get_child_count()).filter(func(index: int) -> bool: return cell(panel.details, index) == "Armor HP (all pieces)")
	check(armor_row.size() == 1 and cell(panel.details, armor_row[0] + 1) == "290", "Armor HP sums every fitted piece")
	screen.get_node("%TabPaint").pressed.emit()
	await settle()
	screen.get_node("%Items").get_child(1).pressed.emit()
	await settle()
	check(panel.title.text == "CURRENT BUILD", "Stats show the current build")
	check(cell(panel.budgets, 3) == "116", "Paint preserves stats")
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
