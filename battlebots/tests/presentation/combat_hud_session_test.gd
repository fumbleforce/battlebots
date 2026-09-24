extends SceneTree
const FreePort := preload("res://tests/fixtures/free_port.gd")
## Controlled server state over real ENet; not a natural combat acceptance test.
const HudScript := preload("res://scripts/ui/combat_hud.gd")
var failures := 0
var views: Array[SubViewport] = []
var host: MvpSession
var client: MvpSession
var hud: Control
var markers: BotWorldMarkers

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func make_session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	views.append(viewport)
	var session := MvpSession.new()
	session.name = "Session"
	viewport.add_child(session)
	return session

func render_received() -> bool:
	markers.render(client.bot_views(), client.local_entity, false, true)
	var local: BotView
	var rival: BotView
	for view: BotView in client.bot_views():
		if view.entity_id == client.local_entity:
			local = view
		else:
			rival = view
	hud.render(local, "R", rival)
	return local != null and rival != null

func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Combat HUD session fixture exceeded its wall-clock limit")
		quit(1))
	host = make_session("HudHost")
	client = make_session("HudClient")
	hud = HudScript.new()
	views[1].add_child(hud)
	markers = BotWorldMarkers.new()
	views[1].add_child(markers)
	await process_frame
	check(client.bot_views().is_empty(), "Disconnected client exposes no fabricated bots")
	check(not render_received() and hud.resources.Core.value.text == "--", "Missing network baseline displays unavailable")
	check(markers.markers.is_empty(), "No world identity is invented without a baseline")
	var port := FreePort.udp()
	check(host.host(port, true, 2) == OK, "Duel listen host starts real ENet")
	check(client.join("127.0.0.1", port) == OK, "HUD observer joins through ENet")
	if not await until(func() -> bool: return client.local_entity > 0 and client.lobby_view.get("slots", []).size() == 2):
		check(false, "Duel admission completes")
		await finish()
		return
	# The default starter fits no armour; a chin plate gives the client a face that can breach.
	var armoured: Dictionary = client.registry.starter()
	armoured.cosmetics["sawblade"] = SawbladeConfig.defaults()
	armoured.cosmetics.sawblade.armor_front = 1
	client.set_loadout(armoured)
	host.set_ready(true)
	client.set_ready(true)
	if not await until(func() -> bool: return client.match_view.get("phase") == "active" and render_received()):
		check(false, "Client receives active duel and both bot baselines")
		await finish()
		return
	check(hud.resources.Core.value.text == "100%" and not hud.components_panel.visible, "Fresh authoritative duel displays healthy living bots")
	check(markers.markers.size() == 2 and markers.markers[client.local_entity].text.is_empty() and markers.markers[client.local_entity].get_node("HealthBar").visible and not markers.markers[client.local_entity].get_node("Leader").visible, "Published client identity keeps local health while suppressing its floating tag and stem")
	var snapshot_tick: int = client._last_snapshot_tick[client.local_entity]
	client._last_snapshot_tick.erase(client.local_entity)
	check(not client.bot_views().any(func(view: BotView) -> bool: return view.entity_id == client.local_entity), "Existing client body without baseline is not published as healthy")
	markers.render(client.bot_views(), client.local_entity, false, true)
	check(markers.markers.is_empty(), "Missing local baseline suppresses rival classification too")
	client._last_snapshot_tick[client.local_entity] = snapshot_tick
	var detached: BotView = client.bot_views()[0]
	detached.zones.weapon = -123.0
	check(client.bot_views().all(func(view: BotView) -> bool: return view.zones.get("weapon") != -123.0), "Published bot views cannot mutate session health")
	var authority: MvpBot = host.world.bots[client.local_entity]
	authority.combat.damage("top", 30.0)
	authority.combat.zones.drive_left = 0.0
	authority.combat.zones.front = 0.0
	authority.combat.recovery_cooldown = 15.0
	var expected_core: String = "%d%%" % roundi(authority.combat.core / authority.combat.stats.core * 100.0)
	check(await until(func() -> bool:
		return render_received() and hud.resources.Core.value.text == expected_core \
			and hud.components.drive_left.text.ends_with("DISABLED") \
			and hud.components.front.text.ends_with("BREACHED") \
			and hud.recovery_label.text.contains("COOLDOWN")),
		"Server damage, disabled drive, breached armor and recovery cooldown reach client HUD")
	var rival: MvpBot = host.world.bots[host.local_entity]
	rival.combat.eliminate("HUD propagation fixture")
	check(await until(func() -> bool:
		return client.match_view.get("phase") == "intermission" and render_received() \
			and markers.markers[host.local_entity].text.contains("OUT")),
		"Server elimination reaches rival status through real round transition")
	check(markers.markers[host.local_entity].text.contains("OUT"), "Authoritative elimination reaches world badge")
	# Advance only the authoritative fixture clock; production reset repairs bots.
	host.match_state.remaining = 0.0
	check(await until(func() -> bool:
		return client.match_view.get("round") == 2 and render_received() \
			and hud.resources.Core.value.text == "100%" \
			and not hud.components_panel.visible \
			and hud.components.drive_left.text == "L DRIVE\n100" \
			and not hud.components.front.text.ends_with("BREACHED") \
			and not hud.recovery_label.text.contains("COOLDOWN") \
			and hud.warning_label.text.is_empty()),
		"Authoritative next-round baseline clears damage, disabled components, cooldown and elimination")
	check(not markers.markers[host.local_entity].text.contains("OUT"), "New-round view clears stale elimination marker")
	client.leave()
	check(not render_received() and hud.resources.Core.value.text == "--" \
		and not hud.components_panel.visible, "Leaving clears stale HUD data")
	check(markers.markers.is_empty(), "Leaving removes world badges")
	await finish()

func finish() -> void:
	host.leave()
	client.leave()
	for viewport: SubViewport in views:
		viewport.queue_free()
	await process_frame
	print("COMBAT HUD SESSION PASS" if failures == 0 else "COMBAT HUD SESSION FAIL")
	quit(0 if failures == 0 else 1)
