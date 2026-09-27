extends SceneTree
## Actual public drive commands over both bridge decks, in both directions.
const GROUND = preload("res://scripts/arena/sunreach_ground.gd")
const RUN_UP_METRES := 23.0
const EXIT_METRES := 20.0
const SETTLE_TICKS := 60
const RUN_TICKS := 480
const DRIVE_THROTTLE := 0.65
var failures := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := AuthorityWorld.new()
	world.arena_id = "sunreach"
	root.add_child(world)
	for bridge: Dictionary in GROUND.settings().bridges:
		for direction: float in [-1.0, 1.0]:
			var bot := world.spawn(1, 0, 0, world.registry.bracken())
			var start := Vector3(float(bridge.x), 0, float(bridge.z) + direction * RUN_UP_METRES)
			start.y = GROUND.height_at(start.x, start.z) + bot.ground_clearance() + 0.15
			bot.body.reset_pose = Transform3D(Basis(Vector3.UP, 0.0 if direction > 0 else PI), start)
			for frame: int in SETTLE_TICKS: await physics_frame
			var crossed := false
			for tick: int in RUN_TICKS:
				var command := BotCommand.new()
				command.sequence = tick
				command.throttle = DRIVE_THROTTLE
				bot.submit_command(command)
				bot.step(1.0 / 60.0, true)
				await physics_frame
				if (bot.body.position.z - float(bridge.z)) * direction < -EXIT_METRES:
					crossed = true
					break
			if not crossed:
				failures += 1
				push_error("Bracken did not cross bridge %s direction %s: %s" % [bridge.x, direction, bot.body.position])
			else: print("BRIDGE CROSSED ", bridge.x, " direction=", direction)
			world.clear_bots()
			await physics_frame
	world.queue_free()
	await process_frame
	print("SUNREACH BRIDGES PASS" if failures == 0 else "SUNREACH BRIDGES FAIL")
	quit(0 if failures == 0 else 1)
