extends Control
## Practice Duel HUD target panel (#97): while the F1 world panel shows,
## the NPC clicked on gets this card to its left, a
## one-column cut of the F2 tuning card for that NPC: remove it, its behaviour,
## its hitboxes, its health, armour and weapon and drive durability, and its
## chassis, drive and weapons.
## Presentation only: the controls call the offline authority through
## MvpSession's practice_* helpers.
const TUNING_OVERLAY = preload("res://scripts/ui/practice_tuning_overlay.gd")
const WORLD_OVERLAY = preload("res://scripts/ui/practice_world_overlay.gd")
## Gap to the world card, whose width it shares.
const CARD_GAP := 16
const HEADING_FONT := 24
## The same size as the dropdown rows (ROW_FONT).
const BUTTON_FONT := 18
const ROW_FONT := 18
## Width of the captions left of the dropdowns.
const CAPTION_WIDTH := 92
## Health, armour on every face, weapon and drive durability: what each -/+
## button takes or gives.
const STEP := 100.0
const DRIVE_ZONES := ["drive_left", "drive_right"]
## Possess is green, Remove red.
const POSSESS_COLOR := Color("2e8b45")
const REMOVE_COLOR := Color("b23a32")
## Picker slot -> caption, in panel order.
const PICKERS := [["chassis", "Chassis"], ["drive", "Drive"], ["weapon", "Weapon 1"], ["utility", "Weapon 2"]]
var card: PanelContainer
## Moves the card when its background is dragged (#97).
var drag: RefCounted
var title: Label
var possess_button: Button
var remove_button: Button
var aggressive_toggle: CheckButton
## Draws this NPC's hitboxes alone (menu_game passes it to the preview).
var hitbox_toggle: CheckButton
## Emitted when the switch changes; menu_game keeps the set of singled-out
## NPCs, whose hitboxes stay on after the panels close.
signal hitboxes_toggled(entity: int, on: bool)
## Possess pressed: menu_game hands the player this NPC.
signal possess_requested(entity: int)
var health_down: Button
var health_up: Button
var armour_down: Button
var armour_up: Button
var weapon_down: Button
var weapon_up: Button
var drive_down: Button
var drive_up: Button
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
	_label(column, "TARGET", &"HeadingWide", HEADING_FONT)
	title = _label(column, "", &"Body", ROW_FONT)
	title.name = "TargetName"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 1.0
	column.add_child(HSeparator.new())
	possess_button = _button(column, "PossessTarget", "Possess", func() -> void: possess_requested.emit(target))
	remove_button = _button(column, "RemoveTarget", "Remove", func() -> void:
		if session != null: session.practice_remove_npc(target))
	aggressive_toggle = _switch(column, "TargetAggressive", func(on: bool) -> void:
		if session != null: session.practice_set_npc_aggressive(target, on)
		WORLD_OVERLAY.caption_behaviour(aggressive_toggle))
	WORLD_OVERLAY.caption_behaviour(aggressive_toggle)
	hitbox_toggle = _switch(column, "TargetHitboxes", func(on: bool) -> void: hitboxes_toggled.emit(target, on))
	hitbox_toggle.text = "Hitbox"
	# Health, armour, weapon and drive, each taken or given STEP at a time.
	column.add_child(HSeparator.new())
	_label(column, "+/- %d Durability" % STEP, &"Body", ROW_FONT)
	var body_row := _row(column)
	health_down = _button(body_row, "TargetHealthDown", "-HP", func() -> void:
		if session != null: session.practice_add_npc_health(target, -STEP))
	health_up = _button(body_row, "TargetHealthUp", "+HP", func() -> void:
		if session != null: session.practice_add_npc_health(target, STEP))
	armour_down = _button(body_row, "TargetArmourDown", "-A", func() -> void:
		if session != null: session.practice_add_npc_armour(target, -STEP))
	armour_up = _button(body_row, "TargetArmourUp", "+A", func() -> void:
		if session != null: session.practice_add_npc_armour(target, STEP))
	var parts_row := _row(column)
	weapon_down = _button(parts_row, "TargetWeaponDown", "-W", func() -> void:
		if session != null: session.practice_add_npc_durability(target, ["weapon"], -STEP))
	weapon_up = _button(parts_row, "TargetWeaponUp", "+W", func() -> void:
		if session != null: session.practice_add_npc_durability(target, ["weapon"], STEP))
	drive_down = _button(parts_row, "TargetDriveDown", "-D", func() -> void:
		if session != null: session.practice_add_npc_durability(target, DRIVE_ZONES, -STEP))
	drive_up = _button(parts_row, "TargetDriveUp", "+D", func() -> void:
		if session != null: session.practice_add_npc_durability(target, DRIVE_ZONES, STEP))
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

## Buttons sharing a row equally.
func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row

## Mouse-only, like the tuning card (#94): Space must not press them again.
func _button(parent: Control, id: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Held to the card's width: long captions clip instead of widening it.
	button.clip_text = true
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _switch(parent: Control, id: String, changed: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = id
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", BUTTON_FONT)
	if changed.is_valid():
		toggle.toggled.connect(changed)
	parent.add_child(toggle)
	return toggle

func _ready() -> void:
	WORLD_OVERLAY.tint(possess_button, POSSESS_COLOR)
	WORLD_OVERLAY.tint(remove_button, REMOVE_COLOR)
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

## Shows the NPC entity; menu_game hides the card when there is none.
## hitboxes: whether this NPC's hitboxes show.
func render(source: Node, entity: int, hitboxes := false) -> void:
	session = source
	target = entity
	var bot: MvpBot = source.practice_npc(entity) if source != null else null
	if bot == null:
		return
	var parts: Dictionary = bot.loadout.parts
	title.text = "Name: %s  #%d" % [_part_name(str(parts.get("chassis", ""))), entity]
	aggressive_toggle.set_pressed_no_signal(source.practice_npc_aggressive(entity))
	WORLD_OVERLAY.caption_behaviour(aggressive_toggle)
	var wrecked := bot.combat.eliminated
	hitbox_toggle.set_pressed_no_signal(hitboxes)
	for control: BaseButton in [possess_button, aggressive_toggle, health_down, health_up, armour_down, armour_up,
			weapon_down, weapon_up, drive_down, drive_up]:
		control.disabled = wrecked
	# The Woodland giant cannot be possessed (#99).
	possess_button.disabled = wrecked or not source.practice_can_possess(entity)
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
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_picker_column.add_child(row)
		var caption := _label(row, pair[1], &"Body", ROW_FONT)
		caption.custom_minimum_size.x = CAPTION_WIDTH
		var picker := OptionButton.new()
		picker.name = "TargetPicker_" + slot
		picker.focus_mode = Control.FOCUS_NONE
		picker.fit_to_longest_item = false
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.clip_text = true
		picker.add_theme_font_size_override("font_size", ROW_FONT)
		row.add_child(picker)
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
