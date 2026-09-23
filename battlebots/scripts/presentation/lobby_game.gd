extends Node3D
## Playable B frontend using A's session and exactly one local input producer.
@onready var session: MvpSession = $Session
@onready var source: SessionBotSource = $PlayerSource
@onready var preview: Node3D = $Preview
@onready var lobby: LobbyPanel = $LobbyLayer/Lobby
@onready var coordinator: LobbyCoordinator = $LobbyCoordinator
@onready var match_hud: Control = $MatchLayer/MatchHud
const ARENA_PHASES := ["countdown", "active", "overtime", "intermission", "results"]
var _last_phase := ""
var _last_source: BotSource
var _last_source_key := ""
var _leaving := false

func _ready() -> void:
	source.input_allowed = gameplay_input_allowed
	coordinator.bind(session, lobby)
	coordinator.resume_requested.connect(resume_gameplay)
	coordinator.return_requested.connect(return_to_launcher)
	coordinator.settings_requested.connect(open_settings)
	lobby.practice_requested.connect(start_practice)
	preview.settings_panel.closed.connect(_settings_closed)
	show_lobby()
	if "--practice" in OS.get_cmdline_user_args():
		start_practice()

func gameplay_input_allowed() -> bool:
	var bot := session.local_source()
	return not _leaving and preview.controls_enabled and not lobby.visible \
		and not preview.settings_panel.visible and get_window().has_focus() \
		and bot != null and not bot.read_view().eliminated \
		and str(session.match_view.get("phase", "")) in ["active", "overtime"]

func _process(_delta: float) -> void:
	var phase := str(session.match_view.get("phase", "lobby"))
	var bot := session.local_source()
	if bot != _last_source:
		_last_source = bot
		# A part pickup rebuilds the local bot under the same entity id. Only a new
		# match or entity re-binds, which recentres; a pickup keeps the player's orbit.
		var key := "%s:%s" % [session.match_view.get("match_id", ""), bot.get("entity_id") if bot != null else ""]
		if key != _last_source_key:
			_last_source_key = key
			preview.rig.bind_source(source)
	if phase != _last_phase:
		var entering_arena := _last_phase not in ARENA_PHASES
		_last_phase = phase
		if entering_arena and phase in ["countdown", "active"] and not preview.settings_panel.visible and get_window().has_focus():
			resume_gameplay()
		elif phase not in ARENA_PHASES:
			show_lobby()
	var show_menu: bool = not preview.controls_enabled and not preview.settings_panel.visible
	if lobby.visible != show_menu:
		lobby.visible = show_menu
		if show_menu:
			lobby.focus_default()
	preview.get_node("CanvasLayer").visible = not lobby.visible and not preview.settings_panel.visible
	# Lobby already presents connection state; preserve screen space for its roster.
	preview.get_node("DiagnosticsLayer").visible = not lobby.visible
	preview.hud.visible = bot != null
	match_hud.visible = bot != null and not lobby.visible and not preview.settings_panel.visible
	match_hud.render(session.match_view, session.connection_state == "practice")

func show_lobby() -> void:
	preview.release_controls(false)
	lobby.visible = not preview.settings_panel.visible
	coordinator.refresh()
	if lobby.visible:
		lobby.focus_default()

func resume_gameplay() -> void:
	if _leaving or session.local_source() == null or preview.settings_panel.visible:
		return
	if str(session.match_view.get("phase", "")) not in ARENA_PHASES:
		return
	lobby.hide()
	preview.capture_controls()

func start_practice() -> void:
	if session.connection_state != "offline":
		return
	var error := session.practice()
	if error != OK:
		coordinator.notice = "Could not start practice: %s" % error_string(error)
		coordinator.refresh()

func open_settings() -> void:
	lobby.hide()
	preview.open_settings()

func _settings_closed(_saved: bool) -> void:
	# Invalidate the preview's deferred auto-resume; the frontend owns navigation.
	show_lobby()

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or _leaving:
		return
	get_viewport().set_input_as_handled()
	if preview.settings_panel.visible:
		preview.settings_panel.cancel()
	elif preview.controls_enabled:
		show_lobby()
	else:
		resume_gameplay()

func return_to_launcher() -> void:
	if _leaving:
		return
	_leaving = true
	preview.release_controls(false)
	session.leave()
	get_viewport().set_input_as_handled()
	get_tree().change_scene_to_file.call_deferred("res://scenes/app/main.tscn")
