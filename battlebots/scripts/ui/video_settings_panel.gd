class_name VideoSettingsPanel
extends PanelContainer
signal applied(preferences: VideoPreferences)
signal finished(saved: bool)
var graphics_apply: Callable
var graphics_controls: Dictionary = {}
var monitor_choice: OptionButton
var preset_choice: OptionButton
var _page: Dictionary
var _groups: Dictionary = {}
var _tabs: Dictionary = {}
var _filling := false
var mode_choice: OptionButton
var resolution_choice: OptionButton
var vsync_button: CheckButton
var message: Label
var apply_button: Button
var keep_button: Button
var revert_button: Button
var defaults_button: Button
var cancel_button: Button
var apply_display: Callable
var capture_display: Callable
var capture_state: Callable
var restore_state: Callable
var _display_state: Dictionary = {}
var _original: VideoPreferences
var _actual: VideoPreferences
var _pending: VideoPreferences
var _path := ""
var _opened := false
var deadline_ms := 0
const MODES := ["windowed", "borderless", "fullscreen"]

func _ready() -> void:
	_page = SettingsStyle.page(self,"Video & graphics","Tune image quality and performance. Display changes include a 15-second recovery timer.")
	for caption: String in ["Display","Quality","Effects"]:
		var tab := SettingsStyle.button(_page.tabs,caption,func() -> void: select_tab(caption))
		tab.toggle_mode = true
		_tabs[caption] = tab
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation",8)
		_page.content.add_child(group)
		_groups[caption] = group
	var display: VBoxContainer = _groups.Display
	SettingsStyle.section(display,"Screen")
	monitor_choice = _choice(display,"Monitor","Choose which connected display to use.",["Current display"])
	monitor_choice.set_item_metadata(0,-1)
	if DisplayServer.get_name() != "headless":
		for index: int in range(DisplayServer.get_screen_count()):
			var extent := DisplayServer.screen_get_size(index)
			monitor_choice.add_item("Display %d · %d × %d" % [index+1,extent.x,extent.y])
			monitor_choice.set_item_metadata(index+1,index)
	mode_choice = _choice(display,"Display mode","Fullscreen modes use the display's native resolution.",["Windowed","Borderless fullscreen","Exclusive fullscreen"])
	resolution_choice = _choice(display,"Window resolution","Render scale on the Quality tab controls internal 3D resolution.",[])
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]: _add_resolution(extent)
	mode_choice.item_selected.connect(func(_index: int) -> void: _dependencies())
	SettingsStyle.section(display,"Frame pacing")
	var sync_row := SettingsStyle.row(display,"V-Sync","Synchronize frames to the display to prevent tearing.")
	vsync_button = CheckButton.new()
	vsync_button.text = "Enabled"
	sync_row.add_child(vsync_button)
	_graphics_option(display,"fps_limit","Frame rate limit","V-Sync may impose a lower limit than the selected cap.")
	_graphics_option(display,"show_fps","Performance counter","Show frame rate and frame time while playing.")
	var quality: VBoxContainer = _groups.Quality
	SettingsStyle.section(quality,"Quality preset")
	preset_choice = _choice(quality,"Overall quality","High balances smooth edges, lighting and detail.",GraphicsOptions.PRESETS + ["Custom"])
	preset_choice.item_selected.connect(_preset_selected)
	SettingsStyle.section(quality,"Image clarity")
	_graphics_option(quality,"aa","Anti-aliasing","Temporal AA reduces surface shimmer; MSAA preserves crisp moving edges.")
	_graphics_option(quality,"upscaler","Resolution method","FSR 2 includes temporal anti-aliasing. Native allows supersampling above 100%.")
	_graphics_option(quality,"render_scale","Render scale","50–100% trades detail for speed. 105–150% supersamples at a higher GPU cost.")
	_graphics_option(quality,"sharpness","Upscaling sharpness","Restore fine detail when FSR is enabled. Higher values sharpen more.")
	_graphics_option(quality,"anisotropy","Texture filtering","Keep ground and angled surfaces sharp at a distance.")
	_graphics_option(quality,"shadows","Shadow quality","Higher resolution shadow maps with smoother penumbra filtering.")
	var effects: VBoxContainer = _groups.Effects
	SettingsStyle.section(effects,"Lighting & atmosphere")
	_graphics_option(effects,"ao","Ambient occlusion","Contact shading in corners and around nearby surfaces.")
	_graphics_option(effects,"indirect","Indirect lighting","Screen-space bounced light adds depth and subtle color spill.")
	_graphics_option(effects,"reflections","Screen-space reflections","Reflect visible scene details alongside the arena's reflection probes.")
	_graphics_option(effects,"bloom","Bloom","Soft glow around bright arena fixtures and emissive surfaces.")
	_graphics_option(effects,"fog","Volumetric atmosphere","Lit haze and localized dust in arenas that support it.")
	_graphics_option(effects,"particles","Particle detail","Dust, exhaust and sparks. Lower settings retain essential combat cues.")
	SettingsStyle.section(effects,"Image refinement")
	_graphics_option(effects,"debanding","Debanding","Dither subtle gradients to reduce visible color bands.")
	_graphics_option(effects,"roughness_limiter","Specular smoothing","Reduce sparkling on fine reflective geometry.")
	_graphics_option(effects,"brightness","Brightness","Adjust the final image without changing arena light placement.")
	_graphics_option(effects,"contrast","Contrast","Control the difference between dark and bright areas.")
	_graphics_option(effects,"saturation","Color saturation","Adjust color intensity; 0% gives a monochrome image.")
	message = _page.message
	defaults_button = SettingsStyle.button(_page.footer,"Restore defaults",reset_defaults)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.footer.add_child(spacer)
	cancel_button = SettingsStyle.button(_page.footer,"Cancel",cancel)
	apply_button = SettingsStyle.button(_page.footer,"Apply changes",preview_changes,true)
	keep_button = SettingsStyle.button(_page.footer,"Keep changes",confirm,true)
	revert_button = SettingsStyle.button(_page.footer,"Revert",revert)
	select_tab("Display")
	_confirming(false)
	hide()

func select_tab(caption: String) -> void:
	for key: String in _groups:
		_groups[key].visible = key == caption
		_tabs[key].set_pressed_no_signal(key == caption)
	_page.scroll.scroll_vertical = 0
	_focus_navigation.call_deferred()

func _choice(parent: Node, caption: String, description: String, options: Array) -> OptionButton:
	var line := SettingsStyle.row(parent,caption,description)
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(390,48)
	choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for text: String in options: choice.add_item(text)
	line.add_child(choice)
	return choice

func _graphics_option(parent: Node, key: String, caption: String, description: String) -> void:
	var control: Control
	if GraphicsOptions.CHOICES.has(key):
		var choice := _choice(parent,caption,description,GraphicsOptions.CHOICES[key].keys())
		for index: int in range(choice.item_count): choice.set_item_metadata(index,GraphicsOptions.CHOICES[key].values()[index])
		choice.item_selected.connect(func(_index: int) -> void: _changed())
		control = choice
	else:
		var line := SettingsStyle.row(parent,caption,description)
		if GraphicsOptions.RANGES.has(key):
			var group := HBoxContainer.new()
			group.custom_minimum_size.x = 390
			group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(group)
			var slider := HSlider.new()
			slider.min_value = GraphicsOptions.RANGES[key][0]
			slider.max_value = GraphicsOptions.RANGES[key][1]
			slider.step = GraphicsOptions.RANGES[key][2]
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.custom_minimum_size.y = 42
			group.add_child(slider)
			var amount := SettingsStyle.label(group,"100%",22,SettingsStyle.ACCENT)
			amount.custom_minimum_size.x = 80
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			slider.value_changed.connect(func(value: float) -> void: amount.text = "%d%%" % roundi(value); _changed())
			slider.set_meta("amount",amount)
			control = slider
		else:
			var toggle := CheckButton.new()
			toggle.text = "Enabled"
			toggle.custom_minimum_size.x = 180
			toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(toggle)
			toggle.toggled.connect(func(_enabled: bool) -> void: _changed())
			control = toggle
	control.tooltip_text = description
	graphics_controls[key] = control

func _graphics_values() -> Dictionary:
	var result := GraphicsOptions.DEFAULTS.duplicate(true)
	for key: String in graphics_controls:
		var control: Control = graphics_controls[key]
		if control is OptionButton: result[key] = control.get_item_metadata(control.selected)
		elif control is HSlider: result[key] = roundi(control.value)
		else: result[key] = control.button_pressed
	return result

func _fill_graphics(values: Dictionary) -> void:
	_filling = true
	for key: String in graphics_controls:
		var control: Control = graphics_controls[key]
		if control is OptionButton: control.select(GraphicsOptions.CHOICES[key].values().find(values[key]))
		elif control is HSlider:
			control.set_value_no_signal(values[key])
			control.get_meta("amount").text = "%d%%" % values[key]
		else: control.set_pressed_no_signal(values[key])
	preset_choice.select(GraphicsOptions.preset_index(values))
	_filling = false
	_dependencies()

func _preset_selected(index: int) -> void:
	if index < 4: _fill_graphics(GraphicsOptions.preset(index,_graphics_values()))

func _changed() -> void:
	if _filling: return
	preset_choice.select(GraphicsOptions.preset_index(_graphics_values()))
	_dependencies()

func _dependencies() -> void:
	var active := deadline_ms > 0
	resolution_choice.disabled = active or mode_choice.selected != 0
	var fsr2: bool = _graphics_values().upscaler == "fsr2"
	for key: String in graphics_controls:
		var control: Control = graphics_controls[key]
		var disabled := active
		if key == "aa": disabled = disabled or fsr2
		if key == "sharpness": disabled = disabled or _graphics_values().upscaler == "native"
		if key in ["ao","indirect","reflections","fog"]: disabled = disabled or (DisplayServer.get_name() != "headless" and not GraphicsRuntime.forward_plus())
		if control is HSlider: control.editable = not disabled
		elif control is BaseButton: control.disabled = disabled
	var scale_slider: HSlider = graphics_controls.render_scale
	scale_slider.max_value = 150 if _graphics_values().upscaler == "native" else 100
	if DisplayServer.get_name() != "headless" and not GraphicsRuntime.forward_plus():
		graphics_controls.upscaler.set_item_disabled(2,true)
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			graphics_controls.upscaler.set_item_disabled(1,true)
			for index: int in [1,2]: graphics_controls.aa.set_item_disabled(index,true)
			graphics_controls.debanding.disabled = true
			graphics_controls.roughness_limiter.disabled = true
		for index: int in [6,7]: graphics_controls.aa.set_item_disabled(index,true)

func _add_resolution(size: Vector2i) -> void:
	resolution_choice.add_item("%d × %d" % [size.x, size.y])
	resolution_choice.set_item_metadata(resolution_choice.item_count - 1, size)

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)
	for item: Node in find_children("*","OptionButton",true,false):
		item.custom_minimum_size.x = 390 * factor

func open_for(preferences: VideoPreferences, path: String = VideoPreferences.DEFAULT_PATH) -> void:
	if deadline_ms > 0:
		revert()
	_original = preferences.copy()
	_actual = capture_display.call() if capture_display.is_valid() else VideoPreferences.capture()
	_display_state = capture_state.call() if capture_state.is_valid() else VideoPreferences.capture_display_state()
	_path = path
	_opened = true
	_fill(_original)
	message.text = "Changes are saved only when applied. FSR 2 handles its own anti-aliasing." if GraphicsRuntime.forward_plus() or DisplayServer.get_name() == "headless" else "Some effects require the Forward+ renderer and are unavailable in this session."
	if preferences.load_error != OK and not path.is_empty():
		message.text = "Saved video settings could not be loaded. Defaults are shown; Apply replaces the file."
	show()
	mode_choice.grab_focus()
	_focus_navigation.call_deferred()

func _fill(preferences: VideoPreferences) -> void:
	mode_choice.select(MODES.find(preferences.mode))
	var index := -1
	for item in range(resolution_choice.item_count):
		if resolution_choice.get_item_metadata(item) == preferences.resolution:
			index = item
	if index < 0:
		_add_resolution(preferences.resolution)
		index = resolution_choice.item_count - 1
	resolution_choice.select(index)
	resolution_choice.disabled = preferences.mode != "windowed"
	vsync_button.set_pressed_no_signal(preferences.vsync)
	monitor_choice.select(clampi(preferences.screen + 1,0,monitor_choice.item_count-1))
	_fill_graphics(preferences.graphics)

func _apply(preferences: VideoPreferences, vsync_only := false) -> Error:
	var error: Error = apply_display.call(preferences) if apply_display.is_valid() else preferences.apply(vsync_only)
	if error == OK and graphics_apply.is_valid(): graphics_apply.call(preferences.graphics)
	return error

func preview_changes() -> void:
	if not _opened or deadline_ms > 0:
		return
	_pending = VideoPreferences.new()
	_pending.mode = MODES[mode_choice.selected]
	_pending.resolution = resolution_choice.get_item_metadata(resolution_choice.selected)
	_pending.vsync = vsync_button.button_pressed
	_pending.screen = monitor_choice.get_item_metadata(monitor_choice.selected)
	_pending.graphics = _graphics_values()
	var vsync_only := _pending.mode == _original.mode and _pending.resolution == _original.resolution and _pending.screen == _original.screen
	var error := _apply(_pending, vsync_only)
	if error != OK:
		message.text = "Display settings could not be applied: " + error_string(error)
		return
	deadline_ms = Time.get_ticks_msec() + 15000
	if vsync_only and _pending.vsync == _original.vsync:
		confirm()
	else:
		_confirming(true)
		keep_button.grab_focus()

func _confirming(active: bool) -> void:
	keep_button.visible = active
	revert_button.visible = active
	apply_button.visible = not active
	defaults_button.visible = not active
	cancel_button.visible = not active
	mode_choice.disabled = active
	resolution_choice.disabled = active or mode_choice.selected != 0
	vsync_button.disabled = active
	monitor_choice.disabled = active
	preset_choice.disabled = active
	_dependencies()
	_focus_navigation.call_deferred()

func _process(_delta: float) -> void:
	if deadline_ms <= 0:
		return
	if Time.get_ticks_msec() >= deadline_ms:
		revert()
	else:
		message.text = "Keep these display settings? Reverting in %d seconds." % ceili((deadline_ms - Time.get_ticks_msec()) / 1000.0)

func confirm() -> void:
	if deadline_ms <= 0:
		return
	if Time.get_ticks_msec() >= deadline_ms:
		revert()
		return
	var error := _pending.save_file(_path)
	if error != OK:
		revert()
		message.text = "Could not save video settings. Previous display restored."
		return
	deadline_ms = 0
	_confirming(false)
	_opened = false
	applied.emit(_pending.copy())
	hide()
	finished.emit(true)

func revert() -> void:
	if deadline_ms <= 0:
		return
	_restore_display()
	deadline_ms = 0
	_confirming(false)
	_fill(_original)
	message.text = "Previous display settings restored."
	apply_button.grab_focus()

func reset_defaults() -> void:
	if deadline_ms == 0:
		_fill(VideoPreferences.new())

func cancel() -> void:
	revert()
	_opened = false
	hide()
	finished.emit(false)

func _input(event: InputEvent) -> void:
	if _opened and visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if deadline_ms > 0:
			revert()
		else:
			cancel()

func _exit_tree() -> void:
	if deadline_ms > 0 and _actual != null:
		_restore_display()

func _restore_display() -> void:
	if restore_state.is_valid():
		restore_state.call(_display_state.duplicate(true))
	elif not _display_state.is_empty():
		VideoPreferences.restore_display_state(_display_state)
	else:
		_apply(_actual)
	if graphics_apply.is_valid(): graphics_apply.call(_original.graphics)

func _focus_navigation() -> void:
	var controls: Array[Control] = []
	for item: Node in find_children("*","Control",true,false):
		if item.is_visible_in_tree() and item.focus_mode != Control.FOCUS_NONE:
			if item is BaseButton and item.disabled: continue
			if item is HSlider and not item.editable: continue
			controls.append(item)
	SettingsStyle.focus_cycle(controls)
