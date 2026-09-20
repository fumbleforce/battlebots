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
	check(profile.bots.size() == 3 and profile.active_loadout().parts.weapon == "saw" and SawbladeConfig.enabled(profile.active_loadout()),"Sawblade starter selected by default")
	check(profile.bots[0].hp == 260 and profile.bots[0].stats["SPEED m/s"] == 8,"Canonical derived stats")
	profile.active_bot = 2
	check(profile.active_loadout().parts.weapon == "hammer" and profile.bots[2].name == "Duelist",
		"Duelist is a selectable legal hammer starter")
	profile.active_bot = 0
	var paint: Dictionary = profile.catalogue.paint[0]
	profile.equip("paint",paint,paint.items[1])
	check(profile.active_loadout().cosmetics.paint == "orange","Canonical paint equipped")
	check(profile.save_active("Office Striker") == OK,"Named build persists")
	var saved := LoadoutStore.new(path).load_saved()
	check(saved.loadouts.size() == 1 and saved.loadouts[0].cosmetics.paint == "orange","Save can be reloaded")
	profile.reload()
	check(profile.bots.size() == 4 and profile.bots[3].name == "Office Striker","Three starters and saved build loaded")
	profile.active_bot = 3
	var chassis: Dictionary = profile.catalogue.parts[0]
	profile.equip("parts",chassis,chassis.items[0])
	var drive: Dictionary = profile.catalogue.parts[1]
	profile.equip("parts",drive,drive.items[3])
	var weapon: Dictionary = profile.catalogue.parts[2]
	profile.equip("parts",weapon,weapon.items[1])
	var armor: Dictionary = profile.catalogue.parts[3]
	profile.equip("parts",armor,armor.items[2])
	check(profile.active_loadout().is_empty() and not profile.bots[3].valid,"Overweight combination retained but cannot play")
	check(profile.save_active("Overweight") == ERR_INVALID_DATA,"Invalid save rejected")
	check(LoadoutStore.new(path).load_saved().loadouts[0].name == "Office Striker","Rejected save preserves disk")
	profile.equip("parts",armor,armor.items[0])
	check(not profile.active_loadout().is_empty(),"Build repair restores validity")
	check(profile.save_active("Repaired") == OK,"Repaired build saves")
	var detached: Dictionary = profile.active_loadout()
	detached.parts.weapon = "bogus"
	check(profile.active_loadout().parts.weapon == "horizontal_spinner","Returned draft is detached")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"loadouts":[{"name":"Broken"}]}))
	file.close()
	profile.reload()
	check(profile.bots.size() == 4 and not profile.bots[3].valid,"Invalid saved build remains visible")
	profile.active_bot = 3
	profile.loadouts[3].parts = "malformed"
	profile.loadouts[3].cosmetics = false
	check(profile.equipped_name("parts",profile.catalogue.parts[0]) == "Missing / invalid","Malformed parts safe in Customize")
	check(profile.equipped_name("paint",profile.catalogue.paint[0]) == "Missing / invalid","Malformed cosmetics safe in Customize")
	profile.active_bot = 0
	check(profile.save_active("New") == OK,"Unrelated valid save succeeds without requiring every sibling repair")
	var preserved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(preserved.loadouts.size() == 2 and preserved.loadouts[0] == {"name":"Broken"},
		"Unrelated save preserves invalid disk entry exactly, not its unsaved edits")
	profile.free()
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	if failures.is_empty(): print("MENU PROFILE PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
