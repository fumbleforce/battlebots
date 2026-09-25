extends SceneTree
## Practice Duel tuning (#84): live, session-only overrides change real
## server-authoritative combat for the player and nobody else.
var failures: Array[String] = []
var events: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame

## Holds the trigger for `ticks` frames and returns the player's minigun hits on the target.
func fire(session: MvpSession, target: MvpBot, ticks: int) -> Array[Dictionary]:
	# Fixture: a bottomless core, so the burst never kills the target.
	target.combat.stats.core = 1000000.0
	target.combat.core = 1000000.0
	events.clear()
	for tick: int in ticks:
		var command := BotCommand.new()
		command.brake = true
		command.primary_held = true
		command.primary_pressed = tick == 0
		session.submit_local(command)
		await frames(1)
	var hits: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.attacker == session.local_entity and event.target == target.entity_id and event.kind == "minigun":
			hits.append(event)
	return hits

func run() -> void:
	var session := MvpSession.new()
	session.pickups_enabled = false
	root.add_child(session)
	session.combat_event.connect(func(event: Dictionary) -> void: events.append(event))
	var build := session.registry.starter()
	build.parts.drive = "traction"
	build.parts.weapon = "minigun"
	check(session.practice(build, "foundry", "duel") == OK, "Duel practice starts with a minigun build")
	var lab: RefCounted = session.practice_tuning()
	check(lab != null, "Practice Duel exposes the player's tuning")
	await frames(3)
	var player: MvpBot = session.local_source()
	var target := session.practice_target() as MvpBot
	check(player.combat.practice_tuning == lab and target.combat.practice_tuning == null, "Only the player's bot is tuned")
	check(lab.value("primary", "damage") == CombatWorld.MINIGUN_DAMAGE and lab.value("primary", "range") == CombatWorld.MINIGUN_RANGE,
		"Defaults are the minigun's real values")
	# #89: Stagger is a strength in percent; the duration stays the weapon's.
	var minigun_stagger: Array = CombatWorld.STAGGER.minigun
	check(is_equal_approx(lab.value("primary", "stagger"), minigun_stagger[1] * 100.0), "Stagger defaults to the minigun's strength in percent")
	lab.set_value("primary", "stagger", 1000.0)
	check(lab.stagger("primary", minigun_stagger) == [minigun_stagger[0], 1.0], "Stagger strength caps at 100% and keeps the weapon's duration")
	lab.set_value("primary", "stagger", 0.0)
	check(lab.stagger("primary", minigun_stagger).is_empty(), "Stagger 0% turns stagger off")
	lab.clear_value("primary", "stagger")
	check(is_equal_approx(lab.total_mass(), float(player.combat.stats.mass)), "Body plus weapon weight is the bot's mass")
	# The Esc-menu panel lists the weapon and body and writes straight into the tuning.
	var panel: VBoxContainer = preload("res://scripts/ui/practice_tuning_panel.gd").new()
	root.add_child(panel)
	panel.render(lab, session)
	var texts: Array[String] = []
	for label: Node in panel.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	check("TUNING" in texts and "BODY" in texts and "ARMOUR" in texts, "Panel shows the Tuning title and the Weapon, Body and Armour sections")
	var heading := func(text: String) -> Node:
		return panel.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text == text)[0]
	var body_column: Node = heading.call("BODY").get_parent()
	var weapon_column: Node = heading.call("WEAPON 1").get_parent()
	check(body_column != weapon_column and body_column.get_parent() == weapon_column.get_parent()
		and body_column.get_index() < weapon_column.get_index(), "Body is the left column and Weapon the right")
	check(texts.has("Fire rate (/s)") and texts.has("Max speed (km/h)") and texts.has("Health"), "Panel lists weapon and body values")
	var spins := panel.find_children("*", "SpinBox", true, false)
	# The damage row: its label, then its box, then its DEFAULT button.
	var damage_label: Node = heading.call("Damage")
	var damage_spin: SpinBox = damage_label.get_parent().get_child(damage_label.get_index() + 1)
	var damage_default: Button = damage_label.get_parent().get_child(damage_label.get_index() + 2)
	check(spins.size() >= 10, "Panel has an editor per value (%d)" % spins.size())
	damage_spin.value = 9.0
	check(lab.value("primary", "damage") == 9.0, "Editing the damage box tunes the weapon")
	var defaults := panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "DEFAULT")
	check(defaults.size() == spins.size(), "Every editable value has a DEFAULT button")
	damage_default.pressed.emit()
	check(lab.scale("primary", "damage") == 1.0 and is_equal_approx(damage_spin.value, CombatWorld.MINIGUN_DAMAGE),
		"DEFAULT restores that value and shows it")
	damage_spin.value = 9.0
	panel.heat_toggle.button_pressed = false
	check(not lab.heat_enabled, "The heat toggle switches heat off")
	check(panel.heat_toggle.text == "Heat" and panel.heat_toggle.get_index() < heading.call("ARMOUR").get_index()
		and heading.call("ARMOUR").get_index() < heading.call("MOVEMENT").get_index()
		and heading.call("MOVEMENT").get_index() < panel.jump_toggle.get_index() and heading.call("MOVEMENT").get_parent() == body_column,
		"Heat sits under Body; Movement follows Armour and holds the jump cooldown toggle")
	check(texts.has("Jump force (m/s)") and texts.has("Acceleration (m/s²)"), "Movement lists speed, acceleration and jump force")
	var speed_label: Node = heading.call("Max speed (km/h)")
	var speed_spin: SpinBox = speed_label.get_parent().get_child(speed_label.get_index() + 1)
	check(is_equal_approx(speed_spin.value, lab.body_value("speed") * 3.6), "Max speed shows the tuned top speed in km/h")
	speed_spin.value = 54.0
	check(is_equal_approx(lab.body_value("speed"), 15.0), "Typing km/h tunes the top speed in m/s")
	speed_label.get_parent().get_child(speed_label.get_index() + 2).pressed.emit()
	panel.jump_toggle.button_pressed = false
	check(not lab.jump_cooldown_enabled, "The jump cooldown toggle switches it off")
	var weapon_picker: OptionButton = panel.pickers.weapon
	var chassis_picker: OptionButton = panel.pickers.chassis
	check(weapon_picker.get_item_metadata(weapon_picker.selected) == "minigun" and weapon_picker.get_item_text(weapon_picker.selected) == "Minigun • Primary"
		and weapon_picker.item_count > 3, "Weapon 1 picker shows the fitted weapon by its Customize name, and the others")
	var utility_picker: OptionButton = panel.pickers.utility
	check(utility_picker.get_item_metadata(utility_picker.selected) == player.loadout.parts.utility and utility_picker.item_count >= 10,
		"Weapon 2 picker lists the Auxiliary / Utility parts")
	check("WEAPON 1" in texts and "WEAPON 2" in texts, "Weapon 1 and Weapon 2 sections")
	check(chassis_picker.get_item_metadata(chassis_picker.selected) == player.loadout.parts.chassis, "Chassis picker shows the fitted chassis")
	lab.reset()
	panel.render(lab, session)
	check(is_equal_approx(damage_spin.value, CombatWorld.MINIGUN_DAMAGE) and panel.heat_toggle.button_pressed, "Reset shows the defaults again")
	panel.queue_free()
	# Park the player 10 m in front of the Atlas, facing it.
	var atlas_front := (-target.spawn_pose.basis.z).slide(Vector3.UP).normalized()
	player.body.reset_pose = session.world.clear_spawn_pose(player, Transform3D(target.spawn_pose.basis.rotated(Vector3.UP, PI),
		Vector3(target.spawn_pose.origin.x, 0, target.spawn_pose.origin.z) + atlas_front * 10.0))
	await frames(30)
	var base_hits := await fire(session, target, 150)
	check(base_hits.size() > 6, "Untuned minigun hits the Atlas (%d hits)" % base_hits.size())
	check(base_hits.all(func(e: Dictionary) -> bool: return is_equal_approx(float(e.damage), CombatWorld.MINIGUN_DAMAGE)), "Untuned hits deal default damage")
	check(player.combat.heat > 0.0, "Firing builds heat by default")

	lab.set_value("primary", "damage", 12.0)
	lab.set_value("primary", "rate", 24.0)
	lab.set_value("primary", "pierce", 100.0)
	lab.heat_enabled = false
	var front_before: float = target.combat.zones.get("front", 0.0)
	var tuned_hits := await fire(session, target, 150)
	check(tuned_hits.size() > base_hits.size() * 1.5, "Doubled fire rate lands more hits (%d vs %d)" % [tuned_hits.size(), base_hits.size()])
	check(tuned_hits.all(func(e: Dictionary) -> bool: return is_equal_approx(float(e.damage), 12.0)), "Tuned hits deal the set damage")
	check(is_equal_approx(float(target.combat.zones.get("front", 0.0)), front_before), "100% piercing leaves the plate untouched")
	check(player.combat.heat == 0.0 and not player.combat.overheated, "Heat off keeps the gun cool")

	# Knockback pushes only the target; recoil only the shooter (#84 feedback).
	var queued := func() -> Array:
		session.world.weapons.pending_hits.clear()
		session.world.weapons._hit(player, target, target.body.global_position, 1.0, Vector3.FORWARD, 0, 1, CombatWorld.MINIGUN_RECOIL, "minigun")
		var hit: Array = session.world.weapons.pending_hits.pop_back()
		return [(hit[4] as Vector3).length(), (hit[4] as Vector3).length() * float(hit[7])]
	var plain: Array = queued.call()
	lab.set_value("primary", "knockback", CombatWorld.MINIGUN_KNOCKBACK * 4.0)
	var knocked: Array = queued.call()
	check(is_equal_approx(knocked[0], plain[0] * 4.0) and is_equal_approx(knocked[1], plain[1]), "Knockback pushes the target harder without pushing the shooter")
	lab.set_value("primary", "recoil", CombatWorld.MINIGUN_RECOIL * 3.0)
	var recoiled: Array = queued.call()
	check(is_equal_approx(recoiled[0], knocked[0]) and is_equal_approx(recoiled[1], plain[1] * 3.0), "Recoil pushes only the shooter")
	lab.clear_value("primary", "knockback")
	lab.clear_value("primary", "recoil")
	lab.set_body("nitro", BotPhysics.settings().nitro_top_speed_multiplier * 1.5)
	await frames(1)
	check(is_equal_approx(player.body.model_config().nitro_speed, BotPhysics.settings().nitro_top_speed_multiplier * 1.5)
		and is_equal_approx(player.body.model_config().nitro_acceleration, BotPhysics.settings().nitro_acceleration_multiplier * 1.5),
		"Nitro boost scales the boosted speed and acceleration")
	check(is_equal_approx(target.body.model_config().nitro_speed, BotPhysics.settings().nitro_top_speed_multiplier), "The Atlas keeps the normal nitro")
	lab.clear_body("nitro")
	# Area of effect: a shot into the ground beside the Atlas splashes it.
	var splashed := func() -> bool:
		session.world.weapons.pending_hits.clear()
		session.world.weapons._splash_miss(player, target.body.global_position + Vector3(2, 0, 0), CombatWorld.MINIGUN_DAMAGE,
			CombatWorld.MINIGUN_KNOCKBACK, "minigun", 0, 1)
		return session.world.weapons.pending_hits.any(func(hit: Array) -> bool: return hit[1] == target and float(hit[3]) > 0.0)
	check(lab.editable("primary", "aoe") and not splashed.call(), "No splash without an area of effect")
	lab.set_value("primary", "aoe", 6.0)
	check(splashed.call(), "A tuned area of effect splashes nearby enemies")
	lab.clear_value("primary", "aoe")
	lab.set_body("core", 500.0)
	lab.set_body("weight", 400.0)
	lab.set_body("speed", 3.0)
	lab.set_body("acceleration", 2.0)
	lab.set_body("grip", 50.0)
	lab.set_body("turn", 3.0)
	await frames(2)
	check(player.combat.core == 500.0 and float(player.combat.stats.core) == 500.0, "Health sets current and maximum core")
	check(is_equal_approx(player.body.mass, 400.0 + lab.value("primary", "weight")), "Weight sets the body mass")
	check(is_equal_approx(player.body.model_config().speed, 3.0) and is_equal_approx(player.body.model_config().acceleration, 2.0)
		and is_equal_approx(player.body.model_config().grip, 50.0 * player.body.grip_multiplier) and player.body.turn_speed == 3.0,
		"Applied speed, acceleration, grip and turn speed reach the drive")
	check(is_equal_approx(player.read_view().top_speed, 3.0), "Max speed is the top speed the HUD speedometer measures against")
	var face: String = lab.body_defaults.plates.keys()[0]
	lab.set_body("plates", 77.0, face)
	await frames(2)
	check(player.combat.zones[face] == 77.0, "Armour piece value applies at once")
	check(session.restart_practice() == OK, "Restart works while tuned")
	await frames(2)
	check(player.combat.core == 500.0 and player.combat.zones[face] == 77.0, "A restart keeps the tuned health and armour")
	check(lab.scale("primary", "damage") == 2.0, "A restart keeps the weapon tuning")
	lab.reset()
	await frames(2)
	check(lab.scale("primary", "damage") == 1.0 and lab.heat_enabled, "Reset restores the defaults")
	check(is_equal_approx(player.body.mass, float(player.combat.stats.mass)) and is_equal_approx(float(player.combat.stats.core), float(lab.body_defaults.core)),
		"Reset restores mass and health")
	lab.jump_cooldown_enabled = false
	player.combat.jump_cooldown = 3.0
	await frames(1)
	check(player.combat.jump_cooldown == 0.0, "Jump cooldown off clears a running cooldown")
	# A full-charge jump through the real perk rules, before and after tuning.
	var jump := func() -> float:
		var held := BotCommand.new()
		held.jump_held = true
		for tick: int in 120:
			player.combat.tick_perks(1.0 / 60.0, held, true, true)
		player.combat.tick_perks(1.0 / 60.0, BotCommand.new(), true, true)
		return player.combat.jump_release_speed
	if player.combat.stats.get("charged_jump", false):
		var base_jump: float = jump.call()
		lab.set_body("jump", CombatState.JUMP_MAX_SPEED * 2.0)
		check(is_equal_approx(base_jump, CombatState.JUMP_MAX_SPEED) and is_equal_approx(jump.call(), CombatState.JUMP_MAX_SPEED * 2.0),
			"Jump force sets the full-charge take-off speed")
		lab.clear_body("jump")
	else:
		failures.append("Test build needs the charged jump")
	# Pickers swap parts for real; the new part starts untuned.
	var fits := session.practice_part_options("weapon").filter(func(o: Dictionary) -> bool: return o.fits and not o.current)
	check(not fits.is_empty(), "Other weapons fit this body")
	check(session.practice_set_part("weapon", fits[0].part).get("part") == fits[0].part, "Choosing a weapon fits it")
	await frames(2)
	player = session.local_source()
	check(player.loadout.parts.weapon == fits[0].part and lab.weapons.primary.id == fits[0].part, "The bot and panel follow the chosen weapon")
	var stepped: Dictionary = session.practice_step_part("chassis", 1)
	await frames(2)
	player = session.local_source()
	check(stepped.has("part") and player.loadout.parts.chassis == stepped.part and lab.chassis() == stepped.part, "Next steps to another chassis")
	session.leave()
	check(session.practice_part_options("weapon").is_empty() and session.practice_set_part("weapon", "saw").has("refused"), "Pickers do nothing outside Practice Duel")
	check(session.practice_tuning() == null, "Leaving drops the tuning")

	# Turret builds get a separate secondary block; full practice has no tuning.
	check(session.practice(session.registry.atlas_turret(), "foundry", "duel") == OK, "Turret duel starts")
	await frames(2)
	lab = session.practice_tuning()
	check(lab.weapons.has("primary") and lab.weapons.has("secondary") and lab.has_field("secondary", "range"), "Turret gets its own block")
	# Weapon 2 swaps the utility: a non-weapon leaves nothing to tune, a mortar tunes its blast.
	check(session.practice_set_part("utility", "cooling_pack").get("part") == "cooling_pack", "Weapon 2 can take a plain utility")
	await frames(2)
	check(not lab.weapons.has("secondary") and lab.utility() == "cooling_pack", "A plain utility has no weapon values")
	check(session.practice_set_part("utility", "turret_mortar").get("part") == "turret_mortar", "Weapon 2 can take the mortar")
	await frames(2)
	check(lab.weapons.has("secondary") and lab.has_field("secondary", "aoe") and session.local_source().loadout.parts.utility == "turret_mortar",
		"The mortar's area of effect is tunable")
	session.leave()
	check(session.practice(session.registry.starter(), "foundry") == OK and session.practice_tuning() == null, "Full practice has no tuning")
	session.leave()
	# A hammer's area of effect blasts around where its head lands, hit or miss.
	var hammer_build := session.registry.starter()
	hammer_build.parts.weapon = "hammer"
	check(session.practice(hammer_build, "foundry", "duel") == OK, "Hammer duel starts")
	await frames(3)
	lab = session.practice_tuning()
	var hammerer: MvpBot = session.local_source()
	var atlas := session.practice_target() as MvpBot
	var blasted := func() -> bool:
		hammerer.combat.strike = true
		session.world.weapons.pending_hits.clear()
		session.world.weapons._hammer_blasts(session.world.bots, 0, 1)
		hammerer.combat.strike = false
		return session.world.weapons.pending_hits.any(func(hit: Array) -> bool: return hit[1] == atlas and float(hit[3]) > 0.0)
	var reach: float = session.world.weapons._hammer_head(hammerer).distance_to(atlas.body.global_position) + 5.0
	check(not blasted.call(), "An untuned hammer strike has no blast")
	lab.set_value("primary", "aoe", reach)
	check(blasted.call(), "A tuned hammer blasts the Atlas %.0f m from the head without touching it" % (reach - 5.0))
	lab.set_value("primary", "aoe", 1.0)
	check(not blasted.call(), "A small blast does not reach it")
	session.leave()
	# Allow auto fire, through the real weapon rules: hold the button for 8 s
	# (the lifter reloads for 3 s after each launch).
	var registry := ContentRegistry.new()
	for case: Array in [["hammer", "weapon", false], ["lifter", "weapon", false], ["turret_railgun", "utility", true]]:
		var draft := registry.atlas() if case[2] else registry.starter()
		draft.parts[case[1]] = case[0]
		var counts: Array[int] = []
		for auto: bool in [false, true]:
			var state := CombatState.new(registry.validate(draft).stats)
			var tuned: RefCounted = preload("res://scripts/simulation/practice_tuning.gd").new()
			tuned.heat_enabled = false
			tuned.auto_fire[("secondary" if case[2] else "primary")] = auto
			state.practice_tuning = tuned
			for tick: int in 480:
				var held := BotCommand.new()
				held.primary_held = not case[2]
				held.primary_pressed = held.primary_held and tick == 0
				held.auxiliary_held = case[2]
				state.tick(1.0 / 60.0, held, true)
			counts.append(state.shot_sequence if case[2] else state.attack_id)
		check(counts[0] <= 1 and counts[1] >= 2, "Allow auto fire repeats a held %s (%d without, %d with)" % [case[0], counts[0], counts[1]])
	# The spear impales whatever its thrust reaches and then carries it while held;
	# with auto fire it lets go and thrusts again. The world's impalement is
	# stood in for here: every strike grips a target.
	var spear_draft := registry.atlas()
	spear_draft.parts.weapon = "spear_fork"
	var thrusts: Array[int] = []
	for auto: bool in [false, true]:
		var state := CombatState.new(registry.validate(spear_draft).stats)
		var tuned: RefCounted = preload("res://scripts/simulation/practice_tuning.gd").new()
		tuned.heat_enabled = false
		tuned.auto_fire.primary = auto
		state.practice_tuning = tuned
		for tick: int in 480:
			var held := BotCommand.new()
			held.primary_held = true
			held.primary_pressed = tick == 0
			state.tick(1.0 / 60.0, held, true)
			if state.strike and state.grip_target == 0:
				state.grip_mode = "spear"
				state.grip_target = 99
		thrusts.append(state.attack_id)
	check(thrusts[0] == 1 and thrusts[1] >= 3, "Allow auto fire re-thrusts a held spear that impaled a target (%d without, %d with)" % thrusts)
	if failures.is_empty():
		print("PRACTICE_TUNING_TEST_PASS")
		quit(0)
	else:
		for failure: String in failures: push_error(failure)
		print("PRACTICE_TUNING_TEST_FAIL")
		quit(1)
