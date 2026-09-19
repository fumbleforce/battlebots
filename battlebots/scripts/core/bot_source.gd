class_name BotSource
extends Node3D
## Adapter boundary: A implements a real source; B can substitute a fixture source.

func submit_command(_command: BotCommand) -> void:
	pass

func read_view() -> BotView:
	var view := BotView.new()
	view.pose = global_transform
	return view

func camera_anchor() -> Node3D:
	return self

func camera_exclusions() -> Array[RID]:
	return []
