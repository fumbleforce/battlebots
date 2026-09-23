class_name NimbleVisual
extends Node3D
## The four nimble bots (#61), animated from accepted BotView only. The hull
## pose already carries the authoritative gait (stride bob and sway, monowheel
## lean, pogo bounds, skater crouch and carve); this node plants the running
## gear under it. No damage, contact or movement authority.
const MODELS := {
	"strider_09": preload("res://assets/models/nimble_runtime/strider_09.glb"),
	"monowheel_07": preload("res://assets/models/nimble_runtime/monowheel_07.glb"),
	"pogo_03": preload("res://assets/models/nimble_runtime/pogo_03.glb"),
	"skater_12": preload("res://assets/models/nimble_runtime/skater_12.glb"),
}
## A pose jump larger than this (game metres) is a respawn or reset, not motion.
const SNAP_DISTANCE := 6.0
## Smoothing rate (1/s) of observed speed and acceleration.
const OBSERVE_RESPONSE := 10.0
## Ground probes start this far above the hull (game metres) and reach this far below it.
const PROBE_ABOVE := 1.5
const PROBE_BELOW := 7.5
# Strider: feet sit this far outboard of the hips (ratio) and lift this high
# mid-swing (model metres); below idle speed (m/s) the stride settles under the hips.
const STRIDER_FOOT_OUTBOARD := 1.12
const STRIDER_ANKLE_HEIGHT := 0.075
const STRIDER_LIFT := 0.16
const STRIDER_IDLE_SPEED := 1.5
## Reverse knees bend backward and slightly outward.
const STRIDER_KNEE_BEND := Vector3(0.15, 0.0, 1.0)
# Hammer arm angles (radians about X): rest, wind-up and strike like MvpWeaponVisual.
const HAMMER_REST := PI / 6.0
const HAMMER_RAISED := PI / 2.0
const HAMMER_STRUCK := -PI / 6.0
const HAMMER_RECOVERY_SECONDS := 1.4
# Pogo: the tripod hub rises this far on compression and drops this far when
# airborne (model metres); rates (1/s) favour a snappy squash and a slow sag.
const POGO_COMPRESS := 0.24
const POGO_EXTEND := 0.2
const POGO_SQUASH_RATE := 30.0
const POGO_SAG_RATE := 8.0
## Height of the hub plate's spring seat above the hub origin (model metres).
const POGO_SEAT := 0.06
# Skater: a push stroke starts when the hull accelerates harder than this (m/s²);
# the kicking rear wheel travels this far back and out (model metres).
const SKATER_STROKE_ACCELERATION := 1.0
const SKATER_KICK_BACK := 0.32
const SKATER_KICK_OUT := 0.12
const SKATER_WHEEL_RADIUS := 0.13
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
var _travel := 0.0
var _turn := 0.0
var _speed := 0.0
var _acceleration := 0.0
var _hub_y := 0.0
var _stroke := 0.0

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
			"hip": hip, "upper": hip.distance_to(knee), "lower": knee.distance_to(_rest[str(end.name)].origin),
			"side": signf(hip.x), "front": signf(-hip.z), "offset": 1.0 if label.ends_with("R") else 0.0})
	_hub_y = _rest["Hub"].origin.y if _rest.has("Hub") else 0.0
	for key: String in ["GunFrame", "Arm"]:
		if nodes.has(key): _groups.weapon.append_array(_meshes(nodes[key]))
	for key: String in nodes:
		if key.begins_with("Thigh") or key.begins_with("Shin") or key.begins_with("Foot") or (key.begins_with("Wheel") and key != "Wheel"):
			_groups["drive_left" if key.ends_with("L") else "drive_right"].append_array(_meshes(nodes[key]))
	if nodes.has("Wheel"): _groups.drive_left.append_array(_meshes(nodes.Wheel))
	if nodes.has("Hub"): _groups.drive_left.append_array(_meshes(nodes.Hub))
	if nodes.has("Coil"): _groups.drive_right.append_array(_meshes(nodes.Coil))
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
	_pose(delta)

func _observe(view: BotView, delta: float) -> void:
	if not _observed or view.pose.origin.distance_to(_previous_pose.origin) > SNAP_DISTANCE:
		_previous_pose = view.pose
		_observed = true
		_speed = 0.0
		_acceleration = 0.0
		return
	var forward := (-view.pose.basis.z).slide(Vector3.UP).normalized()
	var previous_forward := (-_previous_pose.basis.z).slide(Vector3.UP).normalized()
	var moved := (view.pose.origin - _previous_pose.origin).dot(forward)
	_previous_pose = view.pose
	if view.eliminated or delta <= 0.0: return
	_travel += moved
	_turn += absf(previous_forward.signed_angle_to(forward, Vector3.UP))
	var response := 1.0 - exp(-OBSERVE_RESPONSE * delta)
	var speed := moved / delta
	_acceleration = lerpf(_acceleration, (speed - _speed) / delta, response)
	_speed = lerpf(_speed, speed, response)

## Floor under a model-space point, in model space. Without an arena (garage)
## the floor is ride height below the hull; with nothing below, gear dangles.
func _floor(local: Vector3) -> float:
	var ride := -float(spec.ride_height) / BotScale.FACTOR
	if not terrain or not is_inside_tree(): return ride
	var world := to_global(Vector3(local.x, 0.0, local.z))
	var query := PhysicsRayQueryParameters3D.create(world + Vector3.UP * PROBE_ABOVE, world + Vector3.DOWN * PROBE_BELOW,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclusions)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return to_local(hit.position).y if not hit.is_empty() else -float(spec.reach) / BotScale.FACTOR

func _pose(delta: float) -> void:
	match gait:
		"stride": _pose_strider()
		"roll": _pose_wheel()
		"hop": _pose_pogo(delta)
		"skate": _pose_skater(delta)

func _pose_strider() -> void:
	var stride: Dictionary = spec.stride
	var length := float(stride.step_length) / BotScale.FACTOR
	# The same cadence as GaitDrive: walking and pivoting both advance the feet.
	var phase := _travel / float(stride.step_length) + _turn * float(stride.pivot_steps_per_radian)
	# Standing still, the feet settle under the hips instead of freezing mid-swing.
	var moving := clampf(absf(_speed) / STRIDER_IDLE_SPEED, 0.0, 1.0)
	for leg: Dictionary in _legs:
		var cycle := fposmod(phase + float(leg.offset), 2.0)
		var z := -length * 0.5 + cycle * length
		var lift := 0.0
		if cycle >= 1.0:
			z = length * 0.5 - (cycle - 1.0) * length
			lift = STRIDER_LIFT * sin(PI * (cycle - 1.0))
		var hip: Vector3 = leg.hip
		var foot := Vector3(hip.x * STRIDER_FOOT_OUTBOARD, 0.0, hip.z + z * moving)
		foot.y = _floor(foot) + STRIDER_ANKLE_HEIGHT + lift * moving
		var ankle := _reach(leg, foot)
		var knee := solve_knee(hip, ankle, float(leg.upper), float(leg.lower), STRIDER_KNEE_BEND * Vector3(leg.side, 1, 1))
		leg.thigh.transform = _segment(hip, knee)
		leg.shin.transform = _segment(knee, ankle)
		leg.end.transform = Transform3D(Basis.IDENTITY, ankle)

func _pose_hammer(view: BotView) -> void:
	var angle := HAMMER_REST
	if view.weapon_state == "windup":
		angle = lerpf(HAMMER_REST, HAMMER_RAISED, view.weapon_charge_fraction)
	elif view.weapon_state == "strike":
		angle = HAMMER_STRUCK
	elif view.weapon_cooldown > 0:
		angle = lerpf(HAMMER_STRUCK, HAMMER_REST, clampf(1.0 - view.weapon_cooldown / HAMMER_RECOVERY_SECONDS, 0, 1))
	if view.eliminated or view.weapon_state == "disabled": angle = 0.0
	nodes.Arm.transform = Transform3D(Basis(Vector3.RIGHT, angle), _rest.Arm.origin)

func _pose_wheel() -> void:
	# Rolling without slip: the tyre turns by travel over its radius.
	nodes.Wheel.transform = Transform3D(Basis(Vector3.RIGHT, -_travel / float(spec.wheel.radius)), _rest.Wheel.origin)

func _pose_pogo(delta: float) -> void:
	var rest: float = _rest.Hub.origin.y
	# Hub height at which the tripod feet touch the floor.
	var drop := rest + float(spec.ride_height) / BotScale.FACTOR
	var target := clampf(_floor(Vector3.ZERO) + drop, rest - POGO_EXTEND, rest + POGO_COMPRESS)
	var rate := POGO_SQUASH_RATE if target > _hub_y else POGO_SAG_RATE
	_hub_y = target if delta <= 0.0 else lerpf(_hub_y, target, 1.0 - exp(-rate * delta))
	nodes.Hub.transform = Transform3D(Basis.IDENTITY, Vector3(0, _hub_y, 0))
	var top: Vector3 = _rest.Coil.origin
	nodes.Coil.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(1, top.y - (_hub_y + POGO_SEAT), 1)), top)

func _pose_skater(delta: float) -> void:
	var skate: Dictionary = spec.skate
	var accelerating := _acceleration > SKATER_STROKE_ACCELERATION and _speed > 0.0
	if accelerating:
		_stroke = fposmod(_stroke + delta / float(skate.stroke_seconds), 2.0)
	var kicking := int(_stroke)
	var push := fmod(_stroke, 1.0) * float(skate.stroke_seconds) / float(skate.push_seconds)
	var kick := sin(PI * push) if push < 1.0 and accelerating else 0.0
	for index: int in _legs.size():
		var leg: Dictionary = _legs[index]
		var hold: Array = spec.footholds[index]
		var wheel := Vector3(float(hold[0]), 0.0, float(hold[1])) / BotScale.FACTOR
		# Rear wheels take turns pushing back and out, like skating strides.
		if float(leg.front) < 0.0 and int(leg.offset) == kicking:
			wheel += Vector3(float(leg.side) * SKATER_KICK_OUT, 0.0, SKATER_KICK_BACK) * kick
		wheel.y = _floor(wheel) + SKATER_WHEEL_RADIUS
		var hip: Vector3 = leg.hip
		var ankle := _reach(leg, wheel)
		var knee := solve_knee(hip, ankle, float(leg.upper), float(leg.lower), SKATER_KNEE_BEND * Vector3(leg.side, 1, 1))
		leg.thigh.transform = _segment(hip, knee)
		leg.shin.transform = _segment(knee, ankle)
		leg.end.transform = Transform3D(Basis(Vector3.RIGHT, -_travel / (SKATER_WHEEL_RADIUS * _scale)), ankle)

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
