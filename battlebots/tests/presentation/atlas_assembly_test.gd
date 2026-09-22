extends Node3D
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var registry := ContentRegistry.new()
	var original: Dictionary = registry.atlas()
	for weapon: String in ["lifter", "saw", "hammer", "vertical_spinner", "horizontal_spinner", "minigun"]:
		var draft := original.duplicate(true)
		draft.parts.weapon = weapon
		draft.parts.armor = "light"
		draft.parts.utility = "minigun_pod" if weapon != "minigun" else "cooling_pack"
		var visual := AtlasVisual.new()
		add_child(visual)
		visual.assemble(draft, registry.validate(draft).stats.size)
		check(visual.nodes.has("Hull") and visual.nodes.has("DriveLeft") and visual.nodes.has("DriveRight"),
			"Imported Atlas retains independently damageable body and drives")
		for socket: String in ["MountPrimary", "MountTopFront", "MountTopRear", "MountAuxiliary", "MountRear", "MountSideLeft", "MountSideRight"]:
			check(visual.nodes.has(socket), "Authored modular mount is exported: " + socket)
		check(visual._links.size() == 80, "Both tracked drives contain forty independently moving shoes")
		check(visual._wheels.size() >= 10, "Only wheel pivots animate, never their child meshes")
		check(visual.primary.kind == weapon, "Equipped primary is the actual rendered mechanism")
		if weapon == "lifter":
			check(visual.primary.mechanism.get_node_or_null("AtlasLifterAttachment") != null,
				"The default front lifter uses the high-quality authored attachment")
		check((visual.auxiliary != null) == (weapon != "minigun"), "Auxiliary socket follows the installed part")
		var gun := visual.primary if weapon == "minigun" else visual.auxiliary
		var muzzle: Vector3 = gun.gun_effects.muzzle.global_position
		var expected: Vector3 = visual.global_transform * (ScorpionGeometry.GUN_MUZZLE + AtlasGeometry.GUN_OFFSET)
		check(muzzle.distance_to(expected) < 0.001, "Rendered gun and server ray share the same translated muzzle")
		var groups := visual.component_meshes()
		check(not groups.weapon.is_empty() and not groups.drive_left.is_empty() and not groups.drive_right.is_empty(),
			"Actual equipment is registered for damage and destruction")
		for node: Node in groups.drive_left:
			check(not groups.drive_right.has(node), "Independent tracks never share damage surfaces")
		var before: Array[Transform3D] = []
		for link: Dictionary in visual._links: before.append(link.node.transform)
		visual.advance_drive(0.35, -0.35)
		check(not before[0].is_equal_approx(visual._links[0].node.transform), "Movement advances the real imported tread shoes")
		visual.advance_drive(-0.35, 0.35)
		for index: int in before.size():
			check(before[index].is_equal_approx(visual._links[index].node.transform),
				"Track phase returns to authored geometry without drift or collapsing the links")
		var view := BotView.new()
		view.weapon_charge_fraction = 0.8
		view.weapon_state = "active"
		view.secondary_charge = 0.8
		view.gun_pitch = -0.18
		view.server_tick = 1
		visual.show_state(view, 1.0 / 60.0)
		var mount := gun.gun_effects.gun_mount
		var mount_pivot: Vector3 = gun.gun_effects._mount_rest.affine_inverse() * ScorpionGeometry.GUN_PIVOT
		var actual_pivot := visual.to_local(mount.global_transform * mount_pivot)
		check(actual_pivot.distance_to(Vector3(0.48, 0.49, 0)) < 0.001,
			"Elevation rotates around the actual roof socket rather than moving the entire gun: " + str(actual_pivot))
		view.pose = Transform3D(Basis(Vector3.UP, 0.15), Vector3.ZERO)
		visual.show_state(view, 1.0 / 60.0)
		check(visual._travel[0] < 0.0 and visual._travel[1] > 0.0,
			"Turning left reverses the inside left track and advances the right track")
		visual.free()
	modules_case(registry)
	await paint_case(registry)
	await garage_case(registry)
	if failures.is_empty(): print("ATLAS ASSEMBLY PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)

func modules_case(registry: ContentRegistry) -> void:
	for selection: int in 4:
		var draft := registry.atlas()
		var config: Dictionary = draft.cosmetics.sawblade
		config.armor_side = mini(selection, 2)
		config.exhaust = selection
		for slot: String in ["armor_top", "armor_front", "armor_rear"]: config[slot] = mini(selection, 1)
		var visual := AtlasVisual.new()
		add_child(visual)
		visual.assemble(draft, registry.validate(draft).stats.size)
		var expected := {"ArmorSideReference":config.armor_side == 1,
			"ArmorSideHeavy":config.armor_side == 2, "ArmorTop":config.armor_top == 1,
			"ArmorFront":config.armor_front == 1, "ArmorRear":config.armor_rear == 1,
			"ExhaustSmall":config.exhaust == 1, "ExhaustMedium":config.exhaust == 2,
			"ExhaustLarge":config.exhaust == 3}
		for label: String in expected:
			check(visual.nodes.has(label), "Selectable module has authored geometry: " + label)
			if not visual.nodes.has(label): continue
			check(visual.nodes[label].visible == expected[label], "Only the selected module is visible: " + label)
			check(not visual.nodes[label].find_children("*", "MeshInstance3D", true, false).is_empty(),
				"Cosmetic selectors attach real parts rather than empty placeholders: " + label)
		visual.free()

func paint_case(registry: ContentRegistry) -> void:
	var yellow := AtlasVisual.new()
	var cyan := AtlasVisual.new()
	add_child(yellow)
	add_child(cyan)
	var draft := registry.atlas()
	yellow.assemble(draft, registry.validate(draft).stats.size)
	draft.cosmetics.sawblade.paint_primary = [0.02, 0.55, 0.72, 1.0]
	cyan.assemble(draft, registry.validate(draft).stats.size)
	var replaced := 0
	for mesh: MeshInstance3D in cyan.model.find_children("*", "MeshInstance3D", true, false):
		for index: int in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			if original == null or not "PaintPrimary" in original.resource_name: continue
			var painted := mesh.get_surface_override_material(index) as ShaderMaterial
			check(painted != null, "Primary paint replaces yellow enamel with the selected custom color")
			if painted == null: continue
			check(original.albedo_texture != null and original.metallic_texture != null and original.normal_texture != null,
				"Portable imported materials contain real color, metal/roughness and normal maps")
			check(painted.get_shader_parameter("surface_albedo") == original.albedo_texture
				and painted.get_shader_parameter("surface_orm") == original.metallic_texture
				and painted.get_shader_parameter("surface_normal") == original.normal_texture,
				"Repainting preserves imported surface texture, roughness, metal chips and normal detail")
			replaced += 1
	check(replaced > 0, "Custom paint reaches real imported materials")
	for mesh: MeshInstance3D in yellow.model.find_children("*", "MeshInstance3D", true, false):
		for index: int in mesh.mesh.get_surface_count():
			check(mesh.get_surface_override_material(index) == null,
				"Changing another build never alters the original authored yellow material")
	if DisplayServer.get_name() != "headless":
		yellow.position.x = -4.0
		cyan.position.x = 4.0
		var camera := Camera3D.new()
		add_child(camera)
		camera.position = Vector3(18, 12, -20)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		await RenderingServer.frame_post_draw
		camera.free()
	yellow.free()
	cyan.free()
	await get_tree().process_frame

func garage_case(registry: ContentRegistry) -> void:
	var profile: Node = load("res://ui/menus/scripts/player_profile.gd").new()
	profile.save_path = "user://atlas-profile-%d.json" % Time.get_ticks_usec()
	add_child(profile)
	check(profile.loadouts.size() == 5 and profile.loadouts[3].parts.chassis == "scorpion_hex"
		and profile.loadouts[4].parts.chassis == "atlas_mx", "Atlas is an additional preset; existing preset order is retained")
	profile.active_bot = 4
	for category: Dictionary in profile.catalogue.paint:
		if category.slot not in SawbladeConfig.COLORS: continue
		profile.set_sawblade_color(category.slot, Color.CYAN)
		profile.equip("paint", category, category.items[0])
		check(profile.active_loadout().cosmetics.sawblade[category.slot] == AtlasGeometry.paint_defaults()[category.slot],
			"Original restores the current Atlas channel's authored color")
		var resolved: Dictionary = profile.resolved_item("paint", category, category.items[0])
		check(resolved.rgba == AtlasGeometry.paint_defaults()[category.slot],
			"Original paint tile shows the correct Atlas color rather than another chassis palette")
	var preview := GarageBotPreview.new()
	add_child(preview)
	preview.show_loadout(profile.active_loadout())
	check(preview.atlas_visual != null and preview.sawblade_visual == null and preview.scorpion_visual == null,
		"Garage uses the new authored Atlas chassis")
	check(profile.save_active("Painted Atlas") == OK, "Atlas saves through the existing validated profile workflow")
	profile.reload()
	check(profile.loadouts[profile.PRESET_COUNT].parts == registry.atlas().parts,
		"Saved Atlas reloads with the exact installed equipment")
	for suffix: String in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(profile.save_path + suffix)
	preview.free()
	profile.free()
	await get_tree().process_frame
