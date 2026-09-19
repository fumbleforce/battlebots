extends PanelContainer
## Upgrade shop track: level pips, current effect, next step and buy button.

signal buy_requested


func _ready() -> void:
	%Buy.pressed.connect(func(): buy_requested.emit())


func setup(title: String, level: int, max_level: int, desc: String, next: String, cost: int, can_afford: bool) -> void:
	%Name.text = title
	%Level.text = "LV %d / %d" % [level, max_level]
	var i := 0
	for pip in %Pips.get_children():
		pip.theme_type_variation = &"PipOn" if i < level else &"Pip"
		i += 1
	%Desc.text = desc
	var maxed := level >= max_level
	%Next.text = "Fully upgraded" if maxed else "Next: " + next
	if maxed:
		%Buy.text = "MAXED"
	elif can_afford:
		%Buy.text = "UPGRADE · %s" % MenuData.fmt_int(cost)
	else:
		%Buy.text = "NEED %s SCRAP" % MenuData.fmt_int(cost)
	%Buy.disabled = maxed or not can_afford
