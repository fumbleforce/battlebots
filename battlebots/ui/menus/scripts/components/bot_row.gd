extends Button
## Garage bot list row / shop bot chip.


func setup(bot: Dictionary) -> void:
	%Thumb.texture = bot.image
	%Name.text = bot.name
	if has_node("%Class"):
		%Class.text = bot.cls
