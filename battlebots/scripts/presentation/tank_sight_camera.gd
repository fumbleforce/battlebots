class_name TankSightCamera
extends Node3D
## Tank-game third-person sight for turret builds (B control presentation).
## Mouse yaw/pitch/zoom, sensitivity and inversion stay in the shared orbit
## rig; this camera frames them from a sight point well above the turret, so
## the screen-centre crosshair looks over the hull into the world instead of
## sitting on the tank. The turret then chases the crosshair.
## Sight point height above the hull origin and allowed look range.
const SIGHT_HEIGHT := 1.45
const PITCH_MIN := -0.2094395 # -12 degrees
const PITCH_MAX := 0.6981317 # 40 degrees
const CAMERA_RADIUS := 0.3
var camera := Camera3D.new()
var rig: BotOrbitCamera
var active := false:
	set(value):
		active = value
		if is_instance_valid(camera) and camera.is_inside_tree():
			if value: camera.make_current()
			elif is_instance_valid(rig) and is_instance_valid(rig.camera) and rig.camera.is_inside_tree(): rig.camera.make_current()
var _distance := -1.0
var _probe := SphereShape3D.new()

func _init() -> void:
	name = "TankSightCamera"
	camera.name = "SightCamera"
	camera.near = 0.1
	camera.far = 500.0
	add_child(camera)

func clamp_pitch(pitch: float) -> float:
	return clampf(pitch, PITCH_MIN, PITCH_MAX)

## Place the sight camera for this frame. Presentation only.
func update_view(delta: float, source: BotSource) -> void:
	if not is_instance_valid(rig) or not is_instance_valid(source): return
	var view := source.read_view()
	var anchor := source.camera_anchor()
	var scale := float(anchor.get_meta("bot_scale", BotScale.FACTOR)) if is_instance_valid(anchor) else BotScale.FACTOR
	# World-up sight point: tilting over rough ground never rolls the view.
	var pivot := view.pose.origin + Vector3.UP * SIGHT_HEIGHT * scale
	pivot = rig._inside_arena(pivot)
	var basis := Basis.from_euler(Vector3(-clamp_pitch(rig.pitch), rig.yaw, 0.0))
	var back := basis.z
	# The rig's zoom range sets the boom; keep the arena boundary planes solid.
	var wanted := rig._boundary_distance(pivot, back, rig.desired_distance * 0.85)
	_probe.radius = CAMERA_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = back * wanted
	query.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	query.exclude = source.camera_exclusions()
	query.margin = 0.02
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		wanted = 0.0
	else:
		wanted = maxf(0.0, wanted * space.cast_motion(query)[0] - 0.03)
	# Pull in immediately when blocked, ease back out afterwards.
	if _distance < 0.0 or wanted < _distance:
		_distance = wanted
	else:
		_distance = lerpf(_distance, wanted, 1.0 - exp(-8.0 * maxf(delta, 0.0)))
	camera.global_transform = Transform3D(basis, pivot + back * _distance)
	if is_instance_valid(rig.camera): camera.fov = rig.camera.fov

func reset() -> void:
	_distance = -1.0
