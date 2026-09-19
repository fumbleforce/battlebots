extends Control
## Synthetic values for visual/keyboard inspection; never creates a network peer.
@onready var selector: OptionButton = $Margin/Content/Scenario
@onready var explanation: Label = $Margin/Content/Explanation
@onready var panel: NetworkDiagnosticsPanel = $NetworkDiagnostics
const SCENARIOS := ["Connected client", "Degraded snapshots", "Waiting for fresh data",
	"Listen host", "Connecting", "Practice", "Offline after a match", "Malformed metrics"]

func _ready() -> void:
	for title: String in SCENARIOS:
		selector.add_item(title)
	selector.item_selected.connect(show_scenario)
	panel.expanded = true
	show_scenario(0)
	selector.grab_focus()

func show_scenario(index: int) -> void:
	var state := "connected"
	var phase := "active"
	var data := {"rtt_ms": 82.0, "correction_m": 0.12, "interpolation_ms": 100.0,
		"snapshots_received": 420, "degraded": false, "snapshot_bytes": 812, "rejected_inputs": 3}
	match index:
		1:
			data.degraded = true
			data.rtt_ms = 151.0
			data.correction_m = 0.65
			data.interpolation_ms = 150.0
		2:
			data.clear()
		3:
			state = "hosting"
		4:
			state = "connecting"
		5:
			state = "practice"
		6:
			state = "offline"
		7:
			data = {"rtt_ms": NAN, "correction_m": -4, "interpolation_ms": "unknown",
				"snapshots_received": INF, "degraded": "true"}
	selector.select(index)
	panel.show_diagnostics(state, data, {"build": WireCodec.BUILD, "mode": "2v2",
		"phase": phase, "physics_ms": 2.4})
	explanation.text = "Scenario: %s\n\nAll numbers here are synthetic.\nUse this scene to inspect labels, unavailable data,\nkeyboard focus and expanded/collapsed layout.\n\nThe live preview reads A's session directly.\nThis fixture does not connect, send commands,\nor claim LAN performance acceptance." % SCENARIOS[index]
