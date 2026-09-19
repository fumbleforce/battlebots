extends Node3D
## B-owned starting adapter. Replace fixed camera and label with player presentation.

@export var source_path: NodePath
@export var fixture_title: String = "Development fixture"
@onready var source: BotSource = get_node(source_path) as BotSource
@onready var status: Label = $CanvasLayer/Status
var sequence: int = 0

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(source):
		return
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	if get_window().has_focus():
		command.throttle = Input.get_axis("drive_reverse", "drive_forward")
		command.steering = Input.get_axis("steer_left", "steer_right")
		command.brake = Input.is_action_pressed("brake")
		command.primary_held = Input.is_action_pressed("primary")
		command.primary_pressed = Input.is_action_just_pressed("primary")
		command.secondary_held = Input.is_action_pressed("secondary")
		command.recovery_pressed = Input.is_action_just_pressed("recover")
	source.submit_command(command)

func _process(_delta: float) -> void:
	if not is_instance_valid(source):
		return
	var view := source.read_view()
	status.text = "%s\nCore %d%% | Battery %d%% | Heat %d%% | Weapon %d%%\nBaseline only: driving/combat not implemented. Escape: launcher" % [
		fixture_title, roundi(view.core_fraction * 100.0),
		roundi(view.battery_fraction * 100.0), roundi(view.heat_fraction * 100.0),
		roundi(view.weapon_charge_fraction * 100.0)]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file("res://scenes/app/main.tscn")
