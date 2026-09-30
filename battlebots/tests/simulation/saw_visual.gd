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
	var size := Vector3(1.6, 0.5, 2.0)
	visual.assemble("saw", size)
	# Every body mounts the Sawblade's authored blade where the authority sweeps it (#109).
	var axle := SawbladeGeometry.saw_axle({}, size)
	var blade_scale := SawbladeGeometry.saw_scale({}, size)
	check(visual.mechanism.global_position.is_equal_approx(axle), "Saw mount matches authoritative contact disc")
	check(axle.y + size.y * 0.5 - SawbladeGeometry.SAW_RADIUS * blade_scale.y > 0, "Saw teeth clear the floor on an upright chassis")
	check(axle.z + SawbladeGeometry.SAW_RADIUS * blade_scale.z < -size.z * 0.5, "Saw teeth clear the hull front")
	var teeth := 0
	var rim := 0.0
	for part: MeshInstance3D in visual.mechanism.find_children("*", "MeshInstance3D", true, false):
		if str(part.name).begins_with("Carbide cutting tooth"): teeth += 1
		var bounds := visual.global_transform.affine_inverse() * part.global_transform * part.get_aabb()
		rim = maxf(rim, maxf(bounds.end.y - axle.y, axle.z - bounds.position.z))
	check(teeth == 24, "Saw is the Sawblade body's toothed blade")
	check(absf(rim - SawbladeGeometry.SAW_RADIUS * blade_scale.z) < 0.01, "Blade rim matches the authoritative radius: %.3f" % rim)
	check(not visual.mechanism.get_child(0).get_surface_override_material(0) == null, "Borrowed saw takes the build's paint layers")
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
