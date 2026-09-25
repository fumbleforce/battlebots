extends SceneTree
## Floating damage numbers (#85): spray, merging, expiry, the feedback hook and
## the GAME settings toggle. Headless; no rendering is inspected.
const NUMBERS := preload("res://scripts/presentation/damage_numbers.gd")
const TUNING := preload("res://scripts/core/damage_number_tuning.gd")
const GAME_PREFERENCES := preload("res://scripts/ui/game_preferences.gd")
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
	var merge: float = tuning.value("timing", "merge_seconds")
	var numbers := NUMBERS.new()
	root.add_child(numbers)
	numbers.spawn(Vector3(0, 1, 0), Vector3.FORWARD, 24.4, 1, 2)
	check(numbers.live_count() == 1 and numbers.live_texts() == ["24"], "A hit shows its rounded damage")
	var label: Label3D = numbers.get_child(0)
	var start := label.position
	numbers.advance(0.2)
	check(label.position.distance_to(start) > 0.3, "The number flies away from the impact")
	check((label.position - start).dot(Vector3.FORWARD) > 0.0 and label.position.y > start.y, "It sprays outward along the normal and up")
	numbers.advance(merge * 0.5)
	numbers.spawn(Vector3(0, 1, 0), Vector3.FORWARD, 6.0, 7, 2)
	check(numbers.live_count() == 2, "Another attacker gets its own number")
	numbers.clear()
	numbers.spawn(Vector3.ZERO, Vector3.UP, 4.0, 1, 2)
	numbers.advance(merge * 0.5)
	numbers.spawn(Vector3.ZERO, Vector3.UP, 4.0, 1, 2)
	check(numbers.live_count() == 1 and numbers.live_texts() == ["8"], "Rapid hits from one attacker on one target merge")
	numbers.advance(merge * 1.5)
	numbers.spawn(Vector3.ZERO, Vector3.UP, 4.0, 1, 2)
	check(numbers.live_count() == 2, "A pause starts a new number")
	numbers.advance(lifetime + 0.05)
	check(numbers.live_count() == 0, "Numbers expire after their lifetime")
	for bad: Array in [[Vector3(NAN, 0, 0), Vector3.UP, 5.0], [Vector3.ZERO, Vector3(INF, 0, 0), 5.0],
		[Vector3.ZERO, Vector3.UP, NAN], [Vector3.ZERO, Vector3.UP, -3.0], [Vector3.ZERO, Vector3.UP, 0.0]]:
		numbers.spawn(bad[0], bad[1], bad[2])
	check(numbers.live_count() == 0, "Invalid or zero damage shows nothing")
	for index: int in int(tuning.value("text", "max_live")) + 5:
		numbers.spawn(Vector3.ZERO, Vector3.UP, 5.0)
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
	feedback.set_show_damage_numbers(false)
	check(feedback.damage_numbers.live_count() == 0, "Turning numbers off clears them")
	feedback.combat_event(hit(3, 4))
	check(feedback.damage_numbers.live_count() == 0, "Disabled numbers stay hidden")
	feedback.set_show_damage_numbers(true)
	feedback.combat_event(hit(4, 5))
	check(feedback.damage_numbers.live_count() == 1, "Re-enabled numbers show again")
	feedback.observe_match({"match_id":"practice", "round":1, "phase":"intermission", "event_id":2}, true)
	check(feedback.damage_numbers.live_count() == 0, "A phase change clears numbers")
	feedback.queue_free()

	# GAME settings persistence.
	var path := "user://damage_numbers_test_game.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var defaults: RefCounted = GAME_PREFERENCES.load_file(path)
	check(defaults.load_error == OK and defaults.show_damage_numbers, "Numbers default on")
	defaults.show_damage_numbers = false
	check(defaults.save_file(path) == OK, "Game settings save")
	var loaded: RefCounted = GAME_PREFERENCES.load_file(path)
	check(loaded.load_error == OK and not loaded.show_damage_numbers, "Toggle round-trips")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[game]\nversion=1\nshow_damage_numbers=\"yes\"\n")
	file.close()
	var bad: RefCounted = GAME_PREFERENCES.load_file(path)
	check(bad.load_error != OK and bad.show_damage_numbers, "A bad file falls back to defaults")
	check(GAME_PREFERENCES.load_file("").load_error == ERR_INVALID_PARAMETER, "Empty path is refused")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	await process_frame
	for failure: String in failures: push_error(failure)
	print("DAMAGE NUMBERS PASS" if failures.is_empty() else "DAMAGE NUMBERS FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
