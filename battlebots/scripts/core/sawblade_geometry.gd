class_name SawbladeGeometry
extends RefCounted
## Authoritative authored dimensions, in Blender meters converted to Y up / -Z.
## Pure geometry: no scene loading, rendering or camera dependency.
const HAMMER_SWING := -1.2043226957

static func scale_for(size: Vector3) -> Vector3:
	return Vector3(size.x / 1.68, size.z / 2.60, size.z / 2.60)

static func point(source: Vector3, size: Vector3) -> Vector3:
	return source * scale_for(size) - Vector3.UP * size.y * 0.5

static func hammer_center(size: Vector3, angle: float) -> Vector3:
	return point(Vector3(0, 0.86, -0.29) + Basis(Vector3.RIGHT, angle) * Vector3(0, 0.63, -0.93), size)
