extends Node3D
## Native live combat acceptance: stock health/stats, normal input, real Jolt.
## Capture only after accepted damage eliminates the unmodified calibration NPC.
var session: MvpSession
var camera: Camera3D
var frames := 0
var hit_count := 0
var fired := 0
var cooling := false
var done := false
var review_video := false

func _ready() -> void:
	review_video = "--review-video" in OS.get_cmdline_user_args()
	if review_video:
		get_window().size = Vector2i(1600, 1000)
	session = MvpSession.new()
	add_child(session)
	assert(session.practice(session.registry.scorpion()) == OK)
	session.combat_event.connect(func(event: Dictionary) -> void:
		if event.attacker == session.local_entity and event.target == (session.practice_target() as MvpBot).entity_id:
			hit_count += 1)
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = 50
	camera.current = true
	camera.position = Vector3(17,10,9)
	camera.look_at(Vector3(0,1.0,0))

func _physics_process(_delta: float) -> void:
	if done: return
	frames += 1
	var player := session.local_source() as MvpBot
	var target := session.practice_target() as MvpBot
	if target.combat.eliminated:
		done = true
		capture_success.call_deferred()
		return
	var command := BotCommand.new()
	command.brake = true
	# The optional review capture begins with a short, ordinary walking approach.
	# Health, weapon settings, pilots and destruction remain the stock game.
	if review_video and frames > 30 and frames < 90:
		command.throttle = 0.7
		command.brake = false
	if frames > 120:
		var offset := target.body.global_position - player.body.global_position - player.body.global_basis.x * ScorpionGeometry.gun_muzzle(player.combat.stats.size).x
		var local := player.body.global_basis.inverse() * offset
		var angle := atan2(local.x,-local.z)
		command.steering = clampf(angle*1.4,-0.4,0.4)
		command.brake = absf(angle)<.015
		if player.combat.heat > 80 or player.combat.battery < 15: cooling = true
		if player.combat.heat < 30 and player.combat.battery > 55: cooling = false
		command.auxiliary_held = absf(angle)<.07 and not cooling
		command.secondary_held = command.auxiliary_held
		if command.auxiliary_held: fired += 1
	session.submit_local(command)
	if frames % 300 == 0:
		print("NATURAL NPC progress frame=%d hits=%d core=%.1f player_y=%.2f muzzle_y=%.2f target_y=%.2f shots=%d" % [frames,hit_count,target.combat.core,player.body.global_position.y,(player.body.global_transform*ScorpionGeometry.gun_muzzle(player.combat.stats.size)).y,target.body.global_position.y,player.combat.shot_sequence])
	if frames >= 2400:
		done = true
		push_error("Natural minigun NPC destruction timed out: hits=%d core=%.1f" % [hit_count,target.combat.core])
		session.leave()
		get_tree().quit(1)

func capture_success() -> void:
	var target := session.practice_target() as MvpBot
	var neutral := BotCommand.new()
	neutral.brake = true
	session.submit_local(neutral)
	assert(hit_count > 0 and target.combat.core == 0.0)
	await get_tree().create_timer(0.18).timeout
	if DisplayServer.get_name() != "headless":
		assert(target.destruction_visual.active and target.destruction_visual._chunk_paths.size() == 8)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://exports/evidence")
		get_viewport().get_texture().get_image().save_png("res://exports/evidence/practice-natural-destruction.png")
	print("NATURAL NPC DESTRUCTION PASS frames=%d accepted_hits=%d shots=%d" % [frames,hit_count,(session.local_source() as MvpBot).combat.shot_sequence])
	if review_video: await get_tree().create_timer(1.25).timeout
	session.leave()
	for frame: int in 3: await get_tree().process_frame
	get_tree().quit()
