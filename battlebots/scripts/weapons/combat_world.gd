class_name CombatWorld
extends RefCounted
const FRONT_TOOL_TUNING = preload("res://scripts/core/front_tool_tuning.gd")
const ARENA_PROPS = preload("res://scripts/simulation/arena_props.gd")
## Server-only hit queries. No client supplies a target, damage, zone or impulse.
var time := 0.0
var event_id := 0
var cooldowns: Dictionary = {}
var pins: Dictionary = {}
var blocked: Dictionary = {}
var events: Array = []
var pending_hits: Array = []
var _sweep_origins: Dictionary = {}
var _hammer_hits: Dictionary = {}
var _saw_contacts: Dictionary = {}
var _saw_last_tick := -1
var _saw_round := -1
## Open wall-pin windows keyed "pin:attacker:victim": a recent ram whose victim
## may still be driven into static geometry on the face the rammer struck.
var _pin_windows: Dictionary = {}
## Mortar shells in flight: {attacker, point, lands} resolved when they land.
var _shells: Array[Dictionary] = []
## Destructible arena props (#71, scripts/simulation/arena_props.gd), set by
## AuthorityWorld; null on arenas without any.
var props: RefCounted
## Prop contact bookkeeping: "attacker:prop" -> last attack id or cooldown end.
var _prop_strikes: Dictionary = {}
## Component zones lie on these armour faces for the wall-pin hit.
const COMPONENT_FACES := {"drive_left":"left", "drive_right":"right", "weapon":"front"}
const MINIGUN_RANGE := 24.0
## [seconds, depth] of lost drive control while a bot is being shot or sawn.
## Only projectiles and the saw blade stagger; hammer, spinners, lifter and rams
## rely on their impulses. Saw contact repeats every 1/3 s and the minigun fires
## about 12 times a second, so their victims stay staggered while under fire.
const STAGGER := {"saw":[0.4, 0.55], "minigun":[0.15, 0.3], "plasma":[0.2, 0.35],
	"flamer":[0.2, 0.3], "tesla":[0.3, 0.45], "cannon":[0.5, 0.65], "railgun":[0.55, 0.7],
	"harpoon":[0.3, 0.4], "mortar":[0.5, 0.65], "grinder":[0.3, 0.5], "spear":[0.4, 0.6], "ram_punch":[0.35, 0.5]}
## Hits whose events carry the shooter's shot_sequence as their attack id.
const SHOT_KINDS := ["minigun", "cannon", "plasma", "flamer", "tesla", "railgun", "harpoon", "mortar"]
## Before physics.weapon_impulse_multiplier and the heavy-gravity launch scale.
const HAMMER_KNOCKBACK := 2.0
const HAMMER_LIFT := 1.5
const MINIGUN_DAMAGE := 6.0
## Rams below this closing speed (m/s) deal no damage or knock-back.
const RAM_MIN_CLOSING_SPEED := 4.0
## Impact scaling and ram knock-back tuning: data/bot_physics.json "impacts".
var physics := BotPhysics.settings()
## Atlas turret rays, cones and arcs: tuning in data/turret_weapons.json
## (TurretTuning). Every hit uses the ordinary zone/armor rules.

func step(delta: float, bots: Dictionary, tick: int, round_index: int) -> void:
	time += delta
	events.clear()
	pending_hits.clear()
	# AuthorityWorld skips weapon resolution while the match is inactive. A gap
	# in its tick sequence must not preserve partial maintained-contact damage.
	if tick != _saw_last_tick + 1 or round_index != _saw_round:
		_saw_contacts.clear()
		_pin_windows.clear()
		_shells.clear()
	_saw_last_tick = tick
	_saw_round = round_index
	var saw_contacts: Dictionary = {}
	_detonate_shells(bots, tick, round_index)
	for key: String in cooldowns.keys():
		if cooldowns[key] <= time:
			cooldowns.erase(key)
	for key: String in blocked.keys():
		if blocked[key] <= time:
			blocked.erase(key)
	for id: int in bots:
		var attacker: MvpBot = bots[id]
		if attacker.combat.eliminated:
			continue
		var state := attacker.combat
		if state.is_turret():
			_update_turret_aim(attacker, delta)
		elif state.stats.weapon == "minigun" or state.stats.get("secondary_weapon", "") == "minigun":
			_update_gun_aim(attacker, bots, delta)
		if state.gun_shot:
			# Paid cadence pulses resolve once, including a last shot that reaches
			# the shared heat ceiling. A second world step cannot replay a bullet.
			state.gun_shot = false
			if state.is_turret():
				_turret_shot(attacker, bots, tick, round_index)
			else:
				_minigun_shot(attacker, bots, tick, round_index)
		if state.grip_target != 0:
			_update_grip(attacker, bots, delta)
		if state.stats.weapon == "minigun":
			continue
		# A committed strike may reach the heat limit on its impact tick. The
		# resulting lockout prevents the next activation, not this paid strike.
		if state.zones.weapon <= 0 or (state.overheated and not state.strike):
			continue
		_melee_props(attacker, delta)
		if state.stats.weapon in AtlasGeometry.TOOL_PARTS:
			_front_tool(attacker, bots, delta, tick, round_index, saw_contacts)
			continue
		if state.stats.weapon == "saw" and state.weapon_phase != "active":
			continue
		if state.stats.weapon == "hammer":
			if not state.strike or state.attack_id <= 0:
				continue
			var activation: Dictionary = _hammer_hits.get(id, {})
			if activation.get("round") != round_index or activation.get("attack") != state.attack_id:
				_hammer_hits[id] = {"round": round_index, "attack": state.attack_id, "targets": {}}
		if state.stats.weapon in ["vertical_spinner", "horizontal_spinner"] and state.charge < 0.25:
			continue
		if state.stats.weapon == "lifter" and state.charge <= 0 and not state.launch:
			for pin: String in pins.keys():
				if pin.begins_with("%d:" % id):
					pins.erase(pin)
			continue
		var targets := _sweep(attacker)
		for target_id: int in bots:
			var victim: MvpBot = bots[target_id]
			var key := "%d:%d" % [id, target_id]
			if not targets.has(victim.body.get_instance_id()) or victim.team == attacker.team or victim.combat.eliminated:
				pins.erase(key)
				continue
			var direction := (victim.body.global_position - attacker.body.global_position).normalized()
			var contact_origin := attacker.body.global_position
			if state.stats.weapon in ["horizontal_spinner", "hammer", "saw"]:
				contact_origin = _sweep_origins.get(victim.body.get_instance_id(), attacker.body.global_position)
			var local_point := victim.body.global_transform.affine_inverse() * contact_origin
			var bounds := victim.collision_bounds()
			local_point = local_point.clamp(bounds.position, bounds.end)
			var point := victim.body.global_transform * local_point
			if state.stats.weapon == "saw":
				var contact_seconds := float(_saw_contacts.get(key, 0.0)) + delta
				var cadence := 1.0 / 3.0
				while contact_seconds + 0.000001 >= cadence:
					# The blade disc stands in the attacker's YZ plane: its axle is the cut normal.
					_hit(attacker, victim, point, 6, Vector3.ZERO, tick, round_index, 0.2, "", "", 1.0, attacker.body.global_basis.x)
					contact_seconds = maxf(0.0, contact_seconds - cadence)
				saw_contacts[key] = contact_seconds
			elif state.stats.weapon == "hammer":
				if not _hammer_hits[id].targets.has(target_id):
					_hit(attacker, victim, point, 38, _hammer_impulse(attacker, victim), tick, round_index)
					_hammer_hits[id].targets[target_id] = true
			elif state.stats.weapon == "vertical_spinner" and state.charge >= 0.25 and not cooldowns.has(key):
				_hit(attacker, victim, point, 45 * state.charge, (direction * 2 + Vector3.UP * 2) * victim.body.mass, tick, round_index)
				state.charge *= 0.5
				cooldowns[key] = time + 0.3
			elif state.stats.weapon == "horizontal_spinner" and state.charge >= 0.25 and not cooldowns.has(key):
				var lateral := Vector3(victim.body.global_position.x - contact_origin.x, 0, victim.body.global_position.z - contact_origin.z).normalized()
				if lateral.is_zero_approx():
					lateral = Vector3(direction.x, 0, direction.z).normalized()
				_hit(attacker, victim, point, 40 * state.charge, lateral * 4 * victim.body.mass, tick, round_index, 0.6)
				state.charge *= 0.4
				cooldowns[key] = time + 0.3
			elif state.stats.weapon == "lifter" and not blocked.has(key):
				if state.launch:
					# Charge at release (decayed one tick) sets the launch strength.
					var strength := clampf(state.charge, physics.lifter_min_release_charge, 1.0)
					_hit(attacker, victim, point, 8 * strength, (Vector3.UP * 6 + direction) * victim.body.mass * strength, tick, round_index)
				elif state.weapon_phase == "active":
					pins[key] = float(pins.get(key, 0)) + delta if victim.body.linear_velocity.length() < 0.5 else 0.0
					if pins[key] >= 5:
						blocked[key] = time + 3
						pins.erase(key)
					elif physics.lifter_hold_acceleration_at_1g > 0.0:
						# Zero by default: the flipper stays low while charging, then
						# releases one violent launch instead of floating targets up.
						var hold_acceleration := physics.lifter_hold_acceleration_at_1g * victim.body.heft()
						victim.body.apply_force(Vector3.UP * victim.body.mass * hold_acceleration * state.charge, point - victim.body.global_position)
				else:
					pins.erase(key)
	# Only eligible contacts this tick survive. Breaking contact or power cannot
	# bank a nearly complete damage interval for a later touch.
	_saw_contacts = saw_contacts
	# One unordered ram pair per half-second; resolve both struck zones once.
	var ids := bots.keys()
	for i: int in range(ids.size()):
		for j: int in range(i + 1, ids.size()):
			var a: MvpBot = bots[ids[i]]
			var b: MvpBot = bots[ids[j]]
			if a.team == b.team or a.combat.eliminated or b.combat.eliminated:
				continue
			var key := "ram:%d:%d" % [a.entity_id, b.entity_id]
			if cooldowns.has(key) or not a.body.contact_bodies.has(b.body.get_instance_id()):
				continue
			var direction := (b.body.global_position - a.body.global_position).normalized()
			var closing := (a.previous_velocity - b.previous_velocity).dot(direction)
			if closing > RAM_MIN_CLOSING_SPEED:
				var excess_closing := closing - RAM_MIN_CLOSING_SPEED
				var raw := minf(12, 2 * excess_closing)
				# Jolt contacts are plastic (bounce 0); heavy hulls rebound apart.
				var knockback_speed := excess_closing * physics.ram_knockback_per_closing_speed
				var lift := Vector3.UP * physics.ram_knockback_lift_fraction
				# A battering ram's prow multiplies what it deals and absorbs most
				# of the return blow (data/front_tools.json ram).
				var raw_ab := raw
				var raw_ba := raw
				var knock_ab := knockback_speed
				var knock_ba := knockback_speed
				var tools := FRONT_TOOL_TUNING.settings()
				if _ram_face(a, direction):
					raw_ab *= tools.value("ram", "damage_multiplier")
					knock_ab *= tools.value("ram", "knock_multiplier")
					raw_ba *= tools.value("ram", "self_share")
				if _ram_face(b, -direction):
					raw_ba *= tools.value("ram", "damage_multiplier")
					knock_ba *= tools.value("ram", "knock_multiplier")
					raw_ab *= tools.value("ram", "self_share")
				_hit(a, b, a.body.global_position, raw_ab, (direction + lift) * knock_ab * b.body.mass, tick, round_index, 0.2, "ram")
				_hit(b, a, b.body.global_position, raw_ba, (-direction + lift) * knock_ba * a.body.mass, tick, round_index, 0.2, "ram")
				cooldowns[key] = time + 0.5
				_open_pin_window(a, b, direction)
				_open_pin_window(b, a, -direction)
	_ram_props(bots)
	_resolve_pins(bots, tick, round_index)
	# Collect every eligible attack before damage: mutual lethal hits share a tick.
	for hit: Array in pending_hits:
		_apply_hit.callv(hit)
	for id: int in bots:
		var bot: MvpBot = bots[id]
		bot.previous_pose = bot.body.global_transform
		bot.previous_velocity = bot.body.linear_velocity

## Remembers which face of the victim a ram struck and how fast the rammer
## itself was driving into it, for the wall-pin check. A bot that was struck
## while not driving into the other (it was the one rammed) pins nobody.
func _open_pin_window(attacker: MvpBot, victim: MvpBot, direction: Vector3) -> void:
	var face := victim.zone_at(attacker.body.global_position)
	face = COMPONENT_FACES.get(face, face)
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.is_zero_approx():
		return
	var speed := attacker.previous_velocity.dot(flat.normalized())
	if speed < physics.ram_pin_min_attacker_speed:
		return
	_pin_windows["pin:%d:%d" % [attacker.entity_id, victim.entity_id]] = {"attacker":attacker.entity_id,
		"victim":victim.entity_id, "face":face, "direction":flat.normalized(),
		"speed":speed, "expires":time + physics.ram_pin_window_seconds}

## A rammed bot shoved into static geometry behind it takes one "crush" hit per
## ram on the struck face. Armour there soaks only ram_pin_armour_share of it.
func _resolve_pins(bots: Dictionary, tick: int, round_index: int) -> void:
	for key: String in _pin_windows.keys():
		var pin: Dictionary = _pin_windows[key]
		var attacker: MvpBot = bots.get(pin.attacker)
		var victim: MvpBot = bots.get(pin.victim)
		if pin.expires <= time or attacker == null or victim == null or victim.combat.eliminated:
			_pin_windows.erase(key)
			continue
		var wall := _far_wall_contact(victim, pin.direction)
		if wall.is_empty():
			continue
		var raw := pin_damage(physics, float(pin.speed), attacker.body.mass)
		_hit(attacker, victim, wall[0], raw, Vector3.ZERO, tick, round_index, 0.0, "crush", pin.face, physics.ram_pin_armour_share)
		_pin_windows.erase(key)

## Crush damage from the rammer alone: its own speed into the victim and its
## mass. The victim's mass and speed do not matter.
static func pin_damage(tuning: BotPhysics, attacker_speed: float, attacker_mass: float) -> float:
	var excess := maxf(0.0, attacker_speed - tuning.ram_pin_min_attacker_speed)
	var speed_damage := minf(tuning.ram_pin_damage_max,
		tuning.ram_pin_damage_base + tuning.ram_pin_damage_per_speed * excess)
	var mass_factor := clampf(attacker_mass / tuning.reference_mass,
		tuning.ram_pin_min_mass_factor, tuning.ram_pin_max_mass_factor)
	return speed_damage * mass_factor

## The victim's contact with a wall-like static surface on the side facing away
## from the rammer, as [point, normal], or [] when there is none.
func _far_wall_contact(victim: MvpBot, direction: Vector3) -> Array:
	for contact: Array in victim.body.static_contacts:
		var normal: Vector3 = contact[1]
		if absf(normal.y) >= physics.ram_pin_wall_max_normal_y:
			continue
		var offset: Vector3 = contact[0] - victim.body.global_position
		offset.y = 0.0
		if not offset.is_zero_approx() and offset.normalized().dot(direction) >= physics.ram_pin_far_side_min_alignment:
			return contact
	return []

func _sweep(bot: MvpBot) -> Array:
	_sweep_origins.clear()
	if bot.combat.stats.weapon == "horizontal_spinner":
		return _horizontal_sweep(bot)
	if bot.combat.stats.weapon == "hammer":
		return _hammer_sweep(bot)
	if bot.combat.stats.weapon == "saw":
		return _saw_sweep(bot)
	var linear_scale := BotScale.from_size(bot.combat.stats.size)
	var shape := BoxShape3D.new()
	shape.size = Vector3(bot.combat.stats.size.x * 0.8, 0.45 * linear_scale, 0.65 * linear_scale)
	var local := Transform3D(Basis.IDENTITY, Vector3(0, 0, -bot.combat.stats.size.z * 0.5 - 0.2 * linear_scale))
	if ScorpionGeometry.enabled(bot.loadout): local.origin += ScorpionGeometry.fallback_socket(bot.combat.stats.size)
	if SawbladeConfig.enabled(bot.loadout) and not ScorpionGeometry.enabled(bot.loadout) and not AtlasGeometry.enabled(bot.loadout) and bot.combat.stats.weapon == "lifter":
		var size: Vector3 = bot.combat.stats.size
		var angle := bot.combat.charge * deg_to_rad(40)
		if bot.combat.launch or bot.combat.cooldown > 2.7: angle = deg_to_rad(75)
		var rotation := Basis(Vector3.RIGHT, angle)
		# Include the low leading edge of the actual ramp (y=.0645,z=-1.63
		# in source meters), so an enlarged blade cannot visibly pass under a
		# target while the authored query floats above its contact surface.
		shape.size = Vector3(1.50, 0.50, 1.36) * SawbladeGeometry.scale_for(size)
		local = Transform3D(rotation, SawbladeGeometry.point(Vector3(0, 0.36, -0.30) + rotation * Vector3(0, -0.06, -0.66), size))
	var start := bot.previous_pose * local
	var finish := bot.body.global_transform * local
	var distance := start.origin.distance_to(finish.origin)
	var steps := clampi(ceili(distance / 0.15) + 2, 2, 32)
	var found: Array = []
	for index: int in range(steps):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = start.interpolate_with(finish, float(index) / (steps - 1))
		query.collision_mask = BaselineConfig.BOT_LAYER
		query.exclude = [bot.body.get_rid()]
		for hit: Dictionary in bot.body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if not found.has(hit.collider_id):
				found.append(hit.collider_id)
	return found

func _horizontal_sweep(bot: MvpBot) -> Array:
	var linear_scale := BotScale.from_size(bot.combat.stats.size)
	var shape := CylinderShape3D.new()
	shape.radius = bot.combat.stats.size.x * 0.65
	shape.height = 0.24 * linear_scale
	var local := Transform3D(Basis.IDENTITY, Vector3(0, 0, -bot.combat.stats.size.z * 0.5 - 0.2 * linear_scale))
	if ScorpionGeometry.enabled(bot.loadout): local.origin += ScorpionGeometry.fallback_socket(bot.combat.stats.size)
	var start := bot.previous_pose
	var finish := bot.body.global_transform
	var angle := start.basis.get_rotation_quaternion().angle_to(finish.basis.get_rotation_quaternion())
	# Include the disc's orbit around the body and its own outer radius. Sweeping
	# body poses first preserves the curved path during a turn about the chassis.
	var travel := start.origin.distance_to(finish.origin) + angle * (local.origin.length() + shape.radius)
	var steps := clampi(ceili(travel / 0.1) + 2, 2, 128)
	var found: Array = []
	for index: int in range(steps):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = start.interpolate_with(finish, float(index) / (steps - 1)) * local
		query.collision_mask = BaselineConfig.BOT_LAYER
		query.exclude = [bot.body.get_rid()]
		for hit: Dictionary in bot.body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if not found.has(hit.collider_id):
				found.append(hit.collider_id)
				_sweep_origins[hit.collider_id] = query.transform.origin
	return found

func _saw_sweep(bot: MvpBot) -> Array:
	var linear_scale := BotScale.from_size(bot.combat.stats.size)
	var shape := CylinderShape3D.new()
	shape.radius = 0.32 * linear_scale
	shape.height = 0.16 * linear_scale
	var local := Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0, 0.1 * linear_scale, -bot.combat.stats.size.z * 0.5 - 0.4 * linear_scale))
	if ScorpionGeometry.enabled(bot.loadout): local.origin += ScorpionGeometry.fallback_socket(bot.combat.stats.size)
	if SawbladeConfig.enabled(bot.loadout) and not ScorpionGeometry.enabled(bot.loadout) and not AtlasGeometry.enabled(bot.loadout):
		var size: Vector3 = bot.combat.stats.size
		var scale := SawbladeGeometry.scale_for(size)
		shape.radius = 0.678 * scale.z
		shape.height = 0.08 * scale.x
		local.origin = SawbladeGeometry.point(Vector3(0, 0.97, -1.16), size)
	var start := bot.previous_pose
	var finish := bot.body.global_transform
	var angle := start.basis.get_rotation_quaternion().angle_to(finish.basis.get_rotation_quaternion())
	var travel := start.origin.distance_to(finish.origin) + angle * (local.origin.length() + shape.radius)
	var steps := maxi(2, ceili(travel / 0.08) + 1)
	var found: Array = []
	for index: int in range(steps):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = start.interpolate_with(finish, float(index) / (steps - 1)) * local
		query.collision_mask = BaselineConfig.BOT_LAYER
		query.exclude = [bot.body.get_rid()]
		for hit: Dictionary in bot.body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if not found.has(hit.collider_id):
				found.append(hit.collider_id)
				_sweep_origins[hit.collider_id] = query.transform.origin
	return found

func _hammer_sweep(bot: MvpBot) -> Array:
	if ScorpionGeometry.enabled(bot.loadout): return _scorpion_hammer_sweep(bot)
	if SawbladeConfig.enabled(bot.loadout) and not AtlasGeometry.enabled(bot.loadout): return _sawblade_hammer_sweep(bot)
	var linear_scale := BotScale.from_size(bot.combat.stats.size)
	var shape := SphereShape3D.new()
	shape.radius = 0.2 * linear_scale
	# The Strider (#61) swings its hammer from a low shoulder socket.
	var pivot := Vector3(0, bot.combat.stats.size.y * 0.5, -bot.combat.stats.size.z * 0.5 + 0.15 * linear_scale) \
		+ NimbleBots.hammer_socket(bot.loadout)
	var arm := Vector3(0, 0, -1.2 * linear_scale)
	var start := bot.previous_pose
	var finish := bot.body.global_transform
	var body_angle := start.basis.get_rotation_quaternion().angle_to(finish.basis.get_rotation_quaternion())
	var swing_angle := PI * 2.0 / 3.0
	# Follow the descending overhead arc and the chassis motion together. A
	# straight segment between the two head endpoints misses overhead contacts.
	var travel := start.origin.distance_to(finish.origin) + body_angle * (pivot.length() + arm.length() + shape.radius) + swing_angle * arm.length()
	var steps := maxi(2, ceili(travel / 0.08) + 1)
	var found: Array = []
	for index: int in range(steps):
		var fraction := float(index) / (steps - 1)
		var pose := start.interpolate_with(finish, fraction)
		var angle := lerpf(PI / 2.0, -PI / 6.0, fraction)
		var head := pivot + Basis(Vector3.RIGHT, angle) * arm
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, pose * head)
		query.collision_mask = BaselineConfig.BOT_LAYER
		query.exclude = [bot.body.get_rid()]
		for hit: Dictionary in bot.body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if not found.has(hit.collider_id):
				found.append(hit.collider_id)
				_sweep_origins[hit.collider_id] = query.transform.origin
	return found

func _sawblade_hammer_sweep(bot: MvpBot) -> Array:
	var size: Vector3 = bot.combat.stats.size
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.82, 0.405, 0.38) * SawbladeGeometry.scale_for(size)
	var start := bot.previous_pose
	var finish := bot.body.global_transform
	var body_angle := start.basis.get_rotation_quaternion().angle_to(finish.basis.get_rotation_quaternion())
	# Bound the scaled head's full arc, including its corners and body rotation.
	# A fixed old-model distance undersamples the enlarged hammer during turns.
	var pivot := SawbladeGeometry.point(Vector3(0, 0.86, -0.29), size)
	var arm := Vector3(0, 0.63, -0.93) * SawbladeGeometry.scale_for(size)
	var head_radius := shape.size.length() * 0.5
	var travel := start.origin.distance_to(finish.origin) \
		+ body_angle * (pivot.length() + arm.length() + head_radius) \
		+ absf(SawbladeGeometry.HAMMER_SWING) * (arm.length() + head_radius)
	var steps := maxi(20, ceili(travel / 0.06) + 1)
	var found: Array = []
	for index: int in steps:
		var fraction := float(index) / (steps - 1)
		var angle := SawbladeGeometry.HAMMER_SWING * fraction
		var local := Transform3D(Basis(Vector3.RIGHT, angle - SawbladeGeometry.HAMMER_SWING), SawbladeGeometry.hammer_center(size, angle))
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = start.interpolate_with(finish, fraction) * local
		query.collision_mask = BaselineConfig.BOT_LAYER
		query.exclude = [bot.body.get_rid()]
		for hit: Dictionary in bot.body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if not found.has(hit.collider_id):
				found.append(hit.collider_id)
				_sweep_origins[hit.collider_id] = query.transform.origin
	return found

func _scorpion_hammer_sweep(bot: MvpBot) -> Array:
	var size: Vector3 = bot.combat.stats.size
	var shape := BoxShape3D.new()
	shape.size = ScorpionGeometry.HEAD_SIZE * BotScale.from_size(size)
	var start := bot.previous_pose
	var finish := bot.body.global_transform
	var body_angle := start.basis.get_rotation_quaternion().angle_to(finish.basis.get_rotation_quaternion())
	# Conservative bound for four articulated joints, telescopic travel and body motion.
	var travel := start.origin.distance_to(finish.origin) \
		+ body_angle * 4.0 * BotScale.from_size(size) + (4.0 + ScorpionGeometry.HAMMER_EXTENSION) * BotScale.from_size(size)
	var steps := maxi(24, ceili(travel / 0.08) + 1)
	var found: Array = []
	for index: int in steps:
		var fraction := float(index) / (steps - 1)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = start.interpolate_with(finish, fraction) * ScorpionGeometry.hammer_transform(size, fraction)
		query.collision_mask = BaselineConfig.BOT_LAYER
		query.exclude = [bot.body.get_rid()]
		for hit: Dictionary in bot.body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if not found.has(hit.collider_id):
				found.append(hit.collider_id)
				_sweep_origins[hit.collider_id] = query.transform.origin
	return found

func _update_gun_aim(attacker: MvpBot, bots: Dictionary, delta: float) -> void:
	var state := attacker.combat
	var gun_offset := AtlasGeometry.gun_offset(attacker.loadout, state.stats.size)
	var pivot := ScorpionGeometry.GUN_PIVOT * BotScale.from_size(state.stats.size) + gun_offset
	var origin := attacker.body.global_transform * pivot
	var forward := -attacker.body.global_basis.z
	var desired := 0.0
	var nearest := MINIGUN_RANGE + 1.5 * BotScale.from_size(state.stats.size)
	for id: int in bots:
		var candidate: MvpBot = bots[id]
		if candidate == attacker or candidate.team == attacker.team or candidate.combat.eliminated:
			continue
		# Vertical servo only. Test the exact forward ray against each projected
		# hull footprint, not a camera aim point or a client-supplied target.
		var local_origin := candidate.body.global_transform.affine_inverse() * origin
		var local_forward := candidate.body.global_basis.inverse() * forward
		var half: Vector3 = candidate.collision_bounds().size * 0.5
		var entry := 0.0
		var exit_distance := nearest
		for axis: int in [0, 2]:
			if absf(local_forward[axis]) < 0.000001:
				if absf(local_origin[axis]) > half[axis]:
					exit_distance = -1.0
					break
			else:
				var a := (-half[axis] - local_origin[axis]) / local_forward[axis]
				var b := (half[axis] - local_origin[axis]) / local_forward[axis]
				entry = maxf(entry, minf(a, b))
				exit_distance = minf(exit_distance, maxf(a, b))
		if entry > exit_distance or exit_distance <= 0.0 or entry >= nearest:
			continue
		var target := attacker.body.global_transform.affine_inverse() * candidate.body.global_position
		if target.z >= pivot.z:
			continue
		nearest = entry
		# Rotating the authored mount moves the muzzle. Refine the elevation
		# using that rotated position so close low targets remain hittable.
		desired = state.gun_pitch
		for iteration: int in 3:
			var muzzle := ScorpionGeometry.gun_muzzle(state.stats.size, desired) + gun_offset
			var absolute_pitch := atan2(target.y - muzzle.y, maxf(0.1, muzzle.z - target.z))
			desired = clampf(absolute_pitch, deg_to_rad(-35.0), deg_to_rad(20.0)) - ScorpionGeometry.GUN_REST_PITCH
	state.gun_pitch = move_toward(state.gun_pitch, desired, maxf(0.0, delta) * 3.0)

## The client supplies only a world aim bearing, like steering intent. The
## turret servos toward it within mechanical rates and stops, stabilised
## against chassis motion; stale/neutral commands return it to the front.
func _update_turret_aim(attacker: MvpBot, delta: float) -> void:
	var state := attacker.combat
	var target := Vector2.ZERO
	var command := attacker.command
	if command.aim_valid and not state.eliminated and state.zones.weapon > 0.0:
		var world := Basis(Vector3.UP, command.aim_yaw) * Basis(Vector3.RIGHT, command.aim_pitch) * Vector3.FORWARD
		target = AtlasGeometry.turret_target(attacker.body.global_basis, world, state.stats.turret_model)
	elif state.zones.weapon <= 0.0:
		# A disabled turret loses traverse power and stays where it is.
		target = Vector2(state.turret_yaw, state.gun_pitch)
	var next := AtlasGeometry.turret_slew(Vector2(state.turret_yaw, state.gun_pitch), target, delta, state.stats.turret_model)
	state.turret_yaw = next.x
	state.gun_pitch = next.y

func _turret_shot(attacker: MvpBot, bots: Dictionary, tick: int, round_index: int) -> void:
	var tuning := TurretTuning.settings()
	var state := attacker.combat
	if state.zones.weapon <= 0 or state.eliminated:
		return
	var kind: String = state.stats.secondary_weapon
	var size: Vector3 = state.stats.size
	var basis := attacker.body.global_basis
	var direction := (basis * AtlasGeometry.turret_direction(state.turret_yaw, state.gun_pitch)).normalized()
	var reach := tuning.value(kind, "range")
	var space := attacker.body.get_world_3d().direct_space_state
	# Multi-barrel models fire each shot from its own barrel, converged on the
	# point the centre bore line strikes (what the barrel reticle marks), so
	# outboard and stacked barrels do not straddle a target the gunner is on.
	var barrel := AtlasGeometry.turret_barrel(state.stats.turret_model, state.shot_sequence)
	var origin := attacker.body.global_transform * AtlasGeometry.turret_breech(size, state.turret_yaw, state.gun_pitch, barrel)
	var from := attacker.body.global_transform * AtlasGeometry.turret_muzzle(size, kind, state.turret_yaw, state.gun_pitch, barrel)
	if barrel != Vector2.ZERO:
		var centre := attacker.body.global_transform * AtlasGeometry.turret_muzzle(size, kind, state.turret_yaw, state.gun_pitch)
		var sight := PhysicsRayQueryParameters3D.create(centre, centre + direction * reach,
			BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [attacker.body.get_rid()])
		var mark := space.intersect_ray(sight)
		var converge: Vector3 = mark.position if not mark.is_empty() else centre + direction * reach
		# Never converge inside the pods' own spread (a wall at the muzzle).
		if converge.distance_to(centre) > 4.0 * BotScale.from_size(size):
			direction = (converge - from).normalized()
	var end := from + direction * reach
	var barrels := int(state.stats.get("turret_barrels", 1))
	var jolt := tuning.barrel(kind, barrels, "jolt")
	attacker.body.apply_impulse(-direction * attacker.body.mass * jolt, from - attacker.body.global_position)
	var rock_axis := direction.cross(Vector3.UP)
	var tilt := acos(clampf(attacker.body.global_basis.y.dot(Vector3.UP), -1.0, 1.0))
	if rock_axis.length_squared() > 0.0001 and tilt < tuning.rock_tilt_limit:
		var inertia := (attacker.body.inertia.x + attacker.body.inertia.z) * 0.5
		var rock := tuning.barrel(kind, barrels, "rock")
		attacker.body.apply_torque_impulse(rock_axis.normalized() * inertia * rock)
	attacker.body.sleeping = false
	if kind == "flamer":
		_flamer_shot(attacker, bots, from, direction, tick, round_index)
		return
	if kind == "tesla":
		_tesla_shot(attacker, bots, from, direction, tick, round_index)
		return
	if kind == "mortar":
		_mortar_shot(attacker, from, direction, tick)
		return
	# Trace from the trunnion, inside the casting, so a barrel pushed through a
	# wall cannot fire from its far side. Allies block without taking damage.
	var query := PhysicsRayQueryParameters3D.create(origin, end,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [attacker.body.get_rid()])
	query.hit_from_inside = true
	var result := space.intersect_ray(query)
	state.last_shot_from = from
	state.last_shot_to = end if result.is_empty() else result.position
	state.last_shot_tick = tick
	if result.is_empty():
		return
	if origin.distance_squared_to(result.position) < origin.distance_squared_to(from):
		state.last_shot_from = origin
	if kind == "railgun":
		_railgun_path(attacker, bots, result, end, direction, tick, round_index)
		return
	for id: int in bots:
		var victim: MvpBot = bots[id]
		if victim.body.get_instance_id() != result.collider_id:
			continue
		if victim.team != attacker.team and not victim.combat.eliminated:
			_hit(attacker, victim, result.position, tuning.value(kind, "damage"),
				direction * victim.body.mass * tuning.value(kind, "knock"), tick, round_index,
				tuning.value(kind, "recoil"), kind)
			if kind == "harpoon" and state.grip_target == 0:
				state.grip_mode = "harpoon"
				state.grip_target = victim.entity_id
				state.grip_local = victim.body.global_transform.affine_inverse() * result.position
				state.grip_point = result.position
				state.grip_seconds = 0.0
		return
	# No bot took it: a destructible prop may (#71).
	_prop_hit(result.collider_id, result.position, tuning.value(kind, "damage"), kind, direction)

## Harpoon tether: follows its anchor on the victim and, while the shooter
## holds the trigger, reels the victim toward the muzzle with part of the pull
## dragging the shooter. It snaps when stretched past max_length, when static
## geometry cuts the line, after max_seconds, or when either bot is eliminated.
func _update_grip(attacker: MvpBot, bots: Dictionary, delta: float) -> void:
	var state := attacker.combat
	var victim: MvpBot = null
	for id: int in bots:
		if bots[id].entity_id == state.grip_target:
			victim = bots[id]
	if victim == null or victim.combat.eliminated or victim.team == attacker.team:
		state.release_grip()
		return
	var anchor := victim.body.global_transform * state.grip_local
	state.grip_point = anchor
	state.grip_seconds += delta
	if state.grip_mode == "spear":
		_hold_impaled(attacker, victim, anchor)
		return
	var tuning := TurretTuning.settings()
	var muzzle := attacker.body.global_transform * AtlasGeometry.turret_muzzle(state.stats.size, "harpoon", state.turret_yaw, state.gun_pitch)
	var line := muzzle - anchor
	var length := line.length()
	if length > tuning.value("harpoon", "max_length") or state.grip_seconds > tuning.value("harpoon", "max_seconds"):
		state.release_grip()
		return
	var cut := PhysicsRayQueryParameters3D.create(muzzle, anchor, BaselineConfig.WORLD_LAYER)
	var wall := attacker.body.get_world_3d().direct_space_state.intersect_ray(cut)
	if not wall.is_empty() and wall.position.distance_to(anchor) > 0.5 * BotScale.from_size(state.stats.size):
		state.release_grip()
		return
	if not state.secondary_active or length <= tuning.value("harpoon", "min_length"):
		return
	# A winch, not a spring: it drives the line in toward reel_speed and lets
	# the speed fall off over the last metres, so targets arrive rather than
	# being fired into the shooter.
	var inward := line / length
	var closing := (victim.body.linear_velocity - attacker.body.linear_velocity).dot(inward)
	var wanted := minf(tuning.value("harpoon", "reel_speed"), (length - tuning.value("harpoon", "min_length")) * 1.5)
	var drive := clampf((wanted - closing) / maxf(wanted, 0.5), 0.0, 1.0)
	if drive <= 0.0:
		return
	var pull := inward * victim.body.mass * tuning.value("harpoon", "pull_acceleration") * victim.body.heft() * drive
	victim.body.apply_force(pull, anchor - victim.body.global_position)
	attacker.body.apply_force(-pull * tuning.value("harpoon", "reaction_share"), muzzle - attacker.body.global_position)
	victim.body.sleeping = false
	attacker.body.sleeping = false

## Spear/forklift hold: a capped spring-damper drags the impaled target's
## anchor to the tines (lifting with the carriage) while primary is held.
## Letting go throws it off; it tears free past strain_distance, after
## max_hold_seconds, or when the weapon is disabled or overheated.
func _hold_impaled(attacker: MvpBot, victim: MvpBot, anchor: Vector3) -> void:
	var tuning := FRONT_TOOL_TUNING.settings()
	var state := attacker.combat
	var hold := attacker.body.global_transform * AtlasGeometry.spear_hold(state.stats.size, state.tool_pose)
	var error := hold - anchor
	var forward := (-attacker.body.global_basis.z).slide(Vector3.UP).normalized()
	if error.length() > tuning.value("spear", "strain_distance") or state.grip_seconds > tuning.value("spear", "max_hold_seconds") \
			or state.zones.weapon <= 0.0 or state.overheated:
		state.release_grip()
		return
	if not attacker.command.primary_held:
		victim.body.apply_central_impulse((forward + Vector3.UP * 0.3) * victim.body.mass * tuning.value("spear", "release_speed") * victim.body.launch_scale())
		victim.body.sleeping = false
		state.release_grip()
		return
	var relative := victim.body.linear_velocity - attacker.body.linear_velocity
	var acceleration := error * tuning.value("spear", "stiffness") - relative * tuning.value("spear", "damping")
	acceleration = acceleration.limit_length(tuning.value("spear", "max_acceleration") * victim.body.heft())
	var force := acceleration * victim.body.mass
	victim.body.apply_force(force, anchor - victim.body.global_position)
	attacker.body.apply_force(-force * tuning.value("spear", "reaction_share"), hold - attacker.body.global_position)
	victim.body.sleeping = false
	# Pinned on the tines, the target's drive has little purchase.
	victim.combat.stagger(0.2, 0.7)

## Front tool contact (data/front_tools.json). Ram punch and spear thrust hit
## each target once per activation; the grinder drum grinds on a cadence.
func _front_tool(attacker: MvpBot, bots: Dictionary, delta: float, tick: int, round_index: int, contacts: Dictionary) -> void:
	var tuning := FRONT_TOOL_TUNING.settings()
	var state := attacker.combat
	var tool: String = AtlasGeometry.TOOL_PARTS[state.stats.weapon]
	var size: Vector3 = state.stats.size
	var linear := BotScale.from_size(size)
	var forward := (-attacker.body.global_basis.z).slide(Vector3.UP).normalized()
	if tool == "grinder":
		if state.charge < 0.3:
			return
		var shape := CylinderShape3D.new()
		shape.radius = AtlasGeometry.GRINDER_REACH * linear
		shape.height = AtlasGeometry.GRINDER_HALF_WIDTH * 2.0 * linear
		var local := Transform3D(Basis(Vector3.BACK, PI * 0.5), AtlasGeometry.grinder_drum(size, state.tool_pose))
		var cadence := tuning.value("grinder", "cadence")
		for victim: MvpBot in _tool_contacts(attacker, bots, shape, local):
			var key := "grind:%d:%d" % [attacker.entity_id, victim.entity_id]
			var seconds := float(_saw_contacts.get(key, 0.0)) + delta
			var point := _nearest_on(victim, attacker.body.global_transform * local.origin)
			while seconds + 0.000001 >= cadence:
				var zone := victim.zone_at(point)
				var raw := tuning.value("grinder", "damage") * state.charge
				# The spikes shred intact armour much faster than they reach the core.
				if victim.combat.stats.plates.has(zone) and float(victim.combat.zones.get(zone, 0.0)) > 0.0:
					raw *= tuning.value("grinder", "plate_multiplier")
				var inward := (attacker.body.global_position - victim.body.global_position).slide(Vector3.UP).normalized()
				# The drum chews in from the front: it parts the target across the attacker's nose.
				_hit(attacker, victim, point, raw, inward * victim.body.mass * tuning.value("grinder", "pull"), tick, round_index, 0.0, "grinder", zone, 1.0, forward)
				seconds = maxf(0.0, seconds - cadence)
			contacts[key] = seconds
		return
	if not state.strike or state.attack_id <= 0:
		return
	var activation: Dictionary = _hammer_hits.get(attacker.entity_id, {})
	if activation.get("round") != round_index or activation.get("attack") != state.attack_id:
		activation = {"round": round_index, "attack": state.attack_id, "targets": {}}
		_hammer_hits[attacker.entity_id] = activation
	if tool == "ram":
		var volume := AtlasGeometry.ram_volume(size, state.charge)
		var local: Transform3D = volume[0]
		var box := BoxShape3D.new()
		box.size = volume[1]
		for victim: MvpBot in _tool_contacts(attacker, bots, box, local):
			if activation.targets.has(victim.entity_id):
				continue
			activation.targets[victim.entity_id] = true
			var impulse := (forward + Vector3.UP * tuning.value("ram", "punch_lift")) * victim.body.mass * tuning.value("ram", "punch_speed")
			_hit(attacker, victim, _nearest_on(victim, attacker.body.global_transform * local.origin),
				tuning.value("ram", "punch_damage"), impulse, tick, round_index, 0.3, "ram_punch")
		return
	# Spear: the first enemy the blades reach is pierced and impaled.
	if state.grip_target != 0:
		return
	var volume := AtlasGeometry.spear_volume(size, state.charge, state.tool_pose)
	var blade_local: Transform3D = volume[0]
	var blades := BoxShape3D.new()
	blades.size = volume[1]
	var tip := attacker.body.global_transform * blade_local.origin
	var best: MvpBot = null
	for victim: MvpBot in _tool_contacts(attacker, bots, blades, blade_local):
		if activation.targets.has(victim.entity_id):
			continue
		if best == null or victim.body.global_position.distance_to(tip) < best.body.global_position.distance_to(tip):
			best = victim
	if best == null:
		return
	activation.targets[best.entity_id] = true
	var point := _nearest_on(best, tip)
	_hit(attacker, best, point, tuning.value("spear", "thrust_damage"), forward * best.body.mass * 1.0, tick, round_index,
		0.1, "spear", "", tuning.value("spear", "armour_share"))
	state.grip_mode = "spear"
	state.grip_target = best.entity_id
	state.grip_local = best.body.global_transform.affine_inverse() * point
	state.grip_point = point
	state.grip_seconds = 0.0

## Enemies (not allies, not eliminated) a tool volume touches, swept from the
## previous to the current chassis pose.
func _tool_contacts(attacker: MvpBot, bots: Dictionary, shape: Shape3D, local: Transform3D) -> Array[MvpBot]:
	var start := attacker.previous_pose * local
	var finish := attacker.body.global_transform * local
	var steps := clampi(ceili(start.origin.distance_to(finish.origin) / 0.15) + 2, 2, 24)
	var ids: Array = []
	for index: int in range(steps):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = start.interpolate_with(finish, float(index) / (steps - 1))
		query.collision_mask = BaselineConfig.BOT_LAYER
		query.exclude = [attacker.body.get_rid()]
		for hit: Dictionary in attacker.body.get_world_3d().direct_space_state.intersect_shape(query, 16):
			if not ids.has(hit.collider_id): ids.append(hit.collider_id)
	var found: Array[MvpBot] = []
	for id: int in bots:
		var victim: MvpBot = bots[id]
		if ids.has(victim.body.get_instance_id()) and victim.team != attacker.team and not victim.combat.eliminated:
			found.append(victim)
	return found

## Closest point on a bot's collision bounds to a world point.
func _nearest_on(victim: MvpBot, world: Vector3) -> Vector3:
	var bounds := victim.collision_bounds()
	return victim.body.global_transform * (victim.body.global_transform.affine_inverse() * world).clamp(bounds.position, bounds.end)

## A ram whose closing contact lands on its prow (data/front_tools.json ram).
func _ram_face(bot: MvpBot, toward: Vector3) -> bool:
	if bot.combat.stats.weapon != "battering_ram" or bot.combat.zones.weapon <= 0.0:
		return false
	var nose := (-bot.body.global_basis.z).slide(Vector3.UP)
	var flat := toward.slide(Vector3.UP)
	if nose.is_zero_approx() or flat.is_zero_approx():
		return false
	return nose.normalized().dot(flat.normalized()) >= FRONT_TOOL_TUNING.settings().value("ram", "front_cone")

## Flies the shell along its real ballistic path to the first thing it
## strikes; it detonates there after the actual flight time.
func _mortar_shot(attacker: MvpBot, from: Vector3, direction: Vector3, tick: int) -> void:
	var state := attacker.combat
	var path := mortar_trace(attacker.body.get_world_3d().direct_space_state, from, direction, [attacker.body.get_rid()])
	state.last_shot_from = from
	state.last_shot_to = path.point
	state.last_shot_tick = tick
	if path.landed:
		_shells.append({"attacker":attacker.entity_id, "point":path.point, "lands":time + path.flight})

## Swept-ray ballistic trace (30 Hz segments) shared by the server shot and the
## gunner's predicted-impact marker: {points, landed, point, flight}.
static func mortar_trace(space: PhysicsDirectSpaceState3D, from: Vector3, direction: Vector3, exclude: Array[RID]) -> Dictionary:
	var tuning := TurretTuning.settings()
	var gravity := Vector3.DOWN * tuning.value("mortar", "shell_gravity")
	var velocity := direction.normalized() * tuning.value("mortar", "muzzle_speed")
	var at := from
	var travelled := 0.0
	var flight := 0.0
	var step := 1.0 / 30.0
	var points: Array[Vector3] = [from]
	while travelled < tuning.value("mortar", "range") and flight < 10.0:
		var next := at + velocity * step + gravity * (0.5 * step * step)
		var query := PhysicsRayQueryParameters3D.create(at, next,
			BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclude)
		var result := space.intersect_ray(query)
		if not result.is_empty():
			flight += step * at.distance_to(result.position) / maxf(at.distance_to(next), 0.0001)
			points.append(result.position)
			return {"points":points, "landed":true, "point":result.position, "flight":flight}
		travelled += at.distance_to(next)
		velocity += gravity * step
		at = next
		flight += step
		points.append(at)
	return {"points":points, "landed":false, "point":at, "flight":flight}

## Landed shells blast every hostile within blast_radius that the blast can
## see, full damage at the centre falling to blast_edge_share at the edge.
func _detonate_shells(bots: Dictionary, tick: int, round_index: int) -> void:
	var tuning := TurretTuning.settings()
	var radius := tuning.value("mortar", "blast_radius")
	for shell: Dictionary in _shells.duplicate():
		if shell.lands > time + 0.000001:
			continue
		_shells.erase(shell)
		var attacker: MvpBot = null
		for id: int in bots:
			if bots[id].entity_id == shell.attacker:
				attacker = bots[id]
		if attacker == null:
			continue
		var point: Vector3 = shell.point
		for id: int in bots:
			var victim: MvpBot = bots[id]
			if victim.team == attacker.team or victim.combat.eliminated:
				continue
			var bounds := victim.collision_bounds()
			var local := victim.body.global_transform.affine_inverse() * point
			var nearest := victim.body.global_transform * local.clamp(bounds.position, bounds.end)
			var distance := point.distance_to(nearest)
			if distance > radius:
				continue
			var lift := point + Vector3.UP * 0.4
			var sight := PhysicsRayQueryParameters3D.create(lift, nearest, BaselineConfig.WORLD_LAYER)
			var cover := attacker.body.get_world_3d().direct_space_state.intersect_ray(sight)
			if not cover.is_empty() and cover.position.distance_to(nearest) > 0.3:
				continue
			var share := lerpf(1.0, tuning.value("mortar", "blast_edge_share"), distance / radius)
			var away := victim.body.global_position - point
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.0001 else Vector3.ZERO
			var impulse := (away + Vector3.UP * 0.8) * victim.body.mass * tuning.value("mortar", "knock") * share
			_hit(attacker, victim, nearest, tuning.value("mortar", "damage") * share, impulse, tick, round_index,
				0.0, "mortar")
		if props != null:
			for found: Dictionary in props.within(point, radius):
				var share := lerpf(1.0, tuning.value("mortar", "blast_edge_share"), float(found.distance) / radius)
				var at: Vector3 = props.props[found.name].at
				props.damage(found.name, tuning.value("mortar", "damage") * share, "mortar", point, (at - point).normalized() + Vector3.UP)

## The slug punches through what it strikes (#72, #71). A slug that destroys a
## bot or breaks a prop flies on with overpenetration_retain of the energy it
## did not spend, through up to max_penetrations bodies; one that does not
## still pierces a single body behind a bot for pierce_share. Walls, allies
## and props left standing stop it.
func _railgun_path(attacker: MvpBot, bots: Dictionary, result: Dictionary, end: Vector3, direction: Vector3, tick: int, round_index: int) -> void:
	var tuning := TurretTuning.settings()
	var full := tuning.value("railgun", "damage")
	var energy := full
	var passes := 0
	var exclude: Array[RID] = [attacker.body.get_rid()]
	while not result.is_empty():
		var at: Vector3 = result.position
		var victim: MvpBot = null
		for id: int in bots:
			if bots[id].body.get_instance_id() == result.collider_id:
				victim = bots[id]
		var leftover := -1.0
		if victim != null:
			if victim.team == attacker.team or victim.combat.eliminated:
				return
			leftover = victim.combat.overkill(victim.zone_at(at), energy)
			_hit(attacker, victim, at, energy, direction * victim.body.mass * tuning.value("railgun", "knock") * energy / full,
				tick, round_index, tuning.value("railgun", "recoil") if passes == 0 else 0.0, "railgun", "", 1.0, direction)
			exclude.append(victim.body.get_rid())
		else:
			leftover = _prop_hit(result.collider_id, at, energy, "railgun", direction)
			if leftover < 0.0:
				return
			exclude.append(result.rid)
		passes += 1
		if leftover >= 0.0:
			energy = leftover * tuning.value("railgun", "overpenetration_retain")
		elif passes == 1:
			energy *= tuning.value("railgun", "pierce_share")
		else:
			return
		if passes > int(tuning.value("railgun", "max_penetrations")) or energy <= 0.0:
			return
		var query := PhysicsRayQueryParameters3D.create(at + direction * 0.05, end,
			BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclude)
		query.hit_from_inside = true
		result = attacker.body.get_world_3d().direct_space_state.intersect_ray(query)
		attacker.combat.last_shot_to = end if result.is_empty() else result.position

## Damages the prop behind a collider. Returns the energy left after breaking
## it (>= 0), or a negative value when it is no prop or still stands.
func _prop_hit(collider_id: int, point: Vector3, raw: float, kind: String, axis: Vector3) -> float:
	if props == null:
		return -1.0
	var name: String = props.prop_at(collider_id)
	if name.is_empty():
		return -1.0
	return props.damage(name, raw, kind, point, axis)

## A running weapon chews into props ahead of the hull (data/arena_props.json
## melee): saws and grinders continuously, hammers, spinners and front tools
## per strike.
func _melee_props(attacker: MvpBot, delta: float) -> void:
	if props == null or props.props.is_empty():
		return
	var state := attacker.combat
	var weapon: String = AtlasGeometry.TOOL_PARTS.get(state.stats.weapon, state.stats.weapon)
	var melee: Dictionary = ARENA_PROPS.settings().melee
	if not melee.has(weapon):
		return
	var rule: Dictionary = melee[weapon]
	var engaged := false
	var raw := 0.0
	match weapon:
		"saw":
			engaged = state.weapon_phase == "active"
			raw = float(rule.get("dps", 0.0)) * delta
		"grinder":
			engaged = state.charge >= 0.3
			raw = float(rule.get("dps", 0.0)) * state.charge * delta
		"vertical_spinner", "horizontal_spinner":
			engaged = state.charge >= 0.25
			raw = float(rule.get("hit", 0.0)) * state.charge
		_:
			engaged = state.strike and state.attack_id > 0
			raw = float(rule.get("hit", 0.0))
	if not engaged or raw <= 0.0:
		return
	var size: Vector3 = state.stats.size
	var linear := BotScale.from_size(size)
	var reach := float(melee.reach) * linear
	var shape := SphereShape3D.new()
	shape.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = attacker.body.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.1 * linear, -size.z * 0.5 - reach * 0.5))
	query.collision_mask = BaselineConfig.PROP_LAYER
	var axis := attacker.body.global_basis.x if weapon == "saw" else (-attacker.body.global_basis.z)
	for hit: Dictionary in attacker.body.get_world_3d().direct_space_state.intersect_shape(query, 8):
		var name: String = props.prop_at(hit.collider_id)
		if name.is_empty():
			continue
		var key := "%d:%s" % [attacker.entity_id, name]
		if rule.has("cooldown"):
			if float(_prop_strikes.get(key, -INF)) > time:
				continue
			_prop_strikes[key] = time + float(rule.cooldown)
		elif not rule.has("dps"):
			if _prop_strikes.get(key) == state.attack_id:
				continue
			_prop_strikes[key] = state.attack_id
		props.damage(name, raw, weapon, query.transform.origin, axis)

## Driving into a prop at speed batters it (data/arena_props.json ram).
func _ram_props(bots: Dictionary) -> void:
	if props == null or props.props.is_empty():
		return
	var rule: Dictionary = ARENA_PROPS.settings().ram
	for id: int in bots:
		var bot: MvpBot = bots[id]
		if bot.combat.eliminated:
			continue
		for collider: int in bot.body.contact_bodies:
			var name: String = props.prop_at(collider)
			if name.is_empty():
				continue
			var key := "ram:%d:%s" % [bot.entity_id, name]
			if float(_prop_strikes.get(key, -INF)) > time:
				continue
			var at: Vector3 = props.props[name].at
			var toward := Vector3(at.x - bot.body.global_position.x, 0.0, at.z - bot.body.global_position.z)
			if toward.is_zero_approx():
				continue
			var closing := bot.previous_velocity.dot(toward.normalized())
			if closing <= rule.min_closing_speed:
				continue
			_prop_strikes[key] = time + rule.cooldown
			var raw: float = (closing - rule.min_closing_speed) * rule.damage_per_speed * bot.body.mass / maxf(rule.reference_mass, 1.0)
			props.damage(name, raw, "ram", bot.body.global_position, toward.normalized())

## First unobstructed point on a bot seen from a point, or {} when anything
## else (walls, allies, other bots) is in the way.
func _line_of_fire(attacker: MvpBot, from: Vector3, victim: MvpBot, extra_exclude: Array[RID] = []) -> Dictionary:
	var exclude: Array[RID] = [attacker.body.get_rid()]
	exclude.append_array(extra_exclude)
	var query := PhysicsRayQueryParameters3D.create(from, victim.body.global_position,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclude)
	var result := attacker.body.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty() or result.collider_id != victim.body.get_instance_id():
		return {}
	return result

## Flame cone: every hostile inside the widening cone that the flame can
## actually reach takes a burn tick. Walls shorten the jet; allies shield.
func _flamer_shot(attacker: MvpBot, bots: Dictionary, from: Vector3, direction: Vector3, tick: int, round_index: int) -> void:
	var tuning := TurretTuning.settings()
	var state := attacker.combat
	var reach := tuning.value("flamer", "range")
	var wall := PhysicsRayQueryParameters3D.create(from, from + direction * reach, BaselineConfig.WORLD_LAYER)
	var blocked := attacker.body.get_world_3d().direct_space_state.intersect_ray(wall)
	if not blocked.is_empty():
		reach = from.distance_to(blocked.position)
		# The jet licks whatever it splashes against; timber burns (#71).
		_prop_hit(blocked.collider_id, blocked.position, tuning.value("flamer", "damage"), "flamer", direction)
	state.last_shot_from = from
	state.last_shot_to = from + direction * reach
	state.last_shot_tick = tick
	for id: int in bots:
		var victim: MvpBot = bots[id]
		if victim == attacker or victim.team == attacker.team or victim.combat.eliminated:
			continue
		var offset := victim.body.global_position - from
		var along := offset.dot(direction)
		var radius := victim.collision_bounds().size.length() * 0.35
		if along < 0.0 or along > reach + radius:
			continue
		if (offset - direction * along).length() > along * tan(tuning.value("flamer", "half_angle")) + radius:
			continue
		var seen := _line_of_fire(attacker, from, victim)
		if seen.is_empty():
			continue
		_hit(attacker, victim, seen.position, tuning.value("flamer", "damage"),
			direction * victim.body.mass * tuning.value("flamer", "knock"), tick, round_index, 0.0, "flamer")

## Tesla discharge: arcs to the nearest hostile it can see within the seek
## cone, then chains to the nearest other hostile near that target.
func _tesla_shot(attacker: MvpBot, bots: Dictionary, from: Vector3, direction: Vector3, tick: int, round_index: int) -> void:
	var tuning := TurretTuning.settings()
	var state := attacker.combat
	var reach := tuning.value("tesla", "range")
	state.last_shot_from = from
	state.last_shot_to = from + direction * 5.0
	state.last_shot_tick = tick
	var best: MvpBot
	var best_hit := {}
	var best_distance := INF
	for id: int in bots:
		var victim: MvpBot = bots[id]
		if victim == attacker or victim.team == attacker.team or victim.combat.eliminated:
			continue
		var offset := victim.body.global_position - from
		var distance := offset.length()
		if distance > reach + victim.collision_bounds().size.length() * 0.35 or distance < 0.01:
			continue
		if offset.normalized().dot(direction) < cos(tuning.value("tesla", "seek_angle")) or distance >= best_distance:
			continue
		var seen := _line_of_fire(attacker, from, victim)
		if seen.is_empty():
			continue
		best = victim
		best_hit = seen
		best_distance = distance
	if best == null:
		return
	state.last_shot_to = best_hit.position
	_hit(attacker, best, best_hit.position, tuning.value("tesla", "damage"),
		(best.body.global_position - from).normalized() * best.body.mass * tuning.value("tesla", "knock"), tick, round_index, 0.0, "tesla")
	var chained: MvpBot
	var chained_hit := {}
	var chain_distance := tuning.value("tesla", "chain_reach")
	for id: int in bots:
		var victim: MvpBot = bots[id]
		if victim == attacker or victim == best or victim.team == attacker.team or victim.combat.eliminated:
			continue
		var distance := victim.body.global_position.distance_to(best.body.global_position)
		if distance >= chain_distance:
			continue
		var seen := _line_of_fire(attacker, best.body.global_position, victim, [best.body.get_rid()])
		if seen.is_empty():
			continue
		chained = victim
		chained_hit = seen
		chain_distance = distance
	if chained != null:
		_hit(attacker, chained, chained_hit.position, tuning.value("tesla", "damage") * tuning.value("tesla", "chain_share"),
			Vector3.ZERO, tick, round_index, 0.0, "tesla")

func _minigun_shot(attacker: MvpBot, bots: Dictionary, tick: int, round_index: int) -> void:
	var state := attacker.combat
	if state.zones.weapon <= 0 or state.eliminated:
		return
	var gun_offset := AtlasGeometry.gun_offset(attacker.loadout, state.stats.size)
	var muzzle := ScorpionGeometry.gun_muzzle(state.stats.size, state.gun_pitch) + gun_offset
	var breech := ScorpionGeometry.gun_breech(state.stats.size, state.gun_pitch) + gun_offset
	var local_direction := ScorpionGeometry.gun_direction(state.gun_pitch)
	var from := attacker.body.global_transform * muzzle
	var origin := attacker.body.global_transform * breech
	var direction := (attacker.body.global_basis * local_direction).normalized()
	var end := from + direction * MINIGUN_RANGE
	# Start at the breech so a protruding barrel cannot shoot through a wall.
	# The first body always occludes: allies block fire without receiving damage.
	var query := PhysicsRayQueryParameters3D.create(origin, end,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [attacker.body.get_rid()])
	query.hit_from_inside = true
	var result := attacker.body.get_world_3d().direct_space_state.intersect_ray(query)
	state.last_shot_from = from
	state.last_shot_to = end if result.is_empty() else result.position
	state.last_shot_tick = tick
	if result.is_empty():
		return
	if origin.distance_squared_to(result.position) < origin.distance_squared_to(from):
		state.last_shot_from = origin
	for id: int in bots:
		var victim: MvpBot = bots[id]
		if victim.body.get_instance_id() != result.collider_id:
			continue
		if victim.team != attacker.team and not victim.combat.eliminated:
			_hit(attacker, victim, result.position, MINIGUN_DAMAGE,
				direction * victim.body.mass * 0.035, tick, round_index, 0.08, "minigun")
		return
	_prop_hit(result.collider_id, result.position, MINIGUN_DAMAGE, "minigun", direction)

## Hammer blows knock the target away from the attacker and pop it off the floor.
## A straight-down impulse was absorbed by the arena and read as no reaction.
func _hammer_impulse(attacker: MvpBot, victim: MvpBot) -> Vector3:
	var away := victim.body.global_position - attacker.body.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -attacker.body.global_basis.z
		away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.FORWARD
	return (away * HAMMER_KNOCKBACK + Vector3.UP * HAMMER_LIFT) * victim.body.mass

## axis orients the blow for destruction (#72): the saw blade's axle, the
## grinder's approach or the slug's flight. Zero falls back to the impulse, then
## to the direction from the victim's centre to the point.
func _hit(attacker: MvpBot, victim: MvpBot, point: Vector3, raw: float, impulse: Vector3, tick: int, round_index: int, recoil := 0.2, kind := "", zone := "", armour_share := 1.0, axis := Vector3.ZERO) -> void:
	pending_hits.append([attacker, victim, point, raw, impulse, tick, round_index, recoil,
		attacker.combat.stats.weapon if kind.is_empty() else kind, zone, armour_share, axis])

## zone overrides the struck zone derived from point (wall pins name the face);
## armour_share is the part of the hit an intact plate may stop (see CombatState.damage).
func _apply_hit(attacker: MvpBot, victim: MvpBot, point: Vector3, raw: float, impulse: Vector3, tick: int, round_index: int, recoil := 0.2, kind := "", zone := "", armour_share := 1.0, axis := Vector3.ZERO) -> void:
	if victim.combat.eliminated:
		return
	if zone.is_empty():
		zone = victim.zone_at(point)
	var normal := (point - victim.body.global_position).normalized()
	if axis.is_zero_approx():
		axis = impulse.normalized() if not impulse.is_zero_approx() else normal
	var before: float = victim.combat.zones.get(zone, 0.0)
	var core_before := victim.combat.core
	var dealt := victim.combat.damage(zone, raw, armour_share)
	if victim.combat.eliminated:
		var frame := victim.body.global_transform.affine_inverse()
		victim.combat.record_death(kind, frame * point, frame.basis * axis, raw / maxf(core_before, 1.0))
	# A neutral hazard (the Woodland giant) takes damage but never scores it.
	var scored := not victim.has_meta("neutral")
	if scored:
		attacker.combat.effective_damage += dealt
	if scored and before > 0 and victim.combat.zones.get(zone, 1) <= 0:
		attacker.combat.component_disables += 1
	if dealt > 0:
		victim.combat.recent_attackers[attacker.entity_id] = time
	# Impact output comes from the attacking machine, not the target's weight.
	# Heavy targets therefore resist the same strike. Strikes hit hard and
	# sqrt(heft) keeps launch heights under the heavier gravity, so hulls
	# snap up and slam back down instead of drifting.
	var mass_ratio := clampf(attacker.body.mass / victim.body.mass, 0.65, 1.4)
	var impact_scale := physics.weapon_impulse_multiplier
	if kind == "minigun":
		impact_scale = physics.minigun_impulse_multiplier
	elif kind == "lifter":
		impact_scale = physics.lifter_impulse_multiplier
	impact_scale *= victim.body.launch_scale()
	var delivered := impulse * mass_ratio * impact_scale
	victim.body.apply_impulse(delivered, point - victim.body.global_position)
	if STAGGER.has(kind):
		victim.combat.stagger(STAGGER[kind][0], STAGGER[kind][1])
	if kind == "lifter":
		# Tip the struck near edge up and over, away from the flipper.
		var away := (victim.body.global_position - attacker.body.global_position).slide(Vector3.UP).normalized()
		if not away.is_zero_approx():
			var strength := clampf(attacker.combat.charge, physics.lifter_min_release_charge, 1.0)
			victim.body.angular_velocity += Vector3.UP.cross(away) * physics.lifter_flip_spin_at_1g * victim.body.launch_scale() * strength
	attacker.body.apply_central_impulse(-delivered * recoil)
	event_id += 1
	if attacker.combat.stats.weapon in ["vertical_spinner", "horizontal_spinner", "saw"]:
		attacker.combat.attack_id += 1
	events.append({"event_id":event_id, "round":round_index, "tick":tick, "kind":kind,
		"attack_id":attacker.combat.shot_sequence if kind in SHOT_KINDS else attacker.combat.attack_id, "attacker":attacker.entity_id,
		"target":victim.entity_id, "zone":zone, "damage":dealt, "position":point,
		"normal":normal, "axis":axis.normalized()})
