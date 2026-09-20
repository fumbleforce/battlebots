extends SceneTree
var failures := 0
var detector := CombatAudioStatus.new()
var tick := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func view(charge := 0.0, state := &"active", cooldown := 0.0) -> BotView:
	tick += 1
	var result := BotView.new()
	result.entity_id = 1
	result.server_tick = tick
	result.weapon_charge_fraction = charge
	result.weapon_state = state
	result.weapon_cooldown = cooldown
	result.zones = {"front": 100.0, "rear": 100.0, "left": 100.0, "right": 100.0}
	return result

func ready_cases() -> void:
	for family in ["vertical_spinner", "horizontal_spinner", "lifter", "saw"]:
		detector.reset()
		check(detector.observe(view(1.0), family).is_empty(), family + " full initial state silent")
		check(detector.observe(view(1.0), family).is_empty(), family + " held status silent")
		detector.observe(view(0.0), family)
		var result := detector.observe(view(1.0), family)
		var caption := "Saw running" if family == "saw" else ("Lift charged" if family == "lifter" else "Spinner at full speed")
		check(result == [{"cue": "weapon_ready", "caption": caption}], family + " precise active edge")
		detector.observe(view(0.95), family)
		check(detector.observe(view(1.0), family).is_empty(), family + " charge jitter does not repeat")
		detector.observe(view(0.0), family)
		check(detector.observe(view(1.0, &"disabled"), family).is_empty(), family + " disabled state never ready")
		check(detector.observe(view(1.0), family).size() == 1, family + " active state completes armed crossing")
	detector.reset()
	detector.observe(view(0.95), "lifter")
	check(detector.observe(view(1.0), "lifter").size() == 1, "Near-full initial baseline can complete normally")
	detector.observe(view(0.89), "lifter")
	check(detector.observe(view(1.0), "lifter").size() == 1, "Charge below hysteresis rearms")
	detector.reset()
	detector.observe(view(0.0), "saw")
	detector.observe(view(1.0), "saw")
	detector.observe(view(0.1), "saw")
	check(detector.observe(view(1.0), "saw").is_empty(), "Saw rearms only at zero")
	detector.reset()
	detector.observe(view(1.0, &"idle"), "hammer")
	check(detector.observe(view(1.0, &"idle"), "hammer").is_empty(), "Hammer readiness charge is not cooldown completion")
	detector.observe(view(0.0, &"cooldown", 0.2), "hammer")
	check(detector.observe(view(0.0, &"idle"), "hammer") == [{"cue": "weapon_ready", "caption": "Hammer cooldown complete"}], "Hammer cooldown reaches idle")
	detector.observe(view(0.0, &"cooldown", 0.2), "hammer")
	check(detector.observe(view(0.0, &"overheated"), "hammer").is_empty(), "Hammer cooldown zero while overheated is silent")

func run() -> void:
	ready_cases()
	detector.reset()
	var intact := view()
	detector.observe(intact, "lifter")
	var broken := view(1.0)
	broken.zones.front = 0.0
	broken.zones.right = 0.0
	var events := detector.observe(broken, "lifter")
	check(events.size() == 2 and events[0] == {"cue": "armor_break", "caption": "Armor breached: front, right"}, "Simultaneous panels combine while weapon event survives")
	check(detector.observe(broken, "lifter").is_empty(), "Repeated tick ignored")
	check(detector.observe(intact, "lifter").is_empty(), "Backward tick cannot restore baseline")
	broken.server_tick += 1
	check(detector.observe(broken, "lifter").is_empty(), "Broken panel remains silent")
	tick = broken.server_tick
	detector.observe(view(), "lifter")
	broken.server_tick = tick + 1
	check(detector.observe(broken, "lifter").size() == 2, "Repair and recharge rearm both edges")
	tick = broken.server_tick
	var malformed := view()
	malformed.zones = {"front": NAN, "rear": -1, "left": "bad"}
	malformed.weapon_charge_fraction = NAN
	check(detector.observe(malformed, "lifter").is_empty(), "Malformed values invalidate independent baselines")
	broken.server_tick = tick + 1
	check(detector.observe(broken, "lifter").is_empty(), "Restoring full/broken state after invalid data is silent")
	tick = broken.server_tick
	var eliminated := view()
	eliminated.eliminated = true
	detector.observe(eliminated, "lifter")
	broken.server_tick = tick + 1
	check(detector.observe(broken, "lifter").is_empty(), "Elimination clears baselines")
	tick = broken.server_tick
	detector.reset()
	check(detector.observe(broken, "lifter").is_empty(), "Round reset silent baseline")
	broken.server_tick += 1
	check(detector.observe(broken, "saw").is_empty(), "Family change silent baseline")
	broken.entity_id = 2
	broken.server_tick += 1
	check(detector.observe(broken, "saw").is_empty(), "Identity change silent baseline")
	check(detector.observe(null, "saw").is_empty(), "Missing view invalidates baseline")
	detector.reset()
	detector.observe(view(0.0, &"cooldown", 2.0), "hammer")
	detector.observe(view(0.0, &"idle", NAN), "hammer")
	check(detector.observe(view(0.0, &"idle"), "hammer").is_empty(), "Invalid hammer cooldown cannot later cause fake completion")
	detector.reset()
	detector.observe(view(0.0), "lifter")
	detector.observe(view(1.0, &"unknown"), "lifter")
	check(detector.observe(view(1.0), "lifter").is_empty(), "Invalid state invalidates weapon baseline")
	print("COMBAT_AUDIO_STATUS_PASS" if failures == 0 else "COMBAT_AUDIO_STATUS_FAIL")
	quit(0 if failures == 0 else 1)
