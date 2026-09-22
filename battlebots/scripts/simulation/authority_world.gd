class_name AuthorityWorld
extends Node3D
## Physics-only session world. The session owns timing, commands and match rules.
var bots: Dictionary = {}
var registry := ContentRegistry.new()
var weapons := CombatWorld.new()
var tick := 0
var credited: Dictionary = {}
var arena: Node3D
var arena_id := "foundry"

func _ready() -> void:
	_build_arena()

func set_arena(id: String) -> void:
	assert(id in ["foundry", "moon"])
	if id == arena_id:
		return
	clear_bots()
	arena_id = id
	if is_instance_valid(arena):
		remove_child(arena)
		arena.free()
	_build_arena()

func _build_arena() -> void:
	arena = (preload("res://scenes/arenas/moon_arena.tscn") if arena_id == "moon" else preload("res://scenes/arenas/baseline_arena.tscn")).instantiate()
	arena.name = "Arena"
	if DisplayServer.get_name() == "headless":
		_strip_presentation(arena)
	add_child(arena)

func _strip_presentation(node: Node) -> void:
	for child: Node in node.get_children():
		if child is VisualInstance3D or child is WorldEnvironment:
			child.free()
		else:
			_strip_presentation(child)

func make_box(size: Vector3, position: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	node.add_child(collision)
	node.position = position
	if DisplayServer.get_name() != "headless":
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.24, 0.29)
		mesh.material = material
		visual.mesh = mesh
		node.add_child(visual)
	add_child(node)
	return node

func spawn(id: int, team: int, slot: int, loadout: Dictionary, team_size: int = 2, mode: String = "teams") -> MvpBot:
	var bot := MvpBot.create(id, team, loadout, registry)
	if bot == null:
		return null
	bot.name = "Bot%d" % id
	add_child(bot)
	# B's published DriveBody replay_config already includes gravity_scale.
	bot.body.gravity_scale = 1.62 / 9.8 if arena_id == "moon" else 1.0
	var marker_index := slot + 1 if team_size == 5 else (2 if slot == 0 else 4)
	var marker_path := "SpawnPoints/FFA_%d" % (slot + 1) if mode == "ffa" else "SpawnPoints/Team%d_%d" % [team + 1, marker_index]
	var marker := arena.get_node(marker_path) as Node3D
	var pose := clear_spawn_pose(bot, marker.global_transform)
	bot.spawn_pose = pose
	bot.body.reset_pose = pose
	bot.previous_pose = pose
	bot.last_floor = pose.origin
	bots[id] = bot
	return bot

func clear_spawn_pose(bot: MvpBot, authored: Transform3D) -> Transform3D:
	# Keep the authored lane and facing; enlarged outer team slots need room at
	# the octagon's chamfers. These are the existing 50m arena's inner planes.
	var pose := authored
	var half: Vector3 = bot.collision_bounds().size * 0.5
	var extent_x := absf(pose.basis.x.x) * half.x + absf(pose.basis.z.x) * half.z
	var extent_z := absf(pose.basis.x.z) * half.x + absf(pose.basis.z.z) * half.z
	const WALL_GAP := 0.25
	pose.origin.x = clampf(pose.origin.x, -25.0 + extent_x + WALL_GAP, 25.0 - extent_x - WALL_GAP)
	pose.origin.z = clampf(pose.origin.z, -25.0 + extent_z + WALL_GAP, 25.0 - extent_z - WALL_GAP)
	for side_x: float in [-1.0, 1.0]:
		for side_z: float in [-1.0, 1.0]:
			var normal := Vector3(side_x, 0, side_z)
			var reach := absf(normal.dot(pose.basis.x)) * half.x + absf(normal.dot(pose.basis.z)) * half.z
			var bound := (25.0 - WALL_GAP) * sqrt(2.0) - side_x * pose.origin.x - reach
			pose.origin.z = minf(pose.origin.z, bound) if side_z > 0 else maxf(pose.origin.z, -bound)
	var floor_y := 0.0
	if arena_id == "moon":
		# The physical height map is a linear interpolation of these vertices.
		# Include every cell beneath the hull, so no corner starts in a slope even
		# when the authored centre lies on one of the smaller flattened pads.
		const SURFACE = preload("res://scripts/arena/moon_surface.gd")
		var low_x := floori((pose.origin.x - extent_x + 25.0) / SURFACE.STEP)
		var high_x := ceili((pose.origin.x + extent_x + 25.0) / SURFACE.STEP)
		var low_z := floori((pose.origin.z - extent_z + 25.0) / SURFACE.STEP)
		var high_z := ceili((pose.origin.z + extent_z + 25.0) / SURFACE.STEP)
		for x: int in range(low_x, high_x + 1):
			for z: int in range(low_z, high_z + 1):
				floor_y = maxf(floor_y, SURFACE.height_at(x * SURFACE.STEP - 25.0, z * SURFACE.STEP - 25.0))
	# B publishes actual support clearance; tall modular hulls retain the common
	# authoring scale height in stats. See coordination/B_ATLAS_MX.md.
	var clearance := bot.ground_clearance()
	pose.origin.y = floor_y + clearance + 0.05
	return pose

func reset_round() -> void:
	weapons = CombatWorld.new()
	credited.clear()
	for id: int in bots:
		bots[id].reset_round()

func step(delta: float, active: bool, round_index: int) -> void:
	tick += 1
	for id: int in bots:
		bots[id].server_tick = tick
		bots[id].step(delta, active)
	if active:
		weapons.step(delta, bots, tick, round_index)
	for id: int in bots:
		var bot: MvpBot = bots[id]
		if not bot.combat.eliminated or credited.has(id):
			continue
		credited[id] = true
		bot.body.collision_layer = 0
		bot.body.collision_mask = 0
		bot.body.freeze = true
		var latest := -1.0
		var killer := 0
		for source_id: int in bot.combat.recent_attackers:
			var at: float = bot.combat.recent_attackers[source_id]
			if weapons.time - at <= 10 and at > latest:
				latest = at
				killer = source_id
		if killer != 0 and bots.has(killer):
			bots[killer].combat.eliminations += 1
		for source_id: int in bot.combat.recent_attackers:
			if source_id != killer and bots.has(source_id) and weapons.time - float(bot.combat.recent_attackers[source_id]) <= 10:
				bots[source_id].combat.assists += 1

func combatants() -> Dictionary:
	var result := {}
	for id: int in bots:
		result[id] = bots[id].combat
	return result

func clear_bots() -> void:
	for id: int in bots:
		bots[id].queue_free()
	bots.clear()
	credited.clear()
	weapons = CombatWorld.new()
