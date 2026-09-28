extends SceneTree
## Practice Duel HUD world panel (#97): F1 toggles it (F2 stays the
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
	await key(KEY_F1)
	check(not world_panel.visible and not preview.free_cursor, "F1 does nothing outside a Practice Duel")
	game.start_practice("", "duel")
	await frames(30)
	var session: Node = game.session
	check(not world_panel.visible, "Practice starts with the world panel hidden")
	await key(KEY_F1)
	check(world_panel.visible and not tuning_panel.visible and preview.free_cursor,
		"F1 shows the world panel, not the tuning panel, and frees the cursor")
	check(preview.cursor_panel == world_panel.card, "Clicks on the world card stay off the weapons")
	var card: Rect2 = world_panel.card.get_global_rect()
	check(card.size.x < 420 and card.end.x > 1800 and card.end.x <= 1920.5, "A narrow card on the right (%s)" % card)
	for button: BaseButton in [world_panel.clear_button, world_panel.spawn_button, world_panel.aggressive_toggle]:
		check(button.focus_mode == Control.FOCUS_NONE, "%s takes no keyboard focus" % button.name)
	await key(KEY_F2)
	check(tuning_panel.visible and not world_panel.visible, "F2 swaps to the tuning panel")
	await key(KEY_F1)
	check(world_panel.visible and not tuning_panel.visible, "F1 swaps back to the world panel")

	# Clear: only the player is left.
	check(session.world.bots.size() > 1, "The duel starts with NPCs")
	world_panel.clear_button.pressed.emit()
	await frames()
	check(session.world.bots.size() == 1 and session.world.bots.has(session.local_entity),
		"Clear leaves only the player (%d bots)" % session.world.bots.size())
	check(world_panel.status.text.begins_with("0 NPCs, "), "The panel counts no NPCs (%s)" % world_panel.status.text)

	# Items (#105): Clear items empties the arena, Spawn item places one where
	# the camera looks, and clicking it opens the item card.
	world_panel.item_clear_button.pressed.emit()
	await frames()
	check(session.world.pickups.items.is_empty() and world_panel.status.text == "0 NPCs, 0 items",
		"Clear items removes every item pickup (%s)" % world_panel.status.text)
	preview.rig.pitch = deg_to_rad(8.0)
	await frames()
	var item_camera: Camera3D = preview.aim_camera()
	var item_look := (-item_camera.global_basis.z).slide(Vector3.UP).normalized()
	world_panel.item_spawn_button.pressed.emit()
	await frames()
	check(session.world.pickups.items.size() == 1 and world_panel.status.text == "0 NPCs, 1 item", "Spawn item adds one item (%s)" % world_panel.status.text)
	var item_panel: Control = game.practice_item_overlay
	if session.world.pickups.items.size() == 1:
		var spawned: Dictionary = session.world.pickups.items[0]
		var item_id: int = spawned.id
		var item_offset: Vector3 = (spawned.point - item_camera.global_position).slide(Vector3.UP)
		check(item_offset.normalized().dot(item_look) > 0.9 and item_offset.length() > 2.0, "The item spawns where the camera looks")
		await frames(10)
		check(session.world.pickups.find(item_id).get("available", false), "The spawned item waits to be picked up")
		check(not item_panel.visible, "No item card before a click")
		check(session.practice_pickup_at(spawned.point + Vector3(0.5, 300.0, 0.0), Vector3.DOWN) == item_id, "An item is picked from across the map (300 m)")
		var item_screen: Vector2 = preview.aim_camera().unproject_position(spawned.point + Vector3.UP * 2.6)
		var pick_camera: Camera3D = preview.aim_camera()
		check(game._pick_practice_target(item_screen) and game._practice_item == item_id and game._practice_target == 0,
			"Clicking an item selects it (arena %s, item %s, screen %s, ray finds %d)" % [session.arena_id, spawned.point, item_screen,
			session.practice_pickup_at(pick_camera.project_ray_origin(item_screen), pick_camera.project_ray_normal(item_screen))])
		await frames()
		check(item_panel.visible and item_panel.item_id == item_id and not game.practice_target_overlay.visible, "The selected item shows its item card")
		var item_card: Rect2 = item_panel.card.get_global_rect()
		check(item_card.end.x <= world_panel.card.get_global_rect().position.x and preview._over_cursor_panel(item_card.get_center()),
			"The item card sits left of the world card and keeps clicks off the weapons")
		check(item_panel.remove_button.get_theme_stylebox("normal").bg_color == game.practice_target_overlay.REMOVE_COLOR, "Remove is red")
		check(item_panel.picker.item_count == session.practice_pickup_choices().size() and item_panel.picker.item_count > 4,
			"The dropdown lists every item (%d)" % item_panel.picker.item_count)
		check(item_panel.picker.get_popup().get_theme_font_size("font_size") < item_panel.picker.get_theme_font_size("font_size"),
			"The dropdown's list is in smaller text than the card")
		# The selected item gets a yellow outline round the item, not its cage
		# (the markers are not built headless, so on a stand-in token).
		var outline: Node = game.practice_item_outline
		var token := Node3D.new()
		for mesh_name: String in ["Core", "Frame"]:
			var part := MeshInstance3D.new()
			part.name = mesh_name
			part.mesh = BoxMesh.new()
			token.add_child(part)
		root.add_child(token)
		outline.show_on(token)
		check(outline._rim.get_shader_parameter("outline_color") == outline.ITEM_COLOR
			and token.get_node("Core").find_children("PracticeItemOutline*", "MeshInstance3D", false, false).size() == 2
			and token.get_node("Frame").get_child_count() == 0, "The item outline is yellow and skips the cage")
		outline.show_on(null)
		token.queue_free()
		# Choose credits, then a part: the item changes and keeps it.
		for choice_index: int in [1, item_panel.picker.item_count - 1]:
			var choice: Dictionary = session.practice_pickup_choices()[choice_index]
			item_panel.picker.item_selected.emit(choice_index)
			await frames()
			var now_item: Dictionary = session.world.pickups.find(item_id)
			check(now_item.kind == choice.kind and now_item.part == choice.part and now_item.amount == choice.amount
				and item_panel.picker.selected == choice_index, "Choosing %s makes the item one (%s)" % [choice, now_item])
			check(session.pickup_view.items.any(func(view: Dictionary) -> bool: return view.id == item_id and view.kind == choice.kind and view.part == choice.part),
				"The chosen item is published to the pickup visuals")
		var chosen: Dictionary = session.world.pickups.find(item_id).duplicate()
		session.world.pickups.find(item_id).available = false
		session.world.pickups.find(item_id).respawn = 0.0
		await frames()
		var respawned: Dictionary = session.world.pickups.find(item_id)
		check(respawned.available and respawned.kind == chosen.kind and respawned.part == chosen.part, "A chosen item respawns as the same item")
		# Clicking it again clears the selection; clicking an NPC swaps to it.
		item_screen = preview.aim_camera().unproject_position(spawned.point + Vector3.UP * 2.6)
		game._practice_item = item_id
		await frames()
		check(game._pick_practice_target(item_screen) and game._practice_item == -1, "Clicking the item again clears it")
		await frames()
		check(not item_panel.visible, "Clearing the item hides its card")
		game._practice_item = item_id
		await frames()
		item_panel.remove_button.pressed.emit()
		await frames()
		check(session.world.pickups.find(item_id).is_empty() and not item_panel.visible and game._practice_item == -1, "Remove takes the item out of the world")
	session.practice_spawn_pickup(item_camera.global_position, -item_camera.global_basis.z)
	session.practice_spawn_pickup(item_camera.global_position, -item_camera.global_basis.z)
	await frames()
	check(session.world.pickups.items.size() == 2 and session.world.pickups.items[0].id != session.world.pickups.items[1].id, "Each spawned item has its own id")
	world_panel.item_clear_button.pressed.emit()
	await frames()
	check(session.world.pickups.items.is_empty(), "Clear items takes every spawned item")

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

	# Hitboxes moved here from the F2 panel.
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
		check(session.practice_npc_at(npc.body.global_position + Vector3.UP * 300.0, Vector3.DOWN) == id, "An NPC is picked from across the map (300 m)")
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
		# The camera has turned toward it since; click where it shows now.
		on_screen = camera.unproject_position(npc.body.global_transform * (npc.collision_bounds().get_center() + Vector3.UP * npc.collision_bounds().size.y * 0.4))
		check(game._pick_practice_target(on_screen) and game._practice_target == 0, "Clicking the target again clears it")
		await frames()
		check(not target_panel.visible and npc.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).is_empty(),
			"Clearing the target hides its card and outline")
		check(not game._pick_practice_target(Vector2(5, 5)), "A click on no NPC stays a gameplay click")
		# A click on an NPC with the tuning panel up switches to the world panel
		# with it selected.
		game._practice_target = 0
		await key(KEY_F2)
		check(tuning_panel.visible and not world_panel.visible, "F2 shows the tuning panel")
		var from_tuning: Vector2 = preview.aim_camera().unproject_position(session.world.bots[id].body.global_transform
			* (session.world.bots[id].collision_bounds().get_center() + Vector3.UP * session.world.bots[id].collision_bounds().size.y * 0.4))
		check(game._pick_practice_target(from_tuning), "A click on an NPC is taken with the tuning panel up")
		await frames()
		check(not tuning_panel.visible and world_panel.visible and target_panel.visible and game._practice_target == id,
			"It closes the tuning panel and opens the world and target panels")
		# The camera turns toward the selected NPC.
		game._practice_target = id
		await frames(40)
		var npc_at: Vector3 = session.world.bots[id].body.global_position
		var facing_dir: Vector3 = (-preview.rig.camera.global_basis.z).slide(Vector3.UP).normalized()
		var toward_npc: Vector3 = (npc_at - preview.rig.camera.global_position).slide(Vector3.UP).normalized()
		check(preview.rig.look_target is Vector3 and facing_dir.dot(toward_npc) > 0.95, "The camera turns toward the target (%.2f)" % facing_dir.dot(toward_npc))
		check(target_panel.remove_button.get_theme_font_size("font_size") == target_panel.ROW_FONT
			and target_panel.aggressive_toggle.get_theme_font_size("font_size") == target_panel.ROW_FONT, "The card's buttons match its dropdown rows' size")
		# The player's own bot can never be selected.
		var own: MvpBot = session.world.bots[session.local_entity]
		game._practice_target = 0
		await frames()
		var own_at: Vector2 = preview.rig.camera.unproject_position(own.body.global_position + Vector3.UP * 0.3)
		check(not game._pick_practice_target(own_at) and game._practice_target == 0, "Clicking the player's bot selects nothing")
		# Looking at an NPC selects nothing; only a click does.
		var look_cam: Camera3D = preview.aim_camera()
		var looked_at: Vector3 = session.world.bots[id].body.global_position
		preview.rig.yaw = atan2(-(looked_at - look_cam.global_position).x, -(looked_at - look_cam.global_position).z)
		await frames(5)
		check(game._practice_target == 0 and not target_panel.visible, "Looking at an NPC does not select it")
		# Player options, green and on top of the world card, switches to the F2 panel.
		check(world_panel.player_options_button.get_index() < world_panel.spawn_button.get_index()
			and world_panel.player_options_button.get_theme_stylebox("normal").bg_color == world_panel.PLAYER_OPTIONS_COLOR,
			"A green Player options button tops the world card")
		world_panel.player_options_button.pressed.emit()
		await frames()
		check(tuning_panel.visible and not world_panel.visible and preview.free_cursor, "Player options opens the F2 panel")
		await key(KEY_F1)
		check(world_panel.visible and not tuning_panel.visible, "F1 comes back from it")
		# Tabbing out keeps the panels up; focus back, driving resumes.
		preview._on_focus_lost()
		await frames()
		check(world_panel.visible and not preview.pause_menu.visible, "Losing window focus keeps the world panel up")
		preview._on_focus_regained()
		await frames()
		check(world_panel.visible and preview.controls_enabled, "Focus back, the panel is still up and driving resumes")
		# The world card drags by its background, and stays on screen.
		var before_drag: Rect2 = world_panel.card.get_global_rect()
		var grab := before_drag.position + Vector2(before_drag.size.x * 0.5, 12.0)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = grab
		press.global_position = grab
		world_panel.drag._on_card_input(press)
		var motion_drag := InputEventMouseMotion.new()
		motion_drag.position = grab + Vector2(-200.0, 150.0)
		motion_drag.global_position = grab + Vector2(-200.0, 150.0)
		world_panel.drag._on_card_input(motion_drag)
		press.pressed = false
		world_panel.drag._on_card_input(press)
		await frames()
		var after_drag: Rect2 = world_panel.card.get_global_rect()
		check(after_drag.position.distance_to(before_drag.position + Vector2(-200.0, 150.0)) < 2.0, "Dragging moves the world card (%s -> %s)" % [before_drag, after_drag])
		world_panel.drag.offset = Vector2(5000.0, 5000.0)
		world_panel._resize()
		await frames()
		after_drag = world_panel.card.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(after_drag), "A dragged card stays on screen (%s)" % after_drag)
		world_panel.drag.offset = Vector2.ZERO
		world_panel._resize()
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
		await key(KEY_F1)
		check(not target_panel.visible and preview.practice_debug._hitboxes.size() == 1, "Its hitboxes stay on with the panels closed")
		await key(KEY_F1)
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
		check(is_equal_approx(session.world.bots[id].combat.core, health + target_panel.STEP), "+100 adds health (%s -> %s)" % [health, session.world.bots[id].combat.core])
		target_panel.health_down.pressed.emit()
		await frames()
		check(is_equal_approx(session.world.bots[id].combat.core, health), "-100 takes it again")
		npc = session.world.bots[id]
		var plates: Dictionary = npc.combat.stats.plates.duplicate()
		target_panel.armour_up.pressed.emit()
		await frames()
		npc = session.world.bots[id]
		for face: String in plates:
			check(is_equal_approx(float(npc.combat.stats.plates[face]), float(plates[face]) + target_panel.STEP),
				"+armour adds to the %s face (%s -> %s)" % [face, plates[face], npc.combat.stats.plates[face]])
		# A spawn where an NPC already stands lands on top of it.
		target_panel.armour_down.pressed.emit()
		await frames()
		npc = session.world.bots[id]
		for face: String in plates:
			check(is_equal_approx(float(npc.combat.stats.plates[face]), float(plates[face])), "-armour takes it again from the %s face" % face)
		# Under a line and a "+/- 100 Durability" caption: -HP +HP -A +A, then -W +W -D +D.
		var body_row: Control = target_panel.health_down.get_parent()
		var parts_row: Control = target_panel.weapon_down.get_parent()
		var rows: Node = body_row.get_parent()
		check(body_row.get_children() == [target_panel.health_down, target_panel.health_up, target_panel.armour_down, target_panel.armour_up]
			and parts_row.get_children() == [target_panel.weapon_down, target_panel.weapon_up, target_panel.drive_down, target_panel.drive_up]
			and parts_row.get_index() == body_row.get_index() + 1
			and rows.get_child(body_row.get_index() - 1) is Label and (rows.get_child(body_row.get_index() - 1) as Label).text == "+/- 100 Durability"
			and rows.get_child(body_row.get_index() - 2) is HSeparator, "The durability buttons sit in two rows under a line and their caption")
		var zones: Dictionary = session.world.bots[id].combat.zones.duplicate()
		target_panel.weapon_up.pressed.emit()
		target_panel.drive_down.pressed.emit()
		await frames()
		var now: Dictionary = session.world.bots[id].combat.zones
		check(is_equal_approx(now.weapon, zones.weapon + target_panel.STEP)
			and is_equal_approx(now.drive_left, maxf(0.0, zones.drive_left - target_panel.STEP))
			and is_equal_approx(now.drive_right, maxf(0.0, zones.drive_right - target_panel.STEP)),
			"+W adds weapon durability and -D takes both drives' (%s -> %s)" % [zones, now])
		target_panel.weapon_down.pressed.emit()
		target_panel.drive_up.pressed.emit()
		await frames()
		now = session.world.bots[id].combat.zones
		check(is_equal_approx(now.weapon, zones.weapon) and now.drive_left > 0.0 and now.drive_right > 0.0, "-W and +D give them back")
		target_panel.weapon_down.pressed.emit()
		target_panel.drive_down.pressed.emit()
		await frames()
		session.world.bots[id].reset_round()
		await frames()
		now = session.world.bots[id].combat.zones
		check(is_equal_approx(now.weapon, zones.weapon) and is_equal_approx(now.drive_left, zones.drive_left)
			and is_equal_approx(now.drive_right, zones.drive_right), "A respawn restores weapon and drives (%s)" % now)
		check(target_panel.health_down.text == "-HP" and target_panel.weapon_down.text == "-W" and target_panel.drive_up.text == "+D", "They read -HP, -W, +D")
		var stacked: int = session.practice_spawn_npc(npc.body.global_position + Vector3.UP * 6.0, Vector3.DOWN)
		var above: MvpBot = session.world.bots.get(stacked)
		check(above != null and above.body.reset_pose is Transform3D and above.body.reset_pose.origin.y > npc.body.global_position.y + 0.5,
			"A spawn onto an NPC starts above it")
		if above != null: session.practice_remove_npc(stacked)
		# Parts, through the same options as the F2 panel.
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
		# A part that breaks off (flying under a top_level root on the bot, as
		# bot_part_loss does) is not outlined; the bot still is.
		var lost_root := Node3D.new()
		lost_root.top_level = true
		outlined.add_child(lost_root)
		var lost_part := MeshInstance3D.new()
		lost_part.mesh = BoxMesh.new()
		lost_root.add_child(lost_part)
		await frames()
		check(lost_part.get_children().is_empty() and outlined.find_children("PracticeTargetOutline*", "MeshInstance3D", true, false).size() > 0,
			"A broken-off part is not outlined")
		lost_root.queue_free()
		await frames()
		target_panel.remove_button.pressed.emit()
		await frames()
		check(not session.world.bots.has(id) and not target_panel.visible, "Remove takes the target out of the world")
		# Possess: the player takes over an NPC; its old body becomes a friendly NPC.
		var cam_now: Camera3D = preview.aim_camera()
		var fresh_id: int = session.practice_spawn_npc(cam_now.global_position, -cam_now.global_basis.z)
		await frames(10)
		var old_player: int = session.local_entity
		game._practice_target = fresh_id
		await frames()
		check(target_panel.possess_button.get_index() < target_panel.remove_button.get_index() and target_panel.possess_button.text == "Possess",
			"Possess tops the target card's options")
		check(target_panel.possess_button.get_theme_stylebox("normal").bg_color == target_panel.POSSESS_COLOR
			and target_panel.remove_button.get_theme_stylebox("normal").bg_color == target_panel.REMOVE_COLOR, "Possess is green and Remove red")
		check(target_panel.hitbox_toggle.text == "Hitbox" and target_panel.armour_down.text == "-A" and target_panel.armour_up.text == "+A",
			"The target card reads Hitbox, -A and +A")
		target_panel.possess_button.pressed.emit()
		await frames(4)
		check(session.local_entity == fresh_id and session.practice_npc(old_player) != null and session.practice_npc(fresh_id) == null,
			"Possess makes the target the player's bot and the old body an NPC")
		check(session.world.bots[fresh_id].team == 0 and session.world.bots[old_player].team == 1 and not session.practice_npc_aggressive(old_player),
			"The two swap sides; the old body is friendly")
		check(game._practice_target == 0 and not target_panel.visible and preview.source.read_view().entity_id == fresh_id,
			"The selection clears and the view follows the new bot")
		# The player's commands now reach it: its command sequence follows the
		# local client's, far past the few the director gave it.
		var possessed_at: int = session._client_sequence
		await frames(10)
		check(session.world.bots[fresh_id].last_sequence >= possessed_at, "The player's commands drive the possessed bot")

	await key(KEY_F1)
	check(not world_panel.visible and not tuning_panel.visible and not preview.free_cursor,
		"F1 hides the world panel and recaptures the cursor")
	# Escape closes the F1/F2 panels first; only then does it open the pause menu.
	await key(KEY_F1)
	check(world_panel.visible, "F1 opens the world panel again")
	await key(KEY_ESCAPE)
	check(not world_panel.visible and not preview.pause_menu.visible and preview.controls_enabled and not preview.free_cursor,
		"Escape closes the world panel without the pause menu")
	await key(KEY_F2)
	check(tuning_panel.visible, "F2 opens the tuning panel")
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
	# Full Practice has the same panels (#99).
	game.start_practice()
	await frames(30)
	check(session.practice_kind == "full" and preview.controls_enabled, "Full practice starts")
	await key(KEY_F1)
	check(world_panel.visible and not tuning_panel.visible and preview.free_cursor, "F1 shows the world panel in full practice")
	await key(KEY_F2)
	check(tuning_panel.visible and not world_panel.visible, "F2 shows the tuning panel in full practice")
	await key(KEY_F2)
	check(not tuning_panel.visible and not preview.free_cursor, "F2 hides it again in full practice")
	await key(KEY_ESCAPE)
	check(preview.pause_menu.visible and not game.game_menu_page.tuning_panel.visible,
		"The full practice Esc menu keeps its summary, without the tuning copy")
	game.resume_gameplay()
	await frames()
	game.return_to_main()
	await frames()
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
