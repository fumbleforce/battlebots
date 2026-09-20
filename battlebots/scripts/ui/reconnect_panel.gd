class_name ReconnectPanel
extends Control
## Presentation only: session/server state decides whether another attempt is valid.
signal retry_requested
signal leave_requested

var retry: Button
var leave_button: Button
var heading: Label
var status: Label
var countdown: Label
var canvas: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	mouse_filter = Control.MOUSE_FILTER_STOP
	var art := TextureRect.new()
	art.texture = preload("res://ui/menus/art/bg_arena_blur.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.06, 0.9)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var stripe := TextureRect.new()
	stripe.texture = preload("res://ui/menus/art/hazard_stripe.png")
	stripe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stripe.stretch_mode = TextureRect.STRETCH_TILE
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.size = Vector2(1280, 8)
	canvas.add_child(stripe)
	var column := VBoxContainer.new()
	column.position = Vector2(96, 96)
	column.size = Vector2(1088, 536)
	column.add_theme_constant_override("separation", 20)
	canvas.add_child(column)
	_label(column, "THE FOUNDRY  /  MULTIPLAYER", &"EyebrowAmber", 20)
	heading = _label(column, "CONNECTION LOST", &"HeadingItalic", 56)
	status = _label(column, "", &"Muted", 24)
	status.custom_minimum_size.y = 68
	var card := PanelContainer.new()
	card.theme_type_variation = &"PanelGlass"
	column.add_child(card)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 20)
	card.add_child(inset)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 12)
	inset.add_child(details)
	countdown = _label(details, "", &"EyebrowAmber", 22)
	_label(details, "The match continues while you are disconnected. Your bot remains vulnerable.\nThe server decides whether you can rejoin the match.", &"Muted", 22)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 28)
	column.add_child(actions)
	retry = _button(actions, "RECONNECT", &"MenuItemPrimary")
	leave_button = _button(actions, "LEAVE TO MAIN MENU", &"MenuItem")
	retry.pressed.connect(func() -> void: retry_requested.emit())
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	get_viewport().size_changed.connect(_resize)
	_resize()
	render(false, false, 0.0)

func render(can_retry: bool, connecting: bool, seconds: float, message: String = "") -> void:
	if not is_instance_valid(retry):
		return
	var remaining := maxi(0, ceili(seconds)) if is_finite(seconds) else 0
	var available := can_retry and remaining > 0
	heading.text = "RECONNECTING" if connecting else ("CONNECTION LOST" if available else "UNABLE TO RECONNECT")
	status.text = message if not message.is_empty() else ("Trying to return you to your match..." if connecting else ("Your connection to the match was interrupted." if available else "This reconnect attempt is no longer available. Return to the menu to start a new match."))
	countdown.text = "RECONNECT WINDOW  /  UP TO %ds" % remaining if remaining > 0 else "RETRY WINDOW CLOSED"
	var retry_focused := retry.has_focus()
	retry.disabled = connecting or not available
	retry.text = "CONNECTING..." if connecting else "RECONNECT"
	leave_button.disabled = false
	if retry_focused and retry.disabled:
		leave_button.grab_focus()

func _label(parent: Node, text: String, variation: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", 26)
	button.custom_minimum_size = Vector2(400, 68)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
	canvas.size = Vector2(1280, 720)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (extent - canvas.size * ratio) * 0.5
