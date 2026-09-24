class_name WoodlandBoss
extends RefCounted
## Woodland's roaming giant (#45, #79): hunts the nearest bot in Practice and in
## LAN/online Woodland matches. Taking it down leaves one guaranteed top-tier
## part pickup where it fell; the giant rebuilds later. In matches it is a
## neutral hazard: match rules, results and rewards only count players.
##
## The boss is an ordinary MvpBot on its own team, driven through BotCommand
## like any pilot. Its size, core, armour and mass are scaled on the derived
## stats before it enters the tree, so collision, weapon reach, visuals and
## damage all follow the one existing size contract. No catalogue, wire or
## combat-rule change.
const SCALE := 3.5
const CORE_SCALE := 25.0
const ARMOUR_SCALE := 12.0
## Neutral: never equal to a player team (FFA teams are entity ids).
const TEAM := 1000
## Baseline `npcs` kind that tells clients to build a replica (see replica()).
const NPC_KIND := "woodland_boss"
const REBUILD_SECONDS := 60.0
const RETARGET_SECONDS := 1.5
## The turret fires only once its bore is within this angle of the prey (#81).
const AIM_TOLERANCE := deg_to_rad(1.2)
## Pitch/roll rate (rad/s) the stabilisers allow while driving, and while a
## committed volley is firing (recoil otherwise walks the later shells off).
const TILT_RATE_LIMIT := 0.35
const VOLLEY_TILT_RATE_LIMIT := 0.03
## Strongest first; the drop is the first one the killer can actually fit.
const DROPS := ["turret_plasma_quad", "turret_cannon_quad", "hammer", "vertical_spinner"]

var world: AuthorityWorld
var boss: MvpBot
var boss_id := 0
var home := Transform3D.IDENTITY
var target_id := 0
var drop_item_id := -1
var _retarget := 0.0
var _wreck := 0.0
var _stuck := 0.0
var _reverse := 0.0
var _clock := 0.0
var _previous_primary := false

## The giant's loadout: Atlas MX hull, traction, hammer and a quad cannon turret.
static func build(registry: ContentRegistry) -> Dictionary:
	var draft := registry.starter()
	draft.name = "WARDEN OF THE WOODS"
	draft.parts = {"chassis":"atlas_mx", "drive":"traction", "weapon":"hammer", "utility":"turret_cannon_quad",
		"nitro":"nitro_off", "suspension":"jump_off"}
	var look := SawbladeConfig.defaults()
	look.armor_front = 1
	look.armor_top = 1
	look.armor_rear = 1
	look.paint_primary = [0.2, 0.035, 0.03, 1.0]
	look.paint_secondary = [0.03, 0.03, 0.032, 1.0]
	draft.cosmetics = {"paint":"red", "sawblade":look}
	return draft

## Moves the player and practice bots to edge starts and adds the giant.
## Returns the next free entity id.
func configure(authority: AuthorityWorld, first_id: int) -> int:
	world = authority
	boss = replica(world, first_id)
	assert(boss != null, "The Woodland giant must pass canonical validation")
	boss_id = first_id
	home = world.clear_spawn_pose(boss, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, 0)))
	_place(boss, home)
	return first_id + 1

## The giant as built on every peer: the server's authoritative one and each
## client's replica, so scaled stats, collision and drive tuning agree.
static func replica(world: AuthorityWorld, id: int) -> MvpBot:
	var registry := ContentRegistry.new()
	registry.enforce_budget = false
	var bot := MvpBot.create(id, TEAM, build(registry), registry)
	if bot == null:
		return null
	bot.name = "WoodlandGiant"
	bot.set_meta("woodland_boss", true)
	_scale(bot)
	world.add_child(bot)
	bot.arena_half_extent = ArenaBounds.half_extent(world.arena_id)
	bot.camera_anchor().set_meta(&"arena_half_extent", bot.arena_half_extent)
	world.bots[id] = bot
	# A heavy machine needs a strong drive to move its mass at all.
	bot.body.drive_acceleration = 4.2
	bot.body.top_speed = 7.5
	# Gentle, heavy turning: a full-lock pivot rolls a hull this size over.
	bot.body.turn_speed = 0.45
	bot.body.yaw_acceleration_limit = 0.8
	bot.body.lateral_response = 0.12
	# A low centre of mass keeps the giant planted on rocks and ramp lips.
	bot.body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	bot.body.center_of_mass = Vector3(0, -bot.ground_clearance() * 0.9, 0)
	if DisplayServer.get_name() != "headless":
		_dress.call_deferred(bot)
	return bot

## Presentation dressing for the giant: normal-sized damage smoke and a title.
## (Turret effects cap their own scale in TurretShotEffects.MAX_EFFECT_SCALE.)
static func _dress(bot: MvpBot) -> void:
	# Burning/smoking damage effects scale with the hull; keep them normal-sized.
	if bot.damage_visual != null:
		bot.damage_visual.set_geometry_scale(4.0)
	var label := Label3D.new()
	label.name = "GiantTitle"
	label.text = "WARDEN OF THE WOODS"
	label.font_size = 160
	label.pixel_size = 0.02
	label.outline_size = 24
	label.modulate = Color(1.0, 0.45, 0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, bot.combat.stats.size.y * 2.2, 0)
	bot.body.add_child(label)

static func _scale(bot: MvpBot) -> void:
	var stats := bot.combat.stats
	stats.size = stats.size * SCALE
	# Mass by volume: cannon recoil and rams barely move a machine this size.
	stats.mass = float(stats.mass) * SCALE * SCALE * SCALE
	stats.core = float(stats.core) * CORE_SCALE
	stats.speed = float(stats.speed) * 0.8
	bot.combat.core = stats.core
	for face: String in stats.plates:
		stats.plates[face] = float(stats.plates[face]) * ARMOUR_SCALE
		bot.combat.zones[face] = stats.plates[face]
	_boost_subsystems(bot)

## Tracks and weapon mount are not derived from stats, so every CombatState
## reset returns them to normal HP; scale them again after each reset.
static func _boost_subsystems(bot: MvpBot) -> void:
	for zone: String in ["drive_left", "drive_right", "weapon"]:
		bot.combat.zones[zone] = float(bot.combat.zones[zone]) * ARMOUR_SCALE

func _place(bot: MvpBot, pose: Transform3D) -> void:
	bot.spawn_pose = pose
	bot.body.reset_pose = pose
	bot.previous_pose = pose
	bot.last_floor = pose.origin
	bot.body.global_transform = pose

## Called after the session's world.reset_round() repaired every bot.
func restart() -> void:
	if is_instance_valid(boss):
		_place(boss, home)
		_boost_subsystems(boss)
	_wreck = 0.0
	_stuck = 0.0
	_reverse = 0.0
	target_id = 0
	_remove_drop()

func step(delta: float) -> void:
	if not is_instance_valid(boss) or not world.bots.has(boss_id):
		return
	_clock += delta
	_tidy_drop()
	if boss.combat.eliminated:
		if _wreck == 0.0:
			_drop_reward()
		_wreck += delta
		if _wreck >= REBUILD_SECONDS:
			_rebuild()
		return
	_stabilise()
	_retarget -= delta
	# Whoever last hurt it becomes the prey: the giant answers aggression.
	var attacker := _killer()
	if attacker != 0 and attacker != target_id and _alive(attacker) \
			and world.weapons.time - float(boss.combat.recent_attackers[attacker]) < 1.0:
		target_id = attacker
		_retarget = RETARGET_SECONDS * 3.0
	if _retarget <= 0.0 or not _alive(target_id):
		_retarget = RETARGET_SECONDS
		target_id = _nearest()
	var intent := BotCommand.new()
	intent.sequence = boss.last_sequence + 1
	intent.brake = true
	if target_id != 0:
		_hunt(world.bots[target_id], intent, delta)
	intent.recovery_pressed = boss.body.global_basis.y.y < -0.25 and boss.combat.recovery_cooldown <= 0.0
	intent.primary_pressed = intent.primary_held and not _previous_primary
	_previous_primary = intent.primary_held
	boss.submit_command(intent)

## Hull stabilisers. Turret rock is a fixed spin per shot and would throw a hull
## this size around like a small bot; damp and cap pitch/roll, leave yaw free.
func _stabilise() -> void:
	var up := boss.body.global_basis.y
	var spin := boss.body.angular_velocity
	var yaw := up * spin.dot(up)
	var tilt := (spin - yaw) * 0.8
	var firing := boss.combat._volley_left > 0 or boss.combat.gun_shot
	boss.body.angular_velocity = yaw + tilt.limit_length(VOLLEY_TILT_RATE_LIMIT if firing else TILT_RATE_LIMIT)
	if boss.body.linear_velocity.y > 1.5:
		boss.body.linear_velocity.y = 1.5

func _alive(id: int) -> bool:
	return id != 0 and world.bots.has(id) and not world.bots[id].combat.eliminated

func _nearest() -> int:
	var best := 0
	var best_distance := INF
	for id: int in world.bots:
		if id == boss_id or not _alive(id):
			continue
		var distance := boss.body.global_position.distance_to(world.bots[id].body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best

func _hunt(prey: MvpBot, intent: BotCommand, delta: float) -> void:
	var to := prey.body.global_position - boss.body.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var distance := flat.length()
	var local := boss.body.global_basis.inverse() * to
	var angle := atan2(local.x, -local.z)
	var contact: float = (boss.combat.stats.size.z + prey.combat.stats.size.z) * 0.5
	# Charge, ease off to line up the hammer, and back off briefly when stuck.
	intent.throttle = clampf((distance - contact * 0.8) * 0.08, 0.0, 1.0) if absf(angle) < 0.7 else 0.25
	var speed := boss.body.linear_velocity.length()
	_stuck = _stuck + delta if intent.throttle > 0.3 and speed < 0.6 else maxf(0.0, _stuck - delta)
	if _stuck > 2.5:
		_reverse = 1.6
		_stuck = 0.0
	if _reverse > 0.0:
		_reverse -= delta
		intent.throttle = -0.8
		angle = -angle
	var forward := (-boss.body.global_basis.z).slide(Vector3.UP).normalized()
	intent.steering = clampf(angle * 0.9, -0.6, 0.6) * DriveModel.steering_direction(
		boss.body.linear_velocity.dot(forward), intent.throttle)
	intent.brake = absf(intent.throttle) < 0.05
	# Hammer slams whenever the prey is under the head.
	intent.primary_held = absf(angle) < 0.35 and distance < contact + 3.0 and fmod(_clock, 1.8) < 0.3
	# Quad cannon tracks the prey and fires in volleys at range. Aim from the
	# turret's own trunnion (not the hull top) at the prey's centre, and only
	# fire once the servo has actually brought the bore onto it (#81).
	var state := boss.combat
	var breech := boss.body.global_transform * AtlasGeometry.turret_breech(state.stats.size, state.turret_yaw, state.gun_pitch)
	var aim := prey.body.global_position - breech
	intent.aim_valid = true
	intent.aim_yaw = atan2(-aim.x, -aim.z)
	intent.aim_pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
	var bore := boss.body.global_basis * AtlasGeometry.turret_direction(state.turret_yaw, state.gun_pitch)
	var on_target := bore.angle_to(aim) < AIM_TOLERANCE and _clear_shot(breech, bore, prey)
	intent.auxiliary_held = on_target and distance > contact + 2.0 and distance < 140.0 and fmod(_clock, 4.0) < 2.6
	# At range, stop and swing the nose onto the prey: the quad turret can only
	# depress about 2 degrees over the flanks but about 20 over the nose, and
	# this turret sits high above its prey. Hold still through the volley.
	var gunnery := distance > contact + 2.0 and distance < 140.0 and fmod(_clock, 4.0) < 2.6
	if gunnery or state._volley_left > 0:
		intent.throttle = 0.0
		intent.steering = clampf(angle * 0.9, -0.6, 0.6) if state._volley_left == 0 and absf(angle) > 0.05 else 0.0
		intent.brake = intent.steering == 0.0

## True when the bore line reaches the prey before terrain, cover or another
## bot: the giant holds fire at a target hidden behind the mesa lip or a rock.
func _clear_shot(breech: Vector3, bore: Vector3, prey: MvpBot) -> bool:
	var query := PhysicsRayQueryParameters3D.create(breech, breech + bore * 160.0,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [boss.body.get_rid()])
	var hit := boss.body.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider_id == prey.body.get_instance_id()

func _killer() -> int:
	var latest := -1.0
	var killer := 0
	for id: int in boss.combat.recent_attackers:
		var at: float = boss.combat.recent_attackers[id]
		if at > latest and world.bots.has(id):
			latest = at
			killer = id
	return killer

## One guaranteed pickup of the strongest part the killer can fit.
func _drop_reward() -> void:
	_remove_drop()
	var killer := _killer()
	var part: String = DROPS[0]
	if killer != 0:
		for candidate: String in DROPS:
			if not world.pickups.swapped(world.bots[killer].loadout, candidate).is_empty():
				part = candidate
				break
	var at := boss.body.global_position
	at.y = preload("res://scripts/arena/woodland_ground.gd").height_at(at.x, at.z)
	drop_item_id = 9000 + boss_id
	var kind := "perk" if world.pickups.registry.parts[part].category in MatchPickups.PERK_SLOTS else "part"
	world.pickups.items.append({"id":drop_item_id, "point":at, "kind":kind, "part":part, "amount":0,
		"available":true, "respawn":0.0, "boss_drop":true})
	world.pickups.revision += 1

## The drop is single-use: once collected it leaves instead of re-rolling.
func _tidy_drop() -> void:
	if drop_item_id < 0:
		return
	for item: Dictionary in world.pickups.items:
		if item.id == drop_item_id and not item.available:
			_remove_drop()
			return

func _remove_drop() -> void:
	if drop_item_id < 0:
		return
	for index: int in range(world.pickups.items.size() - 1, -1, -1):
		if world.pickups.items[index].id == drop_item_id:
			world.pickups.items.remove_at(index)
			world.pickups.revision += 1
	drop_item_id = -1

func _rebuild() -> void:
	# Wait for a clear footprint like the practice bots do.
	var radius := Vector2(boss.combat.stats.size.x, boss.combat.stats.size.z).length() * 0.5
	for other: MvpBot in world.bots.values():
		if other == boss or other.combat.eliminated:
			continue
		if Vector2(other.body.global_position.x - home.origin.x, other.body.global_position.z - home.origin.z).length() < radius + 6.0:
			return
	boss.spawn_pose = home
	boss.reset_round()
	_boost_subsystems(boss)
	world.credited.erase(boss_id)
	_wreck = 0.0
	target_id = 0
