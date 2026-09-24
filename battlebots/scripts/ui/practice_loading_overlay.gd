class_name PracticeLoadingOverlay
extends CanvasLayer
## Full-screen loading card for starting Practice (#70). MenuGame shows it,
## lets it draw, builds the arena and bots behind it, and lifts it only after
## the first gameplay frames have drawn, so the build and the first-use shader
## setup never show as a frozen menu. Presentation only.
const ARENA_IDS := ["foundry", "moon", "woodland"]
const TIP := "[color=#F5B82E][b]TIP[/b][/color]  Hold SPACE to charge a jump, release to launch. Hold SHIFT for Nitro. Practice bots respawn; so do you."
## Seconds the card takes to fade once the arena has drawn.
const FADE_SECONDS := 0.25
var art: TextureRect
var arena_label: Label
var status_label: Label
var _fade: Tween

func _init() -> void:
	name = "PracticeLoading"
	layer = 20
	visible = false
	var root := Control.new()
	root.name = "Card"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var background := ColorRect.new()
	background.color = MenuData.INK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	art = TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(1, 1, 1, 0.55)
	root.add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(MenuData.INK, 0.85)
	shade.anchor_top = 0.62
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	root.add_child(shade)
	var column := VBoxContainer.new()
	column.anchor_left = 0.06
	column.anchor_top = 0.66
	column.anchor_right = 0.94
	column.anchor_bottom = 0.95
	column.add_theme_constant_override("separation", 10)
	root.add_child(column)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.add_theme_font_size_override("font_size", 26)
	status_label.add_theme_color_override("font_color", MenuData.AMBER)
	column.add_child(status_label)
	arena_label = Label.new()
	arena_label.name = "Arena"
	arena_label.add_theme_font_size_override("font_size", 72)
	arena_label.add_theme_color_override("font_color", MenuData.TEXT)
	column.add_child(arena_label)
	var tip := RichTextLabel.new()
	tip.bbcode_enabled = true
	tip.fit_content = true
	tip.scroll_active = false
	tip.add_theme_font_size_override("normal_font_size", 24)
	tip.add_theme_font_size_override("bold_font_size", 24)
	tip.add_theme_color_override("default_color", MenuData.TEXT2)
	tip.text = TIP
	column.add_child(tip)

## Shows the card for arena_id at full opacity.
func present(arena_id: String) -> void:
	if _fade != null: _fade.kill()
	var index := maxi(0, ARENA_IDS.find(arena_id))
	var arena: Dictionary = MenuData.ARENAS[index]
	art.texture = arena.get("image")
	arena_label.text = arena.name
	status_label.text = "LOADING PRACTICE"
	(get_node("Card") as Control).modulate.a = 1.0
	visible = true

## Fades the card out; instant when the tree is not processing tweens.
func lift() -> void:
	if not visible: return
	if _fade != null: _fade.kill()
	_fade = create_tween()
	_fade.tween_property(get_node("Card"), "modulate:a", 0.0, FADE_SECONDS)
	_fade.tween_callback(hide)
