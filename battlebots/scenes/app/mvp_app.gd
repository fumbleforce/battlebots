extends Node3D
## A's integration console, not B's production menus/camera/garage.
var session: MvpSession
var status: Label
var address: LineEdit
var controller := false
var camera: Camera3D
var last_phase := ""

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
			print("SESSION ERROR: ", details.get("message", "Unknown error"))
		else:
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

func _button(row: HBoxContainer, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	row.add_child(button)

func _build_console() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.05, 0.07, 0.1)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.5
	environment.environment = settings
	add_child(environment)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 8, 12)
	camera.rotation_degrees.x = -35
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	canvas.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var title := Label.new()
	title.text = "A — MVP integration console (temporary presentation)"
	stack.add_child(title)
	var row := HBoxContainer.new()
	stack.add_child(row)
	address = LineEdit.new()
	address.text = "127.0.0.1"
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
	status = Label.new()
	stack.add_child(status)
	var controls := Label.new()
	controls.text = "WASD drive · Space brake · LMB weapon (lifter: hold/release) · RMB lower/brake · R recover"
	stack.add_child(controls)

func _physics_process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless" or session.local_source() == null:
		return
	var command := BotCommand.new()
	var focus := get_viewport().gui_get_focus_owner()
	var enabled := get_window().has_focus() and not focus is LineEdit
	command.brake = not enabled or Input.is_action_pressed("brake")
	if enabled:
		command.throttle = Input.get_axis("drive_reverse", "drive_forward")
		command.steering = Input.get_axis("steer_left", "steer_right")
		# GUI-consumed clicks do not drive weapon intent.
		var over_ui := get_viewport().gui_get_hovered_control() != null
		command.primary_held = Input.is_action_pressed("primary") and not over_ui
		command.primary_pressed = Input.is_action_just_pressed("primary") and not over_ui
		command.secondary_held = Input.is_action_pressed("secondary") or over_ui
		command.recovery_pressed = Input.is_action_just_pressed("recover")
	session.submit_local(command)

func _process(delta: float) -> void:
	if status == null:
		return
	var source := session.local_source()
	var summary := "%s | slots %d/4 | %s | round %d | %.0f s" % [session.connection_state,
		session.lobby_view.get("slots", []).size(), session.match_view.get("phase", "lobby"),
		session.match_view.get("round", 0), session.match_view.get("remaining", 0)]
	if source != null:
		var view := source.read_view()
		summary += "\nCore %.0f%% · Battery %.0f%% · Heat %.0f%% · Weapon %.0f%% (%s)" % [view.core_fraction * 100,
			view.battery_fraction * 100, view.heat_fraction * 100, view.weapon_charge_fraction * 100, view.weapon_state]
		if view.eliminated:
			summary += " — ELIMINATED"
		var target := view.pose.origin
		camera.global_position = camera.global_position.lerp(target + Vector3(0, 8, 12), 1 - exp(-delta * 6))
		camera.look_at(target)
	status.text = summary
