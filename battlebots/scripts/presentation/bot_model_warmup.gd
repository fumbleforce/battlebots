extends RefCounted
## Loads the heavy bot model scenes on background threads while the player is
## in the menus, and keeps them referenced for the whole run (#70). Without it,
## every Woodland start reloaded the Atlas MX models for the giant (~1.8 s on an
## RTX 3080 machine, measured 24 September 2026), because leaving a match freed
## the last reference. Presentation only; servers never run the menus.
const PATHS := [
	"res://assets/models/atlas_runtime/atlas_mx.glb",
	"res://assets/models/atlas_runtime/atlas_drives.glb",
	"res://assets/models/atlas_runtime/atlas_turret.glb",
	"res://assets/models/atlas_runtime/atlas_tools.glb",
	"res://assets/models/atlas_runtime/atlas_lifter.glb",
	"res://assets/models/scorpion_runtime/scorpion.glb",
	"res://assets/models/scorpion_runtime/leg_upper.glb",
	"res://assets/models/scorpion_runtime/leg_lower.glb",
	"res://assets/models/scorpion_runtime/leg_foot.glb",
]
static var _held: Dictionary = {}
static var _pending: Array[String] = []

## Starts background loads for every model not already held. Safe to repeat.
static func begin() -> void:
	for path: String in PATHS:
		if _held.has(path) or path in _pending or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)

## Collects finished loads; call every frame until it returns true.
static func poll() -> bool:
	for path: String in _pending.duplicate():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_held[path] = ResourceLoader.load_threaded_get(path)
			_pending.erase(path)
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_pending.erase(path)
	return _pending.is_empty()

static func held() -> int:
	return _held.size()
