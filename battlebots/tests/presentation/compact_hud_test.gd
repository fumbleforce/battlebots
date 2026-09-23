extends SceneTree
## Composed read-only HUD geometry. Authored data is not combat acceptance.
var failures := 0
var combat: CombatHud
var match_hud: MatchHud
var caption: Label
var captures := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func frames(count := 8) -> void:
	for index: int in count:
		await process_frame

func healthy_bot() -> BotView:
	var bot := BotView.new()
	bot.core_fraction = 1.0
	bot.heat_fraction = 0.0
	bot.weapon_charge_fraction = 0.0
	bot.weapon_state = &"idle"
	bot.zones = {"front":60.0, "rear":60.0, "left":60.0, "right":60.0,
		"drive_left":100.0, "drive_right":100.0, "weapon":140.0}
	return bot

func active_match() -> Dictionary:
	return {"phase":"active", "mode":"1v1", "round":2,
		"remaining":137.2, "scores":[1,0]}

func visible_panels() -> Array[Control]:
	var result: Array[Control] = []
	for panel: PanelContainer in combat.panels:
		if panel.is_visible_in_tree():
			result.append(panel)
	var strip: Control = match_hud.get_node("Panel")
	if strip.is_visible_in_tree():
		result.append(strip)
	return result

func fit_caption(factor: float) -> void:
	var reserved := combat.caption_bounds()
	caption.add_theme_font_size_override("font_size", roundi(18 * factor))
	caption.position = reserved.position
	caption.size = reserved.size

func settle_layout(factor: float) -> void:
	# Runtime composes captions after render and asynchronous container sorting.
	await frames()
	fit_caption(factor)
	await frames(2)
	fit_caption(factor)

func check_layout(context: String) -> void:
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	var ratio := minf(root.size.x / 1280.0, root.size.y / 720.0)
	var stack := combat.status_stack.get_global_rect()
	check(viewport.grow(1).encloses(stack), context + ": bottom status stack fits viewport")
	check(absf(stack.get_center().x - root.size.x * 0.5) <= 1.0,
		context + ": status messages remain horizontally centered")
	check(absf(stack.end.y - (root.size.y - 28 * ratio)) <= 1.0,
		context + ": status stack preserves bottom safe margin")
	for status: Control in [combat.warning_label, combat.recovery_label, combat.components_panel]:
		check(status.get_parent() == combat.status_stack, context + ": warnings, recovery and component failures share bottom status layout")
		if status.is_visible_in_tree():
			check(stack.grow(1).encloses(status.get_global_rect()), context + ": status stays within bottom stack")
			check(status.get_global_rect().position.y >= 430 * ratio,
				context + ": status messages remain below the clear battlefield center")
	for tree: Control in [combat, match_hud]:
		for node: Node in tree.find_children("*", "Control", true, false):
			check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				context + ": HUD does not intercept input: " + str(node.name))
			if node is Label and node.is_visible_in_tree():
				check(viewport.grow(1).encloses(node.get_global_rect()),
					context + ": label fits viewport: " + node.text)
				var ancestor: Node = node.get_parent()
				while ancestor != tree and not ancestor is PanelContainer:
					ancestor = ancestor.get_parent()
				if ancestor is PanelContainer:
					check(ancestor.get_global_rect().grow(1).encloses(node.get_global_rect()),
						context + ": label remains inside its card: " + node.text)
	for panel: Control in visible_panels():
		check(viewport.grow(1).encloses(panel.get_global_rect()), context + ": panel fits viewport")
		for other: Control in visible_panels():
			check(panel == other or not panel.get_global_rect().intersects(other.get_global_rect()),
				context + ": visible cards do not overlap")
	if caption.visible:
		var reserved := combat.caption_bounds()
		check(reserved.grow(1).encloses(Rect2(caption.position, caption.size)),
			context + ": simultaneous captions remain inside reserved area: %s / %s" % [Rect2(caption.position, caption.size), reserved])
		for panel: Control in visible_panels():
			check(not caption.get_global_rect().intersects(panel.get_global_rect()),
				context + ": captions do not cover a HUD card")
		for label: Label in [combat.warning_label, combat.recovery_label]:
			if label.is_visible_in_tree():
				check(not caption.get_global_rect().intersects(label.get_global_rect()),
					context + ": captions do not cover warning or recovery")
	if combat.warning_label.is_visible_in_tree() and combat.recovery_label.is_visible_in_tree():
		check(not combat.warning_label.get_global_rect().intersects(combat.recovery_label.get_global_rect()),
			context + ": warning and recovery remain separate")

func capture(label: String, factor: float) -> void:
	if not captures or root.size.x > 1920:
		return
	await RenderingServer.frame_post_draw
	var path := "user://a-compact-hud-%dx%d-%d-%s.png" % [root.size.x, root.size.y, roundi(factor * 100), label]
	var error := root.get_texture().get_image().save_png(path)
	check(error == OK, "Native HUD capture saved")
	if error == OK:
		print("CAPTURE " + ProjectSettings.globalize_path(path))

func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Compact HUD fixture exceeded its wall-clock limit")
		quit(1))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	captures = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	var background := ColorRect.new()
	background.color = Color("34434b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	combat = CombatHud.new()
	root.add_child(combat)
	match_hud = load("res://scenes/ui/match_hud.tscn").instantiate()
	root.add_child(match_hud)
	caption = Label.new()
	caption.size = Vector2(480,96)
	caption.add_theme_font_size_override("font_size", 18)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.text = "Core integrity critical\nSelf-right ready\nFront armor breached"
	combat.canvas.add_child(caption)
	for extent: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080)]:
		root.size = extent
		for factor: float in [1.0,1.25,1.5]:
			var context := "%dx%d / %d%%" % [extent.x, extent.y, roundi(factor * 100)]
			combat.apply_accessibility(factor, "standard", false)
			match_hud.apply_accessibility(factor, "standard", false)
			caption.hide()
			var bot := healthy_bot()
			var rival := healthy_bot()
			combat.render(bot, "R", rival)
			match_hud.render(active_match(), false, 0)
			await settle_layout(factor)
			check(not combat.components_panel.is_visible_in_tree(), context + ": healthy component details stay hidden")
			for label: Node in combat.find_children("*", "Label", true, false):
				if label.is_visible_in_tree():
					check(not label.text.begins_with("CHASSIS /") and not label.text.contains("BOT STATUS"),
						context + ": permanent roster and compass clutter stay removed")
			check(not combat.warning_label.is_visible_in_tree(), context + ": healthy bot has no warning")
			var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
			var clear_center := Rect2(Vector2(extent.x * 0.5 - 280 * ratio, 270 * ratio), Vector2(560,160) * ratio)
			var left_margin := combat.resources_panel.get_global_rect().position.x
			var right_margin := extent.x - combat.weapon_panel.get_global_rect().end.x
			check(absf(left_margin - right_margin) <= 1.0,
				context + ": instruments use matching edges across the full aspect ratio")
			check(absf(caption.get_global_rect().get_center().x - extent.x * 0.5) <= 1.0,
				context + ": captions align with battlefield center")
			var occupied := 0.0
			for panel: Control in visible_panels():
				occupied += panel.get_global_rect().get_area()
				check(not clear_center.intersects(panel.get_global_rect()), context + ": healthy cards leave battlefield center clear")
			if factor == 1.0:
				check(occupied / (extent.x * extent.y) <= 0.12, context + ": healthy cards occupy at most 12% of viewport")
				if extent == Vector2i(1280,720):
					print("COMPACT HUD OCCUPANCY %.2f%%" % (100.0 * occupied / (extent.x * extent.y)))
			check_layout(context + " healthy")
			await capture("healthy", factor)
			bot.zones.front = 0.0
			bot.zones.drive_right = 0.0
			bot.recovery_available = true
			bot.immobilized_remaining = 4.2
			caption.show()
			combat.render(bot, "Ctrl + Shift + Space", rival)
			await settle_layout(factor)
			check(combat.components_panel.is_visible_in_tree(), context + ": breached armor and disabled drive reveal failure details")
			check(combat.components.front.is_visible_in_tree() and combat.components.drive_right.is_visible_in_tree(),
				context + ": failed zones remain visible")
			check(not combat.components.weapon.is_visible_in_tree() and not combat.components.rear.is_visible_in_tree(),
				context + ": healthy zones do not refill failure card")
			check(combat.components.front.text.contains("BREACHED") and combat.components.drive_right.text.contains("DISABLED"),
				context + ": failure types remain explicit without color")
			check(combat.warning_label.text.contains("4.2") and combat.recovery_label.text.contains("Ctrl + Shift + Space"),
				context + ": authoritative countdown and remapped recovery survive compact layout")
			check_layout(context + " recovery")
			await capture("recovery", factor)
			bot = healthy_bot()
			for key: String in bot.zones:
				bot.zones[key] = 0.0
			bot.weapon_state = &"overheated"
			bot.overheated = true
			bot.weapon_cooldown = 999.9
			bot.recovery_available = true
			bot.immobilized_remaining = 4.2
			combat.render(bot, "Ctrl + Shift + Space", rival)
			await settle_layout(factor)
			check_layout(context + " all failures and recovery")
			await capture("worst", factor)
			bot.recovery_available = false
			bot.immobilized_remaining = 0.0
			bot.recovery_cooldown = 999.9
			combat.render(bot, "Ctrl + Shift + Space", rival)
			await settle_layout(factor)
			check_layout(context + " all failures")
			combat.render(healthy_bot(), "R", rival)
			caption.hide()
			await frames()
			check(not combat.components_panel.is_visible_in_tree() and not combat.warning_label.is_visible_in_tree(),
				context + ": repaired round clears obsolete failures")
	combat.render(null)
	await frames()
	check(not combat.components_panel.is_visible_in_tree() and not combat.warning_label.is_visible_in_tree(),
		"Missing baseline clears stale failures")
	check(combat.resources.Core.value.text == "--", "Missing baseline does not invent healthy core")
	var muted_labels: Array[Label] = []
	for label: Node in combat.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.modulate == CombatHud.MUTED:
			muted_labels.append(label)
	combat.apply_accessibility(1.5, "standard", true)
	combat.apply_accessibility(1.5, "standard", false)
	for label: Label in muted_labels:
		check(label.modulate == CombatHud.MUTED, "Cancelling high contrast restores muted label color: " + label.text)
	combat.queue_free()
	match_hud.queue_free()
	background.queue_free()
	await frames()
	print("COMPACT HUD PASS" if failures == 0 else "COMPACT HUD FAIL")
	quit(0 if failures == 0 else 1)
