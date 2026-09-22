class_name CombatWorld
extends RefCounted
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
const MINIGUN_RANGE := 24.0
const MINIGUN_DAMAGE := 6.0

func step(delta: float, bots: Dictionary, tick: int, round_index: int) -> void:
	time += delta
	events.clear()
	pending_hits.clear()
	# AuthorityWorld skips weapon resolution while the match is inactive. A gap
	# in its tick sequence must not preserve partial maintained-contact damage.
	if tick != _saw_last_tick + 1 or round_index != _saw_round:
		_saw_contacts.clear()
	_saw_last_tick = tick
	_saw_round = round_index
	var saw_contacts: Dictionary = {}
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
		if state.stats.weapon == "minigun" or state.stats.get("secondary_weapon", "") == "minigun":
			_update_gun_aim(attacker, bots, delta)
		if state.gun_shot:
			# Paid cadence pulses resolve once, including a last shot that reaches
			# the shared heat ceiling. A second world step cannot replay a bullet.
			state.gun_shot = false
			_minigun_shot(attacker, bots, tick, round_index)
		if state.stats.weapon == "minigun":
			continue
		# A committed strike may reach the heat limit on its impact tick. The
		# resulting lockout prevents the next activation, not this paid strike.
		if state.zones.weapon <= 0 or (state.overheated and not state.strike):
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
					_hit(attacker, victim, point, 6, Vector3.ZERO, tick, round_index)
					contact_seconds = maxf(0.0, contact_seconds - cadence)
				saw_contacts[key] = contact_seconds
			elif state.stats.weapon == "hammer":
				if not _hammer_hits[id].targets.has(target_id):
					_hit(attacker, victim, point, 38, -attacker.body.global_basis.y * victim.body.mass, tick, round_index)
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
					_hit(attacker, victim, point, 8, (Vector3.UP * 6 + direction) * victim.body.mass, tick, round_index)
				elif state.weapon_phase == "active":
					pins[key] = float(pins.get(key, 0)) + delta if victim.body.linear_velocity.length() < 0.5 else 0.0
					if pins[key] >= 5:
						blocked[key] = time + 3
						pins.erase(key)
					else:
						victim.body.apply_force(Vector3.UP * victim.body.mass * 12 * state.charge, point - victim.body.global_position)
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
			if closing > 4:
				var raw := minf(12, 2 * (closing - 4))
				_hit(a, b, a.body.global_position, raw, Vector3.ZERO, tick, round_index, 0.2, "ram")
				_hit(b, a, b.body.global_position, raw, Vector3.ZERO, tick, round_index, 0.2, "ram")
				cooldowns[key] = time + 0.5
	# Collect every eligible attack before damage: mutual lethal hits share a tick.
	for hit: Array in pending_hits:
		_apply_hit.callv(hit)
	for id: int in bots:
		var bot: MvpBot = bots[id]
		bot.previous_pose = bot.body.global_transform
		bot.previous_velocity = bot.body.linear_velocity

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
	var pivot := Vector3(0, bot.combat.stats.size.y * 0.5, -bot.combat.stats.size.z * 0.5 + 0.15 * linear_scale)
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
		var half: Vector3 = candidate.combat.stats.size * 0.5
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

func _hit(attacker: MvpBot, victim: MvpBot, point: Vector3, raw: float, impulse: Vector3, tick: int, round_index: int, recoil := 0.2, kind := "") -> void:
	pending_hits.append([attacker, victim, point, raw, impulse, tick, round_index, recoil,
		attacker.combat.stats.weapon if kind.is_empty() else kind])

func _apply_hit(attacker: MvpBot, victim: MvpBot, point: Vector3, raw: float, impulse: Vector3, tick: int, round_index: int, recoil := 0.2, kind := "") -> void:
	if victim.combat.eliminated:
		return
	var zone := victim.zone_at(point)
	var before: float = victim.combat.zones.get(zone, 0.0)
	var dealt := victim.combat.damage(zone, raw)
	attacker.combat.effective_damage += dealt
	if before > 0 and victim.combat.zones.get(zone, 1) <= 0:
		attacker.combat.component_disables += 1
	if dealt > 0:
		victim.combat.recent_attackers[attacker.entity_id] = time
	victim.body.apply_impulse(impulse, point - victim.body.global_position)
	attacker.body.apply_central_impulse(-impulse * recoil)
	event_id += 1
	if attacker.combat.stats.weapon in ["vertical_spinner", "horizontal_spinner", "saw"]:
		attacker.combat.attack_id += 1
	events.append({"event_id":event_id, "round":round_index, "tick":tick, "kind":kind,
		"attack_id":attacker.combat.shot_sequence if kind == "minigun" else attacker.combat.attack_id, "attacker":attacker.entity_id,
		"target":victim.entity_id, "zone":zone, "damage":dealt, "position":point,
		"normal":(point - victim.body.global_position).normalized()})
