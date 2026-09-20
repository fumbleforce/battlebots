extends Node3D
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _ready() -> void:
	var registry := ContentRegistry.new()
	var draft := SawbladeConfig.starter(registry)
	for drive: String in ["agile", "standard_wheels", "traction", "walker"]:
		for weapon: String in ["saw", "hammer", "lifter", "vertical_spinner", "horizontal_spinner"]:
			draft.parts.drive = drive
			draft.parts.weapon = weapon
			var visual := SawbladeVisual.new()
			add_child(visual)
			visual.assemble(draft, Vector3(1.6, 0.5, 2.0))
			var groups := visual.component_meshes()
			var seen: Dictionary = {}
			for zone: String in ["weapon", "drive_left", "drive_right"]:
				check(not groups[zone].is_empty(), drive + "/" + weapon + " maps " + zone)
				for mesh: MeshInstance3D in groups[zone]:
					check(not seen.has(mesh), "No mesh belongs to two components")
					seen[mesh] = true
					check(mesh.is_visible_in_tree(), "Only equipped visible mechanisms mapped")
					if zone == "weapon":
						var root: Node3D = visual.fallback_weapon if visual.fallback_weapon != null else visual.nodes["Module_weapon_" + SawbladeConfig.WEAPONS[weapon]]
						check(root == mesh or root.is_ancestor_of(mesh), "Weapon mapping excludes chassis")
					elif drive != "walker":
						var center := visual.to_local(mesh.to_global(mesh.get_aabb().get_center()))
						check(center.x < 0 if zone == "drive_left" else center.x > 0, "Drive side follows actual mesh bounds")
			if drive == "walker":
				var total := visual.walker_legs.find_children("*", "MeshInstance3D", true, false).size()
				check(groups.drive_left.size() + groups.drive_right.size() == total, "All walker meshes including hip joints mapped")
				for leg: Dictionary in visual.walker_legs.legs:
					for mesh: MeshInstance3D in leg.hip_joint.find_children("*", "MeshInstance3D", true, false):
						check(mesh in groups["drive_left" if leg.side < 0 else "drive_right"], "Hip follows its logical pod")
			var view := BotView.new()
			view.weapon_state = "active"
			view.weapon_charge_fraction = 1
			visual.show_state(view, 0.25)
			visual.advance_drive(0.5, -0.3)
			check(visual.component_meshes() == groups, "Animation preserves component membership")
			groups.weapon.clear()
			check(not visual.component_meshes().weapon.is_empty(), "Caller arrays are detached")
			visual.free()
	if failures.is_empty(): print("COMPONENT MESH MAPPING PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
