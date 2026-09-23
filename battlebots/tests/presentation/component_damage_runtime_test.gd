extends Node3D
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func settle() -> void:
	for frame: int in 3: await get_tree().process_frame

func verify(bot: MvpBot, stages: Array) -> void:
	var index := 0
	for zone: String in ["drive_left", "drive_right", "weapon"]:
		check(bot.damage_visual.stage_for(zone) == stages[index], "Runtime stage " + zone)
		var record: Dictionary = bot.damage_visual.components[zone]
		check(not record.surfaces.is_empty(), "Runtime binds real component surfaces")
		for surface: Dictionary in record.surfaces:
			check(surface.mesh.material_overlay == (record.overlay if stages[index] > 0 else surface.original), "Runtime applies/restores " + zone + " overlay")
		check(record.smoke.visible == (stages[index] == 2), "Runtime plume matches disabled state")
		index += 1

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Component damage runtime fixture requires a native rendering driver")
		get_tree().quit(1)
		return
	var registry := ContentRegistry.new()
	for config: Array in [[true, "hammer", "standard_wheels"], [true, "vertical_spinner", "walker"], [false, "horizontal_spinner", "traction"], [false, "lifter", "walker"]]:
		var draft := SawbladeConfig.starter(registry) if config[0] else registry.starter()
		draft.parts.weapon = config[1]
		draft.parts.drive = config[2]
		var bot := MvpBot.create(1, 0, draft, registry)
		check(bot != null, "Fixture build valid")
		if bot == null: continue
		bot.simulated = false
		add_child(bot)
		check(bot.damage_visual != null, "Actual bot creates damage presentation")
		if bot.damage_visual == null:
			bot.queue_free()
			await settle()
			continue
		check((bot.sawblade_visual != null) == bool(config[0]), "Requested authored/classic assembly")
		var collision_count := bot.find_children("*", "CollisionObject3D", true, false).size()
		check(bot.presentation.find_children("*", "CollisionObject3D", true, false).is_empty(), "Presentation has no collision bodies")
		check(bot.presentation.find_children("*", "CollisionShape3D", true, false).is_empty(), "Presentation has no collision shapes")
		await settle()
		verify(bot, [0, 0, 0])
		bot.combat.zones.drive_left = 50.0
		bot.combat.zones.weapon = 70.0
		await settle()
		verify(bot, [1, 0, 1])
		bot.combat.zones.drive_left = 0.0
		bot.combat.zones.weapon = 0.0
		await settle()
		verify(bot, [2, 0, 2])
		bot.reset_round()
		bot.body.freeze = true
		await settle()
		verify(bot, [0, 0, 0])
		# Client presentation must consume accepted remote values, not its fresh local state.
		bot.remote_state = bot.combat.snapshot()
		bot.remote_state.zones.drive_right = 0.0
		bot.remote_state.zones.weapon = 35.0
		var accepted := bot.remote_state.duplicate(true)
		await settle()
		verify(bot, [0, 2, 1])
		check(bot.remote_state == accepted, "Presentation leaves accepted snapshot unchanged")
		check(bot.combat.zones.drive_right == 100 and bot.combat.zones.weapon == 140, "Remote visuals never change combat health")
		bot.remote_state.eliminated = true
		await settle()
		verify(bot, [2, 2, 2])
		bot.remote_state = bot.combat.snapshot()
		await settle()
		verify(bot, [0, 0, 0])
		check(bot.find_children("*", "CollisionObject3D", true, false).size() == collision_count, "State transitions add no physics bodies")
		bot.queue_free()
		await settle()
	if failures.is_empty(): print("COMPONENT DAMAGE RUNTIME PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
