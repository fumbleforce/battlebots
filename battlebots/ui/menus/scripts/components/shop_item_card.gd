extends PanelContainer
## Shop grid card (parts / cosmetics).

signal buy_requested


func _ready() -> void:
	%Buy.pressed.connect(func(): buy_requested.emit())


func setup(it: Dictionary, is_owned: bool, can_afford: bool) -> void:
	%Kind.text = it.kind
	%Name.text = it.name
	%Info.text = it.info
	var has_swatch := it.has("swatch")
	%Swatch.visible = has_swatch
	%Art.visible = not has_swatch
	if has_swatch:
		%Swatch.color = Color(it.swatch)
	var price := int(it.price)
	if is_owned:
		%Buy.text = "OWNED"
	elif can_afford:
		%Buy.text = "BUY · %s" % MenuData.fmt_int(price)
	else:
		%Buy.text = "%s SCRAP" % MenuData.fmt_int(price)
	%Buy.disabled = is_owned or not can_afford
