extends SceneTree
## Practice Duel HUD world panel (#97): F2 toggles it (F1 stays the
## tuning panel and the two never show together); its buttons clear the NPCs,
## spawn a passive NPC where the camera looks, and make the NPCs aggressive
## or not.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count := 4) -> void:
	for index: int in count:
		await physics_frame
		await process_frame

func key(code: Key, shift := false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		root.push_input(event)
	await frames()

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	var preview: Node3D = game.preview
	var world_panel: Control = game.practice_world_overlay
	var tuning_panel: Control = game.practice_tuning_overlay
	await key(KEY_F2)
	check(not world_panel.visible and not preview.free_cursor, "F2 does nothing outside a Practice Duel")
	game.start_practice("", "duel")
	await frames(30)
	var session: Node = game.session
	check(not world_panel.visible, "Practice starts with the world panel hidden")
	await key(KEY_F2)
	check(world_panel.visible and not tuning_panel.visible and preview.free_cursor,
		"F2 shows the world panel, not the tuning panel, and frees the cursor")
	check(preview.cursor_panel == world_panel.card, "Clicks on the world card stay off the weapons")
	var card: Rect2 = world_panel.card.get_global_rect()
	check(card.size.x < 420 and card.end.x > 1800 and card.end.x <= 1920.5, "A narrow card on the right (%s)" % card)
	for button: BaseButton in [world_panel.clear_button, world_panel.spawn_button, world_panel.aggressive_toggle]:
		check(button.focus_mode == Control.FOCUS_NONE, "%s takes no keyboard focus" % button.name)
	await key(KEY_F1)
	check(tuning_panel.visible and not world_panel.visible, "F1 swaps to the tuning panel")
	await key(KEY_F2)
	check(world_panel.visible and not tuning_panel.visible, "F2 swaps back to the world panel")

	# Clear: only the player is left.
	check(session.world.bots.size() > 1, "The duel starts with NPCs")
	world_panel.clear_button.pressed.emit()
	await frames()
	check(session.world.bots.size() == 1 and session.world.bots.has(session.local_entity),
		"Clear leaves only the player (%d bots)" % session.world.bots.size())
	check(world_panel.status.text == "0 NPCs", "The panel counts no NPCs (%s)" % world_panel.status.text)

	# Spawn where the camera looks: ahead of the camera, passive. Near-level,
	# so the ray meets the arena well away from the player.
	preview.rig.pitch = deg_to_rad(8.0)
	await frames()
	var camera: Camera3D = preview.aim_camera()
	var look := (-camera.global_basis.z).slide(Vector3.UP).normalized()
	world_panel.spawn_button.pressed.emit()
	await frames()
	check(session.world.bots.size() == 2, "Spawn adds one NPC")
	var npc: MvpBot = null
	for id: int in session.world.bots:
		if id != session.local_entity: npc = session.world.bots[id]
	var player: MvpBot = session.world.bots[session.local_entity]
	if npc != null:
		var offset: Vector3 = (npc.body.global_position - camera.global_position).slide(Vector3.UP)
		check(offset.normalized().dot(look) > 0.9, "The NPC spawns where the camera looks")
		check(npc.team != player.team, "The NPC is an opponent")
	check(not session.practice_npcs_aggressive() and not world_panel.aggressive_toggle.button_pressed and world_panel.aggressive_toggle.text == "Friendly",
		"NPCs start not aggressive")
	await frames(60)
	if npc != null:
		var home: Vector3 = npc.body.global_position
		var start := flat_distance(home, player.body.global_position)
		await frames(120)
		check(flat_distance(npc.body.global_position, home) < 0.5, "A passive NPC stays put")
		# Aggressive: it closes in on the player.
		world_panel.aggressive_toggle.button_pressed = true
		await frames()
		check(session.practice_npcs_aggressive() and world_panel.aggressive_toggle.text == "Aggressive", "The NPCs turn aggressive")
		await frames(240)
		check(flat_distance(npc.body.global_position, player.body.global_position) < start - 2.0,
			"An aggressive NPC hunts the player (%.1f -> %.1f m)" % [start, flat_distance(npc.body.global_position, player.body.global_position)])
	world_panel.aggressive_toggle.button_pressed = false
	await frames()
	check(not session.practice_npcs_aggressive() and world_panel.aggressive_toggle.text == "Friendly", "The NPCs calm down")

	# Hitboxes moved here from the F1 panel.
	world_panel.hitbox_toggle.button_pressed = true
	check(session.practice_tuning().debug_hitboxes, "The world panel's Hitboxes switch shows the other bots' hitboxes")
	world_panel.hitbox_toggle.button_pressed = false
	check(world_panel.aggressive_toggle.get_theme_color("font_color") == world_panel.FRIENDLY_COLOR, "Friendly reads green")

	# Target panel: the selected NPC gets its own card and a red outline.
	var target_panel: Control = game.practice_target_overlay
	if npc != null:
		var id := npc.entity_id
		check(session.practice_npc_at(npc.body.global_position + Vector3.UP * 4.0, Vector3.DOWN) == id, "A ray onto the NPC finds it")
		check(session.practice_npc_at(player.body.global_position + Vector3.UP * 4.0, Vector3.DOWN) == 0, "The player is never a target")
		# Clicking the NPC selects it; clicking it again clears the selection.
		# Off to one side first, clear of the player's own bot on screen.
		session.practice_director._place(npc, Transform3D(npc.body.global_basis, player.body.global_position + Vector3(12.0, 0.0, 0.0)))
		await frames(10)
		game._practice_target = 0
		# Its top, clear of the player's own bot in front of the camera.
		var on_screen: Vector2 = camera.unproject_position(npc.body.global_transform * (npc.collision_bounds().get_center() + Vector3.UP * npc.collision_bounds().size.y * 0.4))
		check(game._pick_practice_target(on_screen) and game._practice_target == id, "Clicking an NPC selects it")
		await frames()
		check(target_panel.visible and target_panel.target == id, "The selected NPC shows its target card")
		check(npc.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).size() > 0, "The target has a red outline")
		check(game._pick_practice_target(on_screen) and game._practice_target == 0, "Clicking the target again clears it")
		await frames()
		check(not target_panel.visible and npc.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).is_empty(),
			"Clearing the target hides its card and outline")
		check(not game._pick_practice_target(Vector2(5, 5)), "A click on no NPC stays a gameplay click")
		# The camera turns toward the selected NPC.
		game._practice_target = id
		await frames(40)
		var npc_at: Vector3 = session.world.bots[id].body.global_position
		var facing_dir: Vector3 = (-preview.rig.camera.global_basis.z).slide(Vector3.UP).normalized()
		var toward_npc: Vector3 = (npc_at - preview.rig.camera.global_position).slide(Vector3.UP).normalized()
		check(preview.rig.look_target is Vector3 and facing_dir.dot(toward_npc) > 0.95, "The camera turns toward the target (%.2f)" % facing_dir.dot(toward_npc))
		check(target_panel.remove_button.get_theme_font_size("font_size") == target_panel.ROW_FONT
			and target_panel.aggressive_toggle.get_theme_font_size("font_size") == target_panel.ROW_FONT, "The card's buttons match its dropdown rows' size")
		# Clicking the player's own bot selects it: green outline and the F1 card
		# beside the world card instead of the target card.
		var own: MvpBot = session.world.bots[session.local_entity]
		game._practice_target = 0
		await frames()
		var own_at: Vector2 = preview.rig.camera.unproject_position(own.body.global_position + Vector3.UP * 0.3)
		check(game._pick_practice_target(own_at) and game._practice_target == session.local_entity, "Clicking the player's bot selects it")
		await frames()
		var tuning_card: Rect2 = tuning_panel.card.get_global_rect()
		check(tuning_panel.visible and not target_panel.visible and tuning_card.end.x <= world_panel.card.get_global_rect().position.x + 0.5,
			"The F1 card shows left of the world card (%s)" % tuning_card)
		check(preview._over_cursor_panel(tuning_card.get_center()), "Clicks on the docked F1 card stay off the weapons")
		check(own.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).size() > 0
			and game.practice_target_outline._rim.get_shader_parameter("outline_color") == game.practice_target_outline.PLAYER_COLOR,
			"The player's bot has a green outline")
		check(preview.rig.look_target == null, "The camera does not turn toward the player's own bot")
		check(game._pick_practice_target(own_at) and game._practice_target == 0, "Clicking the player's bot again clears it")
		await frames()
		check(not tuning_panel.visible and own.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).is_empty(),
			"Clearing it hides the F1 card and the outline")
		await key(KEY_F1)
		tuning_card = tuning_panel.card.get_global_rect()
		check(tuning_panel.visible and not world_panel.visible and tuning_card.end.x > 1800, "F1 still shows its card at the right edge (%s)" % tuning_card)
		await key(KEY_F2)
		game._practice_target = id
		await frames()
		game._practice_target = id
		await frames()
		check(target_panel.title.text.begins_with("Name: "), "The target's name reads Name: (%s)" % target_panel.title.text)
		var target_card: Rect2 = target_panel.card.get_global_rect()
		var world_card: Rect2 = world_panel.card.get_global_rect()
		check(target_card.end.x <= world_card.position.x and absf(target_card.size.x - world_card.size.x) < 1.0, "The target card sits left of the world card (%s, %s)" % [target_card, world_card])
		check(preview._over_cursor_panel(target_card.get_center()), "Clicks on the target card stay off the weapons")
		for slot: String in ["chassis", "drive", "weapon", "utility"]:
			var picker: OptionButton = target_panel.pickers.get(slot)
			check(picker != null and picker.item_count > 0 and picker.get_parent() is HBoxContainer and picker.get_index() == 1,
				"The target card has a %s picker right of its caption" % slot)
		# Behaviour: this NPC only, red when aggressive.
		target_panel.aggressive_toggle.button_pressed = true
		await frames()
		check(session.practice_npc_aggressive(id) and target_panel.aggressive_toggle.text == "Aggressive"
			and target_panel.aggressive_toggle.get_theme_color("font_color") == world_panel.AGGRESSIVE_COLOR, "The target turns aggressive, in red")
		target_panel.aggressive_toggle.button_pressed = false
		await frames()
		check(not session.practice_npc_aggressive(id) and target_panel.aggressive_toggle.text == "Friendly", "The target turns friendly")
		# Its hitboxes alone.
		target_panel.hitbox_toggle.button_pressed = true
		await frames()
		check(preview.practice_hitbox_overrides.get(id) == true and preview.practice_debug._hitboxes.size() == 1, "The target's Hitboxes switch draws only the target's")
		await key(KEY_F2)
		check(not target_panel.visible and preview.practice_debug._hitboxes.size() == 1, "Its hitboxes stay on with the panels closed")
		await key(KEY_F2)
		game._practice_target = id
		await frames()
		check(target_panel.hitbox_toggle.button_pressed, "Reselected, its switch still reads on")
		# The world switch sets every NPC to its value, the target included.
		world_panel.hitbox_toggle.button_pressed = true
		await frames()
		check(preview.practice_hitbox_overrides.is_empty() and target_panel.hitbox_toggle.button_pressed, "World Hitboxes on leaves the target's on")
		target_panel.hitbox_toggle.button_pressed = false
		await frames()
		check(world_panel.hitbox_toggle.button_pressed and not target_panel.hitbox_toggle.button_pressed
			and preview.practice_debug._hitboxes.size() == session.world.bots.size() - 2, "A target can hide its own under world Hitboxes, the world switch stays on")
		world_panel.hitbox_toggle.button_pressed = false
		await frames()
		check(preview.practice_hitbox_overrides.is_empty() and not target_panel.hitbox_toggle.button_pressed
			and preview.practice_debug._hitboxes.is_empty(), "World Hitboxes off turns every NPC's off")
		# The world behaviour switch keeps its own setting and sets every NPC to it.
		world_panel.aggressive_toggle.button_pressed = true
		await frames()
		check(session.practice_npc_aggressive(id) and target_panel.aggressive_toggle.button_pressed, "World Aggressive makes the target aggressive")
		target_panel.aggressive_toggle.button_pressed = false
		await frames()
		check(not session.practice_npc_aggressive(id) and world_panel.aggressive_toggle.button_pressed
			and world_panel.aggressive_toggle.text == "Aggressive", "A friendly target leaves the world switch on Aggressive")
		world_panel.aggressive_toggle.button_pressed = false
		await frames()
		check(not session.practice_npc_aggressive(id) and not world_panel.aggressive_toggle.button_pressed, "World Friendly makes every NPC friendly")
		# Health -/+ and armour.
		var health: float = session.world.bots[id].combat.core
		target_panel.health_up.pressed.emit()
		await frames()
		check(is_equal_approx(session.world.bots[id].combat.core, health + target_panel.HEALTH_STEP), "+100 adds health (%s -> %s)" % [health, session.world.bots[id].combat.core])
		target_panel.health_down.pressed.emit()
		await frames()
		check(is_equal_approx(session.world.bots[id].combat.core, health), "-100 takes it again")
		npc = session.world.bots[id]
		var plates: Dictionary = npc.combat.stats.plates.duplicate()
		target_panel.armour_up.pressed.emit()
		await frames()
		npc = session.world.bots[id]
		for face: String in plates:
			check(is_equal_approx(float(npc.combat.stats.plates[face]), float(plates[face]) + target_panel.ARMOUR_STEP),
				"+armour adds to the %s face (%s -> %s)" % [face, plates[face], npc.combat.stats.plates[face]])
		# A spawn where an NPC already stands lands on top of it.
		target_panel.armour_down.pressed.emit()
		await frames()
		npc = session.world.bots[id]
		for face: String in plates:
			check(is_equal_approx(float(npc.combat.stats.plates[face]), float(plates[face])), "-armour takes it again from the %s face" % face)
		var stacked: int = session.practice_spawn_npc(npc.body.global_position + Vector3.UP * 6.0, Vector3.DOWN)
		var above: MvpBot = session.world.bots.get(stacked)
		check(above != null and above.body.reset_pose is Transform3D and above.body.reset_pose.origin.y > npc.body.global_position.y + 0.5,
			"A spawn onto an NPC starts above it")
		if above != null: session.practice_remove_npc(stacked)
		# Parts, through the same options as the F1 panel.
		for slot: String in ["chassis", "weapon"]:
			var picker: OptionButton = target_panel.pickers[slot]
			var before: String = session.world.bots[id].loadout.parts[slot]
			var choice := -1
			for index: int in picker.item_count:
				if index != picker.selected and not picker.is_item_disabled(index):
					choice = index
					break
			picker.item_selected.emit(choice)
			await frames(6)
			check(choice >= 0 and session.world.bots[id].loadout.parts[slot] != before,
				"Choosing a %s fits it to the target (%s -> %s)" % [slot, before, session.world.bots[id].loadout.parts[slot]])
		check(target_panel.visible and target_panel.target == id, "The target survives a part swap")
		check(session.world.bots[id].find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).size() > 0, "The outline follows the swapped bot")
		# The outline never becomes wreck pieces, and a wreck has none.
		var outlined: MvpBot = session.world.bots[id]
		var captured: Array = preload("res://scripts/presentation/wreck_pieces.gd").capture(outlined, outlined.body.global_transform)
		check(captured.all(func(entry: Dictionary) -> bool: return not str(entry.source.name).begins_with("PracticeTargetOutline")),
			"Wreck pieces skip the outline")
		outlined.combat.eliminated = true
		await frames()
		check(outlined.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).is_empty(), "A wrecked target loses its outline")
		outlined.combat.eliminated = false
		await frames()
		check(outlined.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).size() > 0, "The outline returns with the NPC")
		target_panel.remove_button.pressed.emit()
		await frames()
		check(not session.world.bots.has(id) and not target_panel.visible, "Remove takes the target out of the world")

	await key(KEY_F2)
	check(not world_panel.visible and not tuning_panel.visible and not preview.free_cursor,
		"F2 hides the world panel and recaptures the cursor")
	# Escape closes the F1/F2 panels first; only then does it open the pause menu.
	await key(KEY_F2)
	check(world_panel.visible, "F2 opens the world panel again")
	await key(KEY_ESCAPE)
	check(not world_panel.visible and not preview.pause_menu.visible and preview.controls_enabled and not preview.free_cursor,
		"Escape closes the world panel without the pause menu")
	await key(KEY_F1)
	check(tuning_panel.visible, "F1 opens the tuning panel")
	await key(KEY_ESCAPE)
	check(not tuning_panel.visible and not preview.pause_menu.visible and preview.controls_enabled, "Escape closes the tuning panel without the pause menu")
	await key(KEY_ESCAPE)
	check(preview.pause_menu.visible and not preview.controls_enabled, "Escape with no panel open shows the pause menu")
	game.resume_gameplay()
	await frames()
	check(not world_panel.visible and not tuning_panel.visible and preview.controls_enabled, "Resuming does not bring a closed panel back")
	game.return_to_main()
	await frames()
	check(not world_panel.visible and not game._practice_world_open, "Leaving practice closes the world panel")
	game.queue_free()
	await frames()
	if failures.is_empty():
		print("PRACTICE_WORLD_OVERLAY_TEST_PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		print("PRACTICE_WORLD_OVERLAY_TEST_FAIL")
		quit(1)
