extends Control

func _ready() -> void:
	theme = GameMenuTheme.create()
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server") or args.has("--server") or args.has("--host") or args.has("--practice") or args.any(func(arg: String) -> bool: return arg.begins_with("--join=")):
		_open.call_deferred("res://scenes/app/mvp.tscn")
		return
	$Center/Panel/Margin/Options/Practice.pressed.connect(func() -> void: _play("practice"))
	$Center/Panel/Margin/Options/Multiplayer.pressed.connect(func() -> void: _play("lobby"))
	$Center/Panel/Margin/Options/Quit.pressed.connect(get_tree().quit)
	$Center/Panel/Margin/Options/Practice.grab_focus()

func _play(mode: String) -> void:
	get_tree().set_meta("start_mode", mode)
	_open("res://scenes/app/mvp.tscn")

func _open(path: String) -> void:
	get_tree().change_scene_to_file(path)
