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
var hammer_hits := 0
var first_hammer_core := 0.0
var phase := "approach"
var phase_started := 0
var gameplay_audio: GameplayAudio
var continuous_audio: ContinuousGameplayAudio

func _ready() -> void:
	review_video = "--review-video" in OS.get_cmdline_user_args()
	if review_video:
		get_window().size = Vector2i(1600, 1000)
	session = MvpSession.new()
	add_child(session)
	assert(session.practice(session.registry.scorpion()) == OK)
	AudioPreferences.new().apply()
	gameplay_audio = GameplayAudio.new()
	add_child(gameplay_audio)
	continuous_audio = ContinuousGameplayAudio.new()
	add_child(continuous_audio)
	gameplay_audio.observe_match(session.match_view, true)
	gameplay_audio.cue_played.connect(func(cue: String) -> void:
		if cue in ["countdown", "start", "round_end", "results", "low_core", "recovery", "armor_break"]:
			continuous_audio.duck())
	session.combat_event.connect(func(event: Dictionary) -> void:
		gameplay_audio.observe_match(session.match_view, true)
		gameplay_audio.combat_event(event, session.local_entity)
		if event.attacker == session.local_entity and event.target == (session.practice_target() as MvpBot).entity_id:
			hit_count += 1
			if event.kind == "hammer":
				hammer_hits += 1
				print("NATURAL HAMMER HIT frame=%d damage=%.1f starting_core=%.1f" % [frames,event.damage,first_hammer_core]))
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = 50
	camera.current = true
	camera.position = Vector3(17,10,9)
	camera.look_at(Vector3(0,2.2,0))
	get_viewport().audio_listener_enable_3d = true

func _process(_delta: float) -> void:
	if done or session == null or session.connection_state != "practice": return
	gameplay_audio.observe_match(session.match_view, true)
	gameplay_audio.observe_bot(session.local_source().read_view(), "hammer")
	continuous_audio.render(session.audio_views(), true)

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
	# The review pilot approaches with ordinary drive/brake commands, settles at
	# the articulated hammer's reach, and presses primary once before firing.
	# Health, weapon settings, NPC pilots and every body pose remain stock.
	if review_video and phase == "approach" and frames > 30:
		var offset := target.body.global_position - player.body.global_position
		var local := player.body.global_basis.inverse() * offset
		var angle := atan2(local.x,-local.z)
		var distance := Vector2(offset.x,offset.z).length()
		command.steering = clampf(angle * 1.4, -0.4, 0.4)
		command.throttle = clampf((distance - 8.2) * 0.65, 0.0, 0.85) if absf(angle) < 0.2 else 0.0
		command.brake = distance <= 8.5
		if distance < 8.65 and player.body.linear_velocity.slide(Vector3.UP).length() < 0.35 and absf(angle) < 0.05:
			phase = "hammer"
			phase_started = frames
			first_hammer_core = target.combat.core
			command.primary_pressed = true
			command.primary_held = true
			print("NATURAL HAMMER PRESS frame=%d range=%.2f core=%.1f" % [frames,distance,first_hammer_core])
	elif review_video and phase == "hammer":
		command.primary_held = frames - phase_started < 30
		if frames - phase_started > 90: phase = "gun"
	if frames > 120 and (not review_video or phase == "gun"):
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
		print("NATURAL NPC progress frame=%d phase=%s hits=%d core=%.1f player_y=%.2f muzzle_y=%.2f target_y=%.2f shots=%d" % [frames,phase,hit_count,target.combat.core,player.body.global_position.y,(player.body.global_transform*ScorpionGeometry.gun_muzzle(player.combat.stats.size)).y,target.body.global_position.y,player.combat.shot_sequence])
	if frames >= (1700 if review_video else 2400):
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
	if review_video:
		assert(hammer_hits > 0 and first_hammer_core == target.combat.stats.core, "Review must show a normal hammer hit on the full-health calibration bot")
	await get_tree().create_timer(0.18).timeout
	if DisplayServer.get_name() != "headless":
		assert(target.destruction_visual.active and target.destruction_visual._chunk_paths.size() == 8)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://exports/evidence")
		get_viewport().get_texture().get_image().save_png("res://exports/evidence/practice-natural-destruction.png")
	print("NATURAL NPC DESTRUCTION PASS frames=%d accepted_hits=%d hammer_hits=%d shots=%d" % [frames,hit_count,hammer_hits,(session.local_source() as MvpBot).combat.shot_sequence])
	if review_video: await get_tree().create_timer(1.25).timeout
	gameplay_audio.reset()
	continuous_audio.reset()
	gameplay_audio.queue_free()
	continuous_audio.queue_free()
	session.leave()
	for frame: int in 3: await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()
