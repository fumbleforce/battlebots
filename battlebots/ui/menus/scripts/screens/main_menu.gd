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

	%ProfileLevel.text = "LOCAL PILOT"
	%XpBar.hide()
	%GarageCaption.text = "%d bots · Customize" % PlayerProfile.bots.size()
	var bot: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	%BotImage.texture = bot.image
	%BotName.text = bot.name
	%BotClass.text = bot.cls
	%BotWeapon.text = bot.weapon
	%BotHull.text = "%s HP" % MenuData.fmt_int(bot.hp)
	%Play.grab_focus()
