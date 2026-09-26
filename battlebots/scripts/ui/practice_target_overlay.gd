extends Control
## Practice Duel HUD target panel (#97): while the Shift+Z world panel shows,
## the NPC the player last looked at gets this card to its left, a one-column
## cut of the Z tuning card for that NPC: remove it, its behaviour, its health,
## more armour, and its chassis, drive and weapons. Presentation only: the
## controls call the offline authority through MvpSession's practice_* helpers.
const TUNING_OVERLAY = preload("res://scripts/ui/practice_tuning_overlay.gd")
const WORLD_OVERLAY = preload("res://scripts/ui/practice_world_overlay.gd")
## Card width on the 1920x1080 design page and its gap to the world card.
const CARD_WIDTH := 340
const CARD_GAP := 16
const HEADING_FONT := 24
const BUTTON_FONT := 20
const ROW_FONT := 18
const HINT_FONT := 15
## Armour the "+ armour" button adds to every face.
const ARMOUR_STEP := 100.0
const HEALTH_MAX := 100000.0
const SPIN_SIZE := Vector2(120, 30)
## Picker slot -> caption, in panel order.
const PICKERS := [["chassis", "Chassis"], ["drive", "Drive"], ["weapon", "Weapon 1"], ["utility", "Weapon 2"]]
var card: PanelContainer
var title: Label
var remove_button: Button
var aggressive_toggle: CheckButton
var health_spin: SpinBox
var armour_button: Button
## Slot -> OptionButton.
var pickers: Dictionary = {}
var _picker_column: VBoxContainer
## The session (MvpSession) the controls act on, and the NPC's entity id.
var session: Node
var target := 0
var _layout := ""
## Part names as Customize shows them (MenuData), read once.
var _names: Dictionary = {}

func _init() -> void:
	name = "PracticeTargetOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_right", TUNING_OVERLAY.CARD_RIGHT + WORLD_OVERLAY.CARD_WIDTH + CARD_GAP)
	margin.add_theme_constant_override("margin_top", TUNING_OVERLAY.CARD_TOP)
	margin.add_theme_constant_override("margin_bottom", TUNING_OVERLAY.CARD_BOTTOM)
	card = PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"PanelGlass"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size.x = CARD_WIDTH
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(card)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, WORLD_OVERLAY.CARD_INSET)
	card.add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inset.add_child(column)
	_label(column, "TARGET", &"HeadingWide", HEADING_FONT)
	title = _label(column, "", &"Body", ROW_FONT)
	title.name = "TargetName"
	column.add_child(HSeparator.new())
	remove_button = _button(column, "RemoveTarget", "Remove", func() -> void:
		if session != null: session.practice_remove_npc(target))
	aggressive_toggle = CheckButton.new()
	aggressive_toggle.name = "TargetAggressive"
	aggressive_toggle.focus_mode = Control.FOCUS_NONE
	aggressive_toggle.add_theme_font_size_override("font_size", BUTTON_FONT)
	aggressive_toggle.toggled.connect(func(on: bool) -> void:
		if session != null: session.practice_set_npc_aggressive(target, on)
		_caption())
	column.add_child(aggressive_toggle)
	_caption()
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 12)
	column.add_child(health_row)
	var health_label := _label(health_row, "Health", &"Body", ROW_FONT)
	health_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_spin = SpinBox.new()
	health_spin.name = "TargetHealth"
	health_spin.min_value = 1.0
	health_spin.max_value = HEALTH_MAX
	health_spin.step = 1.0
	health_spin.custom_arrow_step = 10.0
	health_spin.select_all_on_focus = true
	health_spin.custom_minimum_size = SPIN_SIZE
	health_spin.get_line_edit().add_theme_font_size_override("font_size", ROW_FONT)
	# Applied on Enter or leaving the box, not per keystroke: each change refills.
	health_spin.value_changed.connect(func(amount: float) -> void:
		if session != null: session.practice_set_npc_health(target, amount))
	health_spin.get_line_edit().text_submitted.connect(func(_text: String) -> void:
		health_spin.get_line_edit().release_focus())
	health_row.add_child(health_spin)
	armour_button = _button(column, "TargetArmour", "+%d armour" % ARMOUR_STEP, func() -> void:
		if session != null: session.practice_add_npc_armour(target, ARMOUR_STEP))
	column.add_child(HSeparator.new())
	_picker_column = VBoxContainer.new()
	_picker_column.add_theme_constant_override("separation", 6)
	column.add_child(_picker_column)

func _label(parent: Node, text: String, variation: StringName, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

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

## The switch names the NPC's current behaviour.
func _caption() -> void:
	aggressive_toggle.text = "Aggressive" if aggressive_toggle.button_pressed else "Friendly"

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

## Shows the NPC entity; menu_game hides the card when there is none.
func render(source: Node, entity: int) -> void:
	session = source
	target = entity
	var bot: MvpBot = source.practice_npc(entity) if source != null else null
	if bot == null:
		return
	var parts: Dictionary = bot.loadout.parts
	title.text = "%s  #%d" % [_part_name(str(parts.get("chassis", ""))), entity]
	aggressive_toggle.set_pressed_no_signal(source.practice_npc_aggressive(entity))
	_caption()
	var wrecked := bot.combat.eliminated
	for control: BaseButton in [aggressive_toggle, armour_button]:
		control.disabled = wrecked
	health_spin.editable = not wrecked
	if not health_spin.get_line_edit().has_focus():
		health_spin.set_value_no_signal(roundf(bot.combat.core))
	# Rebuilt only when the target or its parts change, so an open list stays open.
	var layout := "%d;%s" % [entity, ",".join(PICKERS.map(func(pair: Array) -> String: return str(parts.get(pair[0], ""))))]
	if layout != _layout:
		_layout = layout
		_rebuild_pickers()
	for slot: String in pickers:
		pickers[slot].disabled = wrecked or pickers[slot].has_meta(&"empty")

func _rebuild_pickers() -> void:
	for child: Node in _picker_column.get_children():
		_picker_column.remove_child(child)
		child.queue_free()
	pickers.clear()
	for pair: Array in PICKERS:
		var slot: String = pair[0]
		_label(_picker_column, pair[1], &"Muted", HINT_FONT)
		var picker := OptionButton.new()
		picker.name = "TargetPicker_" + slot
		picker.focus_mode = Control.FOCUS_NONE
		picker.fit_to_longest_item = false
		picker.add_theme_font_size_override("font_size", ROW_FONT)
		_picker_column.add_child(picker)
		var options: Array = session.practice_part_options(slot, target)
		for option: Dictionary in options:
			picker.add_item(_part_name(option.part))
			var index := picker.item_count - 1
			picker.set_item_metadata(index, option.part)
			picker.set_item_disabled(index, not option.fits)
			picker.set_item_tooltip(index, "" if option.fits else "Does not fit this build")
			if option.current:
				picker.select(index)
		if options.is_empty():
			picker.add_item("—")
			picker.set_meta(&"empty", true)
		picker.item_selected.connect(func(index: int) -> void:
			if session != null: session.practice_set_part(slot, str(picker.get_item_metadata(index)), target))
		pickers[slot] = picker

func _part_name(part: String) -> String:
	if _names.is_empty() and session != null:
		for category: Dictionary in MenuData.catalogue(session.registry).parts:
			for item: Dictionary in category.items:
				_names[item.id] = item.name
	return str(_names.get(part, part.replace("_", " ").capitalize()))
