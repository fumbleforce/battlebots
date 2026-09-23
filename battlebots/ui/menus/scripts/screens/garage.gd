extends MenuScreen

const BOT_ROW := preload("res://ui/menus/components/bot_row.tscn")
const THUMBNAIL_RENDERER := preload("res://scripts/presentation/garage_bot_thumbnail_renderer.gd")
const CHEVRON_LEFT := preload("res://ui/menus/icons/chevron_left.svg")
const CHEVRON_RIGHT := preload("res://ui/menus/icons/chevron_right.svg")
const WRENCH := preload("res://ui/menus/icons/wrench.svg")
const AMBER := BuildReadout.AMBER
const GOOD := BuildReadout.GOOD
const BAD := BuildReadout.BAD
## Selected build: status, name, live preview and stat strip.
@onready var readout: BuildReadout = $Layout/Body/Row/Preview
var customize_button: Button
var build_preview: GarageBotPreview
var thumbnail_renderer: GarageBotThumbnailRenderer
var recovery_panel: GarageRecoveryPanel
var recovery_button: Button
var save_status: Label
var notice: Label
var _save_badge: HBoxContainer
var _save_dot: Panel
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
	build_preview = BuildReadout.Preview.new()
	readout.attach_preview(build_preview)
	customize_button = Button.new()
	customize_button.name = "Customize"
	customize_button.text = "CUSTOMIZE"
	customize_button.icon = WRENCH
	readout.add_action(customize_button)
	thumbnail_renderer = THUMBNAIL_RENDERER.new()
	add_child(thumbnail_renderer)
	thumbnail_renderer.thumbnail_ready.connect(_thumbnail_ready)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_color_override("font_color", BAD)
	%BotList.get_parent().add_child(notice)
	%BotList.get_parent().move_child(notice, %BotList.get_index() + 1)
	customize_button.pressed.connect(MenuRouter.goto.bind("customize"))
	# Each loadout row opens Customize at the part slot it summarises.
	for link: Array in [[%WeaponSlot, "weapon"], [%AbilitySlot, "utility"], [%BoostSlot, "nitro"]]:
		link[0].pressed.connect(_open_customize.bind(link[1]))
		link[0].tooltip_text = "Change in Customize"
	%NewBot.pressed.connect(func(): PlayerProfile.new_build(); MenuRouter.goto("customize"))
	%Eyebrow.text = "YOUR BOTS · SELECT OR CUSTOMIZE"
	%Next.text = "DONE"
	%Next.pressed.connect(MenuRouter.goto.bind("main", false))
	recovery_panel = GarageRecoveryPanel.new()
	add_child(recovery_panel)
	_save_badge = HBoxContainer.new()
	_save_badge.add_theme_constant_override("separation", 10)
	_save_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save_dot = Panel.new()
	_save_dot.custom_minimum_size = Vector2(10, 10)
	_save_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_badge.add_child(_save_dot)
	save_status = Label.new()
	save_status.theme_type_variation = &"Subheading"
	save_status.add_theme_font_size_override("font_size", 20)
	save_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save_status.mouse_filter = Control.MOUSE_FILTER_PASS
	_save_badge.add_child(save_status)
	%Next.get_parent().add_child(_save_badge)
	%Next.get_parent().move_child(_save_badge, %Next.get_index())
	recovery_button = Button.new()
	recovery_button.text = "SAVED FILE"
	recovery_button.theme_type_variation = &"TextLink"
	recovery_button.add_theme_font_size_override("font_size", 18)
	recovery_button.add_theme_color_override("font_color", Color("#9aa6b5"))
	recovery_button.tooltip_text = "Review saved builds and recover a backup"
	recovery_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%Next.get_parent().add_child(recovery_button)
	%Next.get_parent().move_child(recovery_button, %Next.get_index())
	recovery_button.pressed.connect(func(): recovery_panel.open(PlayerProfile))
	PlayerProfile.inventory_changed.connect(_refresh_builds)
	_prepare_text_layout()
	_build_page = _page_for_item(_build_ranges, PlayerProfile.active_bot)
	_refresh_builds()
	apply_text_scale(_text_factor)
	_focus_selected.call_deferred()

func _open_customize(slot: String) -> void:
	CustomizeRequest.slot = slot
	MenuRouter.goto("customize")


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
		_style_row(row)
		var state := _save_state(i)
		var status: Label = row.get_node("%Class")
		status.add_theme_color_override("font_color", GOOD if PlayerProfile.bots[i].valid else BAD)
		if state != "" and PlayerProfile.bots[i].valid:
			status.text = state
			status.add_theme_color_override("font_color", AMBER)
		if PlayerProfile.bots[i].valid:
			var key := GarageBotThumbnailRenderer.visual_key(PlayerProfile.loadouts[i])
			row.set_meta("thumbnail_key", key)
			var cached := thumbnail_renderer.cached(key)
			if cached != null: row.set_thumbnail(cached)
		row.visible = i >= _build_ranges[_build_page].x and i < _build_ranges[_build_page].y
		var pad: Control = row.get_node("Pad")
		pad.minimum_size_changed.connect(_fit_button_content.bind(row, pad))
		row.button_group = group
		row.pressed.connect(_select.bind(i))
		row.button_pressed = i == PlayerProfile.active_bot
	var valid_drafts: Array = []
	for i in PlayerProfile.bots.size():
		if PlayerProfile.bots[i].valid: valid_drafts.append(PlayerProfile.loadouts[i])
	thumbnail_renderer.sync(valid_drafts)
	%Bays.text = "%d builds · 12 saved max" % PlayerProfile.bots.size()
	notice.text = "Build/file needs attention. Inspect SAVED FILE or customize the selected build." if not PlayerProfile.errors.is_empty() else ""
	notice.visible = not notice.text.is_empty()
	_page_label.text = "Page %d of %d" % [_build_page + 1, _build_ranges.size()]
	_build_pager.get_child(0).disabled = _build_page == 0
	_build_pager.get_child(2).disabled = _build_page + 1 >= _build_ranges.size()
	_select(PlayerProfile.active_bot)
	apply_text_scale(_text_factor)


func _thumbnail_ready(key: String, texture: Texture2D) -> void:
	for row: Button in %BotList.get_children():
		if row.get_meta("thumbnail_key", "") == key: row.set_thumbnail(texture)


func _select(i: int) -> void:
	PlayerProfile.active_bot = i
	_displayed_active = i
	MenuRouter.match_setup.bot = i
	var b: Dictionary = PlayerProfile.bots[i]
	readout.show_build(b, PlayerProfile.loadouts[i])
	%Next.disabled = false
	%Bays.tooltip_text = "; ".join(PlayerProfile.errors)
	_update_save_status(i)
	var parts: Dictionary = PlayerProfile.loadouts[i].get("parts", {}) if PlayerProfile.loadouts[i].get("parts") is Dictionary else {}
	var input := InputPreferences.load_file()
	%Weapon.text = b.weapon
	%Ability.text = b.ability
	%Boost.text = b.boost
	_set_key(%WeaponSlot.get_node("Pad/Row/Key"), input.label_for(&"primary"))
	var utility: String = str(parts.get("utility", ""))
	var auxiliary_label: String = {"minigun_pod":"AUXILIARY GUN", "turret_cannon":"TURRET CANNON", "turret_plasma":"TURRET PLASMA",
		"turret_cannon_dual":"TWIN CANNON", "turret_cannon_quad":"QUAD CANNON",
		"turret_plasma_dual":"TWIN PLASMA", "turret_plasma_quad":"QUAD PLASMA"}.get(utility, "")
	var has_auxiliary := not auxiliary_label.is_empty()
	# Turret builds use tank controls: the primary button fires the main gun.
	var auxiliary_action: StringName = &"primary" if utility.begins_with("turret_") else &"secondary"
	_set_key(%AbilitySlot.get_node("Pad/Row/Key"), input.label_for(auxiliary_action) if has_auxiliary else "—")
	%AbilitySlot.get_node("Pad/Row/Text/Label").text = auxiliary_label if has_auxiliary else "UTILITY"
	_show_perks(parts, input)


func _show_perks(parts: Dictionary, input: InputPreferences) -> void:
	clear_children(%Perks)
	var perks: Array = []
	if parts.get("nitro") == "nitro_boost": perks.append(["Nitro", input.label_for(&"nitro")])
	if parts.get("suspension") == "charged_jump": perks.append(["Jump", input.label_for(&"jump")])
	for perk: Array in perks:
		if %Perks.get_child_count() > 0:
			var rule := ColorRect.new()
			rule.color = Color("262c35")
			rule.custom_minimum_size.y = 1
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			%Perks.add_child(rule)
		%Perks.add_child(_perk_row(perk[0], perk[1]))
	%Boost.visible = perks.is_empty()
	%Perks.visible = not perks.is_empty()
	MenuTextScale.apply(%Perks, _text_factor)
	_fit_button_content.call_deferred(%BoostSlot, %BoostSlot.get_node("Pad"))


func _perk_row(title: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"Subheading"
	label.add_theme_font_size_override("font_size", 34)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(60, 40)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_stylebox_override("panel", %WeaponSlot.get_node("Pad/Row/Key").get_theme_stylebox("panel"))
	var key_label := Label.new()
	key_label.name = "L"
	key_label.theme_type_variation = &"KeyLabel"
	key_label.add_theme_font_size_override("font_size", 16)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(key_label)
	row.add_child(cap)
	_set_key(cap, key)
	return row


func _set_key(cap: PanelContainer, text: String) -> void:
	var label: Label = cap.get_node("L")
	label.text = text
	# Slots without a binding read as a dim placeholder rather than a key.
	var unbound := text == "—" or text == "Unbound"
	cap.self_modulate = Color(1, 1, 1, 0.35) if unbound else Color.WHITE
	label.add_theme_color_override("font_color", Color("8b949e") if unbound else Color("e9ebee"))


func _style_row(row: Button) -> void:
	var looks := {
		"normal": [Color("161a20"), Color("262c35"), 1],
		"hover": [Color("1b2027"), Color("3a424d"), 1],
		"pressed": [Color("1d1a12"), AMBER, 2],
		"hover_pressed": [Color("211d13"), AMBER, 2],
		"disabled": [Color("161a20"), Color("262c35"), 1]}
	for state: String in looks:
		var box := StyleBoxFlat.new()
		box.bg_color = looks[state][0]
		box.border_color = looks[state][1]
		box.set_border_width_all(looks[state][2])
		box.set_corner_radius_all(8)
		row.add_theme_stylebox_override(state, box)
	row.get_node("%Thumb").custom_minimum_size = Vector2(84, 64)


func _save_state(index: int) -> String:
	if PlayerProfile.bots[index].get("retained", false): return "UNSAVED COPY"
	if index >= PlayerProfile._save_indices.size(): return "NEW · NOT SAVED"
	if PlayerProfile._save_indices[index] < 0 and index >= PlayerProfile.PRESET_COUNT:
		return "NEW · NOT SAVED"
	if index < PlayerProfile._draft_baseline.size() and not PlayerProfile._same_draft(PlayerProfile.loadouts[index], PlayerProfile._draft_baseline[index]):
		return "UNSAVED CHANGES"
	return ""


func _update_save_status(index: int) -> void:
	if not is_instance_valid(save_status): return
	var state := _save_state(index)
	var color := BAD if PlayerProfile._read_errors else AMBER
	if PlayerProfile._read_errors: state = "SAVED FILE NEEDS REVIEW"
	save_status.add_theme_color_override("font_color", color)
	var dot := StyleBoxFlat.new()
	dot.bg_color = color
	dot.set_corner_radius_all(5)
	_save_dot.add_theme_stylebox_override("panel", dot)
	save_status.text = state
	save_status.visible = not state.is_empty()
	_save_badge.visible = save_status.visible
	save_status.tooltip_text = "Open Saved File to review the file before saving." if PlayerProfile._read_errors else "Use Customize → Save Build to store this build locally. Done returns to the menu."


func _prepare_text_layout() -> void:
	for label: Label in [%Weapon, %Ability, %Boost]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for slot: Control in [%WeaponSlot, %AbilitySlot, %BoostSlot]:
		var pad: Control = slot.get_node("Pad")
		pad.minimum_size_changed.connect(_fit_button_content.bind(slot, pad))
	_build_pager = HBoxContainer.new()
	_build_pager.add_theme_constant_override("separation", 12)
	%BotList.get_parent().add_child(_build_pager)
	%BotList.get_parent().move_child(_build_pager, %BotList.get_index() + 1)
	var previous := Button.new()
	previous.icon = CHEVRON_LEFT
	previous.tooltip_text = "Previous page"
	previous.pressed.connect(_page_builds.bind(-1))
	_build_pager.add_child(previous)
	_page_label = Label.new()
	_page_label.theme_type_variation = &"Muted"
	_page_label.add_theme_font_size_override("font_size", 18)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_build_pager.add_child(_page_label)
	var next := Button.new()
	next.icon = CHEVRON_RIGHT
	next.tooltip_text = "Next page"
	next.pressed.connect(_page_builds.bind(1))
	_build_pager.add_child(next)
	for arrow: Button in [previous, next]:
		arrow.theme_type_variation = &"IconButton"
		arrow.custom_minimum_size = Vector2(56, 56)
		arrow.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER


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
		_fit_button_content.call_deferred(row, row.get_node("Pad"))
	for slot: Control in [%WeaponSlot, %AbilitySlot, %BoostSlot]:
		_fit_button_content.call_deferred(slot, slot.get_node("Pad"))


func _fit_button_content(button: Control, pad: Control) -> void:
	if is_instance_valid(button) and is_instance_valid(pad):
		var floor_height := 96.0 if button.get_parent() == %BotList else 106.0
		button.custom_minimum_size.y = maxf(floor_height, pad.get_combined_minimum_size().y)

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
	var available: float = size.y - $Layout/Header.size.y - $Layout/Stripe.size.y - $Layout/Footer.size.y
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
	_page_label.text = "Page %d of %d" % [_build_page + 1, ranges.size()]
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
