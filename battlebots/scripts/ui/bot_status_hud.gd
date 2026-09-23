class_name BotStatusHud
extends PanelContainer
## Read-only presentation of the shared BotView contract.

@onready var context_label: Label = $Margin/Content/Context
@onready var state_label: Label = $Margin/Content/State
@onready var rows: VBoxContainer = $Margin/Content/Resources
const NORMAL := Color(0.85, 0.92, 0.96)
const WARNING := Color(1.0, 0.7, 0.3)

func set_context(text: String) -> void:
	context_label.text = text

func show_view(view: BotView) -> void:
	if view == null:
		for row: HBoxContainer in rows.get_children():
			_set_fraction(row, NAN)
		state_label.text = "TARGET UNAVAILABLE"
		state_label.modulate = NORMAL
		return
	_set_fraction(rows.get_node("Core"), view.core_fraction)
	_set_fraction(rows.get_node("Heat"), view.heat_fraction)
	_set_fraction(rows.get_node("Charge"), view.weapon_charge_fraction)
	var weapon := String(view.weapon_state).strip_edges().to_upper().substr(0, 24)
	if weapon.is_empty():
		weapon = "UNKNOWN"
	if view.eliminated:
		state_label.text = "ELIMINATED"
	elif is_finite(view.core_fraction) and view.core_fraction <= 0.25:
		state_label.text = "LOW CORE  /  WEAPON: " + weapon
	elif view.overheated:
		state_label.text = "OVERHEATED / COOL TO 50%"
	elif is_finite(view.heat_fraction) and view.heat_fraction >= 0.9:
		state_label.text = "HIGH HEAT  /  WEAPON: " + weapon
	else:
		state_label.text = "WEAPON: " + weapon
	state_label.modulate = WARNING if view.eliminated or view.overheated \
		or (is_finite(view.core_fraction) and view.core_fraction <= 0.25) \
		or (is_finite(view.heat_fraction) and view.heat_fraction >= 0.9) else NORMAL

func _set_fraction(row: HBoxContainer, fraction: float) -> void:
	var bar: ProgressBar = row.get_node("Bar")
	var value_label: Label = row.get_node("Value")
	var valid := is_finite(fraction)
	var value := clampf(fraction, 0.0, 1.0) * 100.0 if valid else 0.0
	bar.value = value
	value_label.text = "%d%%" % roundi(value) if valid else "--"
