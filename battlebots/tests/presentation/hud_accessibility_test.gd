extends SceneTree
## Detached authored data validates accessibility presentation, not combat behavior.
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func frames() -> void:
	for i: int in 8:
		await process_frame
func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var combat := CombatHud.new()
	root.add_child(combat)
	var match_hud: MatchHud = load("res://scenes/ui/match_hud.tscn").instantiate()
	root.add_child(match_hud)
	var bot := BotView.new()
	bot.zones = {"front":0.0,"rear":0.0,"left":0.0,"right":0.0,"drive_left":0.0,"drive_right":0.0,"weapon":0.0}
	bot.weapon_state = &"overheated"
	bot.weapon_cooldown = 999.9
	bot.recovery_cooldown = 999.9
	bot.immobilized_remaining = 4.2
	for extent: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = extent
		for colors: String in ["standard", "deuteranopia", "protanopia", "tritanopia"]:
			for contrast: bool in [false,true]:
				combat.apply_accessibility(1.5, colors, contrast)
				match_hud.apply_accessibility(1.5, colors, contrast)
				combat.render(bot, "T", bot)
				match_hud.render({"phase":"intermission", "round":3, "remaining":15, "scores":[1,1], "rounds":[{"round":3,"winner":0}]},false,0)
				await frames()
				var bounds := Rect2(Vector2.ZERO, Vector2(extent))
				for tree: Control in [combat,match_hud]:
					for node: Node in tree.find_children("*", "Label", true, false):
						if node.is_visible_in_tree():
							check(bounds.encloses(node.get_global_rect()), "Text within viewport: " + node.text)
							var panel: Node = node.get_parent()
							while panel != tree and not panel is PanelContainer:
								panel = panel.get_parent()
							if panel is PanelContainer:
								check(panel.get_global_rect().grow(1).encloses(node.get_global_rect()), "Text within panel: " + node.text)
				for panel: PanelContainer in combat.panels:
					check(bounds.encloses(panel.get_global_rect()), "Combat panel fits viewport")
					for other: PanelContainer in combat.panels:
						check(panel == other or not panel.get_global_rect().intersects(other.get_global_rect()), "Combat panels do not overlap")
					check(not panel.get_global_rect().intersects(match_hud.get_node("Panel").get_global_rect()), "Combat does not overlap round panel")
				check(combat.components.front.text.ends_with("BREACHED") and combat.components.weapon.text.ends_with("DISABLED"), "Status is expressed without color")
				check(combat.weapon_label.get_theme_font_size("font_size") == 27, "Text scale grows font independent of canvas")
				if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless" and contrast:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("user://a-accessible-hud-%d-%s.png" % [extent.x, colors])
	for combat_active: bool in [false, true]:
		bot.recovery_available = true
		bot.failure_reason = "recovery_unavailable"
		combat.render(bot, "Ctrl + Shift + Space", bot, false, true, combat_active)
		await frames()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(combat.weapon_panel.get_global_rect()), "Expanded recovery binding and phase-lock feedback stay within viewport")
	combat.apply_accessibility(1.0, "standard", false)
	match_hud.apply_accessibility(1.0, "standard", false)
	combat.render(bot)
	await frames()
	check(combat.weapon_label.get_theme_font_size("font_size") == 18 and combat.weapon_panel.position.x == 1000, "Default scale and layout restore")
	combat.free()
	match_hud.free()
	print("HUD ACCESSIBILITY PASS" if failures == 0 else "HUD ACCESSIBILITY FAIL")
	quit(0 if failures == 0 else 1)
