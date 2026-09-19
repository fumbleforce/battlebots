class_name InputCombatProbe
extends BotSource
## Independent B fixture using A's real combat rules, not drive/network simulation.
var combat: CombatState
var last_command := BotCommand.new()
var launch_count: int = 0

func _ready() -> void:
	var registry := ContentRegistry.new()
	var validation := registry.validate(registry.starter(true))
	combat = CombatState.new(validation.stats)

func submit_command(command: BotCommand) -> void:
	last_command = command
	combat.tick(1.0 / 60.0, command, true)
	if combat.launch:
		launch_count += 1

func read_view() -> BotView:
	var view := BotView.new()
	view.entity_id = 990
	view.pose = global_transform
	if combat != null:
		view.core_fraction = combat.core / float(combat.stats.core)
		view.battery_fraction = combat.battery / float(combat.stats.battery)
		view.heat_fraction = combat.heat / 100.0
		view.weapon_charge_fraction = combat.charge
		view.weapon_state = StringName(combat.weapon_phase)
	return view

func camera_anchor() -> Node3D:
	return $CameraAnchor

func _process(_delta: float) -> void:
	if combat != null:
		$Feedback/Label.text = "INPUT / MENU FIXTURE\nReal lifter rules; no driving or networking\nHold LMB to charge, release to launch\nEsc / focus loss must CANCEL\nIntentional launches: %d" % launch_count
