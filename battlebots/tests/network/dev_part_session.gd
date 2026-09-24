extends "res://tests/network/contact_reconciliation.gd"
## Local part shortcuts (#64): practice cycles weapon, body and drive through
## the pickup swap; a joined client, an offline session and a host without its
## own bot are refused.

func run() -> void:
	var practice := make_session("Practice")
	practice.pickups_enabled = false
	check(practice.practice(practice.registry.atlas(), "foundry") == OK, "Practice starts")
	await frames(10)
	var id := practice.local_entity
	var weapon: String = practice.world.bots[id].loadout.parts.weapon
	var seen: Array[String] = [weapon]
	for press: int in 4:
		var result := practice.dev_cycle_part("weapon")
		await frames(2)
		var now: String = practice.world.bots[id].loadout.parts.weapon
		check(result.get("part") == now and not seen.has(now), "Weapon shortcut fits a new weapon: %s" % result)
		seen.append(now)
	var body := practice.dev_cycle_part("chassis")
	await frames(2)
	var bot: MvpBot = practice.world.bots[id]
	check(body.has("part") and bot.loadout.parts.chassis == body.part and bot.loadout.parts.chassis != "atlas_mx"
		and practice.registry.validate(bot.loadout).valid, "Body shortcut swaps to another offered body: %s" % body)
	var drive_before: String = bot.loadout.parts.drive
	var drive := practice.dev_cycle_part("drive")
	await frames(2)
	bot = practice.world.bots[id]
	if bot.loadout.parts.chassis == "scorpion_hex":
		check(drive.get("refused") == "no_fit", "A Scorpion keeps its only drive")
	else:
		check(drive.has("part") and bot.loadout.parts.drive != drive_before, "Drive shortcut swaps the drive: %s" % drive)
	check(practice.local_source() == bot, "The local source follows the rebuilt bot")
	practice.leave()
	var offline := make_session("Offline")
	check(offline.dev_cycle_part("weapon").get("refused") == "remote", "No game, no shortcut")
	# A host with a guest: the guest cannot swap.
	server = make_session("Server")
	var port := FreePort.udp()
	check(server.host(port, false, 2) == OK, "Host binds")
	var guest := make_session("Guest")
	check(guest.join("127.0.0.1", port) == OK, "Guest joins")
	check(await until(func() -> bool: return guest.local_entity > 0), "Guest admitted")
	check(guest.dev_cycle_part("weapon").get("refused") == "remote", "A joined client cannot use part shortcuts")
	var dedicated := server.dev_cycle_part("weapon")
	check(dedicated.get("refused") == "unavailable", "A host without its own bot has nothing to swap: %s" % dedicated)
	await finish()

func finish() -> void:
	for session: MvpSession in sessions: session.leave()
	await get_tree().physics_frame
	for child: Node in get_children():
		if child is SubViewport: get_tree().set_multiplayer(null, child.get_path())
		child.queue_free()
	await get_tree().process_frame
	print("DEV PART SESSION PASS" if failures == 0 else "DEV PART SESSION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
