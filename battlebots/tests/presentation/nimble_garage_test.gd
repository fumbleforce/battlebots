extends SceneTree
## Nimble bots (#61) are selectable, playable factory builds that cannot be
## customised yet: garage links are disabled, profile edits and saves refuse,
## Customize and pickups never offer their parts, and older saves migrate.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures.append(message)

func settle() -> void:
	for _frame in 5: await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var profile = root.get_node("PlayerProfile")
	profile.save_path = "user://nimble-garage-%d.json" % Time.get_ticks_usec()
	profile.reload()
	var sealed: Array[int] = []
	for index: int in profile.PRESET_COUNT:
		if NimbleBots.enabled(profile.loadouts[index]): sealed.append(index)
	check(sealed.size() == NimbleBots.ORDER.size(), "Every nimble bot is a built-in preset")
	for index: int in sealed:
		check(profile.bots[index].valid and profile.bots[index].sealed, "%s is valid and sealed" % profile.bots[index].name)
		check(profile.bots[index].stats["SPEED m/s"] > profile.bots[4].stats["SPEED m/s"], "%s is faster than Atlas MX on paper" % profile.bots[index].name)
	var garage: Control = load("res://ui/menus/screens/garage.tscn").instantiate()
	root.add_child(garage)
	await settle()
	garage._select(sealed[0])
	check(garage.customize_button.disabled and garage.get_node("%WeaponSlot").disabled, "Garage disables Customize for a factory build")
	check(profile.active_loadout().parts.chassis == NimbleBots.ORDER[0], "A factory build can be the active (playable) build")
	var before: Dictionary = profile.loadouts[sealed[0]].duplicate(true)
	var parts: Array = profile.catalogue.parts
	var weapons: Dictionary = parts.filter(func(cat: Dictionary) -> bool: return cat.slot == "weapon")[0]
	profile.equip("parts", weapons, weapons.items[0])
	profile.rename_draft("Renamed")
	check(profile.loadouts[sealed[0]] == before, "Profile edits leave a factory build unchanged")
	check(profile.save_active("Copy") == ERR_UNAUTHORIZED, "A factory build cannot be saved over")
	garage._select(0)
	check(not garage.customize_button.disabled and not garage.get_node("%WeaponSlot").disabled, "Other builds stay customisable")
	garage.free()
	for cat: Dictionary in parts:
		for item: Dictionary in cat.items:
			check(not NimbleBots.locked_part(item.id), "Customize does not offer %s" % item.id)
	var pickups := MatchPickups.new()
	check(pickups.pool.all(func(id: String) -> bool: return not NimbleBots.locked_part(id)), "Pickups never drop nimble parts")
	var nimble: Dictionary = profile.loadouts[sealed[1]]
	check(pickups.swapped(nimble, "saw").is_empty() and pickups.swapped(nimble, "atlas_mx").is_empty(),
		"A nimble bot refuses part pickups")
	check(not pickups.swapped(nimble, "jump_off").is_empty(), "Perk choices stay free on a nimble bot")
	# A revision-16 save keeps its parts and adopts the current catalogue.
	var old: Dictionary = profile.registry.duelist()
	old.content_hash = LoadoutStore.REVISION_SIXTEEN_HASHES[0]
	var migrated: Dictionary = LoadoutStore.new("user://unused.json").migrate({"schema_version": 1, "loadouts": [old]})
	check(migrated.loadouts[0].content_hash == profile.registry.content_hash and migrated.loadouts[0].parts == old.parts,
		"Revision-16 saves migrate to catalogue 17 unchanged")
	await settle()
	for failure: String in failures: push_error(failure)
	print("NIMBLE GARAGE PASS" if failures.is_empty() else "NIMBLE GARAGE FAIL")
	quit(0 if failures.is_empty() else 1)
