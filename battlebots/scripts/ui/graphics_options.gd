class_name GraphicsOptions
extends RefCounted
## Stored values are renderer-independent; unsupported effects are gated at runtime.
const DEFAULTS := {"aa":"taa_msaa", "upscaler":"native", "render_scale":100, "sharpness":50,
	"anisotropy":4, "shadows":2, "particles":2, "ao":2, "indirect":1, "reflections":1,
	"bloom":true, "fog":true, "debanding":true, "roughness_limiter":true,
	"brightness":100, "contrast":100, "saturation":100, "fps_limit":0, "show_fps":false}
const CHOICES := {
	"aa": {"Off":"off", "FXAA":"fxaa", "SMAA":"smaa", "MSAA 2×":"msaa2", "MSAA 4×":"msaa4", "MSAA 8×":"msaa8", "Temporal AA":"taa", "Temporal + MSAA 2×":"taa_msaa"},
	"upscaler":{"Native / resolution scale":"native", "AMD FSR 1":"fsr1", "AMD FSR 2.2":"fsr2"},
	"anisotropy":{"Off":0, "2×":1, "4×":2, "8×":3, "16×":4},
	"particles":{"Low":0,"Medium":1,"High":2,"Ultra":3},
	"shadows":{"Off":0,"Medium":1,"High":2,"Ultra":3},
	"ao":{"Off":0,"Medium":1,"High":2,"Ultra":3},
	"indirect":{"Off":0,"Medium":1,"High":2,"Ultra":3},
	"reflections":{"Off":0,"Medium":1,"High":2,"Ultra":3},
	"fps_limit":{"Unlimited":0,"30 FPS":30,"60 FPS":60,"90 FPS":90,"120 FPS":120,"144 FPS":144,"165 FPS":165,"240 FPS":240}}
const RANGES := {"render_scale":[50,150,5],"sharpness":[0,100,5],"brightness":[70,130,1],"contrast":[80,120,1],"saturation":[0,130,5]}
const PRESETS := ["Low", "Medium", "High", "Ultra"]

static func valid(values: Dictionary) -> bool:
	if values.size() != DEFAULTS.size(): return false
	for key: String in DEFAULTS:
		if not values.has(key) or typeof(values[key]) != typeof(DEFAULTS[key]): return false
		if CHOICES.has(key) and not values[key] in CHOICES[key].values(): return false
		if RANGES.has(key) and (values[key] < RANGES[key][0] or values[key] > RANGES[key][1]): return false
	return true

static func preset(index: int, original: Dictionary = DEFAULTS) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	# Personal display/color preferences are not quality settings.
	for key: String in ["brightness","contrast","saturation","fps_limit","show_fps"]:
		result[key] = original[key]
	match index:
		0:
			result.merge({"aa":"fxaa","particles":0,"anisotropy":2,"shadows":1,"ao":0,"indirect":0,"reflections":0,"fog":false},true)
		1:
			result.merge({"aa":"msaa2","particles":1,"anisotropy":3,"shadows":1,"ao":1,"indirect":0,"reflections":0},true)
		3:
			result.merge({"upscaler":"fsr2","particles":3,"shadows":3,"ao":3,"indirect":3,"reflections":3},true)
	return result

static func preset_index(values: Dictionary) -> int:
	for index: int in range(PRESETS.size()):
		if preset(index,values) == values: return index
	return 4
