extends SceneTree
## Actual preview camera crosshair -> aim command -> wire -> MvpBot -> servo.
const STEP := 1.0 / 60.0
var failures := 0
var sequence := 1
var bot: MvpBot
var target: MvpBot
var weapons := CombatWorld.new()
var tick := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func transmit(command: BotCommand) -> void:
	command.sequence = sequence
	sequence += 1
	var decoded := WireCodec.command_from_array(WireCodec.command_to_array(command))
	check(decoded != null, "Aimed command survives the wire")
	bot.submit_command(decoded)
	bot.step(STEP, true)
	tick += 1
	weapons.step(STEP, {1: bot, 2: target}, tick, 1)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var registry := ContentRegistry.new()
	var draft := registry.atlas()
	draft.parts.utility = "turret_cannon"
	bot = MvpBot.create(1, 0, draft, registry)
	bot.name = "Bot"
	target = MvpBot.create(2, 1, registry.starter(), registry)
	target.name = "Target"
	for item: MvpBot in [bot, target]:
		world.add_child(item)
		item.body.freeze = true
		item.body.gravity_scale = 0.0
	bot.body.global_position = Vector3(0, 2, 0)
	target.body.global_position = Vector3(-30, 1, 0)
	await physics_frame
	await physics_frame
	var view := bot.read_view()
	check(view.turret_kind == "cannon" and view.has_auxiliary_weapon, "Bot view publishes the fitted turret")
	var preview: Node3D = load("res://scenes/ui/baseline_preview.tscn").instantiate()
	preview.source_path = NodePath("../Bot")
	preview.settings_path = ""
	world.add_child(preview)
	preview.set_physics_process(false)
	var rig: BotOrbitCamera = preview.rig
	rig.set_physics_process(false)
	# Look left across the target with the orbit camera, as a mouse would.
	rig.yaw = PI * 0.5
	rig.pitch = deg_to_rad(6.0)
	for frame: int in 110:
		rig.update_camera(STEP)
		preview._update_tank_sight(bot.read_view(), STEP)
		var command := BotCommand.new()
		preview._apply_turret_aim(command, bot.read_view())
		if frame == 0:
			check(command.aim_valid and absf(command.aim_yaw - PI * 0.5) < 0.15,
				"Crosshair ray becomes a world bearing toward the target: %f" % command.aim_yaw)
		transmit(command)
	check(absf(bot.combat.turret_yaw - PI * 0.5) < 0.08, "Authoritative turret follows the mouse aim: %f" % bot.combat.turret_yaw)
	check(bot.combat.gun_pitch < 0.0, "Turret depresses toward the target below the trunnion")
	preview._physics_process(STEP)
	check(not rig.driving, "Turret builds suspend camera auto-recenter; the camera is the sight")
	check(preview.tank_sight.active and preview.aim_camera() == preview.tank_sight.camera and preview.tank_sight.camera.current,
		"Turret builds view through the tank sight camera")
	var sight: Camera3D = preview.tank_sight.camera
	var own := PhysicsRayQueryParameters3D.create(sight.global_position, sight.global_position - sight.global_basis.z * 60.0,
		BaselineConfig.BOT_LAYER)
	var centre_hit := root.get_world_3d().direct_space_state.intersect_ray(own)
	check(centre_hit.is_empty() or centre_hit.collider_id != bot.body.get_instance_id(),
		"The sight's centre ray looks over the own hull, never onto it")
	# Tank buttons: LMB is the main gun, RMB the hull weapon.
	var gate: GameplayInputGate = preview.input_gate
	check(gate.turret_main_gun, "Turret view switches the input gate to tank buttons")
	gate.sample({}, {}, true)
	var lmb := gate.sample({&"primary": 1.0}, {&"primary": true}, true)
	check(lmb.auxiliary_held and not lmb.primary_held and not lmb.secondary_held, "LMB fires the turret, not the hull weapon")
	var rmb := gate.sample({&"secondary": 1.0}, {&"secondary": true}, true)
	check(rmb.primary_held and rmb.primary_pressed and not rmb.auxiliary_held and not rmb.secondary_held,
		"RMB operates the hull weapon without cancelling it")
	var suppressed := gate.sample({&"primary": 1.0, &"secondary": 1.0}, {}, false)
	check(not suppressed.auxiliary_held and suppressed.secondary_held, "Menu suppression never fires and still cancels")
	preview.controls_enabled = true
	preview.pause_menu.hide()
	preview._render_turret_reticle(bot.read_view())
	var reticle: TurretReticle = preview.turret_reticle
	var centre := reticle.size * 0.5
	check(reticle.crosshair_visible and reticle.barrel_visible, "Reticle shows crosshair and barrel marker")
	check(reticle.barrel_point.distance_to(centre) < reticle.size.y * 0.08,
		"Settled barrel marker overlays the crosshair: %s vs %s" % [reticle.barrel_point, centre])
	# Menu/focus suppression sends neutral intent: the servo returns home.
	preview.sequence = sequence
	preview.release_controls()
	check(not bot.command.aim_valid, "Released controls submit no aim")
	for frame: int in 120:
		bot.step(STEP, true)
		weapons.step(STEP, {1: bot, 2: target}, tick, 1)
	check(absf(bot.combat.turret_yaw) < 0.01, "Without aim the turret returns forward")
	preview._render_turret_reticle(bot.read_view())
	check(not reticle.visible, "Reticle hides while controls are released")
	world.queue_free()
	await process_frame
	print("ATLAS TURRET INPUT PASS" if failures == 0 else "ATLAS TURRET INPUT FAIL")
	quit(0 if failures == 0 else 1)
