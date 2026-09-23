extends Node3D
## Native review of the Atlas drive configurations in ordinary Practice, driven
## only by normal commands, plus the garage preview. Evidence captures, no
## acceptance claim. Run without --headless; ATLAS_DRIVES_CAPTURE_DIR redirects PNGs.
const RESOLUTION := Vector2i(1600, 1000)
## Configurations reviewed: drive part and arena.
const CASES := [["standard_wheels", "foundry"], ["walker", "foundry"], ["walker", "woodland"], ["traction", "foundry"]]
## Frames to let a spawned bot settle, to pivot away from the practice target
## (Practice spawns facing it) and to drive between captures.
const SETTLE_FRAMES := 120
const PIVOT_FRAMES := 80
const DRIVE_FRAMES := 90
## Camera placements around the bot: distance back/side/up in game metres.
const HERO := Vector3(-11.0, 6.0, 12.0)
const REAR := Vector3(10.0, 5.0, -11.0)
const SIDE := Vector3(0.0, 1.8, 15.0)
## Planted walker soles may sit this far from the ground below them (game m).
const SOLE_TOLERANCE := 0.25
var session: MvpSession
var camera: Camera3D
var sequence := 0
var throttle := 0.0
var steering := 0.0
var output := ""
var captures: Array[String] = []
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Drive review requires the native renderer, without --headless.")
		get_tree().quit(1)
		return
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = RESOLUTION
	get_viewport().msaa_3d = Viewport.MSAA_4X
	output = OS.get_environment("ATLAS_DRIVES_CAPTURE_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://exports/atlas-drives-review")
	DirAccess.make_dir_recursive_absolute(output)
	var ignore_file := FileAccess.open(output.path_join(".gdignore"), FileAccess.WRITE)
	if ignore_file != null: ignore_file.store_string("")
	camera = Camera3D.new()
	camera.fov = 40.0
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
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	command.throttle = throttle
	command.steering = steering
	command.brake = throttle == 0.0 and steering == 0.0
	session.submit_local(command)

func _capture(label: String, settle := 20) -> void:
	for frame: int in settle: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var filename := output.path_join(label + ".png")
	if get_viewport().get_texture().get_image().save_png(filename) == OK:
		captures.append(filename)
	else:
		check(false, "Cannot save " + filename)

func _frame(bot: MvpBot, offset: Vector3, look_height := 1.8) -> void:
	var basis := bot.body.global_basis.orthonormalized()
	var forward := -basis.z.slide(Vector3.UP).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var centre := bot.body.global_position
	camera.position = centre + right * offset.z - forward * offset.x + Vector3.UP * offset.y
	camera.look_at(centre + Vector3.UP * look_height)

func review(drive: String, arena: String) -> void:
	session = MvpSession.new()
	session.pickups_enabled = false
	add_child(session)
	var draft: Dictionary = session.registry.atlas()
	draft.parts.drive = drive
	check(session.practice(draft, arena) == OK, "Practice starts Atlas on %s in %s" % [drive, arena])
	# Evidence of the running gear, not combat: the NPC pilots stay idle.
	session.practice_director = null
	throttle = 0.0
	steering = 0.0
	for frame: int in SETTLE_FRAMES: await get_tree().process_frame
	var bot := session.local_source() as MvpBot
	if bot == null or bot.atlas_visual == null:
		check(false, "Practice renders the Atlas visual")
		return
	var gear := bot.atlas_visual.drive_gear
	check(gear == AtlasGeometry.DRIVE_GEAR[drive], "%s renders %s" % [drive, gear])
	var tag := "%s-%s" % [gear, arena]
	_frame(bot, HERO)
	await _capture(tag + "-hero")
	_frame(bot, REAR)
	await _capture(tag + "-rear")
	_frame(bot, SIDE, 1.2)
	await _capture(tag + "-side")
	var start := bot.body.global_position
	var spin: Basis = bot.atlas_visual._wheels[0].node.basis if not bot.atlas_visual._wheels.is_empty() else Basis()
	steering = 1.0
	for frame: int in PIVOT_FRAMES: await get_tree().physics_frame
	throttle = 1.0
	steering = 0.25
	for frame: int in DRIVE_FRAMES: await get_tree().physics_frame
	_frame(bot, HERO)
	await _capture(tag + "-moving", 1)
	_frame(bot, SIDE, 1.2)
	await _capture(tag + "-moving-side", 1)
	throttle = 0.0
	steering = 0.0
	check(bot.body.global_position.distance_to(start) > 1.0, "%s drives under ordinary throttle" % tag)
	if gear == "wheels":
		check(not bot.atlas_visual._wheels[0].node.basis.is_equal_approx(spin), "Large wheels roll with travel")
	if gear == "legs":
		for frame: int in 60: await get_tree().physics_frame
		var rig := AtlasDriveRig.settings()
		var scale_factor := bot.body.geometry_scale
		for leg: Dictionary in bot.atlas_visual.legs.legs:
			var foot: Node3D = leg.nodes.Foot
			var sole := foot.global_position - foot.global_basis.y.normalized() * rig.ankle * scale_factor
			var query := PhysicsRayQueryParameters3D.create(sole + Vector3.UP * 2.0, sole + Vector3.DOWN * 2.0,
				BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [bot.body.get_rid()])
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and absf(Vector3(hit.position).y - sole.y) < SOLE_TOLERANCE,
				"%s leg %s stands on the ground after walking" % [tag, leg.tag])
		_frame(bot, HERO)
		await _capture(tag + "-planted")
	session.leave()
	session.queue_free()
	for frame: int in 5: await get_tree().process_frame

func garage(drive: String) -> void:
	var registry := ContentRegistry.new()
	var draft: Dictionary = registry.atlas()
	draft.parts.drive = drive
	var preview := GarageBotPreview.new()
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(preview)
	preview.show_loadout(draft)
	check(preview.atlas_visual != null and preview.atlas_visual.drive_gear == AtlasGeometry.DRIVE_GEAR[drive],
		"Garage shows Atlas on its %s" % drive)
	await _capture("garage-" + AtlasGeometry.DRIVE_GEAR[drive], 45)
	layer.queue_free()
	for frame: int in 3: await get_tree().process_frame

func run() -> void:
	for entry: Array in CASES:
		await review(entry[0], entry[1])
	for drive: String in ["standard_wheels", "walker"]:
		await garage(drive)
	print("DRIVE CAPTURES ", JSON.stringify(captures))
	print("ATLAS DRIVES SHOWCASE PASS" if failures == 0 else "ATLAS DRIVES SHOWCASE FAIL")
	get_tree().quit(0 if failures == 0 else 1)
