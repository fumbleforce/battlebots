extends RefCounted
## Default own-shot camera recoil: the strength each accepted shot adds to the
## shooter's camera kick (TankSightCamera.kick / BotOrbitCamera.add_recoil).
## Presentation only. Practice Duel tuning (#91) starts its Camera recoil field
## from these. Loaded by path, not class name (stale editor class cache).
const PER_SHOT := {"minigun":0.0, "plasma":0.12, "flamer":0.0, "tesla":0.18, "railgun":1.3, "harpoon":0.3, "mortar":0.9}
const CANNON := {"single":0.85, "dual":0.6, "quad":0.45}
const FALLBACK := 0.12

static func per_shot(kind: String, model: String) -> float:
	if kind == "cannon":
		return float(CANNON.single if model == "cannon" else (CANNON.dual if model.ends_with("_dual") else CANNON.quad))
	return float(PER_SHOT.get(kind, FALLBACK))
