class_name SettingsStyle
extends RefCounted
## Settings-only visual system: Barlow display/body, steel blue, warm readable values.
const INK := Color("101b26")
const SURFACE := Color("172634")
const LINE := Color("314957")
const TEXT := Color("e6e9df")
const MUTED := Color("a5b6bf")
const ACCENT := Color("eebd65")
const COOL := Color("7dc5d4")

static func box(color: Color, border := Color.TRANSPARENT, padding := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(3)
	for edge: String in ["left","right","top","bottom"]: style.set("content_margin_"+edge,padding)
	return style

static func make_theme() -> Theme:
	var result: Theme = preload("res://ui/menus/theme/menu_theme.tres").duplicate()
	result.default_font = preload("res://ui/menus/fonts/Barlow-Regular.ttf")
	result.default_font_size = 22
	for kind: String in ["Label","Button","OptionButton","CheckButton","CheckBox","PopupMenu"]:
		result.set_color("font_color",kind,TEXT)
		result.set_color("font_hover_color",kind,Color.WHITE)
		result.set_color("font_focus_color",kind,Color.WHITE)
		result.set_color("font_disabled_color",kind,Color("71838e"))
	for kind: String in ["Button","OptionButton"]:
		result.set_stylebox("normal",kind,box(SURFACE,LINE,12))
		result.set_stylebox("hover",kind,box(Color("233d4c"),COOL,12))
		result.set_stylebox("pressed",kind,box(Color("36505d"),ACCENT,12))
		result.set_stylebox("disabled",kind,box(INK,LINE,12))
		var focus := box(Color.TRANSPARENT,ACCENT,0)
		focus.draw_center = false
		focus.set_border_width_all(2)
		result.set_stylebox("focus",kind,focus)
	result.set_stylebox("panel","PopupMenu",box(INK,LINE,12))
	result.set_stylebox("hover","PopupMenu",box(SURFACE,COOL,8))
	result.set_stylebox("panel","PanelContainer",box(INK,LINE,24))
	result.set_stylebox("slider","HSlider",box(LINE,Color.TRANSPARENT,3))
	result.set_stylebox("grabber_area","HSlider",box(COOL,Color.TRANSPARENT,3))
	result.set_stylebox("grabber_area_highlight","HSlider",box(ACCENT,Color.TRANSPARENT,3))
	return result

static func label(parent: Node, text: String, font_size := 22, color := TEXT) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size",font_size)
	item.add_theme_color_override("font_color",color)
	parent.add_child(item)
	return item

static func heading(parent: Node, title: String, description: String) -> void:
	var title_label := label(parent,title.to_upper(),36)
	title_label.add_theme_font_override("font",preload("res://ui/menus/fonts/BarlowCondensed-Bold.ttf"))
	var subtitle := label(parent,description,18,MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func section(parent: Node, caption: String) -> void:
	var item := label(parent,caption.to_upper(),18,ACCENT)
	item.custom_minimum_size.y = 38
	item.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

static func row(parent: Node, caption: String, description: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",box(SURFACE,Color.TRANSPARENT,10))
	parent.add_child(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation",28)
	panel.add_child(line)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation",3)
	line.add_child(copy)
	label(copy,caption,20)
	if not description.is_empty():
		var note := label(copy,description,16,MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return line

static func button(parent: Node, caption: String, callback: Callable, primary := false) -> Button:
	var item := Button.new()
	item.text = caption
	item.custom_minimum_size = Vector2(160,52)
	if primary:
		item.add_theme_stylebox_override("normal",box(ACCENT,ACCENT,12))
		item.add_theme_color_override("font_color",INK)
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

static func page(panel: PanelContainer, title: String, description: String) -> Dictionary:
	panel.theme = make_theme()
	panel.theme_type_variation = &""
	panel.custom_minimum_size = Vector2(1360,800)
	panel.add_theme_stylebox_override("panel",box(INK,LINE,28))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	heading(column,title,description)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",12)
	column.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",6)
	scroll.add_child(content)
	var message := label(column,"",18,MUTED)
	message.custom_minimum_size.y = 50
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",12)
	column.add_child(footer)
	return {"column":column,"tabs":tabs,"scroll":scroll,"content":content,"message":message,"footer":footer}

static func focus_cycle(controls: Array) -> void:
	for index: int in range(controls.size()):
		var control: Control = controls[index]
		control.focus_next = control.get_path_to(controls[(index+1)%controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index-1,controls.size())])
