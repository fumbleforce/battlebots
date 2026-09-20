extends MenuScreen
## Canonical parts and paint editing; draft history and saves belong to PlayerProfile.

const CATEGORY_ROW := preload("res://ui/menus/components/category_row.tscn")
const ITEM_TILE := preload("res://ui/menus/components/item_tile.tscn")
const TABS := ["parts", "paint", "decals"]
const SLOT_HEADINGS := {"parts": "PART SLOTS", "paint": "PAINT LAYERS", "decals": "VEHICLE MODULES"}

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
var _text_scale := 1.0
var _choice_pages: Dictionary = {}
var _choice_page_label: Label
var _choice_pager: HBoxContainer
var _show_details := false
var _category_page := {"parts": 0, "paint": 0, "decals": 0}
var _category_pager: HBoxContainer
var _category_page_label: Label
var _category_capacity := 3
var _choice_capacity := 2
var _choice_layout_capacity: Dictionary = {}
var _category_ranges: Array[Vector2i] = [Vector2i(0, 3)]
var _choice_ranges: Array[Vector2i] = [Vector2i(0, 2)]
var _color_picker: ColorPickerButton

func apply_text_scale(factor: float) -> void:
	_pagination_frames = 4
	_text_scale = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	MenuTextScale.apply(self, _text_scale)
	$Layout/Header.custom_minimum_size.y = 115 if _text_scale == 1.0 else 160
	if not is_instance_valid(build_preview): return
	build_preview.apply_text_scale(_text_scale)
	comparison_panel.apply_text_scale(_text_scale)
	if is_instance_valid(recovery_panel): recovery_panel.apply_text_scale(_text_scale)
	%BotImage.get_parent().custom_minimum_size.y = 300 if _text_scale == 1.0 else 180
	for row: Control in %Categories.get_children():
		row.custom_minimum_size.y = ceilf(82 * _text_scale)
		row.get_node("%Current").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for tile: Control in %Items.get_children():
		tile.custom_minimum_size.y = ceilf(150 * _text_scale)
		tile.get_node("Inner/Col/ArtBox").custom_minimum_size.y = 40
		tile.get_node("%Name").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _change_choice_page(direction: int) -> void:
	var key := "%s:%d" % [_tab, _cat[_tab]]
	_choice_pages[key] = wrapi(int(_choice_pages.get(key, 0)) + direction, 0, maxi(1, _choice_ranges.size()))
	_refresh()

func _show_choice_details(value: bool) -> void:
	_show_details = value
	%Items.visible = not value
	_choice_pager.visible = not value and _choice_ranges.size() > 1
	%SelDesc.get_parent().visible = value

func _show_preview_stats(value: bool) -> void:
	build_preview.get_parent().visible = not value
	comparison_panel.visible = value


func _ready() -> void:
	super()
	%TabDecals.text = "VEHICLE"
	%Categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_category_pager = HBoxContainer.new()
	%Categories.get_parent().add_child(_category_pager)
	%Categories.get_parent().move_child(_category_pager, %Categories.get_index() + 1)
	for direction: int in [-1, 1]:
		var button := Button.new()
		button.text = "PREV" if direction < 0 else "NEXT"
		_category_pager.add_child(button)
		button.pressed.connect(func():
			_category_page[_tab] = wrapi(_category_page[_tab] + direction, 0, maxi(1, _category_ranges.size()))
			_cat[_tab] = _category_ranges[_category_page[_tab]].x
			_refresh())
		if direction < 0:
			_category_page_label = Label.new()
			_category_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_category_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_category_pager.add_child(_category_page_label)
	_color_picker = ColorPickerButton.new()
	_color_picker.text = "CUSTOM COLOR"
	_color_picker.edit_alpha = false
	%Items.get_parent().add_child(_color_picker)
	_color_picker.popup_closed.connect(func():
		var category: Dictionary = PlayerProfile.catalogue[_tab][_cat[_tab]]
		if _tab == "paint" and category.slot != "paint": PlayerProfile.set_sawblade_color(category.slot, _color_picker.color))
	var options := %Items.get_parent()
	var view_tabs := HBoxContainer.new()
	options.add_child(view_tabs)
	options.move_child(view_tabs, %Items.get_index())
	for caption: String in ["CHOICES", "DETAILS"]:
		var button := Button.new()
		button.text = caption
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view_tabs.add_child(button)
		button.pressed.connect(_show_choice_details.bind(caption == "DETAILS"))
	_choice_pager = HBoxContainer.new()
	options.add_child(_choice_pager)
	options.move_child(_choice_pager, %Items.get_index() + 1)
	var previous := Button.new()
	previous.text = "PREVIOUS"
	previous.pressed.connect(_change_choice_page.bind(-1))
	_choice_pager.add_child(previous)
	_choice_page_label = Label.new()
	_choice_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_pager.add_child(_choice_page_label)
	var next := Button.new()
	next.text = "NEXT"
	next.pressed.connect(_change_choice_page.bind(1))
	_choice_pager.add_child(next)
	%Items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	%SelDesc.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	options.get_node("Line").hide()
	%SelName.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%CatLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%CatLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Eyebrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Eyebrow.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Eyebrow.get_parent().size_flags_vertical = Control.SIZE_FILL
	$Layout/Header/Row/SpacerL.size_flags_horizontal = Control.SIZE_FILL
	$Layout/Header/Row/SpacerR.hide()
	$Layout/Header/Row/Sep.hide()
	$Layout/Header/Row/Scrap.hide()
	build_preview = GarageBotPreview.new()
	var frame := %BotImage.get_parent()
	%BotImage.hide()
	frame.add_child(build_preview)
	frame.move_child(build_preview, 1)
	frame.get_node("PreviewChip").hide()
	frame.custom_minimum_size.y = 300
	comparison_panel = GarageComparisonPanel.new()
	comparison_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_column := frame.get_parent()
	preview_column.add_child(comparison_panel)
	preview_column.move_child(comparison_panel, %Stats.get_index())
	var preview_tabs := HBoxContainer.new()
	preview_column.add_child(preview_tabs)
	preview_column.move_child(preview_tabs, frame.get_index())
	var preview_group := ButtonGroup.new()
	for title: String in ["MODEL", "STATS"]:
		var button := Button.new()
		button.text = title
		button.toggle_mode = true
		button.button_group = preview_group
		button.button_pressed = title == "MODEL"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview_tabs.add_child(button)
		button.pressed.connect(_show_preview_stats.bind(title == "STATS"))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comparison_panel.hide()
	$Layout/Footer/Row/Hint1.hide()
	var bot: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	name_edit = LineEdit.new()
	name_edit.name = "BuildName"
	name_edit.text = bot.name
	name_edit.placeholder_text = "Build name (1–48 characters)"
	name_edit.max_length = 48
	%Save.get_parent().add_child(name_edit)
	name_edit.custom_minimum_size.x = 240
	name_edit.tooltip_text = "Saved build name"
	name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_edit.custom_minimum_size.y = 48
	name_edit.tooltip_text = "Enter a name, then press Enter or leave this field to apply it to the draft. Save writes it to this computer."
	name_edit.text_submitted.connect(func(_value: String) -> void: _commit_name())
	name_edit.focus_exited.connect(_commit_name)
	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 12)
	$Layout/Body/Row/Preview/Col.add_child(history)
	undo_button = Button.new()
	undo_button.text = "UNDO"
	undo_button.tooltip_text = "Undo build edit (Ctrl+Z). Saved files change only when you Save."
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.add_child(undo_button)
	undo_button.pressed.connect(PlayerProfile.undo_edit)
	redo_button = Button.new()
	redo_button.text = "REDO"
	redo_button.tooltip_text = "Redo build edit (Ctrl+Y or Ctrl+Shift+Z)."
	redo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.add_child(redo_button)
	redo_button.pressed.connect(PlayerProfile.redo_edit)
	revalidate_button = Button.new()
	revalidate_button.text = "REVALIDATE"
	revalidate_button.tooltip_text = "Use the current loadout format and catalogue with your existing part IDs and paint. No parts are substituted. Undo is available; Save writes the repaired draft."
	revalidate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.add_child(revalidate_button)
	revalidate_button.pressed.connect(PlayerProfile.revalidate_active)
	for control: Node in find_children("Rotate","Button",true,false):
		control.tooltip_text = "Reset build preview view"
		control.pressed.connect(build_preview.reset_view)
	%Eyebrow.text = "%s · %s" % [bot.name, bot.cls]
	%BotImage.texture = bot.image
	var group := ButtonGroup.new()
	var tab_buttons := [%TabParts, %TabPaint, %TabDecals]
	for i in TABS.size():
		tab_buttons[i].button_group = group
		tab_buttons[i].pressed.connect(_set_tab.bind(TABS[i]))
	%TabParts.button_pressed = true
	%Action.pressed.connect(_on_action)
	%Save.pressed.connect(_save_build)
	%ShopLink.hide()
	PlayerProfile.inventory_changed.connect(_refresh)
	_refocus = "item"
	_refresh()
	recovery_panel = GarageRecoveryPanel.new()
	add_child(recovery_panel)
	recovery_button = Button.new()
	recovery_button.text = "SAVED FILE"
	recovery_button.add_theme_font_size_override("font_size", 20)
	recovery_button.tooltip_text = "Reload saved builds without losing drafts, or review a recovery backup."
	recovery_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%Save.get_parent().add_child(recovery_button)
	$Layout/Footer/Row/Hint0.hide()
	recovery_button.pressed.connect(func():
		_commit_name()
		recovery_panel.open(PlayerProfile))
	apply_text_scale(_text_scale)


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
	build_preview.show_loadout(PlayerProfile.loadouts[PlayerProfile.active_bot])
	if not name_edit.has_focus(): name_edit.text = current.name
	undo_button.disabled = not PlayerProfile.can_undo()
	redo_button.disabled = not PlayerProfile.can_redo()
	revalidate_button.visible = PlayerProfile.needs_revalidation()
	%Eyebrow.text = current.name + " · " + ("EQUIPPED DRAFT" if current.valid else "REPAIR REQUIRED")
	if current.get("retained", false): %Eyebrow.text += " · UNSAVED COPY"
	%Save.disabled = not current.valid
	var cats: Array = PlayerProfile.catalogue[_tab]
	var ci: int = _cat[_tab]
	var cat: Dictionary = cats[ci]
	_category_page_label.text = "%d / %d" % [_category_page[_tab] + 1, _category_ranges.size()]
	_color_picker.visible = _tab == "paint" and cat.slot != "paint" and SawbladeConfig.enabled(PlayerProfile.loadouts[PlayerProfile.active_bot])
	if _color_picker.visible:
		var rgba: Array = PlayerProfile.loadouts[PlayerProfile.active_bot].cosmetics.sawblade[cat.slot]
		_color_picker.color = Color(rgba[0], rgba[1], rgba[2], 1).linear_to_srgb()
	var key := "%s:%d" % [_tab, ci]
	var ii: int = _item.get(key, 0)
	var choice_page: int = _choice_pages.get(key, 0)
	_choice_page_label.text = "%d / %d" % [choice_page + 1, _choice_ranges.size()]
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

	clear_children(%Items)
	var ig := ButtonGroup.new()
	var owned_count := 0
	for i in cat.items.size():
		var it: Dictionary = cat.items[i]
		var st := PlayerProfile.item_state(_tab, cat, it)
		if st == "eq" or st == "own":
			owned_count += 1
		var tile := ITEM_TILE.instantiate()
		%Items.add_child(tile)
		tile.setup(it, st)
		tile.button_group = ig
		tile.button_pressed = i == ii
		var shown_choices := _choice_ranges[clampi(choice_page, 0, _choice_ranges.size() - 1)]
		tile.visible = i >= shown_choices.x and i < shown_choices.y
		tile.pressed.connect(func():
			_item[key] = i
			_choice_pages[key] = _page_for_item(_choice_ranges, i)
			_refocus = "item"
			_refresh())
		if _refocus == "item" and i == ii:
			_focus_control.call_deferred(tile)
	_refocus = ""

	%CatLabel.text = cat.label
	%Count.text = "%d / %d available" % [owned_count, cat.items.size()]
	var cur: Dictionary = cat.items[ii]
	var comparison_slot: String = cat.slot if _tab == "parts" else "chassis"
	var selected_parts: Variant = PlayerProfile.loadouts[PlayerProfile.active_bot].get("parts", {})
	var candidate_id := ""
	if _tab == "parts": candidate_id = str(cur.id)
	elif selected_parts is Dictionary: candidate_id = str(selected_parts.get("chassis", ""))
	var comparison := GarageComparison.compare(PlayerProfile.registry, PlayerProfile.loadouts[PlayerProfile.active_bot], comparison_slot, candidate_id)
	comparison_panel.render(comparison, str(cur.name), _tab == "parts")
	var state := PlayerProfile.item_state(_tab, cat, cur)
	%SelName.text = cur.name
	%PreviewName.text = cur.name
	var fallback := ("Applies to the %s layer." if _tab == "paint" else "Decal for the %s.") % cat.label.to_lower()
	%SelDesc.text = cur.get("desc", fallback)
	if not current.valid: %SelDesc.text += "\nBuild invalid: " + "; ".join(current.reasons)
	if _tab == "parts" and not comparison.proposed.valid:
		%SelDesc.text += "\nProposed build: " + "; ".join(comparison.proposed.reasons)
	match state:
		"eq":
			%Action.text = "EQUIPPED"
			%Action.disabled = true
		"lock":
			%Action.text = "UNAVAILABLE"
			%Action.disabled = true
		"own":
			%Action.text = "EQUIP"
			%Action.disabled = false
		_:
			%Action.text = "UNAVAILABLE"
			%Action.disabled = true

	%Stats.hide()
	%CosmeticNote.hide()
	_show_choice_details(_show_details)
	apply_text_scale(_text_scale)


func _on_action() -> void:
	var cat: Dictionary = PlayerProfile.catalogue[_tab][_cat[_tab]]
	var cur: Dictionary = cat.items[_item.get("%s:%d" % [_tab, _cat[_tab]], 0)]
	_refocus = "item"
	match PlayerProfile.item_state(_tab, cat, cur):
		"own":
			PlayerProfile.equip(_tab, cat, cur)


func _save_build() -> void:
	_commit_name()
	var result: Error = PlayerProfile.save_active(%Save.get_parent().get_node("BuildName").text)
	if result == OK:
		%SelDesc.text = "Build saved to this computer."
	else:
		%SelDesc.text = "; ".join(PlayerProfile.errors)
	_show_choice_details(true)

func _commit_name() -> void:
	if is_inside_tree():
		PlayerProfile.rename_draft(name_edit.text)

func _focus_control(control: Control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()

var _pagination_frames := 4
var _pagination_geometry: Array = []

func _process(_delta: float) -> void:
	if not is_instance_valid(_choice_pager) or not is_visible_in_tree(): return
	var geometry: Array = [size, $Layout/Header.size, $Layout/Footer.size, %Categories.size.x, %Items.size.x, _show_details]
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
		row.custom_minimum_size.y = maxf(ceilf(82 * _text_scale), row.get_node("Pad").get_combined_minimum_size().y)
		category_heights.append(row.get_combined_minimum_size().y)
	var choice_heights: Array[float] = []
	for tile: Control in %Items.get_children():
		var was_visible := tile.visible
		tile.show()
		tile.size.x = (%Items.size.x - %Items.get_theme_constant("h_separation")) / %Items.columns
		tile.get_node("Inner").size.x = tile.size.x
		_measure_hidden_content(tile.get_node("Inner"))
		tile.visible = was_visible
		tile.custom_minimum_size.y = maxf(ceilf(150 * _text_scale), tile.get_node("Inner").get_combined_minimum_size().y)
		tile.get_node("Inner").size.y = tile.custom_minimum_size.y
		choice_heights.append(tile.get_combined_minimum_size().y)
	_category_ranges = _pack_pages(category_heights, _page_budget(%Categories, _category_pager, false), _page_budget(%Categories, _category_pager, true), %Categories.get_theme_constant("separation"), 1)
	_choice_ranges = _pack_pages(choice_heights, _page_budget(%Items, _choice_pager, false), _page_budget(%Items, _choice_pager, true), %Items.get_theme_constant("v_separation"), %Items.columns)
	_category_page[_tab] = _page_for_item(_category_ranges, int(_cat[_tab]))
	var choice_key := "%s:%d" % [_tab, _cat[_tab]]
	if _choice_layout_capacity.get(choice_key, []) != _choice_ranges:
		_choice_layout_capacity[choice_key] = _choice_ranges.duplicate()
		_choice_pages[choice_key] = _page_for_item(_choice_ranges, int(_item.get(choice_key, 0)))
	var category_page: int = _category_page[_tab]
	var category_range := _category_ranges[category_page]
	_category_capacity = category_range.y - category_range.x
	for i in %Categories.get_child_count(): %Categories.get_child(i).visible = i >= category_range.x and i < category_range.y
	_category_pager.visible = _category_ranges.size() > 1
	_category_page_label.text = "%d / %d" % [category_page + 1, _category_ranges.size()]
	var page := clampi(int(_choice_pages.get(choice_key, 0)), 0, _choice_ranges.size() - 1)
	_choice_pages[choice_key] = page
	var choice_range := _choice_ranges[page]
	_choice_capacity = choice_range.y - choice_range.x
	for i in %Items.get_child_count(): %Items.get_child(i).visible = i >= choice_range.x and i < choice_range.y
	_choice_pager.visible = not _show_details and _choice_ranges.size() > 1
	_choice_page_label.text = "%d / %d" % [page + 1, _choice_ranges.size()]


func _page_budget(list: Container, pager: Control, with_pager: bool) -> float:
	# The screen bounds the budget; a list's expanding minimum must not feed it back.
	var body: MarginContainer = $Layout/Body
	var available: float = size.y - $Layout/Header.size.y - $Layout/Footer.size.y
	available -= body.get_theme_constant("margin_top") + body.get_theme_constant("margin_bottom")
	var column := list.get_parent() as VBoxContainer
	if column.get_parent() is PanelContainer:
		available -= column.get_parent().get_theme_stylebox("panel").get_minimum_size().y
	var siblings := 0
	for sibling: Control in column.get_children():
		if sibling == list or sibling == pager or not sibling.visible: continue
		if sibling == %SelDesc.get_parent(): continue
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
