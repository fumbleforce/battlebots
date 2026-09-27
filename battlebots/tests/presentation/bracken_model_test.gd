extends Node3D
## Imported model, moving rig and factory loadout contract. Headless-safe.
var failures := 0
var registry := ContentRegistry.new()

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var draft := registry.bracken()
	var validated := registry.validate(draft)
	check(validated.valid, "Bracken factory loadout validates: %s" % validated.reasons)
	check(validated.stats.turret_barrels == 4, "Four actual cannon barrels use quad volley authority")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(draft))
	check(registry.validate(saved).valid, "JSON save/wire round trip preserves the factory assembly")
	for slot: String in ["drive", "weapon", "utility"]:
		var invalid := draft.duplicate(true)
		invalid.parts[slot] = {"drive":"walker", "weapon":"hammer", "utility":"turret_cannon"}[slot]
		check(not registry.validate(invalid).valid, "Unsupported factory change rejected: " + slot)
	var pickups := MatchPickups.new()
	check(not pickups.pool.has("bracken") and pickups.swapped(draft, "hammer").is_empty(), "Sealed assembly is protected from incompatible pickups")
	check(not pickups.swapped(draft, "jump_off").is_empty(), "Perks remain independent of the assembly")
	var old := registry.atlas()
	old.content_hash = LoadoutStore.REVISION_EIGHTEEN_HASHES[0]
	var migrated := LoadoutStore.new().migrate({"schema_version":1,"loadouts":[old]})
	check(registry.validate(migrated.loadouts[0]).valid and migrated.loadouts[0].parts == old.parts, "Existing saved parts migrate unchanged")
	var visual := AtlasVisual.new()
	add_child(visual)
	visual.assemble(draft, validated.stats.size)
	check(visual.is_bracken and visual.model.scene_file_path == AtlasVisual.BRACKEN_MODEL, "Actual Bracken GLB is assembled")
	check(visual._links.size() == 104 and visual._wheels.size() == 10, "Both complete track loops and rollers imported")
	check(AtlasGeometry.collision_size(draft).x < AtlasGeometry.COLLISION_SIZE.x, "Slim silhouette has a correspondingly narrower collider")
	check(visual._hydraulics.size() == 4, "Two elevation rams have independent barrel and rod pivots")
	# Only permanent vehicle geometry: muzzle flashes/projectile trails legitimately
	# use transient primitive meshes and are outside the authored asset contract.
	var authored: Array[Node] = []
	for root: Node3D in [visual.model, visual.turret, visual.primary.mechanism]:
		authored.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for mesh: MeshInstance3D in authored:
		check(not (mesh.mesh is BoxMesh or mesh.mesh is CylinderMesh), "No untextured primitive adapter remains: " + str(mesh.name))
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null: continue
			var label := material.resource_name.to_lower()
			if "lens" in label or "stencil" in label: continue
			check(material.albedo_texture != null and material.normal_texture != null, "Authored surface carries portable texture detail: " + label)
	var rest: Transform3D = visual._links[0].node.transform
	visual.advance_drive(AtlasGeometry.TRACK_LENGTH / 4.0, -AtlasGeometry.TRACK_LENGTH / 4.0)
	check(not visual._links[0].node.transform.is_equal_approx(rest), "Differential travel moves the real shoes")
	visual.advance_drive(AtlasGeometry.TRACK_LENGTH * 3.0 / 4.0, -AtlasGeometry.TRACK_LENGTH * 3.0 / 4.0)
	check(visual._links[0].node.transform.is_equal_approx(rest), "Shoe returns continuously around the closed loop")
	for pose: Vector2 in [Vector2.ZERO, Vector2(1.1, 0.3), Vector2(-2.6, -0.03),
			Vector2(0, AtlasGeometry.turret_pitch_max("cannon_bracken")),
			Vector2(0, AtlasGeometry.turret_pitch_min("cannon_bracken", 0))]:
		var view := BotView.new()
		view.turret_kind = "cannon"
		view.turret_yaw = pose.x
		view.gun_pitch = pose.y
		visual.reset_observation()
		visual.show_state(view, 1.0 / Engine.physics_ticks_per_second)
		for barrel: int in 4:
			var muzzle: Node3D = visual.turret.find_child("MuzzleCannonBracken_%d" % barrel, true, false)
			var offset := AtlasGeometry.turret_barrel("cannon_bracken", barrel + 1)
			var expected := AtlasGeometry.turret_muzzle(validated.stats.size, "cannon_bracken", pose.x, pose.y, offset)
			check(muzzle != null and muzzle.global_position.distance_to(expected) < 0.001, "Imported barrel %d agrees with authoritative aim at %s" % [barrel, pose])
		for ram: Dictionary in visual._hydraulics:
			var node: Node3D = ram.node
			var direction: Vector3 = node.get_parent().to_local(ram.other.global_position) - node.position
			var drawn_axis: Vector3 = node.basis * ram.basis.inverse() * ram.axis
			check(drawn_axis.normalized().dot(direction.normalized()) > 0.9999, "Both rigid ram sections remain coaxial as the gun elevates")
			var hydraulic: Dictionary = AtlasGeometry.bracken_geometry().hydraulics
			check(direction.length() < hydraulic.barrel_length + hydraulic.rod_length and direction.length() > hydraulic.rod_length, "Piston stays engaged without bottoming out")
	var components := visual.component_meshes()
	check(not components.weapon.is_empty() and not components.drive_left.is_empty() and not components.drive_right.is_empty(), "Real meshes participate in damage and part loss")
	check(visual.primary.mechanism.find_child("BrackenLifter", true, false) != null, "Authored ramp is inside the working lifter mechanism")
	var profile = load("res://ui/menus/scripts/player_profile.gd").new()
	profile.save_path = "user://bracken-test-missing-%d.json" % Time.get_ticks_usec()
	profile.reload()
	var found := false
	for index: int in profile.loadouts.size():
		if AtlasGeometry.bracken_enabled(profile.loadouts[index]):
			found = true
			check(profile.sealed(index), "Garage protects the complete factory preset")
	check(found, "Bracken is selectable in the garage")
	profile.free()
	visual.free()
	if failures == 0: print("BRACKEN MODEL PASS")
	get_tree().quit(1 if failures else 0)
