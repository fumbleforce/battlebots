extends SceneTree
## Optional source-engine wrapper. Deployed workers use normal app startup with
## -- --allocation-config=... so export templates follow the same packed scene.
func _initialize() -> void:
	var worker: Node = load("res://scenes/app/hosted_server.tscn").instantiate()
	root.add_child.call_deferred(worker)
