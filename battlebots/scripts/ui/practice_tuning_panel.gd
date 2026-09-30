extends VBoxContainer
## Practice Duel Esc-menu tuning (#84): live, session-only values for the
## player's weapons and body (scripts/simulation/practice_tuning.gd), plus
## weapon, chassis and drive (#94) pickers, under the debug views (#93). Nothing here is
## saved; leaving practice discards it. Each category folds away from its title
## (#111). Presentation only: the offline
## authority applies the values on its next tick and swaps parts through
## MvpSession.practice_set_part().
const TUNING = preload("res://scripts/simulation/practice_tuning.gd")
const SPIN_MAX := 100000.0
## Compact rows: text size, editor size and row gap.
const ROW_FONT := 18
const HINT_FONT := 15
const HEADING_FONT := 26
const SPIN_SIZE := Vector2(110, 30)
const ROW_GAP := 2
## The DPS readout (#113).
const DPS_FORMAT := "%.1f"
## The fold arrow right of a category title: its box and the gap to the title.
const ARROW_SIZE := Vector2(12, 8)
const ARROW_GAP := 8
## Armour faces in reading order; unknown faces follow.
const FACE_ORDER := ["front", "back", "left", "right", "top", "bottom"]
var tuning: RefCounted
## The session that swaps parts (MvpSession); null disables the pickers.
var session: Node
var heat_toggle: CheckButton
var jump_toggle: CheckButton
## Debug views (#93).
var trajectory_toggle: CheckButton
var impact_toggle: CheckButton
var player_hitbox_toggle: CheckButton
var linger_spin: SpinBox
## Weapon slot ("primary"/"secondary") -> its "Allow auto fire" toggle.
var auto_toggles: Dictionary = {}
## Weapon slot -> its DPS readout (#113): damage times fire rate as tuned.
var dps_labels: Dictionary = {}
var reset_button: Button
var content: HBoxContainer
## The column the section being built goes into.
var _column: VBoxContainer
var mass_label: Label
## Slot ("weapon"/"utility"/"chassis") -> OptionButton.
var pickers: Dictionary = {}
var _layout := ""
## Category id ("debug", "tuning", "body", "armour", "weapon1", "weapon2") ->
## folded. Shared by the Esc-menu card and the HUD copy (#94), and kept for the
## rest of the run.
static var collapsed: Dictionary = {}
## Category id -> [its title's arrow, the Control holding its rows].
var _sections: Dictionary = {}
## [SpinBox, getter Callable] pairs refreshed while their box is not focused.
var _spins: Array = []
## The HUD copy (#94) is used with the mouse while the bot drives: its buttons
## take no keyboard focus (Space would press them again) and a number box lets
## go of the keyboard once its value is submitted.
var pointer_only := false

func use_pointer_only() -> void:
	pointer_only = true
	_unfocus_buttons(self)

func _unfocus_buttons(node: Node) -> void:
	if not pointer_only:
		return
	if node is BaseButton:
		(node as BaseButton).focus_mode = Control.FOCUS_NONE
	for child: Node in node.get_children():
		_unfocus_buttons(child)

func _init() -> void:
	name = "PracticeTuning"
	add_theme_constant_override("separation", 8)
	_debug_section()
	add_child(HSeparator.new())
	var header := HBoxContainer.new()
	add_child(header)
	var title := _heading(header, "tuning", "TUNING", &"HeadingWide", 24)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(gap)
	reset_button = Button.new()
	reset_button.name = "ResetTuning"
	reset_button.text = "RESET ALL"
	reset_button.theme_type_variation = &"TextLink"
	reset_button.add_theme_font_size_override("font_size", 20)
	reset_button.pressed.connect(func() -> void:
		if tuning != null: tuning.reset())
	header.add_child(reset_button)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	content = HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)
	_sections["tuning"] = [title.get_child(1), scroll]

## Debug views (#93): shot paths, impact areas and the player's own armour
## hitboxes, drawn in the arena by the preview's PracticeDebugDraw, and how
## long each mark stays.
func _debug_section() -> void:
	var rows := _section(self, "debug", "DEBUG", &"HeadingWide", 24)
	rows.add_theme_constant_override("separation", 8)
	# Wraps when the toggles do not fit one line.
	var toggles := HFlowContainer.new()
	toggles.add_theme_constant_override("h_separation", 18)
	rows.add_child(toggles)
	trajectory_toggle = _toggle(toggles, "TrajectoryToggle", "Projectile trajectories",
		func(on: bool) -> void: tuning.debug_trajectories = on)
	impact_toggle = _toggle(toggles, "ImpactToggle", "Impact areas",
		func(on: bool) -> void: tuning.debug_impacts = on)
	# #94: hitboxes on the player's own bot. The other bots' Hitboxes toggle is in
	# the F1 world panel (#97).
	player_hitbox_toggle = _toggle(toggles, "PlayerHitboxToggle", "Hitbox",
		func(on: bool) -> void: tuning.debug_player_hitboxes = on)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	rows.add_child(row)
	_label(row, "Marks linger (s)", &"Body", ROW_FONT)
	linger_spin = SpinBox.new()
	linger_spin.name = "DebugLinger"
	linger_spin.min_value = 1.0
	linger_spin.max_value = SPIN_MAX
	linger_spin.step = 0.1
	linger_spin.custom_arrow_step = 5.0
	linger_spin.select_all_on_focus = true
	linger_spin.custom_minimum_size = SPIN_SIZE
	linger_spin.get_line_edit().add_theme_font_size_override("font_size", ROW_FONT)
	linger_spin.value = TUNING.DEFAULT_DEBUG_LINGER
	var set_linger := func(seconds: float) -> void:
		if tuning != null: tuning.debug_linger = seconds
	linger_spin.value_changed.connect(set_linger)
	_live(linger_spin, set_linger)
	row.add_child(linger_spin)
	var default := Button.new()
	default.text = "DEFAULT"
	default.theme_type_variation = &"TextLink"
	default.add_theme_font_size_override("font_size", HINT_FONT)
	default.pressed.connect(func() -> void:
		if tuning != null: tuning.debug_linger = TUNING.DEFAULT_DEBUG_LINGER
		linger_spin.set_value_no_signal(TUNING.DEFAULT_DEBUG_LINGER))
	row.add_child(default)

func _label(parent: Node, text: String, variation: StringName, font_size: int) -> Label:
	var item := Label.new()
	item.text = text
	item.theme_type_variation = variation
	item.add_theme_font_size_override("font_size", font_size)
	parent.add_child(item)
	return item

## A category title that folds its rows when clicked, with an arrow to its
## right: down while the rows show, up while they are folded. Returns the
## clickable title; its second child is the arrow.
func _heading(parent: Node, id: String, text: String, variation: StringName, font_size: int) -> HBoxContainer:
	var title := HBoxContainer.new()
	title.name = "Heading_" + id
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	title.add_theme_constant_override("separation", ARROW_GAP)
	parent.add_child(title)
	var label := _label(title, text, variation, font_size)
	var arrow := Control.new()
	arrow.name = "Arrow"
	arrow.custom_minimum_size = ARROW_SIZE
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(func() -> void:
		var tip := 0.0 if collapsed.get(id, false) else ARROW_SIZE.y
		arrow.draw_colored_polygon(PackedVector2Array([Vector2(0.0, ARROW_SIZE.y - tip), Vector2(ARROW_SIZE.x, ARROW_SIZE.y - tip),
			Vector2(ARROW_SIZE.x * 0.5, tip)]), label.get_theme_color(&"font_color")))
	title.add_child(arrow)
	title.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			set_collapsed(id, not collapsed.get(id, false)))
	return title

## A category: its folding title, then the container its rows go into.
func _section(parent: Node, id: String, text: String, variation: StringName, font_size: int) -> VBoxContainer:
	var title := _heading(parent, id, text, variation, font_size)
	var rows := VBoxContainer.new()
	rows.name = "Section_" + id
	rows.add_theme_constant_override("separation", 6)
	parent.add_child(rows)
	_sections[id] = [title.get_child(1), rows]
	return rows

## The container holding a category's rows.
func section(id: String) -> Control:
	return _sections[id][1]

## Folds or unfolds a category, here and in the other copy of the panel.
func set_collapsed(id: String, folded: bool) -> void:
	collapsed[id] = folded
	_fold_sections()

func _fold_sections() -> void:
	for id: String in _sections:
		var rows: Control = _sections[id][1]
		var folded: bool = collapsed.get(id, false)
		if rows.visible == folded:
			rows.visible = not folded
			(_sections[id][0] as Control).queue_redraw()

## Called every frame while the menu shows; rebuilds only when the fitted
## parts change, otherwise refreshes the displayed values.
func render(value: RefCounted, parts: Node = null) -> void:
	tuning = value
	session = parts
	if tuning == null:
		return
	var layout := _signature()
	if layout != _layout:
		_layout = layout
		_rebuild()
	# The other copy of the panel may have folded a category.
	_fold_sections()
	heat_toggle.set_pressed_no_signal(tuning.heat_enabled)
	jump_toggle.set_pressed_no_signal(tuning.jump_cooldown_enabled)
	trajectory_toggle.set_pressed_no_signal(tuning.debug_trajectories)
	impact_toggle.set_pressed_no_signal(tuning.debug_impacts)
	player_hitbox_toggle.set_pressed_no_signal(tuning.debug_player_hitboxes)
	if not linger_spin.get_line_edit().has_focus():
		linger_spin.set_value_no_signal(tuning.debug_linger)
	for slot: String in auto_toggles:
		auto_toggles[slot].set_pressed_no_signal(tuning.auto_fire.get(slot, false))
	for slot: String in dps_labels:
		dps_labels[slot].text = DPS_FORMAT % tuning.dps(slot)
	for pair: Array in _spins:
		var spin: SpinBox = pair[0]
		if not spin.get_line_edit().has_focus():
			spin.set_value_no_signal(pair[1].call())
	mass_label.text = "Total mass %.0f kg" % tuning.total_mass()

func _signature() -> String:
	var parts: Array[String] = [tuning.chassis(), tuning.drive(), tuning.utility()]
	for slot: String in tuning.weapons:
		parts.append("%s=%s" % [slot, tuning.weapons[slot].id])
	parts.append(",".join(tuning.body_defaults.get("plates", {}).keys()))
	return ";".join(parts)

func _rebuild() -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_spins.clear()
	pickers.clear()
	auto_toggles.clear()
	dps_labels.clear()
	# Body on the left, weapon on the right; one scroll moves both.
	var body_column := _new_column()
	content.add_child(VSeparator.new())
	var weapon_column := _new_column()
	_column = _section(weapon_column, "weapon1", "WEAPON 1", &"HeadingItalic", HEADING_FONT)
	_auto_toggle("primary")
	_picker("weapon")
	if tuning.weapons.has("primary"):
		_weapon_rows("primary")
	# Weapon 2 is the Customize "Auxiliary / Utility" slot: mostly turrets and
	# the auxiliary minigun, whose values tune here like Weapon 1's.
	weapon_column.add_child(HSeparator.new())
	_column = _section(weapon_column, "weapon2", "WEAPON 2", &"HeadingItalic", HEADING_FONT)
	_auto_toggle("secondary")
	_picker("utility")
	if tuning.weapons.has("secondary"):
		_weapon_rows("secondary")
	else:
		_label(_column, "This utility is not a weapon: nothing to tune.", &"Muted", HINT_FONT)
	_column = _section(body_column, "body", "BODY", &"HeadingItalic", HEADING_FONT)
	_picker("chassis")
	_picker("drive")
	heat_toggle = _toggle(_column, "HeatToggle", "Heat", func(on: bool) -> void: tuning.heat_enabled = on)
	jump_toggle = _toggle(_column, "JumpCooldownToggle", "Jump cooldown", func(on: bool) -> void: tuning.jump_cooldown_enabled = on)
	# Max speed reads in km/h like the HUD speedometer; the tuning keeps m/s.
	_body_rows([["speed", "Max speed", "km/h", preload("res://scripts/ui/hud_speed_gauge.gd").KMH_PER_MPS], ["acceleration", "Acceleration", "m/s²"], ["grip", "Grip", "m/s²"],
		["turn", "Turn speed", "rad/s"], ["jump", "Jump force", "m/s"], ["nitro", "Nitro boost", "×"],
		["core", "Health", ""], ["weight", "Weight", "kg"]])
	mass_label = _label(_column, "", &"Muted", HINT_FONT)
	_column = _section(_column, "armour", "ARMOUR", &"Eyebrow", HINT_FONT)
	var armour := _grid()
	var faces: Array = tuning.body_defaults.get("plates", {}).keys()
	faces.sort_custom(func(a: String, b: String) -> bool:
		var ia := FACE_ORDER.find(a)
		var ib := FACE_ORDER.find(b)
		return (ia if ia >= 0 else 99) < (ib if ib >= 0 else 99))
	for face: String in faces:
		var spin := _spin(func() -> float: return tuning.body_value("plates", face),
			func(amount: float) -> void: tuning.set_body("plates", amount, face), SPIN_MAX)
		_row(armour, face.capitalize(), spin, func() -> void: tuning.clear_body("plates", face), "")
	_fold_sections()
	_unfocus_buttons(content)

## Body values: [key, label, unit, optional display scale] rows editing tuning.body.
func _body_rows(fields: Array) -> void:
	var grid := _grid()
	for field: Array in fields:
		var key: String = field[0]
		var scale: float = field[3] if field.size() > 3 else 1.0
		var spin := _spin(func() -> float: return tuning.body_value(key) * scale,
			func(amount: float) -> void: tuning.set_body(key, amount / scale), SPIN_MAX, 0.01)
		_row(grid, field[1], spin, func() -> void: tuning.clear_body(key), field[2])

func _weapon_rows(slot: String) -> void:
	var grid := _grid()
	for field: Array in TUNING.WEAPON_FIELDS:
		var key: String = field[0]
		# No value is hidden (#111): one this weapon does not have shows a dash.
		if not tuning.editable(slot, key):
			_row(grid, field[1], null, Callable(), field[2])
		else:
			var spin := _spin(func() -> float: return tuning.value(slot, key),
				func(amount: float) -> void: tuning.set_value(slot, key, amount), 100.0 if key in ["pierce", "stagger"] else SPIN_MAX)
			_row(grid, field[1], spin, func() -> void: tuning.clear_value(slot, key), field[2])
		if key == "damage":
			# DPS under Damage, then a line (#113); the other values follow in a
			# grid of their own, as a line cannot span a grid's columns.
			_label(grid, "DPS", &"Body", ROW_FONT)
			dps_labels[slot] = _label(grid, "", &"Body", ROW_FONT)
			dps_labels[slot].name = "Dps_" + slot
			grid.add_child(Control.new())
			_column.add_child(HSeparator.new())
			grid = _grid()

## Dropdown of every part for the slot (unfit ones greyed) between previous
## and next buttons that step to the nearest part that fits.
func _picker(slot: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_column.add_child(row)
	var back := _step_button(row, "‹", slot, -1)
	back.name = "Previous_" + slot
	var picker := OptionButton.new()
	picker.name = "Picker_" + slot
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_theme_font_size_override("font_size", ROW_FONT)
	picker.fit_to_longest_item = false
	row.add_child(picker)
	var options: Array = session.practice_part_options(slot) if session != null else []
	for option: Dictionary in options:
		picker.add_item(_part_name(option.part))
		picker.set_item_tooltip(picker.item_count - 1, "" if option.fits else "Does not fit this build")
		var index := picker.item_count - 1
		picker.set_item_metadata(index, option.part)
		picker.set_item_disabled(index, not option.fits)
		if option.current:
			picker.select(index)
	if options.is_empty():
		picker.add_item("—")
		picker.disabled = true
	picker.item_selected.connect(func(index: int) -> void:
		if session != null: session.practice_set_part(slot, str(picker.get_item_metadata(index))))
	pickers[slot] = picker
	var forward := _step_button(row, "›", slot, 1)
	forward.name = "Next_" + slot
	back.disabled = options.is_empty()
	forward.disabled = options.is_empty()

func _step_button(row: HBoxContainer, text: String, slot: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(40, 0)
	button.add_theme_font_size_override("font_size", ROW_FONT + 4)
	button.pressed.connect(func() -> void:
		if session != null: session.practice_step_part(slot, step))
	row.add_child(button)
	return button

## Part names as Customize shows them (MenuData), read once.
var _names: Dictionary = {}

func _part_name(part: String) -> String:
	if _names.is_empty() and session != null:
		for category: Dictionary in MenuData.catalogue(session.registry).parts:
			for item: Dictionary in category.items:
				_names[item.id] = item.name
	return str(_names.get(part, part.replace("_", " ").capitalize()))

func _toggle(parent: Node, id: String, text: String, changed: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = id
	toggle.text = text
	toggle.add_theme_font_size_override("font_size", ROW_FONT)
	toggle.toggled.connect(func(on: bool) -> void:
		if tuning != null: changed.call(on))
	parent.add_child(toggle)
	return toggle

func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", ROW_GAP)
	_column.add_child(grid)
	return grid

func _spin(getter: Callable, setter: Callable, maximum: float, minimum := 0.0) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 0.001
	spin.custom_arrow_step = 1.0
	spin.select_all_on_focus = true
	spin.custom_minimum_size = SPIN_SIZE
	spin.get_line_edit().add_theme_font_size_override("font_size", ROW_FONT)
	spin.set_value_no_signal(getter.call())
	spin.value_changed.connect(setter)
	_live(spin, setter)
	_spins.append([spin, getter])
	return spin

## Applies a number as it is typed (#94), without waiting for Enter or focus
## loss; the box's own commit then sets the same value. The typed text is left
## alone so partial entries such as "1." keep editing.
func _live(spin: SpinBox, setter: Callable) -> void:
	var line := spin.get_line_edit()
	line.text_changed.connect(func(text: String) -> void:
		var typed := text.strip_edges()
		if typed.is_valid_float():
			setter.call(clampf(typed.to_float(), spin.min_value, spin.max_value)))
	line.text_submitted.connect(func(_text: String) -> void:
		if pointer_only: line.release_focus())

## One value: its name, its editor and a DEFAULT button that restores it.
## A value the weapon does not have by default shows a dash and no button.
func _row(grid: GridContainer, text: String, control: Control, to_default: Callable, unit: String) -> void:
	var name_label := _label(grid, text + (" (%s)" % unit if not unit.is_empty() else ""), &"Body", ROW_FONT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control == null:
		_label(grid, "—", &"Body", ROW_FONT)
		grid.add_child(Control.new())
		return
	grid.add_child(control)
	var button := Button.new()
	button.text = "DEFAULT"
	button.theme_type_variation = &"TextLink"
	button.add_theme_font_size_override("font_size", HINT_FONT)
	button.pressed.connect(func() -> void:
		to_default.call()
		# Show the restored value at once, even if its box still has focus.
		for pair: Array in _spins:
			if pair[0] == control:
				(control as SpinBox).set_value_no_signal(pair[1].call()))
	grid.add_child(button)

func _new_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	content.add_child(column)
	return column

func _auto_toggle(slot: String) -> void:
	auto_toggles[slot] = _toggle(_column, "AutoFire_" + slot, "Allow auto fire",
		func(on: bool) -> void: tuning.auto_fire[slot] = on)
