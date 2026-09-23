extends SceneTree
const HudScript := preload("res://scripts/ui/practice_hud.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var hud := HudScript.new()
	hud.hide()
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hud.offset_left = -334
	hud.offset_right = -24
	hud.offset_top = 174
	hud.offset_bottom = 394
	hud.hide()
	await frames()
	var local := BotView.new()
	var target := BotView.new()
	target.core_fraction = 0.634
	target.zones = {"front":0.0, "rear":60.0, "left":60.0, "right":60.0, "drive_left":100.0, "drive_right":100.0, "weapon":140.0}
	var original := target.zones.duplicate(true)
	hud.show()
	hud.render(local, target)
	await frames()
	check_bounds(hud)
	check(hud.target_label.text == "Core: 63%" and hud.components_label.text == "Disabled: none", "Target core uses detached fraction; armor plates are not disabled components")
	check(not hud.local_status.visible and not hud.hint_label.text.is_empty(), "No duplicated local health; restart hint remains available")
	check(target.zones == original and target.core_fraction == 0.634 and not local.eliminated, "Render does not modify either BotView")
	target.zones.drive_left = 0
	target.zones.drive_right = 0.0
	target.zones.weapon = 0
	target.core_fraction = 0.0
	target.eliminated = true
	local.eliminated = true
	original = target.zones.duplicate(true)
	hud.render(local, target)
	check(hud.target_label.text.contains("0%") and hud.target_label.text.contains("TARGET DEFEATED"), "Authoritative target knockout remains explicit")
	check(hud.local_status.visible and hud.local_status.text == "Your bot is knocked out", "Local knockout provides restart context without health duplication")
	check(hud.components_label.text == "Disabled: Left drive, Right drive, Weapon", "Real zone IDs use readable disabled component names")
	check(target.zones == original and target.eliminated and local.eliminated, "KO rendering does not repair either bot")
	await frames()
	check_bounds(hud)
	for invalid: float in [NAN, INF, -0.1, 1.1]:
		target.core_fraction = invalid
		target.eliminated = false
		hud.render(local, target)
		check(hud.target_label.text == "Core unavailable", "Invalid target health does not display a fabricated percentage")
	target.core_fraction = 0
	hud.render(local, target)
	check(not hud.target_label.text.contains("DEFEATED"), "HUD does not infer authoritative elimination from core alone")
	for invalid: Variant in [NAN, INF, -1.0, "0", false, null]:
		target.zones = {"drive_left":0.0, "drive_right":invalid, "weapon":140.0}
		hud.render(local, target)
		check(hud.components_label.text == "Disabled: Left drive\nOther components unavailable", "Invalid zone data is distinct from disabled or healthy")
	await frames()
	check_bounds(hud)
	target.zones = {}
	hud.render(local, target)
	check(hud.components_label.text == "Components unavailable", "Missing zones do not claim components are healthy")
	hud.render(null, null)
	check(hud.target_label.text == "Target unavailable" and hud.local_status.text == "Your bot unavailable" and hud.components_label.text == "Components unavailable", "Missing views clear all stale target and player status")
	await frames()
	check_bounds(hud)
	for control: Node in hud.find_children("*", "Control", true, false):
		check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Practice display never captures pointer input")
	check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Practice panel passes mouse input through")
	layer.queue_free()
	await frames()
	print("PRACTICE HUD PASS" if failures == 0 else "PRACTICE HUD FAIL")
	quit(0 if failures == 0 else 1)

func check_bounds(hud: PanelContainer) -> void:
	check(hud.size.x <= 310 and hud.size.y <= 220, "Practice HUD stays within 310×220 at 1280×720")
	# canvas_items stretch from a 1920×1080 base: controls live in the visible rect, not window pixels.
	check(root.get_visible_rect().encloses(hud.get_global_rect()), "Right-side practice panel fits viewport")
	for label: Label in [hud.target_label, hud.components_label, hud.local_status, hud.hint_label]:
		if label.visible:
			check(hud.get_global_rect().encloses(label.get_global_rect()), "Practice text stays inside the panel")
