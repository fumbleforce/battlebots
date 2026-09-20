extends Node
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	get_window().size = Vector2i(1280, 720)
	var registry := ContentRegistry.new()
	var draft := SawbladeConfig.starter(registry)
	check(registry.validate(draft).valid, "Sawblade starter is legal")
	check(registry.validate(registry.starter()).valid, "Legacy builds remain legal")
	for bad: Variant in [-1, 3, 1.5, "1", INF]:
		var malformed := draft.duplicate(true)
		malformed.cosmetics.sawblade.armor_side = bad
		check(not registry.validate(malformed).valid, "Reject malformed module value")
	var malformed := draft.duplicate(true)
	malformed.cosmetics.sawblade.paint_primary[3] = 0.0
	check(not registry.validate(malformed).valid, "Reject invisible paint")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var preview := GarageBotPreview.new()
	host.add_child(preview)
	for weapon: String in SawbladeConfig.WEAPONS:
		draft.parts.weapon = weapon
		preview.show_loadout(draft)
		var visual := preview.sawblade_visual
		check(visual != null, "Model assembled for " + weapon)
		if visual == null: continue
		for module: String in ["saw", "hammer", "ramp"]:
			check(visual.nodes["Module_weapon_" + module].visible == (module == SawbladeConfig.WEAPONS[weapon]), "Exactly the equipped weapon is visible")
		if weapon == "hammer":
			var ready_pose: Transform3D = visual.nodes.Hammer_SWING_X.transform
			var view := BotView.new()
			view.weapon_state = "windup"
			view.weapon_charge_fraction = 0.5
			visual.show_state(view, 1.0 / 60)
			check(not visual.nodes.Hammer_SWING_X.transform.is_equal_approx(ready_pose), "Primary windup drives authored hammer motion")
			view.weapon_state = "strike"
			visual.show_state(view, 1.0 / 60)
			check(is_equal_approx(visual.hammer_frame, 9), "Authored impact frame matches authoritative strike")
			var impact: Node3D = visual.nodes.Hammer_Impact
			check(absf(visual.to_local(impact.global_position).y) < 0.002, "Authored impact plane reaches ground")
			view.weapon_state = "idle"
			visual.show_state(view, 1.0 / 60)
			check(visual.nodes.Hammer_SWING_X.transform.is_equal_approx(ready_pose), "Hammer returns to authored ready pose")
	for slot: String in SawbladeConfig.OPTIONS:
		for choice: int in SawbladeConfig.OPTIONS[slot].size():
			draft.cosmetics.sawblade[slot] = choice
			preview.show_loadout(draft)
			check(preview.sawblade_visual != null, "All module choices assemble")
	draft.parts.weapon = "hammer"
	draft.parts.drive = "standard_wheels"
	preview.show_loadout(draft)
	check(preview.sawblade_visual.nodes.Module_drive_wheels.visible, "Four wheel drive selects wheels")
	check(not preview.sawblade_visual.nodes.Module_drive_tracks.visible, "Wheels hide tracks")
	var walking := draft.duplicate(true)
	walking.parts.drive = "walker"
	walking.parts.armor = "light"
	preview.show_loadout(walking)
	preview.set_auto_rotate(true)
	var assembly: Node3D = preview.model.get_parent()
	var before_rotation := assembly.rotation.y
	preview._process(0.5)
	preview.sawblade_visual.walker_legs._process(0.5)
	check(not is_equal_approx(before_rotation, assembly.rotation.y), "Authored walker participates in the shared rotating showcase")
	check(preview.rotation_button.visible and preview.status.text == "Drag to inspect", "Authored showcase exposes rotation controls and compact status")
	for leg: Dictionary in preview.sawblade_visual.walker_legs.legs:
		check(Vector3(leg.neutral).distance_to(preview.sawblade_visual.walker_legs.to_local(leg.foot)) < 0.001, "Showcase feet rotate with the pedestal without terrain stepping")
	preview.set_auto_rotate(false)
	preview.show_loadout(draft)
	# Existing primary action exercises real combat readiness, charge and cooldown.
	var combat := CombatState.new(registry.validate(draft).stats)
	var command := BotCommand.new()
	command.primary_pressed = true
	combat.tick(1.0 / 60, command, true)
	check(combat.weapon_phase == "windup", "Primary action starts hammer windup")
	command.primary_pressed = false
	var hit := false
	for tick: int in 120:
		combat.tick(1.0 / 60, command, true)
		hit = hit or combat.strike
	check(hit, "Hammer primary produces authoritative strike")
	check(combat.cooldown <= 0, "Hammer returns after cooldown")
	var storage := LoadoutStore.new("user://sawblade_test.json")
	check(storage.save([draft]) == OK, "Save all modules and paint")
	check(storage.load_saved().loadouts[0] == JSON.parse_string(JSON.stringify(draft)), "Saved model round trips through JSON")
	for suffix: String in ["", ".bak"]:
		DirAccess.remove_absolute("user://sawblade_test.json" + suffix)
	preview.yaw = 2.5
	preview.pitch = 0.35
	preview.distance = 5.1
	preview._update_camera()
	for frame: int in 8: await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-sawblade.png"))
	preview.free()
	var profile := get_node("/root/PlayerProfile")
	profile.save_path = "user://sawblade_profile_test.json"
	profile.reload()
	profile.active_bot = 0
	var before: Dictionary = profile.loadouts[0].duplicate(true)
	profile.set_sawblade_color("paint_primary", Color.RED)
	check(profile.loadouts[0].cosmetics.sawblade.paint_primary != before.cosmetics.sawblade.paint_primary, "Custom palette edits the draft")
	profile.undo_edit()
	check(profile.loadouts[0] == before, "Undo restores all model properties")
	profile.redo_edit()
	check(profile.save_active("Painted sawblade") == OK, "Profile saves model appearance")
	profile.reload()
	check(profile.loadouts[3].cosmetics.sawblade.paint_primary[0] == 1, "Profile reload preserves custom paint")
	var screen: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	get_window().content_scale_size = Vector2i(1920, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	add_child(screen)
	screen._set_tab("decals")
	screen.apply_text_scale(1.5)
	for frame: int in 4: await get_tree().process_frame
	check(screen.get_node("Layout").size.x <= 1921, "Module controls fit logical width at 150%")
	check(screen.get_node("Layout/Footer").get_global_rect().end.y <= 1081, "Module footer fits at 150%")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-sawblade-garage.png"))
	screen.free()
	for suffix: String in ["", ".bak"]: DirAccess.remove_absolute(profile.save_path + suffix)
	if failures.is_empty(): print("SAWBLADE PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
