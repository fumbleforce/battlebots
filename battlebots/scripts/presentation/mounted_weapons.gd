extends Node3D
## Weapons a body other than the Atlas MX carries on its data/weapon_mounts.json
## mounts (#108): the roof turret, a front tool (ram, spear/forklift, grinder)
## and the auxiliary gun. The models are the Atlas ones, placed and scaled by
## the same mount frames the authority uses. This node sits in the hull frame
## (game metres, origin at the hull centre) beside the body's own visual.
## Presentation only: no collision, damage or weapon state lives here.
const WEAPON_MOUNTS = preload("res://scripts/core/weapon_mounts.gd")
const TURRET_MODULE = preload("res://scripts/presentation/turret_module_visual.gd")
const ATLAS_TOOL_VISUAL = preload("res://scripts/presentation/atlas_tool_visual.gd")
const TURRET := "res://assets/models/atlas_runtime/atlas_turret.glb"
## Underside of the turret's base ring and the pedestal radius under it (turret
## source metres); the pedestal widens by RISER_FLARE toward the deck.
const RING_BASE_Y := 0.48
const RISER_RADIUS := 0.5
const RISER_FLARE := 1.08
## Back plate of every front tool, and the coupler rails' section, spacing and
## height (tool source metres; the Atlas rails in AtlasVisual match).
const TOOL_BACK_Z := -1.34
const COUPLER_RAIL := Vector2(0.11, 0.12)
const COUPLER_RAIL_X := 0.25
const COUPLER_RAIL_Y := -0.02
var turret: TURRET_MODULE
var tool: ATLAS_TOOL_VISUAL
## Auxiliary minigun on bodies without an authored gun mount of their own.
var gun: MvpWeaponVisual

## True when the draft mounts something here.
static func wanted(draft: Dictionary) -> bool:
	if WEAPON_MOUNTS.body(draft).is_empty(): return false
	return not AtlasGeometry.turret_model(draft).is_empty() or not AtlasGeometry.tool_kind(draft).is_empty() \
		or _has_gun(draft)

## The Scorpion shows its own authored gun; other bodies borrow the shared mount.
static func _has_gun(draft: Dictionary) -> bool:
	return draft.parts.utility == "minigun_pod" and WEAPON_MOUNTS.body(draft) != "scorpion"

func assemble(draft: Dictionary, size: Vector3) -> void:
	var linear := BotScale.from_size(size)
	var model := AtlasGeometry.turret_model(draft)
	if not model.is_empty() and ResourceLoader.exists(TURRET):
		var frame := WEAPON_MOUNTS.turret(draft, size)
		turret = TURRET_MODULE.new()
		turret.name = "TurretModule"
		add_child(turret)
		turret.transform = frame * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * linear), Vector3.ZERO)
		turret.assemble(TURRET, AtlasGeometry.family(model), model, linear * WEAPON_MOUNTS.scale_of(frame))
		_assemble_riser(WEAPON_MOUNTS.turret_riser(draft))
	var tool_kind := AtlasGeometry.tool_kind(draft)
	if not tool_kind.is_empty() and ResourceLoader.exists(ATLAS_TOOL_VISUAL.MODEL):
		var frame := WEAPON_MOUNTS.tool(draft, size)
		tool = ATLAS_TOOL_VISUAL.new()
		tool.name = "FrontTool"
		add_child(tool)
		tool.transform = frame * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * linear), Vector3.ZERO)
		tool.assemble(tool_kind)
		_assemble_coupler(WEAPON_MOUNTS.tool_coupler(draft))
	if _has_gun(draft):
		gun = MvpWeaponVisual.new()
		gun.name = "AuxiliaryModule"
		add_child(gun)
		gun.position = AtlasGeometry.gun_offset(draft, size)
		gun.assemble("minigun", size)
	_paint(draft)

## A steel pedestal from the deck up to the turret ring, in the turret's frame.
func _assemble_riser(height: float) -> void:
	if height <= 0.0: return
	var column := CylinderMesh.new()
	column.top_radius = RISER_RADIUS
	column.bottom_radius = RISER_RADIUS * RISER_FLARE
	column.height = height
	column.radial_segments = 32
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("394754")
	steel.metallic = 0.8
	steel.roughness = 0.32
	column.material = steel
	var riser := MeshInstance3D.new()
	riser.name = "TurretRiser"
	riser.mesh = column
	riser.position = Vector3(AtlasGeometry.TURRET_YAW_PIVOT.x, RING_BASE_Y - height * 0.5, AtlasGeometry.TURRET_YAW_PIVOT.z)
	turret.add_child(riser)

## Two steel rails from the tool's back plate back into the body, in the tool's
## frame (the Atlas joins its own coupler the same way).
func _assemble_coupler(length: float) -> void:
	if length <= 0.0: return
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("394754")
	steel.metallic = 0.8
	steel.roughness = 0.32
	for side: int in [-1, 1]:
		var bar := BoxMesh.new()
		bar.size = Vector3(COUPLER_RAIL.x, COUPLER_RAIL.y, length)
		bar.material = steel
		var rail := MeshInstance3D.new()
		rail.name = "ToolCouplerRailLeft" if side < 0 else "ToolCouplerRailRight"
		rail.mesh = bar
		rail.position = Vector3(side * COUPLER_RAIL_X, COUPLER_RAIL_Y, TOOL_BACK_Z + length * 0.5)
		tool.add_child(rail)

## The modules take the body's paint layers where it has them; a body still on
## the Sawblade factory finish keeps the modules' own baked enamel on the
## Scorpion (its ceramic is orange too) and is painted to match on the Sawblade.
func _paint(draft: Dictionary) -> void:
	if not SawbladeConfig.enabled(draft): return
	var config: Dictionary = draft.cosmetics.sawblade.duplicate(true)
	var factory := AtlasGeometry.paint_defaults()
	if WEAPON_MOUNTS.body(draft) == "scorpion":
		var untouched := SawbladeConfig.defaults()
		for channel: String in SawbladeConfig.COLORS:
			if config.get(channel) == untouched[channel]: config[channel] = factory[channel]
	for module: Node3D in [turret, tool]:
		if module != null: AtlasVisual.paint(module, config, factory)

func show_state(view: BotView, delta: float) -> void:
	if turret != null: turret.show_state(view, delta)
	if tool != null: tool.show_state(view, delta)
	if gun != null: gun.gun_effects.show_state(view, delta, false)

func reset_observation() -> void:
	if turret != null: turret.clear_effects()
	if tool != null: tool.clear_effects()
	if gun != null: gun.gun_effects.clear_effects()

## Smoothed turret yaw/pitch for reticles, or the given authoritative angles.
func turret_display(fallback: Vector2) -> Vector2:
	return turret.display if turret != null else fallback

## Meshes that belong to the weapon damage zone.
func weapon_meshes() -> Array:
	var found: Array = []
	for module: Node3D in [turret.yaw_node if turret != null else null, tool, gun]:
		if module != null: _collect(module, found)
	return found

func _collect(node: Node3D, found: Array) -> void:
	if not node.visible: return
	if node is MeshInstance3D: found.append(node)
	for child: Node in node.get_children():
		if child is Node3D: _collect(child, found)
