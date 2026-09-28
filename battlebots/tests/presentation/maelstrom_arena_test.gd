extends SceneTree
## Frozen Maelstrom structural regression and reproducible review captures (#102).
## godot --headless --path battlebots --script res://tests/presentation/maelstrom_arena_test.gd
## godot --path battlebots --script res://tests/presentation/maelstrom_arena_test.gd -- --capture [--view=name]
const GROUND = preload("res://scripts/arena/maelstrom_ground.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := AuthorityWorld.new()
	world.arena_id = "maelstrom"
	root.add_child(world)
	var arena := world.arena
	await physics_frame
	await physics_frame
	var cfg: RefCounted = GROUND.settings()
	check(arena.get_node("SpawnPoints").get_child_count() == 18, "Spawn contract changed")
	for wall: Node3D in arena.get_node("Walls").get_children():
		check((wall.get_node("Collision") as CollisionShape3D).disabled, "Open edges: wall %s still collides" % wall.name)
	check((arena.get_node("Floor/Collision") as CollisionShape3D).disabled, "Open edges: the catch slab still collides")
	# About Woodland's playable area (the 240 m octagon, ~47,700 m^2).
	var area: float = PI * (cfg.rim_radius * cfg.rim_radius - cfg.eye_radius * cfg.eye_radius)
	check(area > 42000.0 and area < 56000.0, "Ice ring area %.0f m^2 is not Woodland-sized" % area)
	# The eye spans about two Atlas MX lengths.
	var atlas := MvpBot.create(900, 0, world.registry.atlas(), world.registry)
	root.add_child(atlas)
	var atlas_length := atlas.collision_bounds().size.z
	check(absf(cfg.eye_radius - 2.0 * atlas_length) < atlas_length * 0.25, "Eye radius %.1f m is not ~2 Atlas lengths (%.1f m)" % [cfg.eye_radius, atlas_length])
	atlas.free()
	# Point symmetry: heights and obstacles match their mirrors.
	for i: int in 400:
		var p := Vector2(sin(i * 12.9898) * 125.0, cos(i * 78.233) * 125.0)
		check(absf(GROUND.height_at(p.x, p.y) - GROUND.height_at(-p.x, -p.y)) < 0.001, "Ice is not point-symmetric at %s" % str(p))
	var items := GROUND.obstacles()
	check(items.size() >= 20, "Obstacle set changed")
	for item: Dictionary in items:
		var mirrored := false
		for other: Dictionary in items:
			mirrored = mirrored or (other.model == item.model and other.at.distance_to(Vector3(-item.at.x, item.at.y, -item.at.z)) < 0.01
				and (int(item.faction) < 0 or int(other.faction) == 1 - int(item.faction)))
		check(mirrored, "Obstacle lacks its mirrored partner of the other fleet: %s" % item.name)
		check(not GROUND.hulls(item.model).is_empty(), "Obstacle %s has no collision hulls" % item.model)
		var r := Vector2(item.at.x, item.at.z).length()
		check(r > cfg.eye_radius + 10.0 and r < cfg.rim_radius - 8.0, "Obstacle %s stands off the ice" % item.name)
	var obstacles := arena.get_node("MaelstromObstacles")
	check(obstacles.get_child_count() == items.size(), "Obstacle bodies differ from the list")
	for body: StaticBody3D in obstacles.get_children():
		# Seracs and masts shatter on contact: on the prop layer only, so no bot collides with them.
		var model := String(body.get_meta(&"maelstrom_obstacle").model)
		var shatter := model.begins_with("ice_shards") or model.begins_with("wreck_mast")
		check(body.collision_layer == (BaselineConfig.PROP_LAYER if shatter else 1) and body.collision_mask == 2, "Obstacle layers differ from the arena shell: %s" % body.name)
	# Breakables: mirrored, registered as ArenaProps with their prefixes, off the pads.
	var breakables := GROUND.breakables()
	check(breakables.size() >= 20 and arena.get_node("MaelstromBreakables").get_child_count() == breakables.size(), "Breakable props missing")
	var seracs := items.filter(func(item: Dictionary) -> bool: return String(item.model).begins_with("ice_shards") or String(item.model).begins_with("wreck_mast"))
	check(world.props.props.size() == breakables.size() + seracs.size(), "Every serac, mast, rib, icicle, barrel and crate registers as a prop (%d)" % world.props.props.size())
	for item: Dictionary in breakables:
		check(breakables.any(func(o: Dictionary) -> bool: return o.kind == item.kind and o.at.distance_to(Vector3(-item.at.x, item.at.y, -item.at.z)) < 0.01), "Breakable lacks its mirror: %s" % item.name)
		check(GROUND.on_ice(item.at.x, item.at.z), "Breakable %s stands off the ice" % item.name)
	for kind: String in ["barrel", "serac"]:
		var target: String = world.props.props.keys().filter(func(n: String) -> bool: return world.props.props[n].kind == kind)[0]
		var body: StaticBody3D = world.props.props[target].body
		check(world.props.damage(target, 5000.0, "cannon", body.global_position, Vector3.FORWARD) >= 0.0 and body.collision_layer == 0,
			"A %s breaks and stops colliding" % kind)
	world.props.reset_round()
	# An inverted cone, steepest into the eye (up to 45 degrees there) and at
	# the banks of the start landings; nothing past the 50 degrees tracks hold on. Slab ramps excepted.
	var steep := 0
	var samples := 0
	for i: int in 6000:
		var a := i * 2.39996
		var r := lerpf(cfg.eye_radius + 1.5, cfg.rim_radius - 3.0, fmod(i * 0.6180339, 1.0))
		var p := Vector2(cos(a), sin(a)) * r
		if not GROUND.on_ice(p.x + 1.0, p.y) or not GROUND.on_ice(p.x, p.y + 1.0) or _on_slab(p, cfg):
			continue
		var h := GROUND.height_at(p.x, p.y)
		var gx := GROUND.height_at(p.x + 0.5, p.y) - h
		var gz := GROUND.height_at(p.x, p.y + 0.5) - h
		samples += 1
		var limit := 45.0 if r < 45.0 else 50.0
		if Vector2(gx, gz).length() / 0.5 > tan(deg_to_rad(limit)):
			steep += 1
			if steep <= 5:
				print("STEEP at ", p, " r=", p.length(), " slope=", Vector2(gx, gz).length() / 0.5)
	check(samples > 4000 and steep == 0, "%d of %d ice samples are steeper than allowed (45 degrees by the eye, 50 elsewhere)" % [steep, samples])
	var space := arena.get_world_3d().direct_space_state
	# Starts, Practice Duel places, pickups and cooling points: on level ice, clear.
	var clear_points: Array[Vector3] = []
	for marker: Node3D in arena.get_node("SpawnPoints").get_children():
		clear_points.append(marker.position)
	var spawns := ArenaSpawns.settings()
	var duel := spawns.duel_centre_for("maelstrom")
	var reach := ArenaBounds.half_extent("maelstrom") * spawns.duel_monowheel_side_for("maelstrom")
	for offset: Vector3 in [Vector3.ZERO, Vector3(0, 0, -reach), Vector3(-reach, 0, 0), Vector3(reach, 0, 0)]:
		clear_points.append(duel + offset)
	var others: Array[Vector3] = world.pickup_points() + world.cooling_zones() + world.coolant_points()
	var starts := clear_points.size()
	var index := 0
	for point: Vector3 in clear_points + others:
		var is_start := index < starts
		index += 1
		check(GROUND.on_ice(point.x, point.z) and Vector2(point.x, point.z).length() > cfg.eye_radius + 8.0, "%s is not on the ice" % str(point))
		var clearance := SphereShape3D.new()
		clearance.radius = 7.0
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = clearance
		query.collision_mask = 1
		query.transform.origin = Vector3(point.x, GROUND.height_at(point.x, point.z) + 7.3, point.z)
		# Starts must be clear of everything; pickups and cooling points may sit
		# beside a breakable barrel or icicle.
		var hits := space.intersect_shape(query).filter(func(hit: Dictionary) -> bool: return _crowds(hit, is_start))
		check(hits.is_empty(), "Obstacle crowds %s: %s" % [str(point), str(hits.map(func(hit: Dictionary) -> String: return String(hit.collider.name)))])
	for point: Vector3 in clear_points:
		for dx: float in [-5.0, 0.0, 5.0]:
			for dz: float in [-5.0, 0.0, 5.0]:
				# Terraces cut into the tilt: level where the bots park.
				check(absf(GROUND.height_at(point.x + dx, point.z + dz) - GROUND.height_at(point.x, point.z)) < 0.05, "Pad is not level at %s" % str(point))
	# The two teams start on opposite sides of the eye.
	var first: Vector3 = arena.get_node("SpawnPoints/Team1_3").position
	var second: Vector3 = arena.get_node("SpawnPoints/Team2_3").position
	check(Vector2(first.x + second.x, first.z + second.z).length() < 0.01 and Vector2(first.x, first.z).length() > 80.0, "Duel starts are not across the eye")
	var spawned := world.spawn(1, 0, 0, world.registry.starter(true), 5)
	var origin: Vector3 = spawned.spawn_pose.origin if spawned else Vector3.ZERO
	check(spawned != null and origin.y > GROUND.height_at(origin.x, origin.z) + 0.05, "Maelstrom spawn height %s" % str(origin))
	world.clear_bots()
	var art := arena.get_node("FoundryVisuals")
	check(art.find_children("*", "CollisionObject3D", true, false).is_empty(), "Art created gameplay collision")
	if DisplayServer.get_name() == "headless":
		check(art.get_child_count() == 0, "Headless arena constructed presentation")
		check(arena.find_children("*", "VisualInstance3D", true, false).is_empty(), "Headless world kept visuals")
	else:
		await process_frame
		await process_frame
		check(art.find_children("*", "MeshInstance3D", true, false).size() > 40, "Maelstrom art did not build")
		if "--capture" in OS.get_cmdline_user_args():
			await _capture(world)
	world.queue_free()
	await process_frame
	print("MAELSTROM PASS" if failures == 0 else "MAELSTROM FAIL")
	quit(0 if failures == 0 else 1)

func _crowds(hit: Dictionary, is_start: bool) -> bool:
	return hit.collider.name != "MaelstromIce" and (is_start or hit.collider.collision_layer & BaselineConfig.PROP_LAYER == 0)

func _on_slab(p: Vector2, cfg: RefCounted) -> bool:
	for slab: Dictionary in cfg.slabs:
		for sign: float in [1.0, -1.0]:
			if p.distance_to(Vector2(float(slab.at[0]), float(slab.at[1])) * sign) < Vector2(float(slab.length), float(slab.width)).length() * 0.5 + 4.0:
				return true
	return false

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
	camera.far = 4000
	var registry := ContentRegistry.new()
	for index: int in range(2):
		var bot := MvpBot.create(index + 1, index, registry.starter(index == 1), registry)
		world.add_child(bot)
		bot.body.freeze = true
		var at := Vector3(-6 + index * 14, 0, 70 - index * 10)
		bot.body.position = at + Vector3(0, GROUND.height_at(at.x, at.z) + bot.ground_clearance() + 0.05, 0)
		bot.body.rotation.y = index * PI + 0.35
		bot.previous_pose = bot.body.global_transform
	var views := [
		["overview", Vector3(0, 70, 165), Vector3(0, -4, 20)],
		["high", Vector3(-150, 210, -150), Vector3(0, -10, 0)],
		["chase", Vector3(-2, 7.0, 96), Vector3(0, 2.0, 40)],
		["eye", Vector3(28, 14.0, 30), Vector3(0, -14.0, 0)],
		["bow", Vector3(-40, 6.0, 70), Vector3(-66, 7.0, 48)],
		["stern", Vector3(-48, 6.0, -2), Vector3(-66, 6.0, -24)],
		["deck", Vector3(-68, 5.0, -36), Vector3(-80, 3.0, -58)],
		["keel", Vector3(-28, 4.0, 46), Vector3(-46, 4.0, 30)],
		["rim", Vector3(-88, 8.0, -66), Vector3(-160, 2.0, -110)],
		["spire", Vector3(-70, 6.0, 30), Vector3(-104, 14.0, 16)],
		["banner", Vector3(-72, 6.0, 30), Vector3(-66, 14.0, 44)],
		["wave", Vector3(-30, 5.0, 34), Vector3(-50, 1.5, 50)],
		# Breaks a serac, a mast and an icicle clump in front of the camera.
		["break", Vector3(-24, 12.0, 0), Vector3(-40, 4.0, -12)],
		# Arena-select card (ui/menus/art/arena_maelstrom.jpg): across the eye toward the wrecks.
		["card", Vector3(46, 40.0, 112), Vector3(-18, 2.0, -4)],
	]
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			only = arg.substr(7)
	var output := "res://exports/maelstrom-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var ignore := FileAccess.open(output + "/.gdignore", FileAccess.WRITE)
	ignore.close()
	for view: Array in views:
		if only != "" and view[0] != only:
			continue
		# View heights are metres above the ice under each point (the ring is a cone).
		var eye: Vector3 = view[1]
		var aim: Vector3 = view[2]
		camera.position = eye + Vector3(0, _view_ground(eye), 0)
		camera.look_at(aim + Vector3(0, _view_ground(aim), 0))
		if view[0] == "break":
			for kind: String in ["serac", "mast", "icicle"]:
				var nearest := ""
				for n: String in world.props.props:
					if world.props.props[n].kind == kind and (nearest == "" or (world.props.props[n].at as Vector3).distance_to(view[2]) < (world.props.props[nearest].at as Vector3).distance_to(view[2])):
						nearest = n
				if nearest != "":
					world.props.damage(nearest, 1.0e6, "cannon", world.props.props[nearest].at + Vector3(4, 2, 0), Vector3.LEFT)
		for frame: int in range(25 if view[0] == "break" else 45):
			await process_frame
			await RenderingServer.frame_post_draw
		var path: String = output + "/maelstrom-" + view[0] + ".png"
		var image := root.get_texture().get_image()
		check(image.save_png(path) == OK, "Capture failed")
		if view[0] == "card":
			check(image.save_jpg("res://ui/menus/art/arena_maelstrom.jpg", 0.88) == OK, "Card capture failed")
		print("CAPTURE: ", ProjectSettings.globalize_path(path))

# Camera heights follow the ice; over the chasm they follow the rim instead.
func _view_ground(at: Vector3) -> float:
	return maxf(GROUND.height_at(at.x, at.z), GROUND.bowl_at(Vector2(at.x, at.z).length()))
