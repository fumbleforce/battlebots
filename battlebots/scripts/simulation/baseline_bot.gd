extends BotSource
## A-owned fixture: passive rigid body only. Drive and networking are not implemented.

@onready var body: RigidBody3D = $Body
var last_command: BotCommand

func submit_command(command: BotCommand) -> void:
	if command.is_valid():
		last_command = command

func read_view() -> BotView:
	var view := BotView.new()
	view.entity_id = 1
	view.pose = body.global_transform
	return view

func camera_anchor() -> Node3D:
	return body.get_node("CameraAnchor")

func camera_exclusions() -> Array[RID]:
	return [body.get_rid()]
