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
	set_step(4)
	%Back.pressed.disconnect(MenuRouter.back)
	%Back.pressed.connect(leave_lobby)
	session = session_override if is_instance_valid(session_override) else MenuRouter.session
	if not MenuRouter.session_notice.is_empty():
		_notice = MenuRouter.session_notice
	_build_connection_controls()
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
	panel.theme_type_variation = &"PanelGlass"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	panel.add_child(col)
	var endpoint := HBoxContainer.new()
	address = LineEdit.new()
	address.placeholder_text = "Host LAN IP, e.g. 192.168.1.25"
	address.max_length = 253
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.add_theme_font_size_override("font_size", 19)
	endpoint.add_child(address)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 24567
	port.tooltip_text = "UDP port; both computers must use the same port"
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
	build_button = _button("USE SELECTED BUILD", request_build)
	build_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	build_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	$Layout/Footer/Row.add_child(build_button)
	$Layout/Footer/Row.move_child(build_button, 1)

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
	var count := 2 if MenuRouter.match_setup.mode == "duel" else 4
	var error := session.host(_host_port, true, count)
	if error == OK:
		session.set_loadout(draft)
		_notice = "Share your LAN IPv4 address and UDP port %d." % _host_port
	else:
		_notice = "Host failed: " + error_string(error)
	refresh()

func join_session() -> void:
	if not is_instance_valid(session) or session.connection_state != "offline":
		return
	var endpoint := address.text.strip_edges()
	if endpoint.is_empty() or " " in endpoint or "\n" in endpoint or "\t" in endpoint:
		_notice = "Enter the host's LAN IP address."
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
	if not _can_edit() or index not in [0, 1]:
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
		_notice = "Connected. Ready when your build and team are correct."
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
	var capacity := int(session.lobby_view.get("capacity", 2 if MenuRouter.match_setup.mode == "duel" else 4)) if valid else 4
	var per_team := capacity / 2
	var teams: Array = [[], []]
	var ready_counts := [0, 0]
	for slot: Dictionary in slots:
		var team := int(slot.get("team", -1))
		if team not in [0, 1]:
			continue
		teams[team].append(slot)
		if slot.get("connected", false) and slot.get("ready", false):
			ready_counts[team] += 1
	var cards: Array = [%You, %Mate, %Opp1, %Opp2]
	for team: int in range(2):
		for index: int in range(2):
			var card: Control = cards[team * 2 + index]
			card.visible = index < per_team
			var record := {"name":"OPEN SLOT", "sub":"Waiting for a player", "status":"none"}
			if index < teams[team].size():
				var slot: Dictionary = teams[team][index]
				var id := int(slot.get("entity_id", 0))
				var connected := bool(slot.get("connected", false))
				var draft: Dictionary = slot.get("loadout", {})
				var legal := session.registry.validate(draft).valid
				record = {"name":"PLAYER %d%s" % [id, " (YOU)" if id == session.local_entity else ""],
					"sub":"%s · %s" % [str(draft.get("name", "Unknown build")), "Disconnected" if not connected else ("Valid build" if legal else "Invalid build")],
					"you":id == session.local_entity, "status":"ready" if slot.get("ready", false) and connected else "not_ready"}
				for bot: Dictionary in PlayerProfile.bots:
					if str(bot.get("name", "")).to_lower() == str(draft.get("name", "")).to_lower():
						record["thumb"] = bot.get("image")
						break
			card.setup(record)
	%BlueCount.text = "%d/%d ready" % [ready_counts[0], per_team]
	$Layout/Body/Row/Red/TeamHeader/Row/RedCount.text = "%d/%d ready" % [ready_counts[1], per_team]
	%Eyebrow.text = "STEP 4 OF 4 · %s · LAN / DIRECT IP" % ("1v1 DUEL" if capacity == 2 else "2v2 TEAM BATTLE")
	%StatusEyebrow.text = state.to_upper()
	%StatusBig.text = "%d/%d PLAYERS" % [slots.size(), capacity] if state in ["hosting", "connected"] else ("CONNECTING…" if state == "connecting" else "LAN / DIRECT IP")
	%StatusSub.text = _notice
	if state == "hosting":
		var ips: PackedStringArray = []
		for ip: String in IP.get_local_addresses():
			if ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				ips.append(ip)
		%StatusSub.text += "\n%s · UDP %d" % [", ".join(ips) if not ips.is_empty() else "Use this computer's LAN IPv4 address", _host_port]
	var edit := _can_edit()
	var local := _local_slot()
	host_button.disabled = state != "offline"
	join_button.disabled = state != "offline"
	address.editable = state == "offline"
	port.editable = state == "offline"
	team_choice.disabled = not edit
	team_choice.select(int(local.get("team", 0)))
	build_button.disabled = not edit
	%Ready.disabled = not edit or not session.registry.validate(local.get("loadout", {})).valid if valid else true
	%Ready.text = "CANCEL READY" if local.get("ready", false) else "READY UP"
	%Back.text = "CANCEL CONNECTION" if state == "connecting" else "LEAVE"

func leave_lobby() -> void:
	if is_instance_valid(session) and session.connection_state != "offline":
		session.leave()
	MenuRouter.back()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave_lobby()
