extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var path := "user://graphics-test-%d.cfg" % OS.get_process_id()
	var old := ConfigFile.new()
	old.set_value("video","version",1)
	old.set_value("video","mode","borderless")
	old.set_value("video","resolution",Vector2i(1920,1080))
	old.set_value("video","vsync",false)
	old.save(path)
	var migrated := VideoPreferences.load_file(path)
	check(migrated.load_error == OK and migrated.mode == "borderless" and not migrated.vsync,"v1 migration preserves display choices")
	check(migrated.graphics.aa == "taa_msaa" and migrated.graphics.anisotropy == 4,"v1 migration upgrades smoothing defaults")
	for preset: int in 4:
		migrated.graphics = GraphicsOptions.preset(preset)
		check(migrated.save_file(path) == OK,"Preset saves atomically")
		check(VideoPreferences.load_file(path).graphics == migrated.graphics,"Every preset round trips")
	var detached := migrated.copy()
	detached.graphics.brightness = 85
	check(migrated.graphics.brightness == 100,"Draft copy does not mutate original graphics")
	for invalid: Dictionary in [{"aa":"dlss"},{"render_scale":999},{"brightness":NAN},{"fps_limit":-1},{"bloom":1},{"particles":99}]:
		var broken := migrated.copy()
		broken.graphics.merge(invalid,true)
		check(not broken.valid() and broken.save_file(path) != OK,"Reject malformed values before persistence: "+str(invalid))
	check(VideoPreferences.load_file(path).graphics == migrated.graphics,"Failed save preserves previous file")
	var applied: Array[Dictionary] = []
	var panel := VideoSettingsPanel.new()
	root.add_child(panel)
	panel.capture_display = func() -> VideoPreferences: return migrated.copy()
	panel.capture_state = func() -> Dictionary: return {}
	panel.apply_display = func(_draft: VideoPreferences) -> Error: return OK
	panel.graphics_apply = func(draft: Dictionary) -> void: applied.append(draft.duplicate(true))
	panel.open_for(migrated,path)
	panel.graphics_controls.upscaler.select(2)
	panel.graphics_controls.upscaler.item_selected.emit(2)
	check(panel.graphics_controls.aa.disabled,"FSR2 disables competing AA control")
	check(panel.graphics_controls.render_scale.max_value == 100,"Upscaling prevents accidental supersampling")
	panel.graphics_controls.upscaler.select(0)
	panel.graphics_controls.upscaler.item_selected.emit(0)
	check(not panel.graphics_controls.aa.disabled and panel.graphics_controls.render_scale.max_value == 150,"Native restores AA and supersampling controls")
	panel.graphics_controls.brightness.value = 112
	panel.mode_choice.select(0)
	panel.preview_changes()
	check(applied.back().brightness == 112 and panel.deadline_ms > 0,"Display preview also applies graphics draft")
	panel.cancel()
	check(applied.back() == migrated.graphics,"Cancel restores complete graphics state")
	panel.open_for(migrated,"user://missing-graphics-directory/video.cfg")
	panel.graphics_controls.contrast.value = 107
	panel.preview_changes()
	check(panel.visible and applied.back() == migrated.graphics,"Quality-only save failure restores renderer and remains open")
	panel.cancel()
	panel.open_for(migrated,path)
	panel.graphics_controls.brightness.value = 111
	panel.preview_changes()
	check(not panel.visible and panel.deadline_ms == 0,"Quality-only Apply commits without a display timer")
	check(VideoPreferences.load_file(path).graphics.brightness == 111,"UI graphics draft persists")
	panel.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("GRAPHICS PREFERENCES PASS" if failures == 0 else "GRAPHICS PREFERENCES FAIL")
	quit(0 if failures == 0 else 1)
