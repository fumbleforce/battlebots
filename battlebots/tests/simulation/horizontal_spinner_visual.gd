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
	visual.assemble("horizontal_spinner", Vector3(1.6, 0.5, 2.0))
	check(visual.mechanism.position.is_equal_approx(Vector3(0, 0, -1.2)), "Horizontal disc sits on its combat mount")
	var disc: CylinderMesh = visual.mechanism.get_child(0).mesh
	check(is_equal_approx(disc.top_radius, 1.04), "Disc visibly spans the authored side reach")
	check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "Cosmetic rotor adds no physics colliders")
	var view := BotView.new()
	view.weapon_charge_fraction = 1
	view.weapon_state = "active"
	visual.show_state(view, 0.02)
	check(absf(visual.mechanism.rotation.y) > 0.1 and is_zero_approx(visual.mechanism.rotation.x), "Horizontal rotor spins around its upright axis")
	var previous := visual.mechanism.rotation
	view.weapon_state = "disabled"
	visual.show_state(view, 0.02)
	check(visual.mechanism.rotation == previous, "Disabled rotor stops")
	visual.queue_free()
	await process_frame
	print("HORIZONTAL VISUAL PASS" if failures == 0 else "HORIZONTAL VISUAL FAIL")
	quit(0 if failures == 0 else 1)
