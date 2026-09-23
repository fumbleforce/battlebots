extends SceneTree
## Native review captures of match pickups in the real menu game's Practice:
## stocked markers, a live body swap with the HUD feed, perk/credit toasts and a
## centred notice for a refused pickup.
## Run: godot --path battlebots --script res://tools/capture_pickup_review.gd
var output := "res://exports/pickup-review"
var game: Node

func _initialize() -> void:
	run.call_deferred()

func settle(frames := 45) -> void:
	for index: int in frames:
		await physics_frame
		await process_frame

func capture(caption: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(caption + ".png"))
	print("captured ", caption)

func place(bot: MvpBot, at: Vector3, facing: float) -> void:
	var world: AuthorityWorld = game.session.world
	bot.body.reset_pose = world.clear_spawn_pose(bot, Transform3D(Basis(Vector3.UP, facing), at))
	bot.body.linear_velocity = Vector3.ZERO
	bot.body.angular_velocity = Vector3.ZERO

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native rendering required")
		quit(1)
		return
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	root.add_child(game)
	await settle(30)
	var session: MvpSession = game.session
	var draft: Dictionary = ContentRegistry.new().starter()
	draft.parts.nitro = "nitro_off"
	if session.practice(draft, "foundry") != OK:
		push_error("Practice did not start")
		quit(1)
		return
	game.resume_gameplay()
	await settle(20)
	var world: AuthorityWorld = session.world
	var items := world.pickups.items
	var kinds := [["part", "atlas_mx", 0], ["perk", "nitro_boost", 0], ["credits", "", 50], ["part", "hammer", 0], ["credits", "", 100]]
	for index: int in items.size():
		items[index].kind = kinds[index][0]
		items[index].part = kinds[index][1]
		items[index].amount = kinds[index][2]
		items[index].available = true
	world.pickups.revision += 1
	# Keep the practice NPCs out of frame and off the points.
	for bot: MvpBot in world.bots.values():
		if bot.entity_id != session.local_entity:
			place(bot, Vector3(0, 0, 40) + Vector3(bot.entity_id * 9.0 - 18.0, 0, 0), 0.0)
	var player: MvpBot = world.bots[session.local_entity]
	place(player, Vector3(0, 0, 17), 0.0)
	await settle(90)
	await capture("01-stocked-pickups")
	place(world.bots[session.local_entity], items[0].point, 0.0)
	await settle(40)
	await capture("02-body-swap-feed")
	place(world.bots[session.local_entity], items[1].point, PI * 0.25)
	await settle(25)
	place(world.bots[session.local_entity], items[2].point, PI * 0.25)
	await settle(25)
	await capture("03-perk-credit-toasts")
	# Drive back onto a Nitro the bot now has: the server refuses it with a reason.
	items[1].kind = "perk"
	items[1].part = "nitro_boost"
	items[1].available = true
	world.pickups.revision += 1
	place(world.bots[session.local_entity], items[1].point, PI * 0.25)
	await settle(20)
	await capture("04-refused-notice")
	print("PICKUP REVIEW CAPTURED")
	quit(0)
