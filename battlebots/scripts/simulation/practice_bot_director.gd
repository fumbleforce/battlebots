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
var elapsed := 0.0
var player_wreck_age := 0.0
## Counts completed player respawns so presentation can react to each one.
var player_respawns := 0
var _player_home := Transform3D.IDENTITY

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
	_player_home = player.spawn_pose
	return first_id + VARIANTS.size()

func _place(bot: MvpBot, authored: Transform3D) -> void:
	bot.spawn_pose = world.clear_spawn_pose(bot, authored)
	bot.body.reset_pose = bot.spawn_pose
	bot.previous_pose = bot.spawn_pose
	bot.last_floor = bot.spawn_pose.origin

func restart() -> void:
	elapsed = 0.0
	player_wreck_age = 0.0
	# A fallback respawn may have moved the player's spawn; restore the original.
	_place(world.bots[player_id], _player_home)
	for record: Dictionary in records:
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
	for record: Dictionary in records:
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
	var engaging := distance < (17.0 if record.index == 2 else 11.0)
	var desired := player.body.global_position
	if not engaging:
		# Small loops keep both moving targets visible inside the playable octagon.
		var centre: Vector3 = record.home.origin
		var waypoints := [centre + Vector3(0, 0, 4), centre + Vector3(3, 0, 0), centre + Vector3(0, 0, -4), centre + Vector3(-3, 0, 0)]
		desired = waypoints[int(record.patrol)]
		if bot.body.global_position.distance_to(desired) < 2.0:
			record.patrol = (int(record.patrol) + 1) % waypoints.size()
			desired = waypoints[int(record.patrol)]
	var local := bot.body.global_basis.inverse() * (desired - bot.body.global_position)
	var angle := atan2(local.x, -local.z)
	var contact: float = (bot.combat.stats.size.z + player.combat.stats.size.z) * 0.5
	var reach := 11.0 if bot.combat.stats.weapon == "minigun" else contact + 0.4
	intent.throttle = 0.42 if absf(angle) < 0.9 else 0.10
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

func _pose_clear(bot: MvpBot, pose: Transform3D) -> bool:
	var radius: float = Vector2(bot.combat.stats.size.x, bot.combat.stats.size.z).length() * 0.5
	for other: MvpBot in world.bots.values():
		if other == bot or other.combat.eliminated: continue
		var other_radius: float = Vector2(other.combat.stats.size.x, other.combat.stats.size.z).length() * 0.5
		var gap := Vector2(other.body.global_position.x - pose.origin.x, other.body.global_position.z - pose.origin.z)
		if gap.length() < radius + other_radius + 1.0: return false
	return true

func _respawn_player(player: MvpBot) -> void:
	# Prefer the player's own spawn. An NPC parked there must not hold the player
	# out indefinitely, so also try that spot quarter-turned about the symmetric
	# arena's centre; if all are occupied, retry next tick.
	for turn: int in 4:
		var rotation := Basis(Vector3.UP, turn * PI * 0.5)
		var pose := world.clear_spawn_pose(player, Transform3D(rotation * _player_home.basis, rotation * _player_home.origin))
		if not _pose_clear(player, pose): continue
		player.spawn_pose = pose
		player.reset_round()
		world.credited.erase(player.entity_id)
		player_wreck_age = 0.0
		player_respawns += 1
		# NPCs pause briefly so the player is not hit the instant they return.
		for record: Dictionary in records:
			record.grace = RESET_GRACE
		return

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
