extends Control
## A-owned menu composition; the preview retains its control and settings behavior.
var panel: PanelContainer
var context: Label
var score: Label
var phase_label: Label
var description: Label
var details_margin: MarginContainer
var summary: VBoxContainer
var tuning_panel: VBoxContainer
## Details card margins. The tuning panel uses a taller, wider card: its left
## edge stops just clear of the menu actions (which end at 1920 - 1060).
const SUMMARY_BOTTOM := 220
const TUNING_BOTTOM := 84
const SUMMARY_SIDES := Vector2i(1000, 112)
const TUNING_SIDES := Vector2i(890, 60)
const DETAILS_TOP := 244
## Action column margins on the design page.
const ACTIONS_LEFT := 112
const ACTIONS_RIGHT := 1060
const ACTIONS_TOP := 92
const ACTIONS_BOTTOM := 84
const DESIGN_SIZE := Vector2(1920, 1080)
var actions_margin: MarginContainer
## Extra design-space around the 1920x1080 layout on non-16:9 screens.
var _pad := Vector2.ZERO
var _tuned := false

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
	actions_margin = margin
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
	details_margin = MarginContainer.new()
	details_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(details_margin)
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
	summary = column
	# Practice Duel (#84) swaps the summary for live weapon and body tuning.
	tuning_panel = preload("res://scripts/ui/practice_tuning_panel.gd").new()
	tuning_panel.hide()
	inset.add_child(tuning_panel)
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

## Keeps the 1920x1080 design scale but covers the whole screen at any aspect:
## the page grows in design units, the actions hold the left edge, the details
## card holds the right edge (like the HUD tuning overlay) and both stay
## vertically centred.
func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := maxf(minf(extent.x / DESIGN_SIZE.x, extent.y / DESIGN_SIZE.y), 0.001)
	scale = Vector2.ONE * ratio
	size = extent / ratio
	position = Vector2.ZERO
	_pad = (size - DESIGN_SIZE).max(Vector2.ZERO)
	_place()

func _place() -> void:
	var half_y := int(_pad.y * 0.5)
	actions_margin.add_theme_constant_override("margin_left", ACTIONS_LEFT)
	actions_margin.add_theme_constant_override("margin_right", ACTIONS_RIGHT + int(_pad.x))
	actions_margin.add_theme_constant_override("margin_top", ACTIONS_TOP + half_y)
	actions_margin.add_theme_constant_override("margin_bottom", ACTIONS_BOTTOM + half_y)
	# The margin spans the whole page, so it must keep ignoring the mouse or
	# it would swallow the menu buttons on the left.
	var sides := TUNING_SIDES if _tuned else SUMMARY_SIDES
	details_margin.add_theme_constant_override("margin_left", sides.x + int(_pad.x))
	details_margin.add_theme_constant_override("margin_right", sides.y)
	details_margin.add_theme_constant_override("margin_top", DETAILS_TOP + half_y)
	details_margin.add_theme_constant_override("margin_bottom", (TUNING_BOTTOM if _tuned else SUMMARY_BOTTOM) + half_y)

## tuning is the Practice Duel's live tuning (MvpSession.practice_tuning()) and parts
## the session that swaps its weapon and chassis; both null otherwise.
func render(view: Dictionary, practice: bool, tuning: RefCounted = null, parts: Node = null) -> void:
	var tuned := tuning != null
	if tuning_panel.visible != tuned:
		tuning_panel.visible = tuned
		summary.visible = not tuned
		# The card sits below the network diagnostics; the tuning list uses the full height.
		_tuned = tuned
		_place()
	if tuned:
		tuning_panel.render(tuning, parts)
	context.text = "PRACTICE" if practice else str(view.get("mode", "1v1")).to_upper() + " / MATCH IN PROGRESS"
	description.text = "Take a moment to adjust your setup.\nThe arena stays live while this menu is open."
	score.text = "TEST YOUR BUILD" if practice else "ROUND %d" % int(view.get("round", 0))
	if not practice and view.get("scores") is Array and view.scores.size() == 2:
		score.text += "   /   %d : %d" % [int(view.scores[0]), int(view.scores[1])]
	phase_label.text = "Restart to repair both bots and reset their positions." if practice else str(view.get("phase", "")).capitalize()
	if not practice and (view.get("remaining") is float or view.get("remaining") is int):
		var seconds := maxi(0, ceili(float(view.remaining)))
		phase_label.text += "  ·  %d:%02d remaining" % [seconds / 60, seconds % 60]
