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
	visual.assemble("saw", Vector3(1.6, 0.5, 2.0))
	check(visual.mechanism.position.is_equal_approx(Vector3(0, 0.1, -1.4)), "Saw mount matches authoritative contact disc")
	check(visual.mechanism.position.y + 0.25 - 0.32 > 0, "Saw teeth clear the floor on an upright chassis")
	check(visual.mechanism.get_child_count() == 13, "Saw has a distinct toothed blade")
	check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "Cosmetic saw adds no collision or damage")
	var view := BotView.new()
	view.weapon_state = "active"
	view.weapon_charge_fraction = 1.0
	visual.show_state(view, 1.0 / 60.0)
	check(absf(visual.mechanism.rotation.x) > 0.1, "Powered saw rotates around its axle")
	var before := visual.mechanism.rotation
	for phase: String in ["idle", "overheated", "disabled"]:
		view.weapon_state = phase
		visual.show_state(view, 1.0 / 60.0)
		check(visual.mechanism.rotation == before, "Saw stops in %s" % phase)
	view.weapon_state = "active"
	view.eliminated = true
	visual.show_state(view, 1.0 / 60.0)
	check(visual.mechanism.rotation == before, "Wrecked saw remains stopped")
	visual.queue_free()
	await process_frame
	print("SAW VISUAL PASS" if failures == 0 else "SAW VISUAL FAIL")
	quit(0 if failures == 0 else 1)
