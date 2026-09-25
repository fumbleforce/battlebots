extends Node3D
## Floating damage numbers (#85) that spray out of a struck bot at the impact
## point. Driven only by confirmed combat events (CombatImpactFeedback); no
## collision, gameplay state or hit prediction lives here.
const TUNING := preload("res://scripts/core/damage_number_tuning.gd")
const FONT := preload("res://ui/menus/fonts/BarlowCondensed-Bold.ttf")
const GOLDEN_ANGLE := 2.39996323
## Used when there is no camera (headless tests): typical gameplay framing.
const FALLBACK_DISTANCE := 10.0
const FALLBACK_FOV := 70.0
## Scale a number starts its pop from.
const POP_FROM := 0.35

var tuning: TUNING = TUNING.settings() as TUNING
## Live numbers, oldest first: {label, origin, offset, velocity, age, damage,
## incoming, size}.
var _live: Array[Dictionary] = []
var _serial := 0

func _process(delta: float) -> void:
	advance(delta)

## One number per hit, thrown up and to the side from `position` (never along
## the hit normal, which points at the attacker and so usually the camera).
## `incoming` marks hits on the local player's bot.
func spawn(position: Vector3, damage: float, incoming := false) -> void:
	if not position.is_finite() or not is_finite(damage) \
		or damage < tuning.value("text", "min_damage"): return
	while _live.size() >= int(tuning.value("text", "max_live")):
		_live.pop_front().label.queue_free()
	var angle := float(_serial) * GOLDEN_ANGLE
	_serial += 1
	var side := Vector3(cos(angle), 0.0, sin(angle)) * tuning.value("motion", "spread")
	var velocity := side + Vector3.UP * tuning.value("motion", "up")
	var label := Label3D.new()
	label.font = FONT
	label.font_size = int(tuning.value("text", "font_size"))
	label.outline_size = int(tuning.value("text", "outline_size"))
	label.outline_modulate = tuning.color("outline")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	var entry := {"label":label, "origin":position, "offset":Vector3.ZERO, "velocity":velocity,
		"age":0.0, "damage":damage, "incoming":incoming}
	_live.append(entry)
	_style(entry)
	_place(entry)

func advance(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta): return
	var lifetime := tuning.value("timing", "lifetime_seconds")
	var gravity := tuning.value("motion", "gravity")
	var drag := tuning.value("motion", "drag")
	for index: int in range(_live.size() - 1, -1, -1):
		var entry: Dictionary = _live[index]
		entry.age += delta
		if entry.age >= lifetime:
			entry.label.queue_free()
			_live.remove_at(index)
			continue
		var velocity: Vector3 = entry.velocity
		velocity.y -= gravity * delta
		velocity *= maxf(0.0, 1.0 - drag * delta)
		entry.velocity = velocity
		entry.offset += velocity * delta
		_place(entry)

func live_count() -> int:
	return _live.size()

## Texts of the live numbers, oldest first (tests and diagnostics).
func live_texts() -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in _live: result.append(entry.label.text)
	return result

func clear() -> void:
	for entry: Dictionary in _live: entry.label.queue_free()
	_live.clear()

static func format(damage: float) -> String:
	return "%.1f" % damage if damage < 1.0 else str(roundi(damage))

func _style(entry: Dictionary) -> void:
	var label: Label3D = entry.label
	label.text = format(entry.damage)
	var weight := clampf(float(entry.damage) / tuning.value("text", "big_damage"), 0.0, 1.0)
	var tint: Color
	if entry.incoming:
		tint = tuning.color("incoming")
	elif weight < 0.5:
		tint = tuning.color("small").lerp(tuning.color("mid"), weight * 2.0)
	else:
		tint = tuning.color("mid").lerp(tuning.color("big"), weight * 2.0 - 1.0)
	label.modulate = tint
	entry.size = lerpf(tuning.value("text", "small_scale"), tuning.value("text", "big_scale"), weight)

## Keeps a readable on-screen size at any camera distance; the spray scales
## with it so far hits still visibly burst out of the target.
func _place(entry: Dictionary) -> void:
	var label: Label3D = entry.label
	var distance := FALLBACK_DISTANCE
	var fov := FALLBACK_FOV
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		distance = maxf(0.1, camera.global_position.distance_to(entry.origin))
		fov = camera.fov
	var height := clampf(tuning.value("text", "screen_fraction") * 2.0 * tan(deg_to_rad(fov) * 0.5) * distance,
		tuning.value("text", "min_height"), tuning.value("text", "max_height"))
	var reference := tuning.value("text", "screen_fraction") * 2.0 * tan(deg_to_rad(FALLBACK_FOV) * 0.5) * FALLBACK_DISTANCE
	var spread := maxf(1.0, height / reference)
	label.position = entry.origin + entry.offset * spread
	var pop_seconds := tuning.value("timing", "pop_seconds")
	var pop := 1.0
	if pop_seconds > 0.0 and entry.age < pop_seconds * 2.0:
		# Up to pop_scale over pop_seconds, then settle back over the same time.
		var t: float = entry.age / pop_seconds
		pop = lerpf(POP_FROM, tuning.value("timing", "pop_scale"), t) if t < 1.0 \
			else lerpf(tuning.value("timing", "pop_scale"), 1.0, t - 1.0)
	label.pixel_size = height * entry.size * pop / tuning.value("text", "font_size")
	var lifetime := tuning.value("timing", "lifetime_seconds")
	var fade := tuning.value("timing", "fade_seconds")
	var alpha := clampf((lifetime - entry.age) / fade, 0.0, 1.0) if fade > 0.0 else 1.0
	label.modulate.a = alpha
	label.outline_modulate.a = alpha
