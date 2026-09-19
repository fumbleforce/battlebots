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
var port := 24567
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
		if arg == "--controller":
			controller = true
	if "--server" in args or OS.has_feature("dedicated_server"):
		if session.host(port, false) != OK:
			get_tree().quit(1)
		return
	if DisplayServer.get_name() != "headless":
		_build_console()
	if not remote.is_empty():
		session.join(remote, port)
	elif "--host" in args:
		session.host(port)
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
	var title := Label.new()
	title.text = "BATTLEBOTS"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	resume_button = _button(heading, "Resume", resume_gameplay)
	var builds := HBoxContainer.new()
	stack.add_child(builds)
	striker_button = _button(builds, "Striker / Spinner", func() -> void: select_build(false))
	controller_button = _button(builds, "Controller / Lifter", func() -> void: select_build(true))
	striker_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controller_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	striker_button.toggle_mode = true
	controller_button.toggle_mode = true
	build_hint = Label.new()
	build_hint.add_theme_font_size_override("font_size", 15)
	stack.add_child(build_hint)
	var practice_row := HBoxContainer.new()
	stack.add_child(practice_row)
	_button(practice_row, "Practice / reset", func() -> void: session.leave(); session.practice(session.registry.starter(controller)))
	_button(practice_row, "Camera settings", func() -> void: preview.open_settings())
	stack.add_child(HSeparator.new())
	var network := Label.new()
	network.text = "MULTIPLAYER / 4 PLAYERS"
	network.add_theme_font_size_override("font_size", 14)
	stack.add_child(network)
	var row := HBoxContainer.new()
	stack.add_child(row)
	address = LineEdit.new()
	address.placeholder_text = "Host IP, e.g. 192.168.1.20"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.custom_minimum_size.x = 180
	row.add_child(address)
	_button(row, "Host", host_game)
	_button(row, "Join", join_game)
	_button(row, "Ready", func() -> void: session.set_loadout(session.registry.starter(controller)); session.set_ready(true))
	var lan_hint := Label.new()
	lan_hint.add_theme_font_size_override("font_size", 14)
	lan_hint.text = "Same Wi-Fi / Ethernet: Host, then enter that PC's address to Join.\n2v2 needs 4 ready windows: run 2 per computer. UDP %d." % port
	stack.add_child(lan_hint)
	var match_row := HBoxContainer.new()
	stack.add_child(match_row)
	_button(match_row, "Rematch", session.vote_rematch)
	_button(match_row, "Forfeit", session.vote_forfeit)
	_button(match_row, "Leave", session.leave)
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
	session.leave()
	if session.host(port) == OK:
		session.set_loadout(session.registry.starter(controller))

func join_game() -> void:
	var target := address.text.strip_edges()
	if target.is_empty():
		notice = "Enter the address shown on the host PC. Use 127.0.0.1 only on that same PC."
		return
	session.leave()
	var error := session.join(target, port)
	if error != OK:
		notice = "Could not join %s (error %d). Check the address and try again." % [target, error]
	else:
		notice = "Connecting to %s:%d..." % [target, port]

func select_build(use_controller: bool) -> void:
	controller = use_controller
	if session.connection_state in ["hosting", "connected"]:
		session.set_loadout(session.registry.starter(controller))

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
	striker_button.set_pressed_no_signal(not controller)
	controller_button.set_pressed_no_signal(controller)
	build_hint.text = "Hold LMB to raise; release fully charged to flip. RMB lowers." if controller else "Hold LMB to spin up. Strike with the front disc. RMB brakes."
	preview.hud.visible = source != null and not console_panel.visible and not preview.settings_panel.visible
	var summary := "%s | %d/4 players | %s | round %d | %.0f s" % [session.connection_state,
		session.lobby_view.get("slots", []).size(), session.match_view.get("phase", "lobby"),
		session.match_view.get("round", 0), session.match_view.get("remaining", 0)]
	var scores: Array = session.match_view.get("scores", [0, 0])
	summary += "\nScore %d : %d | RTT %.0f ms | correction %.2f m" % [scores[0], scores[1],
		session.diagnostics.rtt_ms, session.diagnostics.correction_m]
	if session.connection_state == "practice":
		summary = "Practice | %s\nEsc opens session controls and build selection" % session.players[session.local_entity].loadout.name
	if console_panel.visible:
		if session.connection_state == "hosting":
			summary += "\nJoin from the other PC: %s" % (", ".join(lan_addresses) if not lan_addresses.is_empty() else "No LAN IPv4 found")
			summary += "\nOn this PC, extra windows join 127.0.0.1. Port %d." % port
		for slot: Dictionary in session.lobby_view.get("slots", []):
			summary += "\nBot %d / Team %d / %s / %s" % [slot.entity_id, slot.team + 1,
				slot.loadout.get("name", "Build"), "READY" if slot.ready else "not ready"]
		if not notice.is_empty():
			summary += "\n" + notice
	if str(session.match_view.get("phase", "")) == "results":
		var winner := int(session.match_view.get("winner", -1))
		summary += "\nDRAW" if winner < 0 else "\nTeam %d wins" % (winner + 1)
	status.text = summary
	status.visible = not console_panel.visible and not preview.settings_panel.visible
	menu_status.text = summary
