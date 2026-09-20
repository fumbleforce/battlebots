extends MenuScreen

func apply_text_scale(factor: float) -> void:
	preload("res://scripts/ui/menu_text_scale.gd").apply(self, factor)
	$Layout/Columns/NavigationScroll.custom_minimum_size.x = 900 if factor > 1.0 else 672
	%Play.custom_minimum_size.y = 130 if factor > 1.0 else 94
	for item: Button in [%JoinGame, %Practice, %Garage, %Settings]:
		var caption: Label = item.get_node("CaptionPad").get_child(0)
		if not item.has_meta("menu_action_text"):
			item.set_meta("menu_action_text", item.text)
		item.text = str(item.get_meta("menu_action_text")) + ("\n" + caption.text if factor > 1.0 else "")
		caption.visible = factor == 1.0
		item.custom_minimum_size.y = 128 if factor > 1.0 else 64
	%BotName.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%BotName.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%BotClass.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%BotClass.custom_minimum_size.x = 180
	%BotWeapon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_restore_focus_visibility.call_deferred()

func _restore_focus_visibility() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner()
	var scroll := $Layout/Columns/NavigationScroll as ScrollContainer
	if is_instance_valid(focused) and scroll.is_ancestor_of(focused):
		scroll.ensure_control_visible(focused)


func _ready() -> void:
	allow_back = false
	super()
	%Play.pressed.connect(MenuRouter.open_host)
	%JoinGame.pressed.connect(MenuRouter.open_join)
	%Practice.pressed.connect(MenuRouter.start_practice)
	%Garage.pressed.connect(MenuRouter.goto.bind("garage"))
	%Settings.pressed.connect(MenuRouter.open_settings)
	%Quit.pressed.connect(get_tree().quit)
	%CustomizeLink.pressed.connect(MenuRouter.goto.bind("customize"))
	var nav := %Play.get_parent()
	nav.move_child(%JoinGame, 1)
	nav.move_child(%Practice, 2)
	var online := Button.new()
	online.name = "PlayOnline"
	online.text = "PLAY ONLINE"
	online.theme_type_variation = &"MenuItemPrimary"
	online.custom_minimum_size.y = 82
	online.pressed.connect(MenuRouter.open_online)
	nav.add_child(online)
	online.owner = self
	online.unique_name_in_owner = true
	nav.move_child(online, 0)
	%Play.get_node("Pad/Row/Text/Label").text = "HOST LAN GAME"
	%Play.get_node("Pad/Row/Text/Label").add_theme_font_size_override("font_size", 36)
	%Play.get_node("Pad/Row/Text/Caption").text = "Local network · Direct IP"
	%JoinGame.text = "JOIN LAN GAME"
	# Larger text uses the same navigation list with focus-following scrolling.
	%Play.custom_minimum_size.y = 94
	for item: Button in [%JoinGame, %Practice, %Garage, %Settings, %Quit]:
		item.custom_minimum_size.y = 64

	%ProfileLevel.text = "LOCAL PILOT"
	%XpBar.hide()
	%GarageCaption.text = "%d bots · Customize" % PlayerProfile.bots.size()
	var bot: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	%BotImage.texture = bot.image
	%BotName.text = bot.name
	%BotClass.text = bot.cls
	%BotWeapon.text = bot.weapon
	%BotHull.text = "%s HP" % MenuData.fmt_int(bot.hp)
	var left := $Layout/Columns/Left
	var scroll := ScrollContainer.new()
	scroll.name = "NavigationScroll"
	scroll.custom_minimum_size.x = 672
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	$Layout/Columns.add_child(scroll)
	$Layout/Columns.move_child(scroll, 0)
	left.reparent(scroll)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	online.grab_focus()
