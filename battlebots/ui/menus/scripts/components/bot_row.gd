extends Button
## Garage bot list row. Its thumbnail is captured from the current 3D loadout.


func setup(bot: Dictionary) -> void:
	%Thumb.texture = null
	%Thumb.tooltip_text = "Build model unavailable until repaired" if not bot.valid else "Rendering build preview"
	%Name.text = bot.name
	if has_node("%Class"):
		%Class.text = bot.cls


func set_thumbnail(texture: Texture2D) -> void:
	%Thumb.texture = texture
	%Thumb.tooltip_text = "Captured build model" if texture != null else "Build model unavailable until repaired"
