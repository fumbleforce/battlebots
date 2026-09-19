extends MenuScreen


func _ready() -> void:
	allow_back = false
	super()
	%Play.pressed.connect(MenuRouter.goto.bind("mode_select"))
	%Garage.pressed.connect(MenuRouter.goto.bind("garage"))
	%Shop.pressed.connect(MenuRouter.goto.bind("shop"))
	%Career.disabled = true
	%Career.tooltip_text = "Career progression is not available yet."
	%Settings.pressed.connect(MenuRouter.open_settings)
	%Quit.pressed.connect(get_tree().quit)
	%CustomizeLink.pressed.connect(MenuRouter.goto.bind("customize"))

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
