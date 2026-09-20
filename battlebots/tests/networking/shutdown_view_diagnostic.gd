extends SceneTree
## A integration diagnostic: one real bot, public views, then normal teardown.
## A completed workload does not mean the subsequent native shutdown succeeded.

var world: Node3D
var source: BotSource

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	ground.add_child(collision)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)
	source = load("res://scenes/bots/baseline_bot.tscn").instantiate() as BotSource
	world.add_child(source)
	await process_frame
	for step: int in range(2000):
		var view := source.read_view()
		if not view.pose.origin.is_finite():
			push_error("NONFINITE VIEW")
		await physics_frame
	await process_frame
	world.queue_free()
	await process_frame
	print("SHUTDOWN VIEW DONE")
	quit(0)
