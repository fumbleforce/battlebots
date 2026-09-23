extends Node3D
## Native review of the #52-#56 weapons in ordinary Foundry practice, driven
## only by normal commands: harpoon and mortar turrets, and the ram,
## spear/forklift and grinder front tools. Evidence captures, no acceptance claim.
## Run without --headless; ATLAS_WEAPONS_CAPTURE_DIR redirects PNGs.
const RESOLUTION := Vector2i(1600, 1000)
var session: MvpSession
var camera: Camera3D
var sequence := 0
var auxiliary := false
var primary := false
var secondary := false
var throttle := 0.0
var aim_point := Vector3.ZERO
var mortar := false
var output := ""
var captures: Array[String] = []
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Weapon review requires the native renderer, without --headless.")
		get_tree().quit(1)
		return
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = RESOLUTION
	get_viewport().msaa_3d = Viewport.MSAA_4X
	output = OS.get_environment("ATLAS_WEAPONS_CAPTURE_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://exports/atlas-weapons-review")
	DirAccess.make_dir_recursive_absolute(output)
	var ignore_file := FileAccess.open(output.path_join(".gdignore"), FileAccess.WRITE)
	if ignore_file != null: ignore_file.store_string("")
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 400.0
	add_child(camera)
	camera.current = true
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(session) or session.local_source() == null: return
	var bot := session.local_source() as MvpBot
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	command.throttle = throttle
	command.brake = throttle == 0.0
	if aim_point != Vector3.ZERO and bot.combat.is_turret():
		var state := bot.combat
		var breech := bot.body.global_transform * AtlasGeometry.turret_breech(state.stats.size, state.turret_yaw)
		var direction := aim_point - breech
		command.aim_valid = true
		command.aim_yaw = atan2(-direction.x, -direction.z)
		command.aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		if mortar:
			var muzzle := bot.body.global_transform * AtlasGeometry.turret_muzzle(state.stats.size, "mortar", state.turret_yaw, state.gun_pitch)
			var offset := aim_point - muzzle
			var elevation := AtlasGeometry.mortar_elevation(Vector2(offset.x, offset.z).length(), offset.y)
			command.aim_pitch = elevation if not is_nan(elevation) else TurretTuning.settings().value("mortar", "min_elevation")
			command.aim_yaw = atan2(-offset.x, -offset.z)
	command.auxiliary_held = auxiliary
	command.primary_held = primary
	command.primary_pressed = primary
	command.secondary_held = secondary
	session.submit_local(command)

func _capture(label: String, settle := 30) -> void:
	for frame: int in settle: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var filename := output.path_join(label + ".png")
	if get_viewport().get_texture().get_image().save_png(filename) == OK:
		captures.append(filename)
	else:
		check(false, "Cannot save " + filename)

func start(draft: Dictionary, label: String) -> Array:
	session = MvpSession.new()
	session.pickups_enabled = false
	add_child(session)
	check(session.practice(draft, "foundry") == OK, "Practice starts with " + label)
	for frame: int in 900:
		await get_tree().process_frame
		if session.match_view.get("phase") in ["active", "overtime"] and session.local_source() != null: break
	var bot := session.local_source() as MvpBot
	var target := session.practice_target() as MvpBot
	check(bot != null and target != null, "Practice provides the local bot and the target for " + label)
	return [bot, target]

func finish() -> void:
	auxiliary = false
	primary = false
	secondary = false
	throttle = 0.0
	aim_point = Vector3.ZERO
	mortar = false
	session.leave()
	session.queue_free()
	for frame: int in 5: await get_tree().process_frame

func frame_on(bot: MvpBot, target: MvpBot, back: float, side: float, up: float, look_ahead: float) -> void:
	var center := bot.body.global_position
	var toward := (target.body.global_position - center).slide(Vector3.UP).normalized()
	var across := toward.cross(Vector3.UP).normalized()
	camera.position = center - toward * back + across * side + Vector3.UP * up
	camera.look_at(center + toward * look_ahead + Vector3.UP * 1.5)

func harpoon() -> void:
	var draft := MvpSession.new().registry.atlas()
	draft.parts.utility = "turret_harpoon"
	var pair: Array = await start(draft, "harpoon")
	var bot: MvpBot = pair[0]
	var target: MvpBot = pair[1]
	if bot == null or target == null: return
	aim_point = target.body.global_position
	for frame: int in 240: await get_tree().physics_frame
	frame_on(bot, target, 8.0, 14.0, 7.0, 8.0)
	await _capture("harpoon-aimed")
	var start_distance := bot.body.global_position.distance_to(target.body.global_position)
	auxiliary = true
	for frame: int in 20: await get_tree().physics_frame
	await _capture("harpoon-tethered", 2)
	for frame: int in 150:
		aim_point = target.body.global_position
		await get_tree().physics_frame
		if frame % 30 == 0:
			print("HARPOON t%d shots %d grip %d to %s target %s team %d/%d" % [frame, bot.combat.shot_sequence, bot.combat.grip_target,
				bot.combat.last_shot_to, target.body.global_position, bot.team, target.team])
	frame_on(bot, target, 6.0, 16.0, 8.0, 10.0)
	await _capture("harpoon-reeling", 2)
	var reeled := bot.body.global_position.distance_to(target.body.global_position)
	print("HARPOON showcase: %.1f m -> %.1f m, grip %d" % [start_distance, reeled, bot.combat.grip_target])
	# The practice target starts close: the winch stops at min_length.
	check(bot.combat.grip_target == target.entity_id, "The harpoon tethers the practice target")
	await finish()

func mortar_review() -> void:
	var draft := MvpSession.new().registry.atlas()
	draft.parts.utility = "turret_mortar"
	var pair: Array = await start(draft, "mortar")
	var bot: MvpBot = pair[0]
	var target: MvpBot = pair[1]
	if bot == null or target == null: return
	mortar = true
	aim_point = target.body.global_position
	for frame: int in 300: await get_tree().physics_frame
	frame_on(bot, target, 6.0, 12.0, 5.0, 4.0)
	await _capture("mortar-elevated")
	var core := target.combat.core
	var shots := bot.combat.shot_sequence
	auxiliary = true
	for frame: int in 240:
		await get_tree().process_frame
		if bot.combat.shot_sequence > shots: break
	auxiliary = false
	frame_on(bot, target, 10.0, 22.0, 10.0, 6.0)
	await _capture("mortar-launch", 3)
	var flight := AtlasGeometry.mortar_flight(bot.combat.last_shot_from, bot.combat.last_shot_to)
	var center := (bot.combat.last_shot_from + bot.combat.last_shot_to) * 0.5
	var toward := (bot.combat.last_shot_to - bot.combat.last_shot_from).slide(Vector3.UP).normalized()
	camera.position = center + toward.cross(Vector3.UP) * 40.0 + Vector3.UP * 14.0
	camera.look_at(center + Vector3.UP * 10.0)
	await _capture("mortar-arc", int(flight * 30.0))
	camera.position = bot.combat.last_shot_to + toward.cross(Vector3.UP) * 22.0 - toward * 10.0 + Vector3.UP * 9.0
	camera.look_at(bot.combat.last_shot_to + Vector3.UP * 2.0)
	await _capture("mortar-blast", int(flight * 30.0) + 4)
	await _capture("mortar-aftermath", 40)
	print("MORTAR showcase: flight %.2f s, landed %.1f m from target, core %.0f -> %.0f" % [flight,
		bot.combat.last_shot_to.distance_to(target.body.global_position), core, target.combat.core])
	# The practice dummy stands inside the mortar's minimum range, so only
	# the landing is checked here (the blast rules are atlas_launcher_physics).
	check(flight > 1.0, "The mortar lobs a shell that lands")
	await finish()

func tool_review(weapon: String, label: String) -> void:
	var draft := MvpSession.new().registry.atlas()
	draft.parts.weapon = weapon
	var pair: Array = await start(draft, label)
	var bot: MvpBot = pair[0]
	var target: MvpBot = pair[1]
	if bot == null or target == null: return
	check(bot.atlas_visual != null and bot.atlas_visual.tool != null, "%s renders its modelled front tool" % label)
	frame_on(bot, target, -12.0, 9.0, 4.5, -2.0)
	await _capture("%s-rest" % label)
	match weapon:
		"battering_ram":
			primary = true
			for frame: int in 6: await get_tree().physics_frame
			await _capture("%s-punch" % label, 1)
			primary = false
		"spear_fork":
			primary = true
			for frame: int in 5: await get_tree().physics_frame
			await _capture("%s-thrust" % label, 1)
			primary = false
		"grinder_drum":
			primary = true
			secondary = true
			for frame: int in 90: await get_tree().physics_frame
			await _capture("%s-raised-spinning" % label, 1)
			secondary = false
			for frame: int in 40: await get_tree().physics_frame
			await _capture("%s-spinning" % label, 1)
			primary = false
	# Drive into the practice target with the tool working.
	var distance := bot.body.global_position.distance_to(target.body.global_position)
	var core := target.combat.core
	throttle = 1.0
	primary = weapon == "grinder_drum"
	var engaged := false
	for frame: int in 600:
		await get_tree().physics_frame
		if weapon != "grinder_drum" and frame % 40 == 0: primary = not primary
		if bot.body.global_position.distance_to(target.body.global_position) < 11.0 and not engaged:
			engaged = true
			if weapon == "spear_fork": primary = true
		if engaged and target.combat.core < core and frame % 20 == 0: break
	throttle = 0.0
	frame_on(bot, target, -9.0, 12.0, 6.0, -3.0)
	await _capture("%s-engaged" % label, 2)
	for frame: int in 45: await get_tree().physics_frame
	await _capture("%s-engaged-late" % label, 1)
	print("%s showcase: %.1f m run-up, target core %.0f -> %.0f, grip %d" % [label, distance, core, target.combat.core, bot.combat.grip_target])
	check(target.combat.core < core, "%s damages the practice target" % label)
	await finish()

## Cooling zones and coolant canisters (#68) with their real presentation.
func heat_relief_review() -> void:
	var pair: Array = await start(MvpSession.new().registry.atlas(), "heat relief")
	var bot: MvpBot = pair[0]
	if bot == null: return
	session.world.begin_pickups(3)
	var zones := CoolingZoneVisuals.new()
	add_child(zones)
	zones.bind_session(session)
	var markers := PickupVisuals.new()
	add_child(markers)
	markers.bind_session(session)
	var zone: Vector3 = session.world.cooling_zones()[0]
	camera.position = zone + Vector3(-14, 9, 14)
	camera.look_at(zone + Vector3.UP * 1.5)
	await _capture("cooling-zone", 90)
	var canister: Vector3 = session.world.coolant_points()[0]
	camera.position = canister + Vector3(-9, 6, 9)
	camera.look_at(canister + Vector3.UP * 2.0)
	await _capture("coolant-canister", 30)
	zones.queue_free()
	markers.queue_free()
	await finish()

func run() -> void:
	await heat_relief_review()
	await harpoon()
	await mortar_review()
	await tool_review("battering_ram", "ram")
	await tool_review("spear_fork", "spear")
	await tool_review("grinder_drum", "grinder")
	print("WEAPON CAPTURES ", JSON.stringify(captures))
	print("ATLAS WEAPONS SHOWCASE PASS" if failures == 0 else "ATLAS WEAPONS SHOWCASE FAIL")
	get_tree().quit(0 if failures == 0 else 1)
