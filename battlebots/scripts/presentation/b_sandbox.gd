extends Node3D
## Developer B fixture shortcuts, deliberately outside the production InputMap.

@onready var bot: BotSource = $Bot
@onready var preview: Node3D = $Preview

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not preview.controls_enabled:
		return
	match event.physical_keycode:
		KEY_1:
			place_mock(Vector3(0, 0.3, 0), 0.0)
		KEY_2:
			place_mock(Vector3(0, 0.3, 22.8), 0.0)
		KEY_3:
			place_mock(Vector3(22.8, 0.3, 22.8), PI / 4.0)
		KEY_4:
			bot.mock_roll = not bot.mock_roll
		KEY_5:
			preview.rig.auto_recenter = not preview.rig.auto_recenter
		_:
			return
	get_viewport().set_input_as_handled()

func place_mock(at: Vector3, heading: float) -> void:
	bot.position = at
	bot.rotation = Vector3(0.0, heading, 0.0)
	bot.mock_roll = false
	preview.rig.recenter()
