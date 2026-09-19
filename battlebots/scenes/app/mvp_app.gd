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
	var args := OS.get_cmdline_user_args()
	var port := 24567
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
	elif "--practice" in args or args.is_empty():
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
	# B collects inputs once. The proxy gates them before they reach the session.
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(510, 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status)
	console_panel = PanelContainer.new()
	console_panel.position = Vector2(330, 280)
	canvas.add_child(console_panel)
	var stack := VBoxContainer.new()
	console_panel.add_child(stack)
	var title := Label.new()
	title.text = "Session controls"
	stack.add_child(title)
	var row := HBoxContainer.new()
	stack.add_child(row)
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Host LAN address"
	address.custom_minimum_size.x = 150
	row.add_child(address)
	_button(row, "Host", func() -> void: session.leave(); session.host())
	_button(row, "Join", func() -> void: session.leave(); session.join(address.text))
	_button(row, "Ready", func() -> void: session.set_ready(true))
	_button(row, "Rematch", session.vote_rematch)
	_button(row, "Forfeit", session.vote_forfeit)
	_button(row, "Leave", session.leave)
	var second := HBoxContainer.new()
	stack.add_child(second)
	_button(second, "Striker", func() -> void: controller = false; session.set_loadout(session.registry.starter()))
	_button(second, "Controller", func() -> void: controller = true; session.set_loadout(session.registry.starter(true)))
	_button(second, "Practice / reset", func() -> void: session.leave(); session.practice(session.registry.starter(controller)))
	_button(second, "Launcher", func() -> void: session.leave(); get_tree().change_scene_to_file("res://scenes/app/main.tscn"))
	var third := HBoxContainer.new()
	stack.add_child(third)
	resume_button = _button(third, "Resume", resume_gameplay)
	_button(third, "Camera settings", func() -> void: preview.open_settings())
	var controls := Label.new()
	controls.text = "WASD drive | Space brake | LMB weapon | RMB lower/brake | R recover\nMouse orbit | Wheel zoom | MMB recenter | Esc session controls"
	stack.add_child(controls)

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
	resume_button.disabled = source == null
	var summary := "%s | %d/4 players | %s | round %d | %.0f s" % [session.connection_state,
		session.lobby_view.get("slots", []).size(), session.match_view.get("phase", "lobby"),
		session.match_view.get("round", 0), session.match_view.get("remaining", 0)]
	var scores: Array = session.match_view.get("scores", [0, 0])
	summary += "\nScore %d : %d | RTT %.0f ms | correction %.2f m" % [scores[0], scores[1],
		session.diagnostics.rtt_ms, session.diagnostics.correction_m]
	if session.connection_state == "practice":
		summary = "Practice | %s\nEsc opens session controls and build selection" % session.players[session.local_entity].loadout.name
	if console_panel.visible:
		for slot: Dictionary in session.lobby_view.get("slots", []):
			summary += "\nBot %d / Team %d / %s / %s" % [slot.entity_id, slot.team + 1,
				slot.loadout.get("name", "Build"), "READY" if slot.ready else "not ready"]
		if not notice.is_empty():
			summary += "\n" + notice
	if str(session.match_view.get("phase", "")) == "results":
		var winner := int(session.match_view.get("winner", -1))
		summary += "\nDRAW" if winner < 0 else "\nTeam %d wins" % (winner + 1)
	status.text = summary
