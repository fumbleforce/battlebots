class_name HudSettingsPanel
extends PanelContainer
## Emits detached live drafts; cancel restores the original HUD presentation.
signal preview_changed(preferences: HudPreferences)
signal applied(preferences: HudPreferences)
signal finished(saved: bool)
var text_scale_choice: OptionButton
var palette_choice: OptionButton
var contrast_toggle: CheckButton
var save_button: Button
var cancel_button: Button
var message: Label
var sample_panel: PanelContainer
var sample_label: Label
var _original: HudPreferences
var _path := ""
var _opened := false

func _ready() -> void:
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	theme_type_variation = &"PanelGlass"
	custom_minimum_size.x = 480
	var inset := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 20)
	add_child(inset)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	inset.add_child(column)
	_label(column, "HUD ACCESSIBILITY", 28).theme_type_variation = &"HeadingItalic"
	_label(column, "HUD text size", 20)
	text_scale_choice = OptionButton.new()
	for percentage: int in [100, 125, 150]:
		text_scale_choice.add_item("%d%%" % percentage)
	column.add_child(text_scale_choice)
	_label(column, "HUD color preset", 20)
	palette_choice = OptionButton.new()
	for label: String in ["Standard", "Deuteranopia", "Protanopia", "Tritanopia"]:
		palette_choice.add_item(label)
	column.add_child(palette_choice)
	contrast_toggle = CheckButton.new()
	contrast_toggle.text = "High contrast HUD panels"
	column.add_child(contrast_toggle)
	for control: Control in [text_scale_choice, palette_choice, contrast_toggle]:
		control.add_theme_font_size_override("font_size", 20)
		control.custom_minimum_size.y = 44
	text_scale_choice.item_selected.connect(func(_index: int) -> void: _preview())
	palette_choice.item_selected.connect(func(_index: int) -> void: _preview())
	contrast_toggle.toggled.connect(func(_pressed: bool) -> void: _preview())
	_label(column, "HUD SAMPLE", 16)
	sample_panel = PanelContainer.new()
	sample_panel.custom_minimum_size.y = 94
	column.add_child(sample_panel)
	sample_label = _label(sample_panel, "CORE 25%\nFRONT BREACHED", 20)
	sample_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sample_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message = _label(column, "", 16)
	message.custom_minimum_size.y = 56
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	cancel_button = _button(buttons, "CANCEL", cancel)
	save_button = _button(buttons, "SAVE", save_and_close)
	var navigation: Array[Control] = [text_scale_choice, palette_choice, contrast_toggle, cancel_button, save_button]
	for index: int in range(navigation.size()):
		var control := navigation[index]
		control.focus_next = control.get_path_to(navigation[(index + 1) % navigation.size()])
		control.focus_previous = control.get_path_to(navigation[posmod(index - 1, navigation.size())])
	hide()

func _label(parent: Node, text: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	parent.add_child(item)
	return item

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = 44
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_theme_font_size_override("font_size", 20)
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

func open_for(preferences: HudPreferences, path: String) -> void:
	if _opened:
		preview_changed.emit(_original.copy())
	_original = preferences.copy()
	_path = path
	_opened = true
	text_scale_choice.select(maxi(0, HudPreferences.TEXT_SCALES.find(preferences.text_scale)))
	palette_choice.select(maxi(0, HudPreferences.PALETTES.find(preferences.palette)))
	contrast_toggle.set_pressed_no_signal(preferences.high_contrast)
	_update_sample(_values())
	message.text = "Preview HUD text above. Save applies these settings to the combat and round HUD." if preferences.load_error == OK else "HUD settings could not be loaded. Defaults are shown; Save replaces the file."
	show()
	text_scale_choice.grab_focus()

func _values() -> HudPreferences:
	var result := HudPreferences.new()
	result.text_scale = HudPreferences.TEXT_SCALES[text_scale_choice.selected]
	result.palette = HudPreferences.PALETTES[palette_choice.selected]
	result.high_contrast = contrast_toggle.button_pressed
	return result

func _preview() -> void:
	if not _opened:
		return
	message.text = "Unsaved HUD changes"
	var preferences := _values()
	_update_sample(preferences)
	preview_changed.emit(preferences)

func _update_sample(preferences: HudPreferences) -> void:
	sample_label.add_theme_font_size_override("font_size", roundi(20 * preferences.text_scale))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("080c12") if preferences.high_contrast else Color(0.035, 0.045, 0.06, 0.9)
	style.set_border_width_all(2)
	var colors: Array = {
		"standard": ["f5b82e", "ff8a80"],
		"deuteranopia": ["82cfff", "ffce75"],
		"protanopia": ["82cfff", "ffe083"],
		"tritanopia": ["ffcc91", "ffa7cd"],
	}.get(preferences.palette, ["f5b82e", "ff8a80"])
	style.border_color = Color.WHITE if preferences.high_contrast else Color(colors[0])
	sample_label.add_theme_color_override("font_color", Color(colors[1]))
	sample_panel.add_theme_stylebox_override("panel", style)

func cancel() -> void:
	if not _opened:
		return
	_opened = false
	preview_changed.emit(_original.copy())
	hide()
	finished.emit(false)

func save_and_close() -> void:
	if not _opened:
		return
	var preferences := _values()
	var error := preferences.save_file(_path)
	if error != OK:
		message.text = "Could not save HUD settings (%s). Try again or Cancel." % error_string(error)
		return
	_opened = false
	hide()
	preview_changed.emit(preferences.copy())
	applied.emit(preferences)
	finished.emit(true)

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()

func _exit_tree() -> void:
	if _opened and _original != null:
		preview_changed.emit(_original.copy())
