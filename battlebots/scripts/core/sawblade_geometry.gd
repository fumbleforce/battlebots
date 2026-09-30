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

static func scale_for(size: Vector3) -> Vector3:
	return Vector3(size.x / 1.68, size.z / 2.60, size.z / 2.60)

static func point(source: Vector3, size: Vector3) -> Vector3:
	return source * scale_for(size) - Vector3.UP * size.y * 0.5

## Saw module scale in the body frame at game scale.
static func saw_scale(loadout: Dictionary, size: Vector3) -> Vector3:
	if SawbladeConfig.body(loadout): return scale_for(size)
	return scale_for(BODY_SIZE) * BotScale.from_size(size)

## Blade axle in the body frame at game scale. Other bodies carry the blade
## ahead of their front face, as high above the ground as the Sawblade does.
static func saw_axle(loadout: Dictionary, size: Vector3) -> Vector3:
	if SawbladeConfig.body(loadout): return point(SAW_AXLE, size)
	var linear := BotScale.from_size(size)
	var scale := saw_scale(loadout, size)
	var ground := size.y * 0.5
	if loadout.get("parts", {}).get("drive") == "walker": ground = WalkerDrive.RIDE_HEIGHT * linear / BotScale.FACTOR
	elif AtlasGeometry.enabled(loadout): ground = AtlasGeometry.GROUND_DEPTH * linear
	return Vector3(0, SAW_AXLE.y * scale.y - ground, -size.z * 0.5 - SAW_FRONT_GAP * linear - SAW_RADIUS * scale.z)

static func hammer_center(size: Vector3, angle: float) -> Vector3:
	return point(Vector3(0, 0.86, -0.29) + Basis(Vector3.RIGHT, angle) * Vector3(0, 0.63, -0.93), size)
