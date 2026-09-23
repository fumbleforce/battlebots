extends Button
## Compact Customize option tile: one line with the name and, when relevant, its
## status; paint choices add a thin colour strip.


func setup(it: Dictionary, state: String) -> void:
	%Name.text = it.name
	tooltip_text = it.name
	var has_swatch := it.has("swatch")
	# Parts have no art yet; only paint choices keep a slim colour strip.
	$Inner/Col/ArtBox.visible = has_swatch
	%Swatch.visible = has_swatch
	%Art.visible = not has_swatch
	if has_swatch:
		%Swatch.color = Color(it.swatch)
	%Lock.visible = state == "lock"
	# Listed choices are usable, so only equipped/unavailable states need a label.
	%Status.visible = state != "own"
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
