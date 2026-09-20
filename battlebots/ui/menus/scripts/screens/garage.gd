extends MenuScreen

const BOT_ROW := preload("res://ui/menus/components/bot_row.tscn")
var build_preview: GarageBotPreview
var recovery_panel: GarageRecoveryPanel
var recovery_button: Button
var notice: Label
var _text_factor := 1.0


func _ready() -> void:
	super()
	build_preview = GarageBotPreview.new()
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
	%Upgrade.pressed.connect(MenuRouter.goto.bind("shop"))
	%NewBot.pressed.connect(func(): PlayerProfile.new_build(); MenuRouter.goto("customize"))
	%Steps.hide()
	%Eyebrow.text = "YOUR BOTS · SELECT OR CUSTOMIZE"
	%Next.text = "DONE"
	%Next.pressed.connect(MenuRouter.goto.bind("main", false))
	_select(PlayerProfile.active_bot)
	var list: VBoxContainer = %BotList
	var list_parent := list.get_parent()
	var list_position := list.get_index()
	list_parent.remove_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_parent.add_child(scroll)
	list_parent.move_child(scroll,list_position)
	scroll.add_child(list)
	list.owner = self
	list.unique_name_in_owner = true
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recovery_panel = GarageRecoveryPanel.new()
	add_child(recovery_panel)
	recovery_button = Button.new()
	recovery_button.text = "SAVED FILE"
	recovery_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%Next.get_parent().add_child(recovery_button)
	recovery_button.pressed.connect(func(): recovery_panel.open(PlayerProfile))
	PlayerProfile.inventory_changed.connect(_refresh_builds)
	_refresh_builds()
	_prepare_text_layout()
	apply_text_scale(_text_factor)
	_focus_selected.call_deferred()

func _focus_selected() -> void:
	if not is_inside_tree() or recovery_panel.visible: return
	var rows := %BotList.get_children()
	if PlayerProfile.active_bot < rows.size(): rows[PlayerProfile.active_bot].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(recovery_panel) and recovery_panel.visible: return
	super(event)

func _refresh_builds() -> void:
	clear_children(%BotList)
	var group := ButtonGroup.new()
	for i in PlayerProfile.bots.size():
		var row := BOT_ROW.instantiate()
		%BotList.add_child(row)
		row.setup(PlayerProfile.bots[i])
		var pad: Control = row.get_node("Pad")
		pad.minimum_size_changed.connect(_fit_button_content.bind(row, pad))
		row.button_group = group
		row.pressed.connect(_select.bind(i))
		row.button_pressed = i == PlayerProfile.active_bot
	%Bays.text = "%d builds · 12 saved max" % PlayerProfile.bots.size()
	notice.text = "; ".join(PlayerProfile.errors)
	notice.visible = not notice.text.is_empty()
	_select(PlayerProfile.active_bot)
	apply_text_scale(_text_factor)


func _select(i: int) -> void:
	PlayerProfile.active_bot = i
	MenuRouter.match_setup.bot = i
	var b: Dictionary = PlayerProfile.bots[i]
	build_preview.show_loadout(PlayerProfile.loadouts[i])
	%BotImage.texture = b.image
	%BotClass.text = "VALID BUILD · 3D PREVIEW" if b.valid else b.cls
	if b.get("retained", false): %BotClass.text = b.cls
	%BotName.text = b.name
	%BotHp.text = "%s core HP" % MenuData.fmt_int(b.hp) if b.valid else "Stats unavailable"
	%Pips.get_parent().hide()
	%Next.disabled = false
	%Stats.visible = b.valid
	%Bays.tooltip_text = "; ".join(PlayerProfile.errors)
	%Upgrade.text = "PART CATALOGUE"
	var j := 0
	for pip in %Pips.get_children():
		pip.theme_type_variation = &"PipOn" if j < b.shields else &"Pip"
		j += 1
	%Weapon.text = b.weapon
	%Ability.text = b.ability
	%Boost.text = b.boost
	var bars := %Stats.get_children()
	for k in MenuData.STAT_KEYS.size():
		var key: String = MenuData.STAT_KEYS[k]
		bars[k].set_stat(key, b.stats[key], 0, b.stats[key] >= 80)


func _prepare_text_layout() -> void:
	var frame: Control = %BotImage.get_parent()
	var overlay: Control = %Customize.get_parent()
	overlay.reparent(frame.get_parent())
	frame.get_parent().move_child(overlay, 0)
	frame.custom_minimum_size.y = 340
	for button: Button in [%Customize, %Upgrade]:
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
	# Growing content scrolls while footer actions remain available.
	var body: Control = $Layout/Body
	var position := body.get_index()
	var scroll := ScrollContainer.new()
	scroll.name = "GarageBodyScroll"
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	$Layout.add_child(scroll)
	$Layout.move_child(scroll, position)
	body.reparent(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.y = 740


func apply_text_scale(factor: float) -> void:
	_text_factor = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
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
