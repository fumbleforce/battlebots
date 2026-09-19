extends PanelContainer
## Lobby player slot. status: "ready", "not_ready" or "none".


func setup(d: Dictionary) -> void:
	%Name.text = d.get("name", "")
	%Sub.text = d.get("sub", "")
	var thumb: Texture2D = d.get("thumb")
	%Thumb.texture = thumb
	%Thumb.visible = thumb != null
	%Waiting.visible = thumb == null
	theme_type_variation = &"SlotYou" if d.get("you", false) else &"Slot"
	set_status(d.get("status", "none"))


func set_status(status: String) -> void:
	%Badge.visible = status != "none"
	if status == "ready":
		%Badge.theme_type_variation = &"BadgeReady"
		%BadgeLabel.text = "READY"
		%BadgeLabel.add_theme_color_override("font_color", MenuData.INK)
	else:
		%Badge.theme_type_variation = &"BadgeOutline"
		%BadgeLabel.text = "NOT READY"
		%BadgeLabel.add_theme_color_override("font_color", MenuData.TEXT2)
