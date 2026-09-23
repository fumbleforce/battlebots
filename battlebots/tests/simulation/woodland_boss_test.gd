extends SceneTree
## Woodland practice (#45 stage 1): edge starts, a scaled roaming giant that
## hunts, and a single-use top-tier drop when it falls.
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var session := MvpSession.new()
	session.name = "Session"
	root.add_child(session)
	check(session.practice({}, "woodland") == OK, "Woodland practice starts")
	await physics_frame
	var boss := session.woodland_boss
	check(boss != null and is_instance_valid(boss.boss), "Woodland practice installs the giant")
	var giant := boss.boss
	var player: MvpBot = session.world.bots[session.local_entity]
	check(giant.combat.stats.size.x > 20.0 and giant.combat.core >= 280.0 * 20.0, "Giant is scaled: %s core %s" % [giant.combat.stats.size, giant.combat.core])
	check(giant.combat.zones.weapon > 1000.0, "Giant subsystems are hardened")
	check(Vector2(player.spawn_pose.origin.x, player.spawn_pose.origin.z).length() > 80.0, "Player starts at the edge, not the plateau")
	for record: Dictionary in session.practice_director.records:
		var at: Vector3 = record.home.origin
		check(Vector2(at.x, at.z).length() > 80.0, "Practice bot %d starts at the edge" % record.index)
	check(giant.spawn_pose.origin.y > 6.0, "Giant starts on the plateau top")
	# It hunts: after a few seconds it has moved and chosen a target.
	var start := giant.body.global_position
	for i: int in range(60 * 6):
		await physics_frame
	check(boss.target_id != 0, "Giant chose a target")
	check(giant.body.global_position.distance_to(start) > 2.0, "Giant roams (moved %.1f m)" % giant.body.global_position.distance_to(start))
	check(giant.command.aim_valid, "Giant aims its turret")
	# Takedown: credit the player, eliminate, expect one guaranteed drop.
	giant.combat.recent_attackers[player.entity_id] = session.world.weapons.time
	giant.combat.eliminate("test")
	for i: int in range(3):
		await physics_frame
	var drops := session.world.pickups.items.filter(func(item: Dictionary) -> bool: return item.get("boss_drop", false))
	check(drops.size() == 1, "Takedown leaves exactly one drop")
	if drops.size() == 1:
		check(drops[0].part in WoodlandBoss.DROPS and drops[0].available, "Drop is a top-tier part the killer can fit: %s" % drops[0].part)
		check(not session.world.pickups.swapped(player.loadout, drops[0].part).is_empty(), "Killer can fit the dropped part")
		# Collecting removes it for good.
		var event := session.world.pickups.collect(drops[0], player.entity_id, player.loadout)
		check(not event.is_empty(), "Drop is collectable")
		for i: int in range(3):
			await physics_frame
		check(session.world.pickups.items.filter(func(item: Dictionary) -> bool: return item.get("boss_drop", false)).is_empty(), "Collected drop is removed, not re-rolled")
	# Restart repairs the giant at home with hardened subsystems.
	check(session.restart_practice() == OK, "Practice restarts")
	await physics_frame
	check(not giant.combat.eliminated and giant.combat.zones.weapon > 1000.0, "Restart rebuilds the giant")
	check(session.practice_director.player_home.origin.is_equal_approx(player.spawn_pose.origin)
		and Vector2(player.spawn_pose.origin.x, player.spawn_pose.origin.z).length() > 80.0,
		"Player respawns and restarts use the edge start")
	session.leave()
	session.queue_free()
	await process_frame
	# Other arenas have no giant.
	var foundry := MvpSession.new()
	root.add_child(foundry)
	check(foundry.practice({}, "foundry") == OK and foundry.woodland_boss == null, "Foundry practice has no giant")
	foundry.leave()
	foundry.queue_free()
	await process_frame
	print("WOODLAND BOSS PASS" if failures == 0 else "WOODLAND BOSS FAIL")
	quit(0 if failures == 0 else 1)
