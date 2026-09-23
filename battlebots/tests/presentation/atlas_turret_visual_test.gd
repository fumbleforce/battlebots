extends Node3D
## The imported turret GLB must agree with the authoritative ray geometry, and
## presentation must follow accepted servo/shot state only.
var failures := 0
var registry := ContentRegistry.new()

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func build(kind: String) -> Dictionary:
	var draft := registry.atlas()
	draft.parts.utility = "turret_" + kind
	if kind.ends_with("_quad"): draft.parts.armor = "light"
	return draft

func view_for(yaw: float, pitch: float, sequence := 0, tick := 10) -> BotView:
	var view := BotView.new()
	view.turret_kind = "cannon"
	view.turret_yaw = yaw
	view.gun_pitch = pitch
	view.shot_sequence = sequence
	view.server_tick = tick
	view.last_shot_tick = tick if sequence > 0 else -1
	view.last_shot_from = Vector3(0, 2, -5)
	view.last_shot_to = Vector3(0, 2, -60)
	return view

func run() -> void:
	var size: Vector3 = registry.validate(registry.atlas()).stats.size
	for kind: String in ["cannon", "plasma"]:
		var visual := AtlasVisual.new()
		add_child(visual)
		var draft := build(kind)
		var config := AtlasGeometry.paint_defaults()
		config.exhaust = 3
		config.armor_top = 1
		config.paint_primary = [0.1, 0.4, 0.8, 1.0]
		draft.cosmetics.sawblade = config
		visual.assemble(draft, size)
		check(visual.turret != null and visual.turret_kind == kind, "Atlas assembles the %s turret" % kind)
		if visual.turret == null:
			continue
		for label: String in AtlasVisual.TURRET_HIDDEN:
			check(not visual.nodes[label].visible, label + " is hidden under the fitted turret")
		var cannon: Node3D = visual.turret.find_child("AttachmentCannon", true, false)
		var plasma: Node3D = visual.turret.find_child("AttachmentPlasma", true, false)
		check(cannon.visible == (kind == "cannon") and plasma.visible == (kind == "plasma"), "Only the chosen attachment shows")
		var weapon_meshes: Array = visual.component_meshes().weapon
		var housing := visual.turret.find_child("TurretYawSurface", true, false)
		check(housing != null and weapon_meshes.has(housing), "Turret meshes join the weapon damage group")
		for pose: Vector2 in [Vector2.ZERO, Vector2(1.1, 0.3), Vector2(-2.6, -0.08)]:
			var view := view_for(pose.x, pose.y)
			view.turret_kind = kind
			visual.reset_observation()
			visual.show_state(view, 1.0 / 60.0)
			var muzzle: Node3D = visual.turret.find_child("MuzzleCannon" if kind == "cannon" else "MuzzlePlasma", true, false)
			var expected := AtlasGeometry.turret_muzzle(size, kind, pose.x, pose.y)
			check(muzzle.global_position.distance_to(expected) < 0.01,
				"%s muzzle matches the authoritative ray at %s: %s vs %s" % [kind, pose, muzzle.global_position, expected])
			var trunnion: Node3D = visual.turret.find_child("TurretPitch", true, false)
			check(trunnion.global_position.distance_to(AtlasGeometry.turret_breech(size, pose.x)) < 0.01,
				"Trunnion matches the authoritative breech at %s" % pose)
		# Remote 20 Hz steps are smoothed, never overshooting the accepted angle.
		visual.show_state(view_for(0.0, 0.0, 0, 20), 1.0 / 60.0)
		visual.show_state(view_for(0.5, 0.0, 0, 21), 1.0 / 60.0)
		var yaw_node: Node3D = visual.turret.find_child("TurretYaw", true, false)
		var shown := yaw_node.basis.get_euler().y
		check(shown > 0.0 and shown < 0.5, "Presentation slews toward a new snapshot angle: %f" % shown)
		# Between 60 Hz samples of a steady traverse, render frames keep moving
		# forward in small even steps instead of stopping and jumping.
		visual.reset_observation()
		var steps: Array[float] = []
		var last := 0.0
		for frame: int in 24:
			var tick := 30 + frame / 4
			visual.show_state(view_for(0.03 * float(frame / 4), 0.0, 0, tick), 1.0 / 240.0)
			var now := yaw_node.basis.get_euler().y
			if frame >= 8: steps.append(now - last)
			last = now
		check(steps.min() > 0.0, "Turret keeps moving between authoritative samples: %s" % [steps])
		# Shots: a baseline is silent; a new accepted shot animates once.
		visual.reset_observation()
		visual.show_state(view_for(0.0, 0.0, 4, 10), 1.0 / 60.0)
		var effects := visual.turret_effects
		check(effects.shot_count == 0, "Initial shot baseline replays nothing")
		visual.show_state(view_for(0.0, 0.0, 5, 11), 1.0 / 60.0)
		check(effects.shot_count == 1, "A new accepted shot fires one effect")
		if kind == "cannon":
			var recoil: Node3D = visual.turret.find_child("CannonRecoil", true, false)
			visual.show_state(view_for(0.0, 0.0, 5, 12), 0.02)
			check(recoil.position.z > 0.05, "Cannon barrel recoils rearward")
			for index: int in 40: visual.show_state(view_for(0.0, 0.0, 5, 12), 0.02)
			check(recoil.position.z < 0.001, "Recoil returns to battery")
		visual.show_state(view_for(0.0, 0.0, 5, 13), 1.0 / 60.0)
		check(effects.shot_count == 1, "Repeated snapshots never replay a shot")
		visual.queue_free()
	await get_tree().process_frame
	await upgrades(size)
	print("ATLAS TURRET VISUAL PASS" if failures == 0 else "ATLAS TURRET VISUAL FAIL")
	get_tree().quit(0 if failures == 0 else 1)

## Every barrel's muzzle in the GLB matches the authoritative per-barrel ray.
func upgrades(size: Vector3) -> void:
	for model: String in ["cannon_dual", "cannon_quad", "plasma_dual", "plasma_quad"]:
		var visual := AtlasVisual.new()
		add_child(visual)
		visual.assemble(build(model), size)
		check(visual.turret_model == model, "Atlas assembles the %s upgrade" % model)
		var family := model.get_slice("_", 0)
		var suffix := model.get_slice("_", 1).capitalize()
		var chosen: Node3D = visual.turret.find_child("Attachment" + family.capitalize() + suffix, true, false)
		var single: Node3D = visual.turret.find_child("Attachment" + family.capitalize(), true, false)
		check(chosen != null and chosen.visible and not single.visible, "%s shows only its multi-barrel attachment" % model)
		var pose := Vector2(0.7, 0.2)
		var view := view_for(pose.x, pose.y)
		view.turret_kind = family
		visual.reset_observation()
		visual.show_state(view, 1.0 / 60.0)
		var barrels: Array = AtlasGeometry.TURRET_BARRELS[model]
		for index: int in barrels.size():
			var muzzle: Node3D = visual.turret.find_child("Muzzle%s%s_%d" % [family.capitalize(), suffix, index], true, false)
			var expected := AtlasGeometry.turret_muzzle(size, family, pose.x, pose.y, AtlasGeometry.turret_barrel(model, index + 1))
			check(muzzle != null and muzzle.global_position.distance_to(expected) < 0.01,
				"%s barrel %d muzzle matches the authoritative ray" % [model, index])
		check(visual.turret_effects.muzzles.size() == barrels.size(), "%s effects know every muzzle" % model)
		visual.queue_free()
		await get_tree().process_frame
