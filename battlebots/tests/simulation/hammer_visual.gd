extends SceneTree
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var visual := MvpWeaponVisual.new()
	root.add_child(visual)
	visual.assemble("hammer", Vector3(1.2, 0.5, 1.5))
	check(visual.mechanism.position.is_equal_approx(Vector3(0, 0.25, -0.6)), "Hammer mount matches overhead query")
	check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "Hammer visual cannot cause physics hits")
	var view := BotView.new()
	view.weapon_state = "windup"
	view.weapon_charge_fraction = 1.0
	visual.show_state(view, 1.0 / 60.0)
	check(is_equal_approx(visual.mechanism.rotation.x, PI / 2.0), "Windup lifts head overhead")
	view.weapon_state = "strike"
	view.weapon_cooldown = 1.4
	visual.show_state(view, 1.0 / 60.0)
	check(is_equal_approx(visual.mechanism.rotation.x, -PI / 6.0), "Strike reaches down-forward impact pose")
	view.weapon_state = "cooldown"
	view.weapon_cooldown = 0.7
	visual.show_state(view, 1.0 / 60.0)
	check(is_zero_approx(visual.mechanism.rotation.x), "Recovery steadily returns arm")
	view.weapon_state = "disabled"
	visual.show_state(view, 1.0 / 60.0)
	check(is_zero_approx(visual.mechanism.rotation.x), "Destroyed hammer rests")
	visual.queue_free()
	await process_frame
	print("HAMMER VISUAL PASS" if failures == 0 else "HAMMER VISUAL FAIL")
	quit(0 if failures == 0 else 1)
