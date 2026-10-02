extends SceneTree
## Elysium structural regression and reproducible review captures (#115).
## godot --headless --path battlebots --script res://tests/presentation/elysium_arena_test.gd
## godot --path battlebots --script res://tests/presentation/elysium_arena_test.gd -- --capture [--view=name] [--size=WxH]
const GROUND = preload("res://scripts/arena/elysium_ground.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var started := Time.get_ticks_msec()
	var world := AuthorityWorld.new()
	world.arena_id = "elysium"
	root.add_child(world)
	var arena := world.arena
	await physics_frame
	await physics_frame
	print("Elysium world built in %d ms" % (Time.get_ticks_msec() - started))
	var cfg: RefCounted = GROUND.settings()
	check(arena.get_node("SpawnPoints").get_child_count() == 18, "Spawn contract changed")
	for wall: Node3D in arena.get_node("Walls").get_children():
		check((wall.get_node("Collision") as CollisionShape3D).disabled, "Open edges: wall %s still collides" % wall.name)
	check((arena.get_node("Floor/Collision") as CollisionShape3D).disabled, "Open edges: the catch slab still collides")
	# Playable area about Woodland's (the 240 m octagon, ~47,700 m^2).
	var land := 0
	for z: int in range(-150, 151, 2):
		for x: int in range(-150, 151, 2):
			if GROUND.on_land(x, z):
				land += 4
	check(land > 36000 and land < 56000, "Island area %d m^2 is not Woodland-sized" % land)
	# Point symmetry: land, heights and structures match their mirrors.
	for i: int in 600:
		var p := Vector2(sin(i * 12.9898) * 140.0, cos(i * 78.233) * 140.0)
		check(GROUND.on_land(p.x, p.y) == GROUND.on_land(-p.x, -p.y), "Land is not point-symmetric at %s" % str(p))
		check(absf(GROUND.height_at(p.x, p.y) - GROUND.height_at(-p.x, -p.y)) < 0.001, "Heights are not point-symmetric at %s" % str(p))
	var items := GROUND.structures()
	check(items.size() >= 30, "Structure set changed (%d)" % items.size())
	for item: Dictionary in items:
		var at: Vector3 = item.base.origin
		var mirrored := items.any(func(other: Dictionary) -> bool: return other.type == item.type and other.base.origin.distance_to(Vector3(-at.x, at.y, -at.z)) < 0.01)
		check(mirrored or item.type == "rotunda", "Structure lacks its mirrored partner: %s" % item.name)
		for body: Dictionary in item.bodies:
			for part: Dictionary in body.parts:
				var centre: Vector3 = part.xform.origin
				if part.shape == "hull":
					continue
				check(GROUND.on_land(centre.x, centre.z), "%s stands over the sky at %s" % [body.name, str(centre)])
	var bodies := arena.get_node("ElysiumStructures")
	var listed := GROUND.bodies()
	check(bodies.get_child_count() == listed.size(), "Structure bodies differ from the list")
	for body: StaticBody3D in bodies.get_children():
		check(body.collision_mask == 2 and body.collision_layer & 1 and body.get_child_count() > 0, "Structure %s does not collide like the arena shell" % body.name)
	# Destructible architecture (#115): every piece but the obelisk pedestals is
	# an ArenaProps prop on the prop layer.
	var breakable := listed.filter(func(body: Dictionary) -> bool: return not String(body.kind).is_empty())
	check(breakable.size() >= 90 and world.props.props.size() == breakable.size(), "Every breakable piece registers as a prop (%d of %d)" % [world.props.props.size(), breakable.size()])
	for body: Dictionary in breakable:
		var node: StaticBody3D = bodies.get_node(String(body.name))
		check(node.collision_layer & BaselineConfig.PROP_LAYER, "%s is not on the prop layer" % body.name)
		check(world.props.props.has(body.name) and world.props.props[body.name].kind == body.kind, "%s is not registered as %s" % [body.name, body.kind])
	var column: String = "ColumnC0_1"
	check(world.props.damage(column, 1.0e6, "cannon", world.props.props[column].at, Vector3.LEFT) >= 0.0 and bodies.get_node(column).collision_layer == 0,
		"A colonnade column breaks and stops colliding")
	# The arch's attic falls with either pier.
	world.props.damage("PierA6_l", 1.0e6, "hammer", world.props.props["PierA6_l"].at, Vector3.LEFT)
	check(world.props.destroyed.has("AtticA6") and world.props.destroyed["AtticA6"].kind == "collapse" and bodies.get_node("AtticA6").collision_layer == 0,
		"Breaking a pier brings its attic down")
	# The dome caves in once four rotunda columns are gone, not before.
	for i: int in 3:
		world.props.damage("ColumnRotunda%d" % i, 1.0e6, "cannon", world.props.props["ColumnRotunda%d" % i].at, Vector3.LEFT)
	check(not world.props.destroyed.has("DomeRotunda"), "The dome stands on nine columns")
	world.props.damage("ColumnRotunda6", 1.0e6, "cannon", world.props.props["ColumnRotunda6"].at, Vector3.LEFT)
	check(world.props.destroyed.has("DomeRotunda") and bodies.get_node("DomeRotunda").collision_layer == 0, "The dome caves in on eight columns")
	# Flames do not burn marble; a new round restores everything.
	var rail: String = world.props.props.keys().filter(func(n: String) -> bool: return world.props.props[n].kind == "balustrade")[0]
	check(world.props.damage(rail, 1.0e6, "flamer", world.props.props[rail].at, Vector3.LEFT) < 0.0, "Fire does not break marble")
	world.props.reset_round()
	check(world.props.destroyed.is_empty() and bodies.get_node("DomeRotunda").collision_layer != 0 and bodies.get_node(column).collision_layer != 0, "A new round restores the architecture")
	# The chasm round the Sanctum and the wells are open sky; the bridges cross it.
	for angle: float in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var gap := (GROUND.sanctum_radius(angle) + GROUND.halo_inner(angle)) * 0.5
		check(not GROUND.on_land(cos(angle) * gap, sin(angle) * gap), "The chasm is closed at bearing %.2f" % angle)
	for angle: float in GROUND.bridge_angles():
		for r: float in range(0, 115, 3):
			check(GROUND.on_land(cos(angle) * r, sin(angle) * r), "The bridge at bearing %.2f breaks at %.0f m" % [angle, r])
	for well: Dictionary in GROUND.wells():
		check(not GROUND.on_land(well.at.x, well.at.y) and GROUND.height_at(well.at.x, well.at.y) < cfg.kill_y, "Well at %s is not open" % str(well.at))
	check(GROUND.height_at(0, 140) < cfg.kill_y and GROUND.height_at(140, 140) < cfg.kill_y, "Beyond the Halo is not open sky")
	# Nothing on the islands steeper than the tracks hold (bridge ramps included).
	var steep := 0
	var samples := 0
	for i: int in 8000:
		var a := i * 2.39996
		var r := 125.0 * sqrt(fmod(i * 0.6180339, 1.0))
		var p := Vector2(cos(a), sin(a)) * r
		if GROUND.land_sdf(p.x, p.y) > -1.5 or GROUND.land_sdf(p.x + 0.5, p.y) > -1.5 or GROUND.land_sdf(p.x, p.y + 0.5) > -1.5:
			continue
		var h := GROUND.height_at(p.x, p.y)
		var gx := GROUND.height_at(p.x + 0.5, p.y) - h
		var gz := GROUND.height_at(p.x, p.y + 0.5) - h
		samples += 1
		if Vector2(gx, gz).length() / 0.5 > tan(deg_to_rad(30.0)):
			steep += 1
			if steep <= 5:
				print("STEEP at ", p, " slope=", Vector2(gx, gz).length() / 0.5)
	check(samples > 5000 and steep == 0, "%d of %d island samples are steeper than 30 degrees" % [steep, samples])
	var space := arena.get_world_3d().direct_space_state
	# Starts, Practice Duel places, pickups and cooling points: on level land, clear.
	var clear_points: Array[Vector3] = []
	for marker: Node3D in arena.get_node("SpawnPoints").get_children():
		clear_points.append(marker.position)
	var spawns := ArenaSpawns.settings()
	var duel := spawns.duel_centre_for("elysium")
	var reach := ArenaBounds.half_extent("elysium") * spawns.duel_monowheel_side_for("elysium")
	for offset: Vector3 in [Vector3.ZERO, Vector3(0, 0, -reach), Vector3(-reach, 0, 0), Vector3(reach, 0, 0)]:
		clear_points.append(duel + offset)
	var starts := clear_points.size()
	var index := 0
	for point: Vector3 in clear_points + world.pickup_points() + world.cooling_zones() + world.coolant_points():
		var is_start := index < starts
		index += 1
		check(GROUND.land_sdf(point.x, point.z) < (-6.0 if is_start else -3.0), "%s is too near an edge (%.1f m)" % [str(point), -GROUND.land_sdf(point.x, point.z)])
		var clearance := SphereShape3D.new()
		clearance.radius = 7.0
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = clearance
		query.collision_mask = 1
		query.transform.origin = Vector3(point.x, GROUND.height_at(point.x, point.z) + 7.3, point.z)
		var hits := space.intersect_shape(query).filter(func(hit: Dictionary) -> bool: return hit.collider.name != "ElysiumIslands")
		check(hits.is_empty(), "Architecture crowds %s: %s" % [str(point), str(hits.map(func(hit: Dictionary) -> String: return String(hit.collider.name)))])
		if is_start:
			for dx: float in [-5.0, 0.0, 5.0]:
				for dz: float in [-5.0, 0.0, 5.0]:
					var h := GROUND.height_at(point.x + dx, point.z + dz)
					check(absf(h - GROUND.height_at(point.x, point.z)) < 0.6, "Start ground is not level at %s" % str(point))
	# The two teams start across the Sanctum from each other.
	var first: Vector3 = arena.get_node("SpawnPoints/Team1_3").position
	var second: Vector3 = arena.get_node("SpawnPoints/Team2_3").position
	check(Vector2(first.x + second.x, first.z + second.z).length() < 0.01 and Vector2(first.x, first.z).length() > 80.0, "Duel starts are not across the Sanctum")
	var spawned := world.spawn(1, 0, 0, world.registry.starter(true), 5)
	var origin: Vector3 = spawned.spawn_pose.origin if spawned else Vector3.ZERO
	check(spawned != null and origin.y > GROUND.height_at(origin.x, origin.z) + 0.05, "Elysium spawn height %s" % str(origin))
	world.clear_bots()
	var art := arena.get_node("FoundryVisuals")
	check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "Art created gameplay collision")
	if DisplayServer.get_name() == "headless":
		check(art.get_child_count() == 0, "Headless arena constructed presentation")
		check(arena.find_children("*", "VisualInstance3D", true, false).is_empty(), "Headless world kept visuals")
	else:
		var built := Time.get_ticks_msec()
		await process_frame
		await process_frame
		print("Elysium art built in %d ms" % (Time.get_ticks_msec() - built))
		check(art.find_children("*", "MeshInstance3D", true, false).size() > 40, "Elysium art did not build")
		if "--capture" in OS.get_cmdline_user_args():
			await _capture(world)
	world.queue_free()
	await process_frame
	print("ELYSIUM PASS" if failures == 0 else "ELYSIUM FAIL")
	quit(0 if failures == 0 else 1)

func _capture(world: AuthorityWorld) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.substr(7).split("x")
			root.size = Vector2i(int(parts[0]), int(parts[1]))
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 68
	camera.far = 6000
	# Two bots on real team-1 starts (lanes 2 and 4), as a match places them.
	var registry := ContentRegistry.new()
	for index: int in range(2):
		var bot := world.spawn(index + 1, 0, index, registry.starter(index == 1), 2)
		bot.body.freeze = true
		bot.body.global_transform = bot.spawn_pose
		bot.previous_pose = bot.spawn_pose
	var views := [
		["overview", Vector3(0, 80, 210), Vector3(0, -6, 10)],
		["high", Vector3(-190, 230, -190), Vector3(0, -20, 0)],
		["chase", Vector3(-2, 8.0, 104), Vector3(0, 3.0, 50)],
		["sanctum", Vector3(26, 9.0, 52), Vector3(0, 9.0, 0)],
		["rotunda", Vector3(8, 7.0, 8), Vector3(-6, 14.0, -12)],
		["bridge", Vector3(4, 5.0, 74), Vector3(-4, 2.0, 40)],
		["edge", Vector3(70, 6.0, -100), Vector3(120, -40.0, -160)],
		["chasm", Vector3(44, 9.0, 44), Vector3(36, -30.0, 36)],
		["well", Vector3(54, 8.0, 34), Vector3(68, -14.0, 46)],
		["colonnade", Vector3(60, 5.0, 10), Vector3(84, 9.0, -4)],
		["glare", Vector3(0, 8.0, -110), Vector3(30, 20.0, -400)],
		["below", Vector3(-160, -50, 40), Vector3(-60, -10, 0)],
		# Smashes two colonnade columns and an arch pier (its attic follows) in
		# front of the camera.
		["ruins", Vector3(-30, 10.0, 92), Vector3(-6, 6.0, 50), ["ColumnC3_2", "ColumnC3_1", "PierA6_l"]],
		# Four rotunda columns: the dome caves in.
		["collapse", Vector3(34, 14.0, 34), Vector3(0, 12.0, 0), ["ColumnRotunda0", "ColumnRotunda1", "ColumnRotunda2", "ColumnRotunda3"]],
		# Arena-select card (ui/menus/art/arena_elysium.jpg).
		["card", Vector3(70, 34, 150), Vector3(0, 6, 0)],
	]
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			only = arg.substr(7)
	var output := "res://exports/elysium-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open(output + "/.gdignore", FileAccess.WRITE)
	ignore.close()
	for view: Array in views:
		if only != "" and view[0] != only:
			continue
		world.props.reset_round()
		camera.look_at_from_position(view[1], view[2])
		var breaks: Array = view[3] if view.size() > 3 else []
		if not breaks.is_empty():
			# Let the art settle, then break the props and catch them falling.
			for frame: int in 6:
				await process_frame
			for name: String in breaks:
				world.props.damage(name, 1.0e6, "cannon", world.props.props[name].at + Vector3(3, 4, 3), Vector3(-1, 0, -1))
		for frame: int in (14 if not breaks.is_empty() else 24):
			await process_frame
		await RenderingServer.frame_post_draw
		var path := output + "/elysium-%s.png" % view[0]
		var image := root.get_texture().get_image()
		check(image.save_png(path) == OK, "Capture failed")
		if view[0] == "card" and root.size == Vector2i(1600, 900):
			check(image.save_jpg("res://ui/menus/art/arena_elysium.jpg", 0.88) == OK, "Card capture failed")
		print("CAPTURE ", ProjectSettings.globalize_path(path))
