class_name NitroFlameVisual
extends Node3D
## Presentation-only nitro plume. Reads the replicated BotView.nitro_active and
## never infers boost from motion. Jets attach to the authored exhaust outlets.
const PARTICLES_PER_OUTLET := 56
const ATTACK := 14.0
const RELEASE := 7.0
var outlets: Array[Dictionary] = []
var intensity := 0.0
var boosting := false
var _scale := 1.0
var _time := 0.0
var _light: OmniLight3D
static var _cone_mesh: CylinderMesh
static var _ember_mesh: QuadMesh
static var _glow_mesh: QuadMesh
static var _instances := 0

func _enter_tree() -> void:
	_instances += 1

func _exit_tree() -> void:
	_instances -= 1
	if _instances == 0:
		_cone_mesh = null
		_ember_mesh = null
		_glow_mesh = null

## `presentation` is the bot's visual root; `size` is the physics hull size.
func configure(presentation: Node3D, size: Vector3, geometry_scale: float) -> void:
	_scale = geometry_scale
	for outlet: Dictionary in find_outlets(presentation, size):
		outlet.merge(_make_jet(outlets.size()))
		outlets.append(outlet)
	_light = OmniLight3D.new()
	_light.name = "NitroGlow"
	_light.light_color = Color(0.35, 0.55, 1.0)
	_light.omni_range = 2.4 * _scale
	_light.shadow_enabled = false
	_light.hide()
	add_child(_light)
	_light.top_level = true

## Outlets as {anchor, offset, direction, radius} in the anchor's local space,
## so jets follow animated or scaled modules without duplicate coordinates.
static func find_outlets(presentation: Node3D, size: Vector3) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	# Scorpion: the imported open pipe lips, pointing along their local up.
	for label: String in ["ExhaustLeft", "ExhaustRight"]:
		var lip := presentation.find_child(label, true, false) as Node3D
		if lip != null and _shown(lip, presentation):
			found.append({"anchor":lip, "offset":Vector3.ZERO, "direction":Vector3.UP, "radius":0.045})
	if not found.is_empty(): return found
	for mesh: MeshInstance3D in presentation.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not _shown(mesh, presentation): continue
		var label := str(mesh.name)
		if label.begins_with("Horizontal hollow exhaust"):
			# Sawblade: rear-facing hollow pipes; the open end is the far +Z face.
			var box := mesh.get_aabb()
			var center := box.get_center()
			found.append({"anchor":mesh, "offset":Vector3(center.x, center.y, box.end.z),
				"direction":Vector3.BACK, "radius":minf(box.size.x, box.size.y) * 0.5})
		elif label.begins_with("Exhaust") and label.ends_with("Surface"):
			# Atlas: one merged mesh holding two upright stacks; use their top rims.
			found.append_array(_stack_tops(mesh))
	if not found.is_empty(): return found
	# Other bodies have no authored outlet: vent from the rear of the visible
	# model, which can extend past the physics hull and would bury the jets.
	var hull := AABB(Vector3(-size.x, -size.y, -size.z) * 0.5, size)
	var model := _model_bounds(presentation)
	if model.has_volume(): hull = model
	var center := hull.get_center()
	for side: int in [-1, 1]:
		found.append({"anchor":presentation, "direction":Vector3(0, 0.25, 1).normalized(),
			"offset":Vector3(center.x + side * hull.size.x * 0.22, hull.position.y + hull.size.y * 0.4, hull.end.z + 0.02),
			"radius":size.y * 0.09})
	return found

## Authored visibility relative to the bot, so a bot spawned hidden keeps its pipes.
static func _shown(node: Node, root: Node) -> bool:
	var current := node
	while current != null and current != root:
		if current is Node3D and not (current as Node3D).visible: return false
		current = current.get_parent()
	return current == root

## Visible mesh bounds in the presentation root space.
static func _model_bounds(presentation: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var inverse := presentation.global_transform.affine_inverse()
	for mesh: MeshInstance3D in presentation.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not _shown(mesh, presentation): continue
		var box: AABB = inverse * mesh.global_transform * mesh.get_aabb()
		if not box.position.is_finite() or not box.size.is_finite(): continue
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

static func _stack_tops(mesh: MeshInstance3D) -> Array[Dictionary]:
	var top := -INF
	var surfaces: Array[PackedVector3Array] = []
	for index: int in mesh.mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
		surfaces.append(vertices)
		for vertex: Vector3 in vertices: top = maxf(top, vertex.y)
	var rims := {-1: [], 1: []}
	for vertices: PackedVector3Array in surfaces:
		for vertex: Vector3 in vertices:
			if vertex.y >= top - 0.01: rims[-1 if vertex.x < 0.0 else 1].append(vertex)
	var result: Array[Dictionary] = []
	for side: int in [-1, 1]:
		var rim: Array = rims[side]
		if rim.is_empty(): continue
		var low := Vector3.INF
		var high := -Vector3.INF
		for vertex: Vector3 in rim:
			low = low.min(vertex)
			high = high.max(vertex)
		result.append({"anchor":mesh, "offset":(low + high) * 0.5, "direction":Vector3.UP,
			"radius":maxf(high.x - low.x, high.z - low.z) * 0.5})
	return result

func show_state(view: BotView, delta: float) -> void:
	if view == null or not is_finite(delta) or delta < 0.0: return
	boosting = view.nitro_active and not view.eliminated
	var target := 1.0 if boosting else 0.0
	intensity = lerpf(intensity, target, 1.0 - exp(-delta * (ATTACK if target > intensity else RELEASE)))
	if intensity < 0.005: intensity = 0.0
	_time += delta
	var lit := Vector3.ZERO
	var live := 0
	for index: int in outlets.size():
		var outlet: Dictionary = outlets[index]
		var anchor: Node3D = outlet.anchor
		var flame: MeshInstance3D = outlet.flame
		var embers: GPUParticles3D = outlet.embers
		var glow: MeshInstance3D = outlet.glow
		if not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
			flame.hide()
			glow.hide()
			embers.emitting = false
			continue
		var frame := anchor.global_transform
		var origin := frame * (outlet.offset as Vector3)
		var direction := (frame.basis * (outlet.direction as Vector3)).normalized()
		var radius: float = outlet.radius * frame.basis.get_scale().x
		embers.global_transform = Transform3D(_frame_along(direction), origin)
		embers.emitting = boosting
		flame.visible = intensity > 0.0
		glow.visible = flame.visible
		if not flame.visible: continue
		# Length surges and gutters so paired jets never pulse in lockstep.
		var surge := 0.88 + 0.12 * sin(_time * 41.0 + index * 2.1) + 0.06 * sin(_time * 97.0 + index)
		var length := maxf(radius * 16.0, 0.8 * _scale) * intensity * surge
		var width := maxf(radius, 0.05 * _scale) * 1.25 * (0.75 + 0.25 * intensity)
		var axes := _frame_along(direction)
		# The unit cone's +Y nozzle sits at the outlet; its tip points down the jet.
		var basis := Basis(axes.x * width, -direction * length, -axes.z * width)
		flame.global_transform = Transform3D(basis, origin + direction * length * 0.5)
		flame.set_instance_shader_parameter(&"intensity", intensity)
		# A camera-facing bloom at the nozzle reads even when the jet points at the view.
		glow.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(radius * 11.0, 0.45 * _scale) * intensity * surge),
			origin + direction * radius * 1.2)
		lit += origin + direction * length * 0.3
		live += 1
	_light.visible = live > 0
	if live > 0:
		_light.global_position = lit / live
		_light.light_energy = intensity * (1.5 + 0.4 * sin(_time * 63.0))

func _make_jet(index: int) -> Dictionary:
	var flame := MeshInstance3D.new()
	flame.name = "NitroFlame" + str(index)
	flame.mesh = _cone()
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_instance_shader_parameter(&"seed", float(index) * 1.7)
	flame.hide()
	add_child(flame)
	flame.top_level = true
	var glow := MeshInstance3D.new()
	glow.name = "NitroGlow" + str(index)
	glow.mesh = _glow()
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.hide()
	add_child(glow)
	glow.top_level = true
	var embers := GPUParticles3D.new()
	embers.name = "NitroEmbers" + str(index)
	embers.amount = PARTICLES_PER_OUTLET
	embers.lifetime = 0.32
	embers.emitting = false
	embers.local_coords = false
	embers.fixed_fps = 60
	embers.interpolate = true
	embers.visibility_aabb = AABB(Vector3(-4, -4, -4) * _scale, Vector3(8, 8, 8) * _scale)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.process_material = _embers(_scale)
	embers.draw_pass_1 = _ember()
	add_child(embers)
	embers.top_level = true
	return {"flame":flame, "glow":glow, "embers":embers}

static func _frame_along(direction: Vector3) -> Basis:
	var side := direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, direction, side.cross(direction)).orthonormalized()

static func _cone() -> CylinderMesh:
	if _cone_mesh != null: return _cone_mesh
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 1.0
	_cone_mesh.bottom_radius = 0.0
	_cone_mesh.height = 1.0
	_cone_mesh.radial_segments = 16
	_cone_mesh.rings = 6
	_cone_mesh.cap_top = false
	_cone_mesh.cap_bottom = false
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/nitro_flame.gdshader")
	_cone_mesh.material = material
	return _cone_mesh

## Per bot, because jet speed and ember size follow the hull scale.
static func _embers(geometry_scale: float) -> ParticleProcessMaterial:
	var motion := ParticleProcessMaterial.new()
	# Local Y is the jet axis (see _frame_along).
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.05 * geometry_scale
	motion.direction = Vector3.UP
	motion.spread = 9.0
	motion.initial_velocity_min = 2.0 * geometry_scale
	motion.initial_velocity_max = 3.0 * geometry_scale
	motion.gravity = Vector3.ZERO
	motion.damping_min = 4.0
	motion.damping_max = 7.0
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.scale_min = 0.45 * geometry_scale
	motion.scale_max = 0.8 * geometry_scale
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1.0))
	shrink.add_point(Vector2(1, 0.15))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink
	motion.scale_curve = shrink_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(0.7, 1.4, 3.2, 0.9), Color(0.15, 0.55, 3.0, 0.75),
		Color(0.2, 0.2, 2.0, 0.4), Color(0.1, 0.08, 0.8, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.use_hdr = true
	ramp.gradient = gradient
	motion.color_ramp = ramp
	return motion

static func _ember() -> QuadMesh:
	if _ember_mesh != null: return _ember_mesh
	_ember_mesh = QuadMesh.new()
	_ember_mesh.size = Vector2.ONE * 0.2
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.gradient = falloff
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = soft
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_ember_mesh.material = material
	return _ember_mesh

static func _glow() -> QuadMesh:
	if _glow_mesh != null: return _glow_mesh
	_glow_mesh = QuadMesh.new()
	_glow_mesh.size = Vector2.ONE
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.gradient = falloff
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.3, 0.6, 1.6)
	material.albedo_texture = soft
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_glow_mesh.material = material
	return _glow_mesh
