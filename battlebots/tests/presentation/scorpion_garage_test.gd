extends Node
## Exercise the real profile, garage selection and preview using isolated save files.
var failures: Array[String] = []
var profile: Node

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func frames(count := 4) -> void:
	for _frame: int in count: await get_tree().process_frame

func category(slot: String) -> Dictionary:
	for item: Dictionary in profile.catalogue.parts:
		if item.slot == slot: return item
	return {}

func equip_part(slot: String, id: String) -> void:
	var cat := category(slot)
	for item: Dictionary in cat.items:
		if item.id == id:
			profile.equip("parts", cat, item)
			return
	check(false, "Catalogue offers " + id)

func check_preview(preview: GarageBotPreview, hammer: bool, gun: bool) -> void:
	check(preview.scorpion_visual != null, "Garage renders the authored Scorpion scene")
	if preview.scorpion_visual == null: return
	var visual := preview.scorpion_visual
	check(visual.walker_legs.legs.size() == 6, "Preview contains six articulated legs")
	for leg: Dictionary in visual.walker_legs.legs:
		for key: String in ["upper", "lower", "foot_mesh"]:
			check(not leg[key].find_children("*", "MeshInstance3D", true, false).is_empty(), "Each leg segment uses real imported mesh geometry")
	check(not visual.walker_legs.terrain, "Isolated workshop does not raycast into a live arena")
	check(visual.scale.is_equal_approx(Vector3.ONE), "Workshop normalizes the enlarged machine exactly once")
	check(visual.nodes.TailBase.visible == hammer, "Hammer visibility follows the selected primary part")
	check(visual.nodes.GunMount.visible == gun, "Minigun visibility follows primary or auxiliary selection")
	check(preview.model.find_children("*", "CollisionObject3D", true, false).is_empty(), "Preview never instantiates gameplay collision")
	check(visual.nodes.has("ExhaustLeft") and visual.nodes.has("ExhaustRight"), "Preview imports both actual diesel outlet markers")
	for emitter: GPUParticles3D in visual.diesel_exhaust.emitters:
		check(not emitter.emitting, "Workshop and selection previews keep the diesel engine off")

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(name))

func check_default_framing(preview: GarageBotPreview, location: String) -> void:
	var extent := Vector2(preview.viewport.size)
	for mesh: MeshInstance3D in preview.model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		var bounds := mesh.get_aabb()
		for index: int in 8:
			var world_point: Vector3 = mesh.global_transform * bounds.get_endpoint(index)
			var point := preview.camera.unproject_position(world_point)
			check(not preview.camera.is_position_behind(world_point) and point.x >= 0 and point.y >= 0 and point.x <= extent.x and point.y <= extent.y,
				location + " shows the complete default Scorpion including its head and feet: " + str(mesh.name))

func check_featured_menu(scene_path: String, location: String) -> void:
	var screen: Control = load(scene_path).instantiate()
	var session: MvpSession
	if location == "Lobby":
		session = MvpSession.new()
		add_child(session)
		screen.session_override = session
	add_child(screen)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		get_window().size = resolution
		for factor: float in [1.0, 1.5]:
			screen.apply_text_scale(factor)
			await frames(6)
			var preview: GarageBotPreview = screen.featured_vehicle.preview
			preview._rotation_paused = true
			check_preview(preview, true, true)
			for step: int in 16:
				preview._turntable.rotation.y = step * TAU / 16.0
				await frames(1)
				check_default_framing(preview, "%s %s text %.1f" % [location, resolution, factor])
			if resolution == Vector2i(1920, 1080) and is_equal_approx(factor, 1.0):
				preview._turntable.rotation.y = 0.0
				await capture("scorpion-" + location.to_lower() + ".png")
	screen.queue_free()
	if session != null: session.queue_free()
	get_window().size = Vector2i(1920, 1080)
	await frames()

func run() -> void:
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	profile = get_node("/root/PlayerProfile")
	var path := "user://scorpion-garage-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	profile.active_bot = 0
	profile.reload()
	check(profile.PRESET_COUNT == 5 and profile.loadouts.size() == 5, "Fresh garage retains previous presets and adds Atlas MX")
	check(profile.active_bot == 0, "Adding Scorpion preserves the existing initial selection")
	var original_presets: Array = profile.loadouts.slice(0, 3).duplicate(true)
	check(profile.loadouts[3].parts.chassis == "scorpion_hex" and profile.bots[3].valid, "Fourth Scorpion preset is usable")
	var body_choices: Array = []
	for item: Dictionary in category("chassis").items: body_choices.append(item.id)
	check(body_choices == ["balanced", "scorpion_hex", "atlas_mx"], "Garage retains existing body choices and adds Atlas MX")
	var garage: Control = load("res://ui/menus/screens/garage.tscn").instantiate()
	add_child(garage)
	await frames()
	var scorpion_row: Button = garage.get_node("%BotList").get_child(3)
	for _page: int in 4:
		if scorpion_row.visible: break
		garage._page_builds(1)
		await frames(2)
	check(scorpion_row.visible and not scorpion_row.disabled, "Scorpion row is reachable and selectable")
	scorpion_row.button_pressed = true
	scorpion_row.pressed.emit()
	await frames()
	check(profile.active_bot == 3, "Selecting the fourth garage row selects Scorpion")
	check_preview(garage.build_preview, true, true)
	check_default_framing(garage.build_preview, "Garage")
	check(garage.get_node("%AbilitySlot").get_node("Pad/Row/Key/L").text == InputPreferences.load_file().label_for(&"secondary"), "Garage auxiliary gun shows the actual secondary binding")
	await capture("scorpion-garage.png")
	garage.queue_free()
	await frames(1)
	var featured := FeaturedVehicle.new()
	featured.size = Vector2(560, 620)
	featured.render([profile.registry.scorpion()], 0)
	add_child(featured)
	await frames(10)
	featured.preview._rotation_paused = true
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		featured.preview._turntable.rotation.y = angle
		await frames(1)
		check_default_framing(featured.preview, "Vehicle selection")
	featured.queue_free()
	await frames(1)
	await check_featured_menu("res://ui/menus/screens/main_menu.tscn", "Main")
	await check_featured_menu("res://ui/menus/screens/lobby.tscn", "Lobby")
	var customize: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	add_child(customize)
	await frames()
	var original_scorpion: Dictionary = profile.loadouts[3].duplicate(true)
	check_default_framing(customize.build_preview, "Customize")
	equip_part("utility", "cooling_pack")
	check(profile.loadouts[3].parts.weapon == "hammer", "Removing auxiliary gun preserves primary hammer")
	check_preview(customize.build_preview, true, false)
	equip_part("weapon", "minigun")
	check(profile.loadouts[3].parts.utility == "cooling_pack", "Primary gun swap preserves selected utility")
	check_preview(customize.build_preview, false, true)
	equip_part("weapon", "saw")
	check_preview(customize.build_preview, false, false)
	check(customize.build_preview.scorpion_visual.fallback_weapon != null, "Another primary module attaches to the same body")
	equip_part("utility", "minigun_pod")
	check(profile.loadouts[3].parts.weapon == "saw", "Adding auxiliary gun preserves replacement primary")
	check_preview(customize.build_preview, false, true)
	equip_part("weapon", "hammer")
	check(profile.loadouts[3] == original_scorpion, "Independent module changes restore the exact original Scorpion draft")
	check_preview(customize.build_preview, true, true)
	# The body selector must preserve parts even when the resulting combination
	# needs repair. It must never silently replace a gun, drive, or appearance.
	var before_body: Dictionary = profile.loadouts[3].duplicate(true)
	equip_part("chassis", "balanced")
	var expected_body := before_body.duplicate(true)
	expected_body.parts.chassis = "balanced"
	check(profile.loadouts[3] == expected_body, "Changing body preserves both modules and appearance")
	check(not profile.bots[3].valid and customize.get_node("%Save").disabled, "Incompatible auxiliary socket is reported and cannot save")
	profile.undo_edit()
	check(profile.loadouts[3] == before_body and profile.bots[3].valid, "Undo restores the full valid Scorpion without substitutions")
	var detached: Dictionary = profile.active_loadout()
	customize.build_preview.show_loadout(detached)
	detached.parts.weapon = "minigun"
	detached.cosmetics.sawblade.paint_primary[0] = 0.0
	check(profile.loadouts[3] == before_body, "Editing a detached active draft cannot mutate the profile")
	check(customize.build_preview._draft == before_body, "Preview owns a detached nested draft")
	check(profile.loadouts.slice(0, 3) == original_presets, "Scorpion edits never change the three existing preset drafts")
	check(profile.save_active("Scorpion Saved") == OK, "Complete two-module Scorpion saves")
	# JSON stores every number as float; compare all fields after the same
	# serialization boundary rather than requiring in-memory integer variants.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(profile.loadouts[3]))
	await frames()
	await capture("scorpion-customize.png")
	customize.queue_free()
	await frames(1)
	profile.reload()
	check(profile.loadouts.size() == profile.PRESET_COUNT + 1, "Saved Scorpion appears after the built-in presets")
	check(profile.loadouts[profile.PRESET_COUNT] == saved, "Save and reload preserve Scorpion modules and appearance exactly")
	var store := LoadoutStore.new(path)
	var legacy := SawbladeConfig.starter(profile.registry)
	legacy.name = "Revision seven retained"
	legacy.content_hash = LoadoutStore.REVISION_SEVEN_HASHES[0]
	legacy.cosmetics.sawblade.exhaust = 3
	var envelope := {"schema_version":1, "loadouts":[saved.duplicate(true), legacy]}
	var unchanged := envelope.duplicate(true)
	var migrated := store.migrate(envelope)
	check(envelope == unchanged, "Migration leaves its source dictionaries unchanged")
	check(migrated.loadouts[0] == saved, "Current Scorpion is unchanged by revision-seven migration")
	var upgraded: Dictionary = legacy.duplicate(true)
	upgraded.content_hash = profile.registry.content_hash
	check(migrated.loadouts[1] == upgraded and profile.registry.validate(upgraded).valid, "Revision-seven migration preserves every legacy selection while updating content identity")
	var unknown := legacy.duplicate(true)
	unknown.content_hash = "not-a-known-release"
	var rejected := store.migrate({"schema_version":1, "loadouts":[unknown]})
	check(rejected.loadouts[0] == unknown and not profile.registry.validate(rejected.loadouts[0]).valid, "Unknown catalogue hashes remain rejected")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	var before_reload := FileAccess.get_file_as_string(path)
	profile.reload()
	check(profile.loadouts.size() == profile.PRESET_COUNT + 2, "Current and old saved builds both survive garage reload")
	check(profile.loadouts[profile.PRESET_COUNT] == saved, "Legacy migration never changes saved Scorpion")
	check(profile.loadouts[profile.PRESET_COUNT + 1] == JSON.parse_string(JSON.stringify(upgraded)), "Profile exposes the migrated revision-seven build")
	check(FileAccess.get_file_as_string(path) == before_reload, "Read-only migration does not rewrite saved bytes")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	if failures.is_empty(): print("SCORPION GARAGE PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
