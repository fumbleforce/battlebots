class_name MvpBot
extends BotSource

var entity_id := 0
var team := 0
var owner_id := 0
var server_tick := 0
var combat: CombatState
var loadout: Dictionary
var command := BotCommand.new()
var input_age := 1.0
var last_sequence := -1
var previous_pose := Transform3D.IDENTITY
var previous_velocity := Vector3.ZERO
var last_floor := Vector3.ZERO
var spawn_pose := Transform3D.IDENTITY
var body: DriveBody
var remote_state: Dictionary = {}
var simulated := true
var presentation: Node3D
var visual_error := Vector3.ZERO

static func create(id: int, side: int, build: Dictionary, registry: ContentRegistry) -> MvpBot:
	var validation := registry.validate(build)
	if not validation.valid:
		return null
	var bot = load("res://scenes/bots/baseline_bot.tscn").instantiate()
	bot.set_script(load("res://scripts/simulation/mvp_bot.gd"))
	bot.entity_id = id
	bot.team = side
	bot.loadout = validation.loadout
	bot.combat = CombatState.new(validation.stats)
	return bot as MvpBot

func _ready() -> void:
	body = $Body
	var stats := combat.stats
	body.mass = stats.mass
	body.top_speed = stats.speed
	body.grip_acceleration = stats.grip
	body.drive_acceleration = 6.0 * 103.0 / body.mass
	body.max_contacts_reported = 8
	body.contact_monitor = true
	body.probe_half_width = stats.size.x * 0.4
	body.probe_half_length = stats.size.z * 0.4
	var shape := BoxShape3D.new()
	shape.size = stats.size
	$Body/Collision.shape = shape
	var mesh := BoxMesh.new()
	mesh.size = stats.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.65, 0.85) if team == 0 else Color(0.95, 0.4, 0.1)
	mesh.material = material
	$Body/Visual.mesh = mesh
	$Body/ForwardStripe.position.z = -stats.size.z * 0.38
	presentation = Node3D.new()
	presentation.name = "Presentation"
	add_child(presentation)
	for path: String in ["Visual", "ForwardStripe", "CameraAnchor"]:
		body.get_node(path).reparent(presentation, false)
	presentation.global_transform = body.global_transform
	previous_pose = body.global_transform
	last_floor = body.global_position
	body.freeze = not simulated

func _process(delta: float) -> void:
	if simulated:
		presentation.global_transform = body.global_transform
	visual_error = visual_error.lerp(Vector3.ZERO, 1.0 - exp(-delta * 20.0))

func submit_command(intent: BotCommand) -> void:
	if intent == null or not intent.is_valid() or intent.sequence <= last_sequence:
		return
	last_sequence = intent.sequence
	command = BotCommand.new()
	for field: String in ["sequence", "throttle", "steering", "brake", "primary_held", "primary_pressed", "secondary_held", "recovery_pressed"]:
		command.set(field, intent.get(field))
	input_age = 0

func step(delta: float, active: bool) -> void:
	input_age += delta
	if input_age >= 0.25 or not active or combat.eliminated:
		command = BotCommand.new()
		command.brake = true
		command.secondary_held = true # Timeout/disconnect lowers lifter; never synthesize a release attack.
	combat.tick(delta, command, active)
	command.primary_pressed = false
	command.recovery_pressed = false
	body.drive_multiplier = combat.drive_scale()
	body.steering_multiplier = 0.0 if body.drive_multiplier == 0 else (0.6 if body.drive_multiplier < 1 else 1.0)
	body.accept_command(command)
	body.recovery_torque = Vector3.ZERO
	if active and not combat.eliminated:
		var forward := -body.global_basis.z
		# Credit only forward motion while applying drive intent, not passive pushing.
		var travel := (body.global_position - previous_pose.origin).dot(forward) * signf(command.throttle)
		var self_drive := minf(maxf(travel, 0), body.top_speed * delta) if absf(command.throttle) > 0.1 and body.grounded else 0.0
		combat.mobility(delta, body.grounded, body.global_basis.y.dot(Vector3.UP) < 0, self_drive)
		if combat.recovery_remaining > 0:
			var up := body.global_basis.y
			var axis := up.cross(Vector3.UP)
			if axis.length_squared() < 0.0001 and up.y < 0:
				axis = body.global_basis.z
			var angle := acos(clampf(up.dot(Vector3.UP), -1, 1))
			body.recovery_torque = (axis.normalized() * angle * body.mass * 24.0
				- body.angular_velocity * body.mass * 3.0).limit_length(body.mass * 24.0)
			body.sleeping = false
	if body.grounded and absf(body.global_position.x) < 23.5 and absf(body.global_position.z) < 23.5:
		last_floor = body.global_position
	if absf(body.global_position.x) > 27 or absf(body.global_position.z) > 27 or body.global_position.y < -2:
		body.reset_pose = Transform3D(Basis.IDENTITY, last_floor + Vector3.UP * 0.2)
		body.sleeping = false
	if combat.eliminated:
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze = true

func reset_round() -> void:
	combat = CombatState.new(combat.stats)
	command = BotCommand.new()
	input_age = 1
	body.collision_layer = BaselineConfig.BOT_LAYER
	body.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	body.freeze = false
	body.reset_pose = spawn_pose
	body.sleeping = false
	previous_pose = spawn_pose
	last_floor = spawn_pose.origin

func zone_at(world_point: Vector3) -> String:
	var point := body.global_transform.affine_inverse() * world_point
	var half: Vector3 = combat.stats.size * 0.5
	if point.y > half.y * 0.8:
		return "top"
	if point.y < -half.y * 0.8:
		return "underside"
	if absf(point.x) / half.x > absf(point.z) / half.z:
		if point.y < 0.05 and absf(point.z) < half.z * 0.8:
			return "drive_left" if point.x < 0 else "drive_right"
		return "left" if point.x < 0 else "right"
	if point.z < 0 and absf(point.x) < half.x * 0.45:
		return "weapon"
	return "front" if point.z < 0 else "rear"

func read_view() -> BotView:
	var data := remote_state if not simulated and not remote_state.is_empty() else combat.snapshot()
	var view := BotView.new()
	view.entity_id = entity_id
	view.owner_id = owner_id
	view.team = team
	view.server_tick = server_tick
	view.pose = presentation.global_transform
	view.core_fraction = data.core / data.core_max
	view.battery_fraction = data.battery / data.battery_max
	view.heat_fraction = data.heat / 100.0
	view.weapon_charge_fraction = data.charge
	view.weapon_state = data.weapon_state
	view.zones = data.zones.duplicate()
	view.weapon_cooldown = data.cooldown
	view.recovery_cooldown = data.recovery_cooldown
	view.immobilized_remaining = data.immobilized_remaining
	view.recovery_available = data.recovery_available
	view.eliminated = data.eliminated
	view.failure_reason = data.failure
	return view

func camera_anchor() -> Node3D:
	return $Presentation/CameraAnchor

func camera_exclusions() -> Array[RID]:
	return [body.get_rid()]
