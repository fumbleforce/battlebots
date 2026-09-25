class_name SettingsHub
extends Control
signal category_requested(category: String)
signal back_requested
const CATEGORIES := {"game":"Damage numbers and in-match feedback.","video":"Display, anti-aliasing, performance and lighting.","audio":"Master volume, music, effects and announcements.","accessibility":"Text size, color palettes and HUD contrast.","camera":"Sensitivity, inversion, recentering and motion.","controls":"Keyboard, mouse and weapon bindings."}
var buttons: Dictionary = {}
var back_button: Button
var canvas: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = SettingsStyle.make_theme()
	var shade := ColorRect.new()
	shade.color = SettingsStyle.INK
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	add_child(canvas)
	var layout := VBoxContainer.new()
	canvas.add_child(layout)
	layout.position = Vector2(80,50)
	layout.size = Vector2(1760,980)
	layout.add_theme_constant_override("separation",24)
	SettingsStyle.heading(layout,"Settings","Graphics, audio and play preferences.")
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation",48)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(content)
	var categories := VBoxContainer.new()
	categories.custom_minimum_size.x = 1000
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories.add_theme_constant_override("separation",8)
	content.add_child(categories)
	for category: String in CATEGORIES:
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation",4)
		categories.add_child(line)
		var button := Button.new()
		button.text = "VIDEO & GRAPHICS" if category == "video" else category.to_upper()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_override("font",preload("res://ui/menus/fonts/BarlowCondensed-SemiBold.ttf"))
		button.add_theme_font_size_override("font_size",30)
		button.custom_minimum_size.y = 58
		line.add_child(button)
		button.pressed.connect(func() -> void: category_requested.emit(category))
		buttons[category] = button
		SettingsStyle.label(line,CATEGORIES[category],20,SettingsStyle.MUTED)
	var aside := VBoxContainer.new()
	aside.custom_minimum_size.x = 640
	content.add_child(aside)
	aside.add_theme_constant_override("separation",20)
	var art := TextureRect.new()
	art.texture = preload("res://ui/menus/art/arena_foundry.jpg")
	art.custom_minimum_size = Vector2(640,360)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	aside.add_child(art)
	SettingsStyle.label(aside,"THE FOUNDRY",26,SettingsStyle.ACCENT)
	var note := SettingsStyle.label(aside,"Graphics settings apply to every arena.\\nStart with High quality, then tune performance for your hardware.",22,SettingsStyle.MUTED)
	note.text = note.text.replace("\\n","\n")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	back_button = SettingsStyle.button(layout,"Back",func() -> void: back_requested.emit())
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x/1920.0,extent.y/1080.0)
	canvas.size = Vector2(1920,1080)
	canvas.scale = Vector2.ONE*ratio
	canvas.position = (extent-canvas.size*ratio)*0.5

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self,factor)

func open(category := "video") -> void:
	show()
	buttons.get(category,buttons.video).grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
