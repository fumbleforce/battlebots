class_name FeaturedVehicle
extends VBoxContainer
## Displays detached choices; the caller accepts selection and owns persistence/session state.
signal selection_requested(index: int, draft: Dictionary)

var preview: GarageBotPreview
var previous_button: Button
var next_button: Button
var name_label: Label
var status_label: Label
var count_label: Label
var _choices: Array = []
var _selected := -1
var _editable := false
var _message := ""
var _factor := 1.0
var _compact := false
var _heading: Label
var _holder: Control
var _selection_row: HBoxContainer

## Main-menu presentation only; selection, validation and caller-owned locks are unchanged.
func set_compact(enabled: bool) -> void:
	_compact = enabled
	if is_node_ready():
		_apply_layout()
		apply_text_scale(_factor)

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading = Label.new()
	_heading.text = "YOUR VEHICLE"
	_heading.add_theme_font_size_override("font_size", 18)
	_heading.add_theme_color_override("font_color", Color("f5b82e"))
	add_child(_heading)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(name_label)
	_holder = Control.new()
	_holder.name = "PreviewHolder"
	_holder.custom_minimum_size.y = 230
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_holder)
	preview = GarageBotPreview.new()
	_holder.add_child(preview)
	preview.zoom_view(-1.8)
	preview.set_auto_rotate(true)
	_selection_row = HBoxContainer.new()
	_selection_row.add_theme_constant_override("separation", 8)
	add_child(_selection_row)
	previous_button = _button(_selection_row, "PREVIOUS", -1)
	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.add_theme_font_size_override("font_size", 18)
	_selection_row.add_child(count_label)
	next_button = _button(_selection_row, "NEXT", 1)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 18)
	add_child(status_label)
	_update()
	_apply_layout()
	apply_text_scale(_factor)

func _apply_layout() -> void:
	_heading.visible = not _compact
	if _compact:
		if name_label.get_parent() != _selection_row: name_label.reparent(_selection_row)
		_selection_row.move_child(name_label, 0)
		_selection_row.move_child(count_label, 1)
		_selection_row.move_child(previous_button, 2)
		_selection_row.move_child(next_button, 3)
	else:
		if name_label.get_parent() != self: name_label.reparent(self)
		move_child(name_label, 1)
		_selection_row.move_child(previous_button, 0)
		_selection_row.move_child(count_label, 1)
		_selection_row.move_child(next_button, 2)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER if _compact else Control.SIZE_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF if _compact else TextServer.AUTOWRAP_WORD_SMART
	# Long names wrap to at most two lines (full name in the tooltip) so the lobby column fits at 150% text.
	name_label.max_lines_visible = -1 if _compact else 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.set_meta("menu_base_font_size", 24 if _compact else 28)
	count_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if _compact else Control.SIZE_EXPAND_FILL
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER if _compact else Control.SIZE_FILL
	count_label.set_meta("menu_base_font_size", 16 if _compact else 18)
	if _compact: count_label.add_theme_color_override("font_color", Color("98a7b8"))
	else: count_label.remove_theme_color_override("font_color")
	previous_button.text = "‹" if _compact else "PREVIOUS"
	next_button.text = "›" if _compact else "NEXT"
	previous_button.tooltip_text = "Previous vehicle"
	next_button.tooltip_text = "Next vehicle"
	previous_button.accessibility_name = "Previous vehicle"
	next_button.accessibility_name = "Next vehicle"
	for button: Button in [previous_button, next_button]:
		button.set_meta("menu_base_font_size", 24 if _compact else 18)
	preview.set_compact(_compact)

func _button(row: HBoxContainer, text: String, direction: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_request_step.bind(direction))
	row.add_child(button)
	return button

func render(loadouts: Array, selected: int, editable: bool = true, message: String = "") -> void:
	_choices = loadouts.duplicate(true)
	_selected = selected if selected >= 0 and selected < _choices.size() else -1
	_editable = editable
	_message = message
	if is_node_ready(): _update()

func _update() -> void:
	var available := _selected >= 0 and _choices[_selected] is Dictionary
	var draft: Dictionary = _choices[_selected] if available else {}
	var vehicle_name := str(draft.get("name", "No vehicle selected")).replace("\n", " ").replace("\r", " ")
	name_label.text = vehicle_name.left(48)
	name_label.tooltip_text = vehicle_name
	count_label.text = "%d / %d" % [_selected + 1, _choices.size()]
	previous_button.disabled = not _editable or _choices.size() < 2
	next_button.disabled = previous_button.disabled
	status_label.text = _message
	status_label.visible = not _message.is_empty()
	preview.visible = _selected >= 0
	preview.show_loadout(draft)

func _request_step(direction: int) -> void:
	if not _editable or _choices.size() < 2: return
	var target := (0 if direction > 0 else _choices.size() - 1) if _selected < 0 else wrapi(_selected + direction, 0, _choices.size())
	var draft: Dictionary = _choices[target] if _choices[target] is Dictionary else {}
	selection_requested.emit(target, draft.duplicate(true))

func apply_text_scale(factor: float) -> void:
	_factor = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	if not is_node_ready(): return
	MenuTextScale.apply(self, _factor)
	for button: Button in [previous_button, next_button]:
		button.custom_minimum_size = Vector2(40, 40) * _factor if _compact else Vector2(0, 40)
	preview.apply_text_scale(_factor)
