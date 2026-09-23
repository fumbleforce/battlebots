class_name GraphicsRuntime
extends Node
## One client-local owner; keeps authored lighting and applies preferences to new worlds.
var values: Dictionary = GraphicsOptions.DEFAULTS.duplicate(true)
var _environments: Dictionary = {}
var _lights: Dictionary = {}
var _particles: Dictionary = {}
var _viewports: Array[WeakRef] = []
var _fps_label: Label
var _elapsed := 0.0
var _original_fps := 0

func _ready() -> void:
	_original_fps = Engine.max_fps
	if DisplayServer.get_name() == "headless": return
	get_tree().node_added.connect(_queue_node)
	get_tree().node_removed.connect(_unregister)
	var overlay := CanvasLayer.new()
	overlay.layer = 90
	add_child(overlay)
	_fps_label = Label.new()
	_fps_label.position = Vector2(18, 12)
	_fps_label.add_theme_font_size_override("font_size",18)
	_fps_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_fps_label.add_theme_constant_override("shadow_offset_x",1)
	_fps_label.add_theme_constant_override("shadow_offset_y",1)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_fps_label)
	_scan(get_tree().root)
	apply(values)

func _unregister(node: Node) -> void:
	var id := node.get_instance_id()
	_environments.erase(id)
	_lights.erase(id)
	_particles.erase(id)
	if node is Viewport:
		for index: int in range(_viewports.size()-1,-1,-1):
			if _viewports[index].get_ref() == node or _viewports[index].get_ref() == null:
				_viewports.remove_at(index)

func _queue_node(node: Node) -> void:
	# Environment art configures children during _ready, after node_added.
	if node is Viewport or node is WorldEnvironment or node is GPUParticles3D or node is Light3D:
		_register.call_deferred(weakref(node))

func _scan(node: Node) -> void:
	_register(weakref(node))
	for child: Node in node.get_children(): _scan(child)

func _register(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	if node is Viewport:
		for known: WeakRef in _viewports:
			if known.get_ref() == node: return
		_viewports.append(reference)
		_apply_viewport(node)
	elif node is WorldEnvironment and node.environment != null:
		if _environments.has(node.get_instance_id()): return
		var base: Environment = node.environment.duplicate(true)
		node.environment = base.duplicate(true)
		_environments[node.get_instance_id()] = {"node":reference,"base":base}
		_apply_environment(node,base)
	elif node is GPUParticles3D:
		if not _particles.has(node.get_instance_id()):
			_particles[node.get_instance_id()] = {"node":reference,"amount":node.amount}
			node.amount = maxi(8,roundi(node.amount * [0.35,0.65,1.0,1.25][values.particles]))
	elif node is Light3D:
		if _lights.has(node.get_instance_id()): return
		_lights[node.get_instance_id()] = {"node":reference,"shadow":node.shadow_enabled}
		node.shadow_enabled = _lights[node.get_instance_id()].shadow and values.shadows > 0

func apply(draft: Dictionary) -> void:
	if not GraphicsOptions.valid(draft): return
	values = draft.duplicate(true)
	if DisplayServer.get_name() == "headless": return
	Engine.max_fps = values.fps_limit
	for reference: WeakRef in _viewports:
		var viewport: Viewport = reference.get_ref()
		if is_instance_valid(viewport): _apply_viewport(viewport)
	for id: int in _environments.keys():
		var item: Dictionary = _environments[id]
		var node: WorldEnvironment = item.node.get_ref()
		if is_instance_valid(node): _apply_environment(node,item.base)
		else: _environments.erase(id)
	for id: int in _lights.keys():
		var item: Dictionary = _lights[id]
		var node: Light3D = item.node.get_ref()
		if is_instance_valid(node): node.shadow_enabled = item.shadow and values.shadows > 0
		else: _lights.erase(id)
	for id: int in _particles.keys():
		var item: Dictionary = _particles[id]
		var node: GPUParticles3D = item.node.get_ref()
		if is_instance_valid(node): node.amount = maxi(8,roundi(item.amount * [0.35,0.65,1.0,1.25][values.particles]))
		else: _particles.erase(id)
	var quality: int = [0,2,3,5][values.shadows]
	RenderingServer.directional_shadow_atlas_set_size([1024,2048,4096,8192][values.shadows],true)
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(quality)
	if forward_plus():
		RenderingServer.environment_set_ssao_quality([0,1,2,3][values.ao],values.ao < 3,0.5,2,50.0,300.0)
		RenderingServer.environment_set_ssil_quality([0,1,2,3][values.indirect],values.indirect < 3,0.5,2,50.0,300.0)
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		RenderingServer.screen_space_roughness_limiter_set_active(values.roughness_limiter,0.25,0.18)
	if is_instance_valid(_fps_label): _fps_label.visible = values.show_fps

static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func _apply_viewport(viewport: Viewport) -> void:
	var temporal := forward_plus()
	var modern := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var fsr2: bool = values.upscaler == "fsr2" and temporal
	viewport.use_taa = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var scaling_mode := Viewport.SCALING_3D_MODE_FSR2 if fsr2 else (Viewport.SCALING_3D_MODE_FSR if values.upscaler == "fsr1" and modern else Viewport.SCALING_3D_MODE_BILINEAR)
	if viewport.scaling_3d_mode != scaling_mode:
		viewport.scaling_3d_scale = 1.0
		viewport.scaling_3d_mode = scaling_mode
	viewport.scaling_3d_scale = minf(values.render_scale / 100.0,1.0) if fsr2 or values.upscaler == "fsr1" else values.render_scale / 100.0
	viewport.fsr_sharpness = 2.0 * (1.0 - values.sharpness / 100.0)
	if not fsr2:
		viewport.msaa_3d = {"msaa2":1,"msaa4":2,"msaa8":3,"taa_msaa":1}.get(values.aa,0)
		viewport.use_taa = temporal and values.aa in ["taa","taa_msaa"]
		if modern: viewport.screen_space_aa = {"fxaa":1,"smaa":2}.get(values.aa,0)
	viewport.anisotropic_filtering_level = values.anisotropy
	viewport.use_debanding = modern and values.debanding
	viewport.positional_shadow_atlas_size = [1024,2048,4096,8192][values.shadows]

func _apply_environment(node: WorldEnvironment, base: Environment) -> void:
	var env := node.environment
	var advanced := forward_plus()
	env.ssao_enabled = advanced and values.ao > 0
	env.ssil_enabled = advanced and values.indirect > 0
	env.ssr_enabled = advanced and values.reflections > 0
	env.ssr_max_steps = [32,32,64,128][values.reflections]
	env.glow_enabled = base.glow_enabled and values.bloom
	env.volumetric_fog_enabled = advanced and base.volumetric_fog_enabled and values.fog
	# Preserve authored nonvolumetric atmosphere, color grading and exposure.
	env.adjustment_enabled = true
	env.adjustment_brightness = base.adjustment_brightness * values.brightness / 100.0
	env.adjustment_contrast = base.adjustment_contrast * values.contrast / 100.0
	env.adjustment_saturation = base.adjustment_saturation * values.saturation / 100.0

func _process(delta: float) -> void:
	if not is_instance_valid(_fps_label) or not _fps_label.visible: return
	_elapsed += delta
	if _elapsed < 0.25: return
	_elapsed = 0.0
	var fps := Engine.get_frames_per_second()
	_fps_label.text = "%d FPS  ·  %.1f ms" % [fps,1000.0 / maxi(fps,1)]

func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless": Engine.max_fps = _original_fps
