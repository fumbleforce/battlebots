extends MenuScreen
## Read-only loading status. The persistent game root owns all phase navigation.
const SPINNER_ART := preload("res://ui/menus/art/bot_chevron.jpg")
const LIFTER_ART := preload("res://ui/menus/art/bot_rivetrex.jpg")
var _blue_image2: TextureRect

func _ready() -> void:
	allow_back = false
	super()
	%Progress.hide()
	$Bottom/Col/Row/Tip.text = "[color=#F5B82E][b]TIP[/b][/color] Hold SPACE to brake. Weapons unlock when the server starts the round."
	$BlueTeam/Row2/Frame/Placeholder.hide()
	_blue_image2 = TextureRect.new()
	_blue_image2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blue_image2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	$BlueTeam/Row2/Frame.add_child(_blue_image2)
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var names: Array[Label] = [%BlueName1, %BlueName2, %RedName1, %RedName2]
	var subs: Array[Label] = [%BlueSub1, %BlueSub2, %RedSub1, %RedSub2]
	var images: Array[TextureRect] = [%BlueImage1, _blue_image2, %RedImage1, %RedImage2]
	for index: int in range(4):
		images[index].hide()
		images[index].texture = null
		names[index].text = "EMPTY SLOT"
		subs[index].text = ""
	var session: MvpSession = MenuRouter.session
	if not is_instance_valid(session):
		%ModeLine.text = "SESSION UNAVAILABLE"
		return
	%ArenaName.text = "THE FOUNDRY"
	var phase := str(session.match_view.get("phase", "loading"))
	%ModeLine.text = "WAITING FOR PLAYERS TO LOAD" if phase == "loading" else phase.to_upper()
	var teams: Array = [[], []]
	for slot: Dictionary in session.lobby_view.get("slots", []):
		var team := int(slot.get("team", -1))
		if team in [0, 1]:
			teams[team].append(slot)
	for team: int in range(2):
		for index: int in range(2):
			var pos := team * 2 + index
			var populated: bool = index < teams[team].size()
			images[pos].hide()
			images[pos].texture = null
			names[pos].text = "EMPTY SLOT"
			subs[pos].text = ""
			if populated:
				var slot: Dictionary = teams[team][index]
				var id := int(slot.get("entity_id", 0))
				names[pos].text = str(slot.get("loadout", {}).get("name", "Unknown build"))
				subs[pos].text = "PLAYER %d%s" % [id, " · YOU" if id == session.local_entity else ""]
				var weapon := str(slot.get("loadout", {}).get("parts", {}).get("weapon", ""))
				if weapon in ["vertical_spinner", "lifter"]:
					images[pos].texture = LIFTER_ART if weapon == "lifter" else SPINNER_ART
					images[pos].show()
					subs[pos].text += " · CONCEPT ART"
	$BlueTeam/Row2.visible = int(session.lobby_view.get("capacity", 4)) == 4
	$RedTeam/Row2.visible = int(session.lobby_view.get("capacity", 4)) == 4
