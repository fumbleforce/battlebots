class_name PracticeBotDirector
extends RefCounted
## Offline authority only. These pilots use the same commands, damage and physics
## as a human. Appearance metadata never enters a loadout or a network baseline.
const VARIANTS := ["wedge", "bruiser", "sentry"]
const WRECK_SECONDS := 6.0
## The player's wreck returns to its spawn after this delay instead of a menu.
const PLAYER_RESPAWN_SECONDS := 3.0
const RESET_GRACE := 1.0
var world: AuthorityWorld
var player_id := 0
var target_id := 0
var records: Array[Dictionary] = []
## The four nimble bots (#61) roam wide loops and engage a player who comes
## close. Kept apart from the authored records, which other practice fixtures
## (Woodland edge starts) place by index.
var roamers: Array[Dictionary] = []
var elapsed := 0.0
var player_wreck_age := 0.0
## Counts completed player respawns so presentation can react to each one.
var player_respawns := 0
## Where the player spawns; the Woodland boss moves it to an edge start.
var player_home := Transform3D.IDENTITY

func configure(authority: AuthorityWorld, controlled_id: int, first_id: int) -> int:
	world = authority
	player_id = controlled_id
	target_id = first_id
	var player: MvpBot = world.bots[player_id]
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
		var separation: float = (player.combat.stats.size.z + bot.combat.stats.size.z) * 0.5 + 2.0 * BotScale.FACTOR
		var home := Vector3(0, 0, -separation * 0.5)
		if index == 0:
			_place(player, Transform3D(Basis.IDENTITY, Vector3(0, 0, separation * 0.5)))
		elif index == 1: home = Vector3(-13, 0, -2)
		else: home = Vector3(12, 0, -11)
		_place(bot, Transform3D(Basis(Vector3.UP, PI), home))
		records.append({"id":bot.entity_id, "home":bot.spawn_pose, "index":index,
			"wreck_age":0.0, "previous_primary":false, "patrol":0, "grace":RESET_GRACE})
	player_home = player.spawn_pose
	return _add_roamers(first_id + VARIANTS.size())

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
		if int(record.index) != 0 and float(record.grace) <= 0.0 and not player.combat.eliminated:
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
