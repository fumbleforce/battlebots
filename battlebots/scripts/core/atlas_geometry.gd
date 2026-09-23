class_name AtlasGeometry
extends RefCounted
## Atlas source meters. Canonical size.y remains the shared scale reference;
## its taller actual collision and support depth are explicit, never art-derived.
const COLLISION_SIZE := Vector3(2.44, 1.11, 2.60)
const COLLISION_CENTER_Y := 0.0
const GROUND_DEPTH := 0.555
const GUN_OFFSET := Vector3(-0.18, 0.27, 0.42)
const TRACK_RADIUS := 0.44
const TRACK_HALF_LENGTH := 0.76
const TRACK_CENTER_Y := -0.08
const TRACK_LENGTH := 4.0 * TRACK_HALF_LENGTH + TAU * TRACK_RADIUS
## Roof turret (atlas_turret.glb): pivots in Atlas source meters. Positive yaw
## turns the barrel toward -X (Godot Y rotation); positive pitch elevates.
## Utility part -> attachment model. The family (before "_") selects weapon
## rules; dual/quad models fire from several barrels (TURRET_BARRELS).
const TURRET_PARTS := {"turret_cannon":"cannon", "turret_plasma":"plasma",
	"turret_cannon_dual":"cannon_dual", "turret_cannon_quad":"cannon_quad",
	"turret_plasma_dual":"plasma_dual", "turret_plasma_quad":"plasma_quad"}
const TURRET_YAW_PIVOT := Vector3(0.0, 0.52, -0.14)
const TURRET_PITCH_PIVOT := Vector3(0.0, 0.77345, -0.546)
## +30 degrees is the mechanical elevation stop. Depression is limited per
## bearing by the measured hull clearance (tools/build-atlas-turret.py audit,
## atlas_turret_manifest.json): degrees at yaw 0, 5, ... 355. The deck and
## corner sockets restrict the flanks; the nose and rear allow -20/-18.
const TURRET_PITCH_MAX := 0.5235988
const TURRET_DEPRESSION_STEP := 5.0
const TURRET_DEPRESSION := {
	"cannon":[-20, -20, -20, -20, -20, -20, -20, -20, -14, -11, -10, -7, -7, -8, -9, -10, -10, -11, -11, -11, -10, -10, -10, -9, -9, -8, -6, -6, -9, -10, -13, -14, -15, -17, -18, -18, -18, -18, -18, -17, -15, -14, -13, -10, -9, -6, -6, -8, -9, -9, -10, -10, -10, -11, -11, -11, -10, -10, -9, -8, -7, -7, -10, -11, -14, -20, -20, -20, -20, -20, -20, -20],
	"plasma":[-20, -20, -20, -20, -20, -20, -20, -20, -13, -10, -9, -6, -6, -7, -8, -9, -9, -10, -10, -10, -9, -9, -9, -8, -8, -8, -5, -5, -7, -8, -11, -12, -13, -14, -14, -15, -15, -15, -14, -14, -13, -12, -11, -8, -7, -5, -5, -8, -8, -8, -9, -9, -9, -10, -10, -10, -9, -9, -8, -7, -6, -6, -9, -10, -13, -20, -20, -20, -20, -20, -20, -20],
	"cannon_dual":[-20, -20, -20, -20, -20, -20, -20, -16, -13, -11, -9, -9, -9, -9, -9, -11, -11, -12, -12, -12, -11, -11, -10, -11, -9, -8, -8, -8, -8, -11, -11, -14, -16, -16, -18, -20, -20, -20, -18, -16, -16, -14, -11, -11, -8, -8, -8, -8, -9, -11, -10, -11, -11, -12, -12, -12, -11, -11, -9, -9, -9, -9, -9, -11, -13, -16, -20, -20, -20, -20, -20, -20],
	"cannon_quad":[-20, -20, -20, -20, -20, -20, -16, -11, -8, -6, -4, -3, -4, -3, -5, -6, -6, -7, -7, -7, -6, -6, -5, -6, -5, -3, -3, -3, -3, -6, -7, -9, -10, -11, -12, -12, -13, -12, -12, -11, -10, -9, -7, -6, -3, -3, -3, -3, -5, -6, -5, -6, -6, -7, -7, -7, -6, -6, -5, -3, -4, -3, -4, -6, -8, -11, -16, -20, -20, -20, -20, -20],
	"plasma_dual":[-20, -20, -20, -20, -20, -20, -20, -14, -12, -10, -8, -8, -9, -8, -8, -10, -11, -11, -12, -11, -11, -10, -10, -9, -9, -6, -7, -6, -6, -9, -9, -13, -14, -15, -16, -17, -17, -17, -16, -15, -14, -13, -9, -9, -6, -6, -7, -6, -9, -9, -10, -10, -11, -11, -12, -11, -11, -10, -8, -8, -9, -8, -8, -10, -12, -14, -20, -20, -20, -20, -20, -20],
	"plasma_quad":[-20, -20, -20, -20, -20, -20, -18, -10, -7, -6, -3, -3, -3, -3, -4, -5, -6, -6, -7, -6, -6, -6, -5, -5, -5, -2, -2, -2, -2, -4, -6, -8, -9, -9, -10, -10, -11, -10, -10, -9, -9, -8, -6, -4, -2, -2, -2, -2, -5, -5, -5, -6, -6, -6, -7, -6, -6, -5, -4, -3, -3, -3, -3, -6, -7, -10, -18, -20, -20, -20, -20, -20]}
## GENERATED:TURRET_TABLES — tools/update-turret-geometry.py from atlas_turret_manifest.json
const TURRET_BARRELS := {
	"cannon":[[0, 0]],
	"plasma":[[0, 0]],
	"cannon_dual":[[-0.1131, 0], [0.1131, 0]],
	"cannon_quad":[[-0.0928, 0.087], [0.0928, 0.087], [-0.0928, -0.087], [0.0928, -0.087]],
	"plasma_dual":[[-0.1305, 0], [0.1305, 0]],
	"plasma_quad":[[-0.1015, 0.0899], [0.1015, 0.0899], [-0.1015, -0.0899], [0.1015, -0.0899]]}
const TURRET_YAW_RATE := 1.9
const TURRET_PITCH_RATE := 1.2
const TURRET_MUZZLE := {"cannon":1.37025, "plasma":0.957}

static func enabled(draft: Dictionary) -> bool:
	return draft.get("parts", {}).get("chassis") == "atlas_mx"

static func gun_offset(draft: Dictionary, size: Vector3) -> Vector3:
	return GUN_OFFSET * BotScale.from_size(size) if enabled(draft) else Vector3.ZERO

static func paint_defaults() -> Dictionary:
	var config := SawbladeConfig.defaults()
	var colors := {"paint_primary":Color(0.86, 0.51, 0.055),
		"paint_secondary":Color(0.205, 0.225, 0.235), "paint_metal":Color(0.52, 0.55, 0.56),
		"paint_rubber":Color(0.045, 0.055, 0.06)}
	for channel: String in colors:
		var color: Color = colors[channel].srgb_to_linear()
		config[channel] = [color.r, color.g, color.b, 1.0]
	return config

## Continuous capsule loop; x is supplied by the authored left/right track.
static func track_transform(distance: float, x: float) -> Transform3D:
	var phase := fposmod(distance, TRACK_LENGTH)
	var straight := TRACK_HALF_LENGTH * 2.0
	var arc := PI * TRACK_RADIUS
	var angle := 0.0
	var at := Vector3(x, TRACK_CENTER_Y + TRACK_RADIUS, -TRACK_HALF_LENGTH)
	if phase < straight:
		at.z += phase
	elif phase < straight + arc:
		angle = (phase - straight) / TRACK_RADIUS
		at = Vector3(x, TRACK_CENTER_Y + cos(angle) * TRACK_RADIUS,
			TRACK_HALF_LENGTH + sin(angle) * TRACK_RADIUS)
	elif phase < straight * 2.0 + arc:
		angle = PI
		at = Vector3(x, TRACK_CENTER_Y - TRACK_RADIUS,
			TRACK_HALF_LENGTH - (phase - straight - arc))
	else:
		angle = PI + (phase - straight * 2.0 - arc) / TRACK_RADIUS
		at = Vector3(x, TRACK_CENTER_Y + cos(angle) * TRACK_RADIUS,
			-TRACK_HALF_LENGTH + sin(angle) * TRACK_RADIUS)
	return Transform3D(Basis(Vector3.RIGHT, angle), at)

static func track_distance(at: Vector3) -> float:
	var straight := TRACK_HALF_LENGTH * 2.0
	var arc := PI * TRACK_RADIUS
	if at.z > TRACK_HALF_LENGTH + 0.001:
		return straight + atan2(at.z - TRACK_HALF_LENGTH, at.y - TRACK_CENTER_Y) * TRACK_RADIUS
	if at.z < -TRACK_HALF_LENGTH - 0.001:
		return straight * 2.0 + arc + (atan2(at.z + TRACK_HALF_LENGTH, at.y - TRACK_CENTER_Y) + PI) * TRACK_RADIUS
	if at.y >= TRACK_CENTER_Y:
		return at.z + TRACK_HALF_LENGTH
	return straight + arc + TRACK_HALF_LENGTH - at.z

## Attachment model ("cannon", "plasma_quad", ...) or empty.
static func turret_model(draft: Dictionary) -> String:
	return TURRET_PARTS.get(draft.get("parts", {}).get("utility", ""), "") if enabled(draft) else ""

## Weapon family ("cannon" / "plasma") or empty.
static func turret_kind(draft: Dictionary) -> String:
	return family(turret_model(draft))

static func family(model: String) -> String:
	return model.get_slice("_", 0)

## Barrel offset (x, y) in the elevating frame, source metres, for a shot.
static func turret_barrel(model: String, shot_sequence: int) -> Vector2:
	var barrels: Array = TURRET_BARRELS.get(model, [[0.0, 0.0]])
	var entry: Array = barrels[posmod(shot_sequence - 1, barrels.size())]
	return Vector2(entry[0], entry[1])

## Barrel direction in the chassis frame, -Z forward at zero yaw and pitch.
static func turret_direction(yaw: float, pitch: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD

## Elevation trunnion in the chassis frame at game scale; the breech of the ray.
## A barrel offset moves the breech parallel to the bore (multi-barrel models).
static func turret_breech(size: Vector3, yaw: float, pitch := 0.0, barrel := Vector2.ZERO) -> Vector3:
	var local := TURRET_YAW_PIVOT + Basis(Vector3.UP, yaw) * (TURRET_PITCH_PIVOT - TURRET_YAW_PIVOT)
	if barrel != Vector2.ZERO:
		local += Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(barrel.x, barrel.y, 0.0)
	return local * BotScale.from_size(size)

static func turret_muzzle(size: Vector3, kind: String, yaw: float, pitch: float, barrel := Vector2.ZERO) -> Vector3:
	return turret_breech(size, yaw, pitch, barrel) + turret_direction(yaw, pitch) * float(TURRET_MUZZLE.get(family(kind), 0.7)) * BotScale.from_size(size)

## Lowest clear elevation at a bearing: the stricter of the two surrounding
## audit samples, matching the audit's own verification rule.
static func turret_pitch_min(kind: String, yaw: float) -> float:
	var table: Array = TURRET_DEPRESSION.get(kind, TURRET_DEPRESSION.get(family(kind), TURRET_DEPRESSION.cannon))
	var index := int(fposmod(rad_to_deg(yaw), 360.0) / TURRET_DEPRESSION_STEP) % table.size()
	return deg_to_rad(maxf(float(table[index]), float(table[(index + 1) % table.size()])))

## Chassis-frame yaw/pitch that point the barrel at a world direction, pitch
## clamped to the stops at that bearing. Yaw is unbounded (continuous traverse).
static func turret_target(chassis: Basis, world_direction: Vector3, kind: String) -> Vector2:
	var local := chassis.orthonormalized().inverse() * world_direction
	var yaw := atan2(-local.x, -local.z)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	return Vector2(yaw, clampf(pitch, turret_pitch_min(kind, yaw), TURRET_PITCH_MAX))

## Bounded servo step shared by authority and tests. A depressed barrel first
## elevates before traversing into a bearing whose hull clearance needs it.
static func turret_slew(current: Vector2, target: Vector2, delta: float, kind: String) -> Vector2:
	var yaw_step := TURRET_YAW_RATE * maxf(0.0, delta)
	var candidate := wrapf(current.x + clampf(wrapf(target.x - current.x, -PI, PI), -yaw_step, yaw_step), -PI, PI)
	var candidate_floor := turret_pitch_min(kind, candidate)
	var yaw := candidate if current.y >= candidate_floor - 0.0001 else current.x
	var goal := clampf(maxf(target.y, candidate_floor), turret_pitch_min(kind, yaw), TURRET_PITCH_MAX)
	var pitch := move_toward(current.y, goal, TURRET_PITCH_RATE * maxf(0.0, delta))
	return Vector2(yaw, pitch)
