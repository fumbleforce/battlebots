extends MenuScreen
## Direct-IP lobby backed only by authoritative MvpSession publications.
var session_override: MvpSession
var session: MvpSession
var address: LineEdit
var port: SpinBox
var host_button: Button
var join_button: Button
var team_choice: OptionButton
var build_button: Button
var build_choice: OptionButton
var _connection_panel: PanelContainer
var _roster_cards: Array = []
var _notice := "Host a game or enter the host's LAN address."
var _pending := ""
var _expected: Variant
var _deadline := 0
var _refresh_time := 0.0
var _host_port := 24567
var _joined_build_sent := false

func _ready() -> void:
	allow_back = false
	super()
	%Steps.hide()
	%Back.pressed.disconnect(MenuRouter.back)
	%Back.pressed.connect(leave_lobby)
	session = session_override if is_instance_valid(session_override) else MenuRouter.session
	if not MenuRouter.session_notice.is_empty():
		_notice = MenuRouter.session_notice
	else:
		_notice = "Enter the host's address and public UDP port." if MenuRouter.lobby_intent == "join" else "Start the host, then share its address and UDP port."
	_build_connection_controls()
	_build_roster()
	%Ready.toggle_mode = false
	%Ready.pressed.connect(request_ready_state)
	%ArenaName.text = "THE FOUNDRY"
	%ArenaImage.texture = MenuData.ARENAS[0].get("image")
	$Layout/Body/Row/Match/ArenaCard.custom_minimum_size.y = 220
	$Layout/Body/Row/Match/ArenaCard/Caption/Row/Vote.text = "50 × 50 METERS"
	$Layout/Body/Row/Match/Rules/Win/Col/Value.text = "First to 2"
	$Layout/Body/Row/Match/Rules/Hazards/Col/Value.text = "None"
	%StatusBig.add_theme_font_size_override("font_size", 36)
	%StatusSub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_instance_valid(session):
		session.lobby_changed.connect(_lobby_changed)
		session.session_event.connect(_session_event)
	refresh()

func _build_connection_controls() -> void:
	var panel := PanelContainer.new()
	_connection_panel = panel
	panel.theme_type_variation = &"PanelGlass"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	panel.add_child(col)
	var endpoint := HBoxContainer.new()
	address = LineEdit.new()
	address.placeholder_text = "Host name or IP address"
	address.max_length = 253
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.add_theme_font_size_override("font_size", 19)
	endpoint.add_child(address)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 24567
	port.tooltip_text = "Joining: use the host's public tunnel UDP port. Hosting: local listen port, usually 24567. These may differ."
	port.custom_minimum_size.x = 135
	port.add_theme_font_size_override("font_size", 19)
	endpoint.add_child(port)
	col.add_child(endpoint)
	var buttons := HBoxContainer.new()
	host_button = _button("HOST GAME", host_session)
	join_button = _button("JOIN HOST", join_session)
	buttons.add_child(host_button)
	buttons.add_child(join_button)
	col.add_child(buttons)
	$Layout/Body/Row/Match.add_child(panel)
	$Layout/Body/Row/Match.move_child(panel, 2)
	$Layout/Footer/Row/Hint0.hide()
	$Layout/Footer/Row/Hint1.hide()
	team_choice = OptionButton.new()
	team_choice.add_item("BLUE TEAM", 0)
	team_choice.add_item("RED TEAM", 1)
	team_choice.custom_minimum_size = Vector2(220, 58)
	team_choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	team_choice.item_selected.connect(request_team)
	$Layout/Footer/Row.add_child(team_choice)
	$Layout/Footer/Row.move_child(team_choice, 0)
	build_choice = OptionButton.new()
	build_choice.custom_minimum_size = Vector2(280, 58)
	build_choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	build_choice.fit_to_longest_item = false
	build_choice.clip_text = true
	build_choice.tooltip_text = "Choose a saved build for this game"
	for bot: Dictionary in PlayerProfile.bots:
		build_choice.add_item(str(bot.name))
	build_choice.select(PlayerProfile.active_bot)
	build_choice.item_selected.connect(func(index: int) -> void:
		PlayerProfile.active_bot = index
		refresh())
	$Layout/Footer/Row.add_child(build_choice)
	$Layout/Footer/Row.move_child(build_choice, 1)
	build_button = _button("APPLY BUILD", request_build)
	build_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	build_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	$Layout/Footer/Row.add_child(build_button)
	$Layout/Footer/Row.move_child(build_button, 2)
	$Layout/Footer/Row.add_theme_constant_override("separation", 20)

func _build_roster() -> void:
	var existing := [[%You, %Mate], [%Opp1, %Opp2]]
	var columns := [$Layout/Body/Row/Blue, $Layout/Body/Row/Red]
	for index: int in range(2):
		var scroll := ScrollContainer.new()
		scroll.name = "RosterScroll"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		columns[index].add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 14)
		scroll.add_child(list)
		var cards: Array = existing[index]
		for card: Control in cards:
			card.reparent(list)
		for extra: int in range(3):
			var card := preload("res://ui/menus/components/player_slot.tscn").instantiate()
			list.add_child(card)
			cards.append(card)
		_roster_cards.append(cards)

func _configured_capacity() -> int:
	match str(MenuRouter.match_setup.mode):
		"duel": return 2
		"5v5": return 10
		"ffa": return clampi(int(MenuRouter.match_setup.get("capacity", 8)), 4, 8)
	return 4

func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.theme_type_variation = &"GhostButton"
	button.custom_minimum_size.y = 52
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button

func _process(delta: float) -> void:
	_refresh_time += delta
	if _refresh_time >= 0.1:
		_refresh_time = 0.0
		if not _pending.is_empty() and Time.get_ticks_msec() > _deadline:
			_pending = ""
			_notice = "Request not confirmed. Check the lobby before trying again."
		refresh()

func host_session() -> void:
	if not is_instance_valid(session) or session.connection_state != "offline":
		return
	var draft: Dictionary = PlayerProfile.active_loadout()
	var validation := session.registry.validate(draft)
	if not validation.valid:
		_notice = "Invalid selected build: " + "; ".join(validation.reasons)
		refresh()
		return
	_host_port = int(port.value)
	var count := _configured_capacity()
	var error := session.host(_host_port, true, count, "ffa" if MenuRouter.match_setup.mode == "ffa" else "teams")
	if error == OK:
		session.set_loadout(draft)
		_notice = "Share your LAN address and port %d, or your tunnel's public address and UDP port." % _host_port
	else:
		_notice = "Host failed: " + error_string(error)
	refresh()

func join_session() -> void:
	if not is_instance_valid(session) or session.connection_state != "offline":
		return
	var endpoint := address.text.strip_edges()
	if endpoint.is_empty() or " " in endpoint or "\n" in endpoint or "\t" in endpoint:
		_notice = "Enter the host's name or IP address."
		refresh()
		return
	var validation := session.registry.validate(PlayerProfile.active_loadout())
	if not validation.valid:
		_notice = "Choose a valid build in the garage before joining."
		refresh()
		return
	address.text = endpoint
	_joined_build_sent = false
	var error := session.join(endpoint, int(port.value))
	_notice = "Connecting to %s:%d…" % [endpoint, int(port.value)] if error == OK else "Join failed: " + error_string(error)
	refresh()

func _local_slot() -> Dictionary:
	if not is_instance_valid(session):
		return {}
	for slot: Dictionary in session.lobby_view.get("slots", []):
		if int(slot.get("entity_id", 0)) == session.local_entity:
			return slot
	return {}

func _can_edit() -> bool:
	return is_instance_valid(session) and session.connection_state in ["hosting", "connected"] and _pending.is_empty() \
		and str(session.match_view.get("phase", session.lobby_view.get("phase", "lobby"))) == "lobby" and not _local_slot().is_empty()

func _begin(kind: String, expected: Variant) -> void:
	_pending = kind
	_expected = expected
	_deadline = Time.get_ticks_msec() + 3000
	_notice = "Waiting for host confirmation…"

func request_ready_state() -> void:
	if not _can_edit():
		return
	var desired := not bool(_local_slot().get("ready", false))
	_begin("ready", desired)
	session.set_ready(desired)
	refresh()

func request_team(index: int) -> void:
	if not _can_edit() or index not in [0, 1] or session.lobby_view.get("mode") == "ffa":
		refresh()
		return
	_begin("team", index)
	session.set_team(index)
	refresh()

func request_build() -> void:
	if not _can_edit():
		return
	var draft: Dictionary = PlayerProfile.active_loadout()
	var validation := session.registry.validate(draft)
	if not validation.valid:
		_notice = "Selected build is invalid: " + "; ".join(validation.reasons)
		refresh()
		return
	_begin("loadout", validation.loadout)
	session.set_loadout(draft)
	refresh()

func _lobby_changed(_view: Dictionary) -> void:
	var slot := _local_slot()
	if not _pending.is_empty():
		var accepted := false
		if _pending == "loadout":
			var actual: Dictionary = slot.get("loadout", {})
			accepted = actual.get("parts") == _expected.get("parts") and actual.get("name") == _expected.get("name")
		else:
			accepted = slot.get(_pending) == _expected
		if accepted:
			_pending = ""
			_notice = "Host confirmed your change."
	refresh()

func _session_event(kind: String, details: Dictionary) -> void:
	if kind == "joined" and not _joined_build_sent:
		_joined_build_sent = true
		session.set_loadout(PlayerProfile.active_loadout())
		_notice = "Connected. Choose your build, then ready up."
	elif kind == "error":
		_pending = ""
		_notice = str(details.get("message", "Session error"))
	elif kind == "left":
		_pending = ""
		_joined_build_sent = false
		_notice = "Disconnected. Host or join a game."
	refresh()

func refresh() -> void:
	if not is_node_ready():
		return
	var valid := is_instance_valid(session)
	var state := session.connection_state if valid else "unavailable"
	var slots: Array = session.lobby_view.get("slots", []) if valid else []
	var capacity := int(session.lobby_view.get("capacity", _configured_capacity())) if valid else _configured_capacity()
	var mode := str(session.lobby_view.get("mode", "ffa" if MenuRouter.match_setup.mode == "ffa" else ("1v1" if capacity == 2 else ("5v5" if capacity == 10 else "2v2")))) if valid else ""
	var ffa := mode == "ffa"
	var connected := state in ["hosting", "connected"]
	var known := (connected and session.lobby_view.has("mode")) or (state == "offline" and MenuRouter.lobby_intent == "host")
	var per_team := ceili(capacity / 2.0)
	var teams: Array = [[], []]
	var ready_counts := [0, 0]
	for slot_index: int in range(slots.size()):
		var slot: Dictionary = slots[slot_index]
		var team := mini(slot_index / per_team, 1) if ffa else int(slot.get("team", -1))
		if team not in [0, 1]:
			continue
		teams[team].append(slot)
		if slot.get("connected", false) and slot.get("ready", false):
			ready_counts[team] += 1
	for team: int in range(2):
		var places := capacity - per_team if ffa and team == 1 else per_team
		for index: int in range(_roster_cards[team].size()):
			var card: Control = _roster_cards[team][index]
			card.visible = index < places
			var record := {"name":"OPEN SLOT", "sub":"Waiting for a player", "status":"none"}
			if index < teams[team].size():
				var slot: Dictionary = teams[team][index]
				var id := int(slot.get("entity_id", 0))
				var present := bool(slot.get("connected", false))
				var draft: Dictionary = slot.get("loadout", {})
				var legal := session.registry.validate(draft).valid
				record = {"name":"PLAYER %d%s" % [id, " (YOU)" if id == session.local_entity else ""],
					"sub":"%s · %s" % [str(draft.get("name", "Unknown build")), "Disconnected" if not present else ("Valid build" if legal else "Invalid build")],
					"you":id == session.local_entity, "status":"ready" if slot.get("ready", false) and present else "not_ready"}
				for bot: Dictionary in PlayerProfile.bots:
					if str(bot.get("name", "")).to_lower() == str(draft.get("name", "")).to_lower():
						record["thumb"] = bot.get("image")
						break
			card.setup(record)
	%BlueCount.text = "%d/%d ready" % [ready_counts[0], per_team]
	$Layout/Body/Row/Red/TeamHeader/Row/RedCount.text = "%d/%d ready" % [ready_counts[1], capacity - per_team if ffa else per_team]
	$Layout/Body/Row/Blue/TeamHeader/Row/Team.text = "PLAYERS 1–%d" % per_team if ffa else "BLUE TEAM"
	$Layout/Body/Row/Red/TeamHeader/Row/Team.text = "PLAYERS %d–%d" % [per_team + 1, capacity] if ffa else "RED TEAM"
	$Layout/Body/Row/Blue.visible = known
	$Layout/Body/Row/Red.visible = known
	$Layout/Body/Row/Match/ArenaCard.visible = known
	$Layout/Body/Row/Match/Rules.visible = known
	var mode_title := "FREE FOR ALL" if ffa else mode.to_upper()
	%Eyebrow.text = "%s · LOBBY" % mode_title if known else "JOIN GAME"
	$Layout/Body/Row/Match/Rules/Win/Col/Value.text = "Last bot" if ffa else "First to 2"
	$Layout/Body/Row/Match/Rules/Clock/Col/Value.text = "5:00" if ffa else ("4:00" if capacity == 10 else "3:00")
	%StatusEyebrow.text = "MINIMUM 4 · EVERYONE READY" if ffa and connected else state.to_upper()
	%StatusBig.text = "%d/%d PLAYERS" % [slots.size(), capacity] if connected and known else ("CONNECTING…" if state == "connecting" else ("JOIN A HOST" if MenuRouter.lobby_intent == "join" else "HOST A GAME"))
	%StatusSub.text = _notice
	if state == "hosting":
		var ips: PackedStringArray = []
		for ip: String in IP.get_local_addresses():
			if ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				ips.append(ip)
		%StatusSub.text += "\n%s · UDP %d" % [", ".join(ips) if not ips.is_empty() else "Use this computer's LAN IPv4 address", _host_port]
	var edit := _can_edit()
	var local := _local_slot()
	_connection_panel.visible = state == "offline"
	host_button.visible = MenuRouter.lobby_intent == "host"
	join_button.visible = MenuRouter.lobby_intent == "join"
	address.visible = MenuRouter.lobby_intent == "join"
	host_button.disabled = state != "offline"
	join_button.disabled = state != "offline"
	address.editable = state == "offline"
	port.editable = state == "offline"
	team_choice.disabled = not edit
	team_choice.visible = connected and known and not ffa
	if not ffa:
		team_choice.select(clampi(int(local.get("team", 0)), 0, 1))
	build_choice.disabled = state != "offline" and not edit
	build_choice.select(PlayerProfile.active_bot)
	var selected: Dictionary = PlayerProfile.active_loadout()
	var equipped: Dictionary = local.get("loadout", {})
	var differs: bool = selected.get("parts") != equipped.get("parts") or selected.get("name") != equipped.get("name") or selected.get("cosmetics") != equipped.get("cosmetics")
	build_button.visible = edit and differs
	build_button.disabled = not edit
	%Ready.visible = connected and known
	%Ready.disabled = not edit or not session.registry.validate(local.get("loadout", {})).valid if valid else true
	%Ready.text = "CANCEL READY" if local.get("ready", false) else "READY UP"
	%Back.text = "CANCEL CONNECTION" if state == "connecting" else ("LEAVE GAME" if connected else "BACK")

func leave_lobby() -> void:
	if is_instance_valid(session) and session.connection_state != "offline":
		session.leave()
	MenuRouter.goto("main", false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave_lobby()
