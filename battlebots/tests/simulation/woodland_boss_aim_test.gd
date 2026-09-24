extends SceneTree
## The Woodland giant's quad turret lands volleys on a bot it hunts at range
## (#81). Before the fix it aimed from the hull top and fired while slewing or
## over the flanks: 0 hits from 59 shells in this test; after it, 35 from 39.
const DISTANCE := 90.0
const SECONDS := 60
## At least this share of shells must land.
const MIN_HIT_SHARE := 0.5
var failures: Array[String] = []
## A member, not a local: lambdas capture locals by value.
var hits := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	var session := MvpSession.new()
	session.pickups_enabled = false
	root.add_child(session)
	check(session.practice(session.registry.starter(), "woodland") == OK, "Woodland practice starts")
	await physics_frame
	var boss := session.woodland_boss
	var giant: MvpBot = boss.boss
	# Only the player is prey: the other practice bots stay wrecked.
	for id: int in session.world.bots:
		if id != session.local_entity and id != boss.boss_id:
			session.world.bots[id].combat.eliminate("test")
	session.practice_director.records.clear()
	session.practice_director.roamers.clear()
	var player: MvpBot = session.world.bots[session.local_entity]
	session.combat_event.connect(func(event: Dictionary) -> void:
		if event.attacker == boss.boss_id and event.target == player.entity_id and event.kind != "hammer":
			hits += 1)
	var first_shot := giant.combat.shot_sequence
	for frame: int in 60 * SECONDS:
		# Keep the (repaired) player parked at range from wherever the giant is.
		var at := giant.body.global_position + Vector3(DISTANCE, 0, 0).rotated(Vector3.UP, 0.7)
		var flat := Vector2(player.body.global_position.x - giant.body.global_position.x,
			player.body.global_position.z - giant.body.global_position.z).length()
		if frame == 0 or absf(flat - DISTANCE) > 12.0:
			player.body.reset_pose = session.world.clear_spawn_pose(player, Transform3D(Basis.IDENTITY, at))
		player.combat.core = player.combat.stats.core
		player.combat.eliminated = false
		await physics_frame
	var shots := giant.combat.shot_sequence - first_shot
	check(shots > 0, "The giant fires its turret at range")
	check(shots > 0 and float(hits) / shots >= MIN_HIT_SHARE, "The giant lands its volleys: %d hits from %d shells at %d m" % [hits, shots, DISTANCE])
	session.leave()
	session.queue_free()
	await process_frame
	for failure: String in failures: push_error(failure)
	print("WOODLAND BOSS AIM PASS" if failures.is_empty() else "WOODLAND BOSS AIM FAIL")
	quit(0 if failures.is_empty() else 1)
