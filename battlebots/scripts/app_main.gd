extends Control

func _ready() -> void:
	$Center/Panel/Margin/Options/DeveloperA.pressed.connect(
		func() -> void: _open("res://scenes/dev/a_simulation.tscn"))
	$Center/Panel/Margin/Options/DeveloperB.pressed.connect(
		func() -> void: _open("res://scenes/dev/b_presentation.tscn"))
	$Center/Panel/Margin/Options/Quit.pressed.connect(get_tree().quit)

func _open(path: String) -> void:
	get_tree().change_scene_to_file(path)
