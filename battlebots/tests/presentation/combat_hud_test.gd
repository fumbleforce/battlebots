extends SceneTree
## Detached HUD edge cases and rendered layout; authored data is not gameplay evidence.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func frames() -> void:
	for index: int in range(4):
		await process_frame

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var hud: CombatHud = load("res://tests/presentation/combat_hud.tscn").instantiate()
	root.add_child(hud)
	var bot := BotView.new()
	bot.zones = {"front":60.0, "rear":90.0, "left":12.0, "right":0.0, "drive_left":100.0, "drive_right":0.0, "weapon":45.5}
	bot.plate_max = {"front":90.0, "rear":90.0, "left":90.0, "right":90.0}
	bot.core_fraction = 0.64
	bot.heat_fraction = 0.55
	bot.weapon_charge_fraction = 0.4
	bot.weapon_state = &"active"
	bot.recovery_cooldown = 0
	var opponent := BotView.new()
	hud.render(bot, "T", opponent)
	check(hud.resources.keys() == ["Core", "Heat", "Charge"], "HUD exposes heat as its only operating resource")
	check(hud.resources.Core.value.text == "64%" and hud.resources.Heat.value.text == "55%", "Published fractions display accurately")
	check(hud.components.front.text == "FRONT\n60" and hud.components.weapon.text == "WEAPON\n46", "Integrity uses raw units, with positive fractions rounded up")
	check(hud.components.right.text.contains("BREACHED") and hud.components.drive_right.text.contains("DISABLED"), "Destroyed armor and disabled mechanisms are distinguished")
	check(hud.recovery_label.text.ends_with("UNAVAILABLE"), "Zero cooldown does not imply recovery eligibility")
	check(hud.plate_labels.front.text == "Front  60" and hud.plate_labels.left.text == "Left\n12", "Plate map shows each fitted plate's live HP")
	check(hud.plate_labels.top.text == "Top  —" and hud.plate_labels.underside.text == "Bottom  —", "Bare areas read as unarmoured, not breached")
	check(hud.plate_labels.front.modulate == hud._text_color() and hud.plate_labels.left.modulate == hud.accent and hud.plate_labels.right.modulate == hud.danger, "Damaged and breached plates are tinted by share of fitted HP")
	check(hud.plate_labels.right.text == "Right\n0", "Breached plate keeps a numeric reading")
	check(hud._plate_flash.is_empty(), "First reading of a bot is not a hit")
	bot.zones.front = 50.0
	hud.render(bot, "T", opponent)
	check(hud._plate_flash.has("front") and hud.plate_labels.front.modulate == hud.danger and not hud._plate_flash.has("rear"), "Only the plate that lost HP flashes red")
	hud.render(bot, "T", opponent)
	check(hud.plate_labels.front.modulate == hud.danger, "Unchanged HP does not cancel or restart a running flash")
	hud._process(CombatHud.HIT_FLASH + 0.1)
	check(not hud._plate_flash.has("front") and hud.plate_labels.front.modulate == hud._text_color(), "Hit flash returns to the resting colour")
	bot.zones.front = 60.0
	hud.render(bot, "T", opponent)
	check(hud._plate_flash.is_empty(), "Restored HP does not flash")
	hud.combat_event({"target":bot.entity_id, "zone":"top", "damage":12.0})
	hud.render(bot, "T", opponent)
	var bare_red: Color = hud.plate_labels.top.modulate
	check(hud._plate_flash.has("top") and bare_red.s > hud.danger.s and is_equal_approx(bare_red.h, hud.danger.h), "A hit on a bare area flashes that side a deeper red and survives the next render")
	hud.combat_event({"target":bot.entity_id + 1, "zone":"rear", "damage":12.0})
	hud.combat_event({"target":bot.entity_id, "zone":"core", "damage":12.0})
	hud.combat_event({"target":bot.entity_id, "zone":"rear", "damage":0.0})
	check(not hud._plate_flash.has("rear") and hud._plate_flash.size() == 1, "Other bots, unknown zones and harmless contacts do not flash")
	hud.combat_event({"target":bot.entity_id, "zone":"drive_left", "damage":5.0})
	hud.combat_event({"target":bot.entity_id, "zone":"weapon", "damage":5.0})
	check(hud._plate_flash.has("left") and hud._plate_flash.has("front"), "Drive and weapon hits flash the side they sit on")
	hud._process(CombatHud.HIT_FLASH + 0.1)
	check(hud._core_flash == 0.0 and hud.resources.Core.value.modulate == hud._text_color(), "First core reading is not a hit")
	bot.core_fraction = 0.5
	hud.render(bot, "T", opponent)
	check(hud._core_flash > 0.0 and hud.resources.Core.value.modulate == hud.danger, "Lost core integrity flashes the reading")
	check(hud.resources.Core.value.scale.x > 1.0, "A flashing reading swells")
	hud._process(CombatHud.HIT_FLASH * 0.5)
	check(hud.resources.Core.value.rotation != 0.0 or hud.resources.Core.value.scale.x > 1.0, "A flashing reading shakes while it fades")
	hud._process(CombatHud.HIT_FLASH)
	check(hud.resources.Core.value.modulate == hud._text_color(), "Core flash returns to the resting colour")
	check(hud.resources.Core.value.scale == Vector2.ONE and hud.resources.Core.value.rotation == 0.0, "Core reading settles back to rest size and angle")
	bot.core_fraction = 0.64
	hud.render(bot, "T", opponent)
	check(hud._core_flash == 0.0, "Restored core integrity does not flash")
	check(hud.weapon_label.text.ends_with("ACTIVE"), "Powered partial charge is not labelled ready")
	bot.pose = Transform3D.IDENTITY
	bot.recovery_available = true
	bot.immobilized_remaining = 4.2
	hud.render(bot, "T", opponent)
	check(hud.recovery_label.text.contains("READY / T"), "Recovery consumes remapped control label")
	check(hud.warning_label.text.contains("4.2 s"), "Immobilization displays server countdown")
	await frames()
	check(hud.warning_label.text.contains("4.2 s") and bot.immobilized_remaining == 4.2, "HUD neither counts down locally nor mutates input")
	hud.render(bot, "T", opponent, false, true, false)
	check(hud.recovery_label.text.contains("ROUND LOCKED"), "Match-phase lock overrides recovery availability")
	hud.render(bot, "T", opponent)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = resolution
		await frames()
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		for node: Node in hud.find_children("*", "Control", true, false):
			check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD never intercepts mouse: " + str(node.name))
			if node is Label and node.is_visible_in_tree():
				check(bounds.encloses(node.get_global_rect()), "HUD text fits %s: %s %s" % [resolution, node.text, node.get_global_rect()])
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless" and resolution.x <= 1920:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://a-combat-hud-%d.png" % resolution.x)
	bot.eliminated = true
	hud.render(bot, "T", opponent)
	check(hud.warning_label.text == "BOT ELIMINATED" and not hud.recovery_label.text.contains("READY"), "Elimination outranks countdown and stale recovery flag")
	bot.eliminated = false
	bot.immobilized_remaining = 0
	bot.recovery_available = false
	bot.recovery_cooldown = 7.2
	bot.weapon_state = &"disabled"
	bot.overheated = true
	bot.heat_fraction = 0.65
	hud.render(bot)
	check(hud.warning_label.text == "OVERHEATED / COOL TO 50%", "Shared thermal lock displays even when the weapon is disabled")
	check(hud.recovery_label.text.contains("7.2 s COOLDOWN"), "Recovery cooldown uses published seconds")
	bot.zones = {"front":NAN, "rear":-1, "left":true, "right":"0", "weapon":INF}
	bot.core_fraction = 1.1
	bot.heat_fraction = NAN
	bot.weapon_cooldown = INF
	hud.render(bot)
	check(hud.resources.Core.value.text == "--" and hud.resources.Heat.value.text == "--", "Malformed fractions are unavailable, not clamped health")
	for key: String in CombatHud.ZONES:
		check(hud.components[key].text.ends_with("--"), "Malformed/missing component unavailable: " + key)
	for key: String in ["front", "rear", "left", "right"]:
		check(hud.plate_labels[key].text.ends_with("--"), "Malformed plate unavailable: " + key)
	hud.render(null)
	check(hud.resources.Heat.value.text == "--" and not hud.warning_label.visible and not hud.components_panel.visible, "Missing bot clears old HUD state")
	check(not hud.recovery_label.visible, "Missing bot hides stale recovery prompt")
	check(hud.plate_labels.values().all(func(label: Label) -> bool: return label.text.ends_with("--")), "Missing bot clears plate readings")
	hud.free()
	print("COMBAT HUD PASS" if failures == 0 else "COMBAT HUD FAIL")
	quit(0 if failures == 0 else 1)
