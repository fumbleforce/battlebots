extends Node3D
## Imported articulated/telescopic mesh against the pure authoritative geometry.
var failures: Array[String] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	var registry := ContentRegistry.new()
	var draft := registry.scorpion()
	var size: Vector3 = registry.validate(draft).stats.size
	var visual := ScorpionVisual.new()
	add_child(visual)
	visual.assemble(draft, size)
	visual.position = Vector3(3.0, WalkerDrive.RIDE_HEIGHT, -2.0)
	visual.rotation.y = 0.6
	check(visual.nodes.has("TailExtension"), "Portable GLB contains the independently moving telescopic stage")
	if visual.nodes.has("TailExtension"):
		check(visual.nodes.HammerHead.get_parent() == visual.nodes.TailExtension,
			"Hammer wrist and forging ride on the sliding ram")
		check(visual.nodes.TailExtension.get_parent() == visual.nodes.TailFore,
			"Sliding ram remains mechanically attached to the final orange arm")
		var resting_origin := Vector3.ZERO
		var maximum_origin := Vector3.ZERO
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			visual.set_hammer_fraction(fraction)
			var actual: Vector3 = visual.nodes.HammerHead.global_transform * (ScorpionGeometry.HEAD_CENTER - ScorpionGeometry.HEAD_PIVOT)
			# Visual root already includes scale3; pure geometry applies scale3 once.
			var pose := Transform3D(visual.global_basis.orthonormalized(), visual.global_position)
			var expected := pose * ScorpionGeometry.hammer_transform(size, fraction).origin
			check(actual.distance_to(expected) < 0.005,
				"Imported forging center follows the same hinge+extension transform at %.2f" % fraction)
			var relative: Vector3 = visual.nodes.TailExtension.position - (ScorpionGeometry.HEAD_PIVOT - ScorpionGeometry.TAIL_FORE)
			check(is_equal_approx(relative.length(), ScorpionGeometry.hammer_extension(fraction)),
				"Visible ram travel equals authoritative extension at %.2f" % fraction)
			var head_basis: Basis = visual.nodes.HammerHead.global_basis.orthonormalized()
			check(head_basis.is_equal_approx(pose.basis), "Wrist keeps the forged striking head level through the stroke")
			if fraction == 0.0: resting_origin = visual.nodes.TailExtension.position
			if fraction == 1.0: maximum_origin = visual.nodes.TailExtension.position
		check(is_equal_approx(resting_origin.distance_to(maximum_origin) * BotScale.from_size(size), 0.66),
			"Nested shaft visibly extends sixty-six centimetres at full-size game scale")
		var contact := ScorpionGeometry.hammer_transform(size, 1.0).origin
		var lowest := WalkerDrive.RIDE_HEIGHT + contact.y - ScorpionGeometry.HEAD_SIZE.y * BotScale.from_size(size) * 0.5
		check(lowest > 0.02 and lowest < 0.35,
			"Full stroke reaches low NPC armor while retaining physical floor clearance")
		var view := BotView.new()
		view.weapon_state = &"windup"
		view.weapon_charge_fraction = 0.625
		visual.show_state(view, 1.0 / 60.0)
		check(visual.hammer_fraction > 0.4 and visual.hammer_fraction < 0.6,
			"Windup visibly feeds the extendible final arm")
		view.weapon_state = &"strike"
		visual.show_state(view, 1.0 / 60.0)
		check(visual.hammer_fraction == 1.0, "Confirmed impact displays full extension")
		view.weapon_state = &"cooldown"
		view.weapon_cooldown = 0.5
		visual.show_state(view, 1.0 / 60.0)
		check(visual.hammer_fraction < 1.0 and visual.hammer_fraction > 0.0,
			"Recovery retracts the chrome stage into its fixed gland")
		view.weapon_state = &"idle"
		view.weapon_cooldown = 0.0
		visual.show_state(view, 1.0 / 60.0)
		check(visual.hammer_fraction == 0.0 and visual.nodes.TailExtension.position.is_equal_approx(resting_origin),
			"Idle returns the nested piston to its exact parked pose")
	visual.queue_free()
	await get_tree().process_frame
	for message: String in failures: push_error(message)
	print("SCORPION TAIL PASS" if failures.is_empty() else "SCORPION TAIL FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
