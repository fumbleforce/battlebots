extends MenuScreen


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
	# Keep all eight primary actions within the existing 1080p design area.
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
	online.grab_focus()
