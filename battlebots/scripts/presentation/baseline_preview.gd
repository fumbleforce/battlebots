extends Node3D
## B-owned input/presentation adapter; never writes authoritative bot transforms.

@export var source_path: NodePath
@export var fixture_title: String = "Development fixture"
@export var settings_path: String = CameraPreferences.DEFAULT_PATH
@onready var source: BotSource = get_node_or_null(source_path) as BotSource
@onready var rig: BotOrbitCamera = $OrbitCamera
@onready var hud: BotStatusHud = $CanvasLayer/BotStatusHud
@onready var hint: Label = $CanvasLayer/Hint
@onready var pause_menu: PanelContainer = $CanvasLayer/PauseMenu
@onready var resume_button: Button = $CanvasLayer/PauseMenu/Margin/Content/Resume
@onready var settings_button: Button = $CanvasLayer/PauseMenu/Margin/Content/Settings
@onready var return_button: Button = $CanvasLayer/PauseMenu/Margin/Content/Return
@onready var settings_panel: CameraSettingsPanel = $ModalLayer/CameraSettings
@onready var network_diagnostics: NetworkDiagnosticsPanel = $DiagnosticsLayer/NetworkDiagnostics
var sequence: int = 0
var controls_enabled: bool = false
var _resume_on_focus := false
var input_gate := GameplayInputGate.new()
var gamepad := GamepadInput.new()
var _controller_device := -1
var _load_notice: String = ""
var _control_generation: int = 0
var _leaving: bool = false
var input_preferences: InputPreferences
var _input_map_before: Dictionary = {}
var _diagnostics_epoch := ""
var _diagnostics_initial_samples := 0.0
var _diagnostics_fresh := false
## Turret aim: the camera crosshair ray, re-aimed from the turret trunnion.
const TURRET_AIM_DISTANCE := 220.0
var turret_reticle := TurretReticle.new()
var tank_sight := TankSightCamera.new()
var mortar_aim := MortarAimVisual.new()
## A local part shortcut was used (#64): slot and the session's result.
signal dev_part_cycled(slot: String, result: Dictionary)
const DEV_SLOTS := {&"dev_weapon":"weapon", &"dev_body":"chassis", &"dev_drive":"drive"}
var _turret_aim_point := Vector3.ZERO
var _reticle_point := Vector2.ZERO
var _kick_sequence := -1
var _reticle_seen := false

func _ready() -> void:
	hud.set_context(fixture_title)
	$CanvasLayer.add_child(turret_reticle)
	$CanvasLayer.move_child(turret_reticle, 0)
	tank_sight.rig = rig
	add_child(tank_sight)
	add_child(mortar_aim)
	rig.bind_source(source)
	var preferences := CameraPreferences.load_file(settings_path)
	preferences.apply_to(rig)
	if preferences.load_error != OK:
		_load_notice = "Saved settings could not be loaded. Using defaults."
	_input_map_before = InputPreferences.snapshot_input_map()
	var input_path := "" if settings_path.is_empty() else settings_path + ".input"
	if settings_path == CameraPreferences.DEFAULT_PATH:
		input_path = InputPreferences.DEFAULT_PATH
	input_preferences = InputPreferences.load_file(input_path)
	_apply_input_preferences(input_preferences)
	settings_panel.configure_inputs(input_preferences, input_path,
		"Saved controls could not be loaded. Using defaults." if input_preferences.load_error != OK else "")
	settings_panel.input_applied.connect(_apply_input_preferences)
	network_diagnostics.interaction_started.connect(_on_diagnostics_interaction)
	refresh_diagnostics()
	resume_button.pressed.connect(capture_controls)
	settings_button.pressed.connect(open_settings)
	return_button.pressed.connect(return_to_launcher)
	settings_panel.closed.connect(_on_settings_closed)
	Input.joy_connection_changed.connect(_on_controller_connection_changed)
	get_window().focus_exited.connect(_on_focus_lost)
	get_window().focus_entered.connect(_on_focus_regained)
	if DisplayServer.get_name() != "headless":
		capture_controls()
	else:
		release_controls()

func capture_controls() -> void:
	if _leaving or settings_panel.visible or not is_instance_valid(source):
		return
	_control_generation += 1
	controls_enabled = true
	pause_menu.hide()
	input_gate.require_release()
	gamepad.require_release()
	get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Losing window focus (a screenshot tool on Print Screen, alt-tab, overlays)
## still neutralises driving input and frees the mouse, but is not a request to
## pause: the menu stays hidden and control returns with focus.
func _on_focus_lost() -> void:
	if not controls_enabled:
		return
	_resume_on_focus = true
	release_controls(false)
	pause_menu.hide()

func _on_focus_regained() -> void:
	if not _resume_on_focus:
		return
	_resume_on_focus = false
	if not pause_menu.visible:
		capture_controls()

func _apply_input_preferences(preferences: InputPreferences) -> void:
	input_preferences = preferences
	input_preferences.apply_to_input_map()
	input_gate.toggle_primary = preferences.toggle_primary
	input_gate.require_release()
	gamepad.require_release()

func _on_diagnostics_interaction() -> void:
	release_controls(false)
	# Losing focus even briefly cancels a keyboard button's pending activation.
	network_diagnostics.details_button.grab_focus()

func release_controls(focus_menu: bool = true) -> void:
	if focus_menu:
		_resume_on_focus = false
	_control_generation += 1
	controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rig.driving = false
	pause_menu.visible = not settings_panel.visible and not _leaving
	resume_button.disabled = not is_instance_valid(source)
	_submit_neutral()
	if focus_menu:
		_focus_menu()

func _focus_menu() -> void:
	if not pause_menu.is_visible_in_tree() or _leaving:
		return
	if not resume_button.disabled:
		resume_button.grab_focus()
	else:
		return_button.grab_focus()

func open_settings() -> void:
	if _leaving:
		return
	release_controls()
	pause_menu.hide()
	settings_panel.open_for(rig, settings_path, _load_notice)

func _on_settings_closed(saved: bool) -> void:
	if saved:
		_load_notice = ""
	pause_menu.visible = not _leaving
	_focus_menu()
	if get_window().has_focus():
		_resume_after_settings.call_deferred(_control_generation)

func _resume_after_settings(generation: int) -> void:
	# Focus loss or another modal after close invalidates this pending resume.
	if generation == _control_generation and get_window().has_focus():
		capture_controls()

func _on_controller_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == _controller_device:
		_controller_device = -1
		gamepad.require_release()
		if controls_enabled:
			release_controls()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_controller_device = event.device
	elif event is InputEventJoypadMotion and absf(event.axis_value) > InputMap.action_get_deadzone("camera_look_right"):
		_controller_device = event.device
	elif (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_controller_device = -1
	elif event is InputEventMouseMotion and not event.screen_relative.is_zero_approx():
		_controller_device = -1
	if settings_panel.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		settings_panel.cancel()

func return_to_launcher() -> void:
	if _leaving:
		return
	_leaving = true
	get_viewport().set_input_as_handled()
	release_controls()
	_finish_return.call_deferred()

func _finish_return() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/app/main.tscn")

func _exit_tree() -> void:
	if not _input_map_before.is_empty():
		InputPreferences.restore_input_map(_input_map_before)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _submit_neutral() -> void:
	if not is_instance_valid(source):
		return
	var command := input_gate.sample({}, {}, false)
	command.sequence = sequence
	sequence += 1
	source.submit_command(command)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(source):
		if controls_enabled:
			release_controls()
		resume_button.disabled = true
		return
	var strengths: Dictionary = {}
	for action: StringName in GameplayInputGate.ACTIONS:
		strengths[action] = _action_strength(action)
	var edges := {
		&"primary": Input.is_action_just_pressed("primary"),
		&"secondary": Input.is_action_just_pressed("secondary"),
		&"recover": Input.is_action_just_pressed("recover"),
	}
	var enabled := controls_enabled and not settings_panel.visible \
		and not _leaving and get_window().has_focus()
	# Clear toggle intent during A's countdown/elimination/lifecycle suppression too.
	if source is SessionBotSource and source.input_allowed.is_valid():
		enabled = enabled and bool(source.input_allowed.call())
	var view := _source_view()
	input_gate.auxiliary_weapon = view.has_auxiliary_weapon
	input_gate.turret_main_gun = view.turret_kind != ""
	if enabled and source is SessionBotSource and is_instance_valid(source.session):
		for action: StringName in DEV_SLOTS:
			if InputMap.has_action(action) and Input.is_action_just_pressed(action):
				dev_part_cycled.emit(DEV_SLOTS[action], source.session.dev_cycle_part(DEV_SLOTS[action]))
	var command := input_gate.sample(strengths, edges, enabled)
	command.sequence = sequence
	sequence += 1
	var turret := view.turret_kind != ""
	if enabled and turret and not view.eliminated:
		_apply_turret_aim(command, view)
	# The camera is the turret sight: never auto-recenter it away from the aim.
	rig.driving = not turret and (absf(command.throttle) > 0.05 or absf(command.steering) > 0.05)
	source.submit_command(command)

func _turret_scale() -> float:
	var anchor := source.camera_anchor()
	return float(anchor.get_meta("bot_scale", BotScale.FACTOR)) if is_instance_valid(anchor) else BotScale.FACTOR

## World bearing/elevation from the turret trunnion to whatever the crosshair
## ray meets (world or bot, excluding this bot), else a far point along it.
## The active view camera: the tank sight for turret builds, else the orbit rig.
func aim_camera() -> Camera3D:
	return tank_sight.camera if tank_sight.active else rig.camera

func _apply_turret_aim(command: BotCommand, view: BotView) -> void:
	var camera := aim_camera()
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var size := Vector3(0.0, _turret_scale() * BotScale.AUTHORING_HEIGHT, 0.0)
	var breech := view.pose * AtlasGeometry.turret_breech(size, view.turret_yaw)
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var target := origin + forward * TURRET_AIM_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(origin, target,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, source.camera_exclusions())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.position
	if view.turret_kind == "mortar":
		_apply_mortar_aim(command, view, size, target)
		return
	# A near or behind-the-turret contact (ground under a steep camera) would
	# swing the turret wildly; aim along the sight line instead.
	if (target - breech).dot(forward) < 2.0 * size.y:
		target = breech + forward * TURRET_AIM_DISTANCE
	_turret_aim_point = target
	var direction := target - breech
	command.aim_valid = true
	command.aim_yaw = atan2(-direction.x, -direction.z)
	command.aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())

## Artillery aiming: the screen-centre ground point becomes a bearing and the
## steep-arc elevation that lands a shell there. Out of reach aims at maximum
## range (the lowest lobbing elevation); too close clamps to the 80 degree stop.
func _apply_mortar_aim(command: BotCommand, view: BotView, size: Vector3, target: Vector3) -> void:
	var muzzle := view.pose * AtlasGeometry.turret_muzzle(size, "mortar", view.turret_yaw, view.gun_pitch)
	var offset := target - muzzle
	var elevation := AtlasGeometry.mortar_elevation(Vector2(offset.x, offset.z).length(), offset.y)
	if is_nan(elevation):
		elevation = TurretTuning.settings().value("mortar", "min_elevation")
	_turret_aim_point = target
	command.aim_valid = true
	command.aim_yaw = atan2(-offset.x, -offset.z)
	command.aim_pitch = clampf(elevation, -PI * 0.5, PI * 0.5)

func _update_tank_sight(view: BotView, delta: float) -> void:
	var wanted := view != null and view.turret_kind != "" and is_instance_valid(source)
	var artillery := wanted and view.turret_kind == "mortar"
	if wanted != tank_sight.active or artillery != tank_sight.artillery:
		tank_sight.reset()
		tank_sight.active = wanted
		tank_sight.artillery = artillery
		_kick_sequence = -1
	# Every accepted own shot kicks the sight; cannon volleys stack hard.
	if wanted and not view.eliminated:
		if _kick_sequence >= 0 and view.shot_sequence > _kick_sequence:
			var shells := mini(view.shot_sequence - _kick_sequence, 4)
			var per_shell: float = {"plasma":0.12, "flamer":0.0, "tesla":0.18, "railgun":1.3, "harpoon":0.3, "mortar":0.9}.get(view.turret_kind, 0.12)
			if view.turret_kind == "cannon":
				per_shell = 0.85 if view.turret_model == "cannon" else (0.6 if view.turret_model.ends_with("_dual") else 0.45)
			tank_sight.kick(per_shell * float(shells))
		_kick_sequence = view.shot_sequence
	if wanted:
		tank_sight.update_view(delta, source)

func _render_turret_reticle(view: BotView, delta := 0.0) -> void:
	var camera := aim_camera()
	var show := controls_enabled and view != null and view.turret_kind != "" and not view.eliminated \
		and is_instance_valid(camera) and camera.is_inside_tree() and not pause_menu.visible
	if not show or view.turret_kind != "mortar":
		mortar_aim.hide()
	if not show:
		turret_reticle.render(false, false, Vector2.ZERO, 0.0)
		_reticle_seen = false
		return
	# Where the barrel actually points: first world/bot contact along it.
	var size := Vector3(0.0, _turret_scale() * BotScale.AUTHORING_HEIGHT, 0.0)
	# Follow the smoothed, drawn barrel so ring and turret move together.
	var angles := view.turret_display
	var muzzle := view.pose * AtlasGeometry.turret_muzzle(size, view.turret_kind, angles.x, angles.y)
	var direction := (view.pose.basis * AtlasGeometry.turret_direction(angles.x, angles.y)).normalized()
	var end := muzzle + direction * TurretTuning.settings().value(view.turret_kind, "range")
	var query := PhysicsRayQueryParameters3D.create(muzzle, end,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, source.camera_exclusions())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
	if view.turret_kind == "mortar":
		# Where a shell fired now would land, along its real arc.
		var path := CombatWorld.mortar_trace(get_world_3d().direct_space_state, muzzle, direction, source.camera_exclusions())
		end = path.point
		mortar_aim.show_path(path.points, path.landed, TurretTuning.settings().value("mortar", "blast_radius"), view.secondary_charge >= 0.999)
	var on_screen := not camera.is_position_behind(end)
	var point := camera.unproject_position(end) if on_screen else Vector2.ZERO
	# The canvas may be scaled; convert viewport pixels into reticle space.
	point = turret_reticle.get_global_transform_with_canvas().affine_inverse() * point
	# Light filtering hides ray hits flicking between nearby surfaces.
	if not _reticle_seen or delta <= 0.0 or point.distance_to(_reticle_point) > turret_reticle.size.y * 0.25:
		_reticle_point = point
	else:
		_reticle_point = _reticle_point.lerp(point, 1.0 - exp(-delta * 25.0))
	_reticle_seen = on_screen
	turret_reticle.render(true, on_screen, _reticle_point, view.secondary_charge)

func _action_strength(action: StringName) -> float:
	var strength := Input.get_action_strength(action)
	# Rebinding releases action state, but a physical key may still be held.
	# Keep it blocked until real release rather than rearming on an artificial zero.
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and Input.is_physical_key_pressed(event.physical_keycode):
			strength = 1.0
		elif event is InputEventMouseButton and Input.is_mouse_button_pressed(event.button_index):
			strength = 1.0
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			var devices := Input.get_connected_joypads()
			if _controller_device >= 0 and not devices.has(_controller_device): devices.append(_controller_device)
			for device: int in devices:
				if event.device >= 0 and event.device != device: continue
				if event is InputEventJoypadButton:
					if Input.is_joy_button_pressed(device, event.button_index): strength = 1.0
				else:
					var physical := InputEventJoypadMotion.new()
					physical.device = device
					physical.axis = event.axis
					physical.axis_value = Input.get_joy_axis(device, event.axis)
					strength = maxf(strength, physical.get_action_strength(action))
	return strength

func _process(delta: float) -> void:
	var stick := Input.get_vector("camera_look_left", "camera_look_right", "camera_look_up", "camera_look_down")
	var movement := gamepad.look_delta(stick, delta, controls_enabled and not settings_panel.visible and not _leaving and get_window().has_focus())
	if not movement.is_zero_approx():
		rig.orbit(movement)
		if tank_sight.active: rig.pitch = tank_sight.clamp_pitch(rig.pitch)
	var view := _source_view()
	hud.show_view(view)
	_update_tank_sight(view, delta)
	_render_turret_reticle(view, delta)
	refresh_diagnostics()
	hint.text = "Mouse  Orbit  |  %s / %s  Zoom  |  %s  Recenter  |  Esc  Menu" % [
		input_preferences.label_for(&"camera_zoom_in"), input_preferences.label_for(&"camera_zoom_out"),
		input_preferences.label_for(&"camera_recenter")] \
		if controls_enabled else "Tab / arrows  Select   |   Enter  Confirm   |   Esc  Resume"
	if controls_enabled and view != null and view.turret_kind != "":
		var gun: String = {"cannon":"Main gun", "plasma":"Plasma gun", "flamer":"Flamethrower (hold)",
			"tesla":"Tesla arc", "railgun":"Railgun (hold, release)",
			"harpoon":"Harpoon (hold to reel, press to cut)", "mortar":"Mortar"}.get(view.turret_kind, "Turret")
		if view.turret_model.ends_with("_dual"): gun = "Twin " + gun.to_lower()
		elif view.turret_model.ends_with("_quad"): gun = "Quad " + gun.to_lower()
		hint.text = "Mouse  Aim  |  %s  %s  |  %s  Hull weapon  |  Esc  Menu" % [
			input_preferences.label_for(&"primary"), gun, input_preferences.label_for(&"secondary")]
	elif controls_enabled and view != null and view.has_auxiliary_weapon:
		hint.text = "%s  Primary weapon  |  %s  Minigun  |  Mouse  Orbit  |  Esc  Menu" % [
			input_preferences.label_for(&"primary"), input_preferences.label_for(&"secondary")]

	if _controller_device >= 0:
		hint.text = "Left stick  Drive  |  Right stick  Orbit  |  RB  Nitro  |  A  Jump  |  Start  Menu" \
			if controls_enabled else "D-pad  Select  |  A  Confirm  |  B  Back  |  Start  Resume"
		if controls_enabled and view != null and view.turret_kind != "":
			hint.text = "Right stick  Aim  |  RT  Turret  |  LT  Hull weapon  |  Start  Menu"
		elif controls_enabled and view != null and view.has_auxiliary_weapon:
			hint.text = "RT  Primary weapon  |  LT  Auxiliary gun  |  Right stick  Orbit  |  Start  Menu"

func _source_view() -> BotView:
	if not is_instance_valid(source):
		return null
	# The input lifecycle fixture has no MvpSession. Keep its control gate test
	# independent of a live view while preserving normal SessionBotSource reads.
	if source is SessionBotSource and not is_instance_valid(source.session):
		return BotView.new()
	return source.read_view()

func refresh_diagnostics() -> void:
	if not is_instance_valid(source) or not source is SessionBotSource \
		or not is_instance_valid(source.session):
		network_diagnostics.hide()
		_diagnostics_epoch = ""
		return
	var session: MvpSession = source.session
	var state: String = session.connection_state
	var phase: String = str(session.match_view.get("phase", "lobby"))
	var epoch := "%d/%s/%s/%s" % [session.get_instance_id(), state,
		str(session.match_view.get("match_id", "")), phase]
	var samples: Variant = session.diagnostics.get("snapshots_received")
	var count := float(samples) if (samples is int or samples is float) and is_finite(float(samples)) else 0.0
	if epoch != _diagnostics_epoch:
		_diagnostics_epoch = epoch
		_diagnostics_initial_samples = count
		_diagnostics_fresh = false
	elif count > _diagnostics_initial_samples:
		_diagnostics_fresh = true
	var data := session.diagnostics.duplicate(true)
	if state == "connected" and not _diagnostics_fresh:
		data.clear()
	network_diagnostics.show_diagnostics(state, data, {
		"build": WireCodec.BUILD,
		"mode": "Practice" if state == "practice" else str(session.lobby_view.get("mode", "--")),
		"phase": phase,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	})
	# A's centered session menu occupies 720px. Use its side gutter when paused.
	var inset := 24.0 if controls_enabled else clampf(
		(get_viewport().get_visible_rect().size.x - 720.0) * 0.5 - 280.0, 0.0, 24.0)
	network_diagnostics.offset_left = -280.0 - inset
	network_diagnostics.offset_right = -inset
	network_diagnostics.visible = not settings_panel.visible

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel.visible or _leaving:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if controls_enabled:
			release_controls()
		else:
			capture_controls()
		return
	# Resume is explicit; clicks outside buttons must not fire a weapon or close menus.
	if not controls_enabled:
		return
	if event is InputEventMouseMotion:
		# Captured mouse sensitivity uses screen pixels, independent of viewport stretch.
		rig.orbit(event.screen_relative)
		# The sight's look range is narrower than the orbit's; never bank
		# mouse travel beyond it.
		if tank_sight.active: rig.pitch = tank_sight.clamp_pitch(rig.pitch)
	elif event.is_action_pressed("camera_zoom_in"):
		rig.zoom(-1.0)
	elif event.is_action_pressed("camera_zoom_out"):
		rig.zoom(1.0)
	elif event.is_action_pressed("camera_recenter"):
		rig.recenter()
