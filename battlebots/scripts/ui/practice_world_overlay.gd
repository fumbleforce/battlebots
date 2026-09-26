extends Control
## Practice Duel HUD world panel (#97): Shift+Z shows it over the arena while
## the player keeps driving, in the same place as the Z tuning card
## (practice_tuning_overlay.gd); menu_game shows one of the two at a time.
## Presentation only: the buttons call the offline authority through
## MvpSession's practice_* helpers. Only the card takes the mouse.
const TUNING_OVERLAY = preload("res://scripts/ui/practice_tuning_overlay.gd")
const HEADING_FONT := 24
const BUTTON_FONT := 20
const STATUS_FONT := 18
## Asks menu_game for the camera ray to spawn along.
signal spawn_requested
var card: PanelContainer
var clear_button: Button
var spawn_button: Button
var aggressive_button: Button
var passive_button: Button
var status: Label
## The session (MvpSession) the buttons act on; null leaves them inert.
var session: Node

func _init() -> void:
	name = "PracticeWorldOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", TUNING_OVERLAY.CARD_LEFT)
	margin.add_theme_constant_override("margin_right", TUNING_OVERLAY.CARD_RIGHT)
	margin.add_theme_constant_override("margin_top", TUNING_OVERLAY.CARD_TOP)
	margin.add_theme_constant_override("margin_bottom", TUNING_OVERLAY.CARD_BOTTOM)
	card = PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"PanelGlass"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# Only as tall as its buttons, not the tuning card's full height.
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(card)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, TUNING_OVERLAY.CARD_INSET)
	card.add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inset.add_child(column)
	var title := Label.new()
	title.text = "WORLD"
	title.theme_type_variation = &"HeadingWide"
	title.add_theme_font_size_override("font_size", HEADING_FONT)
	column.add_child(title)
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"Body"
	status.add_theme_font_size_override("font_size", STATUS_FONT)
	column.add_child(status)
	column.add_child(HSeparator.new())
	clear_button = _button(column, "ClearNpcs", "Clear all NPCs", func() -> void:
		if session != null: session.practice_clear_npcs())
	spawn_button = _button(column, "SpawnNpc", "Spawn NPC where I look", spawn_requested.emit)
	aggressive_button = _button(column, "NpcsAggressive", "Make NPCs aggressive", func() -> void:
		if session != null: session.practice_set_npcs_aggressive(true))
	passive_button = _button(column, "NpcsPassive", "Make NPCs not aggressive", func() -> void:
		if session != null: session.practice_set_npcs_aggressive(false))

## Mouse-only, like the tuning card (#94): Space must not press them again.
func _button(parent: Control, id: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _ready() -> void:
	get_viewport().size_changed.connect(_resize)
	_resize()

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)

## Same design-page scaling and right-edge anchoring as the tuning card.
func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1920.0, extent.y / 1080.0)
	size = Vector2(1920, 1080)
	scale = Vector2.ONE * ratio
	position = Vector2(extent.x - size.x * ratio, (extent.y - size.y * ratio) * 0.5)

func render(source: Node) -> void:
	session = source
	var count: int = source.practice_director.records.size() + source.practice_director.roamers.size() \
		if source != null and source.practice_director != null else 0
	var aggressive: bool = source != null and source.practice_npcs_aggressive()
	status.text = "%d NPC%s · %s" % [count, "" if count == 1 else "s", "aggressive" if aggressive else "not aggressive"]
	aggressive_button.disabled = aggressive
	passive_button.disabled = not aggressive
