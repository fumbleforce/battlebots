class_name CombatWorld
extends RefCounted
## Server-only hit queries. No client supplies a target, damage, zone or impulse.
var time := 0.0
var event_id := 0
var cooldowns: Dictionary = {}
var pins: Dictionary = {}
var blocked: Dictionary = {}
var events: Array = []

func step(delta: float, bots: Dictionary, tick: int, round_index: int) -> void:
	time += delta
	events.clear()
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
		if state.stats.weapon == "vertical_spinner" and state.charge < 0.25:
			continue
		if state.stats.weapon == "lifter" and state.charge <= 0 and not state.launch:
			continue
		var targets := _sweep(attacker)
		for target_id: int in bots:
			var victim: MvpBot = bots[target_id]
			var key := "%d:%d" % [id, target_id]
			if not targets.has(victim.body.get_instance_id()) or victim.team == attacker.team or victim.combat.eliminated:
				pins.erase(key)
				continue
			var direction := (victim.body.global_position - attacker.body.global_position).normalized()
			var local_point := victim.body.global_transform.affine_inverse() * attacker.body.global_position
			var half: Vector3 = victim.combat.stats.size * 0.5
			local_point = local_point.clamp(-half, half)
			var point := victim.body.global_transform * local_point
			if state.stats.weapon == "vertical_spinner" and not cooldowns.has(key):
				_hit(attacker, victim, point, 45 * state.charge, (direction * 2 + Vector3.UP * 2) * victim.body.mass, tick, round_index)
				state.charge *= 0.5
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
	for id: int in bots:
		var bot: MvpBot = bots[id]
		bot.previous_pose = bot.body.global_transform
		bot.previous_velocity = bot.body.linear_velocity

func _sweep(bot: MvpBot) -> Array:
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

func _hit(attacker: MvpBot, victim: MvpBot, point: Vector3, raw: float, impulse: Vector3, tick: int, round_index: int) -> void:
	var zone := victim.zone_at(point)
	var before: float = victim.combat.zones.get(zone, 0.0)
	var dealt := victim.combat.damage(zone, raw)
	attacker.combat.effective_damage += dealt
	if before > 0 and victim.combat.zones.get(zone, 1) <= 0:
		attacker.combat.component_disables += 1
	if dealt > 0:
		victim.combat.recent_attackers[attacker.entity_id] = time
	victim.body.apply_impulse(impulse, point - victim.body.global_position)
	attacker.body.apply_central_impulse(-impulse * 0.2)
	event_id += 1
	attacker.combat.attack_id += 1
	events.append({"event_id":event_id, "round":round_index, "tick":tick,
		"attack_id":attacker.combat.attack_id, "attacker":attacker.entity_id,
		"target":victim.entity_id, "zone":zone, "damage":dealt, "position":point,
		"normal":(point - victim.body.global_position).normalized()})
