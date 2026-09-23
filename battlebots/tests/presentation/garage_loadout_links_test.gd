extends SceneTree
## Garage loadout rows open Customize at the part slot they summarise.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func settle() -> void:
	for _frame in 5: await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var profile = root.get_node("PlayerProfile")
	profile.save_path = "user://garage-loadout-links-%d.json" % Time.get_ticks_usec()
	profile.reload()
	var garage: Control = load("res://ui/menus/screens/garage.tscn").instantiate()
	root.add_child(garage)
	await settle()
	check(garage.get_node("%BoostSlot/Pad/Row/Text/Label").text == "PERKS", "Perks row is not labelled as the brake")
	for link: Array in [["%WeaponSlot", "weapon"], ["%AbilitySlot", "utility"], ["%BoostSlot", "nitro"]]:
		CustomizeRequest.slot = ""
		garage.get_node(link[0]).pressed.emit()
		check(CustomizeRequest.slot == link[1], link[0] + " requests the " + link[1] + " slot")
		var customize: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
		root.add_child(customize)
		await settle()
		var category: Dictionary = profile.catalogue.parts[customize._cat.parts]
		check(customize._tab == "parts" and category.slot == link[1], "Customize opens at " + link[1])
		check(customize.get_node("%Categories").get_child(customize._cat.parts).button_pressed, "Requested category row is selected")
		check(customize.get_node("%Categories").get_child(customize._cat.parts).visible, "Requested category row is on the shown page")
		var equipped: int = category.items.map(func(item: Dictionary) -> String: return item.id).find(profile.loadouts[profile.active_bot].parts[link[1]])
		var tile: Control = customize.choice_tile("parts", customize._cat.parts, equipped)
		check(tile != null and tile.get_node("%Status").text == "EQUIPPED", "Equipped " + link[1] + " choice is listed")
		check(CustomizeRequest.slot == "", "Request is consumed once")
		customize.free()
	var plain: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	root.add_child(plain)
	await settle()
	check(profile.catalogue.parts[plain._cat.parts].slot == "chassis", "Plain Customize still opens at the first slot")
	plain.free()
	garage.free()
	for suffix: String in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(profile.save_path + suffix)
	await process_frame
	if failures.is_empty(): print("GARAGE LOADOUT LINKS PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
