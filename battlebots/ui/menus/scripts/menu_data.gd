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
				"desc":"Modular body appearance. Armor protection and weight come from PARTS > ARMOR; exhaust has no performance effect."})
		vehicle.append({"label":slot.replace("_", " ").to_upper(),"slot":slot,"items":choices})
	for category: Dictionary in categories:
		for item: Dictionary in category.items:
			if item.id == "balanced":
				item.name = "Sawblade body"
				item.desc = "Authored chassis body. Changing the body preserves all other selected parts and appearance options."
			elif item.id == "atlas_mx":
				item.name = "Atlas MX modular chassis"
				item.desc = "Wide tracked platform with an open equipment deck, front tool coupler, roof rails and auxiliary gun socket. Requires Tracks · Traction. All primary weapons and utilities fit within normal build budgets."
			elif item.id == "traction": item.name = "Tracks · Traction"
			elif item.id == "standard_wheels": item.name = "Four wheels · Standard"
			elif item.id == "agile": item.name = "Four wheels · Agile"
			elif item.id == "lifter": item.name = "Ramp · Lifter"
			elif item.id == "walker":
				item.name = "Articulated walking legs"
				item.desc = "Six legs on Scorpion, four on Sawblade · 32 kg · 35 power · 4 m/s. Planted feet adapt to terrain and smooth alternating steps."
			elif item.id == "scorpion_hex":
				item.name = "Scorpion hex body"
				item.desc = "Orange diesel-powered six-legged combat machine. Tapered hexagonal armor, interchangeable dorsal weapon and minigun socket. Requires walking drive; preserves your other selected parts."
			elif item.id == "minigun_pod":
				item.name = "Minigun • Auxiliary"
				item.desc = "Scorpion / Atlas MX gun socket · 14 kg · 25 power. Hold secondary fire to spool and fire while operating the primary hammer. Uses battery and builds heat. Swap for another utility to remove."
			elif item.id == "minigun":
				item.name = "Minigun • Primary"
				item.desc = "Primary weapon module · 24 kg · 35 power. Hold primary fire for sustained ranged fire. On Scorpion it replaces the dorsal hammer; choose a separate utility."
			elif item.id == "nitro_boost":
				item.name = "Nitro boost"
				item.desc = "Hold Shift to accelerate and drive faster. Consumes battery while active; release to conserve energy."
			elif item.id == "nitro_off":
				item.name = "No Nitro"
				item.desc = "Leave the Nitro perk unequipped."
			elif item.id == "charged_jump":
				item.name = "Charged suspension jump"
				item.desc = "Hold Space while grounded to charge, then release to jump. Longer holds launch harder. Costs battery and has a short cooldown."
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
