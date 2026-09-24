extends RefCounted
## Releases script static caches (loaded configs, shared materials, meshes and
## audio streams) before the engine tears GDScript down at exit. Resources left
## in script statics are destroyed during language teardown; on Windows that
## crashes intermittently after tests pass (#10). Only scripts already loaded
## are touched, so exit never compiles anything. No class_name (#65).

## Script path -> static members to release (null for objects, clear() for
## collections).
const CACHES := {
	"res://scripts/core/bot_physics.gd": ["_loaded"],
	"res://scripts/core/front_tool_tuning.gd": ["_loaded"],
	"res://scripts/core/arena_spawns.gd": ["_loaded"],
	"res://scripts/core/heat_relief.gd": ["_loaded"],
	"res://scripts/core/atlas_drive_rig.gd": ["_loaded"],
	"res://scripts/core/turret_tuning.gd": ["_loaded"],
	"res://scripts/core/nimble_bots.gd": ["_loaded"],
	"res://scripts/presentation/turret_special_effects.gd": ["_streams"],
	"res://scripts/presentation/turret_harpoon_effects.gd": ["_streams"],
	"res://scripts/presentation/atlas_tool_visual.gd": ["_streams"],
	"res://scripts/presentation/turret_shot_effects.gd": ["_streams", "_smoke_materials", "_burn_textures", "_soft"],
	"res://scripts/presentation/garage_bot_thumbnail_renderer.gd": ["_cache"],
	"res://scripts/presentation/sawblade_visual.gd": ["hammer_samples", "tread_samples"],
	"res://scripts/arena/woodland_ground.gd": ["_obstacles", "_scan_meshes", "_scan_shapes"],
}

static func release() -> void:
	for path: String in CACHES:
		if not ResourceLoader.has_cached(path):
			continue
		var script: Script = load(path)
		for member: String in CACHES[path]:
			var value: Variant = script.get(member)
			if value is Dictionary or value is Array:
				value.clear()
			else:
				script.set(member, null)
