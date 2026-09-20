extends Node3D
var failures: Array[String] = []

func _ready() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func run() -> void:
	var registry := ContentRegistry.new()
	var target := StaticBody3D.new()
	target.collision_layer = BaselineConfig.BOT_LAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.025
	shape.shape = sphere
	target.add_child(shape)
	add_child(target)
	for chassis: String in ["compact", "balanced", "wide"]:
		for weapon: String in ["saw", "hammer"]:
			var draft := SawbladeConfig.starter(registry)
			draft.parts.chassis = chassis
			draft.parts.weapon = weapon
			var bot := MvpBot.create(1, 0, draft, registry)
			add_child(bot)
			bot.body.freeze = true
			bot.body.global_position = Vector3(0, 4, 0)
			bot.previous_pose = bot.body.global_transform
			await settle()
			# Pin presentation to the fixture pose before sampling mesh contacts;
			# process_frame resumes before a newly added bot's first _process.
			bot.presentation.global_transform = bot.body.global_transform
			bot.set_process(false)
			var art := SawbladeVisual.new()
			bot.presentation.add_child(art)
			art.assemble(draft, bot.combat.stats.size)
			var contact: Vector3
			if weapon == "hammer":
				art.set_hammer_frame(9)
				contact = art.nodes.Hammer_Impact.global_position + Vector3.UP * 0.04
			else:
				contact = art.nodes.Saw_SPIN_X.global_position - Vector3.BACK * 0.65 * art.scale.z
			target.global_position = contact
			await settle()
			var combat := CombatWorld.new()
			check(combat._sweep(bot).has(target.get_instance_id()), chassis + " " + weapon + " hits actual rendered contact surface")
			target.global_position = Vector3(0, 4, -3.4 * BotScale.FACTOR)
			await settle()
			check(not combat._sweep(bot).has(target.get_instance_id()), weapon + " cannot hit beyond authored reach")
			bot.free()
	if failures.is_empty(): print("SAWBLADE CONTACT PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
