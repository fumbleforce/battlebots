extends Node3D
const COOLING_ZONE_VISUALS = preload("res://scripts/presentation/cooling_zone_visuals.gd")
const SPREE_BANNER = preload("res://scripts/ui/spree_banner.gd")
const PRACTICE_LOADING = preload("res://scripts/ui/practice_loading_overlay.gd")
const BOT_MODEL_WARMUP = preload("res://scripts/presentation/bot_model_warmup.gd")
## Persistent game owner; imported screens navigate without replacing the live session.
@onready var session: MvpSession = $Session
@onready var source: SessionBotSource = $PlayerSource
@onready var preview: Node3D = $Preview
@onready var menu_host: Control = $MenuLayer/MenuHost
@onready var match_hud: MatchHud = $MatchLayer/MatchHud
var screen: Control
var _last_phase := ""
var _last_source: BotSource
var _last_source_key := ""
var _settings_from_menu := false
var settings_hub: SettingsHub
var _settings_session_open := false
var _settings_category := ""
var _settings_dismissing := false
var _settings_return_focus: Control
@export var video_settings_path := "user://video.cfg"
var graphics_runtime: GraphicsRuntime
var video_preferences: VideoPreferences
var video_settings: VideoSettingsPanel
var _video_overlay: Control
var _cli_handoff := false
var _forfeit: Button
var _rematch: Button
var _vote_match := ""
var _menu_music: AudioStreamPlayer
var _battle_music: AudioStreamPlayer
var public_service: PublicServiceClient
var _online_joining := false
var results_panel: MatchResults
var duel_scoreboard: DuelScoreboard
@export var audio_settings_path := "user://audio.cfg"
var audio_preferences: AudioPreferences
var gameplay_audio: GameplayAudio
var continuous_audio: ContinuousGameplayAudio
var audio_settings: AudioSettingsPanel
var audio_settings_button: Button
var _audio_overlay: Control
var _audio_caption: Label
var practice_hud: PracticeHud
var _restart_practice: Button
var cooling_zones: COOLING_ZONE_VISUALS
var spree_banner: SPREE_BANNER
var _practice_knocked_out := false
var _practice_return_screen := ""
var _default_return_text := ""
var _test_drive_entry: GarageTestDriveEntry
var _test_drive_screen := ""
## Loading card shown while a practice arena builds (#70).
var practice_loading: PRACTICE_LOADING
var _practice_loading := false
## True once the heavy bot models are loaded and held (#70).
var _models_warm := true
var game_menu_page: Control
var combat_hud: CombatHud
var pickup_visuals: PickupVisuals
var pickup_feed: PickupFeed
var pickup_notice: PickupNotice
var _diagnostics_canvas: Control
var world_markers: BotWorldMarkers
var impact_feedback: CombatImpactFeedback
var reconnect_panel: Control
var _recovering := false
var _resume_after_reconnect := false
var _reconnect_message := ""
@export var hud_settings_path := "user://hud.cfg"
var hud_preferences: HudPreferences
var hud_settings: HudSettingsPanel
var hud_settings_button: Button
var _hud_overlay: Control
var _menu_text_scale := 1.0

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
	preview.resume_button.pressed.disconnect(preview.capture_controls)
	preview.resume_button.pressed.connect(resume_gameplay)
	preview.settings_button.text = "Settings"
	preview.settings_button.pressed.disconnect(preview.open_settings)
	preview.settings_button.pressed.connect(open_settings)
	preview.settings_panel.closed.connect(_settings_closed)
	preview.settings_panel.input_panel.finished.connect(_controls_category_finished)
	_add_match_actions()
	game_menu_page = preload("res://scripts/ui/game_menu_page.gd").new()
	game_menu_page.configure(preview.pause_menu)
	_default_return_text = preview.return_button.text
	var results_layer := CanvasLayer.new()
	results_layer.layer = 6
	add_child(results_layer)
	results_panel = MatchResults.new()
	results_layer.add_child(results_panel)
	results_panel.rematch_requested.connect(_request_rematch)
	results_panel.leave_requested.connect(return_to_main)
	var scoreboard_layer := CanvasLayer.new()
	scoreboard_layer.layer = 5
	add_child(scoreboard_layer)
	duel_scoreboard = DuelScoreboard.new()
	scoreboard_layer.add_child(duel_scoreboard)
	practice_loading = PRACTICE_LOADING.new()
	add_child(practice_loading)
	var recovery_layer := CanvasLayer.new()
	recovery_layer.layer = 10
	add_child(recovery_layer)
	reconnect_panel = preload("res://scripts/ui/reconnect_panel.gd").new()
	recovery_layer.add_child(reconnect_panel)
	reconnect_panel.retry_requested.connect(_retry_connection)
	reconnect_panel.leave_requested.connect(return_to_main)
	reconnect_panel.hide()
	_add_gameplay_audio()
	_add_practice_hud()
	combat_hud = CombatHud.new()
	$MatchLayer.add_child(combat_hud)
	session.combat_event.connect(combat_hud.combat_event)
	world_markers = BotWorldMarkers.new()
	world_markers.name = "WorldMarkers"
	add_child(world_markers)
	world_markers.hide()
	impact_feedback = CombatImpactFeedback.new()
	impact_feedback.name = "ImpactFeedback"
	add_child(impact_feedback)
	impact_feedback.bind_session(session)
	practice_hud.reparent(combat_hud.canvas, false)
	pickup_visuals = PickupVisuals.new()
	pickup_visuals.name = "PickupVisuals"
	add_child(pickup_visuals)
	pickup_visuals.bind_session(session)
	pickup_feed = PickupFeed.new()
	pickup_feed.name = "PickupFeed"
	combat_hud.canvas.add_child(pickup_feed)
	pickup_feed.position = Vector2(28, 28)
	pickup_feed.size = Vector2(320, 0)
	pickup_feed.bind_names(pickup_visuals.names)
	session.pickup_collected.connect(func(event: Dictionary) -> void:
		pickup_feed.notify(event, session.local_entity)
		gameplay_audio.pickup_collected(event, session.local_entity))
	cooling_zones = COOLING_ZONE_VISUALS.new()
	cooling_zones.name = "CoolingZones"
	add_child(cooling_zones)
	cooling_zones.bind_session(session)
	spree_banner = SPREE_BANNER.new()
	spree_banner.name = "SPREE_BANNER"
	combat_hud.canvas.add_child(spree_banner)
	spree_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	spree_banner.position = Vector2(-400, 150)
	spree_banner.size = Vector2(800, 60)
	spree_banner.pivot_offset = Vector2(400, 30)
	spree_banner.bind_session(session)
	pickup_notice = PickupNotice.new()
	pickup_notice.name = "PickupNotice"
	combat_hud.canvas.add_child(pickup_notice)
	session.pickup_refused.connect(func(event: Dictionary) -> void: pickup_notice.notify(event, pickup_visuals.names))
	preview.dev_part_cycled.connect(_dev_part_cycled)
	_diagnostics_canvas = Control.new()
	_diagnostics_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$MatchLayer.add_child(_diagnostics_canvas)
	preview.network_diagnostics.reparent(_diagnostics_canvas, false)
	var caption_layer := _audio_caption.get_parent()
	_audio_caption.reparent(combat_hud.canvas)
	caption_layer.queue_free()
	_audio_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_audio_caption.position = Vector2(356, 460)
	_audio_caption.size = Vector2(568, 40)
	_style_auxiliary_hud()
	_add_hud_settings()
	_add_settings_hub()
	_add_menu_music()
	_add_battle_music()
	get_viewport().size_changed.connect(_resize_menu)
	_resize_menu()
	show_screen("main")
	# Load the heavy bot models in the background while the player is in the
	# menus, so starting a match does not pay for them (#70).
	if DisplayServer.get_name() != "headless":
		BOT_MODEL_WARMUP.begin()
		_models_warm = false
	if "--practice" in args:
		load_practice()

func _resize_menu() -> void:
	var extent := get_viewport().get_visible_rect().size
	var ratio := minf(extent.x / 1920.0, extent.y / 1080.0)
	menu_host.scale = Vector2.ONE * ratio
	# Keep the design scale while letting anchored backgrounds cover any aspect.
	menu_host.size = extent / maxf(ratio, 0.001)
	menu_host.position = Vector2.ZERO

func show_screen(key: String) -> void:
	if _cli_handoff or not MenuRouter.SCREENS.has(key):
		return
	duel_scoreboard.suppress(Input.is_action_pressed("scoreboard"))
	preview.release_controls(false)
	preview.pause_menu.hide()
	if is_instance_valid(screen):
		menu_host.remove_child(screen)
		screen.queue_free()
	screen = load(MenuRouter.SCREENS[key]).instantiate()
	menu_host.add_child(screen)
	menu_host.show()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_test_drive_screen = key if key in ["garage", "customize"] else ""
	_test_drive_entry = null
	if not _test_drive_screen.is_empty():
		_test_drive_entry = GarageTestDriveEntry.install(screen, load_practice.bind(key))
		_update_test_drive_entry()
	if screen.has_method("apply_text_scale"):
		screen.apply_text_scale(_menu_text_scale)
	_sync_music()

func _add_menu_music() -> void:
	_menu_music = AudioStreamPlayer.new()
	_menu_music.name = "MenuMusic"
	var melody := load("res://assets/audio/menu/system_discovery.mp3").duplicate() as AudioStreamMP3
	melody.loop = true
	_menu_music.stream = melody
	_menu_music.volume_db = -16.0
	_menu_music.bus = &"BBMusic"
	add_child(_menu_music)

func _add_battle_music() -> void:
	_battle_music = AudioStreamPlayer.new()
	_battle_music.name = "BattleMusic"
	var song := load("res://assets/audio/battle/relentless_action.mp3").duplicate() as AudioStreamMP3
	song.loop = true
	_battle_music.stream = song
	_battle_music.volume_db = -16.0
	_battle_music.bus = &"BBMusic"
	add_child(_battle_music)

func _add_gameplay_audio() -> void:
	audio_preferences = AudioPreferences.load_file(audio_settings_path)
	audio_preferences.apply()
	gameplay_audio = GameplayAudio.new()
	gameplay_audio.name = "GameplayAudio"
	add_child(gameplay_audio)
	continuous_audio = ContinuousGameplayAudio.new()
	continuous_audio.name = "ContinuousAudio"
	add_child(continuous_audio)
	gameplay_audio.cue_played.connect(func(cue: String) -> void:
		if cue in ["countdown", "start", "round_end", "results", "low_core", "recovery", "armor_break"]:
			continuous_audio.duck())
	session.combat_event.connect(_audio_combat_event)
	var captions := CanvasLayer.new()
	captions.layer = 5
	add_child(captions)
	_audio_caption = Label.new()
	_audio_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_audio_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_audio_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
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
		if is_instance_valid(combat_hud):
			_audio_caption.position = combat_hud.caption_bounds().position
			_audio_caption.size = combat_hud.caption_bounds().size
		_audio_caption.visible = not text.is_empty())
	_audio_caption.hide()
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
	var center := _settings_center(_audio_overlay)
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
	# A practice knockout keeps the player in the arena: the director respawns
	# the bot after a short countdown, shown by the combat HUD. Keys held through
	# the knockout must be released before they drive the respawned bot.
	var knocked_out := practice and view != null and view.eliminated
	if _practice_knocked_out and not knocked_out:
		preview.input_gate.require_release()
	_practice_knocked_out = knocked_out
	preview.resume_button.disabled = bot == null
	# The target already has an in-world health bar. Keep the practice fixture's
	# readout out of the normal fighting view.
	practice_hud.hide()
	if practice:
		var target := session.practice_target()
		practice_hud.render(view, target.read_view() if target != null else null)

## Local part shortcuts (#64): name the fitted part, or say why nothing changed.
func _dev_part_cycled(slot: String, result: Dictionary) -> void:
	var label: String = {"weapon":"WEAPON", "chassis":"BODY", "drive":"DRIVE"}.get(slot, slot.to_upper())
	if result.has("part"):
		pickup_notice.show_text("%s: %s" % [label, PickupFeed.describe({"part":result.part}, pickup_visuals.names)])
	elif result.get("refused") == "remote":
		pickup_notice.show_text("PART SHORTCUTS ONLY WORK IN GAMES HOSTED ON THIS COMPUTER")
	elif result.get("refused") == "no_fit":
		pickup_notice.show_text("NO OTHER %s FITS THIS BUILD" % label)

func restart_practice() -> void:
	if session.connection_state != "practice" or preview.settings_panel.visible or _general_settings_open():
		return
	preview.release_controls(false)
	var error := session.restart_practice()
	if error != OK:
		show_notice("Cannot restart practice: %s" % error_string(error))
		return
	resume_gameplay()

func open_audio_settings() -> void:
	_prepare_settings_category("audio")
	preview.settings_panel.hide()
	_audio_overlay.show()
	audio_settings.open_for(audio_preferences, audio_settings_path)

func _audio_settings_closed(_saved: bool) -> void:
	_audio_overlay.hide()
	_return_to_settings_hub()

func _add_hud_settings() -> void:
	hud_preferences = HudPreferences.load_file(hud_settings_path)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_hud_overlay = Control.new()
	layer.add_child(_hud_overlay)
	_hud_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.85)
	_hud_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := _settings_center(_hud_overlay)
	hud_settings = HudSettingsPanel.new()
	center.add_child(hud_settings)
	hud_settings.preview_changed.connect(_apply_hud_preferences)
	hud_settings.applied.connect(func(value: HudPreferences) -> void: hud_preferences = value)
	hud_settings.finished.connect(func(_saved: bool) -> void:
		_hud_overlay.hide()
		_return_to_settings_hub())
	_hud_overlay.hide()
	_apply_hud_preferences(hud_preferences)

func _add_settings_hub() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	settings_hub = SettingsHub.new()
	layer.add_child(settings_hub)
	settings_hub.category_requested.connect(_open_settings_category)
	settings_hub.back_requested.connect(_close_settings_hub)
	audio_settings_button = settings_hub.buttons.audio
	hud_settings_button = settings_hub.buttons.accessibility
	settings_hub.apply_text_scale(_menu_text_scale)
	var video_layer := CanvasLayer.new()
	video_layer.layer = 20
	add_child(video_layer)
	_video_overlay = Control.new()
	video_layer.add_child(_video_overlay)
	_video_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.06, 0.98)
	_video_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graphics_runtime = GraphicsRuntime.new()
	add_child(graphics_runtime)
	video_settings = VideoSettingsPanel.new()
	_settings_center(_video_overlay).add_child(video_settings)
	video_preferences = VideoPreferences.load_file(video_settings_path)
	if video_preferences.load_error != OK or not FileAccess.file_exists(video_settings_path):
		var load_error := video_preferences.load_error
		video_preferences = VideoPreferences.capture()
		video_preferences.load_error = load_error
	elif DisplayServer.get_name() != "headless":
		video_preferences.apply()
	graphics_runtime.apply(video_preferences.graphics)
	video_settings.graphics_apply = graphics_runtime.apply
	video_settings.applied.connect(func(value: VideoPreferences) -> void: video_preferences = value)
	video_settings.finished.connect(func(_saved: bool) -> void:
		_video_overlay.hide()
		_return_to_settings_hub())
	video_settings.apply_text_scale(_menu_text_scale)
	_video_overlay.hide()
	# Theme B's published settings container here; its transactions, binding
	# capture, camera preview and source files remain owned by B.
	var camera_panel: Control = preview.settings_panel.get_node("Center/Panel")
	preview.settings_panel.theme = SettingsStyle.make_theme()
	camera_panel.remove_theme_stylebox_override("panel")
	camera_panel.theme_type_variation = &""
	camera_panel.add_theme_stylebox_override("panel",SettingsStyle.box(SettingsStyle.INK,SettingsStyle.LINE,28))
	preview.settings_panel.form.get_node("Title").text = "CAMERA SETTINGS"
	preview.settings_panel.form.get_node("Title").remove_theme_color_override("font_color")
	preview.settings_panel.form.get_node("Title").theme_type_variation = &"Heading"
	preview.settings_panel.form.get_node("Buttons/Save").text = "Save"
	for overlay: Control in [_audio_overlay, _hud_overlay, _video_overlay, preview.settings_panel]:
		var background := TextureRect.new()
		background.texture = preload("res://ui/menus/art/bg_arena_blur.jpg")
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(background)
		overlay.move_child(background, 0)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for child: Node in overlay.get_children():
			if child is ColorRect:
				child.color = Color(0.035, 0.045, 0.06, 0.93)
	get_viewport().size_changed.connect(_fit_camera_settings)
	_fit_camera_settings()
	preview.settings_panel.apply_text_scale(_menu_text_scale)

func _fit_camera_settings() -> void:
	var center: CenterContainer = preview.settings_panel.get_node("Center")
	center.scale = Vector2.ONE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _prepare_settings_category(category: String) -> void:
	if not _settings_session_open:
		open_settings()
	_settings_category = category
	settings_hub.hide()
	menu_host.hide()
	preview.release_controls(false)
	preview.pause_menu.hide()

func _open_settings_category(category: String) -> void:
	match category:
		"audio": open_audio_settings()
		"accessibility": open_hud_settings()
		"video":
			_prepare_settings_category(category)
			_video_overlay.show()
			video_settings.open_for(video_preferences, video_settings_path)
		"camera", "controls":
			_prepare_settings_category(category)
			preview.open_settings()
			if category == "controls":
				preview.settings_panel.open_controls()

func _controls_category_finished() -> void:
	if _settings_session_open and _settings_category == "controls":
		# B first closes its input editor back to the camera form. Closing that
		# unchanged camera transaction returns directly to the hub category.
		preview.settings_panel.cancel()

func _return_to_settings_hub() -> void:
	preview.release_controls(false)
	preview.settings_panel.hide()
	preview.pause_menu.hide()
	if _recovering or _settings_dismissing:
		settings_hub.hide()
		_settings_session_open = false
		return
	settings_hub.open(_settings_category if not _settings_category.is_empty() else "video")

func _close_settings_hub() -> void:
	settings_hub.hide()
	_settings_session_open = false
	_settings_category = ""
	preview.release_controls(false)
	if _settings_from_menu:
		menu_host.show()
		preview.pause_menu.hide()
		if is_instance_valid(_settings_return_focus) and _settings_return_focus.is_visible_in_tree():
			_settings_return_focus.grab_focus()
		elif is_instance_valid(screen):
			var focus := screen.find_next_valid_focus()
			if focus:
				focus.grab_focus()
	else:
		preview.pause_menu.show()
		preview.settings_button.grab_focus()
	_settings_from_menu = false

func _dismiss_settings() -> void:
	_settings_dismissing = true
	if is_instance_valid(_audio_overlay) and _audio_overlay.visible:
		audio_settings.cancel()
	if is_instance_valid(_hud_overlay) and _hud_overlay.visible:
		hud_settings.cancel()
	if is_instance_valid(_video_overlay) and _video_overlay.visible:
		video_settings.cancel()
	# Capture cancellation, controls cancellation and camera cancellation are
	# separate B transactions. Complete each when navigating away entirely.
	for step in 3:
		if preview.settings_panel.visible:
			preview.settings_panel.cancel()
	if is_instance_valid(settings_hub):
		settings_hub.hide()
	_settings_session_open = false
	_settings_from_menu = false
	_settings_dismissing = false

func _settings_center(overlay: Control) -> CenterContainer:
	var center := preload("res://scripts/ui/settings_category_frame.gd").new()
	center.name = "SettingsPage"
	overlay.add_child(center)
	return center

func open_hud_settings() -> void:
	_prepare_settings_category("accessibility")
	preview.settings_panel.hide()
	_hud_overlay.show()
	hud_settings.open_for(hud_preferences, hud_settings_path)

func _general_settings_open() -> bool:
	return _audio_overlay.visible or (is_instance_valid(_hud_overlay) and _hud_overlay.visible) \
		or (is_instance_valid(settings_hub) and settings_hub.visible) \
		or (is_instance_valid(_video_overlay) and _video_overlay.visible)

func _cancel_general_settings() -> void:
	if _hud_overlay.visible:
		hud_settings.cancel()
	elif _audio_overlay.visible:
		audio_settings.cancel()
	elif is_instance_valid(_video_overlay) and _video_overlay.visible:
		video_settings.cancel()
	elif is_instance_valid(settings_hub) and settings_hub.visible:
		_close_settings_hub()

func _apply_hud_preferences(value: HudPreferences) -> void:
	duel_scoreboard.apply_accessibility(value.text_scale, value.palette, value.high_contrast)
	world_markers.apply_accessibility(value.text_scale, value.palette, value.high_contrast)
	_menu_text_scale = value.text_scale
	# The shared text preference also reaches B's camera and input settings.
	preview.settings_panel.apply_text_scale(_menu_text_scale)
	for entry: Button in [audio_settings_button, hud_settings_button]:
		if is_instance_valid(entry):
			MenuTextScale.apply(entry, _menu_text_scale)
	for panel: Control in [screen, game_menu_page, results_panel, reconnect_panel, audio_settings, hud_settings, settings_hub, video_settings]:
		if is_instance_valid(panel) and panel.has_method("apply_text_scale"):
			panel.apply_text_scale(_menu_text_scale)
	combat_hud.apply_accessibility(value.text_scale, value.palette, value.high_contrast)
	pickup_feed.apply_text_scale(value.text_scale)
	pickup_notice.apply_text_scale(value.text_scale)
	match_hud.apply_accessibility(value.text_scale, value.palette, value.high_contrast)
	_audio_caption.add_theme_font_size_override("font_size", roundi(18 * value.text_scale))
	var caption: Rect2 = combat_hud.caption_bounds()
	_audio_caption.position = caption.position
	_audio_caption.size = caption.size
	_audio_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var large := value.text_scale > 1.0
	practice_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	practice_hud.position = Vector2(24, 150) if large else Vector2(946, 174)
	practice_hud.size = Vector2(348, 0) if large else Vector2(310, 0)
	_scale_practice_labels(practice_hud, value.text_scale, 324.0 if large else 286.0)
	practice_hud.hint_label.visible = not large
	practice_hud.local_status.modulate = Color.WHITE if value.high_contrast else Color(1, 0.73, 0.35)
	for panel: PanelContainer in [practice_hud, preview.network_diagnostics]:
		var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.bg_color = Color.BLACK if value.high_contrast else Color(0.045, 0.06, 0.08, 0.94)
		style.border_color = Color.WHITE if value.high_contrast else Color("f5b82e")
		panel.add_theme_stylebox_override("panel", style)

func _scale_practice_labels(node: Node, factor: float, width: float) -> void:
	if node is Label:
		if not node.has_meta("hud_base_font"):
			node.set_meta("hud_base_font", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("hud_base_font")) * factor))
		node.custom_minimum_size.x = width
		node.size.x = width
	for child: Node in node.get_children():
		_scale_practice_labels(child, factor, width)

func _sync_music() -> void:
	if not is_instance_valid(_menu_music) or not is_instance_valid(_battle_music):
		return
	var in_menu: bool = not _recovering and (menu_host.visible or (_settings_from_menu and (preview.settings_panel.visible or _general_settings_open())))
	# Pause/settings do not end the battle or restart its soundtrack.
	var in_battle: bool = not _recovering and not in_menu \
		and session.connection_state in ["hosting", "connected", "practice"] \
		and session.match_view.get("phase") in ["countdown", "active", "overtime", "intermission"]
	if not in_menu and _menu_music.playing:
		_menu_music.stop()
	if not in_battle and _battle_music.playing:
		_battle_music.stop()
	if in_menu and not _menu_music.playing:
		_menu_music.play()
	if in_battle and not _battle_music.playing:
		_battle_music.play()

func gameplay_input_allowed() -> bool:
	var bot := session.local_source()
	return not _cli_handoff and not _recovering and not menu_host.visible and preview.controls_enabled \
		and not _general_settings_open() \
		and not preview.settings_panel.visible and get_window().has_focus() \
		and bot != null and not bot.read_view().eliminated \
		and session.match_view.get("phase") in ["active", "overtime"]

func scoreboard_allowed() -> bool:
	return not _cli_handoff and not _recovering and get_window().has_focus() \
		and session.connection_state in ["hosting", "connected"] \
		and session.match_view.get("mode") == "1v1" \
		and session.match_view.get("phase") in ["countdown", "active", "overtime", "intermission"] \
		and not menu_host.visible and not preview.pause_menu.visible \
		and not preview.settings_panel.visible and not _general_settings_open() \
		and not results_panel.visible and not preview.network_diagnostics.expanded

func _process(_delta: float) -> void:
	if _cli_handoff:
		return
	_update_test_drive_entry()
	if not _models_warm:
		_models_warm = BOT_MODEL_WARMUP.poll()
	var phase := str(session.match_view.get("phase", "lobby"))
	var bot := session.local_source()
	if _resume_after_reconnect and not session.match_view.is_empty() and (bot != null or phase == "lobby"):
		_resume_after_reconnect = false
		_recovering = false
		reconnect_panel.hide()
		_last_phase = ""
		if phase in ["countdown", "active", "overtime", "intermission"]:
			resume_gameplay()
		elif phase == "lobby":
			MenuRouter.goto("lobby", false)
	if _recovering:
		_sync_music()
		duel_scoreboard.suppress(Input.is_action_pressed("scoreboard"))
		continuous_audio.reset()
		get_tree().call_group(&"bot_action_audio", &"set_playback_enabled", false)
		preview.release_controls(false)
		preview.pause_menu.hide()
		menu_host.hide()
		results_panel.hide()
		match_hud.hide()
		combat_hud.hide()
		_diagnostics_canvas.hide()
		world_markers.hide()
		practice_hud.hide()
		preview.get_node("CanvasLayer").hide()
		preview.get_node("DiagnosticsLayer").hide()
		preview.network_diagnostics.hide()
		_audio_caption.hide()
		reconnect_panel.render(session.can_reconnect(), session.is_reconnecting(), session.reconnect_seconds_remaining(), _reconnect_message)
		return
	gameplay_audio.observe_match(session.match_view, session.connection_state == "practice")
	if bot != _last_source:
		_last_source = bot
		# A part pickup rebuilds the local bot under the same entity id. Only a new
		# match or entity re-binds, which recentres; a pickup keeps the player's orbit.
		var key := "%s:%s" % [session.match_view.get("match_id", ""), bot.get("entity_id") if bot != null else ""]
		if key != _last_source_key:
			_last_source_key = key
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
	var game_menu_open: bool = preview.pause_menu.visible or results_panel.visible or _general_settings_open()
	preview.get_node("CanvasLayer").visible = not menu_open and not preview.settings_panel.visible
	preview.get_node("DiagnosticsLayer").visible = not menu_open and not game_menu_open and not preview.settings_panel.visible
	preview.hud.hide()
	preview.hint.hide()
	match_hud.visible = bot != null and not menu_open and not game_menu_open and not preview.settings_panel.visible
	var local_view: BotView
	var published_views := session.bot_views()
	duel_scoreboard.update_hold(Input.is_action_pressed("scoreboard"), scoreboard_allowed())
	if duel_scoreboard.visible:
		duel_scoreboard.render(session.match_view, session.lobby_view, published_views,
			session.local_entity, preview.input_preferences.label_for(&"scoreboard"),
			bool(session.diagnostics.get("degraded", false)))
	for candidate: BotView in published_views:
		if candidate.entity_id == session.local_entity:
			local_view = candidate
			break
	match_hud.render(session.match_view, session.connection_state == "practice", local_view.team if local_view != null else -1)
	combat_hud.visible = match_hud.visible
	pickup_feed.render(session.pickup_view, session.local_entity, session.connection_state == "practice")
	# Enlarged text moves the practice panel to the top-left; stack beneath it.
	var practice_left := practice_hud.visible and practice_hud.position.x < 400.0
	pickup_feed.position.y = practice_hud.position.y + practice_hud.size.y + 12.0 if practice_left else 28.0
	# Centred just above the audio caption band so the two never overlap.
	pickup_notice.size = pickup_notice.get_combined_minimum_size()
	pickup_notice.position = Vector2((combat_hud.canvas.size.x - pickup_notice.size.x) * 0.5,
		combat_hud.caption_bounds().position.y - pickup_notice.size.y - 6.0)
	# Diagnostics remain available from the pause screen; ordinary play only
	# surfaces a connection warning when the session reports degradation.
	_diagnostics_canvas.visible = preview.pause_menu.visible and not menu_open and not _general_settings_open() and not preview.settings_panel.visible
	_diagnostics_canvas.size = combat_hud.canvas.size
	_diagnostics_canvas.scale = combat_hud.canvas.scale
	combat_hud.connection_label.visible = combat_hud.visible and session.connection_state == "connected" and phase in ["active", "overtime"] and bool(session.diagnostics.get("degraded", false))
	var audio_records := session.audio_views()
	var local_audio: Dictionary = {}
	for record: Dictionary in audio_records:
		if record.entity_id == session.local_entity and record.age <= ContinuousGameplayAudio.MAX_AGE:
			local_audio = record
			break
	gameplay_audio.observe_bot(local_view if not local_audio.is_empty() else null,
		str(local_audio.get("weapon", "")))
	continuous_audio.render(audio_records, combat_hud.visible
		and phase in ["active", "overtime"] and local_view != null
		and (session.connection_state == "practice" or session.match_view.get("mode") == "1v1"))
	# Weapon/gait voices share the existing gameplay visibility gate. Resetting
	# their baselines prevents pending steps or old shots replaying on return.
	get_tree().call_group(&"bot_action_audio", &"set_playback_enabled",
		combat_hud.visible and phase in ["active", "overtime"] and local_view != null)
	world_markers.visible = combat_hud.visible
	# Read presentation poses after child bot smoothing has advanced this frame.
	_update_world_markers.call_deferred()
	var opponent: BotView
	if session.match_view.get("mode") == "1v1" and local_view != null:
		for candidate: BotView in published_views:
			if candidate.entity_id != local_view.entity_id and candidate.team != local_view.team:
				opponent = candidate
				break
	combat_hud.respawn_remaining = session.practice_director.player_respawn_remaining() \
		if session.connection_state == "practice" and session.practice_director != null else NAN
	combat_hud.render(local_view, preview.input_preferences.label_for(&"recover"), opponent,
		session.connection_state == "practice", session.match_view.get("mode") == "1v1", phase in ["active", "overtime"],
		bot.loadout.get("parts", {}) if bot != null and local_view != null and bot.entity_id == local_view.entity_id else {})
	_audio_caption.position = combat_hud.caption_bounds().position
	_audio_caption.size = combat_hud.caption_bounds().size
	_update_practice(bot)
	if menu_open:
		preview.pause_menu.hide()
	_forfeit.visible = session.connection_state in ["hosting", "connected"] and phase in ["active", "overtime"]
	_forfeit.text = "Forfeit" if session.match_view.get("mode") == "ffa" else "Vote to forfeit round"
	_rematch.visible = session.connection_state in ["hosting", "connected"] and phase == "results"
	_rematch.disabled = _vote_match == str(session.match_view.get("match_id", ""))
	_rematch.text = "Rematch requested" if _rematch.disabled else "Request rematch"
	_sync_pause_focus()
	_sync_music()

func _update_world_markers() -> void:
	if not is_instance_valid(world_markers) or not is_instance_valid(session):
		return
	world_markers.render(session.bot_views(), session.local_entity,
		session.connection_state == "practice", session.match_view.get("mode") == "1v1")

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

func _test_drive_allowed() -> bool:
	if _test_drive_screen.is_empty() or not is_instance_valid(screen) or not menu_host.visible:
		return false
	if session.connection_state != "offline" or _general_settings_open() or preview.settings_panel.visible:
		return false
	if is_instance_valid(public_service) and public_service.can_cancel(): return false
	for child: Node in get_children():
		if child is Window and child.visible: return false
	var recovery: Variant = screen.get("recovery_panel")
	return not (recovery is Control and recovery.is_visible_in_tree())

func _update_test_drive_entry() -> void:
	if not is_instance_valid(_test_drive_entry): return
	var index: int = PlayerProfile.active_bot
	var draft: Dictionary = PlayerProfile.loadouts[index] if index >= 0 and index < PlayerProfile.loadouts.size() else {}
	_test_drive_entry.render(draft, _test_drive_allowed())

## Player-facing Practice start: draws the loading card first, builds behind it
## and lifts it once the arena's first frames (and their first-use shader setup)
## have drawn. start_practice() stays synchronous for direct callers and tests.
func load_practice(return_screen: String = "", kind := "full") -> void:
	if _practice_loading or session.connection_state != "offline":
		return
	_practice_loading = true
	practice_loading.present(preload("res://scripts/arena/arena_scenery.gd").load_choice())
	await _drawn_frame()
	if is_inside_tree():
		start_practice(return_screen, kind)
		if session.connection_state == "practice":
			for frame: int in 2:
				await _drawn_frame()
	_practice_loading = false
	if is_inside_tree():
		practice_loading.lift()

## Waits until a frame has been drawn; headless builds draw nothing, so a
## processed frame stands in.
func _drawn_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw

func start_practice(return_screen: String = "", kind := "full") -> void:
	if not return_screen.is_empty() and (return_screen != _test_drive_screen or not _test_drive_allowed()):
		return
	if session.connection_state != "offline":
		return
	var draft: Dictionary = PlayerProfile.active_loadout()
	if draft.is_empty() or not session.registry.validate(draft).valid:
		show_notice("Repair and select a valid build in the garage before starting practice.")
		return
	var error := session.practice(draft, preload("res://scripts/arena/arena_scenery.gd").load_choice(), kind)
	if error == OK:
		_practice_return_screen = return_screen
		preview.return_button.text = "BACK TO BUILD" if not return_screen.is_empty() else _default_return_text
		resume_gameplay()
	else:
		show_notice("Cannot start practice: %s" % error_string(error))

func resume_gameplay() -> void:
	if _general_settings_open():
		return
	if session.match_view.get("phase") == "results":
		return
	if session.local_source() == null or preview.settings_panel.visible:
		return
	if session.match_view.get("phase") not in ["countdown", "active", "overtime", "intermission", "results"]:
		return
	menu_host.hide()
	preview.network_diagnostics.expanded = false
	# Hidden workshop shortcuts must not edit the draft behind a running test drive.
	if is_instance_valid(screen): screen.process_mode = Node.PROCESS_MODE_DISABLED
	_sync_music()
	preview.capture_controls()

## Ordinary sessions leave to main; workshop practice restores its build screen.
func return_to_main() -> void:
	var destination := _practice_return_screen if session.connection_state == "practice" and not _practice_return_screen.is_empty() else "main"
	_practice_return_screen = ""
	preview.return_button.text = _default_return_text
	_dismiss_settings()
	duel_scoreboard.suppress(Input.is_action_pressed("scoreboard"))
	_recovering = false
	_resume_after_reconnect = false
	reconnect_panel.hide()
	preview.release_controls(false)
	if is_instance_valid(public_service) and (MenuRouter.lobby_intent == "online" or public_service.can_cancel()):
		cancel_online()
	session.leave()
	gameplay_audio.reset()
	continuous_audio.reset()
	_last_phase = ""
	_vote_match = ""
	results_panel.hide()
	results_panel.clear_record()
	MenuRouter.goto(destination, false)

func open_settings() -> void:
	if _settings_session_open:
		return
	_settings_from_menu = menu_host.visible
	_settings_return_focus = get_viewport().gui_get_focus_owner()
	_settings_session_open = true
	_settings_category = ""
	duel_scoreboard.suppress(Input.is_action_pressed("scoreboard"))
	preview.release_controls(false)
	preview.pause_menu.hide()
	menu_host.hide()
	settings_hub.open()

func _settings_closed(_saved: bool) -> void:
	preview.release_controls(false)
	if _settings_dismissing:
		return
	if _settings_session_open:
		_return_to_settings_hub()
		return
	if _settings_from_menu:
		menu_host.show()
		preview.pause_menu.hide()
		if is_instance_valid(screen):
			var focus := screen.find_next_valid_focus()
			if focus:
				focus.grab_focus()
	_settings_from_menu = false

func _input(event: InputEvent) -> void:
	if not _cli_handoff and event.is_action("scoreboard") and (scoreboard_allowed() or duel_scoreboard.visible):
		get_viewport().set_input_as_handled()
		return
	if _cli_handoff or not event.is_action_pressed("pause"):
		return
	if _recovering:
		get_viewport().set_input_as_handled()
		return
	if _general_settings_open():
		get_viewport().set_input_as_handled()
		_cancel_general_settings()
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
	if kind in ["left", "hosted", "joined"]:
		pickup_feed.clear_toasts()
		pickup_notice.clear()
		_practice_return_screen = ""
		preview.return_button.text = _default_return_text
	if kind == "practice_restarted":
		gameplay_audio.reset()
		continuous_audio.reset()
	if kind == "results":
		results_panel.accept_record(details, str(session.match_view.get("match_id", "")))
		# Server-computed reward; the wallet ignores repeats of the same match.
		if session.connection_state != "practice":
			PlayerProfile.bank_match_credits(str(details.get("match", {}).get("match_id", "")),
				CreditWallet.reward_for(details, session.local_entity))
	elif kind == "error":
		MenuRouter.session_notice = str(details.get("message", "Session error"))
		if _recovering or session.can_reconnect():
			_reconnect_message = MenuRouter.session_notice
			if not _recovering:
				_recovering = true
				gameplay_audio.reset()
				continuous_audio.reset()
				if _general_settings_open():
					_cancel_general_settings()
				if preview.settings_panel.visible:
					preview.settings_panel.cancel()
				reconnect_panel.show()
				reconnect_panel.render(session.can_reconnect(), session.is_reconnecting(), session.reconnect_seconds_remaining(), _reconnect_message)
				reconnect_panel.retry.grab_focus()
			return
		if _online_joining or (MenuRouter.lobby_intent == "online" and session.connection_state == "offline" and public_service.state in ["ready", "connected"]):
			_online_joining = false
			public_service.game_failed()
			MenuRouter.goto("online", false)
	elif kind in ["left", "hosted", "joined", "practice"]:
		MenuRouter.session_notice = ""
		if kind == "joined" and bool(details.get("reconnected", false)):
			_resume_after_reconnect = true
			return
		if kind == "joined" and _online_joining:
			_online_joining = false
			public_service.game_connected()
			session.set_loadout(PlayerProfile.active_loadout())
			MenuRouter.goto("lobby", false)

func _retry_connection() -> void:
	if not _recovering or not session.can_reconnect() or session.is_reconnecting():
		return
	_reconnect_message = ""
	var error := session.reconnect()
	if error != OK:
		_reconnect_message = "Could not reconnect. You can leave this match or retry while recovery is available."

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
