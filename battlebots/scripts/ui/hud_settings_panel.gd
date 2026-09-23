class_name HudSettingsPanel
extends PanelContainer
## Emits detached live drafts; cancel restores HUD and general-menu presentation.
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
	var page := SettingsStyle.page(self,"Accessibility","Make the interface easier to read. Changes preview immediately and can be cancelled.")
	page.tabs.hide()
	SettingsStyle.section(page.content,"Readability")
	var row := SettingsStyle.row(page.content,"Text size","Scale text in the HUD and general menus.")
	text_scale_choice = OptionButton.new()
	for percentage: int in [100,125,150]: text_scale_choice.add_item("%d%%" % percentage)
	row.add_child(text_scale_choice)
	row = SettingsStyle.row(page.content,"HUD color palette","Alternative team and status colors for color-vision accessibility.")
	palette_choice = OptionButton.new()
	for caption: String in ["Standard","Deuteranopia","Protanopia","Tritanopia"]: palette_choice.add_item(caption)
	row.add_child(palette_choice)
	row = SettingsStyle.row(page.content,"High contrast HUD","Stronger panel backgrounds and borders during matches.")
	contrast_toggle = CheckButton.new()
	contrast_toggle.text = "Enabled"
	row.add_child(contrast_toggle)
	for control: Control in [text_scale_choice,palette_choice,contrast_toggle]:
		control.custom_minimum_size = Vector2(390,48)
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_scale_choice.item_selected.connect(func(_index: int) -> void: _preview())
	palette_choice.item_selected.connect(func(_index: int) -> void: _preview())
	contrast_toggle.toggled.connect(func(_pressed: bool) -> void: _preview())
	SettingsStyle.section(page.content,"Live HUD sample")
	sample_panel = PanelContainer.new()
	sample_panel.custom_minimum_size.y = 100
	page.content.add_child(sample_panel)
	sample_label = SettingsStyle.label(sample_panel,"CORE 25%\nFRONT BREACHED",22)
	sample_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sample_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message = page.message
	SettingsStyle.button(page.footer,"Restore defaults",func() -> void:
		text_scale_choice.select(0)
		palette_choice.select(0)
		contrast_toggle.set_pressed_no_signal(false)
		_preview())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.footer.add_child(spacer)
	cancel_button = SettingsStyle.button(page.footer,"Cancel",cancel)
	save_button = SettingsStyle.button(page.footer,"Save changes",save_and_close,true)
	SettingsStyle.focus_cycle([text_scale_choice,palette_choice,contrast_toggle,cancel_button,save_button])
	hide()

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
	message.text = "Text size applies to general menus and the match HUD. Preview changes before saving." if preferences.load_error == OK else "Settings could not be loaded. Defaults are shown; Save replaces the file."
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
	message.text = "Unsaved accessibility changes"
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

func apply_text_scale(factor: float) -> void:
	# The sample reflects its own preview value and must not be scaled twice.
	MenuTextScale.apply(self, factor)
	_update_sample(_values())


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
