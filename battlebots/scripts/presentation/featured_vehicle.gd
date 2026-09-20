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

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := Label.new()
	heading.text = "YOUR VEHICLE"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("f5b82e"))
	add_child(heading)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(name_label)
	var holder := Control.new()
	holder.name = "PreviewHolder"
	holder.custom_minimum_size.y = 230
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(holder)
	preview = GarageBotPreview.new()
	holder.add_child(preview)
	preview.zoom_view(-1.8)
	preview.set_auto_rotate(true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	previous_button = _button(row, "PREVIOUS", -1)
	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.add_theme_font_size_override("font_size", 18)
	row.add_child(count_label)
	next_button = _button(row, "NEXT", 1)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 18)
	add_child(status_label)
	_update()
	apply_text_scale(_factor)

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
	name_label.text = str(draft.get("name", "No vehicle selected")).replace("\n", " ").replace("\r", " ").left(48)
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
	preview.apply_text_scale(_factor)
