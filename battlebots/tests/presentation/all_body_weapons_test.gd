extends Node3D

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var registry := ContentRegistry.new()
	var draft := SawbladeConfig.starter(registry)
	for size: Vector3 in [Vector3(1.4, 0.5, 1.8), Vector3(1.8, 0.6, 2.4), Vector3(4.8, 1.5, 6.0), Vector3(5.4, 1.5, 7.2)]:
		for weapon: String in ["saw", "hammer", "lifter", "vertical_spinner", "horizontal_spinner"]:
			draft.parts.weapon = weapon
			var visual := SawbladeVisual.new()
			add_child(visual)
			visual.assemble(draft, size)
			for module: String in ["saw", "hammer", "ramp"]:
				check(visual.nodes["Module_weapon_" + module].visible == (module == SawbladeConfig.WEAPONS.get(weapon, "")), weapon + " only equipped authored weapon visible")
			check(visual.nodes.SawbladeTank_ROOT.visible, weapon + " keeps authored body")
			if not SawbladeConfig.WEAPONS.has(weapon):
				var fallback := visual.fallback_weapon
				check(fallback != null and fallback.kind == weapon, "Canonical spinner assembled")
				var geometry_scale := BotScale.from_size(size)
				check(fallback.global_basis.is_equal_approx(Basis.IDENTITY.scaled(Vector3.ONE * geometry_scale)),
					"Spinner composes physical dimensions without inherited authored scale")
				check(fallback.global_position.is_zero_approx(), "Spinner keeps canonical body origin")
				var rotor: MeshInstance3D = fallback.mechanism.get_child(0)
				var disc: CylinderMesh = rotor.mesh
				var expected_radius := 0.36 * geometry_scale if weapon == "vertical_spinner" else size.x * 0.65
				check(is_equal_approx(disc.top_radius * rotor.global_basis.x.length(), expected_radius),
					"Actual composed spinner radius matches physical weapon geometry")
				var view := BotView.new()
				view.weapon_charge_fraction = 1
				var before := fallback.mechanism.basis
				visual.show_state(view, 0.1)
				check(not fallback.mechanism.basis.is_equal_approx(before), "Spinner responds to charge")
				view.weapon_state = "disabled"
				before = fallback.mechanism.basis
				visual.show_state(view, 0.1)
				check(fallback.mechanism.basis.is_equal_approx(before), "Disabled spinner stops")
			else:
				check(visual.fallback_weapon == null, "Authored weapon has no duplicate mechanism")
			check(visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "Appearance adds no collision")
			visual.free()
	var preview := GarageBotPreview.new()
	add_child(preview)
	draft.parts.chassis = "balanced"
	for drive: String in ["agile", "standard_wheels", "traction", "walker"]:
		for weapon: String in ["saw", "hammer", "lifter", "vertical_spinner", "horizontal_spinner"]:
			draft.parts.drive = drive
			draft.parts.weapon = weapon
			check(registry.validate(draft).valid, drive + "/" + weapon + " is legal")
			preview.show_loadout(draft)
			check(preview.sawblade_visual != null, "Real garage preserves authored body")
			if preview.sawblade_visual != null:
				check((preview.sawblade_visual.walker_legs != null) == (drive == "walker"), "Garage shows equipped locomotion")
			if DisplayServer.get_name() != "headless":
				var bot := MvpBot.create(1, 0, draft, registry)
				check(bot != null, "Real bot accepts equipped build")
				if bot != null:
					bot.simulated = false
					add_child(bot)
					check(bot.sawblade_visual != null, "Runtime preserves authored body")
					check((bot.sawblade_visual.fallback_weapon != null) == not SawbladeConfig.WEAPONS.has(weapon), "Runtime equips requested weapon")
					bot.queue_free()
					await get_tree().process_frame
	preview.free()
	await get_tree().process_frame
	if failures.is_empty(): print("ALL BODY WEAPONS PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
