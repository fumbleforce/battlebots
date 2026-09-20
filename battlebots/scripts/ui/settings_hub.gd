class_name SettingsHub
extends Control
signal category_requested(category: String)
signal back_requested
const CATEGORIES := {"video":"Display mode, resolution and vertical sync.", "audio":"Master, music, effects and announcements.", "accessibility":"Text size, color palette and contrast.", "camera":"Camera sensitivity, inversion and recentering.", "controls":"Keyboard, mouse and weapon activation bindings."}
var buttons: Dictionary = {}
var back_button: Button
var canvas: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	var art := TextureRect.new()
	art.texture = preload("res://ui/menus/art/bg_arena_blur.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.06, 0.93)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	add_child(canvas)
	var layout := VBoxContainer.new()
	canvas.add_child(layout)
	layout.position = Vector2(80, 48)
	layout.size = Vector2(1760, 984)
	layout.add_theme_constant_override("separation", 24)
	var heading := Label.new()
	heading.text = "SETTINGS"
	heading.theme_type_variation = &"HeadingItalic"
	heading.add_theme_font_size_override("font_size", 60)
	layout.add_child(heading)
	var help := Label.new()
	help.text = "Choose a category. Changes can be reviewed before saving."
	help.add_theme_font_size_override("font_size", 24)
	help.theme_type_variation = &"Muted"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(grid)
	for category: String in CATEGORIES:
		var card := PanelContainer.new()
		card.theme_type_variation = &"PanelBox"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 12)
		card.add_child(column)
		var button := Button.new()
		button.text = category.to_upper()
		button.theme_type_variation = &"MenuItem"
		button.add_theme_font_size_override("font_size", 34)
		button.custom_minimum_size.y = 70
		column.add_child(button)
		button.pressed.connect(func() -> void: category_requested.emit(category))
		buttons[category] = button
		var description := Label.new()
		description.text = CATEGORIES[category]
		description.theme_type_variation = &"Muted"
		description.add_theme_font_size_override("font_size", 22)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(description)
	back_button = Button.new()
	back_button.text = "BACK"
	back_button.theme_type_variation = &"GhostButton"
	back_button.add_theme_font_size_override("font_size", 30)
	back_button.custom_minimum_size = Vector2(220, 76)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout.add_child(back_button)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1920.0, extent.y / 1080.0)
	canvas.size = Vector2(1920, 1080)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (extent - canvas.size * ratio) * 0.5

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)

func open(category := "video") -> void:
	show()
	buttons.get(category, buttons.video).grab_focus()
