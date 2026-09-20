extends MenuScreen
## Read-only loading status. The persistent game root owns all phase navigation.
const SPINNER_ART := preload("res://ui/menus/art/bot_chevron.jpg")
const LIFTER_ART := preload("res://ui/menus/art/bot_rivetrex.jpg")
var _blue_image2: TextureRect
var _roster: Label

func apply_text_scale(factor: float) -> void:
	preload("res://scripts/ui/menu_text_scale.gd").apply(self, factor)
	for label: Label in [%BlueName1, %BlueName2, %RedName1, %RedName2, %BlueSub1, %BlueSub2, %RedSub1, %RedSub2]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.get_parent().custom_minimum_size.x = 480
		label.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$BlueTeam.size.x = 780
	$RedTeam.offset_left = -866
	$RedTeam.offset_right = -86
	$Bottom/Col/Row/Tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Bottom/Col/Row/Tip.custom_minimum_size.x = 500
	$Bottom/Col/Row/Tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%ModeLine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%ModeLine.custom_minimum_size.x = 240

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
	_roster = Label.new()
	_roster.position = Vector2(150, 140)
	_roster.size = Vector2(1620, 680)
	_roster.add_theme_font_size_override("font_size", 32)
	_roster.add_theme_constant_override("line_spacing", 12)
	_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_roster)
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
	var mode := str(session.lobby_view.get("mode", ""))
	var expanded := mode == "ffa" or int(session.lobby_view.get("capacity", 4)) > 4
	_roster.visible = expanded
	for node: CanvasItem in [$BlueTeam, $RedTeam, $Vs, $VsDiamond, $TeamSplit]:
		node.visible = not expanded
	if expanded:
		var lines := PackedStringArray(["FREE FOR ALL" if mode == "ffa" else "5V5 · TEAM BATTLE"])
		for slot: Dictionary in session.lobby_view.get("slots", []):
			var team := "" if mode == "ffa" else ("BLUE · " if int(slot.get("team", 0)) == 0 else "RED · ")
			lines.append("%sPLAYER %d%s · %s" % [team, int(slot.get("entity_id", 0)), " (YOU)" if int(slot.get("entity_id", 0)) == session.local_entity else "", str(slot.get("loadout", {}).get("name", "Unknown build"))])
		_roster.text = "\n".join(lines)
		return
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
