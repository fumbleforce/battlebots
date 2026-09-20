extends SceneTree
## Persistent public friend code; never display or copy admission credentials.
class HostFixture extends Node:
	var public_service: PublicServiceClient

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for index in 8:
		await process_frame

func run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var session := MvpSession.new()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.connection_state = "connected"
	session.local_entity = 1
	session.lobby_view = {"mode":"1v1", "capacity":2, "phase":"lobby", "slots":[
		{"entity_id":1,"team":0,"connected":true,"ready":false,"loadout":session.registry.starter()}]}
	var host := HostFixture.new()
	host.public_service = PublicServiceClient.new()
	host.add_child(host.public_service)
	root.add_child(host)
	host.public_service.set_process(false)
	host.public_service.membership = {"code":"ABCD1234", "token":"must-not-be-displayed", "admission_ticket":"must-not-be-copied"}
	host.public_service.region = "Stockholm"
	var router := root.get_node("MenuRouter")
	router.bind(host, session)
	router.lobby_intent = "online"
	var lobby: Control = load("res://ui/menus/screens/lobby.tscn").instantiate()
	lobby.session_override = session
	root.add_child(lobby)
	for extent in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = extent
		for factor in [1.0, 1.5]:
			lobby.apply_text_scale(factor)
			lobby.refresh()
			await settle()
			var header: Control = lobby.get_node("Layout/Header")
			var bounds := Rect2(Vector2.ZERO, Vector2(root.content_scale_size))
			check(lobby.room_code_panel.visible and lobby.room_code_label.text == "ABCD1234", "Private friend code persists in lobby")
			check(lobby.copy_code_button.text == "COPY CODE" and not lobby.copy_code_button.disabled, "Copy action is explicit and available")
			for item: Control in [lobby.room_code_panel, lobby.room_code_label, lobby.copy_code_button, lobby.get_node("%Title"), lobby.get_node("%Back")]:
				check(bounds.encloses(item.get_global_rect()) and header.get_global_rect().encloses(item.get_global_rect()), "Room sharing fits fixed header at %s/%s: %s" % [extent, factor, item.get_class()])
			check(lobby.get_node("Layout/Body").scroll_vertical == 0, "Room sharing requires no body scroll")
			lobby.copy_code_button.grab_focus()
			check(lobby.copy_code_button.has_focus(), "Copy code is keyboard reachable")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://private-lobby-code-%d-%d.png" % [extent.x, roundi(factor * 100)])
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		var previous_clipboard := DisplayServer.clipboard_get()
		lobby.copy_code_button.pressed.emit()
		check(DisplayServer.clipboard_get() == "ABCD1234", "Copy writes only the public friend code")
		check(lobby.copy_code_button.text == "COPIED", "Copy provides immediate feedback")
		DisplayServer.clipboard_set(previous_clipboard)
	else:
		print("PRIVATE_LOBBY_CLIPBOARD_UNAVAILABLE: verify native capture run")
	# The code survives ready updates and the opponent arriving.
	session.lobby_view.slots[0].ready = true
	session.lobby_view.slots.append({"entity_id":2,"team":1,"connected":true,"ready":false,"loadout":session.registry.starter(true)})
	lobby.refresh()
	check(lobby.room_code_label.text == "ABCD1234" and lobby.room_code_panel.visible, "Roster and ready updates preserve room code")
	host.public_service.membership = {"code":"", "token":"not-a-room-code"}
	lobby.refresh()
	check(not lobby.room_code_panel.visible and lobby.copy_code_button.disabled and lobby.room_code_label.text.is_empty(), "Quick Play has no code or stale sharing action")
	host.public_service.membership = {"code":"WXYZ5678"}
	lobby.refresh()
	check(lobby.room_code_label.text == "WXYZ5678" and lobby.copy_code_button.text == "COPY CODE", "New membership replaces stale room and copy feedback")
	for invalid: Variant in [null, 12345678, "short", "TOKEN/SECRET", "ABCD12\n4"]:
		host.public_service.membership.code = invalid
		lobby.refresh()
		check(not lobby.room_code_panel.visible, "Malformed public code never becomes a shareable credential")
	host.public_service.membership = {"code":"ABCD1234"}
	router.lobby_intent = "join"
	lobby.refresh()
	check(not lobby.room_code_panel.visible, "Direct sessions do not inherit online room codes")
	lobby.queue_free()
	router.host = null
	router.session = null
	session.connection_state = "offline"
	session.queue_free()
	host.queue_free()
	await settle()
	print("PRIVATE LOBBY CODE PASS" if failures == 0 else "PRIVATE LOBBY CODE FAIL")
	quit(0 if failures == 0 else 1)
