extends Node3D
## Real authoritative firing and native stereo mixer/lifecycle acceptance.
var failures: Array[String] = []
var capture: AudioEffectCapture
var world: AuthorityWorld
var bot: MvpBot
var hold := false
var stepping := true
var sequence := 0
var camera: Camera3D
var effects: MinigunEffects
var sound: MinigunWeaponAudio
var bus := -1
var master := -1

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _physics_process(delta: float) -> void:
	if bot == null or not stepping: return
	var command := BotCommand.new()
	sequence += 1
	command.sequence = sequence
	command.auxiliary_held = hold
	command.secondary_held = hold
	bot.submit_command(command)
	world.step(delta, true, 1)

func frames(count: int) -> void:
	for index: int in count: await get_tree().physics_frame
	await get_tree().process_frame

func energy() -> Vector2:
	var result := Vector2.ZERO
	var samples := capture.get_buffer(capture.get_frames_available())
	for sample: Vector2 in samples:
		check(sample.is_finite(), "Gun mixer samples remain finite")
		result += sample * sample
	return result

func quiet_buffer() -> void:
	await get_tree().create_timer(0.25).timeout
	capture.clear_buffer()

func report_at(view: BotView, at: Vector3) -> Vector2:
	await quiet_buffer()
	view.server_tick += 6
	view.shot_sequence += 1
	view.last_shot_tick = view.server_tick
	view.last_shot_from = at
	view.last_shot_to = at + Vector3.FORWARD * 15.0
	effects.show_state(view, 0.1)
	await get_tree().create_timer(0.25).timeout
	return energy()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run minigun audio integration with native rendering/audio")
		get_tree().quit(1)
		return
	AudioPreferences.ensure_buses()
	bus = AudioServer.get_bus_index("BBEffects")
	master = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioServer.set_bus_volume_db(master, -80.0)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(master, capture)
	get_viewport().audio_listener_enable_3d = true
	world = AuthorityWorld.new()
	add_child(world)
	bot = world.spawn(1, 0, 0, world.registry.scorpion())
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 2.9, 0))
	bot.spawn_pose = bot.body.reset_pose
	effects = bot.scorpion_visual.gun_effects
	sound = effects.weapon_audio
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 4, 9)
	camera.make_current()
	await frames(75)
	check(sound.played_count == 0 and not sound.motor.playing, "Idle and initial accepted snapshot are silent")
	check(sound.reports.size() == 4 and sound.get_child_count() == 5, "Minigun owns a fixed five-voice spatial pool")
	for player: AudioStreamPlayer3D in sound.reports:
		check(player.bus == &"BBEffects" and player.top_level, "Reports use the shared Effects gain and world positions")
		check(player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Mechanical reports cannot loop")
	capture.clear_buffer()
	hold = true
	await frames(75)
	var firing := energy()
	check(bot.combat.shot_sequence >= 5 and sound.played_count >= 5, "Real auxiliary commands spool and fire accepted authoritative reports")
	check(sound.motor.playing and sound.motor_level > 0.9, "Accepted spool runs the mechanical motor loop")
	check(firing.x + firing.y > 0.01, "Actual native mixer receives sustained minigun firing")
	check(sound.get_child_count() == 5, "Sustained fire reuses bounded voices")
	hold = false
	await frames(75)
	check(not sound.motor.playing and sound.motor_level < 0.025, "Released barrel coasts down to silence")
	stepping = false
	bot.set_process(false)
	var view := bot.read_view()
	view.secondary_charge = 0.0
	view.weapon_charge_fraction = 0.0
	view.server_tick += 100
	effects.clear_effects()
	effects.show_state(view, 0.1)
	await quiet_buffer()
	view.server_tick += 1
	effects.show_state(view, 0.1)
	await get_tree().create_timer(0.2).timeout
	check(energy().length_squared() < 0.000001, "Released idle produces no mixer output")
	camera.global_transform = Transform3D.IDENTITY
	var left := await report_at(view, Vector3(-4, 0, -4))
	var right := await report_at(view, Vector3(4, 0, -4))
	check(left.x > left.y * 1.2 and right.y > right.x * 1.2, "Fresh accepted reports pan to their real world origin")
	var near := await report_at(view, Vector3(0, 0, -3))
	var far := await report_at(view, Vector3(0, 0, -35))
	check(near.x + near.y > (far.x + far.y) * 4.0, "Minigun report attenuates across the arena")
	var played := sound.played_count
	view.shot_sequence += 4
	view.last_shot_tick = view.server_tick - 60
	effects.show_state(view, 0.1)
	check(sound.played_count == played, "Old batched snapshots never replay historical shots")
	view.server_tick -= 1
	view.secondary_charge = 1.0
	effects.show_state(view, 0.1)
	check(not sound.motor.playing and sound.played_count == played, "Rollback silences motor and reports")
	for index: int in 20: effects.show_state(view, 1.0 / 60.0)
	check(not sound.motor.playing, "Frozen snapshot cannot restart a spool loop")
	view.server_tick += 2
	effects.show_state(view, 0.1)
	check(sound.motor.playing, "Fresh continuing accepted state can resume spool")
	for index: int in 25: effects.show_state(view, 1.0 / 60.0)
	check(not sound.motor.playing, "Snapshot timeout stops the motor even at stale full charge")
	view.eliminated = true
	view.server_tick += 1
	view.shot_sequence += 1
	view.last_shot_tick = view.server_tick
	effects.show_state(view, 0.1)
	check(not sound.motor.playing and sound.played_count == played, "Elimination cannot emit a pending report or motor noise")
	check(sound.reports.all(func(player: AudioStreamPlayer3D) -> bool: return not player.playing), "Elimination immediately clears report tails")
	view.eliminated = false
	effects.clear_effects()
	effects.show_state(view, 0.1)
	check(not sound.motor.playing and sound.played_count == played, "Same-pose restart establishes a silent baseline")
	view.secondary_charge = 0.0
	view.server_tick += 1
	effects.show_state(view, 0.1)
	AudioServer.set_bus_volume_linear(bus, 0.0)
	var muted := await report_at(view, Vector3(0, 0, -3))
	check(muted.length_squared() < 0.000001, "Effects volume zero silences the actual downstream mixer")
	AudioServer.set_bus_volume_linear(bus, 1.0)
	view.secondary_charge = 1.0
	view.server_tick += 1
	effects.show_state(view, 0.1)
	check(sound.motor.playing and sound.is_in_group(&"bot_action_audio"), "Active minigun registers for the app's existing action-audio gate")
	played = sound.played_count
	sound.set_playback_enabled(false)
	check(not sound.motor.playing, "Menu/settings gate immediately stops the running motor")
	view.server_tick += 1
	view.shot_sequence += 1
	view.last_shot_tick = view.server_tick
	effects.show_state(view, 0.1)
	check(sound.played_count == played and not sound.motor.playing, "Covered gameplay stays silent while accepted shots continue")
	sound.set_playback_enabled(true)
	view.server_tick += 1
	effects.show_state(view, 0.1)
	check(not sound.motor.playing and sound.played_count == played, "Resuming gameplay first establishes a silent fresh baseline")
	view.server_tick += 1
	effects.show_state(view, 0.1)
	check(sound.motor.playing and sound.played_count == played, "Fresh resumed spool runs without replaying menu-time reports")
	effects.clear_effects()
	# The generic primary uses this exact shared effects/audio implementation.
	var primary := MvpWeaponVisual.new()
	add_child(primary)
	primary.assemble("minigun", Vector3(4.8, 1.5, 6.0))
	var generic := primary.gun_effects
	var primary_view := BotView.new()
	primary_view.entity_id = 2
	primary_view.server_tick = 100
	primary_view.weapon_charge_fraction = 1.0
	generic.show_state(primary_view, 0.1, true)
	check(not generic.weapon_audio.motor.playing, "Generic primary initial state is equally silent")
	primary_view.server_tick += 1
	generic.show_state(primary_view, 0.1, true)
	check(generic.weapon_audio.motor.playing, "Generic primary reads its accepted primary spool")
	primary_view.shot_sequence = 1
	primary_view.last_shot_tick = primary_view.server_tick
	primary_view.last_shot_from = Vector3(0, 0, -3)
	primary_view.last_shot_to = Vector3(0, 0, -20)
	generic.show_state(primary_view, 0.1, true)
	check(generic.weapon_audio.played_count == 1, "Generic primary gets the same fresh spatial report")
	generic.clear_effects()
	check(not generic.weapon_audio.motor.playing, "Generic primary reset stops its motor")
	primary_view.entity_id = 0
	primary_view.server_tick += 1
	generic.show_state(primary_view, 0.1, true)
	primary_view.server_tick += 1
	generic.show_state(primary_view, 0.1, true)
	check(not generic.weapon_audio.motor.playing, "Garage/mock view cannot synthesize running-weapon audio")
	print("MINIGUN AUDIO CAPTURE firing=", firing, " left=", left, " right=", right, " near=", near, " far=", far, " reports=", sound.played_count)
	primary.queue_free()
	bot = null
	world.queue_free()
	await get_tree().process_frame
	AudioServer.remove_bus_effect(master, AudioServer.get_bus_effect_count(master) - 1)
	for message: String in failures: push_error(message)
	print("MINIGUN AUDIO PASS" if failures.is_empty() else "MINIGUN AUDIO FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
