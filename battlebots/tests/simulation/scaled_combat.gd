extends Node3D
## Independent surface probes: hit points come from the rendered assembly, not query constants.
var failures: Array[String] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func front_vertex(meshes: Array, body: Node3D) -> Vector3:
	var selected := Vector3.ZERO
	var front := INF
	for mesh: MeshInstance3D in meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var at := mesh.to_global(vertex)
				var local := body.to_local(at)
				if local.z < front:
					front = local.z
					selected = at
	return selected

func run() -> void:
	var registry := ContentRegistry.new()
	var probe := StaticBody3D.new()
	probe.collision_layer = BaselineConfig.BOT_LAYER
	probe.collision_mask = 0
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.035 * BotScale.FACTOR
	collision.shape = sphere
	probe.add_child(collision)
	add_child(probe)
	for chassis: String in ["compact", "balanced", "wide"]:
		for weapon: String in ["vertical_spinner", "horizontal_spinner", "saw", "hammer", "lifter"]:
			var build := SawbladeConfig.starter(registry)
			build.parts.chassis = chassis
			build.parts.weapon = weapon
			var bot := MvpBot.create(1, 0, build, registry)
			check(bot != null, "Scaled contact build is valid")
			if bot == null: continue
			add_child(bot)
			bot.set_process(false)
			bot.body.freeze = true
			bot.body.global_transform = Transform3D(Basis(Vector3.UP, 0.41), Vector3(3, 10, -2))
			bot.previous_pose = bot.body.global_transform
			bot.presentation.global_transform = bot.body.global_transform
			var size: Vector3 = bot.combat.stats.size
			check(is_equal_approx(size.y, 1.5) and bot.body.global_basis.get_scale().is_equal_approx(Vector3.ONE),
				"Canonical large hull uses full dimensions and an unscaled physics root")
			var art := SawbladeVisual.new()
			bot.presentation.add_child(art)
			art.assemble(build, size)
			var contact: Vector3
			if weapon == "vertical_spinner":
				contact = art.fallback_weapon.mechanism.to_global(Vector3(0, 0, -0.40))
			elif weapon == "horizontal_spinner":
				var rotor: CylinderMesh = art.fallback_weapon.mechanism.get_child(0).mesh
				contact = art.fallback_weapon.mechanism.to_global(Vector3(rotor.top_radius * 0.98, 0, 0))
			elif weapon == "saw":
				contact = art.nodes.Saw_SPIN_X.global_position - bot.body.global_basis.z * 0.65 * art.scale.z
			elif weapon == "hammer":
				art.set_hammer_frame(9)
				contact = art.nodes.Hammer_Impact.global_position + bot.body.global_basis.y * 0.04 * BotScale.FACTOR
			else:
				contact = front_vertex(art.component_meshes().weapon, bot.body)
			probe.global_position = contact
			await settle()
			var combat := CombatWorld.new()
			check(combat._sweep(bot).has(probe.get_instance_id()), chassis + " " + weapon + " query reaches the actual equipped weapon surface")
			if weapon == "lifter":
				for launching: bool in [false, true]:
					bot.combat.charge = 1.0
					bot.combat.launch = launching
					var lifted := BotView.new()
					lifted.weapon_charge_fraction = 1.0
					lifted.weapon_state = "launch" if launching else "active"
					art.show_state(lifted, 0.0)
					probe.global_position = front_vertex(art.component_meshes().weapon, bot.body)
					await settle()
					check(combat._sweep(bot).has(probe.get_instance_id()), chassis + " lifter leading surface stays inside its raised/launch query")
			probe.global_position = bot.body.to_global(Vector3(0, 0, -size.z * 3.0))
			await settle()
			check(not combat._sweep(bot).has(probe.get_instance_id()), chassis + " " + weapon + " query cannot hit beyond its physical reach")
			probe.global_position = bot.body.to_global(Vector3(0, size.y * 6.0, 0))
			await settle()
			check(not combat._sweep(bot).has(probe.get_instance_id()), chassis + " " + weapon + " query cannot hit remote overhead space")
			check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "Weapon art does not add duplicate damage colliders")
			bot.free()
	probe.free()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("SCALED COMBAT PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
