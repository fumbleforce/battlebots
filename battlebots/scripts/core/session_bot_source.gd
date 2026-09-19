class_name SessionBotSource
extends BotSource
## B can point the existing input/camera adapter at this node across loads/reconnects.
@export var session_path: NodePath
@onready var session: MvpSession = get_node(session_path) as MvpSession
func submit_command(command: BotCommand) -> void:
	session.submit_local(command)
func read_view() -> BotView:
	var source := session.local_source()
	return source.read_view() if source != null else BotView.new()
func camera_anchor() -> Node3D:
	var source := session.local_source()
	return source.camera_anchor() if source != null else self
func camera_exclusions() -> Array[RID]:
	var source := session.local_source()
	return source.camera_exclusions() if source != null else []
