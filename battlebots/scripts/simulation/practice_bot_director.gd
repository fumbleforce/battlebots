class_name PracticeBotDirector
extends RefCounted
## Offline authority only. These pilots use the same commands, damage and physics
## as a human. Appearance metadata never enters a loadout or a network baseline.
const ARENA_SPAWNS = preload("res://scripts/core/arena_spawns.gd")
const VARIANTS := ["wedge", "bruiser", "sentry"]
const WRECK_SECONDS := 6.0
## The player's wreck returns to its spawn after this delay instead of a menu.
const PLAYER_RESPAWN_SECONDS := 3.0
const RESET_GRACE := 1.0
## Practice Duel shuttle (#88): metres ahead on its line it steers toward.
const SHUTTLE_LOOKAHEAD := 6.0
var world: AuthorityWorld
var player_id := 0
var target_id := 0
var records: Array[Dictionary] = []
## The four nimble bots (#61) roam wide loops and engage a player who comes
## close. Kept apart from the authored records (calibration target and pilots).
var roamers: Array[Dictionary] = []
var elapsed := 0.0
var player_wreck_age := 0.0
## Counts completed player respawns so presentation can react to each one.
var player_respawns := 0
## Where the player spawns: its team edge (data/arena_spawns.json practice).
var player_home := Transform3D.IDENTITY

func configure(authority: AuthorityWorld, controlled_id: int, first_id: int) -> int:
	world = authority
	player_id = controlled_id
	target_id = first_id
	var player: MvpBot = world.bots[player_id]
	var spawns := ARENA_SPAWNS.settings()
	for index: int in VARIANTS.size():
		var build := world.registry.starter(index == 0)
		build.name = ["BULWARK / calibration", "RAMMER / mobile drone", "WATCHDOG / sentry"][index]
		build.cosmetics.paint = ["white", "red", "cyan"][index]
		if index == 2:
			build.parts.drive = "traction"
			build.parts.weapon = "minigun"
		var bot := MvpBot.create(first_id + index, 1, build, world.registry)
		assert(bot != null, "Practice builds must pass canonical validation")
		bot.name = "Practice_%s_%d" % [VARIANTS[index], bot.entity_id]
		bot.set_meta("practice_variant", VARIANTS[index])
		world.add_child(bot)
		bot.arena_half_extent = ArenaBounds.half_extent(world.arena_id)
		bot.camera_anchor().set_meta(&"arena_half_extent", bot.arena_half_extent)
		world.bots[bot.entity_id] = bot
		bot.body.gravity_scale = 1.62 / 9.8 if world.arena_id == "moon" else 1.0
		if index == 0:
			# The player starts at its own edge with the calibration target ahead.
			_place(player, spawns.team_start(world.arena_id, 0, spawns.practice_player_lane))
			var separation: float = (player.combat.stats.size.z + bot.combat.stats.size.z) * 0.5 + spawns.practice_target_gap
			var ahead := -player.spawn_pose.basis.z.slide(Vector3.UP).normalized()
			_place(bot, Transform3D(player.spawn_pose.basis.rotated(Vector3.UP, PI), player.spawn_pose.origin + ahead * separation))
		else:
			# Mobile pilots start on the flanks and come to find the player.
			var starts := spawns.practice_pilot_starts
			_place(bot, spawns.ffa_start(world.arena_id, starts[(index - 1) % starts.size()]))
		records.append({"id":bot.entity_id, "home":bot.spawn_pose, "index":index,
			"wreck_age":0.0, "previous_primary":false, "patrol":0, "grace":RESET_GRACE})
	player_home = player.spawn_pose
	return _add_roamers(first_id + VARIANTS.size())

## Practice Duel (#83, #88): the player at its usual edge, a stationary,
## non-aggressive Atlas MX straight ahead facing the player, the monowheel block
## on the left, and a second Atlas on the right that shuttles forward and back.
## The far Atlas and the shuttle stand as far from their walls as the monowheel
## block does from the left wall. No pilots or roamers. The Atlases keep their
## own model and never collect pickups.
func configure_duel(authority: AuthorityWorld, controlled_id: int, first_id: int) -> int:
	world = authority
	player_id = controlled_id
	target_id = first_id
	var player: MvpBot = world.bots[player_id]
	var spawns := ARENA_SPAWNS.settings()
	_place(player, spawns.team_start(world.arena_id, 0, spawns.practice_player_lane))
	player_home = player.spawn_pose
	var forward := (-player.spawn_pose.basis.z).slide(Vector3.UP).normalized()
	var left := Vector3.UP.cross(forward).normalized()
	var facing_player := _facing(-forward)
	var atlas := _add_fixture(first_id, world.registry.atlas(), "atlas", Transform3D(facing_player, Vector3.ZERO))
	var next_id := _add_monowheel_row(player, first_id + 1)
	var reach := _monowheel_reach(left)
	# Back from the player: the Atlas's rear sits as far from the far wall as the
	# block's outer row does from the left wall.
	var depth := maxf(0.0, reach - atlas.collision_bounds().size.z * 0.5)
	_place(atlas, Transform3D(facing_player, forward * depth))
	records[0].home = atlas.spawn_pose
	# On the right, a quarter turn from facing the middle: it faces along the
	# player's forward axis, its side toward the right wall.
	var shuttle := _add_fixture(next_id, world.registry.atlas(), "atlas_shuttle", Transform3D(_facing(forward), -left * reach))
	var inset := maxf(0.0, reach - shuttle.collision_bounds().size.x * 0.5)
	_place(shuttle, Transform3D(_facing(forward), -left * inset))
	records[records.size() - 1].home = shuttle.spawn_pose
	records[records.size() - 1].shuttle = 1.0
	return next_id + 1

## Yaw basis whose forward (-Z) points along direction.
static func _facing(direction: Vector3) -> Basis:
	return Basis(Vector3.UP, atan2(-direction.x, -direction.z))

## How far from the centre, toward the left wall, the monowheel block's outer
## hull edge reaches; the configured block offset when there are none.
func _monowheel_reach(left: Vector3) -> float:
	var reach := -INF
	for bot: MvpBot in world.bots.values():
		if bot.has_meta("practice_fixture") and NimbleBots.enabled(bot.loadout):
			reach = maxf(reach, bot.spawn_pose.origin.dot(left) + bot.collision_bounds().size.z * 0.5)
	if is_finite(reach):
		return reach
	return ArenaBounds.half_extent(world.arena_id) * ARENA_SPAWNS.settings().duel_monowheel_side_for(world.arena_id)

## A tight row of stationary monowheels on the player's left, seen from its
## start, facing into the room (data/arena_spawns.json duel.monowheels).
func _add_monowheel_row(player: MvpBot, next_id: int) -> int:
	var spawns := ARENA_SPAWNS.settings()
	var count := spawns.duel_monowheel_count
	if count <= 0:
		return next_id
	var forward := (-player.spawn_pose.basis.z).slide(Vector3.UP).normalized()
	var left := Vector3.UP.cross(forward).normalized()
	var centre := left * ArenaBounds.half_extent(world.arena_id) * spawns.duel_monowheel_side_for(world.arena_id)
	# Facing into the room: each hull's forward points away from the left wall.
	var facing := Basis(Vector3.UP, atan2(left.x, left.z))
	# Rows one behind the other: the front row nearest the room, the rest
	# stepping back toward the left wall.
	var rows := mini(spawns.duel_monowheel_rows, count)
	var per_row := ceili(float(count) / float(rows))
	var wheels: Array[MvpBot] = []
	for index: int in count:
		wheels.append(_add_fixture(next_id + index, NimbleBots.preset(world.registry, "monowheel_07"), "monowheel", Transform3D(facing, centre)))
	var hull := wheels[0].collision_bounds().size
	var offsets: Array[Vector3] = []
	for index: int in count:
		var row := index / per_row
		var in_row := mini(per_row, count - row * per_row)
		# Hull to hull: width plus the gap along a row, length plus the gap between rows.
		var along := (float(index % per_row) - float(in_row - 1) * 0.5) * (hull.x + spawns.duel_monowheel_gap)
		var back := (float(row) - float(rows - 1) * 0.5) * (hull.z + spawns.duel_monowheel_gap)
		offsets.append(forward * along + left * back)
	for index: int in count:
		_place(wheels[index], Transform3D(facing, centre + offsets[index]))
		records[records.size() - count + index].home = wheels[index].spawn_pose
	return next_id + count

## A stationary, non-aggressive fixture (records index 0: it never drives or
## attacks) that keeps its own model and never collects pickups.
func _add_fixture(id: int, build: Dictionary, label: String, pose: Transform3D) -> MvpBot:
	var bot := MvpBot.create(id, 1, build, world.registry)
	assert(bot != null, "Practice Duel fixtures must pass canonical validation")
	bot.name = "Practice_%s_%d" % [label, bot.entity_id]
	bot.set_meta("practice_fixture", true)
	world.add_child(bot)
	bot.arena_half_extent = ArenaBounds.half_extent(world.arena_id)
	bot.camera_anchor().set_meta(&"arena_half_extent", bot.arena_half_extent)
	world.bots[bot.entity_id] = bot
	bot.body.gravity_scale = 1.62 / 9.8 if world.arena_id == "moon" else 1.0
	_place(bot, pose)
	records.append({"id":bot.entity_id, "home":bot.spawn_pose, "index":0,
		"wreck_age":0.0, "previous_primary":false, "patrol":0, "grace":RESET_GRACE})
	return bot

func _add_roamers(next_id: int) -> int:
	var tuning := NimbleBots.practice()
	if world.arena_id not in tuning.arenas: return next_id
	var radius := ArenaBounds.half_extent(world.arena_id) * float(tuning.home_radius_fraction)
	for index: int in NimbleBots.ORDER.size():
		var chassis: String = NimbleBots.ORDER[index]
		var bot := MvpBot.create(next_id, 1, NimbleBots.preset(world.registry, chassis), world.registry)
		assert(bot != null, "Nimble presets must pass canonical validation")
		bot.name = "Practice_%s_%d" % [chassis, bot.entity_id]
		world.add_child(bot)
		bot.arena_half_extent = ArenaBounds.half_extent(world.arena_id)
		bot.camera_anchor().set_meta(&"arena_half_extent", bot.arena_half_extent)
		world.bots[bot.entity_id] = bot
		bot.body.gravity_scale = 1.62 / 9.8 if world.arena_id == "moon" else 1.0
		# Diagonal ring positions, each facing the arena centre.
		var angle := TAU * (index + 0.5) / NimbleBots.ORDER.size()
		var home := Vector3(cos(angle), 0, sin(angle)) * radius
		_place(bot, Transform3D(Basis(Vector3.UP, atan2(home.x, home.z)), home))
		roamers.append({"id":bot.entity_id, "home":bot.spawn_pose, "index":VARIANTS.size() + index, "roamer":true,
			"wreck_age":0.0, "previous_primary":false, "patrol":0, "grace":RESET_GRACE})
		next_id += 1
	return next_id

func _place(bot: MvpBot, authored: Transform3D) -> void:
	bot.spawn_pose = world.clear_spawn_pose(bot, authored)
	bot.body.reset_pose = bot.spawn_pose
	bot.previous_pose = bot.spawn_pose
	bot.last_floor = bot.spawn_pose.origin

func restart() -> void:
	elapsed = 0.0
	player_wreck_age = 0.0
	# A fallback respawn may have moved the player's spawn; restore the original.
	_place(world.bots[player_id], player_home)
	for record: Dictionary in records + roamers:
		record.wreck_age = 0.0
		record.previous_primary = false
		record.patrol = 0
		if record.has("shuttle"): record.shuttle = 1.0
		record.grace = RESET_GRACE
		var bot: MvpBot = world.bots[record.id]
		_place(bot, record.home)

func step(delta: float) -> void:
	if not is_instance_valid(world) or not world.bots.has(player_id): return
	elapsed += delta
	var player: MvpBot = world.bots[player_id]
	if player.combat.eliminated:
		player_wreck_age += delta
		if player_wreck_age >= PLAYER_RESPAWN_SECONDS:
			_respawn_player(player)
	else:
		player_wreck_age = 0.0
	for record: Dictionary in records + roamers:
		var bot: MvpBot = world.bots[record.id]
		if bot.combat.eliminated:
			record.wreck_age += delta
			if record.wreck_age >= WRECK_SECONDS:
				_try_respawn(bot, record)
			continue
		record.wreck_age = 0.0
		record.grace = maxf(0.0, float(record.grace) - delta)
		var intent := BotCommand.new()
		intent.sequence = bot.last_sequence + 1
		intent.brake = true
		if record.has("shuttle"):
			if float(record.grace) <= 0.0: _shuttle(bot, record, intent)
		elif int(record.index) != 0 and float(record.grace) <= 0.0 and not player.combat.eliminated:
			_pilot(bot, player, record, intent)
		# The calibration target never drives or attacks, but can recover after a flip.
		intent.recovery_pressed = bot.body.global_basis.y.y < -0.25 and bot.combat.recovery_cooldown <= 0.0
		intent.primary_pressed = intent.primary_held and not bool(record.previous_primary)
		record.previous_primary = intent.primary_held
		bot.submit_command(intent)

func _pilot(bot: MvpBot, player: MvpBot, record: Dictionary, intent: BotCommand) -> void:
	var offset := player.body.global_position - bot.body.global_position
	offset.y = 0.0
	var distance := offset.length()
	var roaming: bool = record.get("roamer", false)
	var tuning := NimbleBots.practice()
	var engaging := distance < (float(tuning.engage_distance) if roaming else (17.0 if record.index == 2 else 11.0))
	var desired := player.body.global_position
	if not engaging:
		# Small loops keep both moving targets visible inside the playable octagon;
		# the quick roamers race wider loops around their own homes.
		var centre: Vector3 = record.home.origin
		var waypoints := [centre + Vector3(0, 0, 4), centre + Vector3(3, 0, 0), centre + Vector3(0, 0, -4), centre + Vector3(-3, 0, 0)]
		if roaming:
			waypoints.clear()
			for point: int in int(tuning.patrol_points):
				var angle := TAU * point / float(tuning.patrol_points)
				waypoints.append(centre + Vector3(cos(angle), 0, sin(angle)) * float(tuning.patrol_radius))
		desired = waypoints[int(record.patrol) % waypoints.size()]
		if bot.body.global_position.distance_to(desired) < (4.0 if roaming else 2.0):
			record.patrol = (int(record.patrol) + 1) % waypoints.size()
			desired = waypoints[int(record.patrol)]
	var local := bot.body.global_basis.inverse() * (desired - bot.body.global_position)
	var angle := atan2(local.x, -local.z)
	var contact: float = (bot.combat.stats.size.z + player.combat.stats.size.z) * 0.5
	var reach := 11.0 if bot.combat.stats.weapon == "minigun" else contact + 0.4
	intent.throttle = (float(tuning.patrol_throttle) if roaming else 0.42) if absf(angle) < 0.9 else 0.10
	if engaging:
		intent.throttle = clampf((distance - reach) * 0.2, -0.20, 0.50) if absf(angle) < 0.9 else 0.0
		intent.primary_held = absf(angle) < 0.18 and distance < reach + 2.2
		if bot.combat.stats.weapon == "hammer": intent.primary_held = intent.primary_held and fmod(elapsed, 2.3) < 0.25
	# The pilot requests facing yaw; convert it to vehicle steering so retreating
	# continues to face the player under the same controls used by human drivers.
	var forward := (-bot.body.global_basis.z).slide(Vector3.UP).normalized()
	intent.steering = clampf(angle * 1.5, -1.0, 1.0) * DriveModel.steering_direction(
		bot.body.linear_velocity.dot(forward), intent.throttle)
	intent.brake = absf(intent.throttle) < 0.06 and absf(angle) < 0.12

## Practice Duel shuttle (#88): drives along its home heading, reversing at
## duel.shuttle travel metres either side of home without turning or attacking.
## It steers for a point ahead on its own line, so knocks and reversing do not
## walk it off course.
func _shuttle(bot: MvpBot, record: Dictionary, intent: BotCommand) -> void:
	var spawns := ARENA_SPAWNS.settings()
	var home: Transform3D = record.home
	var axis := (-home.basis.z).slide(Vector3.UP).normalized()
	var along := (bot.body.global_position - home.origin).dot(axis)
	if along >= spawns.duel_shuttle_travel: record.shuttle = -1.0
	elif along <= -spawns.duel_shuttle_travel: record.shuttle = 1.0
	intent.brake = false
	intent.throttle = spawns.duel_shuttle_throttle * float(record.shuttle)
	# Aim for a point on the line in the direction of travel. Reversing, the rear
	# leads: face directly away from that point instead.
	var position := bot.body.global_position
	var aim := home.origin + axis * (along + SHUTTLE_LOOKAHEAD * float(record.shuttle))
	var desired := aim if float(record.shuttle) > 0.0 else position * 2.0 - aim
	var local := bot.body.global_basis.inverse() * (desired - position)
	var forward := (-bot.body.global_basis.z).slide(Vector3.UP).normalized()
	intent.steering = clampf(atan2(local.x, -local.z) * 1.5, -1.0, 1.0) * DriveModel.steering_direction(
		bot.body.linear_velocity.dot(forward), intent.throttle)

## Seconds until the knocked-out player returns; NAN while the player is alive.
func player_respawn_remaining() -> float:
	if not is_instance_valid(world) or not world.bots.has(player_id) or not world.bots[player_id].combat.eliminated:
		return NAN
	return maxf(0.0, PLAYER_RESPAWN_SECONDS - player_wreck_age)

## Smallest spare gap (m) between a bot placed at pose and any live bot;
## negative when it would sit inside another bot's clearance.
func _clearance(bot: MvpBot, pose: Transform3D) -> float:
	var radius: float = Vector2(bot.combat.stats.size.x, bot.combat.stats.size.z).length() * 0.5
	var spare := INF
	for other: MvpBot in world.bots.values():
		if other == bot or other.combat.eliminated: continue
		var other_radius: float = Vector2(other.combat.stats.size.x, other.combat.stats.size.z).length() * 0.5
		var gap := Vector2(other.body.global_position.x - pose.origin.x, other.body.global_position.z - pose.origin.z)
		spare = minf(spare, gap.length() - (radius + other_radius + 1.0))
	return spare

func _pose_clear(bot: MvpBot, pose: Transform3D) -> bool:
	return _clearance(bot, pose) >= 0.0

## The player's own spawn first, then the arena's authored spawn markers
## nearest to it. They spread around the whole arena, so pilots gathered
## where the player fell cannot cover them all.
func _player_candidates(player: MvpBot) -> Array[Transform3D]:
	var candidates: Array[Transform3D] = [player_home]
	var markers := world.arena.get_node_or_null("SpawnPoints") if is_instance_valid(world.arena) else null
	if markers != null:
		var authored: Array[Transform3D] = []
		for marker: Node in markers.get_children():
			if marker is Node3D:
				authored.append(world.clear_spawn_pose(player, (marker as Node3D).global_transform))
		authored.sort_custom(func(a: Transform3D, b: Transform3D) -> bool:
			return a.origin.distance_squared_to(player_home.origin) < b.origin.distance_squared_to(player_home.origin))
		candidates.append_array(authored)
	return candidates

func _respawn_player(player: MvpBot) -> void:
	# Use the first clear candidate. The player must never be held out, so if
	# every one is covered, fall back to the roomiest.
	var best := player_home
	var best_spare := -INF
	for pose: Transform3D in _player_candidates(player):
		var spare := _clearance(player, pose)
		if spare >= 0.0:
			best = pose
			break
		if spare > best_spare:
			best = pose
			best_spare = spare
	player.spawn_pose = best
	player.reset_round()
	world.credited.erase(player.entity_id)
	player_wreck_age = 0.0
	player_respawns += 1
	# NPCs pause briefly so the player is not hit the instant they return.
	for record: Dictionary in records + roamers:
		record.grace = RESET_GRACE

func _try_respawn(bot: MvpBot, record: Dictionary) -> void:
	# Reuse the stable entity; do not reset the world, player, weapon clock or IDs.
	# If its home is occupied, defer regeneration until it is safe to materialize.
	var pose: Transform3D = record.home
	if not _pose_clear(bot, pose): return
	bot.spawn_pose = pose
	bot.reset_round()
	world.credited.erase(bot.entity_id)
	record.wreck_age = 0.0
	record.previous_primary = false
	record.grace = RESET_GRACE
	if record.has("shuttle"): record.shuttle = 1.0
