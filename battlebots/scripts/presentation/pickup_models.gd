class_name PickupModels
extends RefCounted
## Real art for pickup markers. Bodies show the whole painted machine; weapons,
## drives and the auxiliary minigun show only that module, cut from a Sawblade
## assembled with the part fitted, so paint and materials match the game.
## Parts with no dedicated mesh (armour grades, other utilities) and perks
## return null and keep the marker's plain token. Presentation only.
const FIT := 3.2
const BODIES := ["balanced", "scorpion_hex", "atlas_mx"]

static func has_model(part: String, registry: ContentRegistry) -> bool:
	if not registry.parts.has(part):
		return false
	var slot: String = registry.parts[part].category
	return slot in ["chassis", "weapon", "drive"] or part == "minigun_pod"

## Returns a model centred on its origin and scaled to fit FIT metres, or null.
## `holder` must be inside the scene tree: bounds use global transforms.
static func build(part: String, registry: ContentRegistry, holder: Node3D) -> Node3D:
	if not has_model(part, registry):
		return null
	var slot: String = registry.parts[part].category
	var size := _size(registry)
	var root := Node3D.new()
	root.name = "Model"
	holder.add_child(root)
	var art: Node3D
	if slot == "chassis":
		art = _body(part, registry, size)
		root.add_child(art)
		art.assemble(_body_draft(part, registry), _body_size(part, registry))
	elif part == "minigun_pod" or part == "minigun":
		art = MvpWeaponVisual.new()
		root.add_child(art)
		art.assemble("minigun", size)
	else:
		var draft := SawbladeConfig.starter(registry)
		draft.parts[slot] = part
		var sawblade := SawbladeVisual.new()
		root.add_child(sawblade)
		sawblade.assemble(draft, size)
		art = sawblade
		_isolate(sawblade, _module(sawblade, slot, part))
	_fit(root, holder)
	return root

static func _size(registry: ContentRegistry) -> Vector3:
	var chassis: Dictionary = registry.parts.balanced
	return Vector3(chassis.size[0], chassis.size[1], chassis.size[2])

static func _body_size(part: String, registry: ContentRegistry) -> Vector3:
	var chassis: Dictionary = registry.parts[part]
	return Vector3(chassis.size[0], chassis.size[1], chassis.size[2])

static func _body(part: String, _registry: ContentRegistry, _size: Vector3) -> Node3D:
	if part == "atlas_mx":
		return AtlasVisual.new()
	if part == "scorpion_hex":
		return ScorpionVisual.new()
	return SawbladeVisual.new()

static func _body_draft(part: String, registry: ContentRegistry) -> Dictionary:
	if part == "atlas_mx":
		return registry.atlas()
	if part == "scorpion_hex":
		return registry.scorpion()
	return SawbladeConfig.starter(registry)

## The subtree that represents one fitted part on an assembled Sawblade.
static func _module(sawblade: SawbladeVisual, slot: String, part: String) -> Node3D:
	if slot == "weapon":
		if sawblade.fallback_weapon != null:
			return sawblade.fallback_weapon
		return sawblade.nodes.get("Module_weapon_" + str(SawbladeConfig.WEAPONS.get(part, "")))
	if part == "walker":
		return sawblade.walker_legs
	return sawblade.nodes.get("Module_drive_tracks" if part == "traction" else "Module_drive_wheels")

## Hide every mesh that is not part of `keep`. Without a module, keep the whole
## assembly rather than showing nothing.
static func _isolate(art: Node3D, keep: Node3D) -> void:
	if keep == null:
		return
	for node: Node in art.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.visible = geometry == keep or keep.is_ancestor_of(geometry)
		if geometry.visible:
			# Ancestors hidden above the module would hide it too.
			var parent := geometry.get_parent()
			while parent != null and parent != art:
				if parent is Node3D and not parent.visible and not (parent is GeometryInstance3D):
					parent.visible = true
				parent = parent.get_parent()

static func _fit(root: Node3D, holder: Node3D) -> void:
	var bounds := AABB()
	var found := false
	var to_holder := holder.global_transform.affine_inverse()
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree() or not (visual is GeometryInstance3D):
			continue
		var box := to_holder * visual.global_transform * visual.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	if not found or bounds.size.length() < 0.001:
		return
	var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var factor := FIT / largest
	root.scale = Vector3.ONE * factor
	root.position = -bounds.get_center() * factor
