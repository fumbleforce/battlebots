class_name ScorpionStance
extends RefCounted
## Source-meter socket positions shared by the hex hull and its six supports.
const UPPER_LENGTH := 0.45
const LOWER_LENGTH := 0.73
const PROFILE := [Vector2(-0.40,-0.82), Vector2(0.40,-0.82), Vector2(0.80,0),
	Vector2(0.40,0.82), Vector2(-0.40,0.82), Vector2(-0.80,0)]

static func hip(row: int, side: int) -> Vector3:
	return Vector3(side * (0.79 if row == 1 else 0.46), -0.13, (row - 1) * 0.68)

static func foot(row: int, side: int) -> Vector3:
	return Vector3(side * (1.40 if row == 1 else 0.90), -0.95, (row - 1) * 1.10)

static func outward(row: int, side: int) -> Vector3:
	return Vector3(side, 0, row - 1).normalized()

static func knee(hip_position: Vector3, ankle: Vector3, radial: Vector3) -> Vector3:
	var direction := (ankle - hip_position).normalized()
	var reach := clampf(hip_position.distance_to(ankle), LOWER_LENGTH - UPPER_LENGTH + 0.001,
		UPPER_LENGTH + LOWER_LENGTH - 0.001)
	var along := (UPPER_LENGTH * UPPER_LENGTH - LOWER_LENGTH * LOWER_LENGTH + reach * reach) / (2.0 * reach)
	var bend := radial.slide(direction).normalized()
	return hip_position + direction * along + bend * sqrt(maxf(0, UPPER_LENGTH * UPPER_LENGTH - along * along))

static func collision_points(geometry_scale: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for ring: Vector2 in [Vector2(-0.25,0.92), Vector2(-0.16,1.0), Vector2(0.25,0.70)]:
		for point: Vector2 in PROFILE:
			points.append(Vector3(point.x * ring.y, ring.x, point.y * ring.y) * geometry_scale)
	return points
