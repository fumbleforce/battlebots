extends Node3D
## The modelled roof turret (atlas_turret.glb family): shows the fitted
## attachment, follows the authoritative yaw and elevation smoothly and plays
## the weapon's effects. Shared by the Atlas MX and by every body that carries
## the turret on a WeaponMounts race (#108); this node sits in the Atlas source
## frame, so its parent supplies scale and mount. No authority lives here.
const TURRET_HARPOON_EFFECTS = preload("res://scripts/presentation/turret_harpoon_effects.gd")
## The instanced turret scene.
var root: Node3D
var kind := ""
var model := ""
## TurretShotEffects (cannon, plasma, mortar), TurretSpecialEffects (flamer,
## tesla, railgun) or TURRET_HARPOON_EFFECTS; all expose configure/show_state/clear_effects/muzzles/shot_count.
var effects: Node3D
## Smoothed yaw/pitch actually drawn this frame (also drives the reticle).
var display := Vector2.ZERO
var yaw_node: Node3D
var pitch_node: Node3D
var _rest := {}
var _shown := false
var _sample := Vector2.ZERO
var _sample_rate := Vector2.ZERO
var _sample_tick := -1
var _since_sample := 0.0

## effects_scale: game metres per turret source metre (sizes flashes and sounds).
func assemble(scene_path: String, turret_kind: String, turret_model: String, effects_scale: float) -> void:
	kind = turret_kind
	model = turret_model
	root = load(scene_path).instantiate()
	root.name = "AtlasTurretModule"
	add_child(root)
	var found := {}
	for node: Node in root.find_children("*", "Node3D", true, false):
		found[str(node.name)] = node
	yaw_node = found.get("TurretYaw")
	pitch_node = found.get("TurretPitch")
	# Node names: Attachment<Family><Suffix>, CannonRecoil<Suffix>_i, Muzzle<Family><Suffix>_i.
	var family := kind.capitalize()
	var suffix := model.get_slice("_", 1).capitalize() if "_" in model else ""
	var chosen := "Attachment" + family + suffix
	for label: String in found:
		if label.begins_with("Attachment") and not label.ends_with("Surface"):
			found[label].visible = label == chosen
		elif label == "SponsonsQuad":
			# Turret-integrated armored sponsons house the quad side guns.
			found[label].visible = model.ends_with("_quad")
	for node: Node3D in [yaw_node, pitch_node]:
		if node != null: _rest[node] = node.transform
	var muzzles: Array[Node3D] = []
	var recoils: Array[Node3D] = []
	var barrels: int = AtlasGeometry.turret_barrels(model).size()
	for index: int in barrels:
		var tag := "" if suffix.is_empty() else "%s_%d" % [suffix, index]
		muzzles.append(found.get("Muzzle" + family + tag))
		recoils.append(found.get("CannonRecoil" + tag) if kind == "cannon" else null)
	if kind == "harpoon":
		# The loaded head leaves the tube while the bolt is out.
		recoils = [found.get("HarpoonHead")]
		effects = TURRET_HARPOON_EFFECTS.new()
	elif kind in ["flamer", "tesla", "railgun"]:
		effects = TurretSpecialEffects.new()
	else:
		effects = TurretShotEffects.new()
	effects.name = "TurretShotEffects"
	add_child(effects)
	effects.configure(kind, muzzles, recoils, effects_scale)

## Presentation only. Authoritative angles arrive per physics tick (60 Hz
## locally, 20 Hz snapshots remotely). Estimate their rate from each new
## sample, predict between samples and ease toward the prediction, so the
## turret moves smoothly at any frame rate without lagging the servo.
func show_state(view: BotView, delta: float) -> void:
	var target := Vector2(view.turret_yaw, view.gun_pitch)
	var jump := absf(wrapf(target.x - _sample.x, -PI, PI)) > 1.2
	if not _shown or jump:
		display = target
		_sample = target
		_sample_rate = Vector2.ZERO
		_sample_tick = view.server_tick
		_since_sample = 0.0
	elif view.server_tick != _sample_tick:
		var elapsed := maxf(_since_sample, 1.0 / 240.0)
		_sample_rate = Vector2(
			clampf(wrapf(target.x - _sample.x, -PI, PI) / elapsed, -TurretTuning.settings().yaw_rate, TurretTuning.settings().yaw_rate),
			clampf((target.y - _sample.y) / elapsed, -TurretTuning.settings().pitch_rate, TurretTuning.settings().pitch_rate))
		_sample = target
		_sample_tick = view.server_tick
		_since_sample = 0.0
	_shown = true
	_since_sample += maxf(delta, 0.0)
	var ahead := minf(_since_sample, 0.1)
	var predicted := Vector2(wrapf(_sample.x + _sample_rate.x * ahead, -PI, PI), _sample.y + _sample_rate.y * ahead)
	var ease := 1.0 - exp(-maxf(delta, 0.0) * 30.0)
	display.x = wrapf(display.x + wrapf(predicted.x - display.x, -PI, PI) * ease, -PI, PI)
	display.y = lerpf(display.y, predicted.y, ease)
	if yaw_node != null:
		yaw_node.transform = _rest[yaw_node] * Transform3D(Basis(Vector3.UP, display.x))
	if pitch_node != null:
		pitch_node.transform = _rest[pitch_node] * Transform3D(Basis(Vector3.RIGHT, display.y))
	effects.show_state(view, delta)

func clear_effects() -> void:
	effects.clear_effects()
	_shown = false
