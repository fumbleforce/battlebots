extends Node3D
## Native production-arena review capture, not a substitute for live combat tests.
var session: MvpSession
var camera: Camera3D
var sequence := 0

func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	session = MvpSession.new()
	add_child(session)
	assert(session.practice(session.registry.scorpion()) == OK)
	camera = Camera3D.new()
	camera.fov = 46
	camera.far = 180
	add_child(camera)
	camera.current = true
	run.call_deferred()

func _physics_process(_delta: float) -> void:
	if session == null or session.local_source() == null: return
	var command := BotCommand.new()
	command.sequence = sequence
	command.brake = true
	sequence += 1
	session.submit_local(command)

func run() -> void:
	for frame: int in 140: await get_tree().process_frame
	var bot := session.local_source() as MvpBot
	var center: Vector3 = bot.body.global_position
	camera.position = center + Vector3(11, 8, -15)
	camera.look_at(center + Vector3(0, 1.5, -0.2))
	for frame: int in 30: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("SCORPION_CAPTURE")
	if output.is_empty(): output = OS.get_environment("TEMP") + "/scorpion-foundry.png"
	get_viewport().get_texture().get_image().save_png(output)
	print("SCORPION CAPTURE ", output)
	session.leave()
	for frame: int in 3: await get_tree().process_frame
	get_tree().quit()
