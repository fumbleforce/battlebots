extends SceneTree
## Real input gate -> wire codec -> MvpBot authority, plus menu/focus cancellation.
const STEP := 1.0 / 60.0
var failures := 0
var sequence := 1
var bot: MvpBot

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func transmit(command: BotCommand, active := true) -> void:
	command.sequence = sequence
	sequence += 1
	var decoded := WireCodec.command_from_array(WireCodec.command_to_array(command))
	check(decoded != null and decoded.auxiliary_held == command.auxiliary_held,
		"Wire preserves the explicit auxiliary flag")
	bot.submit_command(decoded)
	bot.step(STEP, active)

func gate(toggle := false) -> GameplayInputGate:
	var result := GameplayInputGate.new()
	result.auxiliary_weapon = true
	result.toggle_primary = toggle
	result.sample({}, {}, true)
	return result

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var registry := ContentRegistry.new()
	bot = MvpBot.create(1, 0, registry.scorpion(), registry)
	bot.name = "Bot"
	world.add_child(bot)
	bot.body.freeze = true
	await process_frame
	check(bot.read_view().has_auxiliary_weapon, "Canonical bot view exposes auxiliary gun capability")
	for toggle: bool in [false, true]:
		bot.combat = CombatState.new(bot.combat.stats)
		var input := gate(toggle)
		for frame: int in 36:
			var intent := input.sample({&"primary": 1.0, &"secondary": 1.0},
				{&"primary": frame == 0}, true)
			transmit(intent)
		check(bot.combat.attack_id == 1 and bot.combat.shot_sequence == 1,
			"Hold/toggle mode %s permits a real LMB hammer edge together with RMB gun" % toggle)
		check(bot.command.auxiliary_held, "MvpBot copies explicit gun intent from wire")
		transmit(input.sample({&"secondary": 1.0}, {}, true))
		check(bot.combat.attack_id == 1, "Releasing LMB while holding gun does not invent hammer attacks")
		var shots := bot.combat.shot_sequence
		transmit(input.sample({&"secondary": 1.0}, {}, false))
		check(not bot.command.auxiliary_held and bot.command.secondary_held and not bot.combat.gun_shot,
			"Suppressed menu command preserves cancellation but never auxiliary fire")
		for frame: int in 40:
			transmit(input.sample({&"secondary": 1.0}, {}, true))
		check(bot.combat.shot_sequence == shots and bot.combat.secondary_charge == 0.0,
			"RMB held through resume stays blocked until physical release")
		transmit(input.sample({}, {}, true))
		for frame: int in 36:
			transmit(input.sample({&"secondary": 1.0}, {}, true))
		check(bot.combat.shot_sequence == shots + 1, "Fresh RMB after release rearms the gun")
		input.require_release()
		transmit(input.sample({&"secondary": 1.0}, {}, true))
		check(not bot.command.auxiliary_held and not bot.combat.gun_shot,
			"Focus/rebind release barrier immediately blocks existing RMB hold")
	var legacy := GameplayInputGate.new()
	legacy.sample({}, {}, true)
	check(not legacy.sample({&"secondary": 1.0}, {}, true).auxiliary_held,
		"Bots without auxiliary capability preserve ordinary secondary cancellation")
	check(WireCodec.command_from_array([1, 0.0, 0.0, 512]) == null,
		"Unknown command flag bits are rejected")
	var cancel := BotCommand.new()
	cancel.secondary_held = true
	check(not WireCodec.command_from_array(WireCodec.command_to_array(cancel)).auxiliary_held,
		"Legacy secondary bit cannot be interpreted as auxiliary fire")
	bot.combat = CombatState.new(bot.combat.stats)
	var trigger := BotCommand.new()
	trigger.auxiliary_held = true
	trigger.secondary_held = true
	for frame: int in 36:
		transmit(trigger)
	check(bot.combat.shot_sequence == 1, "Timeout fixture starts with actual powered gun")
	for frame: int in 17: bot.step(STEP, true)
	var timed_out := bot.combat.shot_sequence
	check(bot.input_age >= 0.25 and not bot.command.auxiliary_held and bot.command.secondary_held,
		"Quarter-second input timeout clears gun intent while retaining safe weapon cancel")
	for frame: int in 60: bot.step(STEP, true)
	check(bot.combat.shot_sequence == timed_out and bot.combat.secondary_charge == 0.0,
		"Timed-out gun neither keeps firing nor respools")
	var packet := WireCodec.encode_bot(bot, "fixture:1")
	check(packet.size() <= 1200, "Extended gun snapshot stays inside existing packet limit")
	var decoded := WireCodec.decode_bot(packet, bot.combat.stats)
	check(decoded.shot_sequence == bot.combat.shot_sequence and decoded.secondary_charge == 0.0,
		"Gun counters and stopped rotor survive snapshot encode/decode")
	for item: Array in [[29, NAN], [29, 1.1], [30, 1], [31, -1], [32, Vector3(INF, 0, 0)], [33, Vector3(1000, 0, 0)], [34, -2], [35, NAN], [35, 1.1]]:
		var malformed: Array = bytes_to_var(packet)
		malformed[item[0]] = item[1]
		check(WireCodec.decode_bot(var_to_bytes(malformed), bot.combat.stats).is_empty(),
			"Malformed auxiliary/shot field is rejected: " + str(item[0]))
	var preview: Node3D = load("res://scenes/ui/baseline_preview.tscn").instantiate()
	preview.source_path = NodePath("../Bot")
	preview.settings_path = ""
	preview.sequence = sequence
	world.add_child(preview)
	preview.set_physics_process(false)
	preview._physics_process(STEP)
	check(preview.input_gate.auxiliary_weapon, "Actual preview reads auxiliary capability from BotView")
	preview.capture_controls()
	root.focus_exited.emit()
	bot.step(STEP, true)
	check(not preview.controls_enabled and not bot.command.auxiliary_held and not bot.combat.gun_shot,
		"Actual window focus-loss signal submits neutral gun command")
	preview.release_controls()
	bot.step(STEP, true)
	check(not bot.command.auxiliary_held and bot.command.secondary_held,
		"Actual menu release sends cancellation without gun intent")
	world.queue_free()
	await process_frame
	print("SCORPION INPUT PASS" if failures == 0 else "SCORPION INPUT FAIL")
	quit(0 if failures == 0 else 1)
