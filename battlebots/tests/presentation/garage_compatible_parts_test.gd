extends SceneTree
## Customize lists only parts that fit the current build; a body change swaps only
## the parts it cannot use and restores them on switching back.
var failures: Array[String] = []
var profile: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func use(parts: Dictionary, armor := {}) -> void:
	var draft: Dictionary = profile.registry.starter()
	draft.parts.merge(parts, true)
	if not armor.is_empty():
		draft.cosmetics["sawblade"] = SawbladeConfig.defaults()
		draft.cosmetics.sawblade.merge(armor, true)
	profile.loadouts[0] = draft
	profile.active_bot = 0

func category(slot: String) -> Dictionary:
	for cat: Dictionary in profile.catalogue.parts:
		if cat.slot == slot: return cat
	return {}

func equip_part(slot: String, id: String) -> void:
	for item: Dictionary in category(slot).items:
		if item.id == id: profile.equip("parts", category(slot), item)

func shown_ids(screen: Control, slot: String) -> Array:
	var cats: Array = profile.catalogue.parts
	for index: int in cats.size():
		if cats[index].slot == slot: screen._cat["parts"] = index
	screen._refresh()
	var ids: Array = []
	for index: int in screen._shown_items: ids.append(category(slot).items[index].id)
	return ids

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	profile = root.get_node("PlayerProfile")
	profile.save_path = "user://garage-compatible-parts-test-%d.json" % Time.get_ticks_usec()
	profile.reload()

	use({"chassis":"balanced", "drive":"standard_wheels", "weapon":"hammer", "utility":"recovery_assist"})
	check(not profile.part_fits("utility", "minigun_pod"), "Sawblade body hides the auxiliary minigun")
	check(profile.part_fits("drive", "walker") and profile.part_fits("drive", "traction"), "Sawblade keeps every drive it can mount")
	check(profile.part_fits("weapon", "minigun"), "Primary minigun fits without an auxiliary gun")

	use({"chassis":"scorpion_hex", "drive":"walker", "weapon":"hammer", "utility":"minigun_pod"})
	check(profile.registry.validate(profile.loadouts[0]).valid, "Scorpion fixture is valid")
	check(not profile.part_fits("drive", "traction") and not profile.part_fits("drive", "agile"), "Scorpion hides drives other than walking legs")
	check(not profile.part_fits("weapon", "minigun"), "One minigun per gun socket")
	check(profile.part_fits("weapon", "lifter"), "Scorpion keeps compatible primaries")

	use({"chassis":"scorpion_hex", "drive":"walker", "weapon":"hammer", "utility":"recovery_assist"},
		{"armor_side":2, "armor_front":1, "armor_rear":1})
	check(profile.registry.validate(profile.loadouts[0]).valid, "Heavy Scorpion fixture is valid at 115 kg")
	check(not profile.part_fits("weapon", "horizontal_spinner"), "Over-mass weapon is hidden")
	check(not profile.part_fits("utility", "minigun_pod"), "Over-mass auxiliary is hidden")
	check(profile.part_fits("utility", "cooling_pack"), "Utilities within budget remain")

	use({"chassis":"balanced", "drive":"standard_wheels", "weapon":"hammer", "utility":"minigun_pod"})
	check(profile.part_fits("utility", "minigun_pod"), "Equipped invalid part remains listed for repair")
	check(profile.part_fits("utility", "cooling_pack"), "Repairing choices remain listed on an invalid build")

	use({"chassis":"balanced", "drive":"standard_wheels", "weapon":"hammer", "utility":"recovery_assist"})
	var before: Dictionary = profile.loadouts[0].duplicate(true)
	check(profile.fit_body("scorpion_hex").swaps == {"drive": ["standard_wheels", "walker"]}, "Body preview names the automatic drive swap")
	equip_part("chassis", "scorpion_hex")
	var expected := before.duplicate(true)
	expected.parts.chassis = "scorpion_hex"
	expected.parts.drive = "walker"
	expected.cosmetics["sawblade"] = SawbladeConfig.defaults()
	check(profile.loadouts[0] == expected, "Body switch swaps only the parts the new body cannot use")
	check(profile.registry.validate(profile.loadouts[0]).valid, "Body switch leaves a valid build")
	equip_part("chassis", "balanced")
	check(profile.loadouts[0].parts == before.parts, "Switching back re-equips the original parts")
	equip_part("chassis", "atlas_mx")
	check(profile.loadouts[0].parts.drive == "standard_wheels", "Atlas keeps a drive it can mount (large wheels)")
	equip_part("weapon", "saw")
	equip_part("chassis", "balanced")
	check(profile.loadouts[0].parts.drive == "standard_wheels" and profile.loadouts[0].parts.weapon == "saw", "Manual edits on another body survive switching back")

	var screen: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	root.add_child(screen)
	for _frame in 5: await process_frame
	use({"chassis":"balanced", "drive":"standard_wheels", "weapon":"hammer", "utility":"recovery_assist"})
	var utilities := shown_ids(screen, "utility")
	check("minigun_pod" not in utilities and "recovery_assist" in utilities, "Customize omits the auxiliary minigun on Sawblade")
	check(screen.get_node("%Items").get_child_count() == utilities.size(), "One tile per listed choice")
	check(screen.get_node("%Count").text == "%d / %d available" % [utilities.size(), category("utility").items.size()], "Count reflects filtered choices")
	check(shown_ids(screen, "chassis").size() == category("chassis").items.size(), "Every body stays selectable")
	equip_part("chassis", "scorpion_hex")
	check(shown_ids(screen, "drive") == ["walker"], "Scorpion switches to and lists only walking legs")
	check("minigun_pod" in shown_ids(screen, "utility"), "Scorpion lists the auxiliary minigun")
	shown_ids(screen, "weapon")
	for _frame in 6: await process_frame
	for tile: Control in screen.get_node("%Items").get_children():
		if not tile.visible: continue
		var inner: Control = tile.get_node("Inner")
		check(inner.get_global_rect().is_equal_approx(tile.get_global_rect()), "Tile contents stay inside their tile: " + tile.get_node("%Name").text)
		check(tile.size.y < 100, "Part tiles are compact")
	check(screen.get_node("Layout/Footer").get_global_rect().end.y <= 1081, "Footer remains within viewport")
	screen.free()
	for suffix: String in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(profile.save_path + suffix)
	await process_frame
	if failures.is_empty(): print("GARAGE COMPATIBLE PARTS PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
