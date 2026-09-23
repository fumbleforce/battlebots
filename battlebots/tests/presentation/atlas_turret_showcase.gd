extends Node3D
## Native review of the turret in ordinary Foundry practice, driven only by
## normal commands (aim + auxiliary trigger). Evidence captures, no acceptance claim.
## Run without --headless; ATLAS_TURRET_CAPTURE_DIR redirects PNGs.
const RESOLUTION := Vector2i(1600, 1000)
var session: MvpSession
var camera: Camera3D
var sequence := 0
var firing := false
var aim_point := Vector3.ZERO
var output := ""
var captures: Array[String] = []
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Turret review requires the native renderer, without --headless.")
		get_tree().quit(1)
		return
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = RESOLUTION
	get_viewport().msaa_3d = Viewport.MSAA_4X
	output = OS.get_environment("ATLAS_TURRET_CAPTURE_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://exports/atlas-turret-review")
	DirAccess.make_dir_recursive_absolute(output)
	var ignore_file := FileAccess.open(output.path_join(".gdignore"), FileAccess.WRITE)
	if ignore_file != null: ignore_file.store_string("")
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 300.0
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
	command.brake = true
	if aim_point != Vector3.ZERO:
		var breech := bot.body.global_transform * AtlasGeometry.turret_breech(bot.combat.stats.size, bot.combat.turret_yaw)
		var direction := aim_point - breech
		command.aim_valid = true
		command.aim_yaw = atan2(-direction.x, -direction.z)
		command.aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	command.auxiliary_held = firing
	command.secondary_held = firing
	session.submit_local(command)

func _capture(label: String, settle := 30) -> void:
	for frame: int in settle: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var filename := output.path_join(label + ".png")
	if get_viewport().get_texture().get_image().save_png(filename) == OK:
		captures.append(filename)
	else:
		check(false, "Cannot save " + filename)

func review(kind: String) -> void:
	session = MvpSession.new()
	add_child(session)
	var draft: Dictionary = session.registry.atlas()
	draft.parts.utility = "turret_" + kind
	check(session.practice(draft, "foundry") == OK, "Practice starts with the %s turret" % kind)
	for frame: int in 120: await get_tree().process_frame
	var bot := session.local_source() as MvpBot
	var target := session.practice_target() as MvpBot
	if bot == null or target == null:
		check(false, "Practice provides the local bot and the calibration target")
		return
	check(bot.atlas_visual != null and bot.atlas_visual.turret != null, "Practice renders the modelled turret")
	var center: Vector3 = bot.body.global_position
	var toward: Vector3 = (target.body.global_position - center)
	toward.y = 0.0
	toward = toward.normalized()
	var side := toward.cross(Vector3.UP).normalized()
	aim_point = target.body.global_position
	for frame: int in 150: await get_tree().physics_frame
	var barrel := bot.body.global_basis * AtlasGeometry.turret_direction(bot.combat.turret_yaw, bot.combat.gun_pitch)
	var wanted := (aim_point - bot.body.global_transform * AtlasGeometry.turret_breech(bot.combat.stats.size, bot.combat.turret_yaw)).normalized()
	print("TURRET DEBUG bot=", center, " target=", target.body.global_position, " yaw=", bot.combat.turret_yaw, " pitch=", bot.combat.gun_pitch,
		" barrel=", barrel.normalized(), " wanted=", wanted, " aim_valid=", bot.command.aim_valid, " phase=", session.match_view.get("phase"))
	check(barrel.normalized().dot(wanted) > 0.995, "%s turret settles on the practice target" % kind)
	camera.position = center - toward * 7.0 + side * 13.0 + Vector3.UP * 7.5
	camera.look_at(center + toward * 5.0 + Vector3.UP * 2.0)
	await _capture("turret-%s-aimed" % kind)
	camera.position = center + toward * 5.0 + side * 10.0 + Vector3.UP * 4.0
	camera.look_at(center + Vector3.UP * 2.3)
	await _capture("turret-%s-close" % kind)
	var core := target.combat.core
	var shots := bot.combat.shot_sequence
	camera.position = center - toward * 10.0 + side * 16.0 + Vector3.UP * 7.0
	camera.look_at(center + toward * 12.0 + Vector3.UP * 2.0)
	firing = true
	# Catch the muzzle blast / projectile a few frames after the first shot.
	for frame: int in 240:
		await get_tree().process_frame
		if bot.combat.shot_sequence > shots:
			break
	await _capture("turret-%s-firing" % kind, 3 if kind == "cannon" else 8)
	for frame: int in 60: await get_tree().physics_frame
	firing = false
	print("TURRET SHOT DEBUG seq=", bot.combat.shot_sequence, " from=", bot.combat.last_shot_from, " to=", bot.combat.last_shot_to, " core=", target.combat.core, "/", core)
	check(bot.combat.shot_sequence > shots, "%s fires from the ordinary auxiliary trigger" % kind)
	check(target.combat.core < core, "%s shots damage the practice target" % kind)
	await _capture("turret-%s-after" % kind, 10)
	aim_point = Vector3.ZERO
	session.leave()
	session.queue_free()
	for frame: int in 5: await get_tree().process_frame

func run() -> void:
	for kind: String in ["cannon", "plasma"]:
		await review(kind)
	print("TURRET CAPTURES ", JSON.stringify(captures))
	print("ATLAS TURRET SHOWCASE PASS" if failures == 0 else "ATLAS TURRET SHOWCASE FAIL")
	get_tree().quit(0 if failures == 0 else 1)
