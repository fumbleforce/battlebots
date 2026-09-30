class_name SawbladeGeometry
extends RefCounted
## Authoritative authored dimensions, in Blender meters converted to Y up / -Z.
## Pure geometry: no scene loading, rendering or camera dependency.
const HAMMER_SWING := -1.2043226957

## Saw module (Module_weapon_saw): blade axle, radius over the teeth and disc
## thickness, in source metres.
const SAW_AXLE := Vector3(0, 0.97, -1.16)
const SAW_RADIUS := 0.678
const SAW_THICKNESS := 0.08
## The Sawblade body's own size in authoring metres (catalogue `balanced` over
## BotScale.FACTOR). Its saw keeps this size on every other body (#109).
const BODY_SIZE := Vector3(1.6, 0.5, 2.0)
## Gap between the blade's teeth and another body's front face, authoring metres.
const SAW_FRONT_GAP := 0.05
## Other bodies carry only the blade on its axle fork (#109): the module parts
## kept (export source names), the fork's rear pivot in source metres (mirrored
## in x), and the bracket that ties each pivot back into the hull: its size in
## authoring metres and its centre's offset from the pivot.
const SAW_FORK_PARTS := ["Saw_SPIN_X", "Axle fork", "Axle fork.001",
	"Pivot bushing.002", "Pivot bushing.003", "Pivot bushing.007", "Pivot bushing.008",
	"Pivot hex bolt.002", "Pivot hex bolt.003", "Pivot hex bolt.007", "Pivot hex bolt.008"]
const SAW_FORK_ROOT := Vector3(0.23, 0.77, -0.48)
const SAW_BRACKET_SIZE := Vector3(0.12, 0.16, 0.45)
const SAW_BRACKET_OFFSET := Vector3(0, -0.03, 0.18)
## Ramp module (Module_weapon_ramp): its hinge, and the plate volume the
## authority sweeps (centre from the hinge, size), in source metres. The volume
## includes the low leading edge of the plate (y 0.0645, z -1.63), so an
## enlarged ramp cannot pass under a target while its query floats above it.
const RAMP_HINGE := Vector3(0, 0.36, -0.30)
const RAMP_PLATE_CENTER := Vector3(0, -0.06, -0.66)
const RAMP_PLATE_SIZE := Vector3(1.50, 0.50, 1.36)
## Plate angle (radians) at full charge and while it flips a target. Charging
## dips the plate, as the Lifter lowers its fork, before the release flips it
## up (#111): the load angle is the dip that puts the plate's leading edge
## (y 0.0645, z -1.63) on the floor, the plane of the hull's underside (y 0).
const RAMP_LOAD_ANGLE := -0.0488
const RAMP_LAUNCH_ANGLE := 1.3089969
## Gap between the hinge and another body's front face, authoring metres (#108).
const RAMP_FRONT_GAP := 0.10

static func scale_for(size: Vector3) -> Vector3:
	return Vector3(size.x / 1.68, size.z / 2.60, size.z / 2.60)

static func point(source: Vector3, size: Vector3) -> Vector3:
	return source * scale_for(size) - Vector3.UP * size.y * 0.5

## Saw module scale in the body frame at game scale.
static func saw_scale(loadout: Dictionary, size: Vector3) -> Vector3:
	if SawbladeConfig.body(loadout): return scale_for(size)
	return scale_for(BODY_SIZE) * BotScale.from_size(size)

## Hull centre height above the ground for a body other than the Sawblade, game metres.
static func _ground(loadout: Dictionary, size: Vector3) -> float:
	var linear := BotScale.from_size(size)
	if loadout.get("parts", {}).get("drive") == "walker": return WalkerDrive.RIDE_HEIGHT * linear / BotScale.FACTOR
	return AtlasGeometry.GROUND_DEPTH * linear if AtlasGeometry.enabled(loadout) else size.y * 0.5

## Blade axle in the body frame at game scale. Other bodies carry the blade
## ahead of their front face, as high above the ground as the Sawblade does.
static func saw_axle(loadout: Dictionary, size: Vector3) -> Vector3:
	if SawbladeConfig.body(loadout): return point(SAW_AXLE, size)
	var scale := saw_scale(loadout, size)
	return Vector3(0, SAW_AXLE.y * scale.y - _ground(loadout, size),
		-size.z * 0.5 - SAW_FRONT_GAP * BotScale.from_size(size) - SAW_RADIUS * scale.z)

## Ramp module scale in the body frame at game scale: like the saw, the Ramp
## keeps its Sawblade size on every other body (#108).
static func ramp_scale(loadout: Dictionary, size: Vector3) -> Vector3:
	return saw_scale(loadout, size)

## Ramp hinge in the body frame at game scale. Other bodies carry the hinge
## just ahead of their front face, as high above the ground as the Sawblade
## does at the lowest stance they take: a four-legged walker crouches
## (WalkerDrive.crouching), and the plate must not dig into the floor then, so
## it reaches the floor only while that walker crouches.
static func ramp_hinge(loadout: Dictionary, size: Vector3) -> Vector3:
	if SawbladeConfig.body(loadout): return point(RAMP_HINGE, size)
	var linear := BotScale.from_size(size)
	var ground := _ground(loadout, size)
	if loadout.get("parts", {}).get("drive") == "walker" and not ScorpionGeometry.enabled(loadout):
		ground = BotPhysics.settings().crouch_ride_height * linear / BotScale.FACTOR
	return Vector3(0, RAMP_HINGE.y * ramp_scale(loadout, size).y - ground, -size.z * 0.5 - RAMP_FRONT_GAP * linear)

## Plate angle for a charge of 0..1, or the flip angle while it launches.
static func ramp_angle(charge: float, launching: bool) -> float:
	return RAMP_LAUNCH_ANGLE if launching else charge * RAMP_LOAD_ANGLE

## Plate volume the authority sweeps at a plate angle: [transform, size], body
## frame at game scale.
static func ramp_volume(loadout: Dictionary, size: Vector3, angle: float) -> Array:
	var scale := ramp_scale(loadout, size)
	var rotation := Basis(Vector3.RIGHT, angle)
	return [Transform3D(rotation, ramp_hinge(loadout, size) + rotation * (RAMP_PLATE_CENTER * scale)), RAMP_PLATE_SIZE * scale]

## Plate angles sampled for the box around a flip.
const RAMP_SWING_SAMPLES := 8

## One box around everything the plate passes through as it flips from one
## angle to another: [transform, size], axis-aligned in the body frame at game
## scale. The authority checks this box when the Ramp launches (#111).
static func ramp_swing_volume(loadout: Dictionary, size: Vector3, from_angle: float, to_angle: float) -> Array:
	var low := Vector3.INF
	var high := -Vector3.INF
	for index: int in RAMP_SWING_SAMPLES + 1:
		var volume := ramp_volume(loadout, size, lerpf(from_angle, to_angle, float(index) / RAMP_SWING_SAMPLES))
		var plate: Transform3D = volume[0]
		var half: Vector3 = volume[1] * 0.5
		for corner: Vector3 in [Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, -1), Vector3(-1, 1, 1),
				Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, -1), Vector3(1, 1, 1)]:
			var point := plate * (half * corner)
			low = low.min(point)
			high = high.max(point)
	return [Transform3D(Basis.IDENTITY, (low + high) * 0.5), high - low]

static func hammer_center(size: Vector3, angle: float) -> Vector3:
	return point(Vector3(0, 0.86, -0.29) + Basis(Vector3.RIGHT, angle) * Vector3(0, 0.63, -0.93), size)
