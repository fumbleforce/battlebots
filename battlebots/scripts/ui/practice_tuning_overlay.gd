extends Control
## Practice Duel HUD tuning panel (#94): the Esc menu's right-hand card
## (scripts/ui/practice_tuning_panel.gd) shown over the arena while the player
## keeps driving. menu_game toggles it on the practice_panel action. Only the
## card takes the mouse; everything around it passes through to gameplay.
const TUNING_PANEL = preload("res://scripts/ui/practice_tuning_panel.gd")
## The Esc menu's tuning card placement on the 1920x1080 design page
## (game_menu_page TUNING_SIDES / TUNING_BOTTOM and its details top).
const CARD_LEFT := 890
const CARD_RIGHT := 60
const CARD_TOP := 244
const CARD_BOTTOM := 84
const CARD_INSET := 40
var card: PanelContainer
var tuning_panel: VBoxContainer

func _init() -> void:
	name = "PracticeTuningOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", CARD_LEFT)
	margin.add_theme_constant_override("margin_right", CARD_RIGHT)
	margin.add_theme_constant_override("margin_top", CARD_TOP)
	margin.add_theme_constant_override("margin_bottom", CARD_BOTTOM)
	card = PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"PanelGlass"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(card)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, CARD_INSET)
	card.add_child(inset)
	tuning_panel = TUNING_PANEL.new()
	tuning_panel.use_pointer_only()
	inset.add_child(tuning_panel)

func _ready() -> void:
	get_viewport().size_changed.connect(_resize)
	_resize()

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)

## Same design-page scaling as the Esc menu (game_menu_page._resize), but held
## against the right edge on wide screens.
func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1920.0, extent.y / 1080.0)
	size = Vector2(1920, 1080)
	scale = Vector2.ONE * ratio
	position = Vector2(extent.x - size.x * ratio, (extent.y - size.y * ratio) * 0.5)

func render(tuning: RefCounted, parts: Node) -> void:
	tuning_panel.render(tuning, parts)

## Drops keyboard focus held by the card, e.g. a number box, when it hides.
func release_card_focus() -> void:
	var owner_control := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner_control != null and card.is_ancestor_of(owner_control):
		owner_control.release_focus()
