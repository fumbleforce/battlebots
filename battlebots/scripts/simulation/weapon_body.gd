extends RigidBody3D
## A bot's resting melee weapon as its own body (#112). It meets other bots'
## hulls only: never the floor, walls or props, and no hit query sees it, so
## drive support, client replay and damage zones keep reading the hull alone.
##
## It mirrors the hull: every tick it takes the hull's pose and velocity, with
## the hull's mass, centre of mass and inertia, so a contact changes its
## velocity exactly as it would change the hull's. That change is handed to the
## hull (DriveBody.weapon_reaction_*), which makes the contact an ordinary
## two-body collision. A frozen hull (eliminated, or a client's replica) has a
## frozen weapon that follows it as its child.
var hull: DriveBody
## Bot hulls this weapon touches this tick (body instance ids).
var contacts: Array = []
var _linear := Vector3.ZERO
var _angular := Vector3.ZERO
var _mirrored := false

func configure(owner_body: DriveBody) -> void:
	hull = owner_body
	set_meta(&"hull_id", hull.get_instance_id())
	collision_layer = BaselineConfig.WEAPON_LAYER
	collision_mask = BaselineConfig.BOT_LAYER
	add_collision_exception_with(hull)
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	follow_hull()
	gravity_scale = 0.0
	linear_damp_mode = DAMP_MODE_REPLACE
	angular_damp_mode = DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	freeze_mode = FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 8
	var slick := PhysicsMaterial.new()
	slick.friction = 0.0
	slick.bounce = 0.0
	physics_material_override = slick

## Keeps the hull's mass properties (the Woodland giant and Practice tuning
## change them after assembly) and its freeze; a body that starts mirroring
## again has no previous tick to compare with.
func follow_hull() -> void:
	if mass != hull.mass: mass = hull.mass
	if center_of_mass != hull.center_of_mass: center_of_mass = hull.center_of_mass
	if inertia != hull.inertia: inertia = hull.inertia
	if freeze != hull.freeze:
		freeze = hull.freeze
		_mirrored = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	contacts.clear()
	for index: int in state.get_contact_count():
		contacts.append(state.get_contact_collider_id(index))
	if _mirrored:
		hull.weapon_reaction_linear += state.linear_velocity - _linear
		hull.weapon_reaction_angular += state.angular_velocity - _angular
	var rid := hull.get_rid()
	# Include what the hull has not applied yet: a mirror still moving at the
	# hull's old velocity would strike the same target again next step.
	_linear = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) + hull.weapon_reaction_linear
	_angular = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) + hull.weapon_reaction_angular
	state.transform = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	state.linear_velocity = _linear
	state.angular_velocity = _angular
	_mirrored = true
