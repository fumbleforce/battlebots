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

## Hull centre height above the ground, game metres (the Sawblade body rests
## on its underside).
static func ground(loadout: Dictionary, size: Vector3) -> float:
	var linear := BotScale.from_size(size)
	if loadout.get("parts", {}).get("drive") == "walker": return WalkerDrive.RIDE_HEIGHT * linear / BotScale.FACTOR
	return AtlasGeometry.GROUND_DEPTH * linear if AtlasGeometry.enabled(loadout) else size.y * 0.5

## Blade axle in the body frame at game scale. Other bodies carry the blade
## ahead of their front face, as high above the ground as the Sawblade does.
static func saw_axle(loadout: Dictionary, size: Vector3) -> Vector3:
	if SawbladeConfig.body(loadout): return point(SAW_AXLE, size)
	var scale := saw_scale(loadout, size)
	return Vector3(0, SAW_AXLE.y * scale.y - ground(loadout, size),
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
	var ground := ground(loadout, size)
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

## The Ramp's wedge in profile, (height from the hull's underside, z) in source
## metres: its lip, the top and the foot of its back edge; and its width.
const RAMP_PROFILE := [Vector2(0.0645, -1.63), Vector2(0.757, -0.36), Vector2(0.0, -0.36)]
const RAMP_WIDTH := 1.49

## Everything the Ramp's wedge passes through as it flips from one plate angle
## to another, rounded at the front by the arc of its lip: a prism across the
## wedge's width, as (left, right) pairs of points around its outline, body
## frame at game scale. The authority checks this volume when the Ramp
## launches (#111).
static func ramp_swing_points(loadout: Dictionary, size: Vector3, from_angle: float, to_angle: float) -> PackedVector3Array:
	var scale := ramp_scale(loadout, size)
	var hinge := ramp_hinge(loadout, size)
	var corners: Array = []
	for corner: Vector2 in RAMP_PROFILE:
		corners.append(hinge + Vector3(0, corner.x - RAMP_HINGE.y, corner.y - RAMP_HINGE.z) * scale)
	return AtlasGeometry.swing_prism(corners, hinge, RAMP_WIDTH * scale.x, from_angle, to_angle)

static func hammer_center(size: Vector3, angle: float) -> Vector3:
	return point(Vector3(0, 0.86, -0.29) + Basis(Vector3.RIGHT, angle) * Vector3(0, 0.63, -0.93), size)
