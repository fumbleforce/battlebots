class_name AtlasLegs
extends WalkerLegs
## Four authored hydraulic legs (atlas_drives.glb) on the shared planted-foot
## gait. Each leg is a slewing coxa, a femur pitched by a planetary hip drive
## and a tibia in one vertical plane; the knee ram is re-aimed every frame.
## The frames match pose() in tools/build-atlas-drives.py; dimensions come from
## AtlasDriveRig. No collision, damage or authoritative footholds live here.
const PARTS := ["Coxa", "Femur", "Tibia", "Foot", "KneeBarrel", "KneeRod"]
## Below this horizontal reach the heading keeps the leg's neutral yaw.
const MIN_HEADING_REACH := 0.02
## Kept from full extension so the knee never locks straight.
const REACH_MARGIN := 0.002
## A recovery cooldown that jumps by more than this (s) means a respawn/reset.
const RECOVERY_RESET_JUMP := 0.2
var rig: AtlasDriveRig
var _last_tick := -1
var _last_recovery := 0.0
var _was_eliminated := false

## parts: node name -> Node3D from the instanced atlas_drives.glb.
func attach(size: Vector3, parts: Dictionary) -> void:
	rig = AtlasDriveRig.settings()
	_geometry_scale = BotScale.from_size(size)
	scale *= _geometry_scale
	for side: int in [-1, 1]:
		for end: int in [-1, 1]:
			var tag := "%s_%s" % ["L" if side < 0 else "R", "Front" if end < 0 else "Rear"]
			var nodes := {}
			for part: String in PARTS:
				nodes[part] = parts["Leg%s_%s" % [part, tag]]
			# The same footholds WalkerDrive supports the hull on (AtlasDriveRig).
			var neutral := Vector3(side * rig.foothold.x, -WalkerDrive.RIDE_HEIGHT / BotScale.FACTOR, end * rig.foothold.y)
			var axis := Vector3(side * rig.yaw_axis.x, rig.pin_height, end * rig.yaw_axis.y)
			legs.append({"side":side, "end":end, "tag":tag, "nodes":nodes, "neutral":neutral, "hip":axis,
				"neutral_yaw":atan2(side * (neutral.x - axis.x), end * (neutral.z - axis.z)),
				"pair":0 if (side < 0) == (end < 0) else 1,
				"upper":nodes.Femur, "lower":nodes.Tibia, "foot_mesh":nodes.Foot, "hip_joint":nodes.Coxa,
				"foot":Vector3.ZERO, "start":Vector3.ZERO, "target":Vector3.ZERO, "normal":Vector3.UP,
				"time":1.0, "collider":null, "local_contact":Vector3.ZERO, "local_normal":Vector3.UP})
	reset_feet()

## Leg meshes grouped by hull side for component damage presentation.
func component_meshes() -> Dictionary:
	var result := {"weapon": [], "drive_left": [], "drive_right": []}
	for leg: Dictionary in legs:
		for part: String in PARTS:
			(result.drive_left if leg.side < 0 else result.drive_right).append(leg.nodes[part])
	return result

func observe_state(view: BotView) -> void:
	if _last_tick < 0 or view.server_tick < _last_tick or view.eliminated != _was_eliminated \
		or view.recovery_cooldown > _last_recovery + RECOVERY_RESET_JUMP:
		reset_feet()
	_last_tick = view.server_tick
	_last_recovery = view.recovery_cooldown
	_was_eliminated = view.eliminated

func _pose() -> void:
	if rig == null: return
	for leg: Dictionary in legs:
		var normal := (global_basis.inverse() * Vector3(leg.normal)).normalized()
		var ankle := to_local(leg.foot) + normal * rig.ankle
		var frames := solve(rig, leg.side, leg.end, ankle, normal, leg.neutral_yaw)
		for part: String in PARTS:
			var node: Node3D = leg.nodes[part]
			node.global_transform = global_transform * frames[part]

## Hull-frame transforms (source metres) of every moving part for an ankle
## target: coxa X = heading, Y = up; segments +Y along the member, Z = the
## hinge (up x heading), X = Y x Z; foot Y = ground normal, X = heading. The
## ankle rises at most rig.ankle_rise_limit above its stance height.
static func solve(rig: AtlasDriveRig, side: int, end: int, ankle: Vector3, normal: Vector3,
		neutral_yaw: float) -> Dictionary:
	var axis := Vector3(side * rig.yaw_axis.x, rig.pin_height, end * rig.yaw_axis.y)
	ankle.y = minf(ankle.y, -WalkerDrive.RIDE_HEIGHT / BotScale.FACTOR + rig.ankle + rig.ankle_rise_limit)
	var flat := Vector3(ankle.x - axis.x, 0.0, ankle.z - axis.z)
	var outward := neutral_yaw
	if flat.length() > MIN_HEADING_REACH:
		outward = atan2(side * flat.x, end * flat.z)
	outward = clampf(outward, rig.coxa_yaw_min, rig.coxa_yaw_max)
	var heading := Vector3(side * sin(outward), 0.0, end * cos(outward))
	var femur_pin := axis + heading * rig.coxa_reach
	var relative := ankle - femur_pin
	var along_heading := relative.dot(heading)
	var span := Vector2(along_heading, relative.y)
	var direction := span.normalized() if span.length() > 0.0 else Vector2.DOWN
	var reach := clampf(span.length(), absf(rig.femur - rig.tibia) + REACH_MARGIN, rig.femur + rig.tibia - REACH_MARGIN)
	var along := (rig.femur * rig.femur - rig.tibia * rig.tibia + reach * reach) / (2.0 * reach)
	var rise := sqrt(maxf(0.0, rig.femur * rig.femur - along * along))
	# The knee rises out of the plane's +90 degree side: up and outboard.
	var knee := femur_pin + heading * (along * direction.x - rise * direction.y) \
		+ Vector3.UP * (along * direction.y + rise * direction.x)
	var reached := femur_pin + heading * (direction.x * reach) + Vector3.UP * (direction.y * reach)
	var hinge := Vector3.UP.cross(heading).normalized()
	var frames := {"Coxa": Transform3D(Basis(heading, Vector3.UP, heading.cross(Vector3.UP)), axis)}
	frames.Femur = _member(femur_pin, knee, hinge)
	frames.Tibia = _member(knee, reached, hinge)
	var up := normal.normalized()
	var foot_x := (heading - up * heading.dot(up)).normalized()
	frames.Foot = Transform3D(Basis(foot_x, up, foot_x.cross(up)), reached)
	var knee_low: Vector3 = frames.Femur * Vector3(rig.knee_femur.x, rig.knee_femur.y, 0.0)
	var knee_high: Vector3 = frames.Tibia * Vector3(rig.knee_tibia.x, rig.knee_tibia.y, 0.0)
	frames.KneeBarrel = _member(knee_low, knee_high, hinge)
	frames.KneeRod = _member(knee_high, knee_low, hinge)
	return frames

static func _member(start: Vector3, stop: Vector3, hinge: Vector3) -> Transform3D:
	var y := (stop - start).normalized()
	return Transform3D(Basis(y.cross(hinge), y, hinge), start)
