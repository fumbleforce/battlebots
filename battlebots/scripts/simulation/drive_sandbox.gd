extends Node3D
## A-only manual test harness. B supplies the production camera/input presentation.

@onready var source: BotSource = $Bot
var sequence: int = 0

func _ready() -> void:
	# Temporary collision fixtures, independent of B's evolving arena perimeter.
	for side: int in range(4):
		var wall := StaticBody3D.new()
		wall.collision_layer = BaselineConfig.WORLD_LAYER
		wall.collision_mask = BaselineConfig.BOT_LAYER
		var shape := BoxShape3D.new()
		shape.size = Vector3(51, 3, 0.5) if side < 2 else Vector3(0.5, 3, 50)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		wall.add_child(collider)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		mesh.mesh = box
		wall.add_child(mesh)
		wall.position = [Vector3(0, 1.5, -25.25), Vector3(0, 1.5, 25.25),
			Vector3(-25.25, 1.5, 0), Vector3(25.25, 1.5, 0)][side]
		add_child(wall)

func _physics_process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	command.brake = not get_window().has_focus()
	if get_window().has_focus():
		command.throttle = Input.get_axis("drive_reverse", "drive_forward")
		command.steering = Input.get_axis("steer_left", "steer_right")
		command.brake = Input.is_action_pressed("brake")
	source.submit_command(command)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file("res://scenes/app/main.tscn")
