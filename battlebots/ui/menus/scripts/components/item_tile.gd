extends Button
## Customize option tile: swatch (paint) or art placeholder, name and ownership status.


func setup(it: Dictionary, state: String) -> void:
	%Name.text = it.name
	var has_swatch := it.has("swatch")
	%Swatch.visible = has_swatch
	%Art.visible = not has_swatch
	if has_swatch:
		%Swatch.color = Color(it.swatch)
	%Lock.visible = state == "lock"
	match state:
		"eq":
			_status("EQUIPPED", MenuData.GREEN)
		"own":
			_status("AVAILABLE", MenuData.TEXT2)
		"lock":
			_status("UNAVAILABLE", MenuData.MUTED)
		_:
			_status("%s SCRAP" % MenuData.fmt_int(int(it.get("price", 0))), MenuData.AMBER)


func _status(text: String, color: Color) -> void:
	%Status.text = text
	%Status.add_theme_color_override("font_color", color)
