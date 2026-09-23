extends MenuScreen
## Canonical parts and paint editing; draft history and saves belong to PlayerProfile.

const CATEGORY_ROW := preload("res://ui/menus/components/category_row.tscn")
const ITEM_TILE := preload("res://ui/menus/components/item_tile.tscn")
## Vehicle modules ("decals" catalogue) are sections of PARTS > ARMOR, not a tab.
const TABS := ["parts", "paint"]
const SLOT_HEADINGS := {"parts": "PART SLOTS", "paint": "PAINT LAYERS"}
## Compact one-line option tiles, plus a thin swatch strip on paint choices.
const TILE_HEIGHT := 44
const SWATCH_HEIGHT := 6

var _tab := "parts"
var _cat := {"parts": 0, "paint": 0, "decals": 0}
var _item := {}
var _refocus := ""
var name_edit: LineEdit
var undo_button: Button
var redo_button: Button
var build_preview: GarageBotPreview
var comparison_panel: GarageComparisonPanel
var revalidate_button: Button
var recovery_panel: GarageRecoveryPanel
var recovery_button: Button
var stats_button: Button
var _text_scale := 1.0
var _showing_stats := false
var _category_page := {"parts": 0, "paint": 0, "decals": 0}
var _category_pager: HBoxContainer
var _category_page_label: Label
var _category_capacity := 3
var _category_ranges: Array[Vector2i] = [Vector2i(0, 3)]
var _color_picker: ColorPickerButton
## Catalogue indices of the first choice group's tiles, in display order.
var _shown_items: Array[int] = []
## Choice group ("tab:category") whose selected tile fills the description.
var _detail_key := ""
## Vertical scroll box holding the choice grid; keeps its position per category.
var _choice_scroll: ScrollContainer
var _scroll_key := ""
## Choice tiles by "tab:category:item" for keyboard/test lookup.
var _tiles: Dictionary = {}
## Selected build: status, name, live preview and stat strip.
@onready var readout: BuildReadout = $Layout/Body/Row/Preview
## Part swap about to be equipped: the build summary before it and its caption.
var _pending_swap: Dictionary = {}
## Last equipped part swap, shown while the draft still matches its result.
var _last_swap: Dictionary = {}

func apply_text_scale(factor: float) -> void:
	_pagination_frames = 4
	_text_scale = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	MenuTextScale.apply(self, _text_scale)
	$Layout/Header.custom_minimum_size.y = 115 if _text_scale == 1.0 else 160
	if not is_instance_valid(build_preview): return
	build_preview.apply_text_scale(_text_scale)
	comparison_panel.apply_text_scale(_text_scale)
	if is_instance_valid(recovery_panel): recovery_panel.apply_text_scale(_text_scale)
	readout.get_node("%ImageFrame").custom_minimum_size.y = 240 if _text_scale == 1.0 else 160
	# Room for a name and three description lines keeps the preview from resizing.
	%SelDesc.get_parent().custom_minimum_size.y = ceilf(120 * _text_scale)
	for row: Control in %Categories.get_children():
		row.custom_minimum_size.y = ceilf(82 * _text_scale)
		row.get_node("%Current").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for tile: Control in %Items.get_children():
		if not tile.has_node("Inner"): continue
		tile.custom_minimum_size.y = ceilf(TILE_HEIGHT * _text_scale)
		tile.get_node("Inner/Col/ArtBox").custom_minimum_size.y = SWATCH_HEIGHT

func _show_preview_stats(value: bool) -> void:
	_showing_stats = value
	readout.show_detail(comparison_panel, value)
	stats_button.text = "SHOW MODEL" if value else "SHOW STATS"


func _ready() -> void:
	super()
	%TabDecals.hide()
	%Categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_category_pager = HBoxContainer.new()
	%Categories.get_parent().add_child(_category_pager)
	%Categories.get_parent().move_child(_category_pager, %Categories.get_index() + 1)
	for direction: int in [-1, 1]:
		var button := Button.new()
		button.icon = preload("res://ui/menus/icons/chevron_left.svg") if direction < 0 else preload("res://ui/menus/icons/chevron_right.svg")
		button.tooltip_text = "Previous page" if direction < 0 else "Next page"
		button.theme_type_variation = &"IconButton"
		button.custom_minimum_size = Vector2(56, 56)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_category_pager.add_child(button)
		button.pressed.connect(func():
			_category_page[_tab] = wrapi(_category_page[_tab] + direction, 0, maxi(1, _category_ranges.size()))
			_cat[_tab] = _category_ranges[_category_page[_tab]].x
			_refresh())
		if direction < 0:
			_category_page_label = Label.new()
			_category_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_category_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_category_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_category_page_label.theme_type_variation = &"Muted"
			_category_pager.add_child(_category_page_label)
	_color_picker = ColorPickerButton.new()
	_color_picker.text = "CUSTOM COLOR"
	_color_picker.edit_alpha = false
	%Items.get_parent().add_child(_color_picker)
	_color_picker.popup_closed.connect(func():
		var category: Dictionary = PlayerProfile.catalogue[_tab][_cat[_tab]]
		if _tab == "paint" and category.slot != "paint": PlayerProfile.set_sawblade_color(category.slot, _color_picker.color))
	var options := %Items.get_parent()
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.name = "ChoiceScroll"
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.follow_focus = true
	_choice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options.add_child(_choice_scroll)
	options.move_child(_choice_scroll, %Items.get_index())
	var scroll_gutter := MarginContainer.new()
	scroll_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_gutter.add_theme_constant_override("margin_right", 18)
	_choice_scroll.add_child(scroll_gutter)
	%Items.reparent(scroll_gutter)
	%Items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Items.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	options.get_node("Line").hide()
	%SelName.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%CatLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%CatLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Eyebrow.hide()
	%Eyebrow.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Eyebrow.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	$Layout/Header/Row/SpacerL.size_flags_horizontal = Control.SIZE_FILL
	$Layout/Header/Row/SpacerR.hide()
	$Layout/Header/Row/Sep.hide()
	$Layout/Header/Row/Scrap.hide()
	build_preview = BuildReadout.Preview.new()
	readout.attach_preview(build_preview)
	comparison_panel = GarageComparisonPanel.new()
	comparison_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	readout.show_detail(comparison_panel, false)
	stats_button = Button.new()
	stats_button.name = "StatsToggle"
	stats_button.text = "SHOW STATS"
	stats_button.tooltip_text = "Switch between the 3D model and the detailed stat table."
	stats_button.custom_minimum_size.x = 196
	stats_button.add_theme_font_size_override("font_size", 22)
	readout.add_action(stats_button)
	stats_button.pressed.connect(func(): _show_preview_stats(not _showing_stats))
	# The chosen item's name and description stay under its choices.
	var selected := %SelDesc.get_parent() as Control
	selected.size_flags_vertical = Control.SIZE_SHRINK_END
	%SelDesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Layout/Footer/Row/Hint1.hide()
	var bot: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	name_edit = LineEdit.new()
	name_edit.name = "BuildName"
	name_edit.text = bot.name
	name_edit.placeholder_text = "Build name (1–48 characters)"
	name_edit.max_length = 48
	var name_group := HBoxContainer.new()
	name_group.name = "BuildNameGroup"
	name_group.add_theme_constant_override("separation", 12)
	%Save.get_parent().add_child(name_group)
	%Save.get_parent().move_child(name_group, %Save.get_index())
	var name_label := Label.new()
	name_label.text = "BUILD NAME"
	name_label.theme_type_variation = &"Eyebrow"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_group.add_child(name_label)
	name_group.add_child(name_edit)
	name_edit.custom_minimum_size.x = 240
	name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_edit.custom_minimum_size.y = 77
	name_edit.tooltip_text = "Enter a name, then press Enter or leave this field to apply it to the draft. Save writes it to this computer."
	name_edit.text_submitted.connect(func(_value: String) -> void: _commit_name())
	name_edit.focus_exited.connect(func(): _commit_name.call_deferred())
	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 12)
	$Layout/Footer/Row.add_child(history)
	$Layout/Footer/Row.move_child(history, $Layout/Footer/Row/Spacer.get_index())
	undo_button = Button.new()
	undo_button.text = "UNDO"
	undo_button.tooltip_text = "Undo build edit (Ctrl+Z). Saved files change only when you Save."
	_style_utility_button(undo_button)
	history.add_child(undo_button)
	undo_button.pressed.connect(PlayerProfile.undo_edit)
	redo_button = Button.new()
	redo_button.text = "REDO"
	redo_button.tooltip_text = "Redo build edit (Ctrl+Y or Ctrl+Shift+Z)."
	_style_utility_button(redo_button)
	history.add_child(redo_button)
	redo_button.pressed.connect(PlayerProfile.redo_edit)
	revalidate_button = Button.new()
	revalidate_button.text = "REPAIR"
	revalidate_button.tooltip_text = "Use the current loadout format and catalogue with your existing part IDs and paint. No parts are substituted. Undo is available; Save writes the repaired draft."
	_style_utility_button(revalidate_button)
	history.add_child(revalidate_button)
	revalidate_button.pressed.connect(PlayerProfile.revalidate_active)
	var group := ButtonGroup.new()
	var tab_buttons := [%TabParts, %TabPaint, %TabDecals]
	for i in TABS.size():
		tab_buttons[i].button_group = group
		tab_buttons[i].pressed.connect(_set_tab.bind(TABS[i]))
	%TabParts.button_pressed = true
	%Save.pressed.connect(_save_build)
	PlayerProfile.inventory_changed.connect(_refresh)
	_open_requested_slot()
	_refocus = "item"
	_refresh()
	recovery_panel = GarageRecoveryPanel.new()
	add_child(recovery_panel)
	recovery_button = Button.new()
	recovery_button.text = "MANAGE SAVES"
	_style_utility_button(recovery_button)
	recovery_button.custom_minimum_size.x = 180
	recovery_button.tooltip_text = "Reload saved builds without losing drafts, or review a recovery backup."
	%Save.get_parent().add_child(recovery_button)
	%Save.get_parent().move_child(recovery_button, $Layout/Footer/Row/Spacer.get_index())
	$Layout/Footer/Row/Hint0.hide()
	recovery_button.pressed.connect(func():
		_commit_name()
		recovery_panel.open(PlayerProfile))
	apply_text_scale(_text_scale)


func _open_requested_slot() -> void:
	var slot := CustomizeRequest.slot
	CustomizeRequest.slot = ""
	var categories: Array = PlayerProfile.catalogue.parts
	for index: int in categories.size():
		if categories[index].slot == slot: _cat.parts = index


func _style_utility_button(button: Button) -> void:
	button.theme_type_variation = &"GhostButton"
	button.custom_minimum_size = Vector2(112, 50)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("#ecf2f8"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#202c39")
	normal.border_color = Color("#71849a")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#2a3847")
	hover.border_color = Color("#f5b82e")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(recovery_panel) and recovery_panel.visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed \
		and not event.alt_pressed and not event.meta_pressed:
		var focus := get_viewport().gui_get_focus_owner()
		if not focus is LineEdit and not focus is TextEdit:
			var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if code in [KEY_Z, KEY_Y]:
				if code == KEY_Y or event.shift_pressed:
					PlayerProfile.redo_edit()
				else:
					PlayerProfile.undo_edit()
				get_viewport().set_input_as_handled()
				return
	super(event)
	var dir := tab_input(event)
	if dir != 0:
		var i := wrapi(TABS.find(_tab) + dir, 0, TABS.size())
		[%TabParts, %TabPaint, %TabDecals][i].button_pressed = true
		_set_tab(TABS[i])


func _set_tab(t: String) -> void:
	_tab = t
	for index: int in TABS.size():
		[%TabParts, %TabPaint, %TabDecals][index].button_pressed = TABS[index] == t
	_refresh()


func _refresh() -> void:
	var current: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	var loadout: Dictionary = PlayerProfile.loadouts[PlayerProfile.active_bot]
	readout.show_build(current, loadout)
	if not _pending_swap.is_empty():
		_last_swap = _pending_swap
		_last_swap.target = GarageComparison.current(PlayerProfile.registry, loadout)
		_last_swap.loadout = loadout.duplicate(true)
		_pending_swap = {}
	_show_last_swap()
	if not name_edit.has_focus(): name_edit.text = current.name
	undo_button.disabled = not PlayerProfile.can_undo()
	redo_button.disabled = not PlayerProfile.can_redo()
	revalidate_button.visible = PlayerProfile.needs_revalidation()
	%Save.disabled = not current.valid
	var cats: Array = PlayerProfile.catalogue[_tab]
	var ci: int = _cat[_tab]
	var cat: Dictionary = cats[ci]
	_category_page_label.text = "Page %d of %d" % [_category_page[_tab] + 1, _category_ranges.size()]
	_color_picker.visible = _tab == "paint" and cat.slot != "paint" and SawbladeConfig.enabled(PlayerProfile.loadouts[PlayerProfile.active_bot])
	if _color_picker.visible:
		var rgba: Array = PlayerProfile.loadouts[PlayerProfile.active_bot].cosmetics.sawblade[cat.slot]
		_color_picker.color = Color(rgba[0], rgba[1], rgba[2], 1).linear_to_srgb()
	var key := "%s:%d" % [_tab, ci]
	var groups := _choice_groups(cat, ci)
	var group_keys: Array = groups.map(func(group: Dictionary) -> String: return "%s:%d" % [group.tab, group.index])
	if _detail_key not in group_keys: _detail_key = group_keys[0]
	%SlotHeading.text = SLOT_HEADINGS[_tab]

	clear_children(%Categories)
	var cg := ButtonGroup.new()
	for i in cats.size():
		var row := CATEGORY_ROW.instantiate()
		%Categories.add_child(row)
		row.setup(cats[i].label, PlayerProfile.equipped_name(_tab, cats[i]))
		row.button_group = cg
		row.button_pressed = i == ci
		var shown_categories := _category_ranges[clampi(_category_page[_tab], 0, _category_ranges.size() - 1)]
		row.visible = i >= shown_categories.x and i < shown_categories.y
		row.pressed.connect(func():
			_cat[_tab] = i
			_refocus = "cat"
			_refresh())
		if _refocus == "cat" and i == ci:
			_focus_control.call_deferred(row)

	# Rebuilding the grid resets its height; restore the scroll within one category.
	var scroll_to: int = _choice_scroll.scroll_vertical if _scroll_key == key else 0
	_scroll_key = key
	clear_children(%Items)
	_tiles.clear()
	var ig := ButtonGroup.new()
	var shown_count := 0
	var total_count := 0
	var detail: Dictionary = {}
	for group: Dictionary in groups:
		var group_key := "%s:%d" % [group.tab, group.index]
		var group_cat: Dictionary = group.cat
		var items := _group_items(group.tab, group_cat)
		if group_key == group_keys[0]: _shown_items = items
		var selected := _selected_item(group_key, group.tab, group_cat, items)
		shown_count += items.size()
		total_count += group_cat.items.size()
		if not str(group.heading).is_empty(): _add_section_heading(group.heading)
		for i: int in items:
			var it: Dictionary = PlayerProfile.resolved_item(group.tab, group_cat, group_cat.items[i])
			var tile := ITEM_TILE.instantiate()
			%Items.add_child(tile)
			tile.setup(it, PlayerProfile.item_state(group.tab, group_cat, it))
			tile.button_group = ig
			_tiles["%s:%d" % [group_key, i]] = tile
			var described: bool = group_key == _detail_key and i == selected
			tile.button_pressed = described
			if described:
				detail = {"item": group_cat.items[i], "cat": group_cat, "tab": group.tab}
			var group_tab: String = group.tab
			tile.pressed.connect(func():
				_item[group_key] = i
				_detail_key = group_key
				_refocus = "item"
				if PlayerProfile.item_state(group_tab, group_cat, it) == "own":
					if group_tab == "parts": _pending_swap = _swap("CHANGED", group_cat, it)
					PlayerProfile.equip(group_tab, group_cat, it)
				else:
					_refresh())
			if group_tab == "parts":
				# Hovering or focusing another part previews how it would move the build.
				for entered: Signal in [tile.mouse_entered, tile.focus_entered]:
					entered.connect(_preview_swap.bind(group_cat, it))
				for exited: Signal in [tile.mouse_exited, tile.focus_exited]:
					exited.connect(_show_last_swap)
			if _refocus == "item" and described:
				_focus_control.call_deferred(tile)
	_refocus = ""
	_restore_scroll.call_deferred(key, scroll_to)

	%CatLabel.text = cat.label
	%Count.text = "%d / %d available" % [shown_count, total_count]
	var cur: Dictionary = detail.item
	comparison_panel.render_current(GarageComparison.current(PlayerProfile.registry, PlayerProfile.loadouts[PlayerProfile.active_bot]))
	%SelName.text = cur.name
	var fallback := ("Applies to the %s layer." if detail.tab == "paint" else "Decal for the %s.") % detail.cat.label.to_lower()
	%SelDesc.text = cur.get("desc", fallback)
	if not current.valid: %SelDesc.text += "\nBuild invalid: " + "; ".join(current.reasons)

	apply_text_scale(_text_scale)


## Swap summary for equipping a part: the build before it and "old → new".
func _swap(verb: String, cat: Dictionary, item: Dictionary) -> Dictionary:
	var loadout: Dictionary = PlayerProfile.loadouts[PlayerProfile.active_bot]
	var comparison := GarageComparison.compare(PlayerProfile.registry, loadout, cat.slot, item.id)
	return {"base": comparison.current, "target": comparison.proposed,
		"caption": "%s %s · %s → %s" % [verb, cat.label, PlayerProfile.equipped_name("parts", cat), item.name]}


func _preview_swap(cat: Dictionary, item: Dictionary) -> void:
	if not is_inside_tree() or PlayerProfile.item_state("parts", cat, item) == "eq":
		_show_last_swap()
		return
	var swap := _swap("PREVIEW", cat, item)
	readout.show_change(swap.base, swap.target, swap.caption)


## Marks the last equipped swap while the draft is still its result.
func _show_last_swap() -> void:
	if not is_instance_valid(readout): return
	var loadout: Dictionary = PlayerProfile.loadouts[PlayerProfile.active_bot]
	if not _last_swap.is_empty() and _last_swap.loadout == loadout:
		readout.show_change(_last_swap.base, _last_swap.target, _last_swap.caption)
	else:
		readout.clear_change()


## Right-panel choice groups for the selected category. PARTS > ARMOR follows its
## armor package choices with one headed section per vehicle module category.
func _choice_groups(cat: Dictionary, ci: int) -> Array[Dictionary]:
	var groups: Array[Dictionary] = [{"tab": _tab, "index": ci, "cat": cat, "heading": ""}]
	if _tab == "parts" and cat.slot == "armor":
		groups[0].heading = "ARMOR PACKAGE"
		var modules: Array = PlayerProfile.catalogue.decals
		for index: int in modules.size():
			groups.append({"tab": "decals", "index": index, "cat": modules[index], "heading": modules[index].label})
	return groups


func _group_items(tab: String, cat: Dictionary) -> Array[int]:
	# Bodies stay selectable; other part slots list only choices that fit this build.
	var items: Array[int] = []
	for i in cat.items.size():
		if tab == "parts" and cat.slot != "chassis" and not PlayerProfile.part_fits(cat.slot, cat.items[i].id): continue
		items.append(i)
	if items.is_empty(): items.assign(range(cat.items.size()))
	return items


func _selected_item(group_key: String, tab: String, cat: Dictionary, items: Array[int]) -> int:
	var selected: int = _item.get(group_key, 0)
	if selected in items: return selected
	selected = items.front()
	for i: int in items:
		if PlayerProfile.item_state(tab, cat, cat.items[i]) == "eq": selected = i
	_item[group_key] = selected
	return selected


func _add_section_heading(text: String) -> void:
	# Each section starts on its own grid row; blank cells complete the rows.
	while %Items.get_child_count() % %Items.columns != 0: %Items.add_child(_grid_filler())
	var heading := Label.new()
	heading.text = text
	heading.theme_type_variation = &"Eyebrow"
	heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	%Items.add_child(heading)
	for _column in %Items.columns - 1: %Items.add_child(_grid_filler())


func _grid_filler() -> Control:
	var filler := Control.new()
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return filler


func _restore_scroll(key: String, value: int) -> void:
	if _scroll_key == key and is_instance_valid(_choice_scroll): _choice_scroll.scroll_vertical = value


## The tile for one catalogue choice, or null when it is not listed.
func choice_tile(tab: String, category: int, item: int) -> Control:
	return _tiles.get("%s:%d:%d" % [tab, category, item])


func _save_build() -> void:
	_commit_name()
	var result: Error = PlayerProfile.save_active(name_edit.text)
	if result == OK:
		%SelDesc.text = "Build saved to this computer."
	else:
		%SelDesc.text = "; ".join(PlayerProfile.errors)

func _commit_name() -> void:
	if is_inside_tree():
		PlayerProfile.rename_draft(name_edit.text)

func _focus_control(control: Control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()

var _pagination_frames := 4
var _pagination_geometry: Array = []

func _process(_delta: float) -> void:
	if not is_instance_valid(_choice_scroll) or not is_visible_in_tree(): return
	var geometry: Array = [size, $Layout/Header.size, $Layout/Footer.size, %Categories.size.x, %Items.size.x, %Items.get_child_count()]
	if geometry != _pagination_geometry:
		_pagination_geometry = geometry
		_pagination_frames = 4
	if _pagination_frames <= 0: return
	_pagination_frames -= 1
	var category_heights: Array[float] = []
	for row: Control in %Categories.get_children():
		var was_visible := row.visible
		row.show()
		row.size.x = %Categories.size.x
		row.get_node("Pad").size.x = row.size.x
		_measure_hidden_content(row.get_node("Pad"))
		row.visible = was_visible
		# Pad grows both ways; measuring must not leave it offset from its row.
		row.get_node("Pad").set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.custom_minimum_size.y = maxf(ceilf(82 * _text_scale), row.get_node("Pad").get_combined_minimum_size().y)
		category_heights.append(row.get_combined_minimum_size().y)
	for tile: Control in %Items.get_children():
		# Tiles are Buttons with a free child; size each to its scaled text.
		if not tile.has_node("Inner"): continue
		tile.size.x = (%Items.size.x - %Items.get_theme_constant("h_separation")) / %Items.columns
		tile.get_node("Inner").size.x = tile.size.x
		_measure_hidden_content(tile.get_node("Inner"))
		tile.custom_minimum_size.y = maxf(ceilf(TILE_HEIGHT * _text_scale), tile.get_node("Inner").get_combined_minimum_size().y)
		# Inner grows both ways; resizing it here shifted contents into neighbouring tiles.
		tile.get_node("Inner").set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_category_ranges = _pack_pages(category_heights, _page_budget(%Categories, _category_pager, false), _page_budget(%Categories, _category_pager, true), %Categories.get_theme_constant("separation"), 1)
	_category_page[_tab] = _page_for_item(_category_ranges, int(_cat[_tab]))
	var category_page: int = _category_page[_tab]
	var category_range := _category_ranges[category_page]
	_category_capacity = category_range.y - category_range.x
	for i in %Categories.get_child_count(): %Categories.get_child(i).visible = i >= category_range.x and i < category_range.y
	_category_pager.visible = _category_ranges.size() > 1
	_category_page_label.text = "Page %d of %d" % [category_page + 1, _category_ranges.size()]


func _page_budget(list: Container, pager: Control, with_pager: bool) -> float:
	# The screen bounds the budget; a list's expanding minimum must not feed it back.
	var body: MarginContainer = $Layout/Body
	var available: float = size.y - $Layout/Header.size.y - $Layout/Stripe.size.y - $Layout/Footer.size.y
	available -= body.get_theme_constant("margin_top") + body.get_theme_constant("margin_bottom")
	var column := list.get_parent() as VBoxContainer
	if column.get_parent() is PanelContainer:
		available -= column.get_parent().get_theme_stylebox("panel").get_minimum_size().y
	var siblings := 0
	for sibling: Control in column.get_children():
		if sibling == list or sibling == pager or not sibling.visible: continue
		available -= sibling.get_combined_minimum_size().y
		siblings += 1
	var separation := column.get_theme_constant("separation")
	available -= siblings * separation
	if with_pager: available -= pager.get_combined_minimum_size().y + separation
	return available


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
