class_name MortarAimVisual
extends Node3D
## Gunner-only artillery marker (B controls presentation): the arc a shell
## fired now would fly and a ground ring of the blast radius where it lands.
## Amber while reloading, bright once a shell is ready; red when the arc is
## still in flight at the trace limit (out of reach).
var _arc := MeshInstance3D.new()
var _ring := MeshInstance3D.new()
var _lines := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()

func _init() -> void:
	name = "MortarAimVisual"
	for material: StandardMaterial3D in [_material, _ring_material]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.vertex_color_use_as_albedo = false
	_arc.mesh = _lines
	_arc.material_override = _material
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 64
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_arc.top_level = true
	_ring.top_level = true
	hide()

func show_path(points: Array[Vector3], landed: bool, radius: float, ready: bool) -> void:
	var color := Color(1.0, 0.82, 0.25, 0.9) if ready else Color(1.0, 0.55, 0.15, 0.55)
	if not landed: color = Color(1.0, 0.25, 0.2, 0.6)
	_material.albedo_color = color
	_ring_material.albedo_color = Color(color, color.a * 0.8)
	_lines.clear_surfaces()
	if points.size() >= 2:
		_lines.surface_begin(Mesh.PRIMITIVE_LINES)
		# Dashed arc: every other segment, so it reads as a trajectory guide.
		for index: int in range(0, points.size() - 1, 2):
			_lines.surface_add_vertex(points[index])
			_lines.surface_add_vertex(points[index + 1])
		_lines.surface_end()
	_arc.global_transform = Transform3D.IDENTITY
	var at: Vector3 = points.back() if not points.is_empty() else Vector3.ZERO
	_ring.visible = landed
	_ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(radius, 1.0, radius)), at + Vector3.UP * 0.15)
	show()
