extends Node3D
## Native review of the four nimble bots (#61) in ordinary Foundry practice,
## driven only by normal commands: each runs, turns and is captured mid-gait,
## then one overview shows the four practice roamers. Evidence captures only;
## no visual acceptance claim. Run without --headless; NIMBLE_CAPTURE_DIR
## redirects PNGs.
const RESOLUTION := Vector2i(1600, 1000)
var session: MvpSession
var camera: Camera3D
var sequence := 0
var throttle := 0.0
var steering := 0.0
var primary := false
var output := ""
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Nimble review requires the native renderer, without --headless.")
		get_tree().quit(1)
		return
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = RESOLUTION
	get_viewport().msaa_3d = Viewport.MSAA_4X
	output = OS.get_environment("NIMBLE_CAPTURE_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://exports/nimble-review")
	DirAccess.make_dir_recursive_absolute(output)
	var ignore_file := FileAccess.open(output.path_join(".gdignore"), FileAccess.WRITE)
	if ignore_file != null: ignore_file.store_string("")
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 500.0
	add_child(camera)
	camera.current = true
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1
		push_error(message)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(session) or session.local_source() == null: return
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	command.throttle = throttle
	command.steering = steering
	command.brake = throttle == 0.0 and steering == 0.0
	command.primary_held = primary
	command.primary_pressed = primary
	session.submit_local(command)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var filename := output.path_join(label + ".png")
	check(get_viewport().get_texture().get_image().save_png(filename) == OK, "Saved " + filename)

func follow(bot: MvpBot, side: float, back: float, up: float) -> void:
	var at := bot.presentation.global_position
	var forward := (-bot.presentation.global_basis.z).slide(Vector3.UP).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	camera.global_position = at + right * side - forward * back + Vector3.UP * up
	camera.look_at(at + Vector3.UP * 0.5)

func frames(count: int, bot: MvpBot = null, side := 0.0, back := 0.0, up := 0.0) -> void:
	for frame: int in count:
		await get_tree().process_frame
		if bot != null: follow(bot, side, back, up)

func run() -> void:
	var registry := ContentRegistry.new()
	for draft: Dictionary in registry.nimble():
		await showcase(draft)
	await overview(registry.nimble()[0])
	print("NIMBLE SHOWCASE %s (%d failures) -> %s" % ["PASS" if failures == 0 else "FAIL", failures, output])
	get_tree().quit(0 if failures == 0 else 1)

func start(draft: Dictionary) -> MvpBot:
	session = MvpSession.new()
	session.pickups_enabled = false
	add_child(session)
	check(session.practice(draft, "foundry") == OK, "Practice starts with " + draft.name)
	for frame: int in 600:
		await get_tree().process_frame
		if session.match_view.get("phase") in ["active", "overtime"] and session.local_source() != null: break
	return session.local_source() as MvpBot

func finish() -> void:
	throttle = 0.0
	steering = 0.0
	primary = false
	session.leave()
	session.queue_free()
	await frames(5)

func showcase(draft: Dictionary) -> void:
	var bot := await start(draft)
	if bot == null: return
	var label: String = draft.parts.chassis
	check(bot.nimble_visual != null, "%s shows its authored model" % draft.name)
	await frames(30, bot, 14.0, 4.0, 4.0)
	await _capture(label + "-idle")
	throttle = 1.0
	await frames(70, bot, 16.0, 2.0, 3.0)
	await _capture(label + "-running")
	steering = 1.0
	await frames(40, bot, 4.0, 18.0, 5.0)
	await _capture(label + "-turning")
	steering = 0.0
	throttle = 0.0
	primary = true
	await frames(40, bot, 12.0, -6.0, 4.0)
	await _capture(label + "-weapon")
	primary = false
	await finish()

func overview(draft: Dictionary) -> void:
	var bot := await start(draft)
	if bot == null: return
	await frames(200)
	camera.global_position = Vector3(0, 16, 46)
	camera.look_at(Vector3(0, 0, 0))
	await frames(2)
	await _capture("practice-roamers")
	await finish()
