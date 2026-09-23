class_name MenuData
extends RefCounted
## Menu presentation of the canonical catalogue. Art is concept art, not a bot render.
const AMBER := Color("#F5B82E")
const GREEN := Color("#3FCB4A")
const RED := Color("#E5534B")
const TEXT := Color("#E8ECF1")
const TEXT2 := Color("#B8C2CE")
const MUTED := Color("#9AA6B5")
const INK := Color("#141413")
const STAT_KEYS := ["MASS kg", "POWER", "SPEED m/s", "ARMOR %"]
const MODES := [
	{"id":"training","big":"SOLO","tag":"PRACTICE","title":"PRACTICE","desc":"Test your build against a calibration target and two active NPC bots.","meta1":"Solo","meta2":"No rewards","tint":Color("#2F5A36"),"rules":"Solo practice · Three respawning NPC bots · No rating or rewards","enabled":true},
	{"id":"duel","big":"1V1","tag":"PRIVATE","title":"PRIVATE DUEL","desc":"Host a private duel for two players.","meta1":"First to 2","meta2":"2 players","tint":Color("#8A2520"),"rules":"1v1 · First to two rounds · Five-round cap","enabled":true},
	{"id":"team","big":"2V2","tag":"STANDARD","title":"TEAM BRAWL","desc":"Coordinate with a teammate in a private match.","meta1":"First to 2","meta2":"4 players","tint":Color("#1F4A9A"),"rules":"2v2 · First to two rounds · Five-round cap · No arena hazards","enabled":true},
	{"id":"quick","big":"GO","tag":"UNAVAILABLE","title":"QUICK MATCH","desc":"Public matchmaking is not implemented.","meta1":"Unavailable","meta2":"Planned","tint":Color("#3A4452"),"rules":"Public services unavailable","enabled":false},
	{"id":"ranked","big":"1V1","tag":"DEFERRED","title":"RANKED DUEL","desc":"Ranked play is deferred.","meta1":"Unavailable","meta2":"Deferred","tint":Color("#3A4452"),"rules":"Ranked play unavailable","enabled":false},
	{"id":"5v5","big":"5V5","tag":"PLAYTEST","title":"LARGE TEAMS","desc":"Two teams of five in a private match.","meta1":"First to 2","meta2":"10 players","tint":Color("#3A4452"),"rules":"5v5 · Four-minute rounds · First to two · Five-round cap","enabled":true},
	{"id":"ffa","big":"FFA","tag":"PLAYTEST","title":"FREE FOR ALL","desc":"Every bot for itself. Start with 4–8 players.","meta1":"One round","meta2":"4–8 players","tint":Color("#3A4452"),"rules":"Free-for-all · One five-minute round · No overtime","enabled":true},
]
const ARENAS := [
	{"name":"THE FOUNDRY","sub":"Industrial octagon · Standard gravity","size":"100 m ACROSS · 9.8 m/s²","image":preload("res://ui/menus/art/arena_foundry.jpg"),"hazards":["Expanded flat steel combat floor","Standard gravity · No active hazards","Armored cage and spectator galleries"],"enabled":true},
	{"name":"LUNAR OUTPOST","sub":"Moon surface · Low gravity","size":"50 m ACROSS · 1.62 m/s²","image":preload("res://ui/menus/art/arena_moon.png"),"art":"LUNAR OUTPOST","hazards":["Uneven regolith and small edge rocks","Lunar gravity · Longer airtime","Ballistic dust, floodlights and Earth overhead"],"enabled":true},
	{"name":"WOODLAND","sub":"Forest stadium · Giant scale","size":"240 m ACROSS · 9.8 m/s²","image":preload("res://ui/menus/art/arena_woodland.jpg"),"art":"WOODLAND","hazards":["Central cliff mesa, rock terraces and outcrops","Jump ramps, bunkers, pine groves and log cover","Rutted mud, timber palisade and roaring crowd"],"enabled":true}
]

static func _armor_description(registry: ContentRegistry, section: String, index: int) -> String:
	if not registry.armor_pieces.has(section): return "Body appearance only; no performance effect."
	var piece: Dictionary = registry.armor_pieces[section][index]
	var faces := " and ".join(PackedStringArray(piece.covers))
	if piece.covers.is_empty():
		return "No armour here: hits on this area go straight to the core."
	return "Covers %s · %s HP%s · %s kg. While it has HP it fully shields %s from core damage." % [
		faces, fmt_int(roundi(piece.integrity)), " each" if piece.covers.size() > 1 else "",
		fmt_int(roundi(piece.mass)), "those areas" if piece.covers.size() > 1 else "that area"]

static func catalogue(registry: ContentRegistry) -> Dictionary:
	var categories: Array = []
	for slot: String in ContentRegistry.SLOTS:
		var items: Array = []
		for id: String in registry.parts:
			var part: Dictionary = registry.parts[id]
			if part.category == slot and (slot != "chassis" or id in ["balanced", "scorpion_hex", "atlas_mx"]):
				items.append({"id":id,"name":id.capitalize(),"default":"own","desc":"%s · %.0f kg · %.0f installed power. All functional parts are available." % [id.capitalize(),part.mass,part.power],"d":{}})
		categories.append({"label":slot.to_upper(),"slot":slot,"items":items})
		if slot == "utility": categories.back().label = "AUXILIARY / UTILITY"
		if slot == "nitro": categories.back().label = "NITRO PERK"
		if slot == "suspension": categories.back().label = "SUSPENSION PERK"
		# Armour is chosen per area in the ARMOR sections, not as one package part.
		if slot == "weapon": categories.append({"label":"ARMOR","slot":"armor","items":[]})
	var paints: Array = []
	var colors := {"cyan":"#29cce5","orange":"#ef922a","white":"#eeeeee","red":"#d93c39"}
	for id: String in colors:
		paints.append({"id":id,"name":id.capitalize(),"default":"own","swatch":colors[id],"desc":"Apply this paint to the body and secondary panels. Individual channels can be adjusted separately; paint has no performance effect."})
	var paint_categories: Array = [{"label":"OVERALL PAINT","slot":"paint","items":paints}]
	for channel: String in SawbladeConfig.COLORS:
		var choices: Array = []
		var original: Array = SawbladeConfig.defaults()[channel]
		choices.append({"id":"original", "name":"Original", "default":"own", "rgba":original,
			"swatch":Color(original[0], original[1], original[2]).linear_to_srgb().to_html(), "desc":"Authored module color. Use CUSTOM COLOR for any color."})
		for id: String in colors:
			var color := Color(colors[id]).srgb_to_linear()
			choices.append({"id":id,"name":id.capitalize(),"default":"own","swatch":colors[id],
				"rgba":[color.r,color.g,color.b,1.0],"desc":"Tint this channel across compatible painted modules."})
		paint_categories.append({"label":channel.trim_prefix("paint_").to_upper(),"slot":channel,"items":choices})
	var vehicle: Array = []
	for slot: String in SawbladeConfig.OPTIONS:
		var choices: Array = []
		for index: int in SawbladeConfig.OPTIONS[slot].size():
			choices.append({"id":str(index),"name":SawbladeConfig.OPTIONS[slot][index],"default":"own",
				"desc":_armor_description(registry, slot, index)})
		vehicle.append({"label":slot.replace("_", " ").to_upper(),"slot":slot,"items":choices})
	for category: Dictionary in categories:
		for item: Dictionary in category.items:
			if item.id == "balanced":
				item.name = "Sawblade body"
				item.desc = "Authored chassis body. Changing the body preserves all other selected parts and appearance options."
			elif item.id == "atlas_mx":
				item.name = "Atlas MX modular chassis"
				item.desc = "Wide tracked platform with an open equipment deck, front tool coupler, roof rails, auxiliary gun socket and a turret race for a cannon or plasma turret. Runs on Tracks · Traction, large off-road wheels (Four wheels · Standard) or four hydraulic legs (Articulated walking legs). All primary weapons and utilities fit within normal build budgets."
			elif item.id == "traction": item.name = "Tracks · Traction"
			elif item.id == "standard_wheels":
				item.name = "Four wheels · Standard"
				item.desc = "Standard wheels · 22 kg · 25 power · 10 m/s. On Atlas MX: four large lugged off-road tyres on hub motors under the sponson hoods."
			elif item.id == "agile": item.name = "Four wheels · Agile"
			elif item.id == "lifter": item.name = "Ramp · Lifter"
			elif item.id == "battering_ram":
				item.name = "Battering ram"
				item.desc = "Atlas MX front tool · 26 kg · 30 power. An armoured prow with hardened striker plates: rams landed on the prow deal 2.2× damage and 1.6× knock-back while you take only a third of the return blow. Press primary for a hydraulic punch (24 damage, big shove). Drive enemies into walls."
			elif item.id == "spear_fork":
				item.name = "Spear · Forklift"
				item.desc = "Atlas MX front tool · 22 kg · 30 power. Press primary to thrust a barbed lance and fork tines: 30 piercing damage that armour only partly stops, and the target is impaled. Keep holding to lift and carry it helplessly; release to throw it off. Tears free after 5 s or under heavy strain."
			elif item.id == "grinder_drum":
				item.name = "Grinder drum"
				item.desc = "Atlas MX front tool · 30 kg · 40 power. A huge spiked drum on thick hydraulic arms. Hold primary to spin it up and shred whatever it touches; armour plates take 2.4× damage. Hold secondary to raise the arms onto a target's top. Pulls victims into the drum; builds heat fast."
			elif item.id == "walker":
				item.name = "Articulated walking legs"
				item.desc = "Six legs on Scorpion, four hydraulic legs on Atlas MX, four on Sawblade · 32 kg · 35 power · 4 m/s. Planted feet adapt to terrain and smooth alternating steps."
			elif item.id == "scorpion_hex":
				item.name = "Scorpion hex body"
				item.desc = "Orange diesel-powered six-legged combat machine. Tapered hexagonal armor, interchangeable dorsal weapon and minigun socket. Requires walking drive; preserves your other selected parts."
			elif item.id == "minigun_pod":
				item.name = "Minigun • Auxiliary"
				item.desc = "Scorpion / Atlas MX gun socket · 14 kg · 25 power. Hold secondary fire to spool and fire while operating the primary hammer. Builds shared heat. Swap for another utility to remove."
			elif item.id == "turret_cannon":
				item.name = "Turret · Cannon"
				item.desc = "Atlas MX roof turret · 16 kg · 25 power. Tank controls: aim with the mouse over the turret sight and fire the main gun with primary fire; secondary fire operates the hull weapon. A heavy shell every 2.4 s knocks targets back. Builds shared heat. Replaces the roof gun mount, so it excludes the minigun."
			elif item.id == "turret_cannon_dual":
				item.name = "Turret · Twin cannon ▲"
				item.desc = "Upgrade · Atlas MX roof turret · 22 kg · 35 power. Two barrels ripple a volley of heavy shells every 2.6 s. Tank controls: mouse to aim, primary fire to shoot. Replaces the roof gun mount."
			elif item.id == "turret_cannon_quad":
				item.name = "Turret · Quad cannon ▲▲"
				item.desc = "Upgrade · Atlas MX roof turret · 30 kg · 40 power. Four barrels unload a devastating rippling volley every 3 s. Heavy: slows the tank. Tank controls; replaces the roof gun mount."
			elif item.id == "turret_plasma_dual":
				item.name = "Turret · Twin plasma ▲"
				item.desc = "Upgrade · Atlas MX roof turret · 20 kg · 35 power. Alternating emitters pour searing plasma bolts at almost twice the rate. Watch heat. Tank controls; replaces the roof gun mount."
			elif item.id == "turret_plasma_quad":
				item.name = "Turret · Quad plasma ▲▲"
				item.desc = "Upgrade · Atlas MX roof turret · 28 kg · 40 power. Four emitters hose a torrent of plasma until heat runs out. Heavy: slows the tank. Tank controls; replaces the roof gun mount."
			elif item.id == "turret_flamer":
				item.name = "Turret · Flamethrower 🔥"
				item.desc = "Atlas MX roof turret · 15 kg · 25 power. Close quarters: hold primary fire to hose a 17 m cone of fire that burns every enemy inside it. Walls cut the jet short. Builds shared heat."
			elif item.id == "turret_tesla":
				item.name = "Turret · Tesla arc ⚡"
				item.desc = "Atlas MX roof turret · 16 kg · 30 power. Close quarters: each discharge arcs lightning to the nearest enemy within 15 m of your aim and chains to a second enemy nearby. No aiming precision needed."
			elif item.id == "turret_railgun":
				item.name = "Turret · Railgun"
				item.desc = "Atlas MX roof turret · 20 kg · 35 power. Hold primary fire to charge, release to fire a hypersonic slug: 70 damage, 140 m, pierces into a second target. Releasing early cancels. Massive recoil."
			elif item.id == "turret_harpoon":
				item.name = "Turret · Harpoon ⚓"
				item.desc = "Atlas MX roof turret · 15 kg · 25 power. Press primary fire to shoot a barbed harpoon on a cable (42 m). A hit tethers the enemy: keep holding to winch them toward you; press again to cut the cable. The cable snaps past 50 m, around walls or after 7 s. Drag enemies onto your hull weapon or into a wall."
			elif item.id == "turret_mortar":
				item.name = "Turret · Mortar"
				item.desc = "Atlas MX roof turret · 22 kg · 35 power. Artillery: the camera rises over the battlefield and the mouse places a ground target (about 20–60 m). Primary fire lobs a shell over walls that blasts everything within 7.5 m. Heavy 3.2 s reload; useless up close."
			elif item.id == "turret_plasma":
				item.name = "Turret · Plasma gun"
				item.desc = "Atlas MX roof turret · 14 kg · 25 power. Tank controls: aim with the mouse over the turret sight and hold primary fire for rapid plasma bolts; secondary fire operates the hull weapon. Light hits that build heat quickly. Replaces the roof gun mount, so it excludes the minigun."
			elif item.id == "minigun":
				item.name = "Minigun • Primary"
				item.desc = "Primary weapon module · 24 kg · 35 power. Hold primary fire for sustained ranged fire. On Scorpion it replaces the dorsal hammer; choose a separate utility."
			elif item.id == "nitro_boost":
				item.name = "Nitro boost"
				item.desc = "Hold Shift to accelerate and drive faster. Generates 14 heat/s while active; release to cool."
			elif item.id == "nitro_off":
				item.name = "No Nitro"
				item.desc = "Leave the Nitro perk unequipped."
			elif item.id == "charged_jump":
				item.name = "Charged suspension jump"
				item.desc = "Hold Space while grounded to charge, then release to jump. Longer holds launch harder. Generates 20 heat on release and has a short cooldown."
			elif item.id == "jump_off":
				item.name = "No jump"
				item.desc = "Leave the suspension perk unequipped."

	return {"parts":categories,"paint":paint_categories,"decals":vehicle}

static func mode_by_id(id: String) -> Dictionary:
	for mode: Dictionary in MODES:
		if mode.id == id: return mode
	return MODES[0]

static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0,s.length() - 3)
	return ("-" if n < 0 else "") + s + out
