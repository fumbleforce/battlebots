class_name NetworkDiagnosticsPanel
extends PanelContainer
## Read-only presentation: values are supplied by the local session adapter.

signal interaction_started

@onready var title_label: Label = $Margin/Content/Title
@onready var summary_label: Label = $Margin/Content/Summary
@onready var details_label: Label = $Margin/Content/Details
@onready var details_button: Button = $Margin/Content/DetailsButton

var expanded: bool = false:
	set(value):
		expanded = value
		if is_node_ready():
			_refresh_expanded()

func _ready() -> void:
	details_button.button_down.connect(func() -> void: interaction_started.emit())
	details_button.pressed.connect(func() -> void: expanded = not expanded)
	_refresh_expanded()
	show_diagnostics("offline", {})

func _refresh_expanded() -> void:
	details_label.visible = expanded
	details_button.text = "Hide details" if expanded else "Details"

func show_diagnostics(state: String, diagnostics: Dictionary, context: Dictionary = {}) -> void:
	var phase := _safe_text(context.get("phase"))
	var has_match_metrics := phase.to_lower() in ["active", "overtime"]
	var lines: PackedStringArray = []
	title_label.modulate = Color(0.72, 0.86, 0.94)
	match state:
		"connected":
			var degraded: Variant = diagnostics.get("degraded")
			var is_degraded: bool = has_match_metrics and typeof(degraded) == TYPE_BOOL and degraded == true
			title_label.text = "CONNECTION DEGRADED" if is_degraded else "CONNECTED"
			if is_degraded:
				title_label.modulate = Color(1.0, 0.71, 0.35)
			summary_label.text = "Last RTT %s ms" % _metric(diagnostics, "rtt_ms", 1) if has_match_metrics else "Waiting for match data"
			if is_degraded:
				summary_label.text += "\nRemote motion may pause."
			if has_match_metrics:
				lines.append("Last correction: %s m" % _metric(diagnostics, "correction_m", 3))
				lines.append("Interpolation: %s ms" % _metric(diagnostics, "interpolation_ms", 1))
				lines.append("Snapshots received: %s" % _metric(diagnostics, "snapshots_received", 0))
				lines.append("Counters: since session node creation.")
			else:
				lines.append("Network metrics unavailable outside active play.")
		"hosting":
			title_label.text = "HOSTING"
			summary_label.text = "Local server authority"
			lines.append("Rejected inputs: %s" % _metric(diagnostics, "rejected_inputs", 0))
			lines.append("Largest snapshot packet: %s B" % _metric(diagnostics, "snapshot_bytes", 0))
			lines.append("Counts / maximum: since session node creation.")
		"practice":
			title_label.text = "PRACTICE"
			summary_label.text = "Local play • no network metrics"
		"connecting":
			title_label.text = "CONNECTING"
			summary_label.text = "Waiting for session connection…"
		"offline":
			title_label.text = "OFFLINE"
			summary_label.text = "No active network session"
		_:
			title_label.text = "CONNECTION UNKNOWN"
			summary_label.text = "Network metrics unavailable"
	lines.append("Build: %s" % _safe_text(context.get("build")))
	lines.append("Mode: %s • Phase: %s" % [_safe_text(context.get("mode")), phase])
	lines.append("Local physics: %s ms" % _metric(context, "physics_ms", 2))
	details_label.text = "\n".join(lines)

static func _metric(values: Dictionary, key: String, decimals: int) -> String:
	var value: Variant = values.get(key)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return "--"
	var number := float(value)
	if not is_finite(number) or number < 0:
		return "--"
	# Keep unusually large valid values readable without growing the panel.
	if number >= 1000000000.0:
		return ">=1 billion"
	return ("%." + str(decimals) + "f") % number

static func _safe_text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return "--"
	var result := String(value).replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if result.is_empty():
		return "--"
	return result.left(31) + "…" if result.length() > 32 else result
