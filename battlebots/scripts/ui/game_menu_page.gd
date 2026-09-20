extends Control
## A-owned menu composition; the preview retains its control and settings behavior.
var panel: PanelContainer
var context: Label
var score: Label
var phase_label: Label
var description: Label

func configure(existing_panel: PanelContainer) -> void:
	panel = existing_panel
	name = "GameMenuPage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.get_parent().add_child(self)
	panel.reparent(self)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.remove_theme_stylebox_override("panel")
	panel.theme = preload("res://ui/menus/theme/menu_theme.tres")
	var art := TextureRect.new()
	art.texture = preload("res://ui/menus/art/bg_arena_blur.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	panel.move_child(art, 0)
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.06, 0.9)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shade)
	panel.move_child(shade, 1)
	var margin := panel.get_node("Margin") as MarginContainer
	margin.add_theme_constant_override("margin_left", 112)
	margin.add_theme_constant_override("margin_right", 1060)
	margin.add_theme_constant_override("margin_top", 92)
	margin.add_theme_constant_override("margin_bottom", 84)
	var actions := margin.get_node("Content") as VBoxContainer
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	actions.reparent(scroll)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 20)
	var title := actions.get_node("Title") as Label
	title.text = "GAME MENU"
	title.theme_type_variation = &"HeadingItalic"
	title.add_theme_font_size_override("font_size", 76)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description = actions.get_node("Description") as Label
	description.theme_type_variation = &"Muted"
	description.add_theme_font_size_override("font_size", 25)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 80
	for child: Node in actions.get_children():
		if child is Button:
			child.theme_type_variation = &"MenuItemPrimary" if child.name == "Resume" else &"MenuItem"
			child.add_theme_font_size_override("font_size", 34)
			child.custom_minimum_size.y = 76
			child.remove_theme_stylebox_override("focus")
	(actions.get_node("Resume") as Button).text = "RESUME GAME"
	(actions.get_node("Settings") as Button).text = "SETTINGS"
	(actions.get_node("Return") as Button).text = "LEAVE TO MAIN MENU"
	var details_margin := MarginContainer.new()
	details_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(details_margin)
	details_margin.add_theme_constant_override("margin_left", 1000)
	details_margin.add_theme_constant_override("margin_right", 112)
	details_margin.add_theme_constant_override("margin_top", 244)
	details_margin.add_theme_constant_override("margin_bottom", 220)
	var card := PanelContainer.new()
	card.theme_type_variation = &"PanelGlass"
	details_margin.add_child(card)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 40)
	card.add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	inset.add_child(column)
	context = _label(column, "", &"HeadingWide", 30)
	_label(column, "THE FOUNDRY", &"HeadingItalic", 58)
	column.add_child(HSeparator.new())
	score = _label(column, "", &"HeadingWide", 48)
	phase_label = _label(column, "", &"Muted", 26)
	phase_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label(column, "ESC  /  RETURN TO THE ARENA", &"Muted", 22)
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)
	var stripe := TextureRect.new()
	stripe.texture = preload("res://ui/menus/art/hazard_stripe.png")
	stripe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stripe.stretch_mode = TextureRect.STRETCH_TILE
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(stripe)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 10
	get_viewport().size_changed.connect(_resize)
	_resize()

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)

func _label(parent: Node, text: String, variation: StringName, font_size: int) -> Label:
	var item := Label.new()
	item.text = text
	item.theme_type_variation = variation
	item.add_theme_font_size_override("font_size", font_size)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1920.0, extent.y / 1080.0)
	size = Vector2(1920, 1080)
	scale = Vector2.ONE * ratio
	position = (extent - size * ratio) * 0.5

func render(view: Dictionary, practice: bool) -> void:
	context.text = "PRACTICE" if practice else str(view.get("mode", "1v1")).to_upper() + " / MATCH IN PROGRESS"
	description.text = "Take a moment to adjust your setup.\nThe arena stays live while this menu is open."
	score.text = "TEST YOUR BUILD" if practice else "ROUND %d" % int(view.get("round", 0))
	if not practice and view.get("scores") is Array and view.scores.size() == 2:
		score.text += "   /   %d : %d" % [int(view.scores[0]), int(view.scores[1])]
	phase_label.text = "Restart to repair both bots and reset their positions." if practice else str(view.get("phase", "")).capitalize()
	if not practice and (view.get("remaining") is float or view.get("remaining") is int):
		var seconds := maxi(0, ceili(float(view.remaining)))
		phase_label.text += "  ·  %d:%02d remaining" % [seconds / 60, seconds % 60]
