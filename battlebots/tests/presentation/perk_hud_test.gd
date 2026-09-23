extends SceneTree
## Presentation acceptance through real local and decoded remote BotView producers.
## Authored combat values isolate HUD behavior; this is not natural gameplay evidence.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var registry := ContentRegistry.new()
	var bot := MvpBot.create(1, 0, registry.starter(), registry)
	root.add_child(bot)
	bot.set_physics_process(false)
	var hud := CombatHud.new()
	root.add_child(hud)
	var parts: Dictionary = bot.loadout.parts.duplicate()
	bot.combat.nitro_active = true
	bot.combat.jump_charge = 0.65
	for remote: bool in [false, true]:
		bot.simulated = remote == false
		if remote:
			bot.remote_state = WireCodec.decode_bot(WireCodec.encode_bot(bot, "perk-hud"), bot.combat.stats)
		var view := bot.read_view()
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.NITRO.text == "ACTIVE", "Local and remote Nitro activity reaches HUD")
		check(hud.perk_labels.JUMP.text == "CHARGING" and hud.jump_gauge.visible and is_equal_approx(hud.jump_gauge.charge, 0.65), "Local and remote charge reaches existing force gauge")
		for palette: String in ["standard", "deuteranopia", "protanopia", "tritanopia"]:
			for contrast: bool in [false, true]:
				hud.apply_accessibility(1.5, palette, contrast)
				check(hud.perk_labels.NITRO.text == "ACTIVE" and hud.perk_labels.NITRO.modulate == hud.accent, "Activity has explicit text in every palette")
				check(hud.jump_gauge.accent == hud.accent and hud.jump_gauge.high_contrast == contrast, "Force gauge shares palette and contrast")
		view.jump_charge_fraction = 1.0
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.JUMP.text == "MAX CHARGE", "Full charge is explicit without color")
		view.jump_charge_fraction = 0.0
		view.jump_cooldown = 2.4
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.JUMP.text == "2.4 s COOLDOWN" and hud.jump_gauge.cooldown == 2.4, "Published cooldown is displayed in seconds")
		for index: int in 4: await process_frame
		check(view.jump_cooldown == 2.4 and hud.perk_labels.JUMP.text == "2.4 s COOLDOWN", "HUD does not invent a local countdown or mutate its view")
		hud.render(view, "R", null, false, true, false, parts)
		check(hud.perk_labels.NITRO.text == "ROUND LOCKED" and hud.perk_labels.JUMP.text == "ROUND LOCKED" and not hud.jump_gauge.visible, "Round lock overrides stale active/charging state")
		view.overheated = true
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.NITRO.text == "OVERHEATED" and hud.perk_labels.JUMP.text == "OVERHEATED" and not hud.jump_gauge.visible, "Shared heat lock never advertises an available perk")
		view.eliminated = true
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.NITRO.text == "DISABLED" and hud.perk_labels.JUMP.text == "DISABLED", "Elimination overrides stale perk activity")
		view.eliminated = false
		view.overheated = false
		view.zones.drive_left = 0
		view.zones.drive_right = 0
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.NITRO.text == "DRIVE DISABLED", "Destroyed drive pods explain unavailable Nitro")
		hud.render(view, "R", null, false, true, true, {"nitro":"nitro_off", "suspension":"jump_off"})
		check(hud.perk_labels.NITRO.text == "NOT EQUIPPED" and hud.perk_labels.JUMP.text == "NOT EQUIPPED" and not hud.jump_gauge.visible, "Unequipped perks override obsolete activity after a loadout swap")
		view.jump_cooldown = INF
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.JUMP.text == "UNAVAILABLE" and not hud.jump_gauge.visible, "Invalid cooldown does not look ready")
		view.jump_cooldown = 0.0
		view.jump_charge_fraction = -0.1
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.JUMP.text == "UNAVAILABLE" and not hud.jump_gauge.visible, "Invalid charge does not invent a force reading")
		view = BotView.new()
		hud.render(view, "R", null, false, true, true, parts)
		check(hud.perk_labels.NITRO.text == "IDLE" and hud.perk_labels.JUMP.text == "IDLE" and not hud.jump_gauge.visible, "Fresh round clears stale activity/cooldowns without claiming ground contact")
		hud.render(view)
		check(hud.perk_labels.NITRO.text == "UNAVAILABLE" and hud.perk_labels.JUMP.text == "UNAVAILABLE", "Missing loadout does not invent equipment")
		hud.render(null, "R", null, false, true, true, parts)
		check(hud.perk_labels.NITRO.text == "UNAVAILABLE" and not hud.jump_gauge.visible, "Missing view clears stale perk readings")
	check(parts == bot.loadout.parts, "HUD leaves loadout metadata unchanged")
	hud.free()
	bot.queue_free()
	for index: int in 4: await process_frame
	# Exercise the real menu composer, including loadout propagation and reset.
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	for index: int in 8: await process_frame
	game.start_practice()
	for index: int in 15: await process_frame
	var local: MvpBot = game.session.local_source()
	check(local != null, "Practice supplies the local source")
	if local != null:
		check(game.combat_hud.perk_labels.NITRO.text == "IDLE" and game.combat_hud.perk_labels.JUMP.text == "IDLE", "Real menu supplies starter perk equipment to HUD")
		game.preview.set_physics_process(false)
		game.session.set_physics_process(false)
		local.combat.nitro_active = true
		local.combat.jump_charge = 0.5
		for index: int in 4: await process_frame
		check(game.combat_hud.perk_labels.NITRO.text == "ACTIVE" and game.combat_hud.jump_gauge.visible, "Real menu composes activity and the force gauge")
		game.session.set_physics_process(true)
		game.restart_practice()
		for index: int in 10: await process_frame
		check(game.combat_hud.perk_labels.NITRO.text == "IDLE" and game.combat_hud.perk_labels.JUMP.text == "IDLE" and not game.combat_hud.jump_gauge.visible, "Real Practice reset clears perk displays")
	game.return_to_main()
	for index: int in 4: await process_frame
	check(not game.combat_hud.visible and not game.combat_hud.jump_gauge.visible, "Leaving the match clears the force gauge")
	game.queue_free()
	for index: int in 8: await process_frame
	print("PERK HUD PASS" if failures == 0 else "PERK HUD FAIL")
	quit(0 if failures == 0 else 1)
