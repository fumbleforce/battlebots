extends VBoxContainer
## Labelled 0-100 stat bar with an optional +/- delta segment (green gain, red loss).


func set_stat(label: String, value: int, delta := 0, highlight := false) -> void:
	%Name.text = label
	var maximum: float = {"MASS kg":120.0,"POWER":100.0,"SPEED m/s":12.0,"ARMOR %":100.0}.get(label,100.0)
	%Value.text = "%d / %d" % [value + delta,int(maximum)]
	%Delta.text = "" if delta == 0 else "%+d" % delta
	var col := MenuData.GREEN if delta > 0 else MenuData.RED
	%Delta.add_theme_color_override("font_color", col)
	var base := clampf(float(value + mini(delta, 0)) / maximum, 0.0, 1.0)
	%Fill.anchor_right = base
	%Fill.color = MenuData.AMBER if highlight else MenuData.TEXT
	%DeltaFill.anchor_left = base
	%DeltaFill.anchor_right = clampf(base + absf(delta) / maximum, 0.0, 1.0)
	%DeltaFill.color = col
	%DeltaFill.visible = delta != 0
