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
	bot.core_fraction = 0.64
	bot.battery_fraction = 0.33
	bot.heat_fraction = 0.55
	bot.weapon_charge_fraction = 0.4
	bot.weapon_state = &"active"
	bot.recovery_cooldown = 0
	var opponent := BotView.new()
	hud.render(bot, "T", opponent)
	check(hud.resources.Core.value.text == "64%" and hud.resources.Heat.value.text == "55%", "Published fractions display accurately")
	check(hud.components.front.text == "FRONT\n60" and hud.components.weapon.text == "WEAPON\n46", "Integrity uses raw units, with positive fractions rounded up")
	check(hud.components.right.text.contains("BREACHED") and hud.components.drive_right.text.contains("DISABLED"), "Destroyed armor and disabled mechanisms are distinguished")
	check(hud.recovery_label.text.ends_with("UNAVAILABLE"), "Zero cooldown does not imply recovery eligibility")
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
	bot.weapon_state = &"overheated"
	bot.heat_fraction = 0.65
	hud.render(bot)
	check(hud.warning_label.text == "WEAPON OVERHEATED", "Overheat lock follows weapon state after cooling begins")
	check(hud.recovery_label.text.contains("7.2 s COOLDOWN"), "Recovery cooldown uses published seconds")
	bot.zones = {"front":NAN, "rear":-1, "left":true, "right":"0", "weapon":INF}
	bot.core_fraction = 1.1
	bot.heat_fraction = NAN
	bot.weapon_cooldown = INF
	hud.render(bot)
	check(hud.resources.Core.value.text == "--" and hud.resources.Heat.value.text == "--", "Malformed fractions are unavailable, not clamped health")
	for key: String in CombatHud.ZONES:
		check(hud.components[key].text.ends_with("--"), "Malformed/missing component unavailable: " + key)
	hud.render(null)
	check(hud.resources.Battery.value.text == "--" and not hud.warning_label.visible and not hud.components_panel.visible, "Missing bot clears old HUD state")
	check(not hud.recovery_label.visible, "Missing bot hides stale recovery prompt")
	hud.free()
	print("COMBAT HUD PASS" if failures == 0 else "COMBAT HUD FAIL")
	quit(0 if failures == 0 else 1)
