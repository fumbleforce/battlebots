extends MenuScreen

class GaragePreview extends GarageBotPreview:
	func _layout_status() -> void:
		super()
		if is_instance_valid(status): status.hide()
		if is_instance_valid(_status_next): _status_next.hide()

	func _invalid_status(message: String) -> void:
		super(message)
		status.hide()
		_status_next.hide()

	func rotate_view(delta: Vector2) -> void:
		super(Vector2(-delta.x, delta.y))

const BOT_ROW := preload("res://ui/menus/components/bot_row.tscn")
var build_preview: GarageBotPreview
var recovery_panel: GarageRecoveryPanel
var recovery_button: Button
var notice: Label
var _text_factor := 1.0
var _build_page := 0
var _initial_focus_pending := true
var _build_capacity := 2
var _build_ranges: Array[Vector2i] = [Vector2i(0, 2)]
var _displayed_active := -1
var _build_pager: HBoxContainer
var _page_label: Label


func _ready() -> void:
	super()
	build_preview = GaragePreview.new()
	var frame := %BotImage.get_parent()
	%BotImage.hide()
	frame.add_child(build_preview)
	frame.move_child(build_preview, 1)
	for control: Node in find_children("Rotate","Button",true,false):
		control.tooltip_text = "Reset build preview view"
		control.pressed.connect(build_preview.reset_view)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%BotList.get_parent().add_child(notice)
	%Customize.pressed.connect(MenuRouter.goto.bind("customize"))
	%NewBot.pressed.connect(func(): PlayerProfile.new_build(); MenuRouter.goto("customize"))
	%Steps.hide()
	%Eyebrow.text = "YOUR BOTS · SELECT OR CUSTOMIZE"
	%Next.text = "DONE"
	%Next.pressed.connect(MenuRouter.goto.bind("main", false))
	_select(PlayerProfile.active_bot)
	recovery_panel = GarageRecoveryPanel.new()
	add_child(recovery_panel)
	recovery_button = Button.new()
	recovery_button.text = "SAVED FILE"
	recovery_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%Next.get_parent().add_child(recovery_button)
	recovery_button.pressed.connect(func(): recovery_panel.open(PlayerProfile))
	PlayerProfile.inventory_changed.connect(_refresh_builds)
	_prepare_text_layout()
	_build_page = _page_for_item(_build_ranges, PlayerProfile.active_bot)
	_refresh_builds()
	apply_text_scale(_text_factor)
	_focus_selected.call_deferred()

func _focus_selected() -> void:
	if not is_inside_tree() or recovery_panel.visible: return
	var rows := %BotList.get_children()
	for row: Button in rows:
		if row.button_pressed: row.grab_focus(); return

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(recovery_panel) and recovery_panel.visible: return
	super(event)

func _refresh_builds() -> void:
	if _displayed_active != PlayerProfile.active_bot: _build_page = _page_for_item(_build_ranges, PlayerProfile.active_bot)
	clear_children(%BotList)
	var group := ButtonGroup.new()
	_build_page = clampi(_build_page, 0, _build_ranges.size() - 1)
	for i in PlayerProfile.bots.size():
		var row := BOT_ROW.instantiate()
		%BotList.add_child(row)
		row.setup(PlayerProfile.bots[i])
		row.visible = i >= _build_ranges[_build_page].x and i < _build_ranges[_build_page].y
		var pad: Control = row.get_node("Pad")
		pad.minimum_size_changed.connect(_fit_button_content.bind(row, pad))
		row.button_group = group
		row.pressed.connect(_select.bind(i))
		row.button_pressed = i == PlayerProfile.active_bot
	%Bays.text = "%d builds · 12 saved max" % PlayerProfile.bots.size()
	notice.text = "Build/file needs attention. Inspect SAVED FILE or customize the selected build." if not PlayerProfile.errors.is_empty() else ""
	notice.visible = not notice.text.is_empty()
	_page_label.text = "%d / %d" % [_build_page + 1, _build_ranges.size()]
	_build_pager.get_child(0).disabled = _build_page == 0
	_build_pager.get_child(2).disabled = _build_page + 1 >= _build_ranges.size()
	_select(PlayerProfile.active_bot)
	apply_text_scale(_text_factor)


func _select(i: int) -> void:
	PlayerProfile.active_bot = i
	_displayed_active = i
	MenuRouter.match_setup.bot = i
	var b: Dictionary = PlayerProfile.bots[i]
	build_preview.show_loadout(PlayerProfile.loadouts[i])
	%BotImage.texture = b.image
	%BotClass.text = "VALID BUILD · 3D PREVIEW" if b.valid else b.cls
	if b.get("retained", false): %BotClass.text = b.cls
	%BotName.text = b.name
	%BotHp.text = "%s core HP" % MenuData.fmt_int(b.hp) if b.valid else "Stats unavailable · " + "; ".join(b.reasons)
	%Pips.get_parent().hide()
	%Next.disabled = false
	%Stats.visible = b.valid
	%Bays.tooltip_text = "; ".join(PlayerProfile.errors)
	var j := 0
	for pip in %Pips.get_children():
		pip.theme_type_variation = &"PipOn" if j < b.shields else &"Pip"
		j += 1
	%Weapon.text = b.weapon
	%Ability.text = b.ability
	%Boost.text = b.boost
	var has_auxiliary: bool = PlayerProfile.loadouts[i].get("parts", {}).get("utility") == "minigun_pod"
	var auxiliary_key: Label = %AbilitySlot.get_node("Pad/Row/Key/L")
	auxiliary_key.text = InputPreferences.load_file().label_for(&"secondary") if has_auxiliary else "—"
	%AbilitySlot.get_node("Pad/Row/Text/Label").text = "AUXILIARY GUN" if has_auxiliary else "UTILITY"
	for child in %Stats.get_children():
		%Stats.remove_child(child)
		child.queue_free()
	if b.valid:
		var stats := ContentRegistry.new().validate(PlayerProfile.loadouts[i]).stats
		for text: String in [
			"Mass  %s / 120 kg" % MenuData.fmt_int(stats.mass),
			"Battery  %s" % MenuData.fmt_int(stats.battery),
			"Max speed  %s m/s" % MenuData.fmt_int(stats.speed),
			"Front armor  %s HP" % MenuData.fmt_int(stats.plate_integrity),
			"Rear armor  %s HP" % MenuData.fmt_int(stats.plate_integrity),
			"Left armor  %s HP" % MenuData.fmt_int(stats.plate_integrity),
			"Right armor  %s HP" % MenuData.fmt_int(stats.plate_integrity)]:
			var label := Label.new()
			label.text = text
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 20)
			%Stats.add_child(label)
		MenuTextScale.apply(%Stats, _text_factor)


func _prepare_text_layout() -> void:
	var frame: Control = %BotImage.get_parent()
	var overlay: Control = %Customize.get_parent()
	overlay.reparent(frame.get_parent())
	frame.get_parent().move_child(overlay, 0)
	frame.custom_minimum_size.y = 180
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for button: Button in [%Customize]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for label: Label in [%BotName, %BotClass, %BotHp, %Weapon, %Ability, %Boost]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%BotHp.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for slot: Control in [%WeaponSlot, %AbilitySlot, %BoostSlot]:
		var pad: Control = slot.get_node("Pad")
		pad.minimum_size_changed.connect(_fit_button_content.bind(slot, pad))
	$Layout/Body/Row/BotsCol.custom_minimum_size.x = 430
	$Layout/Body/Row/RightCol.custom_minimum_size.x = 400
	%BotName.add_theme_font_size_override("font_size", 32)
	%BotHp.add_theme_font_size_override("font_size", 22)
	%BotList.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_pager = HBoxContainer.new()
	%BotList.get_parent().add_child(_build_pager)
	%BotList.get_parent().move_child(_build_pager, 2)
	var previous := Button.new()
	previous.text = "PREV"
	previous.pressed.connect(_page_builds.bind(-1))
	_build_pager.add_child(previous)
	_page_label = Label.new()
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_pager.add_child(_page_label)
	var next := Button.new()
	next.text = "NEXT"
	next.pressed.connect(_page_builds.bind(1))
	_build_pager.add_child(next)
	$Layout/Body/Row/RightCol/Loadout.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _page_builds(direction: int) -> void:
	_build_page += direction
	_refresh_builds()
	%BotList.get_child(_build_ranges[_build_page].x).grab_focus()


func apply_text_scale(factor: float) -> void:
	_pagination_frames = 4
	_text_factor = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	$Layout/Header.custom_minimum_size.y = 115 if _text_factor == 1.0 else 160
	MenuTextScale.apply(self, _text_factor)
	if not is_instance_valid(build_preview) or not is_instance_valid(recovery_panel): return
	build_preview.apply_text_scale(_text_factor)
	recovery_panel.apply_text_scale(_text_factor)
	for row: Control in %BotList.get_children():
		var box: Control = row.get_node("Pad/Row/Text")
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for label: Label in box.get_children():
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.get_node("%Thumb").custom_minimum_size.x = 70
		_fit_button_content.call_deferred(row, row.get_node("Pad"))
	for slot: Control in [%WeaponSlot, %AbilitySlot, %BoostSlot]:
		_fit_button_content.call_deferred(slot, slot.get_node("Pad"))


func _fit_button_content(button: Control, pad: Control) -> void:
	if is_instance_valid(button) and is_instance_valid(pad):
		button.custom_minimum_size.y = maxf(106, pad.get_combined_minimum_size().y)

var _pagination_frames := 4
var _pagination_geometry: Array = []

func _process(_delta: float) -> void:
	if not is_instance_valid(_build_pager) or not is_visible_in_tree(): return
	var geometry: Array = [size, $Layout/Header.size, $Layout/Footer.size, %BotList.size.x]
	if geometry != _pagination_geometry:
		_pagination_geometry = geometry
		_pagination_frames = 4
	if _pagination_frames <= 0: return
	_pagination_frames -= 1
	var heights: Array[float] = []
	for row: Control in %BotList.get_children():
		var was_visible := row.visible
		row.show()
		row.size.x = %BotList.size.x
		row.get_node("Pad").size.x = row.size.x
		_measure_hidden_content(row.get_node("Pad"))
		row.visible = was_visible
		_fit_button_content(row, row.get_node("Pad"))
		heights.append(row.get_combined_minimum_size().y)
	var body: MarginContainer = $Layout/Body
	var available: float = size.y - $Layout/Header.size.y - $Layout/Footer.size.y
	available -= body.get_theme_constant("margin_top") + body.get_theme_constant("margin_bottom")
	var column: VBoxContainer = %BotList.get_parent()
	var siblings := 0
	for sibling: Control in column.get_children():
		if sibling == %BotList or sibling == _build_pager or not sibling.visible: continue
		available -= sibling.get_combined_minimum_size().y
		siblings += 1
	var separation := column.get_theme_constant("separation")
	available -= siblings * separation
	var gap: int = %BotList.get_theme_constant("separation")
	var previous_focus := get_viewport().gui_get_focus_owner()
	var restore_list_focus := previous_focus != null and %BotList.is_ancestor_of(previous_focus)
	var ranges := _pack_pages(heights, available, available - _build_pager.get_combined_minimum_size().y - separation, gap, 1)
	if ranges != _build_ranges:
		_build_ranges = ranges
		_build_page = _page_for_item(ranges, PlayerProfile.active_bot)
	_build_page = clampi(_build_page, 0, ranges.size() - 1)
	var page_range := ranges[_build_page]
	_build_capacity = page_range.y - page_range.x
	for i in %BotList.get_child_count(): %BotList.get_child(i).visible = i >= page_range.x and i < page_range.y
	_build_pager.visible = ranges.size() > 1
	_page_label.text = "%d / %d" % [_build_page + 1, ranges.size()]
	_build_pager.get_child(0).disabled = _build_page == 0
	_build_pager.get_child(2).disabled = _build_page + 1 >= ranges.size()
	if _initial_focus_pending:
		var selected: Control = %BotList.get_child(PlayerProfile.active_bot)
		if selected.has_focus(): _initial_focus_pending = false
		elif previous_focus == null or restore_list_focus: _focus_selected.call_deferred()
		else: _initial_focus_pending = false
	elif restore_list_focus and get_viewport().gui_get_focus_owner() == null:
		_focus_selected.call_deferred()



func _measure_hidden_content(control: Control) -> void:
	# Hidden pages also need their actual column width before wrapped-text measurement.
	if control is Container: control.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in control.get_children():
		if child is Control: _measure_hidden_content(child)
	control.update_minimum_size()


func _pack_pages(heights: Array[float], full_budget: float, paged_budget: float, gap: float, columns: int) -> Array[Vector2i]:
	var total := 0.0
	for start in range(0, heights.size(), columns):
		var height := 0.0
		for i in range(start, mini(start + columns, heights.size())): height = maxf(height, heights[i])
		total += height + (gap if start > 0 else 0.0)
	if total <= full_budget: return [Vector2i(0, heights.size())]
	var pages: Array[Vector2i] = []
	var first := 0
	var used := 0.0
	for start in range(0, heights.size(), columns):
		var height := 0.0
		for i in range(start, mini(start + columns, heights.size())): height = maxf(height, heights[i])
		var needed := height + (gap if start > first else 0.0)
		if start > first and used + needed > paged_budget:
			pages.append(Vector2i(first, start))
			first = start
			used = height
		else: used += needed
	pages.append(Vector2i(first, heights.size()))
	return pages


func _page_for_item(pages: Array[Vector2i], index: int) -> int:
	for page in pages.size():
		if index >= pages[page].x and index < pages[page].y: return page
	return maxi(0, pages.size() - 1)
