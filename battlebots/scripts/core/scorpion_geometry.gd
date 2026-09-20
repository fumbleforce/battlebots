class_name ScorpionGeometry
extends RefCounted
## Pure source-meter geometry shared by Blender presentation and authority.
## Body transforms stay unit scale; each authored coordinate is enlarged once.
const SOURCE_SIZE := Vector3(1.6, 0.5, 2.0)
const TAIL_BASE := Vector3(0, 0.22, 0.68)
const TAIL_UPPER := Vector3(0, 0.98, 0.95)
const TAIL_FORE := Vector3(0, 1.73, 0.28)
const HEAD_PIVOT := Vector3(0, 1.51, -0.88)
const HEAD_CENTER := Vector3(0, 1.25, -1.12)
const HEAD_SIZE := Vector3(0.62, 0.76, 0.50)
const HAMMER_EXTENSION := 0.22
const FALLBACK_SOCKET := Vector3(0, -0.55, 0)
const GUN_MUZZLE := Vector3(0.66, 0.27, -1.72)
const GUN_BREECH := Vector3(0.66, 0.3155, -0.42)
const GUN_PIVOT := Vector3(0.66, 0.22, -0.42)
const GUN_DIRECTION := Vector3(0, -0.035, -1)
const GUN_REST_PITCH := -0.0349857188

static func enabled(loadout: Dictionary) -> bool:
	return loadout.get("parts", {}).get("chassis", "") == "scorpion_hex"

static func fallback_socket(size: Vector3) -> Vector3:
	return FALLBACK_SOCKET * BotScale.from_size(size)

static func hammer_angles(fraction: float) -> Vector4:
	return Vector4(-0.90, -0.15, 0.50, 0.55) * clampf(fraction, 0.0, 1.0)

static func hammer_extension(fraction: float) -> float:
	return HAMMER_EXTENSION * smoothstep(0.15, 0.85, clampf(fraction, 0.0, 1.0))

static func hammer_extension_offset(fraction: float) -> Vector3:
	return (HEAD_PIVOT - TAIL_FORE).normalized() * hammer_extension(fraction)

static func hammer_transform(size: Vector3, fraction: float) -> Transform3D:
	var angles := hammer_angles(fraction)
	var result := Transform3D(Basis(Vector3.RIGHT, angles.x), TAIL_BASE)
	result *= Transform3D(Basis(Vector3.RIGHT, angles.y), TAIL_UPPER - TAIL_BASE)
	result *= Transform3D(Basis(Vector3.RIGHT, angles.z), TAIL_FORE - TAIL_UPPER)
	result *= Transform3D(Basis(Vector3.RIGHT, angles.w), HEAD_PIVOT - TAIL_FORE + hammer_extension_offset(fraction))
	result *= Transform3D(Basis.IDENTITY, HEAD_CENTER - HEAD_PIVOT)
	result.origin *= BotScale.from_size(size)
	return result

static func gun_muzzle(size: Vector3, pitch := 0.0) -> Vector3:
	return (GUN_PIVOT + Basis(Vector3.RIGHT, pitch) * (GUN_MUZZLE - GUN_PIVOT)) * BotScale.from_size(size)

static func gun_breech(size: Vector3, pitch := 0.0) -> Vector3:
	return (GUN_PIVOT + Basis(Vector3.RIGHT, pitch) * (GUN_BREECH - GUN_PIVOT)) * BotScale.from_size(size)

static func gun_direction(pitch := 0.0) -> Vector3:
	return (Basis(Vector3.RIGHT, pitch) * GUN_DIRECTION).normalized()
