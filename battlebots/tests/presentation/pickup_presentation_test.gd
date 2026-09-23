extends SceneTree
## Credit wallet persistence/banking, the pickup HUD feed, the results credit line
## and pickup world markers. Rendering is a construction check only; the native
## look is reviewed separately.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	wallet()
	await feed()
	await results()
	await markers()
	await notice()
	await credit_sound()
	print("PICKUP PRESENTATION PASS" if failures == 0 else "PICKUP PRESENTATION FAIL")
	quit(0 if failures == 0 else 1)

func wallet() -> void:
	var path := "user://pickup_wallet_fixture_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(path)
	var wallet := CreditWallet.new(path)
	check(wallet.balance == 0, "A new wallet starts empty")
	check(wallet.bank("match-a", 325) and wallet.balance == 325, "A finished match pays its reward")
	check(not wallet.bank("match-a", 325) and wallet.balance == 325, "Repeated results for one match pay once")
	check(not wallet.bank("", 50) and not wallet.bank("match-b", 0) and not wallet.bank("match-c", -9), "Empty or invalid rewards are ignored")
	check(wallet.bank("match-b", 75) and wallet.balance == 400, "Separate matches accumulate")
	var reloaded := CreditWallet.new(path)
	check(reloaded.balance == 400 and reloaded.banked.has("match-a") and reloaded.banked.has("match-b"), "Balance and paid matches persist")
	check(not reloaded.bank("match-a", 325), "Paid matches are remembered across restarts")
	for index: int in range(CreditWallet.REMEMBERED_MATCHES + 5):
		reloaded.bank("bulk-%d" % index, 1)
	check(reloaded.banked.size() == CreditWallet.REMEMBERED_MATCHES and not reloaded.banked.has("bulk-0"), "Paid-match memory stays bounded")
	var tampered := ConfigFile.new()
	tampered.set_value("wallet", "balance", -50)
	tampered.set_value("wallet", "banked_matches", "not a list")
	tampered.save(path)
	var repaired := CreditWallet.new(path)
	check(repaired.balance == 0 and repaired.banked.is_empty(), "Malformed wallet data is not trusted")
	DirAccess.remove_absolute(path)
	var results := {"participants":{2:{"credits":{"pickups":50, "performance":275, "total":325}}, 3:{"credits":{"total":"9"}}}}
	check(CreditWallet.reward_for(results, 2) == 325, "Local reward is read from the server record")
	check(CreditWallet.reward_for(results, 3) == 0 and CreditWallet.reward_for(results, 9) == 0
		and CreditWallet.reward_for({}, 2) == 0, "Missing or malformed rewards pay nothing")

func feed() -> void:
	var hud := Control.new()
	root.add_child(hud)
	var panel := PickupFeed.new()
	hud.add_child(panel)
	panel.bind_names(PickupFeed.names_from(ContentRegistry.new()))
	await process_frame
	panel.render({}, 1, false)
	check(not panel.visible, "No pickup state hides the feed")
	var view := {"items":[{"id":0}], "credits":{1:150, 2:25}}
	panel.render(view, 1, false)
	check(panel.visible and panel.credits_value.text == "+150" and not panel.practice_note.visible, "Feed shows this player's match credits")
	panel.render(view, 1, true)
	check(panel.practice_note.visible, "Practice explains that rewards are not banked")
	panel.render({"items":[{"id":0}], "credits":{1:"x"}}, 1, false)
	check(panel.credits_value.text == "+0", "Malformed credits are not shown")
	panel.notify({"entity":2, "kind":"part", "part":"hammer"}, 1)
	check(panel.toasts.get_child_count() == 0, "Other players' pickups do not notify")
	panel.notify({"entity":1, "kind":"part", "part":"atlas_mx"}, 1)
	var first: Label = panel.toasts.get_child(0).get_child(0).get_child(1)
	check(first.text == "ATLAS MX MODULAR CHASSIS", "Part toast uses the Customize name")
	panel.notify({"entity":1, "kind":"perk", "part":"nitro_boost"}, 1)
	panel.notify({"entity":1, "kind":"credits", "amount":50}, 1)
	panel.notify({"entity":1, "kind":"part", "part":"hammer"}, 1)
	check(panel.toasts.get_child_count() == PickupFeed.MAX_TOASTS, "Toasts stay bounded")
	var newest: Label = panel.toasts.get_child(0).get_child(0).get_child(1)
	check(newest.text == "HAMMER", "Newest toast is on top")
	check(PickupFeed.describe({"kind":"credits", "amount":100}, {}) == "+100 CREDITS", "Credit items describe their amount")
	check(panel.get_combined_minimum_size().y <= 100.0 and panel.credits_panel.get_combined_minimum_size().y <= 26.0,
		"Feed stays compact: one-line credits chip and toasts")
	panel.apply_text_scale(1.5)
	check(panel.credits_value.get_theme_font_size("font_size") == 20, "Feed follows HUD text size")
	check(panel.get_combined_minimum_size().y <= 140.0, "Enlarged feed stays compact: %s" % panel.get_combined_minimum_size())
	panel._process(PickupFeed.TOAST_SECONDS + 0.1)
	check(panel.toasts.get_child_count() == 0, "Toasts expire")
	hud.queue_free()

func results() -> void:
	var panel := MatchResults.new()
	root.add_child(panel)
	panel.show()
	var view := {"match_id":"fixture", "phase":"results", "mode":"1v1", "winner":0, "scores":[2, 0], "remaining":20}
	panel.render(view, 1, 0)
	check(not panel.credits_label.visible, "No credit line before the record arrives")
	var participants := {1:{"damage":80, "credits":{"pickups":50, "performance":290, "total":340}}, 2:{"damage":10}}
	panel.accept_record({"match":view.duplicate(true), "participants":participants}, "fixture")
	panel.render(view, 1, 0)
	check(panel.credits_label.visible and panel.credits_label.text.begins_with("+340 CREDITS EARNED")
		and panel.credits_label.text.contains("pickups 50"), "Results show the local reward breakdown")
	panel.render(view, 2, 1)
	check(not panel.credits_label.visible, "A record without credits shows no invented reward")
	panel.queue_free()
	await process_frame

func markers() -> void:
	var visuals := PickupVisuals.new()
	root.add_child(visuals)
	var marker := visuals._marker()
	visuals.add_child(marker)
	await process_frame
	visuals._show(marker, {"id":0, "point":Vector3(3, 0, 4), "kind":"credits", "part":"", "amount":50, "available":true})
	check(marker.visible and marker.position == Vector3(3, 0, 4) and (marker.get_node("Label") as Label3D).text == "+50 CREDITS",
		"Marker shows its contents at the pickup point")
	check((marker.get_node("Token/Core") as MeshInstance3D).mesh is CylinderMesh, "Credits use a coin token")
	visuals._show(marker, {"id":0, "point":Vector3(3, 0, 4), "kind":"perk", "part":"nitro_boost", "amount":0, "available":false})
	check(not marker.visible and (marker.get_node("Token/Core") as MeshInstance3D).mesh is SphereMesh, "Collected items hide and restyle for their next roll")
	visuals.registry = ContentRegistry.new()
	for part: String in ["hammer", "vertical_spinner", "minigun", "traction", "standard_wheels", "atlas_mx", "scorpion_hex", "balanced", "minigun_pod"]:
		visuals._show(marker, {"id":0, "point":Vector3.ZERO, "kind":"part", "part":part, "amount":0, "available":true})
		var model := marker.get_node_or_null("Token/Model") as Node3D
		check(model != null and not (marker.get_node("Token/Core") as Node3D).visible, part + " pickup shows its real model")
		if model != null:
			var shown := 0
			for mesh: Node in model.find_children("*", "GeometryInstance3D", true, false):
				shown += int((mesh as GeometryInstance3D).is_visible_in_tree())
			check(shown > 0 and model.scale.x > 0.0, part + " model has visible, fitted geometry")
	for part: String in ["heavy", "cooling_pack"]:
		visuals._show(marker, {"id":0, "point":Vector3.ZERO, "kind":"part", "part":part, "amount":0, "available":true})
		check(marker.get_node_or_null("Token/Model") == null or marker.get_node("Token/Model").is_queued_for_deletion(),
			part + " without a dedicated mesh keeps the token")
		check((marker.get_node("Token/Core") as Node3D).visible, part + " token is shown")
	visuals.queue_free()

func notice() -> void:
	var names := PickupFeed.names_from(ContentRegistry.new())
	check(PickupNotice.message({"kind":"perk", "part":"nitro_boost", "reason":"equipped"}, names) == "NITRO BOOST ALREADY EQUIPPED",
		"Equipped perk explains itself")
	check(PickupNotice.message({"kind":"part", "part":"hammer", "reason":"equipped"}, names) == "HAMMER ALREADY FITTED",
		"Fitted part explains itself")
	check(PickupNotice.message({"kind":"part", "part":"standard_wheels", "reason":"incompatible"}, names).ends_with("DOESN'T FIT YOUR BUILD"),
		"Incompatible part explains itself")
	var label := PickupNotice.new()
	root.add_child(label)
	await process_frame
	check(not label.visible, "Notice starts hidden")
	label.notify({"kind":"part", "part":"hammer", "reason":"equipped"}, names)
	check(label.visible and label.text == "HAMMER ALREADY FITTED", "Refusal shows centred text")
	label._process(PickupNotice.SECONDS + 0.1)
	check(not label.visible, "Notice fades away")
	label.queue_free()

func credit_sound() -> void:
	var stream := GameplaySoundBank.new().stream("credit_pickup")
	var peak := 0
	for index: int in range(0, stream.data.size(), 2):
		peak = maxi(peak, absi(stream.data.decode_s16(index)))
	check(stream != null and is_equal_approx(stream.get_length(), 0.42) and peak > 3000 and peak < 32767,
		"Credit pling is a short, audible, unclipped cue")
	var audio := GameplayAudio.new()
	root.add_child(audio)
	await process_frame
	var cues: Array[String] = []
	var captions: Array[String] = []
	audio.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	audio.caption_changed.connect(func(text: String) -> void: captions.append(text))
	audio.pickup_collected({"entity":2, "kind":"credits", "amount":50}, 1)
	audio.pickup_collected({"entity":1, "kind":"part", "part":"hammer", "amount":0}, 1)
	check(cues.is_empty(), "Only the local player's credit pickups ring")
	audio.pickup_collected({"entity":1, "kind":"credits", "amount":50}, 1)
	await process_frame
	check(cues == ["credit_pickup"], "Local credit pickup plays the pling")
	check(captions.any(func(text: String) -> bool: return text.contains("+50 credits")), "Pling has an accessible caption")
	audio.queue_free()
	await process_frame
