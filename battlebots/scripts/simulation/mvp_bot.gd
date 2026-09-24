class_name MvpBot
extends BotSource

## Steps around the axle of the monowheel's revolved tyre collider.
const TYRE_SEGMENTS := 24
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
var arena_half_extent := ArenaBounds.FOUNDRY_HALF
var remote_state: Dictionary = {}
var simulated := true
var presentation: Node3D
var visual_error := Vector3.ZERO
var weapon_visual: MvpWeaponVisual
var sawblade_visual: SawbladeVisual
var scorpion_visual: ScorpionVisual
var atlas_visual: AtlasVisual
var practice_npc_visual: PracticeNpcVisual
var nimble_visual: NimbleVisual
var damage_visual: BotDamageVisual
var destruction_visual: BotDestructionVisual
var nitro_visual: NitroFlameVisual
var hammer_slam: HammerSlamDetector

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
	body.reconciled.connect(_on_reconciled)
	var stats := combat.stats
	body.geometry_scale = BotScale.from_size(stats.size)
	body.mass = stats.mass
	body.top_speed = stats.speed
	body.walker = loadout.parts.drive == "walker"
	body.walker_rows = 3 if ScorpionGeometry.enabled(loadout) else 2
	body.grip_acceleration = stats.grip
	body.nitro_equipped = stats.nitro
	body.jump_equipped = stats.charged_jump
	body.drive_acceleration = 8.0 * 103.0 / body.mass
	body.brake_acceleration = 9.0
	body.coast_acceleration = 1.1
	body.turn_speed = 1.65
	body.throttle_response = 4.0
	body.steering_response = 4.0
	body.yaw_response = 0.2
	body.yaw_acceleration_limit = 4.5
	body.lateral_response = 0.24
	body.angular_damp = 0.45
	# Enlarge the hull reach, not the contact tolerance: a bigger robot must not
	# continue applying tire forces during a shallow airborne weapon launch.
	body.probe_depth = stats.size.y * 0.5 + 0.07
	# Floor contacts must not crowd out the wall contacts that mark a pin.
	body.max_contacts_reported = 16
	body.contact_monitor = true
	body.probe_half_width = stats.size.x * 0.4
	body.probe_half_length = stats.size.z * 0.4
	var shape := BoxShape3D.new()
	shape.size = stats.size
	$Body/Collision.shape = shape
	if AtlasGeometry.enabled(loadout):
		shape.size = AtlasGeometry.COLLISION_SIZE * body.geometry_scale
		$Body/Collision.position.y = AtlasGeometry.COLLISION_CENTER_Y * body.geometry_scale
		body.probe_depth = AtlasGeometry.GROUND_DEPTH * body.geometry_scale + 0.07
		if AtlasGeometry.drive_gear(loadout) == "legs":
			body.walker_footholds = AtlasDriveRig.settings().foothold * body.geometry_scale
	var nimble := NimbleBots.spec(loadout)
	if not nimble.is_empty():
		# Quick bots hover on their gait support; handling comes from their record.
		body.gait = nimble.gait
		body.gait_spec = nimble
		body.turn_speed = nimble.turn_speed
		body.lateral_response = nimble.lateral_response
		body.coast_acceleration = nimble.coast_acceleration
		body.low_gravity_heft = float(nimble.get("low_gravity_heft", 1.0))
		if nimble.has("wheel"):
			# The monowheel's tyre is solid: rams and weapons meet it below the hull.
			var wheel := CollisionShape3D.new()
			wheel.name = "WheelCollision"
			# Its rounded profile, revolved, so a leaning tyre meets the floor where it is drawn.
			var tyre := ConvexPolygonShape3D.new()
			tyre.points = NimbleBots.tyre_points(nimble.wheel, TYRE_SEGMENTS)
			wheel.shape = tyre
			wheel.position = Vector3(0, nimble.wheel.centre_y, 0)
			body.add_child(wheel)
		if nimble.has("leg_collision"):
			# Legs and spring are solid down to a floor clearance: walls stop them.
			var legs := CollisionShape3D.new()
			legs.name = "LegCollision"
			var column := BoxShape3D.new()
			column.size = NimbleBots.vector(nimble.leg_collision.size)
			legs.shape = column
			legs.position.y = nimble.leg_collision.centre_y
			body.add_child(legs)
	if ScorpionGeometry.enabled(loadout):
		var hull := ConvexPolygonShape3D.new()
		hull.points = ScorpionStance.collision_points(body.geometry_scale)
		$Body/Collision.shape = hull
	if SawbladeConfig.enabled(loadout) and not ScorpionGeometry.enabled(loadout) and not AtlasGeometry.enabled(loadout) and not has_meta("practice_variant"):
		var rear := CollisionShape3D.new()
		rear.name = "RearPackCollision"
		var rear_shape := BoxShape3D.new()
		var art_scale: float = stats.size.z / 2.60
		rear_shape.size = Vector3(1.10 * stats.size.x / 1.68, 1.04 * art_scale, 0.88 * art_scale)
		rear.shape = rear_shape
		rear.position = Vector3(0, 1.05 * art_scale - stats.size.y * 0.5, 0.83 * art_scale)
		body.add_child(rear)
	# Keep ballast low and resist pitch/roll independently of the yaw motor.
	# Explicit inertia prevents a tall cosmetic rear pack from making the hull
	# behave like a top-heavy hollow box. Budget mass and motor power stay intact.
	var bounds := collision_bounds()
	var hull := bounds.size
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = bounds.get_center() - Vector3.UP * hull.y * 0.2
	body.inertia = body.mass / 12.0 * Vector3(
		(hull.y * hull.y + hull.z * hull.z) * 1.8,
		hull.x * hull.x + hull.z * hull.z,
		(hull.x * hull.x + hull.y * hull.y) * 1.8)
	var contact_material := PhysicsMaterial.new()
	contact_material.friction = body.hull_friction()
	contact_material.bounce = 0.0
	body.physics_material_override = contact_material
	var mesh := BoxMesh.new()
	mesh.size = stats.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.65, 0.85) if team == 0 else Color(0.95, 0.4, 0.1)
	mesh.material = material
	$Body/Visual.mesh = mesh
	var stripe_mesh: BoxMesh = $Body/ForwardStripe.mesh.duplicate()
	stripe_mesh.size *= body.geometry_scale
	$Body/ForwardStripe.mesh = stripe_mesh
	$Body/ForwardStripe.position.y = stats.size.y * 0.5 + 0.015 * body.geometry_scale
	$Body/ForwardStripe.position.z = -stats.size.z * 0.38
	$Body/CameraAnchor.position.y = 0.6 * body.geometry_scale
	$Body/CameraAnchor.set_meta("bot_scale", body.geometry_scale)
	presentation = Node3D.new()
	presentation.name = "Presentation"
	add_child(presentation)
	for path: String in ["Visual", "ForwardStripe", "CameraAnchor"]:
		body.get_node(path).reparent(presentation, false)
	presentation.global_transform = body.global_transform
	if DisplayServer.get_name() != "headless" and not nimble.is_empty():
		presentation.get_node("Visual").hide()
		presentation.get_node("ForwardStripe").hide()
		nimble_visual = NimbleVisual.new()
		presentation.add_child(nimble_visual)
		nimble_visual.exclusions = [body.get_rid()]
		nimble_visual.assemble(loadout, stats.size)
	elif DisplayServer.get_name() != "headless" and has_meta("practice_variant"):
		presentation.get_node("Visual").hide()
		presentation.get_node("ForwardStripe").hide()
		practice_npc_visual = PracticeNpcVisual.new()
		presentation.add_child(practice_npc_visual)
		practice_npc_visual.assemble(str(get_meta("practice_variant")), stats.size)
	elif DisplayServer.get_name() != "headless" and AtlasGeometry.enabled(loadout):
		presentation.get_node("Visual").hide()
		presentation.get_node("ForwardStripe").hide()
		atlas_visual = AtlasVisual.new()
		presentation.add_child(atlas_visual)
		atlas_visual.assemble(loadout, stats.size)
		if atlas_visual.legs != null:
			atlas_visual.legs.exclusions = [body.get_rid()]
	elif DisplayServer.get_name() != "headless" and ScorpionVisual.enabled(loadout):
		presentation.get_node("Visual").hide()
		presentation.get_node("ForwardStripe").hide()
		scorpion_visual = ScorpionVisual.new()
		presentation.add_child(scorpion_visual)
		scorpion_visual.assemble(loadout, stats.size)
		scorpion_visual.walker_legs.exclusions = [body.get_rid()]
	elif DisplayServer.get_name() != "headless" and SawbladeConfig.enabled(loadout):
		presentation.get_node("Visual").hide()
		presentation.get_node("ForwardStripe").hide()
		sawblade_visual = SawbladeVisual.new()
		presentation.add_child(sawblade_visual)
		sawblade_visual.assemble(loadout, stats.size)
		if sawblade_visual.walker_legs != null:
			sawblade_visual.walker_legs.exclusions = [body.get_rid()]
	elif DisplayServer.get_name() != "headless":
		weapon_visual = MvpWeaponVisual.new()
		weapon_visual.name = "Weapon"
		presentation.add_child(weapon_visual)
		weapon_visual.assemble(stats.weapon, stats.size)
		if body.walker:
			var legs := WalkerLegs.new()
			presentation.add_child(legs)
			legs.exclusions = [body.get_rid()]
			legs.assemble(stats.size, material, SawbladeConfig.defaults())
	if DisplayServer.get_name() != "headless":
		var gun_offset := AtlasGeometry.gun_offset(loadout, stats.size)
		for node: Node in presentation.find_children("*", "Node3D", true, false):
			if node is MinigunEffects: (node as MinigunEffects).set_shot_geometry(stats.size, gun_offset)
		_create_damage_visual(stats.size)
		destruction_visual = BotDestructionVisual.new()
		add_child(destruction_visual)
		var damaged_meshes: Array = []
		for record: Dictionary in damage_visual.components.values():
			for surface: Dictionary in record.surfaces: damaged_meshes.append(surface.mesh)
		destruction_visual.configure(presentation, stats.size, damaged_meshes)
		if stats.get("nitro", false):
			nitro_visual = NitroFlameVisual.new()
			nitro_visual.name = "NitroFlame"
			presentation.add_child(nitro_visual)
			nitro_visual.configure(presentation, stats.size, body.geometry_scale)
		if stats.weapon == "hammer":
			hammer_slam = HammerSlamDetector.new()
			hammer_slam.name = "HammerSlam"
			add_child(hammer_slam)
			hammer_slam.configure(loadout, stats.size, body.get_rid(), entity_id)
	previous_pose = body.global_transform
	last_floor = body.global_position
	body.freeze = not simulated

func _on_reconciled(displacement: Vector3) -> void:
	visual_error += displacement
	if visual_error.length() >= 2:
		visual_error = Vector3.ZERO

func _process(delta: float) -> void:
	if simulated:
		presentation.global_transform = body.interpolated_transform()
	# Catch up sizeable contact offsets within the settling budget while keeping
	# small driving corrections gentle. Large divergences still snap on receipt.
	var decay := 30.0 if visual_error.length_squared() > 0.25 * 0.25 else 20.0
	visual_error = visual_error.lerp(Vector3.ZERO, 1.0 - exp(-delta * decay))
	var view: BotView
	if weapon_visual != null or sawblade_visual != null or scorpion_visual != null or atlas_visual != null or practice_npc_visual != null or nimble_visual != null or damage_visual != null:
		view = read_view()
	if weapon_visual != null:
		weapon_visual.show_state(view, delta)
	if sawblade_visual != null:
		sawblade_visual.show_state(view, delta)
	if scorpion_visual != null:
		scorpion_visual.show_state(view, delta)
	if atlas_visual != null:
		atlas_visual.show_state(view, delta)
	if practice_npc_visual != null:
		practice_npc_visual.show_state(view, delta)
	if nimble_visual != null:
		nimble_visual.show_state(view, delta)
	if damage_visual != null:
		damage_visual.show_state(view)
	if nitro_visual != null:
		nitro_visual.show_state(view, delta)
	if hammer_slam != null:
		hammer_slam.observe(view, delta)
	# A newly spawned remote bot has default healthy combat until its baseline is
	# accepted. Never use that fallback to invent a destruction edge on reconnect.
	if destruction_visual != null and (simulated or not remote_state.is_empty()):
		destruction_visual.observe(view)

func _create_damage_visual(size: Vector3) -> void:
	var groups: Dictionary
	if practice_npc_visual != null:
		groups = practice_npc_visual.component_meshes()
	elif nimble_visual != null:
		groups = nimble_visual.component_meshes()
	elif atlas_visual != null:
		groups = atlas_visual.component_meshes()
	elif scorpion_visual != null:
		groups = scorpion_visual.component_meshes()
	elif sawblade_visual != null:
		groups = sawblade_visual.component_meshes()
	else:
		groups = {"weapon": weapon_visual.find_children("*", "MeshInstance3D", true, false),
			"drive_left": [], "drive_right": []}
		var legs: WalkerLegs
		for child: Node in presentation.get_children():
			if child is WalkerLegs: legs = child
		if legs != null:
			var walking := legs.component_meshes()
			groups.drive_left = walking.drive_left
			groups.drive_right = walking.drive_right
		else:
			# Give the legacy box bot visible, independently readable drive housings.
			for side: int in [-1, 1]:
				var pod := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.16 * body.geometry_scale, 0.26 * body.geometry_scale, size.z * 0.75)
				pod.mesh = mesh
				pod.position = Vector3(side * size.x * 0.5, -0.08 * body.geometry_scale, 0)
				var material := StandardMaterial3D.new()
				material.albedo_color = Color(0.25, 0.28, 0.3)
				material.metallic = 0.6
				pod.material_override = material
				presentation.add_child(pod)
				groups["drive_left" if side < 0 else "drive_right"].append(pod)
	damage_visual = BotDamageVisual.new()
	damage_visual.set_geometry_scale(body.geometry_scale)
	presentation.add_child(damage_visual)
	for zone: String in groups:
		var anchor := Node3D.new()
		anchor.name = "DamageAnchor_" + zone
		presentation.add_child(anchor)
		anchor.position = Vector3(0, size.y * 0.5, -size.z * 0.5) if zone == "weapon" else Vector3(
			-size.x * 0.5 if zone == "drive_left" else size.x * 0.5, size.y * 0.5, 0)
		damage_visual.bind_component(zone, groups[zone], anchor)
	damage_visual.show_state(read_view())

func submit_command(intent: BotCommand) -> void:
	if intent == null or not intent.is_valid() or intent.sequence <= last_sequence:
		return
	last_sequence = intent.sequence
	command = BotCommand.new()
	for field: String in ["sequence", "throttle", "steering", "brake", "nitro_held", "jump_held", "jump_cancel", "crouch_held", "primary_held", "primary_pressed", "secondary_held", "auxiliary_held", "recovery_pressed", "aim_valid", "aim_yaw", "aim_pitch"]:
		command.set(field, intent.get(field))
	input_age = 0

func step(delta: float, active: bool) -> void:
	input_age += delta
	if input_age >= 0.25 or not active or combat.eliminated:
		command = BotCommand.new()
		command.brake = true
		command.jump_cancel = true
		command.secondary_held = true # Timeout/disconnect lowers lifter; never synthesize a release attack.
	combat.tick(delta, command, active)
	combat.tick_perks(delta, command, active, body.grounded)
	command.primary_pressed = false
	command.recovery_pressed = false
	var pods := combat.drive_scale()
	var stagger := combat.stagger_factor()
	body.drive_multiplier = pods * stagger
	body.steering_multiplier = (0.0 if pods == 0 else (0.6 if pods < 1 else 1.0)) * stagger
	body.grip_multiplier = lerpf(0.3, 1.0, stagger)
	body.accept_command(command)
	body.nitro_active = combat.nitro_active
	if combat.jump_release_speed > 0.0:
		body.queue_jump(combat.jump_release_speed * sqrt(body.gravity_scale))
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
				- body.angular_velocity * body.mass * 3.0).limit_length(body.mass * 24.0) * body.geometry_scale * body.geometry_scale
			body.sleeping = false
	var safe_radius: float = Vector2(combat.stats.size.x, combat.stats.size.z).length() * 0.5
	var at := body.global_position
	if body.grounded and ArenaBounds.contains(at, arena_half_extent, safe_radius):
		last_floor = body.global_position
	if not ArenaBounds.contains(at, arena_half_extent + 2.0) or at.y < -2:
		body.reset_pose = Transform3D(Basis.IDENTITY, last_floor + Vector3.UP * 0.2)
		body.sleeping = false
	if combat.eliminated:
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze = true

func reset_round() -> void:
	if destruction_visual != null: destruction_visual.reset_observation()
	if scorpion_visual != null: scorpion_visual.reset_observation()
	if nimble_visual != null: nimble_visual.reset_observation()
	if atlas_visual != null: atlas_visual.reset_observation()
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

## B assembly publishes actual collision bounds to A's spawn-clearance consumer.
## Canonical size retains the shared weapon/scale frame for older authored bots.
func collision_bounds() -> AABB:
	if AtlasGeometry.enabled(loadout):
		var size := AtlasGeometry.COLLISION_SIZE * body.geometry_scale
		return AABB(-size * 0.5 + Vector3.UP * AtlasGeometry.COLLISION_CENTER_Y * body.geometry_scale, size)
	return AABB(-combat.stats.size * 0.5, combat.stats.size)

func ground_clearance() -> float:
	if body.walker:
		return WalkerDrive.RIDE_HEIGHT * body.geometry_scale / BotScale.FACTOR
	if body.gait != "":
		return float(body.gait_spec.ride_height)
	return -collision_bounds().position.y

func zone_at(world_point: Vector3) -> String:
	var point := body.global_transform.affine_inverse() * world_point
	var bounds := collision_bounds()
	point -= bounds.get_center()
	var half := bounds.size * 0.5
	if point.y > half.y * 0.8:
		return "top"
	if point.y < -half.y * 0.8:
		return "underside"
	if absf(point.x) / half.x > absf(point.z) / half.z:
		if point.y < 0.05 * body.geometry_scale and absf(point.z) < half.z * 0.8:
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
	view.overheated = data.overheated
	view.heat_fraction = data.heat / 100.0
	view.weapon_charge_fraction = data.charge
	view.weapon_state = data.weapon_state
	view.zones = data.zones.duplicate()
	# Areas without an armour piece have nothing to breach; views report fitted armour only.
	var fitted: Variant = data.get("plate_max")
	if fitted is Dictionary:
		for face: String in fitted:
			if float(fitted[face]) <= 0.0: view.zones.erase(face)
			else: view.plate_max[face] = float(fitted[face])
	view.weapon_cooldown = data.cooldown
	view.recovery_cooldown = data.recovery_cooldown
	view.immobilized_remaining = data.immobilized_remaining
	view.recovery_available = data.recovery_available
	view.eliminated = data.eliminated
	view.failure_reason = data.failure
	view.has_auxiliary_weapon = combat.stats.get("secondary_weapon", "") != ""
	view.turret_kind = combat.stats.secondary_weapon if combat.is_turret() else ""
	view.turret_yaw = data.get("turret_yaw", 0.0)
	view.turret_model = combat.stats.get("turret_model", "")
	view.turret_display = atlas_visual.turret_display if atlas_visual != null and atlas_visual.turret != null \
		else Vector2(view.turret_yaw, data.get("gun_pitch", 0.0))
	view.secondary_charge = data.get("secondary_charge", 0.0)
	view.secondary_active = data.get("secondary_active", false)
	view.shot_sequence = data.get("shot_sequence", 0)
	view.last_shot_from = data.get("last_shot_from", Vector3.ZERO)
	view.last_shot_to = data.get("last_shot_to", Vector3.ZERO)
	view.last_shot_tick = data.get("last_shot_tick", -1)
	view.gun_pitch = data.get("gun_pitch", 0.0)
	view.nitro_active = data.get("nitro_active", false)
	view.jump_charge_fraction = data.get("jump_charge", 0.0)
	view.jump_cooldown = data.get("jump_cooldown", 0.0)
	view.grip_target = data.get("grip_target", 0)
	view.grip_point = data.get("grip_point", Vector3.ZERO)
	view.tool_pose = data.get("tool_pose", 0.0)
	view.spree = data.get("spree", 0)
	view.cooling = data.get("cooling", false)
	return view

func camera_anchor() -> Node3D:
	return $Presentation/CameraAnchor

func camera_exclusions() -> Array[RID]:
	return [body.get_rid()]
