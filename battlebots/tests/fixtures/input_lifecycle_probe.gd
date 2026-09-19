extends SessionBotSource
## Lifecycle gate probe used without entering a live networking scene.
var last_command: BotCommand

func submit_command(command: BotCommand) -> void:
	last_command = command
