extends Node3D
## A-owned integration shell mounting B's published presentation components.
var session: MvpSession
var status: Label
var address: LineEdit
var controller := false
var last_phase := ""
var notice := ""
var preview: Node3D
var player_source: SessionBotSource
var console_panel: PanelContainer
var resume_button: Button
var striker_button: Button
var controller_button: Button
var build_hint: Label
var menu_status: Label
var menu_scroll: ScrollContainer
var menu_backdrop: ColorRect
var port := 24567
var player_count := 2
var player_count_choice: OptionButton
var menu_title: Label
var menu_hint: Label
var build_row: HBoxContainer
var host_setup: VBoxContainer
var join_setup: HBoxContainer
var lobby_actions: HBoxContainer
var match_actions: HBoxContainer
var ready_button: Button
var leave_button: Button
var forfeit_button: Button
var rematch_button: Button
var practice_button: Button
var camera_button: Button
var _ui_phase := ""
var lan_addresses := PackedStringArray()
var _previous_source: BotSource

func _ready() -> void:
	session = MvpSession.new()
	session.name = "Session"
	add_child(session)
	session.match_changed.connect(func(view: Dictionary) -> void:
		if str(view.phase) != last_phase:
			last_phase = view.phase
			print("SESSION PHASE: ", last_phase))
	session.session_event.connect(func(kind: String, details: Dictionary) -> void:
		if kind == "error":
			notice = str(details.get("message", "Unknown error"))
			print("SESSION ERROR: ", notice)
		else:
			notice = kind.capitalize()
			print("SESSION: ", kind))
	session.session_event.connect(func(kind: String, _details: Dictionary) -> void:
		if kind == "joined" and session.match_view.get("phase", "lobby") == "lobby":
			session.set_loadout(session.registry.starter(controller)))
	var start_mode := str(get_tree().get_meta("start_mode", "practice"))
	get_tree().remove_meta("start_mode")
	var args := OS.get_cmdline_user_args()
	lan_addresses = local_lan_addresses()
	var remote := ""
	for arg: String in args:
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		if arg.begins_with("--join="):
			remote = arg.trim_prefix("--join=")
		if arg.begins_with("--players="):
			player_count = arg.trim_prefix("--players=").to_int()
		if arg == "--controller":
			controller = true
	if "--server" in args or OS.has_feature("dedicated_server"):
		if session.host(port, false, player_count) != OK:
			get_tree().quit(1)
		return
	if DisplayServer.get_name() != "headless":
		_build_console()
	if not remote.is_empty():
		session.join(remote, port)
	elif "--host" in args:
		session.host(port, true, player_count)
	elif "--practice" in args or (args.is_empty() and start_mode == "practice"):
		session.practice(session.registry.starter(controller))
	if "--ready" in args:
		session.session_event.connect(func(kind: String, _details: Dictionary) -> void:
			if kind == "joined":
				session.set_loadout(session.registry.starter(controller))
				session.set_ready(true))
		if session.connection_state == "hosting":
			session.set_ready(true)

func _button(row: HBoxContainer, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _build_console() -> void:
	get_window().title = "Battlebots - A+B playtest"
	player_source = SessionBotSource.new()
	player_source.name = "PlayerSource"
	player_source.session_path = NodePath("../Session")
	player_source.input_allowed = gameplay_input_allowed
	add_child(player_source)
	preview = preload("res://scenes/ui/baseline_preview.tscn").instantiate()
	preview.name = "Preview"
	preview.source_path = NodePath("../PlayerSource")
	preview.fixture_title = "Battlebots / live session"
	add_child(preview)
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	menu_backdrop = ColorRect.new()
	menu_backdrop.color = Color(0.018, 0.03, 0.045)
	menu_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(menu_backdrop)
	menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status = Label.new()
	status.position = Vector2(510, 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status)
	var center := CenterContainer.new()
	canvas.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_scroll = ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.follow_focus = true
	center.add_child(menu_scroll)
	console_panel = PanelContainer.new()
	console_panel.custom_minimum_size.x = 680
	console_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	console_panel.theme = GameMenuTheme.create()
	menu_scroll.add_child(console_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	console_panel.add_child(margin)
	var stack := VBoxContainer.new()
	margin.add_child(stack)
	var heading := HBoxContainer.new()
	stack.add_child(heading)
	menu_title = Label.new()
	menu_title.add_theme_font_size_override("font_size", 28)
	menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(menu_title)
	resume_button = _button(heading, "Resume", resume_gameplay)
	menu_hint = Label.new()
	menu_hint.add_theme_font_size_override("font_size", 16)
	menu_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(menu_hint)
	build_row = HBoxContainer.new()
	stack.add_child(build_row)
	striker_button = _button(build_row, "Striker / Spinner", func() -> void: select_build(false))
	controller_button = _button(build_row, "Controller / Lifter", func() -> void: select_build(true))
	striker_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controller_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	striker_button.toggle_mode = true
	controller_button.toggle_mode = true
	build_hint = Label.new()
	build_hint.add_theme_font_size_override("font_size", 15)
	stack.add_child(build_hint)
	var practice_row := HBoxContainer.new()
	stack.add_child(practice_row)
	practice_button = _button(practice_row, "Apply build / reset practice", func() -> void: session.leave(); session.practice(session.registry.starter(controller)))
	camera_button = _button(practice_row, "Camera settings", func() -> void: preview.open_settings())
	host_setup = VBoxContainer.new()
	stack.add_child(host_setup)
	var host_row := HBoxContainer.new()
	host_setup.add_child(host_row)
	player_count_choice = OptionButton.new()
	player_count_choice.add_item("2 players / 1v1", 2)
	player_count_choice.add_item("4 players / 2v2", 4)
	player_count_choice.select(1 if player_count == 4 else 0)
	player_count_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_count_choice.item_selected.connect(func(index: int) -> void: player_count = player_count_choice.get_item_id(index))
	host_row.add_child(player_count_choice)
	_button(host_row, "Host game", host_game)
	var or_label := Label.new()
	or_label.text = "OR JOIN A FRIEND"
	or_label.add_theme_font_size_override("font_size", 14)
	host_setup.add_child(or_label)
	join_setup = HBoxContainer.new()
	stack.add_child(join_setup)
	address = LineEdit.new()
	address.placeholder_text = "Host IP, e.g. 192.168.1.20"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.custom_minimum_size.x = 180
	join_setup.add_child(address)
	_button(join_setup, "Join game", join_game)
	lobby_actions = HBoxContainer.new()
	stack.add_child(lobby_actions)
	ready_button = _button(lobby_actions, "Ready", toggle_ready)
	match_actions = HBoxContainer.new()
	stack.add_child(match_actions)
	rematch_button = _button(match_actions, "Vote rematch", session.vote_rematch)
	forfeit_button = _button(match_actions, "Forfeit round", session.vote_forfeit)
	leave_button = _button(match_actions, "Leave lobby", session.leave)
	menu_status = Label.new()
	menu_status.add_theme_font_size_override("font_size", 15)
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_status.add_theme_color_override("font_color", Color(0.55, 0.75, 0.8))
	stack.add_child(menu_status)
	stack.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	stack.add_child(footer)
	var controls := Label.new()
	controls.add_theme_font_size_override("font_size", 14)
	controls.text = "WASD drive / Space brake / LMB weapon\nRMB lower / R recover / Mouse orbit / Esc menu"
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(controls)
	_button(footer, "Main menu", func() -> void: session.leave(); get_tree().change_scene_to_file("res://scenes/app/main.tscn"))
	_process(0)

static func local_lan_addresses() -> PackedStringArray:
	var candidates := PackedStringArray()
	for candidate: String in IP.get_local_addresses():
		if ":" in candidate or candidate.begins_with("127.") or candidate.begins_with("169.254.") or candidate == "0.0.0.0":
			continue
		if not candidates.has(candidate):
			candidates.append(candidate)
	candidates.sort()
	return candidates

func host_game() -> void:
	if session.connection_state != "offline":
		return
	if session.host(port, true, player_count) == OK:
		session.set_loadout(session.registry.starter(controller))

func join_game() -> void:
	var target := address.text.strip_edges()
	if target.is_empty():
		notice = "Enter the address shown on the host PC. Use 127.0.0.1 only on that same PC."
		return
	if session.connection_state != "offline":
		return
	var error := session.join(target, port)
	if error != OK:
		notice = "Could not join %s (error %d). Check the address and try again." % [target, error]
	else:
		notice = "Connecting to %s:%d..." % [target, port]

func select_build(use_controller: bool) -> void:
	controller = use_controller
	if session.connection_state in ["hosting", "connected"] and session.match_view.get("phase", "lobby") == "lobby":
		session.set_loadout(session.registry.starter(controller))

func local_ready() -> bool:
	for slot: Dictionary in session.lobby_view.get("slots", []):
		if slot.entity_id == session.local_entity:
			return slot.ready
	return false

func toggle_ready() -> void:
	if session.connection_state in ["hosting", "connected"] and session.match_view.get("phase", "lobby") == "lobby":
		session.set_ready(not local_ready())

func gameplay_input_allowed() -> bool:
	return is_instance_valid(preview) and preview.controls_enabled \
		and not preview.settings_panel.visible and get_window().has_focus() \
		and session.local_source() != null \
		and not session.local_source().read_view().eliminated \
		and str(session.match_view.get("phase", "")) in ["active", "overtime"]

func resume_gameplay() -> void:
	if session.local_source() == null:
		return
	get_viewport().gui_release_focus()
	preview.capture_controls()

func _process(_delta: float) -> void:
	if status == null:
		return
	var source := session.local_source()
	if source != _previous_source:
		_previous_source = source
		preview.rig.bind_source(player_source)
		if source != null and get_window().has_focus() and not preview.settings_panel.visible:
			resume_gameplay()
	if source == null:
		if preview.controls_enabled:
			preview.release_controls()
		preview.hud.hide()
	else:
		preview.hud.show()
	console_panel.visible = not preview.controls_enabled and not preview.settings_panel.visible
	menu_scroll.visible = console_panel.visible
	menu_scroll.custom_minimum_size = Vector2(720, minf(680, get_viewport().get_visible_rect().size.y - 48))
	resume_button.disabled = source == null
	_refresh_menu(source)

func _refresh_menu(source: BotSource) -> void:
	var state := session.connection_state
	var phase := str(session.match_view.get("phase", "lobby"))
	var online := state in ["hosting", "connected"]
	var lobby := online and phase == "lobby"
	var practice := state == "practice"
	var capacity := int(session.lobby_view.get("capacity", player_count))
	var mode := str(session.lobby_view.get("mode", "1v1" if capacity == 2 else "2v2"))
	var slots: Array = session.lobby_view.get("slots", [])
	menu_backdrop.visible = state in ["offline", "connecting"]
	if phase != _ui_phase:
		_ui_phase = phase
		if phase == "results":
			preview.release_controls()
			notice = ""
	host_setup.visible = state == "offline"
	join_setup.visible = state == "offline"
	lobby_actions.visible = lobby
	ready_button.visible = lobby
	ready_button.text = "Not ready" if local_ready() else "Ready"
	build_row.visible = state == "offline" or lobby or practice
	build_hint.visible = build_row.visible
	practice_button.visible = practice
	camera_button.visible = source != null
	resume_button.visible = source != null and phase != "results"
	leave_button.visible = online or state == "connecting"
	leave_button.text = "Cancel connection" if state == "connecting" else ("Close lobby" if state == "hosting" and lobby else ("Leave lobby" if lobby else "Leave match"))
	forfeit_button.visible = online and phase in ["active", "overtime"] and source != null and not source.read_view().eliminated
	rematch_button.visible = online and phase == "results"
	match_actions.visible = leave_button.visible or forfeit_button.visible or rematch_button.visible
	striker_button.set_pressed_no_signal(not controller)
	controller_button.set_pressed_no_signal(controller)
	build_hint.text = "Hold LMB to raise; release charged to flip. RMB lowers." if controller else "Hold LMB to spin up; hit with the front disc. RMB brakes."
	preview.hud.visible = source != null and not console_panel.visible and not preview.settings_panel.visible
	preview.get_node("CanvasLayer").visible = not console_panel.visible and not preview.settings_panel.visible
	menu_title.text = "Multiplayer"
	menu_hint.text = "Choose a player count and host, or enter your friend's address. One game window per player."
	var summary := ""
	if state == "connecting":
		menu_title.text = "Connecting"
		menu_hint.text = "Waiting for the host. You can cancel and try another address."
	elif practice:
		menu_title.text = "Practice"
		menu_hint.text = "Try either weapon. Apply a new build to restart practice."
		summary = "Current bot: %s" % session.players[session.local_entity].loadout.name
	elif lobby:
		menu_title.text = "Lobby / %s" % mode
		var ready_count := 0
		for slot: Dictionary in slots:
			ready_count += int(slot.ready and slot.connected)
		menu_hint.text = "%d/%d players joined / %d ready. " % [slots.size(), capacity, ready_count]
		var missing := capacity - slots.size()
		menu_hint.text += "Waiting for %d more %s." % [missing, "player" if missing == 1 else "players"] if missing > 0 else "Everyone must press Ready to start."
		if state == "hosting":
			summary = "Host address(es): %s\nUse the Ethernet / Wi-Fi address on your friend's network." % (", ".join(lan_addresses) if not lan_addresses.is_empty() else "No LAN IPv4 found")
		for slot: Dictionary in slots:
			summary += "\n%s / Team %d / %s / %s" % ["You" if slot.entity_id == session.local_entity else "Player %d" % slot.entity_id,
				slot.team + 1, slot.loadout.get("name", "Build"), "Ready" if slot.ready else "Not ready"]
	elif online:
		menu_title.text = "Match complete" if phase == "results" else "Match / %s" % mode
		menu_hint.text = "Vote for another match, or leave." if phase == "results" else "The match continues while this menu is open."
		var scores: Array = session.match_view.get("scores", [0, 0])
		summary = "Round %d / %s / %.0f s\nTeam 1  %d : %d  Team 2" % [session.match_view.get("round", 0), phase.capitalize(), session.match_view.get("remaining", 0), scores[0], scores[1]]
		if phase == "results":
			var winner := int(session.match_view.get("winner", -1))
			summary += "\nDraw" if winner < 0 else "\nTeam %d wins" % (winner + 1)
	if not notice.is_empty() and (state in ["offline", "connecting"] or notice not in ["Hosted", "Joined", "Practice", "Left", "Results"]):
		summary += "\n" + notice
	menu_status.text = summary.strip_edges()
	menu_status.visible = not menu_status.text.is_empty()
	status.text = "Practice / %s\nEsc opens the menu" % session.players[session.local_entity].loadout.name if practice else "%s / %s / Round %d / %.0f s" % [mode, phase.capitalize(), session.match_view.get("round", 0), session.match_view.get("remaining", 0)]
	status.visible = source != null and not console_panel.visible and not preview.settings_panel.visible
