extends PanelContainer
## Daily deal row with struck-through old price.

signal buy_requested


func _ready() -> void:
	%Buy.pressed.connect(func(): buy_requested.emit())


func setup(d: Dictionary, is_owned: bool, can_afford: bool) -> void:
	%Name.text = d.name
	%Info.text = d.info
	%Was.text = "[s]%s[/s]" % MenuData.fmt_int(int(d.was))
	var price := int(d.price)
	if is_owned:
		%Buy.text = "OWNED"
	elif can_afford:
		%Buy.text = "BUY · %s" % MenuData.fmt_int(price)
	else:
		%Buy.text = "%s SCRAP" % MenuData.fmt_int(price)
	%Buy.disabled = is_owned or not can_afford
