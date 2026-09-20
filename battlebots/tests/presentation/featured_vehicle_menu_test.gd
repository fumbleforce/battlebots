extends Node
var failures := 0
var surface: Control
func check(ok: bool, message: String) -> void:
 if not ok:
  failures += 1
  push_error(message)
func frames() -> void:
 for frame: int in 8: await get_tree().process_frame
func _ready() -> void:
 Engine.max_fps = 60
 call_deferred("run")
func run() -> void:
 surface = Control.new()
 add_child(surface)
 get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
 get_window().size = Vector2i(1920,1080)
 surface.size = Vector2(1920,1080)
 var original: Array = PlayerProfile.loadouts.duplicate(true)
 var original_active := PlayerProfile.active_bot
 var first := PlayerProfile.registry.starter()
 var painted := first.duplicate(true)
 painted.cosmetics.paint = "red"
 PlayerProfile.loadouts = [first, painted]
 PlayerProfile.active_bot = 0
 var main: Control = load("res://ui/menus/screens/main_menu.tscn").instantiate()
 surface.add_child(main)
 main.featured_vehicle.next_button.pressed.emit()
 check(PlayerProfile.active_bot == 1, "Main showcase selects active profile build")
 check(main.featured_vehicle.preview._draft == painted, "Main preview receives selected canonical draft")
 PlayerProfile.loadouts[1].name = "Renamed vehicle"
 PlayerProfile.inventory_changed.emit()
 check(main.featured_vehicle.name_label.text == "Renamed vehicle", "Main reacts to edited profile")
 PlayerProfile.loadouts[1].name = "W".repeat(48)
 PlayerProfile.inventory_changed.emit()
 await layout(main, "main")
 PlayerProfile.loadouts[1] = painted
 main.queue_free()
 await frames()
 var session := MvpSession.new()
 add_child(session)
 var lobby: Control = load("res://ui/menus/screens/lobby.tscn").instantiate()
 lobby.session_override = session
 surface.add_child(lobby)
 PlayerProfile.active_bot = 0
 lobby.refresh()
 await layout(lobby, "lobby-offline")
 lobby.host_button.pressed.emit()
 check(session.connection_state == "hosting", "Lobby fixture uses real host authority")
 await layout(lobby, "lobby")
 var published_arena: String = session.lobby_view.get("arena", "foundry")
 session.lobby_view.arena = "moon"
 lobby.refresh()
 check(lobby.get_node("%Eyebrow").text.contains("LUNAR OUTPOST") and lobby.get_node("%Eyebrow").text.contains("LUNAR GRAVITY"), "Published Moon identity remains visible beside vehicle showcase")
 check(lobby.get_node("Layout/Body/Row/Match/Rules/Hazards/Col/Value").text == "Uneven", "Moon terrain rule remains visible")
 await layout(lobby, "lobby-moon")
 session.lobby_view.arena = published_arena
 lobby.refresh()
 PlayerProfile.loadouts[0].name = "W".repeat(48)
 PlayerProfile.inventory_changed.emit()
 await layout(lobby, "lobby-long")
 PlayerProfile.loadouts[0].name = "Striker"
 PlayerProfile.loadouts.append({"name":"W".repeat(48)})
 lobby._select_vehicle(2, {})
 await layout(lobby, "lobby-invalid")
 check(lobby.featured_vehicle.preview.model == null, "Invalid selection has no fabricated model")
 lobby.request_build()
 check(lobby._pending.is_empty(), "Invalid selection cannot submit a build")
 lobby._select_vehicle(0, {})
 PlayerProfile.loadouts.pop_back()
 lobby.refresh()
 var before: Dictionary = lobby._local_slot().loadout.duplicate(true)
 lobby.featured_vehicle.next_button.pressed.emit()
 check(PlayerProfile.active_bot == 1, "Lobby selection changes local draft")
 check(lobby._local_slot().loadout == before, "Selection does not optimistically change accepted build")
 lobby._begin("loadout", painted)
 lobby._lobby_changed(session.lobby_view)
 check(lobby._pending == "loadout", "Old paint cannot acknowledge paint-only request")
 var selected_before := PlayerProfile.active_bot
 lobby.featured_vehicle.selection_requested.emit(0, first)
 check(PlayerProfile.active_bot == selected_before, "Pending request guards direct selection signal")
 lobby._pending = ""
 lobby.refresh()
 lobby.build_button.pressed.emit()
 check(lobby._local_slot().loadout.cosmetics.paint == "red", "Apply submits paint to host authority")
 check(lobby._pending.is_empty(), "Host acknowledges complete painted loadout")
 lobby._select_vehicle(0, {})
 session.match_view = {"phase":"countdown"}
 lobby.refresh()
 lobby.featured_vehicle.next_button.pressed.emit()
 lobby.featured_vehicle.selection_requested.emit(1, painted)
 check(PlayerProfile.active_bot == 0, "Match lock blocks button and signal selection")
 check(lobby.featured_vehicle.status_label.text.contains("Unapplied draft"), "Locked selection remains distinct from host build")
 check(lobby.featured_vehicle.next_button.disabled, "Match lock visibly disables selector")
 session.leave()
 lobby.queue_free()
 session.queue_free()
 await frames()
 PlayerProfile.loadouts = original
 PlayerProfile.active_bot = original_active
 print("FEATURED VEHICLE MENU PASS" if failures == 0 else "FEATURED VEHICLE MENU FAIL")
 get_tree().quit(0 if failures == 0 else 1)

func layout(screen: Control, label: String) -> void:
 for resolution: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080)]:
  get_window().size = resolution
  var ratio := minf(resolution.x/1920.0, resolution.y/1080.0)
  surface.scale = Vector2.ONE * ratio
  surface.size = Vector2(resolution)/ratio
  for factor: float in [1.0, 1.5]:
   screen.apply_text_scale(factor)
   await frames()
   if screen.has_node("Layout/Body"):
    var body := screen.get_node("Layout/Body") as ScrollContainer
    check(body.get_v_scroll_bar().max_value <= body.get_v_scroll_bar().page + 1, "%s %.2f body %s scroll %s" % [label,factor,body.get_v_scroll_bar().page,body.get_v_scroll_bar().max_value])
   var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
   for control: Node in screen.find_children("*", "Control", true, false):
    if control.is_visible_in_tree() and (control is Button or control is Label):
     check(bounds.grow(1).encloses(control.get_global_rect()), "%s %s %.2f contains %s %s" % [label,resolution,factor,screen.get_path_to(control),control.get_global_rect()])
   if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless" and resolution == Vector2i(1280,720) and factor == 1.5:
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png("user://featured-"+label+"-150.png")
