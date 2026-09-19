extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func run() -> void:
	var profile = load("res://ui/menus/scripts/player_profile.gd").new()
	var path := "user://menu-profile-test-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	root.add_child(profile)
	await process_frame
	check(profile.bots.size() == 2 and profile.active_loadout().parts.weapon == "vertical_spinner","Canonical starter builds")
	check(profile.bots[0].hp == 260 and profile.bots[0].stats["SPEED m/s"] == 10,"Canonical derived stats")
	var paint: Dictionary = profile.catalogue.paint[0]
	profile.equip("paint",paint,paint.items[1])
	check(profile.active_loadout().cosmetics.paint == "orange","Canonical paint equipped")
	check(profile.save_active("Office Striker") == OK,"Named build persists")
	var saved := LoadoutStore.new(path).load_saved()
	check(saved.loadouts.size() == 1 and saved.loadouts[0].cosmetics.paint == "orange","Save can be reloaded")
	profile.reload()
	check(profile.bots.size() == 3 and profile.bots[2].name == "Office Striker","Two starters and saved build loaded")
	profile.active_bot = 2
	var chassis: Dictionary = profile.catalogue.parts[0]
	profile.equip("parts",chassis,chassis.items[2])
	var drive: Dictionary = profile.catalogue.parts[1]
	profile.equip("parts",drive,drive.items[2])
	var armor: Dictionary = profile.catalogue.parts[3]
	profile.equip("parts",armor,armor.items[2])
	check(profile.active_loadout().is_empty() and not profile.bots[2].valid,"Overweight combination retained but cannot play")
	check(profile.save_active("Overweight") == ERR_INVALID_DATA,"Invalid save rejected")
	check(LoadoutStore.new(path).load_saved().loadouts[0].name == "Office Striker","Rejected save preserves disk")
	profile.equip("parts",armor,armor.items[0])
	check(not profile.active_loadout().is_empty(),"Build repair restores validity")
	check(profile.save_active("Repaired") == OK,"Repaired build saves")
	var detached: Dictionary = profile.active_loadout()
	detached.parts.weapon = "bogus"
	check(profile.active_loadout().parts.weapon == "vertical_spinner","Returned draft is detached")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"loadouts":[{"name":"Broken"}]}))
	file.close()
	profile.reload()
	check(profile.bots.size() == 3 and not profile.bots[2].valid,"Invalid saved build remains visible")
	profile.active_bot = 2
	profile.loadouts[2].parts = "malformed"
	profile.loadouts[2].cosmetics = false
	check(profile.equipped_name("parts",profile.catalogue.parts[0]) == "Missing / invalid","Malformed parts safe in Customize")
	check(profile.equipped_name("paint",profile.catalogue.paint[0]) == "Missing / invalid","Malformed cosmetics safe in Customize")
	profile.active_bot = 0
	check(profile.save_active("New") == ERR_INVALID_DATA,"Unrelated save cannot erase invalid entries")
	profile.free()
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	if failures.is_empty(): print("MENU PROFILE PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
