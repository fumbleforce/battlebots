extends Control

func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server") or args.has("--server") or args.has("--host") or args.has("--practice") or args.any(func(arg: String) -> bool: return arg.begins_with("--join=")):
		_open.call_deferred("res://scenes/app/mvp.tscn")
		return
	$Center/Panel/Margin/Options/DeveloperA.pressed.connect(
		func() -> void: _open("res://scenes/dev/a_simulation.tscn"))
	$Center/Panel/Margin/Options/DeveloperB.pressed.connect(
		func() -> void: _open("res://scenes/dev/b_presentation.tscn"))
	$Center/Panel/Margin/Options/Quit.pressed.connect(get_tree().quit)
	$Center/Panel/Margin/Options/MVP.pressed.connect(
		func() -> void: _open("res://scenes/app/mvp.tscn"))

func _open(path: String) -> void:
	get_tree().change_scene_to_file(path)
