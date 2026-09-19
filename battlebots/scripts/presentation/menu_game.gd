extends Node3D
## Persistent game owner; imported screens navigate without replacing the live session.
@onready var session: MvpSession = $Session
@onready var source: SessionBotSource = $PlayerSource
@onready var preview: Node3D = $Preview
@onready var menu_host: Control = $MenuLayer/MenuHost
@onready var match_hud: MatchHud = $MatchLayer/MatchHud
var screen: Control
var _last_phase := ""
var _last_source: BotSource
var _settings_from_menu := false
var _cli_handoff := false
var _forfeit: Button
var _rematch: Button
var _vote_match := ""
var _menu_music: AudioStreamPlayer
var public_service: PublicServiceClient
var _online_joining := false
var results_panel: MatchResults

func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if args.any(func(arg: String) -> bool: return arg.begins_with("--allocation-config=")):
		_cli_handoff = true
		get_tree().change_scene_to_file.call_deferred("res://scenes/app/hosted_server.tscn")
		return
	if OS.has_feature("dedicated_server") or args.has("--server") or args.has("--host") or args.any(func(arg: String) -> bool: return arg.begins_with("--join=")):
		_cli_handoff = true
		get_tree().change_scene_to_file.call_deferred("res://scenes/app/mvp.tscn")
		return
	MenuRouter.bind(self, session)
	public_service = PublicServiceClient.new()
	public_service.name = "PublicService"
	add_child(public_service)
	public_service.assignment_ready.connect(_online_assignment)
	session.session_event.connect(_session_event)
	source.input_allowed = gameplay_input_allowed
	preview.return_button.pressed.disconnect(preview.return_to_launcher)
	preview.return_button.pressed.connect(return_to_main)
	preview.settings_panel.closed.connect(_settings_closed)
	_add_match_actions()
	var results_layer := CanvasLayer.new()
	results_layer.layer = 6
	add_child(results_layer)
	results_panel = MatchResults.new()
	results_layer.add_child(results_panel)
	results_panel.rematch_requested.connect(_request_rematch)
	results_panel.leave_requested.connect(return_to_main)
	_add_menu_music()
	get_viewport().size_changed.connect(_resize_menu)
	_resize_menu()
	show_screen("main")
	if "--practice" in args:
		start_practice()

func _resize_menu() -> void:
	var extent := get_viewport().get_visible_rect().size
	var ratio := minf(extent.x / 1920.0, extent.y / 1080.0)
	menu_host.scale = Vector2.ONE * ratio
	menu_host.size = Vector2(1920, 1080)
	menu_host.position = (extent - menu_host.size * ratio) * 0.5

func show_screen(key: String) -> void:
	if _cli_handoff or not MenuRouter.SCREENS.has(key):
		return
	preview.release_controls(false)
	preview.pause_menu.hide()
	if is_instance_valid(screen):
		menu_host.remove_child(screen)
		screen.queue_free()
	screen = load(MenuRouter.SCREENS[key]).instantiate()
	menu_host.add_child(screen)
	menu_host.show()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sync_menu_music()

func _add_menu_music() -> void:
	_menu_music = AudioStreamPlayer.new()
	_menu_music.name = "MenuMusic"
	var melody := load("res://assets/audio/menu/system_discovery.mp3").duplicate() as AudioStreamMP3
	melody.loop = true
	_menu_music.stream = melody
	_menu_music.volume_db = -16.0
	add_child(_menu_music)

func _sync_menu_music() -> void:
	if not is_instance_valid(_menu_music):
		return
	var in_menu: bool = menu_host.visible or (_settings_from_menu and preview.settings_panel.visible)
	if in_menu and not _menu_music.playing:
		_menu_music.play()
	elif not in_menu and _menu_music.playing:
		_menu_music.stop()

func gameplay_input_allowed() -> bool:
	var bot := session.local_source()
	return not _cli_handoff and not menu_host.visible and preview.controls_enabled \
		and not preview.settings_panel.visible and get_window().has_focus() \
		and bot != null and not bot.read_view().eliminated \
		and session.match_view.get("phase") in ["active", "overtime"]

func _process(_delta: float) -> void:
	if _cli_handoff:
		return
	var phase := str(session.match_view.get("phase", "lobby"))
	var bot := session.local_source()
	if bot != _last_source:
		_last_source = bot
		preview.rig.bind_source(source)
	if phase != _last_phase:
		var prior := _last_phase
		_last_phase = phase
		if phase == "loading":
			MenuRouter.goto("loading", false)
		elif phase == "countdown" and prior == "loading" and not preview.settings_panel.visible:
			resume_gameplay()
		elif phase == "lobby" and prior in ["results", "loading", "countdown", "active", "intermission", "overtime"]:
			MenuRouter.goto("online" if MenuRouter.lobby_intent == "online" and public_service.state == "failed" else "lobby", false)
		if phase == "results":
			preview.release_controls(false)
			results_panel.show()
			results_panel.rematch.grab_focus()
		elif prior == "results":
			results_panel.hide()
			results_panel.clear_record()
	results_panel.render(session.match_view, session.local_entity)
	var menu_open := menu_host.visible
	preview.get_node("CanvasLayer").visible = not menu_open and not preview.settings_panel.visible
	preview.get_node("DiagnosticsLayer").visible = not menu_open and not preview.settings_panel.visible
	preview.hud.visible = bot != null
	match_hud.visible = bot != null and not menu_open and not preview.settings_panel.visible
	match_hud.render(session.match_view, session.connection_state == "practice")
	if menu_open:
		preview.pause_menu.hide()
	_forfeit.visible = session.connection_state in ["hosting", "connected"] and phase in ["active", "overtime"]
	_forfeit.text = "Forfeit" if session.match_view.get("mode") == "ffa" else "Vote to forfeit round"
	_rematch.visible = session.connection_state in ["hosting", "connected"] and phase == "results"
	_rematch.disabled = _vote_match == str(session.match_view.get("match_id", ""))
	_rematch.text = "Rematch requested" if _rematch.disabled else "Request rematch"
	_sync_menu_music()

func start_practice() -> void:
	if session.connection_state != "offline":
		return
	var draft: Dictionary = PlayerProfile.active_loadout()
	if draft.is_empty() or not session.registry.validate(draft).valid:
		show_notice("Repair and select a valid build in the garage before starting practice.")
		return
	var error := session.practice(draft)
	if error == OK:
		resume_gameplay()
	else:
		show_notice("Cannot start practice: %s" % error_string(error))

func resume_gameplay() -> void:
	if session.match_view.get("phase") == "results":
		return
	if session.local_source() == null or preview.settings_panel.visible:
		return
	if session.match_view.get("phase") not in ["countdown", "active", "overtime", "intermission", "results"]:
		return
	menu_host.hide()
	_sync_menu_music()
	preview.capture_controls()

func return_to_main() -> void:
	preview.release_controls(false)
	if is_instance_valid(public_service) and (MenuRouter.lobby_intent == "online" or public_service.can_cancel()):
		cancel_online()
	session.leave()
	_last_phase = ""
	_vote_match = ""
	results_panel.hide()
	results_panel.clear_record()
	MenuRouter.goto("main", false)

func open_settings() -> void:
	_settings_from_menu = menu_host.visible
	menu_host.hide()
	preview.open_settings()

func _settings_closed(_saved: bool) -> void:
	preview.release_controls(false)
	if _settings_from_menu:
		menu_host.show()
		preview.pause_menu.hide()
		if is_instance_valid(screen):
			var focus := screen.find_next_valid_focus()
			if focus:
				focus.grab_focus()
	_settings_from_menu = false

func _input(event: InputEvent) -> void:
	if _cli_handoff or not event.is_action_pressed("pause"):
		return
	if results_panel.visible:
		get_viewport().set_input_as_handled()
		return
	if preview.settings_panel.visible:
		get_viewport().set_input_as_handled()
		preview.settings_panel.cancel()
	elif menu_host.visible and MenuRouter.current in ["main", "loading"]:
		# These screens intentionally have no Back action; do not fall through to driving UI.
		get_viewport().set_input_as_handled()
	elif not menu_host.visible:
		get_viewport().set_input_as_handled()
		if preview.controls_enabled:
			preview.release_controls()
		else:
			resume_gameplay()

func _session_event(kind: String, details: Dictionary) -> void:
	if kind == "results":
		results_panel.accept_record(details, str(session.match_view.get("match_id", "")))
	elif kind == "error":
		MenuRouter.session_notice = str(details.get("message", "Session error"))
		if _online_joining or (MenuRouter.lobby_intent == "online" and session.connection_state == "offline" and public_service.state in ["ready", "connected"]):
			_online_joining = false
			public_service.game_failed()
			MenuRouter.goto("online", false)
	elif kind in ["left", "hosted", "joined", "practice"]:
		MenuRouter.session_notice = ""
		if kind == "joined" and _online_joining:
			_online_joining = false
			public_service.game_connected()
			session.set_loadout(PlayerProfile.active_loadout())
			MenuRouter.goto("lobby", false)

func _online_assignment(assignment: Dictionary) -> void:
	if MenuRouter.lobby_intent != "online" or MenuRouter.current != "online" or public_service.state != "ready" or session.connection_state != "offline":
		return
	var draft: Dictionary = PlayerProfile.active_loadout()
	if not session.registry.validate(draft).valid:
		public_service.game_failed()
		MenuRouter.session_notice = "Select a valid bot in the Garage before joining online."
		return
	_online_joining = true
	var error: int = session.join(str(assignment.address), int(assignment.port), "", str(assignment.admission_ticket))
	if error != OK:
		_online_joining = false
		public_service.game_failed()

func cancel_online() -> void:
	_online_joining = false
	if MenuRouter.lobby_intent == "online" and session.connection_state != "offline":
		session.leave()
	if is_instance_valid(public_service):
		public_service.cancel()

func _add_match_actions() -> void:
	var actions: Node = preview.return_button.get_parent()
	_forfeit = Button.new()
	_forfeit.text = "Vote to forfeit round"
	actions.add_child(_forfeit)
	_forfeit.pressed.connect(func() -> void:
		if session.match_view.get("phase") in ["active", "overtime"]:
			session.vote_forfeit())
	_rematch = Button.new()
	actions.add_child(_rematch)
	_rematch.pressed.connect(_request_rematch)

func _request_rematch() -> void:
	if session.connection_state not in ["hosting", "connected"] or session.match_view.get("phase") != "results":
		return
	var match_id := str(session.match_view.get("match_id", ""))
	if match_id.is_empty() or _vote_match == match_id:
		return
	_vote_match = match_id
	results_panel.mark_requested()
	session.vote_rematch()

func show_notice(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(560, 180))

func _exit_tree() -> void:
	if MenuRouter.host == self:
		MenuRouter.host = null
		MenuRouter.session = null
