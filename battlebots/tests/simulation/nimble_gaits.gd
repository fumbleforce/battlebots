extends SceneTree
## Nimble bots (#61) on real Jolt bodies: each is faster than the tanks and
## moves with its own measurable gait. Scope: flat test floor, one bot at a time,
## authoritative simulation only (no network replay, no presentation).
const FLOOR_SIZE := Vector3(900, 2, 900)
const FLOOR_AT := Vector3(0, 200, 4000)
const SETTLE_FRAMES := 90
const RUN_FRAMES := 240
const TURN_FRAMES := 120
const COAST_FRAMES := 120
const PIVOT_FRAMES := 60
## Stride: the hull must visibly bob and the speed surge each step.
const MIN_STRIDE_BOB := 0.12
const MIN_STRIDE_SURGE := 0.6
## Roll: a hard turn at speed leans the monowheel; at rest it barely pivots.
const MIN_ROLL_LEAN_DEGREES := 12.0
const MAX_ROLL_PIVOT_FRACTION := 0.6
## Braking out of a leaned turn must not wind the monowheel into a spin.
const BRAKE_FRAMES := 120
const MAX_BRAKING_SPIN := 2.0
## The monowheel weighs this much more than other bots on the Moon.
const MOON_GRAVITY_SCALE := 1.62 / 9.8
## Hop: the pogo spends a large share of travel airborne, in several bounds.
const MIN_HOP_AIR_FRACTION := 0.35
const MIN_HOPS := 3
## Skate: it glides much further than a tank after the throttle is released.
const MIN_GLIDE_RATIO := 2.0
const STAND_HEIGHT_TOLERANCE := 0.35
## A Foundry-height wall (3 m) ahead of the start: no gait may cross it.
const WALL_SIZE := Vector3(60, 3, 1)
const WALL_AHEAD := 30.0
const WALL_FRAMES := 300
var failures := 0
var world: AuthorityWorld
var sequence := 0
var floor_top := 0.0

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int, bot: MvpBot, throttle := 0.0, steering := 0.0, brake := false, sample: Callable = Callable()) -> void:
	for index: int in range(count):
		var command := BotCommand.new()
		sequence += 1
		command.sequence = sequence
		command.throttle = throttle
		command.steering = steering
		command.brake = brake
		bot.submit_command(command)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		if sample.is_valid(): sample.call()
	await process_frame

func place(draft: Dictionary, id: int) -> MvpBot:
	var bot := world.spawn(id, 0, 0, draft)
	assert(bot != null, "Nimble presets must validate")
	bot.arena_half_extent = 100000.0
	var pose := Transform3D(Basis.IDENTITY, FLOOR_AT + Vector3(0, FLOOR_SIZE.y * 0.5 + bot.ground_clearance() + 0.3, 0))
	bot.spawn_pose = pose
	bot.body.reset_pose = pose
	bot.previous_pose = pose
	bot.last_floor = pose.origin
	await frames(SETTLE_FRAMES, bot)
	return bot

func remove(bot: MvpBot) -> void:
	world.bots.erase(bot.entity_id)
	bot.queue_free()
	await process_frame

func planar_speed(bot: MvpBot) -> float:
	return Vector2(bot.body.linear_velocity.x, bot.body.linear_velocity.z).length()

func run() -> void:
	world = AuthorityWorld.new()
	root.add_child(world)
	world.make_box(FLOOR_SIZE, FLOOR_AT)
	floor_top = FLOOR_AT.y + FLOOR_SIZE.y * 0.5
	var registry := world.registry
	check(registry.nimble().size() == 4, "Four nimble presets")
	for draft: Dictionary in registry.nimble():
		check(registry.validate(draft).valid, "%s validates" % draft.name)
		var modified := draft.duplicate(true)
		modified.parts.weapon = "saw"
		check(not registry.validate(modified).valid, "%s refuses another weapon" % draft.name)
	var borrowed := registry.starter()
	borrowed.parts.drive = "mono_wheel"
	check(not registry.validate(borrowed).valid, "A nimble drive cannot move to another body")
	var tank_speed := await top_speed(registry.atlas(), 1)
	var wheels_speed := await top_speed(registry.starter(), 2)
	print("tank %.1f m/s, standard wheels %.1f m/s" % [tank_speed, wheels_speed])
	var id := 10
	var coast_tank := await coast_distance(registry.atlas(), 3)
	for draft: Dictionary in registry.nimble():
		id += 1
		var speed := await top_speed(draft, id)
		check(speed > tank_speed * 1.4, "%s top speed %.1f beats the tank's %.1f" % [draft.name, speed, tank_speed])
		id += 1
		await stands(draft, id)
		id += 1
		var gait: String = NimbleBots.spec(draft).gait
		if gait == "stride": await stride(draft, id)
		elif gait == "roll": await roll(draft, id)
		elif gait == "hop": await hop(draft, id)
		id += 1
		await walled(draft, id)
		if gait == "skate":
			var glide := await coast_distance(draft, id)
			check(glide > coast_tank * MIN_GLIDE_RATIO, "Skater glides %.1f m after release vs tank %.1f m" % [glide, coast_tank])
	print("FAILURES %d" % failures)
	quit(1 if failures > 0 else 0)

func walled(draft: Dictionary, id: int) -> void:
	var wall := world.make_box(WALL_SIZE, FLOOR_AT + Vector3(0, FLOOR_SIZE.y * 0.5 + WALL_SIZE.y * 0.5, -WALL_AHEAD))
	var bot := await place(draft, id)
	var furthest := [INF]
	var plane := FLOOR_AT.z - WALL_AHEAD
	await frames(WALL_FRAMES, bot, 1.0, 0.0, false, func(): furthest[0] = minf(furthest[0], bot.body.global_position.z - plane))
	check(furthest[0] > 0.0, "%s stays %.1f m short of a 3 m arena wall at full speed" % [draft.name, furthest[0]])
	await remove(bot)
	wall.queue_free()
	await process_frame

func top_speed(draft: Dictionary, id: int) -> float:
	var bot := await place(draft, id)
	var best := [0.0]
	await frames(RUN_FRAMES, bot, 1.0, 0.0, false, func(): best[0] = maxf(best[0], planar_speed(bot)))
	await remove(bot)
	return best[0]

func stands(draft: Dictionary, id: int) -> void:
	var bot := await place(draft, id)
	var height := bot.body.global_position.y - floor_top
	var ride: float = NimbleBots.spec(draft).ride_height
	check(bot.body.grounded, "%s stands on its gait support" % draft.name)
	check(absf(height - ride) < STAND_HEIGHT_TOLERANCE + float(NimbleBots.spec(draft).get("stride", {}).get("bob", 0.0)),
		"%s rides at %.2f m (authored %.2f)" % [draft.name, height, ride])
	check(bot.body.global_basis.y.dot(Vector3.UP) > 0.98, "%s stands upright" % draft.name)
	await remove(bot)

func stride(draft: Dictionary, id: int) -> void:
	var bot := await place(draft, id)
	await frames(90, bot, 1.0)
	var heights: Array[float] = []
	var speeds: Array[float] = []
	await frames(120, bot, 1.0, 0.0, false, func():
		heights.append(bot.body.global_position.y)
		speeds.append(planar_speed(bot)))
	var bob: float = heights.max() - heights.min()
	var surge: float = speeds.max() - speeds.min()
	check(bob > MIN_STRIDE_BOB, "Strider bobs %.2f m per step at speed" % bob)
	check(surge > MIN_STRIDE_SURGE, "Strider speed surges %.2f m/s with its steps" % surge)
	await remove(bot)

func roll(draft: Dictionary, id: int) -> void:
	var bot := await place(draft, id)
	await frames(120, bot, 1.0)
	var lean := [0.0]
	await frames(TURN_FRAMES, bot, 1.0, 1.0, false, func():
		var right := bot.body.global_basis.x
		lean[0] = maxf(lean[0], rad_to_deg(asin(clampf(-right.y, -1.0, 1.0)))))
	check(lean[0] > MIN_ROLL_LEAN_DEGREES, "Monowheel leans %.1f° into a right turn" % lean[0])
	var spin := [0.0]
	await frames(BRAKE_FRAMES, bot, 0.0, 0.0, true, func(): spin[0] = maxf(spin[0], absf(bot.body.angular_velocity.y)))
	check(spin[0] < MAX_BRAKING_SPIN, "Monowheel brakes out of the turn without spinning (%.2f rad/s)" % spin[0])
	bot.body.gravity_scale = MOON_GRAVITY_SCALE
	check(is_equal_approx(bot.body.heft(), float(NimbleBots.spec(draft).low_gravity_heft)) and bot.body.heft() > 1.0,
		"Monowheel keeps extra weight on the Moon (heft %.1f)" % bot.body.heft())
	await remove(bot)
	# Pivot on the spot against the Strider, which turns freely at rest.
	var mono_pivot := await pivot_rate(draft, id + 100)
	var strider_pivot := await pivot_rate(NimbleBots.preset(world.registry, "strider_09"), id + 101)
	check(mono_pivot < strider_pivot * MAX_ROLL_PIVOT_FRACTION, "Monowheel pivots %.2f rad/s at rest vs Strider %.2f" % [mono_pivot, strider_pivot])

func pivot_rate(draft: Dictionary, id: int) -> float:
	var bot := await place(draft, id)
	var best := [0.0]
	await frames(PIVOT_FRAMES, bot, 0.0, 1.0, false, func(): best[0] = maxf(best[0], absf(bot.body.angular_velocity.y)))
	await remove(bot)
	return best[0]

func hop(draft: Dictionary, id: int) -> void:
	var bot := await place(draft, id)
	var airborne := [0, 0, true]
	await frames(RUN_FRAMES, bot, 1.0, 0.0, false, func():
		if not bot.body.grounded: airborne[0] += 1
		if airborne[2] and not bot.body.grounded: airborne[1] += 1
		airborne[2] = bot.body.grounded)
	var fraction := float(airborne[0]) / RUN_FRAMES
	check(fraction > MIN_HOP_AIR_FRACTION, "Pogo is airborne %.0f%% of its run" % (fraction * 100.0))
	check(airborne[1] >= MIN_HOPS, "Pogo bounds %d times" % airborne[1])
	await frames(60, bot)
	check(bot.body.global_basis.y.dot(Vector3.UP) > 0.95, "Pogo lands upright")
	await remove(bot)

func coast_distance(draft: Dictionary, id: int) -> float:
	var bot := await place(draft, id)
	await frames(150, bot, 1.0)
	var start := bot.body.global_position
	await frames(COAST_FRAMES, bot, 0.0)
	var distance := Vector2(bot.body.global_position.x - start.x, bot.body.global_position.z - start.z).length()
	await remove(bot)
	return distance
