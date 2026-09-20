extends Node3D
## Interchangeable primaries must reach real wheeled hulls from walker ride height.
var failures: Array[String] = []
var world: AuthorityWorld
var attacker: MvpBot
var victim: MvpBot
var primary_held := false
var primary_edge := false
var hits: Array[Dictionary] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _physics_process(delta: float) -> void:
	if attacker == null: return
	for bot: MvpBot in [attacker, victim]:
		var command := BotCommand.new()
		command.sequence = bot.last_sequence + 1
		command.brake = true
		command.primary_held = primary_held and bot == attacker
		command.primary_pressed = primary_edge and bot == attacker
		bot.submit_command(command)
	primary_edge = false
	world.step(delta, true, 1)
	for event: Dictionary in world.weapons.events:
		if event.attacker == attacker.entity_id and event.target == victim.entity_id:
			hits.append(event.duplicate(true))

func frames(count: int) -> void:
	for frame: int in count: await get_tree().physics_frame

func run() -> void:
	world = AuthorityWorld.new()
	add_child(world)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(9, 4, -6)
	camera.look_at(Vector3(0, 1.2, 1))
	camera.current = true
	for weapon: String in ["saw", "lifter", "vertical_spinner", "horizontal_spinner"]:
		await grounded_case(weapon)
	if failures.is_empty(): print("SCORPION GROUNDED MODULES PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)

func grounded_case(weapon: String) -> void:
	var registry := ContentRegistry.new()
	var draft := registry.scorpion()
	draft.parts.weapon = weapon
	draft.parts.utility = "cooling_pack"
	check(registry.validate(draft).valid, weapon + " is a legal interchangeable primary")
	attacker = world.spawn(1, 0, 0, draft)
	victim = world.spawn(2, 1, 0, registry.starter())
	attacker.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 4, 4))
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -2.8))
	primary_held = false
	primary_edge = false
	hits.clear()
	await frames(120)
	check(absf(attacker.body.global_position.y - WalkerDrive.RIDE_HEIGHT) < 0.10,
		weapon + " test settles at the real six-leg ride height")
	check(victim.body.global_position.y < 0.9 and victim.body.grounded,
		weapon + " target is a normal grounded wheeled hull")
	check(attacker.body.walker_contacts.size() == 6,
		weapon + " does not lift the attacker onto the target")
	if attacker.scorpion_visual != null:
		var visual := attacker.scorpion_visual
		check((visual.global_transform * visual.fallback_weapon.position).distance_to(
			visual.global_transform.origin + visual.global_basis.orthonormalized() * ScorpionGeometry.fallback_socket(attacker.combat.stats.size)) < 0.001,
			weapon + " imported body and authoritative lowered socket agree")
		check(visual.fallback_weapon.find_child("ToolSocketAdapter", true, false) != null,
			weapon + " has a visible mechanical connection to the body")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("scorpion-socket-" + weapon + ".png"))
	var before := victim.combat.core
	primary_held = true
	primary_edge = true
	await frames(66 if weapon == "lifter" else 120)
	primary_held = false
	await frames(4)
	var proper_hits := 0
	for event: Dictionary in hits:
		if event.kind == weapon: proper_hits += 1
	check(proper_hits > 0 and victim.combat.core < before,
		weapon + " damages the grounded full-health target through ordinary primary commands")
	print("GROUNDED MODULE %s: hits=%d core=%s -> %s" % [weapon, proper_hits, before, victim.combat.core])
	attacker = null
	victim = null
	world.clear_bots()
	await frames(2)
