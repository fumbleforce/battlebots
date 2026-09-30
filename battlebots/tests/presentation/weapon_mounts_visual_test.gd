extends SceneTree
## The drawn turret, front tool and auxiliary gun of a body other than the
## Atlas MX sit on the mounts the authority uses (#108): muzzle markers match
## the server's rays on the Sawblade, the Scorpion and the placeholder box.
const MOUNTED_WEAPONS = preload("res://scripts/presentation/mounted_weapons.gd")
const WEAPON_MOUNTS = preload("res://scripts/core/weapon_mounts.gd")
## Drawn markers must match authoritative geometry within this distance (m).
const TOLERANCE := 0.01
const POSES := [Vector2(0.0, 0.0), Vector2(1.1, 0.2), Vector2(-2.4, -0.1)]
var failures := 0
var registry := ContentRegistry.new()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func build(body: String, weapon := "lifter", utility := "recovery_assist") -> Dictionary:
	var draft := registry.starter()
	match body:
		"sawblade": draft = SawbladeConfig.starter(registry)
		"scorpion": draft = registry.scorpion()
		"atlas": draft = registry.atlas()
	draft.parts.weapon = weapon
	draft.parts.utility = utility
	return draft

func mount(draft: Dictionary) -> Array:
	var stats: Dictionary = registry.validate(draft).stats
	var visual := MOUNTED_WEAPONS.new()
	root.add_child(visual)
	visual.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(4, 2, -3))
	visual.assemble(draft, stats.size)
	return [visual, stats]

func turrets() -> void:
	for body: String in WEAPON_MOUNTS.BODIES:
		for part: String in AtlasGeometry.TURRET_PARTS:
			var model: String = AtlasGeometry.TURRET_PARTS[part]
			var family := AtlasGeometry.family(model)
			var draft := build(body, "lifter", part)
			check(MOUNTED_WEAPONS.wanted(draft), "%s wants its %s drawn" % [body, part])
			var pair := mount(draft)
			var visual: MOUNTED_WEAPONS = pair[0]
			var stats: Dictionary = pair[1]
			check(visual.turret != null and visual.turret.kind == family and visual.turret.model == model,
				"%s assembles the %s turret" % [body, model])
			if visual.turret == null: continue
			var frame: Transform3D = visual.global_transform * (stats.turret_mount as Transform3D)
			var barrels: Array = AtlasGeometry.turret_barrels(model)
			check(visual.turret.effects.muzzles.size() == barrels.size(), "%s effects know every %s muzzle" % [body, model])
			for pose: Vector2 in POSES:
				var view := BotView.new()
				view.turret_yaw = pose.x
				view.gun_pitch = pose.y
				view.server_tick = 1
				visual.turret.clear_effects()
				visual.show_state(view, 0.0)
				check(visual.turret.pitch_node.global_position.distance_to(frame * AtlasGeometry.turret_breech(stats.size, pose.x)) < TOLERANCE,
					"%s %s trunnion is where the server traces from" % [body, model])
				for index: int in barrels.size():
					var marker: Node3D = visual.turret.effects.muzzles[index]
					var expected := frame * AtlasGeometry.turret_muzzle(stats.size, family, pose.x, pose.y, AtlasGeometry.turret_barrel(model, index + 1))
					check(marker != null and marker.global_position.distance_to(expected) < TOLERANCE,
						"%s %s muzzle %d matches the server ray at %s" % [body, model, index, pose])
			check(not visual.weapon_meshes().is_empty(), "%s %s belongs to the weapon damage zone" % [body, model])
			check((visual.turret.get_node_or_null("TurretRiser") != null) == (WEAPON_MOUNTS.turret_riser(draft) > 0.0),
				"%s pedestal follows its mount record" % body)
			visual.free()

func tools_and_gun() -> void:
	for body: String in WEAPON_MOUNTS.BODIES:
		for weapon: String in AtlasGeometry.TOOL_PARTS:
			var pair := mount(build(body, weapon))
			var visual: MOUNTED_WEAPONS = pair[0]
			var stats: Dictionary = pair[1]
			check(visual.tool != null and visual.tool.tool == AtlasGeometry.TOOL_PARTS[weapon], "%s assembles the %s" % [body, weapon])
			if visual.tool == null: continue
			# Atlas tool metres to world: the mount frame at game scale.
			var expected: Transform3D = visual.global_transform * (stats.tool_mount as Transform3D) \
				* Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * BotScale.from_size(stats.size)), Vector3.ZERO)
			check(visual.tool.global_transform.is_equal_approx(expected), "%s %s sits on the server's tool frame" % [body, weapon])
			var rails: int = visual.tool.find_children("ToolCouplerRail*", "MeshInstance3D", false, false).size()
			check(rails == (2 if WEAPON_MOUNTS.tool_coupler(build(body, weapon)) > 0.0 else 0), "%s %s coupler follows its mount record: %d rails" % [body, weapon, rails])
			check(not visual.weapon_meshes().is_empty(), "%s %s belongs to the weapon damage zone" % [body, weapon])
			visual.free()
		var gunner := build(body, "lifter", "minigun_pod")
		check(MOUNTED_WEAPONS.wanted(gunner) == (body != "scorpion"), "%s borrows the shared gun mount only without its own" % body)
		var pair := mount(gunner)
		check((pair[0].gun != null) == (body != "scorpion"), "%s auxiliary gun is drawn once" % body)
		if pair[0].gun != null:
			check(pair[0].gun.gun_effects != null and pair[0].gun.kind == "minigun", "%s auxiliary gun carries its effects" % body)
			check(pair[0].gun.position.is_equal_approx(AtlasGeometry.gun_offset(gunner, pair[1].size)),
				"%s auxiliary gun sits where the server fires from" % body)
		pair[0].free()
	check(not MOUNTED_WEAPONS.wanted(build("sawblade", "saw")), "A build without mounted weapons draws none")
	for draft: Dictionary in [build("atlas", "battering_ram", "turret_cannon"), registry.bracken()]:
		check(not MOUNTED_WEAPONS.wanted(draft), "%s keeps its authored weapons" % draft.name)
	for nimble: Dictionary in registry.nimble():
		check(not MOUNTED_WEAPONS.wanted(nimble), "%s keeps its own weapons" % nimble.name)

## The Ramp off the Sawblade body (#108): the borrowed plate hinges where the
## authority sweeps, reaches as far as its volume and follows the same angles.
func ramp() -> void:
	for body: String in ["atlas", "scorpion", "box"]:
		var draft := build(body, "ramp")
		var stats: Dictionary = registry.validate(draft).stats
		var parent := Node3D.new()
		root.add_child(parent)
		parent.transform = Transform3D(Basis(Vector3.UP, -0.4), Vector3(-6, 1, 2))
		var visual := MvpWeaponVisual.new()
		parent.add_child(visual)
		visual.assemble("ramp", stats.size, draft)
		var hinge: Vector3 = parent.global_transform * SawbladeGeometry.ramp_hinge(draft, stats.size)
		check(visual.mechanism.global_position.distance_to(hinge) < TOLERANCE, "%s Ramp hinges where the server sweeps" % body)
		var volume: Array = SawbladeGeometry.ramp_volume(draft, stats.size, 0.0)
		var front := INF
		var shown := 0
		for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if not mesh.is_visible_in_tree(): continue
			shown += 1
			var box := parent.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			front = minf(front, box.position.z)
		var reach: float = (volume[0] as Transform3D).origin.z - (volume[1] as Vector3).z * 0.5
		check(shown > 0 and absf(front - reach) < 0.1 * BotScale.from_size(stats.size), "%s Ramp lip is the front of the server's plate: %.2f vs %.2f" % [body, front, reach])
		check(front < -stats.size.z * 0.5, "%s carries the Ramp ahead of its nose" % body)
		var view := BotView.new()
		view.weapon_charge_fraction = 1.0
		view.weapon_state = &"active"
		visual.show_state(view, 0.0)
		check(is_equal_approx(visual.mechanism.rotation.x, SawbladeGeometry.RAMP_LOAD_ANGLE), "%s Ramp loads to the server's angle" % body)
		view.weapon_state = &"launch"
		visual.show_state(view, 0.0)
		check(is_equal_approx(visual.mechanism.rotation.x, SawbladeGeometry.RAMP_LAUNCH_ANGLE), "%s Ramp flips to the server's angle" % body)
		parent.free()

func garage() -> void:
	var preview := GarageBotPreview.new()
	preview.size = Vector2(640, 480)
	root.add_child(preview)
	await process_frame
	preview.show_loadout(build("sawblade", "spear_fork", "turret_cannon"))
	check(preview.mounted_weapons != null and preview.mounted_weapons.turret != null and preview.mounted_weapons.tool != null,
		"Garage draws the Sawblade's turret and front tool")
	var handles := 0
	for key: String in preview.sawblade_visual.nodes:
		if key.begins_with("Carry handle"):
			handles += 1
			check(not preview.sawblade_visual.nodes[key].visible, "The turret replaces the pack's %s" % key)
	check(handles > 0, "The Sawblade pack has a carry handle to clear")
	preview.show_loadout(build("sawblade", "saw"))
	check(preview.mounted_weapons == null, "Garage clears mounted weapons with the build")
	for key: String in preview.sawblade_visual.nodes:
		if key.begins_with("Carry handle"): check(preview.sawblade_visual.nodes[key].visible, "Without a turret the pack keeps its %s" % key)
	preview.show_loadout(build("scorpion", "battering_ram", "turret_plasma"))
	check(preview.scorpion_visual != null and preview.mounted_weapons != null and preview.mounted_weapons.turret != null
		and preview.mounted_weapons.tool != null, "Garage draws the Scorpion's turret and front tool")
	preview.show_loadout(build("atlas", "battering_ram", "turret_cannon"))
	check(preview.mounted_weapons == null and preview.atlas_visual.turret != null and preview.atlas_visual.tool != null,
		"The Atlas still draws its own turret and tool")
	preview.show_loadout(build("atlas", "ramp"))
	check(preview.atlas_visual != null and preview.atlas_visual.primary.kind == "ramp", "Garage draws the Ramp on the Atlas")
	preview.show_loadout(build("sawblade", "lifter"))
	check(preview.sawblade_visual != null and preview.sawblade_visual.fallback_weapon != null
		and preview.sawblade_visual.fallback_weapon.kind == "lifter" and not preview.sawblade_visual.nodes.Module_weapon_ramp.visible,
		"Garage draws the Lifter, not the Ramp, on a Sawblade that mounts it")
	preview.show_loadout(build("sawblade", "ramp"))
	check(preview.sawblade_visual.fallback_weapon == null and preview.sawblade_visual.nodes.Module_weapon_ramp.visible,
		"The Sawblade body keeps its built-in Ramp")
	preview.queue_free()
	await process_frame

func run() -> void:
	registry.enforce_budget = false
	await process_frame
	turrets()
	tools_and_gun()
	ramp()
	await garage()
	print("WEAPON MOUNTS VISUAL PASS" if failures == 0 else "WEAPON MOUNTS VISUAL FAIL")
	quit(mini(failures, 1))
