extends SceneTree
## Practice Duel HUD world panel (#97): Shift+Z toggles it (Z alone stays the
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
	await key(KEY_Z, true)
	check(not world_panel.visible and not preview.free_cursor, "Shift+Z does nothing outside a Practice Duel")
	game.start_practice("", "duel")
	await frames(30)
	var session: Node = game.session
	check(not world_panel.visible, "Practice starts with the world panel hidden")
	await key(KEY_Z, true)
	check(world_panel.visible and not tuning_panel.visible and preview.free_cursor,
		"Shift+Z shows the world panel, not the tuning panel, and frees the cursor")
	check(preview.cursor_panel == world_panel.card, "Clicks on the world card stay off the weapons")
	var card: Rect2 = world_panel.card.get_global_rect()
	check(card.size.x < 420 and card.end.x > 1800 and card.end.x <= 1920.5, "A narrow card on the right (%s)" % card)
	for button: BaseButton in [world_panel.clear_button, world_panel.spawn_button, world_panel.aggressive_toggle]:
		check(button.focus_mode == Control.FOCUS_NONE, "%s takes no keyboard focus" % button.name)
	await key(KEY_Z)
	check(tuning_panel.visible and not world_panel.visible, "Z swaps to the tuning panel")
	await key(KEY_Z, true)
	check(world_panel.visible and not tuning_panel.visible, "Shift+Z swaps back to the world panel")

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

	# Target panel: the NPC under the crosshair gets its own card.
	var target_panel: Control = game.practice_target_overlay
	if npc != null:
		var id := npc.entity_id
		check(session.practice_npc_at(npc.body.global_position + Vector3.UP * 4.0, Vector3.DOWN) == id, "A ray onto the NPC finds it")
		check(session.practice_npc_at(player.body.global_position + Vector3.UP * 4.0, Vector3.DOWN) == 0, "The player is never a target")
		game._practice_target = id
		await frames()
		check(target_panel.visible and target_panel.target == id, "Looking at an NPC shows its target card")
		var target_card: Rect2 = target_panel.card.get_global_rect()
		var world_card: Rect2 = world_panel.card.get_global_rect()
		check(target_card.end.x <= world_card.position.x and target_card.size.x < 420, "The target card sits left of the world card (%s, %s)" % [target_card, world_card])
		check(preview._over_cursor_panel(target_card.get_center()), "Clicks on the target card stay off the weapons")
		for slot: String in ["chassis", "drive", "weapon", "utility"]:
			check(target_panel.pickers.has(slot) and target_panel.pickers[slot].item_count > 0, "The target card has a %s picker" % slot)
		# Behaviour: this NPC only.
		target_panel.aggressive_toggle.button_pressed = true
		await frames()
		check(session.practice_npc_aggressive(id) and target_panel.aggressive_toggle.text == "Aggressive", "The target turns aggressive")
		target_panel.aggressive_toggle.button_pressed = false
		await frames()
		check(not session.practice_npc_aggressive(id) and target_panel.aggressive_toggle.text == "Friendly", "The target turns friendly")
		# Health and armour.
		target_panel.health_spin.value = 777.0
		await frames()
		npc = session.world.bots[id]
		check(is_equal_approx(npc.combat.core, 777.0), "Setting health sets the target's health (%s)" % npc.combat.core)
		var plates: Dictionary = npc.combat.stats.plates.duplicate()
		target_panel.armour_button.pressed.emit()
		await frames()
		npc = session.world.bots[id]
		for face: String in plates:
			check(is_equal_approx(float(npc.combat.stats.plates[face]), float(plates[face]) + target_panel.ARMOUR_STEP),
				"+armour adds to the %s face (%s -> %s)" % [face, plates[face], npc.combat.stats.plates[face]])
		# Parts, through the same options as the Z panel.
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
		target_panel.remove_button.pressed.emit()
		await frames()
		check(not session.world.bots.has(id) and not target_panel.visible, "Remove takes the target out of the world")

	await key(KEY_Z, true)
	check(not world_panel.visible and not tuning_panel.visible and not preview.free_cursor,
		"Shift+Z hides the world panel and recaptures the cursor")
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
