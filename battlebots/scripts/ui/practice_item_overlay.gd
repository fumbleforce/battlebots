extends Control
## Practice HUD item card (#105): while the F1 world panel shows, the item
## pickup clicked on gets this card in the target card's place, left of the
## world card: what the item is, from a dropdown, and a red Remove.
## Presentation only: the controls call the offline authority through
## MvpSession's practice_* helpers.
const TUNING_OVERLAY = preload("res://scripts/ui/practice_tuning_overlay.gd")
const WORLD_OVERLAY = preload("res://scripts/ui/practice_world_overlay.gd")
const TARGET_OVERLAY = preload("res://scripts/ui/practice_target_overlay.gd")
## The dropdown list's text size and row spacing.
const LIST_FONT := 13
const LIST_SPACING := 2
var card: PanelContainer
## Moves the card when its background is dragged.
var drag: RefCounted
var title: Label
var picker: OptionButton
var remove_button: Button
## The session (MvpSession) the controls act on, and the item's id.
var session: Node
var item_id := -1
## The dropdown's choices ({kind, part, amount}), in item order.
var _choices: Array[Dictionary] = []
var _names: Dictionary = {}

func _init() -> void:
	name = "PracticeItemOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_right", TUNING_OVERLAY.CARD_RIGHT + WORLD_OVERLAY.CARD_WIDTH + TARGET_OVERLAY.CARD_GAP)
	margin.add_theme_constant_override("margin_top", TUNING_OVERLAY.CARD_TOP)
	margin.add_theme_constant_override("margin_bottom", TUNING_OVERLAY.CARD_BOTTOM)
	card = PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"PanelGlass"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size.x = WORLD_OVERLAY.CARD_WIDTH
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(card)
	drag = preload("res://scripts/ui/practice_card_drag.gd").new(self, card)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, WORLD_OVERLAY.CARD_INSET)
	card.add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inset.add_child(column)
	_label(column, "ITEM", &"HeadingWide", TARGET_OVERLAY.HEADING_FONT)
	title = _label(column, "", &"Body", TARGET_OVERLAY.ROW_FONT)
	title.name = "ItemName"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 1.0
	column.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_label(row, "Item", &"Body", TARGET_OVERLAY.ROW_FONT).custom_minimum_size.x = TARGET_OVERLAY.CAPTION_WIDTH
	picker = OptionButton.new()
	picker.name = "ItemPicker"
	picker.focus_mode = Control.FOCUS_NONE
	picker.fit_to_longest_item = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.clip_text = true
	picker.add_theme_font_size_override("font_size", TARGET_OVERLAY.ROW_FONT)
	# The list holds every item: small, tight rows keep it on screen.
	picker.get_popup().add_theme_font_size_override("font_size", LIST_FONT)
	picker.get_popup().add_theme_constant_override("v_separation", LIST_SPACING)
	picker.item_selected.connect(func(index: int) -> void:
		if session != null and index >= 0 and index < _choices.size():
			session.practice_set_pickup(item_id, _choices[index]))
	row.add_child(picker)
	remove_button = Button.new()
	remove_button.name = "RemoveItem"
	remove_button.text = "Remove"
	# Mouse-only, like the other practice cards: Space must not press it again.
	remove_button.focus_mode = Control.FOCUS_NONE
	remove_button.add_theme_font_size_override("font_size", TARGET_OVERLAY.BUTTON_FONT)
	remove_button.pressed.connect(func() -> void:
		if session != null: session.practice_remove_pickup(item_id))
	column.add_child(remove_button)

func _label(parent: Node, text: String, variation: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _ready() -> void:
	WORLD_OVERLAY.tint(remove_button, TARGET_OVERLAY.REMOVE_COLOR)
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
	drag.place(Vector2(extent.x - size.x * ratio, (extent.y - size.y * ratio) * 0.5))

## Shows the item pickup id; menu_game hides the card when there is none.
func render(source: Node, id: int) -> void:
	session = source
	item_id = id
	var item: Dictionary = source.practice_pickup(id) if source != null else {}
	if item.is_empty():
		return
	if _choices.is_empty():
		_fill_picker()
	title.text = "%s  #%d" % [describe(item), id]
	var current := _choices.find({"kind":item.kind, "part":item.part, "amount":item.amount})
	# Only on a change, so an open list stays open.
	if picker.selected != current:
		picker.select(current)

func _fill_picker() -> void:
	_choices = session.practice_pickup_choices()
	_names = PickupFeed.names_from(session.registry)
	picker.clear()
	for choice: Dictionary in _choices:
		picker.add_item(describe(choice))

## The dropdown's name for an item's contents.
func describe(choice: Dictionary) -> String:
	match str(choice.get("kind", "")):
		"coolant":
			return "Coolant"
		"credits":
			return "%d credits" % int(choice.get("amount", 0))
		"perk":
			return "%s (perk)" % _part_name(str(choice.get("part", "")))
	return _part_name(str(choice.get("part", "")))

func _part_name(part: String) -> String:
	return str(_names.get(part, part.replace("_", " ").capitalize()))
