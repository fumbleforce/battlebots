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
	{"id":"training","big":"SOLO","tag":"PRACTICE","title":"PRACTICE","desc":"Test your build in the arena against a stationary target.","meta1":"Solo","meta2":"No rewards","tint":Color("#2F5A36"),"rules":"Solo practice · Stationary target · No rating or rewards","enabled":true},
	{"id":"duel","big":"1V1","tag":"PRIVATE","title":"PRIVATE DUEL","desc":"Host a private duel for two players.","meta1":"First to 2","meta2":"2 players","tint":Color("#8A2520"),"rules":"1v1 · First to two rounds · Five-round cap","enabled":true},
	{"id":"team","big":"2V2","tag":"STANDARD","title":"TEAM BRAWL","desc":"Coordinate with a teammate in a private match.","meta1":"First to 2","meta2":"4 players","tint":Color("#1F4A9A"),"rules":"2v2 · First to two rounds · Five-round cap · No arena hazards","enabled":true},
	{"id":"quick","big":"GO","tag":"UNAVAILABLE","title":"QUICK MATCH","desc":"Public matchmaking is not implemented.","meta1":"Unavailable","meta2":"Planned","tint":Color("#3A4452"),"rules":"Public services unavailable","enabled":false},
	{"id":"ranked","big":"1V1","tag":"DEFERRED","title":"RANKED DUEL","desc":"Ranked play is deferred.","meta1":"Unavailable","meta2":"Deferred","tint":Color("#3A4452"),"rules":"Ranked play unavailable","enabled":false},
	{"id":"5v5","big":"5V5","tag":"PLAYTEST","title":"LARGE TEAMS","desc":"Two teams of five in a private match.","meta1":"First to 2","meta2":"10 players","tint":Color("#3A4452"),"rules":"5v5 · Four-minute rounds · First to two · Five-round cap","enabled":true},
	{"id":"ffa","big":"FFA","tag":"PLAYTEST","title":"FREE FOR ALL","desc":"Every bot for itself. Start with 4–8 players.","meta1":"One round","meta2":"4–8 players","tint":Color("#3A4452"),"rules":"Free-for-all · One five-minute round · No overtime","enabled":true},
]
const ARENAS := [{"name":"THE FOUNDRY","sub":"50 × 50 metres · No hazards","size":"50 × 50 m ARENA","image":preload("res://ui/menus/art/arena_foundry.jpg"),"hazards":["Flat arena with perimeter walls","No active arena hazards","Concept art; playable arena is a graybox"],"enabled":true}]

static func catalogue(registry: ContentRegistry) -> Dictionary:
	var categories: Array = []
	for slot: String in ContentRegistry.SLOTS:
		var items: Array = []
		for id: String in registry.parts:
			var part: Dictionary = registry.parts[id]
			if part.category == slot:
				items.append({"id":id,"name":id.capitalize(),"default":"own","desc":"%s · %.0f kg · %.0f installed power. All functional parts are available." % [id.capitalize(),part.mass,part.power],"d":{}})
		categories.append({"label":slot.to_upper(),"slot":slot,"items":items})
	var paints: Array = []
	var colors := {"cyan":"#29cce5","orange":"#ef922a","white":"#eeeeee","red":"#d93c39"}
	for id: String in colors:
		paints.append({"id":id,"name":id.capitalize(),"default":"own","swatch":colors[id],"desc":"Canonical bot paint; no effect on performance."})
	return {"parts":categories,"paint":[{"label":"PAINT","slot":"paint","items":paints}],"decals":[{"label":"DECALS","slot":"unavailable","items":[{"id":"unavailable","name":"Not available","default":"lock","desc":"Decals are not supported by the current loadout format."}]}]}

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
