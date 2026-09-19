extends BotSource
## Local simulation adapter. Networking and combat are not implemented.

@onready var body: DriveBody = $Body

func submit_command(command: BotCommand) -> void:
	if command != null and command.is_valid():
		body.accept_command(command)

func read_view() -> BotView:
	var view := BotView.new()
	view.entity_id = 1
	view.pose = body.global_transform
	return view

func camera_anchor() -> Node3D:
	return body.get_node("CameraAnchor")

func camera_exclusions() -> Array[RID]:
	return [body.get_rid()]
