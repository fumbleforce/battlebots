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

func step(delta: float, bots: Dictionary, tick: int, round_index: int) -> void:
	time += delta
	events.clear()
	pending_hits.clear()
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
		# A committed strike may reach the heat limit on its impact tick. The
		# resulting lockout prevents the next activation, not this paid strike.
		if state.zones.weapon <= 0 or (state.overheated and not state.strike):
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
			if state.stats.weapon in ["horizontal_spinner", "hammer"]:
				contact_origin = _sweep_origins.get(victim.body.get_instance_id(), attacker.body.global_position)
			var local_point := victim.body.global_transform.affine_inverse() * contact_origin
			var half: Vector3 = victim.combat.stats.size * 0.5
			local_point = local_point.clamp(-half, half)
			var point := victim.body.global_transform * local_point
			if state.stats.weapon == "hammer":
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
				_hit(a, b, a.body.global_position, raw, Vector3.ZERO, tick, round_index)
				_hit(b, a, b.body.global_position, raw, Vector3.ZERO, tick, round_index)
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
	var shape := BoxShape3D.new()
	shape.size = Vector3(bot.combat.stats.size.x * 0.8, 0.45, 0.65)
	var local := Transform3D(Basis.IDENTITY, Vector3(0, 0, -bot.combat.stats.size.z * 0.5 - 0.2))
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
	var shape := CylinderShape3D.new()
	shape.radius = bot.combat.stats.size.x * 0.65
	shape.height = 0.24
	var local := Transform3D(Basis.IDENTITY, Vector3(0, 0, -bot.combat.stats.size.z * 0.5 - 0.2))
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

func _hammer_sweep(bot: MvpBot) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	var pivot := Vector3(0, bot.combat.stats.size.y * 0.5, -bot.combat.stats.size.z * 0.5 + 0.15)
	var arm := Vector3(0, 0, -1.2)
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

func _hit(attacker: MvpBot, victim: MvpBot, point: Vector3, raw: float, impulse: Vector3, tick: int, round_index: int, recoil := 0.2) -> void:
	pending_hits.append([attacker, victim, point, raw, impulse, tick, round_index, recoil])

func _apply_hit(attacker: MvpBot, victim: MvpBot, point: Vector3, raw: float, impulse: Vector3, tick: int, round_index: int, recoil := 0.2) -> void:
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
	if attacker.combat.stats.weapon in ["vertical_spinner", "horizontal_spinner"]:
		attacker.combat.attack_id += 1
	events.append({"event_id":event_id, "round":round_index, "tick":tick,
		"attack_id":attacker.combat.attack_id, "attacker":attacker.entity_id,
		"target":victim.entity_id, "zone":zone, "damage":dealt, "position":point,
		"normal":(point - victim.body.global_position).normalized()})
