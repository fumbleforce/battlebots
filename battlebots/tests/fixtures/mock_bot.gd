extends BotSource
## B-owned fixture. Never instantiate in authoritative gameplay.

var elapsed: float = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	rotation.y = sin(elapsed * 0.4) * 0.3

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
