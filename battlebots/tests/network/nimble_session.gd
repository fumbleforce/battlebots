extends SceneTree
## Nimble bots (#61) online: the server accepts sealed presets and refuses a
## modified one, authority and prediction both run the gait, and a hopping
## pogo and a skater settle onto the authoritative pose after driving. Local
## ENet only; the correction figures are reported, not a feel acceptance.
const DRIVE_FRAMES := 240
const SETTLE_FRAMES := 120
const SETTLED_DISTANCE := 0.5
## Replay does not model gaits; corrections must stay small, never a teleport.
const MAX_CORRECTION := 2.0
var failures: Array[String] = []
var sessions: Array[MvpSession] = []
var containers: Array[SubViewport] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var instance := MvpSession.new()
	instance.name = "Session"
	viewport.add_child(instance)
	containers.append(viewport)
	sessions.append(instance)
	return instance

func until(predicate: Callable, seconds := 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

func run() -> void:
	var server := session("Server")
	var first := session("First")
	var second := session("Second")
	var port := 36000 + OS.get_process_id() % 10000
	check(server.host(port, false, 2) == OK, "Duel server starts")
	first.join("127.0.0.1", port)
	second.join("127.0.0.1", port)
	if not await until(func(): return first.local_entity > 0 and second.local_entity > 0):
		check(false, "Two clients join")
		finish()
		return
	var pogo := NimbleBots.preset(first.registry, "pogo_03")
	var tampered := pogo.duplicate(true)
	tampered.parts.weapon = "saw"
	first.set_loadout(tampered)
	await until(func(): return false, 1.0)
	check(server.players[first.local_entity].loadout.parts.get("weapon") != "saw", "Server refuses a modified factory build")
	first.set_loadout(pogo)
	second.set_loadout(NimbleBots.preset(second.registry, "skater_12"))
	check(await until(func(): return (server.players[first.local_entity].loadout.parts.chassis == "pogo_03"
		and server.players[second.local_entity].loadout.parts.chassis == "skater_12")), "Server accepts both factory builds")
	first.set_ready(true)
	second.set_ready(true)
	if not await until(func(): return server.match_state.phase == "active" and first.world != null and first.world.bots.size() == 2):
		check(false, "Ready/countdown reaches active")
		finish()
		return
	var ids := [first.local_entity, second.local_entity]
	var clients := [first, second]
	for index: int in 2:
		var id: int = ids[index]
		var client: MvpSession = clients[index]
		check(server.world.bots[id].body.gait != "" and client.world.bots[id].body.gait == server.world.bots[id].body.gait,
			"Authority and prediction run the %s gait" % server.world.bots[id].body.gait)
	var starts := [server.world.bots[ids[0]].body.global_position, server.world.bots[ids[1]].body.global_position]
	var corrections := [0.0, 0.0]
	var airborne := 0
	for frame: int in DRIVE_FRAMES + SETTLE_FRAMES:
		for index: int in 2:
			var command := BotCommand.new()
			command.throttle = 1.0 if frame < DRIVE_FRAMES else 0.0
			command.steering = 0.4 if frame < DRIVE_FRAMES else 0.0
			command.brake = frame >= DRIVE_FRAMES
			clients[index].submit_local(command)
		await physics_frame
		if frame < DRIVE_FRAMES and not server.world.bots[ids[0]].body.grounded: airborne += 1
		for index: int in 2:
			corrections[index] = maxf(corrections[index], clients[index].diagnostics.correction_m)
	check(airborne > DRIVE_FRAMES / 5, "The network-driven pogo bounds (%d airborne frames)" % airborne)
	for index: int in 2:
		var id: int = ids[index]
		var authority: Vector3 = server.world.bots[id].body.global_position
		check(authority.distance_to(starts[index]) > 10.0, "Client commands drive the authoritative %s" % server.world.bots[id].loadout.name)
		var settled: float = clients[index].world.bots[id].body.global_position.distance_to(authority)
		check(settled < SETTLED_DISTANCE, "%s settles %.2f m from authority" % [server.world.bots[id].loadout.name, settled])
		check(corrections[index] < MAX_CORRECTION, "%s max correction %.2f m" % [server.world.bots[id].loadout.name, corrections[index]])
	finish()

func finish() -> void:
	for instance: MvpSession in sessions: instance.leave()
	for viewport: SubViewport in containers: viewport.queue_free()
	await process_frame
	if failures.is_empty(): print("NIMBLE SESSION PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
