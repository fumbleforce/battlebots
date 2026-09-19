class_name LobbyPanel
extends Control
## Read-only presentation of an authoritative lobby. All edits are requests.
signal host_requested(port: int, player_count: int)
signal join_requested(address: String, port: int)
signal leave_requested
signal ready_requested(value: bool)
signal team_requested(team: int)
signal loadout_requested(draft: Dictionary)
signal return_requested
signal resume_requested
signal settings_requested
signal practice_requested

var host_button: Button
var join_button: Button
var leave_button: Button
var ready_button: Button
var resume_button: Button
var address: LineEdit
var port: SpinBox
var capacity: OptionButton
var team_choice: OptionButton
var loadout_choice: OptionButton
var status_label: Label
var notice_label: Label
var roster_labels: Array[Label] = []
var _practice_button: Button
var _setup: VBoxContainer
var _online: VBoxContainer
var _details: Label
var _registry := ContentRegistry.new()
var _ready_value := false
var _team_value := -1
var _loadout_value := -1
var _state := "offline"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("101821")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 24)
	add_child(margins)
	var center := CenterContainer.new()
	margins.add_child(center)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 640)
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	var title := _label(body, "BATTLEBOTS  /  READY ROOM")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("ffcb76"))
	status_label = _label(body, "Offline")
	_details = _label(body, "")
	notice_label = _label(body, "")
	notice_label.add_theme_color_override("font_color", Color("ffcb76"))
	_setup = VBoxContainer.new()
	body.add_child(_setup)
	_label(_setup, "HOST A MATCH")
	var setup_row := HBoxContainer.new()
	_setup.add_child(setup_row)
	_label(setup_row, "UDP port")
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 24567
	setup_row.add_child(port)
	capacity = OptionButton.new()
	capacity.add_item("2v2 · 4 players", 4)
	capacity.add_item("1v1 · 2 players", 2)
	setup_row.add_child(capacity)
	_practice_button = _button(_setup, "Practice", func() -> void: practice_requested.emit())
	host_button = _button(setup_row, "Host", func() -> void: host_requested.emit(int(port.value), capacity.get_selected_id()))
	_label(_setup, "JOIN YOUR OFFICE HOST")
	var join_row := HBoxContainer.new()
	_setup.add_child(join_row)
	address = LineEdit.new()
	address.placeholder_text = "Host IP, for example 192.168.1.20"
	address.max_length = 253
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(address)
	join_button = _button(join_row, "Join", func() -> void: join_requested.emit(address.text.strip_edges(), int(port.value)))
	_online = VBoxContainer.new()
	_online.add_theme_constant_override("separation", 8)
	body.add_child(_online)
	for index: int in range(4):
		var row := _label(_online, "Open slot")
		row.custom_minimum_size.y = 55
		roster_labels.append(row)
	var edits := HBoxContainer.new()
	_online.add_child(edits)
	team_choice = OptionButton.new()
	team_choice.add_item("Team A", 0)
	team_choice.add_item("Team B", 1)
	edits.add_child(team_choice)
	team_choice.item_selected.connect(func(index: int) -> void:
		team_requested.emit(team_choice.get_item_id(index))
		team_choice.select(_team_value))
	loadout_choice = OptionButton.new()
	loadout_choice.add_item("Striker", 0)
	loadout_choice.add_item("Controller", 1)
	loadout_choice.add_item("Custom build", 2)
	loadout_choice.set_item_disabled(2, true)
	edits.add_child(loadout_choice)
	loadout_choice.item_selected.connect(func(index: int) -> void:
		loadout_requested.emit(_registry.starter(index == 1))
		loadout_choice.select(_loadout_value))
	ready_button = _button(edits, "Ready", func() -> void: ready_requested.emit(not _ready_value))
	var actions := HBoxContainer.new()
	body.add_child(actions)
	resume_button = _button(actions, "Resume", func() -> void: resume_requested.emit())
	leave_button = _button(actions, "Leave lobby", func() -> void: leave_requested.emit())
	_button(actions, "Settings", func() -> void: settings_requested.emit())
	_button(actions, "Main menu", func() -> void: return_requested.emit())
	render("offline", {}, -1)

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110, 38)
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func render(state: String, view: Dictionary, local_entity: int, context: Dictionary = {}) -> void:
	_state = state
	var offline := state == "offline"
	var connecting := state == "connecting"
	_setup.visible = offline
	_online.visible = not offline and not connecting
	host_button.disabled = not offline
	_practice_button.disabled = not offline
	join_button.disabled = not offline
	leave_button.visible = not offline
	leave_button.text = "Cancel connection" if connecting else "Leave session"
	resume_button.visible = context.get("can_resume") == true
	resume_button.disabled = not resume_button.visible
	notice_label.text = _plain(context.get("notice", ""), 240)
	_details.text = _plain(context.get("endpoint", ""), 180)
	var build := _plain(context.get("build", ""), 40)
	if not build.is_empty():
		_details.text += "  •  Build " + build
	var rtt: Variant = context.get("local_rtt")
	if (rtt is int or rtt is float) and is_finite(float(rtt)) and float(rtt) >= 0.0:
		_details.text += "  •  Your RTT %.0f ms" % float(rtt)
	var valid := _valid_view(view)
	var phase := str(view.get("phase", "unknown")) if valid else "unknown"
	status_label.text = "Offline · host or join a match" if offline else ("Connecting to host…" if connecting else ("%s · %s" % [view.mode, phase] if valid else "Lobby data unavailable · waiting for host"))
	_ready_value = false
	_team_value = -1
	_loadout_value = -1
	var local: Dictionary = {}
	for row: Label in roster_labels:
		row.text = "Lobby data unavailable"
		row.visible = false
	if valid:
		var row_index := 0
		for team: int in range(2):
			var occupants: Array = []
			for slot: Dictionary in view.slots:
				if slot.team == team:
					occupants.append(slot)
			for position: int in range(int(view.capacity) / 2):
				var row := roster_labels[row_index]
				row_index += 1
				row.visible = true
				var heading := "Team %s · Slot %d" % ["A" if team == 0 else "B", position + 1]
				if position >= occupants.size():
					row.text = heading + "  /  OPEN"
					continue
				var slot: Dictionary = occupants[position]
				if slot.entity_id == local_entity:
					local = slot
				var validation := _registry.validate(slot.loadout)
				var parts: Dictionary = slot.loadout.get("parts", {}) if slot.loadout.get("parts") is Dictionary else {}
				row.text = heading + ("  /  YOU" if slot.entity_id == local_entity else "  /  Bot %d" % slot.entity_id)
				row.text += "  •  " + ("Connected" if slot.connected else "Disconnected") + "  •  " + ("Ready" if slot.ready else "Not ready")
				row.text += "\n%s · %s / %s · %s" % [_plain(slot.loadout.get("name", "Unnamed"), 48), _plain(parts.get("chassis", "Unknown chassis"), 40), _plain(parts.get("weapon", "Unknown weapon"), 40), "Valid build" if validation.valid else "Invalid build"]
	var editable: bool = state in ["hosting", "connected"] and valid and phase == "lobby" and not local.is_empty() and local.get("connected") == true and context.get("pending") != true
	ready_button.disabled = not editable
	team_choice.disabled = not editable
	loadout_choice.disabled = not editable
	if not local.is_empty():
		_ready_value = local.ready
		_team_value = local.team
		for index: int in range(2):
			if _same_build(local.loadout, _registry.starter(index == 1)):
				_loadout_value = index
		if _loadout_value == -1 and _registry.validate(local.loadout).valid:
			_loadout_value = 2
		ready_button.disabled = ready_button.disabled or not _registry.validate(local.loadout).valid
	ready_button.text = "Unready" if _ready_value else "Ready"
	team_choice.select(_team_value)
	loadout_choice.select(_loadout_value)

func _same_build(actual: Dictionary, starter: Dictionary) -> bool:
	# JSON carries schema numbers as floats; compare validated semantic fields.
	if not _registry.validate(actual).valid:
		return false
	for field: String in ["name", "content_hash", "parts", "cosmetics"]:
		if actual.get(field) != starter.get(field):
			return false
	return true

func _valid_view(view: Dictionary) -> bool:
	if not view.get("capacity") is int or view.get("capacity") not in [2, 4] or view.get("mode") not in ["1v1", "2v2"] or not view.get("phase") is String or not view.get("slots") is Array:
		return false
	if view.slots.size() > view.capacity:
		return false
	var seen: Array = []
	var counts := [0, 0]
	for slot: Variant in view.slots:
		if not slot is Dictionary or not slot.get("entity_id") is int or slot.entity_id <= 0 or seen.has(slot.entity_id) or not slot.get("team") is int or slot.get("team") not in [0, 1] or not slot.get("ready") is bool or not slot.get("connected") is bool or not slot.get("loadout") is Dictionary:
			return false
		seen.append(slot.entity_id)
		counts[int(slot.team)] += 1
	return counts[0] <= int(view.capacity) / 2 and counts[1] <= int(view.capacity) / 2

func _plain(value: Variant, limit: int) -> String:
	return str(value).replace("\n", " ").replace("\r", " ").replace("\t", " ").left(limit)

func focus_default() -> void:
	if _state == "offline":
		host_button.grab_focus()
	elif _state == "connecting":
		leave_button.grab_focus()
	elif resume_button.visible:
		resume_button.grab_focus()
	elif not ready_button.disabled:
		ready_button.grab_focus()
	else:
		leave_button.grab_focus()
