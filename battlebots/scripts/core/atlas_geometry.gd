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

static func enabled(draft: Dictionary) -> bool:
	return draft.get("parts", {}).get("chassis") == "atlas_mx"

static func gun_offset(draft: Dictionary, size: Vector3) -> Vector3:
	return GUN_OFFSET * BotScale.from_size(size) if enabled(draft) else Vector3.ZERO

static func paint_defaults() -> Dictionary:
	var config := SawbladeConfig.defaults()
	var colors := {"paint_primary":Color(0.86, 0.51, 0.055),
		"paint_secondary":Color(0.205, 0.225, 0.235), "paint_metal":Color(0.43, 0.46, 0.48),
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
