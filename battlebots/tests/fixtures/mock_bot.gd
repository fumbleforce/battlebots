extends BotSource
## B-owned fixture. Never instantiate in authoritative gameplay.

var elapsed: float = 0.0
var last_command := BotCommand.new()
var mock_roll: bool = false

func submit_command(command: BotCommand) -> void:
	if command.is_valid():
		last_command = command

func _physics_process(delta: float) -> void:
	# Visual-only movement for camera tests, never a substitute for A's drive physics.
	rotation.y -= last_command.steering * 1.8 * delta
	if not last_command.brake:
		position += -transform.basis.z * last_command.throttle * 8.0 * delta
	position.x = clampf(position.x, -22.8, 22.8)
	position.z = clampf(position.z, -22.8, 22.8)
	rotation.z = PI if mock_roll else 0.0

func _process(delta: float) -> void:
	elapsed += delta

func read_view() -> BotView:
	var view := BotView.new()
	view.entity_id = 999
	view.pose = global_transform
	view.core_fraction = 0.75
	view.battery_fraction = 0.6
	view.heat_fraction = 0.25
	view.weapon_charge_fraction = (sin(elapsed) + 1.0) * 0.5
	view.weapon_state = &"mock"
	return view

func camera_anchor() -> Node3D:
	return $CameraAnchor
