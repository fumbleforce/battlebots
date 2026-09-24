class_name NimbleVisual
extends Node3D
## The four nimble bots (#61, #75), animated from accepted BotView only. The
## hull pose already carries the authoritative gait (stride bob and sway,
## monowheel lean, pogo bounds, skater crouch and carve); this node plants the
## running gear under it without sliding: Strider feet stay where they land
## and step to where the hull will be, the pogo leans over its planted tripod,
## skate wheels steer along their own travel and roll by it, and the monowheel
## tyre rolls by the hull's travel (GaitDrive keeps it on the floor). A charged
## jump crouches the legged bots. No damage, contact or movement authority.
const MODELS := {
	"strider_09": preload("res://assets/models/nimble_runtime/strider_09.glb"),
	"monowheel_07": preload("res://assets/models/nimble_runtime/monowheel_07.glb"),
	"pogo_03": preload("res://assets/models/nimble_runtime/pogo_03.glb"),
	"skater_12": preload("res://assets/models/nimble_runtime/skater_12.glb"),
}
## A pose jump larger than this (game metres) is a respawn or reset, not motion.
const SNAP_DISTANCE := 6.0
## Smoothing rate (1/s) of observed speed, velocity, yaw rate and acceleration.
const OBSERVE_RESPONSE := 10.0
## Ground probes start this far above the hull (game metres) and reach this far below it.
const PROBE_ABOVE := 1.5
const PROBE_BELOW := 7.5
## Charged-jump crouch (model metres the hull sinks at full charge) per gait,
## and how fast (1/s) the crouch follows the charge and springs back on release.
const JUMP_CROUCH := {"stride": 0.3, "roll": 0.0, "hop": 0.18, "skate": 0.14}
const CROUCH_RESPONSE := 12.0
const CROUCH_RELEASE := 30.0
# Strider: feet sit this far outboard of the hips (ratio) and lift this high
# mid-swing (model metres); the sole is ANKLE_HEIGHT below the ankle pivot.
const STRIDER_FOOT_OUTBOARD := 1.12
const STRIDER_ANKLE_HEIGHT := 0.075
const STRIDER_LIFT := 0.16
## Toes dip this much (radians) mid-swing, then the foot lands flat (more lets
## the long claws scrape the floor at a slow step).
const STRIDER_TOE_DIP := 0.12
## Share of the swing at each end spent lifting off and setting down before
## the foot travels, so it never scuffs along the floor.
const STRIDER_CLEAR_SHARE := 0.15
## Below this cadence (steps/s) the stride settles: a swinging foot finishes
## its step at the settle cadence and a planted foot only steps again when it
## is more than SETTLE_DISTANCE (game metres) from its stance spot.
const STRIDER_SETTLE_RATE := 2.2
const STRIDER_SETTLE_DISTANCE := 0.45
## When a standing leg stretches past this share of its reach, the stride
## hurries (up to HURRY_RATE extra steps/s at full stretch) so the swinging foot
## lands and the stretched one lifts before it would leave the floor.
const STRIDER_STRETCH := 0.85
const STRIDER_HURRY_RATE := 12.0
## A step never predicts further ahead than this (seconds).
const STRIDER_MAX_LOOKAHEAD := 0.6
## Airborne legs hang at this share of their full reach.
const STRIDER_HANG := 0.92
## Reverse knees bend backward and slightly outward.
const STRIDER_KNEE_BEND := Vector3(0.15, 0.0, 1.0)
# Hammer arm angles (radians about X, 0 = level forward): carried low beside the
# hull, a dip before the wind-up, cocked past vertical, struck at the
# authoritative -30 degree floor of the sweep.
const HAMMER_REST := -PI / 12.0
const HAMMER_DIP := -PI / 7.0
const HAMMER_COCKED := PI * 0.58
const HAMMER_STRUCK := -PI / 6.0
## Share of the wind-up spent dipping before the lift.
const HAMMER_DIP_SHARE := 0.18
## Seconds after the strike: the head slams down, rebounds, then recovers.
const HAMMER_SLAM_SECONDS := 0.06
const HAMMER_REBOUND_SECONDS := 0.24
const HAMMER_REBOUND := PI / 14.0
const HAMMER_COOLDOWN_SECONDS := 1.4
## Walking swings the carried arm this far (radians) with the stride.
const HAMMER_WALK_SWING := PI / 30.0
## The body leans back (radians) while cocking and forward into the strike.
const HAMMER_LEAN_BACK := PI / 40.0
const HAMMER_LEAN_FORWARD := PI / 22.0
# Pogo: the tripod hub rises this far on compression and drops this far when
# airborne (model metres); in the air it sags at SAG_RATE (1/s).
const POGO_COMPRESS := 0.24
const POGO_EXTEND := 0.2
const POGO_SAG_RATE := 8.0
## Height of the hub plate's spring seat above the hub origin (model metres).
const POGO_SEAT := 0.06
## The head leans over the planted tripod at most this far (radians) and eases
## back upright in the air at TILT_RECOVERY (1/s).
const POGO_MAX_TILT := PI / 9.0
const POGO_TILT_RECOVERY := 10.0
# Skater: a push stroke starts when the hull accelerates harder than this (m/s²);
# the kicking rear wheel travels this far back and out (model metres).
const SKATER_STROKE_ACCELERATION := 1.0
const SKATER_KICK_BACK := 0.32
const SKATER_KICK_OUT := 0.12
## Skate tyre half cross-section, [axial offset, radius] pairs in model metres:
## the convex envelope of the modelled tread (flat crown, rounded shoulders).
const SKATER_TYRE_PROFILE := [[0.0, 0.1308], [0.038, 0.1303], [0.041, 0.1198], [0.045, 0.098]]
## A kick eases in and out at this rate (1/s), so a stroke cut short by a
## change of throttle draws the wheel back instead of snapping it.
const SKATER_KICK_RESPONSE := 14.0
## Skate wheels steer along their travel once they move faster than
## STEER_SPEED (m/s); slower, they hold their heading.
const SKATER_STEER_SPEED := 0.4
## Skater knees rise up and out like a spider's.
const SKATER_KNEE_BEND := Vector3(0.5, 1.0, 0.0)

var exclusions: Array[RID] = []
## Garage previews have no arena: legs take their neutral stance.
var terrain := true
var chassis := ""
var gait := ""
var spec: Dictionary = {}
var model: Node3D
var nodes: Dictionary = {}
var gun_effects: MinigunEffects
var _rest: Dictionary = {}
var _legs: Array[Dictionary] = []
var _groups := {"weapon": [], "drive_left": [], "drive_right": []}
## Node scale: data is in game metres, the model in source metres (/ BotScale.FACTOR).
var _scale := 1.0
var _observed := false
var _previous_pose := Transform3D.IDENTITY
var _speed := 0.0
var _acceleration := 0.0
## Smoothed planar world velocity (m/s) and yaw rate (rad/s, + = left turn).
var _velocity := Vector3.ZERO
var _yaw_rate := 0.0
## This frame's unsmoothed planar velocity and yaw rate (rolling must match the
## motion exactly; stepping and steering use the smoothed values).
var _frame_velocity := Vector3.ZERO
var _frame_yaw_rate := 0.0
var _crouch := 0.0
## Extra body pitch (radians, + = nose up) from the hammer swing.
var _lean := 0.0
var _hub_y := 0.0
## Monowheel tyre spin (radians about its axle).
var _spin := 0.0
var _stroke := 0.0
## Strider stride phase: leg L stands on [0, 1) and swings on [1, 2).
var _phase := 0.0
## Pogo: whether the pads stand, their planted floor point and tripod heading
## (world), and the head's lean over them.
var _planted := false
var _anchor := Vector3.ZERO
var _anchor_basis := Basis.IDENTITY
var _tilt := Quaternion.IDENTITY

func assemble(draft: Dictionary, size: Vector3) -> void:
	spec = NimbleBots.spec(draft)
	chassis = draft.parts.chassis
	gait = spec.gait
	_scale = BotScale.from_size(size)
	scale = Vector3.ONE * _scale
	model = MODELS[chassis].instantiate()
	add_child(model)
	for node: Node in model.find_children("*", "Node3D", true, false):
		nodes[str(node.name)] = node
		_rest[str(node.name)] = (node as Node3D).transform
	if nodes.has("GunMount"):
		gun_effects = MinigunEffects.new()
		add_child(gun_effects)
		gun_effects.configure(nodes.GunBarrels, nodes.Muzzle, _scale, nodes.GunMount)
	for label: String in ["L", "R", "FL", "FR", "BL", "BR"]:
		if not nodes.has("Thigh" + label): continue
		var end: Node3D = nodes.get("Foot" + label, nodes.get("Wheel" + label))
		var hip: Vector3 = _rest["Thigh" + label].origin
		var knee: Vector3 = _rest["Shin" + label].origin
		_legs.append({"label": label, "thigh": nodes["Thigh" + label], "shin": nodes["Shin" + label], "end": end,
			"fork": nodes.get("Fork" + label), "hip": hip, "upper": hip.distance_to(knee),
			"lower": knee.distance_to(_rest[str(end.name)].origin), "side": signf(hip.x), "front": signf(-hip.z),
			"offset": 1.0 if label.ends_with("R") else 0.0, "planted": false, "foot": Vector3.ZERO,
			"yaw": 0.0, "from": Vector3.ZERO, "from_yaw": 0.0, "steer": 0.0, "roll": 0.0, "kick": 0.0,
			"contact": Vector3.ZERO, "tracked": false})
	_hub_y = _rest["Hub"].origin.y if _rest.has("Hub") else 0.0
	for key: String in ["GunFrame", "Arm"]:
		if nodes.has(key): _groups.weapon.append_array(_meshes(nodes[key]))
	for key: String in nodes:
		if key.begins_with("Thigh") or key.begins_with("Shin") or key.begins_with("Foot") or key.begins_with("Fork") \
				or (key.begins_with("Wheel") and key != "Wheel"):
			_groups["drive_left" if key.ends_with("L") else "drive_right"].append_array(_meshes(nodes[key]))
	if nodes.has("Wheel"): _groups.drive_left.append_array(_meshes(nodes.Wheel))
	if nodes.has("Hub"): _groups.drive_left.append_array(_meshes(nodes.Hub))
	if nodes.has("Coil"): _groups.drive_right.append_array(_meshes(nodes.Coil))
	if nodes.has("Arm"): _pose_arm(HAMMER_REST)
	_pose(0.0)

func _meshes(node: Node) -> Array:
	var found: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D: found.append(node)
	return found

func component_meshes() -> Dictionary:
	return _groups

func reset_observation() -> void:
	_observed = false
	if gun_effects != null: gun_effects.clear_effects()

func show_state(view: BotView, delta: float) -> void:
	if view == null: return
	if gun_effects != null: gun_effects.show_state(view, delta, true)
	_observe(view, delta)
	if nodes.has("Arm"): _pose_hammer(view)
	_pose_body(view, delta)
	_pose(delta)

## Motion of the drawn hull (the interpolated presentation pose, not the tick
## pose), so rolling and planted gear match what is on screen.
func _observe(view: BotView, delta: float) -> void:
	var pose := Transform3D(global_transform.basis.orthonormalized(), global_transform.origin) if is_inside_tree() else view.pose
	if not _observed or pose.origin.distance_to(_previous_pose.origin) > SNAP_DISTANCE:
		_previous_pose = pose
		_observed = true
		_speed = 0.0
		_acceleration = 0.0
		_velocity = Vector3.ZERO
		_yaw_rate = 0.0
		_frame_velocity = Vector3.ZERO
		_frame_yaw_rate = 0.0
		_planted = false
		for leg: Dictionary in _legs:
			leg.planted = false
			leg.tracked = false
		return
	var forward := (-pose.basis.z).slide(Vector3.UP).normalized()
	var previous_forward := (-_previous_pose.basis.z).slide(Vector3.UP).normalized()
	var displacement := (pose.origin - _previous_pose.origin).slide(Vector3.UP)
	var moved := displacement.dot(forward)
	var yawed := previous_forward.signed_angle_to(forward, Vector3.UP)
	_previous_pose = pose
	if view.eliminated or delta <= 0.0: return
	var response := 1.0 - exp(-OBSERVE_RESPONSE * delta)
	var speed := moved / delta
	_acceleration = lerpf(_acceleration, (speed - _speed) / delta, response)
	_speed = lerpf(_speed, speed, response)
	_frame_velocity = displacement / delta
	_frame_yaw_rate = yawed / delta
	_velocity = _velocity.lerp(_frame_velocity, response)
	_yaw_rate = lerpf(_yaw_rate, _frame_yaw_rate, response)

## Whole-model offsets: the charged-jump crouch and the hammer's body lean
## (the pogo adds its lean over the tripod in _pose_pogo).
func _pose_body(view: BotView, delta: float) -> void:
	var target := float(JUMP_CROUCH[gait]) * view.jump_charge_fraction
	var rate := CROUCH_RESPONSE if target >= _crouch else CROUCH_RELEASE
	_crouch = lerpf(_crouch, target, 1.0 - exp(-rate * delta)) if delta > 0.0 else target
	model.transform = Transform3D(Basis(_tilt) * Basis(Vector3.RIGHT, _lean), Vector3(0.0, -_crouch, 0.0))

## Model space (the authored hull frame, after crouch and lean) to world and back.
func _model_to_world(local: Vector3) -> Vector3:
	return model.global_transform * local

func _world_to_model(world: Vector3) -> Vector3:
	return model.global_transform.affine_inverse() * world

## A world rotation as a basis for a node directly under the model.
func _world_basis_to_model(basis: Basis) -> Basis:
	return model.global_transform.basis.orthonormalized().inverse() * basis

## Floor height (world) under a world point, or NAN with nothing within reach.
func _floor_world(world: Vector3) -> float:
	if not terrain or not is_inside_tree(): return NAN
	var query := PhysicsRayQueryParameters3D.create(world + Vector3.UP * PROBE_ABOVE, world + Vector3.DOWN * PROBE_BELOW,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclusions)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit.position.y) if not hit.is_empty() else NAN

## Floor under a model-space point along the hull's own down axis, in model
## space: a wheel set that far above it touches the floor with its lowest
## point even on a leaning hull. Without an arena (garage) the floor is ride
## height below the hull; with nothing below, gear dangles.
func _floor(local: Vector3) -> float:
	var ride := -float(spec.ride_height) / BotScale.FACTOR
	if not terrain or not is_inside_tree(): return ride
	var query := PhysicsRayQueryParameters3D.create(_model_to_world(Vector3(local.x, PROBE_ABOVE / _scale, local.z)),
		_model_to_world(Vector3(local.x, -PROBE_BELOW / _scale, local.z)), BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclusions)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return -float(spec.reach) / BotScale.FACTOR
	return _world_to_model(hit.position).y

func _pose(delta: float) -> void:
	match gait:
		"stride": _pose_strider(delta)
		"roll": _pose_wheel(delta)
		"hop": _pose_pogo(delta)
		"skate": _pose_skater(delta)

## A Strider foot's stance spot under the hull (model space, ankle at the hull origin height).
func _strider_rest(leg: Dictionary) -> Vector3:
	var hip: Vector3 = leg.hip
	return Vector3(hip.x * STRIDER_FOOT_OUTBOARD, 0.0, hip.z)

## World ankle spot under the hull predicted `ahead` seconds from now, and the
## hull heading then (radians about world up).
func _strider_target(leg: Dictionary, ahead: float) -> Dictionary:
	var hull := global_transform
	var turn := _yaw_rate * ahead
	var spot := hull.origin + _velocity * ahead + (hull.basis * _strider_rest(leg)).rotated(Vector3.UP, turn)
	var height := _floor_world(spot)
	if is_nan(height): height = spot.y - float(spec.ride_height)
	spot.y = height + STRIDER_ANKLE_HEIGHT * _scale
	return {"at": spot, "yaw": _yaw_of(hull.basis) + turn}

static func _yaw_of(basis: Basis) -> float:
	var forward := (-basis.z).slide(Vector3.UP)
	return atan2(-forward.x, -forward.z)

## Feet stand where they land. Each swings, on the GaitDrive cadence, from where
## it lifted to the spot under the hull at the middle of its next stance, so the
## hull passes over it; when the bot stops, the swinging foot finishes its step.
func _pose_strider(delta: float) -> void:
	if not terrain or not is_inside_tree() or (delta <= 0.0 and not _legs[0].planted):
		for leg: Dictionary in _legs:
			var rest := _strider_rest(leg)
			rest.y = _floor(rest) + STRIDER_ANKLE_HEIGHT
			_place_leg(leg, rest, Basis.IDENTITY)
		return
	if delta <= 0.0: return
	var stride: Dictionary = spec.stride
	var rate := absf(_speed) / float(stride.step_length) + absf(_yaw_rate) * float(stride.pivot_steps_per_radian)
	var stretch := 0.0
	for leg: Dictionary in _legs:
		if leg.planted and fposmod(_phase + float(leg.offset), 2.0) < 1.0:
			var reach := (float(leg.upper) + float(leg.lower)) * _scale
			stretch = maxf(stretch, _model_to_world(leg.hip).distance_to(leg.foot) / reach)
	if stretch > STRIDER_STRETCH:
		rate += STRIDER_HURRY_RATE * minf(1.0, (stretch - STRIDER_STRETCH) / (1.0 - STRIDER_STRETCH))
	var previous := _phase
	if rate >= STRIDER_SETTLE_RATE:
		_phase += rate * delta
	elif not is_equal_approx(_phase, roundf(_phase)):
		_phase = minf(_phase + STRIDER_SETTLE_RATE * delta, floorf(_phase) + 1.0)
	else:
		# Both feet stand; the next one only steps when it is out of place.
		var next: Dictionary = _legs[0] if fposmod(_phase, 2.0) >= 1.0 - 0.001 else _legs[1]
		var spot: Vector3 = _strider_target(next, 0.0).at
		if not next.planted or (next.foot as Vector3).distance_to(spot) > STRIDER_SETTLE_DISTANCE:
			_phase += STRIDER_SETTLE_RATE * delta
	_phase = fposmod(_phase, 2.0)
	var cadence := maxf(rate, STRIDER_SETTLE_RATE)
	for leg: Dictionary in _legs:
		var was := fposmod(previous + float(leg.offset), 2.0)
		var cycle := fposmod(_phase + float(leg.offset), 2.0)
		var hip_world := _model_to_world(leg.hip)
		var reach := (float(leg.upper) + float(leg.lower)) * _scale
		var hang := _strider_rest(leg)
		hang.y = (leg.hip as Vector3).y - (float(leg.upper) + float(leg.lower)) * STRIDER_HANG
		if hip_world.y - _settle(_model_to_world(hang)).y > reach:
			# The floor is out of reach: the legs hang until it comes back.
			leg.planted = false
			leg.foot = _model_to_world(hang)
			leg.yaw = _yaw_of(global_transform.basis)
			_place_leg(leg, hang, Basis.IDENTITY)
			continue
		if not leg.planted:
			# Landing or first frame: the foot sets down where it hangs.
			leg.planted = true
			if not leg.tracked: leg.yaw = _yaw_of(global_transform.basis)
			leg.foot = _settle(leg.foot if leg.tracked else _strider_target(leg, 0.0).at)
			leg.tracked = true
		if cycle >= 1.0 and (was < 1.0 or cycle < was):
			leg.from = leg.foot
			leg.from_yaw = leg.yaw
		elif cycle < 1.0 and was >= 1.0:
			# Touchdown (a fast frame may skip the end of the swing): the foot
			# sets straight down where it is.
			leg.foot = _settle(leg.foot)
		if cycle >= 1.0:
			var swing := cycle - 1.0
			var target := _strider_target(leg, minf((1.5 - swing) / cadence, STRIDER_MAX_LOOKAHEAD))
			# Lift, carry, set down: the foot leaves and meets the floor vertically.
			var eased := smoothstep(STRIDER_CLEAR_SHARE, 1.0 - STRIDER_CLEAR_SHARE, swing)
			var foot: Vector3 = (leg.from as Vector3).lerp(target.at, eased)
			foot.y += STRIDER_LIFT * _scale * sin(PI * swing)
			leg.foot = foot
			leg.yaw = lerp_angle(float(leg.from_yaw), float(target.yaw), eased)
			var dip := clampf((swing - STRIDER_CLEAR_SHARE) / (1.0 - 2.0 * STRIDER_CLEAR_SHARE), 0.0, 1.0)
			_place_world(leg, foot, float(leg.yaw), STRIDER_TOE_DIP * sin(PI * dip))
		else:
			_place_world(leg, leg.foot, float(leg.yaw), 0.0)

## A world ankle point set onto the floor under it.
func _settle(foot: Vector3) -> Vector3:
	var height := _floor_world(foot)
	return foot if is_nan(height) else Vector3(foot.x, height + STRIDER_ANKLE_HEIGHT * _scale, foot.z)

## Solve a leg to a world ankle point with a level foot facing yaw, toes dipped by pitch.
func _place_world(leg: Dictionary, ankle_world: Vector3, yaw: float, pitch: float) -> void:
	var basis := _world_basis_to_model(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch))
	_place_leg(leg, _world_to_model(ankle_world), basis)

func _place_leg(leg: Dictionary, ankle_target: Vector3, foot_basis: Basis) -> void:
	var hip: Vector3 = leg.hip
	var ankle := _reach(leg, ankle_target)
	var knee := solve_knee(hip, ankle, float(leg.upper), float(leg.lower), STRIDER_KNEE_BEND * Vector3(leg.side, 1, 1))
	leg.thigh.transform = _segment(hip, knee)
	leg.shin.transform = _segment(knee, ankle)
	leg.end.transform = Transform3D(foot_basis, ankle)

## Hammer arm about the shoulder (local X). The authority strikes the instant
## the 0.35 s wind-up ends, then cools down for 1.4 s: the arm dips, cocks past
## vertical over the wind-up with the body leaning back, slams to the -30
## degree strike as the cooldown starts with the body lunging forward,
## rebounds and swings back to its carry.
func _pose_hammer(view: BotView) -> void:
	var angle := HAMMER_REST + HAMMER_WALK_SWING * sin(PI * _phase)
	var lean := 0.0
	if view.eliminated or view.weapon_state == "disabled":
		angle = HAMMER_STRUCK
	elif view.weapon_state == "windup":
		var charge := view.weapon_charge_fraction
		if charge < HAMMER_DIP_SHARE:
			angle = lerpf(HAMMER_REST, HAMMER_DIP, sin(PI * 0.5 * charge / HAMMER_DIP_SHARE))
		else:
			var lift := (charge - HAMMER_DIP_SHARE) / (1.0 - HAMMER_DIP_SHARE)
			angle = lerpf(HAMMER_DIP, HAMMER_COCKED, 1.0 - pow(1.0 - lift, 3.0))
		lean = HAMMER_LEAN_BACK * charge
	elif view.weapon_state == "strike":
		angle = HAMMER_STRUCK
		lean = -HAMMER_LEAN_FORWARD
	elif view.weapon_cooldown > 0.0:
		var since := HAMMER_COOLDOWN_SECONDS - view.weapon_cooldown
		if since < HAMMER_SLAM_SECONDS:
			var slam := since / HAMMER_SLAM_SECONDS
			angle = lerpf(HAMMER_COCKED, HAMMER_STRUCK, slam * slam)
			lean = lerpf(HAMMER_LEAN_BACK, -HAMMER_LEAN_FORWARD, slam)
		elif since < HAMMER_SLAM_SECONDS + HAMMER_REBOUND_SECONDS:
			var rebound := (since - HAMMER_SLAM_SECONDS) / HAMMER_REBOUND_SECONDS
			angle = HAMMER_STRUCK + HAMMER_REBOUND * sin(PI * rebound) * (1.0 - rebound)
			lean = -HAMMER_LEAN_FORWARD * (1.0 - rebound * 0.5)
		else:
			var recover := clampf((since - HAMMER_SLAM_SECONDS - HAMMER_REBOUND_SECONDS)
				/ (HAMMER_COOLDOWN_SECONDS - HAMMER_SLAM_SECONDS - HAMMER_REBOUND_SECONDS), 0.0, 1.0)
			var eased := smoothstep(0.0, 1.0, recover)
			angle = lerpf(HAMMER_STRUCK, HAMMER_REST, eased)
			lean = -HAMMER_LEAN_FORWARD * 0.5 * (1.0 - eased)
	_lean = lean
	_pose_arm(angle)

func _pose_arm(angle: float) -> void:
	nodes.Arm.transform = Transform3D(Basis(Vector3.RIGHT, angle), _rest.Arm.origin)

## The tyre rolls without slip at its contact patch: leaning into a turn puts
## the patch on the rounded shoulder (a smaller rolling radius) and off the
## hull's centre line (where yaw adds speed), so it spins by the patch's own
## forward speed over its distance from the axle.
func _pose_wheel(delta: float) -> void:
	var hull := global_transform
	var axle := (hull.basis.x).normalized()
	var centre := _model_to_world(_rest.Wheel.origin)
	var patch := tyre_patch(spec.wheel.profile, centre, axle, 1.0)
	if delta > 0.0:
		var speed := (_frame_velocity + (Vector3.UP * _frame_yaw_rate).cross(patch - hull.origin)).dot(Vector3.UP.cross(axle).normalized())
		var arm := patch - centre
		_spin -= speed * delta / maxf((arm - axle * arm.dot(axle)).length(), 0.001)
	nodes.Wheel.transform = Transform3D(Basis(Vector3.RIGHT, _spin), _rest.Wheel.origin)

## The pogo stands on its tripod: when the pads reach the floor they plant (a
## fixed world point and heading), the hub squashes to the floor and the head
## leans over the planted pads as the hull moves, like a pogo stick pivoting on
## its foot. In the air the hub sags, the tripod turns back with the head and
## the head levels.
func _pose_pogo(delta: float) -> void:
	var rest: float = _rest.Hub.origin.y
	if not terrain or not is_inside_tree():
		_hub_y = rest
		_set_hub(Basis.IDENTITY)
		return
	# Pads sit this far below the hub origin (model metres, negative).
	var pads := -float(spec.ride_height) / BotScale.FACTOR - rest
	var hull := model.global_transform.origin
	var upright := Quaternion(global_transform.basis.orthonormalized())
	var floor_height := _floor_world(hull)
	var reach := -(rest - POGO_EXTEND + pads) * _scale
	var standing := not is_nan(floor_height) and hull.y - floor_height <= reach
	# Pushing off, the pads stay down until the spring reaches full extension.
	if _planted and not standing:
		var hub_seat := _anchor + Vector3.UP * -pads * _scale
		standing = (hub_seat - hull).length() <= reach + pads * _scale and Quaternion(upright * Vector3.DOWN, (hub_seat - hull).normalized()).get_angle() <= POGO_MAX_TILT
	if standing and not _planted:
		_anchor = Vector3(hull.x, floor_height, hull.z)
		_anchor_basis = Basis(Vector3.UP, _yaw_of(global_transform.basis))
	_planted = standing
	var response := 1.0 - exp(-POGO_TILT_RECOVERY * delta) if delta > 0.0 else 1.0
	# The tripod stays level, so its hub stands this far above the planted pads.
	var seat := _anchor + Vector3.UP * -pads * _scale
	if _planted:
		# Lean the head so its spring axis points at the hub over the planted pads.
		var world_tilt := Quaternion(upright * Vector3.DOWN, (seat - hull).normalized())
		var angle := world_tilt.get_angle()
		if angle > POGO_MAX_TILT: world_tilt = Quaternion.IDENTITY.slerp(world_tilt, POGO_MAX_TILT / angle)
		_tilt = upright.inverse() * world_tilt * upright
	else:
		_tilt = _tilt.slerp(Quaternion.IDENTITY, response)
	model.transform = Transform3D(Basis(_tilt) * Basis(Vector3.RIGHT, _lean), model.transform.origin)
	if _planted:
		_hub_y = clampf(-(seat - model.global_transform.origin).length() / _scale, rest - POGO_EXTEND, rest + POGO_COMPRESS)
		_set_hub(_world_basis_to_model(_anchor_basis))
	else:
		var sag := 1.0 - exp(-POGO_SAG_RATE * delta) if delta > 0.0 else 1.0
		_hub_y = lerpf(_hub_y, rest - POGO_EXTEND, sag)
		var hub_basis: Basis = (nodes.Hub as Node3D).transform.basis
		_set_hub(Basis(hub_basis.get_rotation_quaternion().slerp(Quaternion.IDENTITY, response)))

func _set_hub(basis: Basis) -> void:
	nodes.Hub.transform = Transform3D(basis, Vector3(0, _hub_y, 0))
	var top: Vector3 = _rest.Coil.origin
	nodes.Coil.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(1, top.y - (_hub_y + POGO_SEAT), 1)), top)

## Skate legs hold their wheels at the footholds (rear ones kick out on push
## strokes). Each wheel's fork swivels about its shin so the tyre points along
## the wheel's own travel, and the tyre rolls by that travel: pivots, carves and
## kicks roll instead of scrubbing.
func _pose_skater(delta: float) -> void:
	var skate: Dictionary = spec.skate
	var accelerating := _acceleration > SKATER_STROKE_ACCELERATION and _speed > 0.0
	if accelerating:
		_stroke = fposmod(_stroke + delta / float(skate.stroke_seconds), 2.0)
	var kicking := int(_stroke)
	var push := fmod(_stroke, 1.0) * float(skate.stroke_seconds) / float(skate.push_seconds)
	var kick := sin(PI * push) if push < 1.0 and accelerating else 0.0
	var crown := float(SKATER_TYRE_PROFILE[0][1])
	for index: int in _legs.size():
		var leg: Dictionary = _legs[index]
		var hold: Array = spec.footholds[index]
		var wheel := Vector3(float(hold[0]), 0.0, float(hold[1])) / BotScale.FACTOR
		var target := kick if float(leg.front) < 0.0 and int(leg.offset) == kicking else 0.0
		leg.kick = lerpf(float(leg.kick), target, 1.0 - exp(-SKATER_KICK_RESPONSE * delta)) if delta > 0.0 else target
		wheel += Vector3(float(leg.side) * SKATER_KICK_OUT, 0.0, SKATER_KICK_BACK) * float(leg.kick)
		wheel.y = _floor(wheel) + crown
		var ankle := _pose_skate_leg(leg, wheel)
		var patch := _model_to_world(ankle + Vector3.DOWN * crown)
		if terrain and is_inside_tree():
			# A leaning tyre stands on its shoulder: set that point on the floor.
			patch = tyre_patch(SKATER_TYRE_PROFILE, _model_to_world(ankle), _skate_axle(leg), _scale)
			var height := _floor_world(patch)
			if not is_nan(height) and not is_equal_approx(patch.y, height):
				ankle = _pose_skate_leg(leg, _world_to_model(_model_to_world(ankle) + Vector3.UP * (height - patch.y)))
				patch.y = height
		# The wheel's travel over the floor (hull motion, turning, leaning and
		# kicks), taken under its centre so swivelling does not feed back.
		var under := _model_to_world(ankle + Vector3.DOWN * crown)
		var travel := Vector3.ZERO
		if leg.tracked and delta > 0.0: travel = (under - (leg.contact as Vector3)).slide(Vector3.UP) / delta
		leg.contact = under
		leg.tracked = true
		if leg.fork != null and travel.length() > SKATER_STEER_SPEED and delta > 0.0:
			# Swivel about the shin until the axle lies across the travel; the
			# axle may lie either way, so swivel the least distance, like a
			# castor, and the fork never flips.
			var shin: Basis = (leg.shin as Node3D).transform.basis
			var heading := _world_basis_to_model(Basis.IDENTITY) * travel.normalized()
			var across := shin.x.dot(heading)
			var along := shin.z.dot(heading)
			var steer := atan(across / along) if not is_zero_approx(along) else PI * 0.5
			leg.steer = steer + PI * roundf((float(leg.steer) - steer) / PI)
		var wheel_basis := _skate_basis(leg)
		if leg.fork != null: leg.fork.transform = Transform3D(wheel_basis, ankle)
		# Roll by the travel along the wheel's heading over the patch's distance from the axle.
		var axle := _skate_axle(leg)
		var arm := patch - _model_to_world(ankle)
		var radius := maxf((arm - axle * arm.dot(axle)).length(), 0.001)
		leg.roll = float(leg.roll) - travel.dot(Vector3.UP.cross(axle).normalized()) * delta / radius
		leg.end.transform = Transform3D(wheel_basis * Basis(Vector3.RIGHT, float(leg.roll)), ankle)

## Solve a skate leg to a model-space wheel centre; returns the reached centre.
func _pose_skate_leg(leg: Dictionary, wheel: Vector3) -> Vector3:
	var hip: Vector3 = leg.hip
	var ankle := _reach(leg, wheel)
	var knee := solve_knee(hip, ankle, float(leg.upper), float(leg.lower), SKATER_KNEE_BEND * Vector3(leg.side, 1, 1))
	leg.thigh.transform = _segment(hip, knee)
	leg.shin.transform = _segment(knee, ankle)
	return ankle

## Fork and wheel frame: the shin's frame swivelled by the steer about the shin
## (without a fork the wheel keeps the hull's axle).
func _skate_basis(leg: Dictionary) -> Basis:
	if leg.fork == null: return Basis.IDENTITY
	return (leg.shin as Node3D).transform.basis * Basis(Vector3.UP, float(leg.steer))

func _skate_axle(leg: Dictionary) -> Vector3:
	return (model.global_transform.basis * _skate_basis(leg).x).normalized()

## Lowest point (world) of a tyre whose half cross-section `profile` ([axial
## offset, radius] pairs, times `units` for world metres) is revolved about
## `axle` through `centre`: where a leaning tyre touches a level floor.
static func tyre_patch(profile: Array, centre: Vector3, axle: Vector3, units: float) -> Vector3:
	var down := (Vector3.DOWN - axle * Vector3.DOWN.dot(axle)).normalized()
	var patch := centre
	for pair: Array in profile:
		var point := centre + (axle * -float(pair[0]) * signf(axle.y) + down * float(pair[1])) * units
		if point.y < patch.y: patch = point
	return patch

## The joint target, pulled within the leg's reach so a dangling leg hangs straight.
func _reach(leg: Dictionary, target: Vector3) -> Vector3:
	var hip: Vector3 = leg.hip
	return hip + (target - hip).limit_length(float(leg.upper) + float(leg.lower) - 0.001)

static func solve_knee(hip: Vector3, ankle: Vector3, upper: float, lower: float, bend: Vector3) -> Vector3:
	var direction := (ankle - hip).normalized()
	var distance := clampf(hip.distance_to(ankle), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var out := bend.slide(direction).normalized()
	if out.is_zero_approx(): out = Vector3.BACK.slide(direction).normalized()
	return hip + direction * along + out * sqrt(maxf(0.0, upper * upper - along * along))

## Limb frame at start whose local -Y points at end (the authored hang).
static func _segment(start: Vector3, end: Vector3) -> Transform3D:
	var y := -(end - start).normalized()
	var x := Vector3.RIGHT.slide(y).normalized()
	if x.is_zero_approx(): x = Vector3.FORWARD.cross(y).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), start)
