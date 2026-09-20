extends Node3D
## Independent public BotView acceptance for fixed-size world health bars.
const GREEN := Color("35d05b")
const RED := Color("df3945")
var failures: Array[String] = []
func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func view(id: int, side: int, at: Vector3) -> BotView:
	var result := BotView.new()
	result.entity_id = id
	result.team = side
	result.pose.origin = at
	return result
func check_pixels(bar: Sprite3D, green_width: int, updated := false) -> void:
	# Dummy rendering retains the initial ImageTexture readback after update().
	# Initial images are checked on every driver; native checks also cover updates.
	if updated and DisplayServer.get_name() == "headless": return
	var image := bar.texture.get_image()
	check(image.get_size() == Vector2i(128,12),"Health texture remains128x12")
	var border_ok := true
	var fill_ok := true
	for y in 12:
		for x in 128:
			var pixel := image.get_pixel(x,y)
			if x < 2 or x >= 126 or y < 2 or y >= 10:
				border_ok = border_ok and pixel.r < 0.1 and pixel.g < 0.1 and pixel.b < 0.1 and pixel.a > 0.99
			else:
				var expected := GREEN if x < 2 + green_width else RED
				fill_ok = fill_ok and pixel.is_equal_approx(expected)
	check(border_ok,"Health bar has a continuous two-pixel dark border")
	check(fill_ok,"Current health fills green from left; missing health stays red")
func run() -> void:
	for fraction: float in [1.0,0.5,0.0]:
		var fresh := BotWorldMarkers.new()
		add_child(fresh)
		var initial := view(99,0,Vector3.ZERO)
		initial.core_fraction = fraction
		fresh.render([initial],99,false,true)
		check_pixels(fresh.markers[99].get_node("HealthBar"),roundi(fraction * 124))
		fresh.free()
	var markers := BotWorldMarkers.new()
	add_child(markers)
	var local := view(7,0,Vector3(-1,0.5,0))
	var rival := view(21,1,Vector3(1,0.5,0))
	var views: Array[BotView] = [local,rival]
	markers.render(views,7,false,true)
	await get_tree().process_frame
	var label: Label3D = markers.markers[7]
	var bar := label.get_node("HealthBar") as Sprite3D
	var rival_bar := markers.markers[21].get_node("HealthBar") as Sprite3D
	check(bar != null and rival_bar != null,"Every player name has a health bar")
	check(bar.fixed_size and is_equal_approx(bar.pixel_size,0.001),"Bar uses fixed screen size")
	check(not bar.no_depth_test and not bar.shaded and bar.billboard == BaseMaterial3D.BILLBOARD_ENABLED,"Bar faces camera, stays unshaded, respects arena occlusion")
	var original_size := bar.get_aabb().size
	var original_texture := bar.texture
	check_pixels(bar,124)
	markers.render(views,7,false,true)
	await get_tree().process_frame
	check(bar.texture == original_texture,"Unchanged health reuses its texture resource")
	local.core_fraction = 0.5
	markers.render(views,7,false,true)
	await get_tree().process_frame
	check_pixels(bar,62,true)
	check_pixels(rival_bar,124)
	check(bar.texture != rival_bar.texture,"Players own isolated health textures")
	check(bar.get_aabb().size.is_equal_approx(original_size),"Half health does not shrink the bar")
	var half_image := bar.texture.get_image().get_data()
	local.core_fraction = 0.0
	check(bar.texture.get_image().get_data() == half_image,"Changing a detached snapshot waits for render")
	markers.render(views,7,false,true)
	await get_tree().process_frame
	check_pixels(bar,0,true)
	check(bar.visible and bar.get_aabb().size.is_equal_approx(original_size),"Zero health retains full-size red bar")
	for invalid: float in [NAN,INF,-0.1,1.1]:
		local.core_fraction = invalid
		markers.render(views,7,false,true)
		await get_tree().process_frame
		check(not bar.visible,"Invalid health hides stale bar: " + str(invalid))
	local.core_fraction = 0.5
	markers.render(views,7,false,true)
	await get_tree().process_frame
	check(bar.visible,"Valid health restores hidden bar")
	check_pixels(bar,62,true)
	for factor: float in [1.0,1.25,1.5,1.0]:
		markers.apply_accessibility(factor,"deuteranopia",true)
		check(bar.fixed_size and is_equal_approx(bar.pixel_size,0.001),"Accessibility preserves requested fixed bar size")
		check(bar.get_aabb().size.is_equal_approx(original_size),"Accessibility does not stretch bar geometry")
		check(bar.offset.y + 6.0 <= -float(label.font_size) * 0.5,"Bar sits below player name at every text scale")
		check_pixels(bar,62,true)
	markers.transform = Transform3D(Basis.from_euler(Vector3(0.2,0.5,0.3)).scaled(Vector3(2,1.5,0.8)),Vector3(8,3,-2))
	markers.render(views,7,false,true)
	await get_tree().process_frame
	check(label.global_basis.is_equal_approx(Basis.IDENTITY),"Marker resets inherited scale and rotation")
	check(bar.scale.is_equal_approx(Vector3.ONE),"Health fraction never changes sprite scale")
	markers.transform = Transform3D.IDENTITY
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless": await capture(markers,views)
	markers.render([local],7,false,true)
	check(not is_instance_valid(rival_bar),"Removed player frees its health sprite")
	markers.render([],7,false,true)
	check(markers.markers.is_empty() and not is_instance_valid(bar),"Missing baseline clears all health bars")
	markers.free()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("PLAYER HEALTH BARS PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

func capture(markers: BotWorldMarkers, views: Array[BotView]) -> void:
	get_window().size = Vector2i(1280,720)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("27323e")
	add_child(environment)
	for distance: float in [6.0,18.0]:
		camera.position = Vector3(0,3,distance)
		camera.look_at(Vector3(0,1,0))
		for factor: float in [1.0,1.5]:
			markers.apply_accessibility(factor,"standard",false)
			markers.render(views,7,false,true)
			await get_tree().process_frame
			for frame in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("player-health-bars-%dm-%d.png" % [distance,roundi(factor * 100)]))
	camera.free()
	environment.free()


