extends Control
## Practice Duel HUD world panel (#97): F1 shows it over the arena while
## the player keeps driving, a narrow card against the right edge at the F2
## tuning card's top (practice_tuning_overlay.gd); menu_game shows one of the
## two at a time. Presentation only: the controls call the offline authority
## through MvpSession's practice_* helpers. Only the card takes the mouse.
const TUNING_OVERLAY = preload("res://scripts/ui/practice_tuning_overlay.gd")
## Card width on the 1920x1080 design page, and its inner margin.
const CARD_WIDTH := 300
const CARD_INSET := 24
const HEADING_FONT := 24
## As the target card's rows.
const BUTTON_FONT := 18
const STATUS_FONT := 18
## Behaviour switch captions: red while aggressive, green while friendly.
const AGGRESSIVE_COLOR := Color("ff5a4f")
const FRIENDLY_COLOR := Color("62d26f")
## The Player options button, green like the target card's Possess.
const PLAYER_OPTIONS_COLOR := Color("2e8b45")
## Respawn time boxes (#113), here and on the target card: their size, the
## longest wait they take (s) and the steps of a typed value and of the arrows.
const RESPAWN_SPIN_SIZE := Vector2(96, 30)
const RESPAWN_MAX := 3600.0
const RESPAWN_STEP := 0.1
const RESPAWN_ARROW_STEP := 1.0
const CAPTION_COLORS := [&"font_color", &"font_hover_color", &"font_pressed_color",
	&"font_hover_pressed_color", &"font_focus_color", &"font_disabled_color"]
## Asks menu_game for the camera ray to spawn along.
signal spawn_requested
## Asks menu_game for the camera ray to place an item pickup along (#105).
signal item_spawn_requested
## Player options pressed: menu_game opens the F2 tuning panel.
signal player_options_requested
## The Hitboxes switch changed: it overrides every NPC's own (#97).
signal hitboxes_toggled(on: bool)
var card: PanelContainer
## Moves the card when its background is dragged (#97).
var drag: RefCounted
var clear_button: Button
var player_options_button: Button
var spawn_button: Button
## Item pickups (#105): spawn one where the camera looks, or clear them all.
var item_spawn_button: Button
var item_clear_button: Button
var aggressive_toggle: CheckButton
## The other bots' debug hitboxes (#93), moved here from the F2 panel.
var hitbox_toggle: CheckButton
## Seconds a wrecked NPC waits before it returns (#113): the default for every
## NPC the target card has not given its own.
var respawn_spin: SpinBox
var status: Label
## The session (MvpSession) the controls act on; null leaves them inert.
var session: Node

func _init() -> void:
	name = "PracticeWorldOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_right", TUNING_OVERLAY.CARD_RIGHT)
	margin.add_theme_constant_override("margin_top", TUNING_OVERLAY.CARD_TOP)
	margin.add_theme_constant_override("margin_bottom", TUNING_OVERLAY.CARD_BOTTOM)
	card = PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"PanelGlass"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# Only as big as its controls, held against the right edge.
	card.custom_minimum_size.x = CARD_WIDTH
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(card)
	drag = preload("res://scripts/ui/practice_card_drag.gd").new(self, card)
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, CARD_INSET)
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
	player_options_button = _button(column, "PlayerOptions", "Player options", player_options_requested.emit)
	spawn_button = _button(column, "SpawnNpc", "Spawn NPC", spawn_requested.emit)
	clear_button = _button(column, "ClearNpcs", "Clear NPCs", func() -> void:
		if session != null: session.practice_clear_npcs())
	item_spawn_button = _button(column, "SpawnItem", "Spawn item", item_spawn_requested.emit)
	item_clear_button = _button(column, "ClearItems", "Clear items", func() -> void:
		if session != null: session.practice_clear_pickups())
	aggressive_toggle = CheckButton.new()
	aggressive_toggle.name = "Aggressive"
	aggressive_toggle.focus_mode = Control.FOCUS_NONE
	aggressive_toggle.add_theme_font_size_override("font_size", BUTTON_FONT)
	aggressive_toggle.toggled.connect(func(on: bool) -> void:
		if session != null: session.practice_set_npcs_aggressive(on)
		caption_behaviour(aggressive_toggle))
	column.add_child(aggressive_toggle)
	caption_behaviour(aggressive_toggle)
	hitbox_toggle = CheckButton.new()
	hitbox_toggle.name = "HitboxToggle"
	hitbox_toggle.text = "Hitboxes"
	hitbox_toggle.focus_mode = Control.FOCUS_NONE
	hitbox_toggle.add_theme_font_size_override("font_size", BUTTON_FONT)
	hitbox_toggle.toggled.connect(func(on: bool) -> void:
		var tuning: RefCounted = session.practice_tuning() if session != null else null
		if tuning != null: tuning.debug_hitboxes = on
		hitboxes_toggled.emit(on))
	column.add_child(hitbox_toggle)
	var respawn_row := HBoxContainer.new()
	respawn_row.add_theme_constant_override("separation", 8)
	column.add_child(respawn_row)
	respawn_caption(respawn_row, "NPC respawn (s)")
	respawn_spin = respawn_box("NpcRespawn", func(seconds: float) -> void:
		if session != null: session.practice_set_npc_respawn(seconds))
	respawn_row.add_child(respawn_spin)
	visibility_changed.connect(func() -> void:
		if not visible: respawn_spin.get_line_edit().release_focus())

## A behaviour switch names the current behaviour, in red or green; the
## target card's switch (#97) uses it too.
static func caption_behaviour(toggle: CheckButton) -> void:
	var aggressive := toggle.button_pressed
	toggle.text = "Aggressive" if aggressive else "Friendly"
	for key: StringName in CAPTION_COLORS:
		toggle.add_theme_color_override(key, AGGRESSIVE_COLOR if aggressive else FRIENDLY_COLOR)

## Fills a button's backgrounds with color, lighter when hovered and darker
## when pressed; the theme's other styling is kept. The target card uses it too.
static func tint(button: Button, color: Color) -> void:
	for state: Array in [["normal", color], ["hover", color.lightened(0.15)], ["pressed", color.darkened(0.2)],
			["disabled", color.darkened(0.5)]]:
		var box := button.get_theme_stylebox(state[0])
		var filled: StyleBoxFlat = box.duplicate() if box is StyleBoxFlat else StyleBoxFlat.new()
		filled.bg_color = state[1]
		button.add_theme_stylebox_override(state[0], filled)

## The caption left of a respawn time box; it gives way to the box on a
## narrow card.
static func respawn_caption(row: Control, text: String) -> Label:
	var caption := Label.new()
	caption.text = text
	caption.theme_type_variation = &"Body"
	caption.add_theme_font_size_override("font_size", BUTTON_FONT)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.clip_text = true
	row.add_child(caption)
	return caption

## A respawn time box (#113). Like the tuning card's boxes (#94) it applies a
## number as it is typed and lets go of the keyboard once it is submitted, so
## the bot drives on.
static func respawn_box(id: String, changed: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = id
	spin.max_value = RESPAWN_MAX
	spin.step = RESPAWN_STEP
	spin.custom_arrow_step = RESPAWN_ARROW_STEP
	spin.select_all_on_focus = true
	spin.custom_minimum_size = RESPAWN_SPIN_SIZE
	var line := spin.get_line_edit()
	line.add_theme_font_size_override("font_size", BUTTON_FONT)
	spin.value_changed.connect(changed)
	line.text_changed.connect(func(text: String) -> void:
		var typed := text.strip_edges()
		if typed.is_valid_float():
			changed.call(clampf(typed.to_float(), spin.min_value, spin.max_value)))
	line.text_submitted.connect(func(_text: String) -> void: line.release_focus())
	return spin

## Shows seconds in a respawn time box, unless it is being typed in.
static func show_respawn(spin: SpinBox, seconds: float) -> void:
	if not spin.get_line_edit().has_focus():
		spin.set_value_no_signal(seconds)

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
	tint(player_options_button, PLAYER_OPTIONS_COLOR)
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

func render(source: Node) -> void:
	session = source
	var count := 0
	if source != null and source.practice_director != null:
		count = source.practice_director.records.size() + source.practice_director.roamers.size()
	var items: int = source.world.pickups.items.size() if source != null and source.practice_tuning() != null else 0
	status.text = "%d NPC%s, %d item%s" % [count, "" if count == 1 else "s", items, "" if items == 1 else "s"]
	aggressive_toggle.set_pressed_no_signal(source != null and source.practice_npcs_aggressive())
	caption_behaviour(aggressive_toggle)
	var tuning: RefCounted = source.practice_tuning() if source != null else null
	hitbox_toggle.set_pressed_no_signal(tuning != null and tuning.debug_hitboxes)
	if tuning != null:
		show_respawn(respawn_spin, source.practice_npc_respawn())
