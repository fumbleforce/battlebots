class_name AuthorityWorld
extends Node3D
## Physics-only session world. The session owns timing, commands and match rules.
## Emitted after a pickup (or a replicated swap) changes a bot's match loadout.
## A body/drive/weapon change replaces the MvpBot node under the same entity id.
signal loadout_changed(entity_id: int)
var bots: Dictionary = {}
var registry := ContentRegistry.new()
var weapons := CombatWorld.new()
var tick := 0
var credited: Dictionary = {}
var pickups := MatchPickups.new()
var arena: Node3D
var arena_id := "foundry"

func _ready() -> void:
	_build_arena()

func set_arena(id: String) -> void:
	assert(id in ArenaBounds.IDS)
	if id == arena_id:
		return
	clear_bots()
	arena_id = id
	if is_instance_valid(arena):
		remove_child(arena)
		arena.free()
	_build_arena()

func _build_arena() -> void:
	var scene: PackedScene = preload("res://scenes/arenas/baseline_arena.tscn")
	if arena_id == "moon":
		scene = preload("res://scenes/arenas/moon_arena.tscn")
	elif arena_id == "woodland":
		scene = preload("res://scenes/arenas/woodland_arena.tscn")
	arena = scene.instantiate()
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
	bot.arena_half_extent = ArenaBounds.half_extent(arena_id)
	bot.camera_anchor().set_meta(&"arena_half_extent", bot.arena_half_extent)
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
	# the octagon's chamfers. Each arena publishes its own inner planes.
	var arena_half := ArenaBounds.half_extent(arena_id)
	var pose := authored
	var half: Vector3 = bot.collision_bounds().size * 0.5
	var extent_x := absf(pose.basis.x.x) * half.x + absf(pose.basis.z.x) * half.z
	var extent_z := absf(pose.basis.x.z) * half.x + absf(pose.basis.z.z) * half.z
	const WALL_GAP := 0.25
	pose.origin.x = clampf(pose.origin.x, -arena_half + extent_x + WALL_GAP, arena_half - extent_x - WALL_GAP)
	pose.origin.z = clampf(pose.origin.z, -arena_half + extent_z + WALL_GAP, arena_half - extent_z - WALL_GAP)
	for side_x: float in [-1.0, 1.0]:
		for side_z: float in [-1.0, 1.0]:
			var normal := Vector3(side_x, 0, side_z)
			var reach := absf(normal.dot(pose.basis.x)) * half.x + absf(normal.dot(pose.basis.z)) * half.z
			var bound := (arena_half - WALL_GAP) * sqrt(2.0) - side_x * pose.origin.x - reach
			pose.origin.z = minf(pose.origin.z, bound) if side_z > 0 else maxf(pose.origin.z, -bound)
	var floor_y := 0.0
	# Terrain arenas: the physical height map is a linear interpolation of these
	# vertices. Include every cell beneath the hull, so no corner starts in a
	# slope even when the authored centre lies on a smaller flattened pad.
	var surface: Script = null
	if arena_id == "moon":
		surface = preload("res://scripts/arena/moon_surface.gd")
	elif arena_id == "woodland":
		surface = preload("res://scripts/arena/woodland_ground.gd")
	if surface != null:
		var step: float = surface.get("STEP")
		var low_x := floori((pose.origin.x - extent_x + arena_half) / step)
		var high_x := ceili((pose.origin.x + extent_x + arena_half) / step)
		var low_z := floori((pose.origin.z - extent_z + arena_half) / step)
		var high_z := ceili((pose.origin.z + extent_z + arena_half) / step)
		for x: int in range(low_x, high_x + 1):
			for z: int in range(low_z, high_z + 1):
				floor_y = maxf(floor_y, surface.height_at(x * step - arena_half, z * step - arena_half))
	# B publishes actual support clearance; tall modular hulls retain the common
	# authoring scale height in stats. See coordination/B_ATLAS_MX.md.
	var clearance := bot.ground_clearance()
	pose.origin.y = floor_y + clearance + 0.05
	return pose

func reset_round() -> void:
	weapons = CombatWorld.new()
	credited.clear()
	pickups.reset_round()
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
	if active:
		_collect_pickups(delta)

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
	pickups.clear()
	weapons = CombatWorld.new()

## Pickup points avoid the team spawn lanes on the Z axis: one at the centre and
## four on the diagonals, scaled to the arena. Terrain arenas follow their ground.
func pickup_points() -> Array[Vector3]:
	var half := ArenaBounds.half_extent(arena_id)
	var points: Array[Vector3] = [Vector3.ZERO]
	for angle: float in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		points.append(Vector3(cos(angle), 0.0, sin(angle)) * half * 0.5)
	var surface: Script = null
	if arena_id == "moon":
		surface = preload("res://scripts/arena/moon_surface.gd")
	elif arena_id == "woodland":
		surface = preload("res://scripts/arena/woodland_ground.gd")
	if surface != null:
		for index: int in points.size():
			points[index].y = surface.height_at(points[index].x, points[index].z)
	return points

## Stocks every point that is clear of the bots' spawn poses, so nobody collects
## an item on the first frame (Practice places the player beside the centre).
func begin_pickups(seed: int) -> void:
	const SPAWN_CLEARANCE := 3.0
	var clear: Array[Vector3] = []
	for point: Vector3 in pickup_points():
		var blocked := false
		for bot: MvpBot in bots.values():
			var size: Vector3 = bot.collision_bounds().size
			var at := bot.spawn_pose.origin
			var reach := maxf(size.x, size.z) * 0.5 + 0.5 + SPAWN_CLEARANCE
			blocked = blocked or Vector2(at.x - point.x, at.z - point.z).length() <= reach
		if not blocked:
			clear.append(point)
	pickups.begin(clear, seed)

func _collect_pickups(delta: float) -> void:
	pickups.tick(delta)
	var ids: Array = bots.keys()
	ids.sort()
	for item: Dictionary in pickups.items:
		if not item.available:
			continue
		for id: int in ids:
			var bot: MvpBot = bots[id]
			# Practice NPCs keep their authored training builds.
			if bot.combat.eliminated or bot.has_meta("practice_variant") or not touches_pickup(bot, item.point):
				continue
			var event := pickups.collect(item, id, bot.loadout)
			if event.is_empty():
				continue
			if event.has("loadout"):
				apply_loadout(id, event.loadout)
			break

## A pickup is a vertical column: the hull footprint must overlap the point
## horizontally, and some part of the hull must lie between REACH_DOWN below the
## point and the top of its REACH_UP light beam, so jumping and launched bots
## still collect it.
func touches_pickup(bot: MvpBot, point: Vector3) -> bool:
	var size: Vector3 = bot.collision_bounds().size
	var at := bot.body.global_position
	if Vector2(at.x - point.x, at.z - point.z).length() > maxf(size.x, size.z) * 0.5 + 0.5:
		return false
	var above := at.y - point.y
	return above >= -(size.y * 0.5 + MatchPickups.REACH_DOWN) and above <= MatchPickups.REACH_UP + size.y * 0.5

## Applies a match loadout to a live bot. Perk-only changes update the existing
## bot; any other slot rebuilds it in place, keeping pose, motion, owner, score
## counters and damage fractions. The part in each changed slot arrives intact.
## Clients call this for replicated swaps; they never choose loadouts themselves.
func apply_loadout(id: int, loadout: Dictionary) -> MvpBot:
	var old: MvpBot = bots.get(id)
	var validation := pickups.registry.validate(loadout)
	if old == null or not validation.valid:
		return null
	var changed: Array[String] = []
	for slot: String in ContentRegistry.SLOTS:
		if old.loadout.parts.get(slot) != validation.loadout.parts[slot]:
			changed.append(slot)
	if changed.is_empty() and old.loadout.get("cosmetics") == validation.loadout.get("cosmetics"):
		return old
	var perks_only := true
	for slot: String in changed:
		perks_only = perks_only and slot in MatchPickups.PERK_SLOTS
	if perks_only and old.loadout.get("cosmetics") == validation.loadout.get("cosmetics"):
		old.loadout = validation.loadout
		old.combat.stats.nitro = validation.stats.nitro
		old.combat.stats.charged_jump = validation.stats.charged_jump
		old.body.nitro_equipped = validation.stats.nitro
		old.body.jump_equipped = validation.stats.charged_jump
		loadout_changed.emit(id)
		return old
	var bot := MvpBot.create(id, old.team, validation.loadout, pickups.registry)
	bot.name = old.name
	bot.owner_id = old.owner_id
	bot.server_tick = old.server_tick
	bot.last_sequence = old.last_sequence
	bot.input_age = old.input_age
	bot.command = old.command
	bot.simulated = old.simulated
	bot.remote_state = old.remote_state
	for key: StringName in old.get_meta_list():
		bot.set_meta(key, old.get_meta(key))
	var pose := old.body.global_transform
	var display := old.presentation.global_transform
	var linear := old.body.linear_velocity
	var angular := old.body.angular_velocity
	var pending: Variant = old.body.reset_pose
	var old_clearance := old.ground_clearance()
	var authored_spawn := old.spawn_pose
	var old_combat := old.combat
	var frozen := old.body.freeze
	remove_child(old)
	old.queue_free()
	bots[id] = bot
	add_child(bot)
	bot.arena_half_extent = ArenaBounds.half_extent(arena_id)
	bot.camera_anchor().set_meta(&"arena_half_extent", bot.arena_half_extent)
	bot.body.gravity_scale = 1.62 / 9.8 if arena_id == "moon" else 1.0
	carry_combat(old_combat, bot.combat, changed)
	# A taller replacement starts clear of the floor it was standing on.
	var lift := maxf(0.0, bot.ground_clearance() - old_clearance)
	pose.origin.y += lift + (0.05 if lift > 0.0 else 0.0)
	display.origin.y += lift
	bot.body.global_transform = pose
	bot.presentation.global_transform = display
	bot.previous_pose = pose
	bot.last_floor = old.last_floor
	bot.spawn_pose = clear_spawn_pose(bot, authored_spawn)
	bot.body.reset_pose = clear_spawn_pose(bot, pending) if pending is Transform3D else null
	bot.body.freeze = frozen
	if not frozen:
		bot.body.linear_velocity = linear
		bot.body.angular_velocity = angular
	if old_combat.eliminated:
		bot.body.collision_layer = 0
		bot.body.collision_mask = 0
	loadout_changed.emit(id)
	return bot

static func carry_combat(from: CombatState, to: CombatState, changed: Array[String]) -> void:
	to.core = to.stats.core * clampf(from.core / float(from.stats.core), 0.0, 1.0)
	var fixed := {"drive_left":100.0, "drive_right":100.0, "weapon":140.0}
	for zone: String in to.zones:
		var fresh := (zone == "weapon" and "weapon" in changed) 			or (zone.begins_with("drive_") and "drive" in changed)
		if fresh:
			continue
		var old_max: float = fixed.get(zone, float(from.stats.plates.get(zone, 0.0)))
		var new_max: float = fixed.get(zone, float(to.stats.plates.get(zone, 0.0)))
		# Armour that was not fitted before arrives intact; fitted armour keeps its wear.
		if old_max <= 0.0 or not from.zones.has(zone):
			continue
		to.zones[zone] = new_max * clampf(float(from.zones[zone]) / old_max, 0.0, 1.0)
	for field: String in ["heat", "overheated", "recovery_cooldown", "recovery_remaining",
			"inverted_seconds", "immobilized_seconds", "driven_distance", "eliminated",
			"elimination_reason", "effective_damage", "eliminations", "assists",
			"component_disables", "recovery_count", "jump_cooldown", "attack_id",
			"shot_sequence", "last_shot_tick"]:
		to.set(field, from.get(field))
	to.recent_attackers = from.recent_attackers.duplicate()
