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
@export var audio_settings_path := "user://audio.cfg"
var audio_preferences: AudioPreferences
var gameplay_audio: GameplayAudio
var audio_settings: AudioSettingsPanel
var audio_settings_button: Button
var _audio_overlay: Control
var _audio_caption: Label
var practice_hud: PracticeHud
var _restart_practice: Button
var _practice_knockout_handled := false
var game_menu_page: Control
var combat_hud: CombatHud

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
	preview.settings_button.text = "Settings"
	preview.settings_panel.closed.connect(_settings_closed)
	_add_match_actions()
	game_menu_page = preload("res://scripts/ui/game_menu_page.gd").new()
	game_menu_page.configure(preview.pause_menu)
	preview.network_diagnostics.interaction_started.connect(_network_details_interaction)
	var results_layer := CanvasLayer.new()
	results_layer.layer = 6
	add_child(results_layer)
	results_panel = MatchResults.new()
	results_layer.add_child(results_panel)
	results_panel.rematch_requested.connect(_request_rematch)
	results_panel.leave_requested.connect(return_to_main)
	_add_gameplay_audio()
	_add_practice_hud()
	combat_hud = CombatHud.new()
	$MatchLayer.add_child(combat_hud)
	practice_hud.reparent(combat_hud.canvas, false)
	preview.network_diagnostics.reparent(combat_hud.canvas, false)
	var caption_layer := _audio_caption.get_parent()
	_audio_caption.reparent(combat_hud.canvas)
	caption_layer.queue_free()
	_audio_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_audio_caption.position = Vector2(356, 460)
	_audio_caption.size = Vector2(568, 40)
	_style_auxiliary_hud()
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
	_menu_music.bus = &"BBMusic"
	add_child(_menu_music)

func _add_gameplay_audio() -> void:
	audio_preferences = AudioPreferences.load_file(audio_settings_path)
	audio_preferences.apply()
	gameplay_audio = GameplayAudio.new()
	gameplay_audio.name = "GameplayAudio"
	add_child(gameplay_audio)
	session.combat_event.connect(_audio_combat_event)
	var captions := CanvasLayer.new()
	captions.layer = 5
	add_child(captions)
	_audio_caption = Label.new()
	_audio_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_audio_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_audio_caption.add_theme_font_size_override("font_size", 24)
	_audio_caption.add_theme_constant_override("outline_size", 6)
	_audio_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	captions.add_child(_audio_caption)
	_audio_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_audio_caption.offset_left = 16
	_audio_caption.offset_right = -16
	_audio_caption.offset_top = -58
	_audio_caption.offset_bottom = -20
	gameplay_audio.caption_changed.connect(func(text: String) -> void:
		_audio_caption.text = text
		_audio_caption.visible = not text.is_empty())
	_audio_caption.hide()
	# Compose general Audio settings without changing B's control settings code.
	audio_settings_button = Button.new()
	audio_settings_button.name = "AudioSettingsButton"
	audio_settings_button.text = "Audio…"
	audio_settings_button.custom_minimum_size.y = 36
	preview.settings_panel.form.get_node("Title").text = "Settings"
	preview.settings_panel.form.add_child(audio_settings_button)
	audio_settings_button.pressed.connect(open_audio_settings)
	var audio_layer := CanvasLayer.new()
	audio_layer.layer = 20
	add_child(audio_layer)
	_audio_overlay = Control.new()
	audio_layer.add_child(_audio_overlay)
	_audio_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.8)
	_audio_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_audio_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio_settings = AudioSettingsPanel.new()
	center.add_child(audio_settings)
	audio_settings.applied.connect(func(preferences: AudioPreferences) -> void: audio_preferences = preferences)
	audio_settings.finished.connect(_audio_settings_closed)
	_audio_overlay.hide()

func _audio_combat_event(event: Dictionary) -> void:
	gameplay_audio.observe_match(session.match_view, session.connection_state == "practice")
	gameplay_audio.combat_event(event, session.local_entity)

func _add_practice_hud() -> void:
	practice_hud = PracticeHud.new()
	$MatchLayer.add_child(practice_hud)
	practice_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	practice_hud.offset_left = -334
	practice_hud.offset_right = -24
	practice_hud.offset_top = 174
	practice_hud.offset_bottom = 394
	practice_hud.hide()

func _style_auxiliary_hud() -> void:
	for panel: PanelContainer in [practice_hud, preview.network_diagnostics]:
		panel.theme = preload("res://ui/menus/theme/menu_theme.tres")
		var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.bg_color = Color(0.045, 0.06, 0.08, 0.94)
		style.border_color = Color("f5b82e")
		panel.add_theme_stylebox_override("panel", style)
	preview.network_diagnostics.details_button.theme_type_variation = &"GhostButton"
	preview.network_diagnostics.details_button.add_theme_font_size_override("font_size", 16)

func _update_practice(bot: BotSource) -> void:
	var practice := session.connection_state == "practice"
	_restart_practice.visible = practice
	var view: BotView = bot.read_view() if bot != null else null
	var knocked_out := practice and view != null and view.eliminated
	var modal: bool = preview.settings_panel.visible or _audio_overlay.visible or menu_host.visible
	if knocked_out and (not _practice_knockout_handled or preview.controls_enabled) and not modal:
		preview.release_controls(false)
		_restart_practice.grab_focus()
		_practice_knockout_handled = true
	preview.resume_button.disabled = knocked_out or bot == null
	practice_hud.visible = practice and not modal and not preview.pause_menu.visible and not preview.network_diagnostics.expanded
	if practice:
		var target := session.practice_target()
		practice_hud.render(view, target.read_view() if target != null else null)

func restart_practice() -> void:
	if session.connection_state != "practice" or preview.settings_panel.visible or _audio_overlay.visible:
		return
	preview.release_controls(false)
	var error := session.restart_practice()
	if error != OK:
		show_notice("Cannot restart practice: %s" % error_string(error))
		return
	resume_gameplay()

func open_audio_settings() -> void:
	preview.release_controls(false)
	preview.settings_panel.hide()
	_audio_overlay.show()
	audio_settings.open_for(audio_preferences, audio_settings_path)

func _audio_settings_closed(_saved: bool) -> void:
	_audio_overlay.hide()
	preview.settings_panel.show()
	audio_settings_button.grab_focus()

func _sync_menu_music() -> void:
	if not is_instance_valid(_menu_music):
		return
	var in_menu: bool = menu_host.visible or (_settings_from_menu and (preview.settings_panel.visible or _audio_overlay.visible))
	if in_menu and not _menu_music.playing:
		_menu_music.play()
	elif not in_menu and _menu_music.playing:
		_menu_music.stop()

func gameplay_input_allowed() -> bool:
	var bot := session.local_source()
	return not _cli_handoff and not menu_host.visible and preview.controls_enabled \
		and not _audio_overlay.visible \
		and not preview.settings_panel.visible and get_window().has_focus() \
		and bot != null and not bot.read_view().eliminated \
		and session.match_view.get("phase") in ["active", "overtime"]

func _process(_delta: float) -> void:
	if _cli_handoff:
		return
	var phase := str(session.match_view.get("phase", "lobby"))
	var bot := session.local_source()
	gameplay_audio.observe_match(session.match_view, session.connection_state == "practice")
	if bot != null:
		gameplay_audio.observe_bot(bot.read_view())
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
	results_panel.render(session.match_view, session.local_entity, bot.read_view().team if bot != null else -1)
	game_menu_page.render(session.match_view, session.connection_state == "practice")
	var menu_open := menu_host.visible
	var game_menu_open: bool = preview.pause_menu.visible or results_panel.visible or _audio_overlay.visible
	preview.get_node("CanvasLayer").visible = not menu_open and not preview.settings_panel.visible
	preview.get_node("DiagnosticsLayer").visible = not menu_open and not game_menu_open and not preview.settings_panel.visible
	preview.hud.hide()
	preview.hint.hide()
	match_hud.visible = bot != null and not menu_open and not game_menu_open and not preview.settings_panel.visible
	var local_view: BotView
	var published_views := session.bot_views()
	for candidate: BotView in published_views:
		if candidate.entity_id == session.local_entity:
			local_view = candidate
			break
	match_hud.render(session.match_view, session.connection_state == "practice", local_view.team if local_view != null else -1)
	combat_hud.visible = match_hud.visible
	var opponent: BotView
	if session.match_view.get("mode") == "1v1" and local_view != null:
		for candidate: BotView in published_views:
			if candidate.entity_id != local_view.entity_id and candidate.team != local_view.team:
				opponent = candidate
				break
	combat_hud.render(local_view, preview.input_preferences.label_for(&"recover"), opponent,
		session.connection_state == "practice", session.match_view.get("mode") == "1v1", phase in ["active", "overtime"])
	_update_practice(bot)
	if menu_open:
		preview.pause_menu.hide()
	_forfeit.visible = session.connection_state in ["hosting", "connected"] and phase in ["active", "overtime"]
	_forfeit.text = "Forfeit" if session.match_view.get("mode") == "ffa" else "Vote to forfeit round"
	_rematch.visible = session.connection_state in ["hosting", "connected"] and phase == "results"
	_rematch.disabled = _vote_match == str(session.match_view.get("match_id", ""))
	_rematch.text = "Rematch requested" if _rematch.disabled else "Request rematch"
	_sync_pause_focus()
	_sync_menu_music()

func _sync_pause_focus() -> void:
	var buttons: Array[Button] = []
	for child: Node in preview.return_button.get_parent().get_children():
		if child is Button and child.visible and not child.disabled:
			buttons.append(child)
	for index: int in range(buttons.size()):
		var button := buttons[index]
		var next := button.get_path_to(buttons[(index + 1) % buttons.size()])
		var previous := button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		button.focus_next = next
		button.focus_neighbor_bottom = next
		button.focus_previous = previous
		button.focus_neighbor_top = previous

func _network_details_interaction() -> void:
	# The preview releases controls on button-down. Keep the clicked panel visible
	# until release so its Details button can complete the interaction.
	if not menu_host.visible and not results_panel.visible and not preview.settings_panel.visible and not _audio_overlay.visible:
		preview.pause_menu.hide()

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
	if _audio_overlay.visible:
		return
	if session.match_view.get("phase") == "results":
		return
	if session.local_source() == null or preview.settings_panel.visible:
		return
	if session.connection_state == "practice" and session.local_source().read_view().eliminated:
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
	gameplay_audio.reset()
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
	if _audio_overlay.visible:
		get_viewport().set_input_as_handled()
		audio_settings.cancel()
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
	if kind in ["practice", "practice_restarted", "left"]:
		_practice_knockout_handled = false
	if kind == "practice_restarted":
		gameplay_audio.reset()
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
	_restart_practice = Button.new()
	_restart_practice.name = "RestartPractice"
	_restart_practice.text = "Restart practice"
	_restart_practice.custom_minimum_size.y = 40
	_restart_practice.hide()
	actions.add_child(_restart_practice)
	actions.move_child(_restart_practice, preview.resume_button.get_index() + 1)
	_restart_practice.pressed.connect(restart_practice)
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
