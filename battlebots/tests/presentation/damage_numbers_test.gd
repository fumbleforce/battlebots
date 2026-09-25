extends SceneTree
## Floating damage numbers (#85): spray, merging, expiry, the feedback hook and
## the GAME settings toggle. Headless; no rendering is inspected.
const NUMBERS := preload("res://scripts/presentation/damage_numbers.gd")
const TUNING := preload("res://scripts/core/damage_number_tuning.gd")
const GAME_PREFERENCES := preload("res://scripts/ui/game_preferences.gd")
const GAME_SETTINGS_PANEL := preload("res://scripts/ui/game_settings_panel.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func hit(id: int, attacker := 1, target := 2, damage := 18.0, kind := "cannon") -> Dictionary:
	return {"round":1, "event_id":id, "tick":60, "attacker":attacker, "target":target,
		"damage":damage, "kind":kind, "position":Vector3(2, 1, 3), "normal":Vector3.RIGHT}

func run() -> void:
	var tuning: RefCounted = TUNING.settings()
	check(tuning != null, "Tuning loads")
	check(TUNING.from_json("{}") == null and TUNING.from_json("[]") == null, "Malformed tuning is rejected")
	var lifetime: float = tuning.value("timing", "lifetime_seconds")
	var numbers := NUMBERS.new()
	root.add_child(numbers)
	numbers.spawn(Vector3(0, 1, 0), 24.4)
	check(numbers.live_count() == 1 and numbers.live_texts() == ["24"], "A hit shows its rounded damage")
	var label: Label3D = numbers.get_child(0)
	var start := label.position
	check(start.is_equal_approx(Vector3(0, 1, 0)), "The number starts at the impact point")
	numbers.advance(0.2)
	var moved := label.position - start
	check(moved.length() > 0.3 and moved.y > 0.0, "The number sprays up from the impact")
	for index: int in 8:
		numbers.spawn(Vector3.ZERO, 5.0)
	numbers.advance(0.2)
	var sideways := Vector3.ZERO
	for child: Node in numbers.get_children():
		if child != label: sideways += Vector3((child as Label3D).position.x, 0.0, (child as Label3D).position.z)
	check(sideways.length() < 0.5 * 8, "Sideways spray fans around the impact instead of one direction")
	numbers.clear()
	numbers.spawn(Vector3.ZERO, 4.0)
	numbers.spawn(Vector3.ZERO, 4.0)
	check(numbers.live_count() == 2 and numbers.live_texts() == ["4", "4"], "Every hit sprays its own number")
	numbers.advance(lifetime + 0.05)
	check(numbers.live_count() == 0, "Numbers expire after their lifetime")
	for bad: Array in [[Vector3(NAN, 0, 0), 5.0], [Vector3.ZERO, NAN], [Vector3.ZERO, -3.0], [Vector3.ZERO, 0.0]]:
		numbers.spawn(bad[0], bad[1])
	check(numbers.live_count() == 0, "Invalid or zero damage shows nothing")
	for index: int in int(tuning.value("text", "max_live")) + 5:
		numbers.spawn(Vector3.ZERO, 5.0)
	check(numbers.live_count() == int(tuning.value("text", "max_live")), "Live numbers are capped")
	check(NUMBERS.format(0.4) == "0.4" and NUMBERS.format(69.6) == "70", "Formatting")
	numbers.queue_free()

	# The hook: any accepted damaging kind, including turret shots with no sparks.
	var feedback := CombatImpactFeedback.new()
	root.add_child(feedback)
	feedback.observe_match({"match_id":"practice", "round":1, "phase":"active", "event_id":1}, true)
	feedback.combat_event(hit(1))
	check(feedback.damage_numbers.live_count() == 1 and feedback.visual.spark_count() == 0, "A cannon hit shows a number without melee sparks")
	feedback.combat_event(hit(1))
	check(feedback.damage_numbers.live_count() == 1, "A replayed event shows no second number")
	feedback.combat_event(hit(2, 3, 2, 0.0, "hammer"))
	check(feedback.damage_numbers.live_count() == 1, "A zero-damage hit shows no number")
	feedback.combat_event(hit(3, 1, 2, 5.0, "ram"))
	check(feedback.damage_numbers.live_count() == 2, "A ram without a client world still shows its number")
	feedback.set_damage_numbers(false, true)
	check(feedback.damage_numbers.live_count() == 0, "Turning numbers off clears them")
	feedback.combat_event(hit(4, 4))
	check(feedback.damage_numbers.live_count() == 0, "Disabled numbers stay hidden")
	# The local player's own bot has its own toggle.
	var session := MvpSession.new()
	session.local_entity = 2
	feedback.session = session
	feedback.combat_event(hit(5, 4))
	check(feedback.damage_numbers.live_count() == 1, "Hits on your bot follow the own-bot toggle")
	feedback.set_damage_numbers(true, false)
	feedback.combat_event(hit(6, 4))
	feedback.combat_event(hit(7, 2, 9))
	check(feedback.damage_numbers.live_count() == 1, "Own-bot numbers off hides only hits on your bot")
	feedback.session = null
	session.free()
	feedback.set_damage_numbers(true, true)
	feedback.observe_match({"match_id":"practice", "round":1, "phase":"intermission", "event_id":2}, true)
	check(feedback.damage_numbers.live_count() == 0, "A phase change clears numbers")
	feedback.queue_free()

	# GAME settings persistence.
	var path := "user://damage_numbers_test_game.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var defaults: RefCounted = GAME_PREFERENCES.load_file(path)
	check(defaults.load_error == OK and defaults.show_damage_numbers and defaults.show_player_damage_numbers and defaults.show_speedometer and defaults.show_speed_value, "Numbers and speedometer default on")
	defaults.show_damage_numbers = false
	defaults.show_speedometer = false
	defaults.show_speed_value = false
	check(defaults.save_file(path) == OK, "Game settings save")
	var loaded: RefCounted = GAME_PREFERENCES.load_file(path)
	check(loaded.load_error == OK and not loaded.show_damage_numbers and loaded.show_player_damage_numbers and not loaded.show_speedometer and not loaded.show_speed_value, "Toggles round-trip")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[game]
version=1
show_damage_numbers=true
")
	file.close()
	var older: RefCounted = GAME_PREFERENCES.load_file(path)
	check(older.load_error == OK and older.show_player_damage_numbers and older.show_speedometer and older.show_speed_value, "A file without the newer keys keeps their defaults")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[game]\nversion=1\nshow_damage_numbers=\"yes\"\n")
	file.close()
	var bad: RefCounted = GAME_PREFERENCES.load_file(path)
	check(bad.load_error != OK and bad.show_damage_numbers, "A bad file falls back to defaults")
	check(GAME_PREFERENCES.load_file("").load_error == ERR_INVALID_PARAMETER, "Empty path is refused")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# GAME page: each toggle's caption states its value.
	var panel: PanelContainer = GAME_SETTINGS_PANEL.new()
	root.add_child(panel)
	var shown: RefCounted = GAME_PREFERENCES.create()
	shown.show_player_damage_numbers = false
	shown.show_speedometer = false
	panel.open_for(shown, path)
	check(panel.damage_numbers_toggle.text == "On" and panel.player_numbers_toggle.text == "Off" and panel.speedometer_toggle.text == "Off" and panel.speed_value_toggle.text == "On", "Captions show each toggle's state")
	panel.damage_numbers_toggle.button_pressed = false
	check(panel.damage_numbers_toggle.text == "Off", "Caption follows a click")
	panel.cancel()
	panel.queue_free()

	await process_frame
	for failure: String in failures: push_error(failure)
	print("DAMAGE NUMBERS PASS" if failures.is_empty() else "DAMAGE NUMBERS FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
