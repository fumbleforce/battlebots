extends Node3D
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var registry := ContentRegistry.new()
	var original: Dictionary = registry.atlas()
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/atlas_runtime/atlas_manifest.json"))
	check(metadata.mounts.size() == 11, "Atlas exports eleven equipment mounts including four supported corner sockets")
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
		for socket: String in metadata.mounts:
			check(visual.nodes.has(socket), "Authored modular mount is exported: " + socket)
			if visual.nodes.has(socket):
				var coordinate: Array = metadata.mounts[socket]
				check(visual._relative_transform(visual.nodes[socket]).origin.distance_to(Vector3(coordinate[0], coordinate[1], coordinate[2])) < 0.001,
					"Imported socket agrees with its published addon transform: " + socket)
		check(visual._links.size() == 80, "Both tracked drives contain forty independently moving shoes")
		check(visual._connectors.size() == 80, "Both tracked drives have independently moving straps between all neighboring shoes")
		check(visual._wheels.size() >= 10, "Only wheel pivots animate, never their child meshes")
		check(visual.primary.kind == weapon, "Equipped primary is the actual rendered mechanism")
		if weapon == "lifter":
			check(visual.primary.mechanism.get_node_or_null("AtlasLifterAttachment") != null,
				"The default front lifter uses the high-quality authored attachment")
			connectors_case(visual)
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
	if DisplayServer.get_name() != "headless": await thumbnail_case(registry)
	if failures.is_empty(): print("ATLAS ASSEMBLY PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)

func connectors_case(visual: AtlasVisual) -> void:
	var rest: Dictionary = {}
	var mesh_bounds: Dictionary = {}
	for connector: Dictionary in visual._connectors:
		rest[str(connector.node.name)] = connector.node.transform
		check(not connector.node.find_children("ConnectingStraps*", "MeshInstance3D", true, false).is_empty(),
			"Every connector carries the authored pair of slate straps")
		mesh_bounds[str(connector.node.name)] = part_mesh_bounds(connector.node)
	for link: Dictionary in visual._links:
		# The central inward engagement tooth is deeper than the shoe plate;
		# only the slate shoe surface is adjacent to the two outside straps.
		mesh_bounds[str(link.node.name)] = part_mesh_bounds(link.node, "Atlas_TrackSteel")
	# Sample forward/reverse travel across straight/arc boundaries and both wraps.
	for travel: float in [0.0, 0.033, 0.61, 1.84, 5.83]:
		visual.advance_drive(travel, -travel)
		for side: String in ["L", "R"]:
			for index: int in 40:
				var label := "TrackConnector_%s_%02d" % [side, index]
				if not visual.nodes.has(label):
					check(false, "Authored track connector is exported: " + label)
					continue
				var connector := visual._relative_transform(visual.nodes[label])
				var first := visual._relative_transform(visual.nodes["Tread_%s_%02d" % [side, index]])
				var second := visual._relative_transform(visual.nodes["Tread_%s_%02d" % [side, (index + 1) % 40]])
				var a := connector.origin.distance_to(first.origin)
				var b := connector.origin.distance_to(second.origin)
				check(a > 0.071 and a < 0.074 and b > 0.071 and b < 0.074 and absf(a - b) < 0.001,
					"Moving connector stays between its two actual adjacent shoes: " + label)
				check(connector.basis.z.normalized().dot((second.origin - first.origin).normalized()) > 0.995,
					"Connector straps follow the neighboring shoe gap around each return wheel: " + label)
				var first_bounds: AABB = mesh_bounds["Tread_%s_%02d" % [side, index]]
				var second_bounds: AABB = mesh_bounds["Tread_%s_%02d" % [side, (index + 1) % 40]]
				var straps: AABB = mesh_bounds[label]
				# Check actual imported strap spans against both shoe inner edges;
				# 8 mm allows the chamfer and arc's midpoint chord offset.
				for x: float in [-0.156, 0.156]:
					var contact_a := connector.affine_inverse() * (first * Vector3(x, first_bounds.position.y, first_bounds.end.z))
					var contact_b := connector.affine_inverse() * (second * Vector3(x, second_bounds.position.y, second_bounds.position.z))
					check(straps.grow(0.008).has_point(contact_a) and straps.grow(0.008).has_point(contact_b),
						"Actual connector mesh covers the open gap between moving shoe edges: " + label)
		visual.advance_drive(-travel, travel)
	for connector: Dictionary in visual._connectors:
		check(rest[str(connector.node.name)].is_equal_approx(connector.node.transform),
			"Connector travel returns exactly to its imported resting pose")

func part_mesh_bounds(part: Node3D, material_name := "") -> AABB:
	var bounds := AABB()
	var initialized := false
	for mesh: MeshInstance3D in part.find_children("*", "MeshInstance3D", true, false):
		var local := part.global_transform.affine_inverse() * mesh.global_transform
		for index: int in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(index)
			if not material_name.is_empty() and (material == null or material.resource_name != material_name): continue
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := local * vertex
				if initialized: bounds = bounds.expand(point)
				else:
					bounds = AABB(point, Vector3.ZERO)
					initialized = true
	check(initialized, "Imported moving part has inspectable surface geometry: " + str(part.name))
	return bounds

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
	draft.cosmetics.sawblade.paint_secondary = [0.55, 0.025, 0.02, 1.0]
	cyan.assemble(draft, registry.validate(draft).stats.size)
	var replaced := 0
	var untouched_steel := 0
	var checked_masks: Dictionary = {}
	for mesh: MeshInstance3D in cyan.model.find_children("*", "MeshInstance3D", true, false):
		for index: int in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			if original == null: continue
			if "Metal" in original.resource_name:
				check(mesh.get_surface_override_material(index) == null, "Primary repaint leaves the independently selected steel finish unchanged")
				untouched_steel += 1
			if not ("PaintPrimary" in original.resource_name or "PaintSecondary" in original.resource_name): continue
			check(not "PaintPrimaryEdge" in original.resource_name, "Baked painted chamfers belong to the worn primary atlas")
			var painted := mesh.get_surface_override_material(index) as ShaderMaterial
			check(painted != null, "Both baked paint families accept their selected custom colors")
			if painted == null: continue
			check(original.albedo_texture != null and original.metallic_texture != null and original.normal_texture != null,
				"Portable imported materials contain real color, metal/roughness and normal maps")
			check(painted.get_shader_parameter("surface_albedo") == original.albedo_texture
				and painted.get_shader_parameter("surface_orm") == original.metallic_texture
				and painted.get_shader_parameter("surface_normal") == original.normal_texture
				and painted.get_shader_parameter("surface_ao") == original.ao_texture,
				"Repainting preserves imported color, roughness, normal and actual occlusion maps")
			check(original.ao_enabled and original.ao_texture != null,
				"Baked occlusion reaches the imported material, not just an unused ORM channel")
			check(is_equal_approx(painted.get_shader_parameter("normal_strength"), original.normal_scale),
				"Repainting retains the authored normal strength")
			var coverage := painted.get_shader_parameter("surface_coverage") as Texture2D
			check(coverage != null, "Each paint atlas has an explicit enamel coverage mask")
			if coverage != null and not checked_masks.has(original.resource_name):
				checked_masks[original.resource_name] = true
				var mask := coverage.get_image()
				if mask.is_compressed(): mask.decompress()
				var enamel := 0
				var protected := 0
				for y: int in range(8, mask.get_height(), 16):
					for x: int in range(8, mask.get_width(), 16):
						var value := mask.get_pixel(x, y).r
						if value > 0.9: enamel += 1
						if value < 0.1: protected += 1
				check(enamel > 20 and protected > 20, "Baked mask separates remaining enamel from protected primer and metal")
				for texture: Texture2D in [original.albedo_texture, original.metallic_texture, original.normal_texture, original.ao_texture, coverage]:
					check(texture != null and texture.get_image().has_mipmaps(), "Atlas surface maps have mipmaps for stable distant detail")
			replaced += 1
	check(replaced > 0, "Custom paint reaches real imported materials")
	check(checked_masks.has("Atlas_PaintPrimary") and checked_masks.has("Atlas_PaintSecondary") and untouched_steel > 0,
		"Both paint families have coverage while independent steel remains untouched")
	for mesh: MeshInstance3D in yellow.model.find_children("*", "MeshInstance3D", true, false):
		for index: int in mesh.mesh.get_surface_count():
			check(mesh.get_surface_override_material(index) == null,
				"Changing another build never alters the original authored yellow material")
	if DisplayServer.get_name() != "headless":
		await paint_coverage_render_case(cyan)
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

func paint_coverage_render_case(visual: AtlasVisual) -> void:
	# Exercise the real production shader with enamel, nonmetal primer and steel.
	# A metallic-threshold mask would incorrectly recolor the middle swatch.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 32)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 2.0
	viewport.add_child(camera)
	camera.current = true
	var base := Image.create(12, 4, false, Image.FORMAT_RGBA8)
	var mask := Image.create(12, 4, false, Image.FORMAT_RGBA8)
	var orm := Image.create(12, 4, false, Image.FORMAT_RGBA8)
	for y: int in 4:
		for x: int in 12:
			var band := x / 4
			base.set_pixel(x, y, [Color(0.86, 0.51, 0.055), Color(0.32, 0.23, 0.16), Color(0.5, 0.52, 0.54)][band])
			mask.set_pixel(x, y, Color.WHITE if band == 0 else Color.BLACK)
			orm.set_pixel(x, y, Color(1.0, 0.66, 0.92 if band == 2 else 0.08))
	var original := StandardMaterial3D.new()
	original.albedo_texture = ImageTexture.create_from_image(base)
	original.metallic_texture = ImageTexture.create_from_image(orm)
	original.roughness = 1.0
	original.metallic = 1.0
	var authored := Color(0.86, 0.51, 0.055)
	var material := visual._repaint_material(original, ImageTexture.create_from_image(mask), authored, authored)
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.mesh.size = Vector2(6.0, 2.0)
	mesh.material_override = material
	viewport.add_child(mesh)
	for frame: int in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image()
	material.set_shader_parameter("paint", Color(0.03, 0.76, 0.87))
	for frame: int in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image()
	for band: int in 3:
		var a := before.get_pixel(16 + band * 32, 16)
		var b := after.get_pixel(16 + band * 32, 16)
		var difference := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
		check(difference > 0.08 if band == 0 else difference < 0.015,
			"Rendered recolor changes enamel and preserves nonmetal primer/steel swatch %d" % band)
	viewport.free()

func thumbnail_case(registry: ContentRegistry) -> void:
	var renderer := GarageBotThumbnailRenderer.new()
	add_child(renderer)
	var draft := registry.atlas()
	var key := GarageBotThumbnailRenderer.visual_key(draft)
	renderer.sync([draft])
	for frame: int in 120:
		if renderer.cached(key) != null: break
		await get_tree().process_frame
	var texture := renderer.cached(key)
	check(texture != null and renderer._preview.atlas_visual != null,
		"The new garage thumbnail pipeline renders Atlas itself rather than another bot image")
	if texture != null:
		var captured := texture.get_image()
		check(captured.get_size() == Vector2i(256, 160), "Atlas thumbnail uses the bounded reusable viewport")
		var background := captured.get_pixel(0, 0)
		var model_pixels := 0
		for y: int in range(4, 156, 4):
			for x: int in range(4, 252, 4):
				var sample := captured.get_pixel(x, y)
				if Vector3(sample.r - background.r, sample.g - background.g, sample.b - background.b).length() > 0.10:
					model_pixels += 1
		check(model_pixels > 100, "The captured Atlas thumbnail contains a visible model")
		var framed := true
		for mesh: MeshInstance3D in renderer._preview.model.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree(): continue
			for corner: int in 8:
				var point := mesh.global_transform * mesh.get_aabb().get_endpoint(corner)
				var screen := renderer._preview.camera.unproject_position(point)
				framed = framed and not renderer._preview.camera.is_position_behind(point)
				framed = framed and screen.x >= 0 and screen.x <= 256 and screen.y >= 0 and screen.y <= 160
		check(framed, "Atlas thumbnail keeps the complete tracks, hull and default lifter in frame")
	renderer.queue_free()
	await get_tree().process_frame

func garage_case(registry: ContentRegistry) -> void:
	var profile: Node = load("res://ui/menus/scripts/player_profile.gd").new()
	profile.save_path = "user://atlas-profile-%d.json" % Time.get_ticks_usec()
	add_child(profile)
	check(profile.loadouts.size() == 9 and profile.loadouts[3].parts.chassis == "scorpion_hex"
		and profile.loadouts[4].parts.chassis == "atlas_mx" and profile.loadouts[5].parts.utility == "turret_cannon",
		"Atlas and Atlas turret are additional presets; existing preset order is retained")
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
