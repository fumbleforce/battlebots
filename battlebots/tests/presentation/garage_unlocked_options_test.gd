extends Node

var failures: Array[String] = []
var profile: Node

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func category(slot: String) -> Dictionary:
	for cat: Dictionary in profile.catalogue.parts:
		if cat.slot == slot: return cat
	return {}

func equip_part(slot: String, id: String) -> void:
	var cat := category(slot)
	for item: Dictionary in cat.items:
		if item.id == id:
			profile.equip("parts", cat, item)
			return
	check(false, "Missing available part " + id)

func _ready() -> void:
	profile = load("res://ui/menus/scripts/player_profile.gd").new()
	profile.save_path = "user://garage_unlocked_options_test.json"
	for suffix: String in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(profile.save_path + suffix)
	add_child(profile)
	var body := category("chassis")
	var body_ids: Array = []
	for item: Dictionary in body.items: body_ids.append(item.id)
	check(body_ids == ["balanced", "scorpion_hex", "atlas_mx"], "All authored bodies offered without legacy placeholders")
	for draft: Dictionary in profile.loadouts:
		check(ScorpionVisual.enabled(draft) or SawbladeConfig.enabled(draft), "Every starter has authored body")
	for tab: String in profile.catalogue:
		for cat: Dictionary in profile.catalogue[tab]:
			for item: Dictionary in cat.items:
				check(profile.item_state(tab, cat, item) in ["own", "eq"], "Every option is unlocked")
	profile.loadouts[0].parts.chassis = "compact"
	profile.loadouts[0].parts.weapon = "horizontal_spinner"
	profile.loadouts[0].parts.drive = "walker"
	profile.loadouts[0].cosmetics.sawblade.exhaust = 3
	var before: Dictionary = profile.loadouts[0].duplicate(true)
	equip_part("chassis", "balanced")
	var expected := before.duplicate(true)
	expected.parts.chassis = "balanced"
	check(profile.loadouts[0] == expected, "Body changes preserve all other parts and cosmetics")
	profile.undo_edit()
	check(profile.loadouts[0] == before, "Undo restores exact previous body and selections")
	profile.redo_edit()
	for drive: String in ["agile", "standard_wheels", "traction", "walker"]:
		for weapon: String in ["saw", "hammer", "lifter", "vertical_spinner", "horizontal_spinner", "minigun"]:
			equip_part("drive", drive)
			equip_part("weapon", weapon)
			check(profile.loadouts[0].parts.drive == drive and profile.loadouts[0].parts.weapon == weapon, "All drive/weapon choices persist")
			check(profile.registry.validate(profile.loadouts[0]).valid, "All twenty-four combinations legal with default side armour")
	for tab: String in ["decals", "paint"]:
		for cat: Dictionary in profile.catalogue[tab]:
			for item: Dictionary in cat.items:
				profile.equip(tab, cat, item)
				var config: Dictionary = profile.loadouts[0].cosmetics.sawblade
				if tab == "decals": check(config[cat.slot] == int(item.id), "Every module equips")
				elif cat.slot == "paint": check(profile.loadouts[0].cosmetics.paint == item.id, "Every overall paint equips")
				else: check(config[cat.slot] == item.rgba, "Every channel paint equips")
	var store := LoadoutStore.new(profile.save_path)
	for old_hash: String in LoadoutStore.REVISION_FIVE_HASHES:
		# Revision-five saves used schema 2 with a light armour package part.
		var legacy := before.duplicate(true)
		legacy.schema_version = 2
		legacy.parts.armor = "light"
		legacy.content_hash = old_hash
		var migrated := store.migrate({"schema_version":1, "loadouts":[legacy]})
		check(migrated.loadouts[0].content_hash == profile.registry.content_hash, "Known previous saves migrate content identity")
		check(migrated.loadouts[0].parts == before.parts and migrated.loadouts[0].schema_version == ContentRegistry.SCHEMA, "Migration retires the armour package")
		check(migrated.loadouts[0].cosmetics == legacy.cosmetics, "Migration preserves legacy compact, selections and appearance")
		check(legacy.content_hash == old_hash, "Migration does not mutate source")
	var saved_legacy := before.duplicate(true)
	saved_legacy.schema_version = 2
	saved_legacy.parts.armor = "light"
	saved_legacy.cosmetics.erase("sawblade")
	saved_legacy.cosmetics.paint = "red"
	saved_legacy.content_hash = LoadoutStore.REVISION_FIVE_HASHES[0]
	var file := FileAccess.open(profile.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1, "loadouts":[saved_legacy]}))
	file.close()
	profile.reload()
	check(profile.loadouts.size() == profile.PRESET_COUNT + 1, "Existing saved build remains available")
	if profile.loadouts.size() == profile.PRESET_COUNT + 1:
		var restored: Dictionary = profile.loadouts[profile.PRESET_COUNT]
		check(restored.parts == before.parts, "Profile reload preserves all legacy selected parts")
		check(restored.cosmetics.paint == "red", "Profile reload retains saved paint")
		check(SawbladeConfig.enabled(restored), "Legacy garage draft receives offered authored appearance")
		check(profile.registry.validate(restored).valid, "Restored legacy draft remains valid")
	for suffix: String in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(profile.save_path + suffix)
	profile.free()
	if failures.is_empty(): print("GARAGE UNLOCKED OPTIONS PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
